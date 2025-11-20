// lib/hop_booking_info_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'services/email_notification_service.dart';
import 'package:intl/intl.dart';

class HopBookingInfoPage extends StatefulWidget {
  const HopBookingInfoPage({super.key});

  @override
  State<HopBookingInfoPage> createState() => _HopBookingInfoPageState();
}

class _HopBookingInfoPageState extends State<HopBookingInfoPage> {
  bool _argsParsed = false;
  String? _appointmentId;

  String _fbName = '—';
  String _fbFaculty = '—';
  String _fbEmail = '—';
  int _fbSessions = 0;
  List<String> _fbSpecializes = const <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsParsed) return;
    _argsParsed = true;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    _appointmentId = (args['appointmentId'] as String?);

    _fbName = (args['name'] as String?) ?? _fbName;
    _fbFaculty = (args['faculty'] as String?) ?? _fbFaculty;
    _fbEmail = (args['email'] as String?) ?? _fbEmail;
    _fbSessions = (args['sessions'] as int?) ?? _fbSessions;
    _fbSpecializes =
        (args['specializes'] as List?)?.map((e) => e.toString()).toList() ??
            _fbSpecializes;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'missed':
        return 'Missed';
      case 'pending_reschedule_hop':
        return 'Reschedule Pending';
      case 'pending_reschedule_peer':
        return 'Confirm Reschedule?';
      default:
        return 'Pending';
    }
  }

  (Color bg, Color fg) _statusColors(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'completed':
        return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'cancelled':
        return (const Color(0xFFFFE0E0), const Color(0xFFD32F2F));
      case 'missed':
        return (const Color(0xFFFFF3E0), const Color(0xFFEF6C00));
      case 'pending_reschedule_hop':
      case 'pending_reschedule_peer':
        return (const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      default:
        return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  Future<void> _updateStatus(String id, String status, {String? cancellationReason}) async {
    final updateData = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonHop': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      if (cancellationReason != null) 'cancellationReason': cancellationReason,
      if (cancellationReason != null) 'cancelledBy': 'hop',
    };
    await FirebaseFirestore.instance.collection('appointments').doc(id).set(
      updateData,
      SetOptions(merge: true),
    );
  }

  Future<String?> _getReason(BuildContext context, String action) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action Reason'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: 'Enter reason (Max 20 characters)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, null),
              child: const Text('Close')),
          FilledButton(
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty || reason.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A reason (max 20 characters) is required.')),
                );
                return;
              }
              Navigator.pop(dialogContext, reason);
            },
            child: Text('Confirm $action'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<bool> _hasOverlap({
    required String helperId,
    required DateTime startDt,
    required DateTime endDt,
    String? excludeId,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .limit(500)
        .get();

    for (final d in snap.docs) {
      if (excludeId != null && d.id == excludeId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase().trim();
      if (status != 'pending' && status != 'confirmed' && !status.startsWith('pending_reschedule')) continue;

      final tsStart = m['startAt'];
      final tsEnd = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;
      final existingStart = tsStart.toDate();
      final existingEnd = tsEnd.toDate();
      final overlaps =
          existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }

  Future<void> _reschedule(
      BuildContext context, String apptId, Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();
    final origStart = (m['startAt'] as Timestamp).toDate();
    final origEnd = (m['endAt'] as Timestamp).toDate();
    final status = (m['status'] ?? '').toString().toLowerCase().trim();

    // CONDITION 1: If <= 24h, cannot reschedule
    final hoursUntil = origStart.difference(DateTime.now()).inHours;
    if (hoursUntil <= 24) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours (Condition 1).')),
        );
      }
      return;
    }

    // CONDITION 2: Can only reschedule if confirmed
    if (status != 'confirmed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Can only reschedule after confirmation (Condition 2).')),
        );
      }
      return;
    }

    DateTime date = DateTime(origStart.year, origStart.month, origStart.day);
    TimeOfDay startTod = TimeOfDay.fromDateTime(origStart);
    TimeOfDay endTod = TimeOfDay.fromDateTime(origEnd);

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now().add(const Duration(hours: 24)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) setState(() => date = picked);
    }

    Future<void> pickTime(bool isStart) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: isStart ? startTod : endTod,
      );
      if (picked != null) {
        setState(() {
          if (isStart) {
            startTod = picked;
          } else {
            endTod = picked;
          }
        });
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          return AlertDialog(
            title: const Text('Propose Reschedule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Date'),
                  subtitle: Text(_fmtDate(date)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () async {
                      await pickDate();
                      setStateDlg(() {});
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('Start'),
                        subtitle: Text(_fmtTime(startTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async {
                            await pickTime(true);
                            setStateDlg(() {});
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('End'),
                        subtitle: Text(_fmtTime(endTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async {
                            await pickTime(false);
                            setStateDlg(() {});
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Close')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Next')),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final startDt = DateTime(
        date.year, date.month, date.day, startTod.hour, startTod.minute);
    final endDt =
    DateTime(date.year, date.month, date.day, endTod.hour, endTod.minute);

    if (!startDt.isAfter(DateTime.now().add(const Duration(hours: 24)))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('New time must be at least 24 hours from now.')),
        );
      }
      return;
    }
    if (!endDt.isAfter(startDt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End time must be after start.')));
      }
      return;
    }
    if (await _hasOverlap(
        helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conflicts with another booking.')));
      }
      return;
    }

    // Get reason
    final reason = await _getReason(context, 'Reschedule');
    if (reason == null || !mounted) return;

    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(apptId)
        .set({
      'status': 'pending_reschedule_hop',
      'proposedStartAt': Timestamp.fromDate(startDt),
      'proposedEndAt': Timestamp.fromDate(endDt),
      'rescheduleReasonHop': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'rescheduleReasonPeer': FieldValue.delete(),
    }, SetOptions(merge: true));

    // Send email notification to peer about reschedule request
    debugPrint("🔔 Attempting to send reschedule email to peer");
    try {
      final apptDoc = await FirebaseFirestore.instance.collection('appointments').doc(apptId).get();
      final apptData = apptDoc.data();

      if (apptData != null) {
        final helperId = apptData['helperId'] ?? '';
        final helperDoc = await FirebaseFirestore.instance.collection('users').doc(helperId).get();
        final helperData = helperDoc.data();

        final hopDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .get();
        final hopData = hopDoc.data();

        if (helperData != null && hopData != null) {
          final helperEmail = helperData['email'] ?? '';
          final helperName = helperData['fullName'] ?? helperData['name'] ?? 'Peer';
          final hopName = hopData['fullName'] ?? hopData['name'] ?? 'HOP';

          if (helperEmail.isNotEmpty) {
            await EmailNotificationService.sendRescheduleRequestToPeer(
              peerEmail: helperEmail,
              peerName: helperName,
              studentName: hopName,
              studentRole: 'Head of Programme',
              originalDate: _fmtDate(origStart),
              originalTime: '${_fmtTime(TimeOfDay.fromDateTime(origStart))} - ${_fmtTime(TimeOfDay.fromDateTime(origEnd))}',
              newDate: _fmtDate(startDt),
              newTime: '${_fmtTime(TimeOfDay.fromDateTime(startDt))} - ${_fmtTime(TimeOfDay.fromDateTime(endDt))}',
              reason: reason,
            );
          }
        }
      }
    } catch (emailError) {
      debugPrint('Failed to send reschedule email: $emailError');
      // Don't fail the reschedule if email fails
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reschedule proposed. Waiting for peer confirmation.')));
    }
  }

  Future<void> _acceptPeerReschedule(String apptId, Map<String, dynamic> m) async {
    final propStart = m['proposedStartAt'] as Timestamp?;
    final propEnd = m['proposedEndAt'] as Timestamp?;

    if (propStart == null || propEnd == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule data incomplete.')),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('appointments').doc(apptId).set({
      'status': 'confirmed',
      'startAt': propStart,
      'endAt': propEnd,
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonHop': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Send email notification to peer about reschedule confirmation
    try {
      final apptDoc = await FirebaseFirestore.instance.collection('appointments').doc(apptId).get();
      final apptData = apptDoc.data();

      if (apptData != null) {
        final helperId = apptData['helperId'] ?? '';
        final helperDoc = await FirebaseFirestore.instance.collection('users').doc(helperId).get();
        final helperData = helperDoc.data();

        final hopDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid)
            .get();
        final hopData = hopDoc.data();

        if (helperData != null && hopData != null) {
          final helperEmail = helperData['email'] ?? '';
          final helperName = helperData['fullName'] ?? helperData['name'] ?? 'Peer';
          final hopName = hopData['fullName'] ?? hopData['name'] ?? 'HOP';

          if (helperEmail.isNotEmpty) {
            await EmailNotificationService.sendAppointmentConfirmedToPeer(
              peerEmail: helperEmail,
              peerName: helperName,
              studentName: hopName,
              studentRole: 'Head of Programme',
              appointmentDate: _fmtDate(propStart.toDate()),
              appointmentTime: '${_fmtTime(TimeOfDay.fromDateTime(propStart.toDate()))} - ${_fmtTime(TimeOfDay.fromDateTime(propEnd.toDate()))}',
            );
          }
        }
      }
    } catch (emailError) {
      debugPrint('Failed to send confirmation email: $emailError');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reschedule accepted.')),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reschedule accepted.')),
      );
    }
  }

  Future<void> _cancelExisting(String appointmentId, DateTime startAt, String status) async {
    // HOP can cancel pending or confirmed appointments with reason
    final canCancel = status == 'pending' || status == 'confirmed';

    if (!canCancel) {
      _msg('Cannot cancel this appointment.');
      return;
    }

    // Get reason
    final reason = await _getReason(context, 'Cancel');
    if (reason == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await _updateStatus(appointmentId, 'cancelled', cancellationReason: reason);

        // Send email notification to peer about cancellation
        try {
          final doc = await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).get();
          final m = doc.data();
          final helperId = m?['helperId'] ?? m?['tutorId'];
          if (helperId != null) {
            final helper = await FirebaseFirestore.instance.collection('users').doc(helperId).get();
            final hop = await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).get();

            await EmailNotificationService.sendCancellationToPeer(
              peerEmail: helper.data()?['email'] ?? '',
              peerName: helper.data()?['fullName'] ?? 'Peer',
              studentName: hop.data()?['fullName'] ?? 'HOP',
              studentRole: 'Head of Programme',
              appointmentDate: _fmtDate(startAt),
              appointmentTime: 'See details in app', // Simplification or fetch end time
              reason: reason,
            );
          }
        } catch (e) { debugPrint('Email error: $e'); }

        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
        Navigator.maybePop(context);
      } catch (e) {
        if (!mounted) return;
        _msg('Cancel failed: $e');
      }
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    if (_appointmentId == null || _appointmentId!.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Missing appointmentId.\nOpen from Scheduling → tap a task.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('appointments')
                .doc(_appointmentId)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (!snap.hasData || !snap.data!.exists) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _HopHeader(),
                    const SizedBox(height: 16),
                    Text('Booking Info',
                        style:
                        t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Text('Appointment not found.'),
                    ),
                  ],
                );
              }

              final m = snap.data!.data()!;
              final start = ((m['startAt'] ?? m['start']) as Timestamp?)?.toDate();
              final end = ((m['endAt'] ?? m['end']) as Timestamp?)?.toDate();              final loc = (m['location'] ?? '').toString();
              final notes = (m['notes'] ?? '').toString();
              final statusRaw = (m['status'] ?? 'pending').toString();
              final helperIdFromDoc = (m['helperId'] ?? '').toString().trim();

              final statusLbl = _statusLabel(statusRaw);
              final (chipBg, chipFg) = _statusColors(statusRaw);

              final cancellationReason = (m['cancellationReason'] ?? '').toString().trim();
              final rescheduleReasonHop = (m['rescheduleReasonHop'] ?? '').toString().trim();
              final rescheduleReasonPeer = (m['rescheduleReasonPeer'] ?? '').toString().trim();

              final now = DateTime.now();
              final hasStart = start != null;
              final hoursUntil = hasStart ? start!.difference(now).inHours : 0;
              final isWithin24Hours = hoursUntil <= 24;
              final isPending = statusRaw == 'pending';
              final isConfirmed = statusRaw == 'confirmed';
              final isPendingReschedulePeer = statusRaw == 'pending_reschedule_peer';
              final isTerminal = statusRaw == 'cancelled' || statusRaw == 'completed' || statusRaw == 'missed';

              // HOP BUSINESS LOGIC (Conditions 1, 2, 3)
              bool canCancel = false;
              bool canReschedule = false;
              bool showAcceptReschedule = false;

              if (hasStart && !isTerminal && start!.isAfter(now)) {
                if (isPending) {
                  // CONDITION 1 & 2: Pending - can cancel with reason
                  canCancel = false;
                } else if (isConfirmed) {
                  if (isWithin24Hours) {
                    // CONDITION 1: <= 24h, confirmed - can only cancel
                    canCancel = false;
                  } else {
                    // CONDITION 2: > 24h, confirmed - can reschedule and cancel
                    canCancel = true;
                    canReschedule = true;
                  }
                } else if (isPendingReschedulePeer) {
                  // Peer proposed reschedule
                  showAcceptReschedule = true;
                  canCancel = true;
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HopHeader(),
                  const SizedBox(height: 16),

                  Text('Booking Info',
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Appointment details', style: t.bodySmall),
                  const SizedBox(height: 12),

                  Stack(
                    children: [
                      _HelperHeader(
                        helperId: helperIdFromDoc,
                        fallbackName: _fbName,
                        fallbackFaculty: _fbFaculty,
                        fallbackEmail: _fbEmail,
                        fallbackSessions: _fbSessions,
                        fallbackPhotoUrl: '',
                        specializes: _fbSpecializes,
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: _Chip(label: statusLbl, bg: chipBg, fg: chipFg),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Display reasons
                  if (rescheduleReasonHop.isNotEmpty) ...[
                    _ReasonContainer(
                      label: 'HOP Reschedule Reason',
                      reason: rescheduleReasonHop,
                      isReschedule: true,
                    ),
                    const SizedBox(height: 12),
                  ] else if (rescheduleReasonPeer.isNotEmpty) ...[
                    _ReasonContainer(
                      label: 'Peer Reschedule Reason',
                      reason: rescheduleReasonPeer,
                      isReschedule: true,
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (statusRaw == 'cancelled' && cancellationReason.isNotEmpty) ...[
                    _ReasonContainer(
                      label: 'Cancellation Reason',
                      reason: cancellationReason,
                      isAlert: true,
                    ),
                    const SizedBox(height: 12),
                  ],

                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (start != null) ? _fmtDate(start) : '—',
                            style: t.bodyMedium,
                          ),
                        ),
                        const Icon(Icons.calendar_month_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (start != null && end != null)
                                ? '${_fmtTime(TimeOfDay.fromDateTime(start))}  to  ${_fmtTime(TimeOfDay.fromDateTime(end))}'
                                : '—',
                            style: t.bodyMedium,
                          ),
                        ),
                        const Icon(Icons.timer_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(
                            child:
                            Text(loc.isEmpty ? '—' : loc, style: t.bodyMedium)),
                        const Icon(Icons.place_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: SingleChildScrollView(
                      primary: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(notes.isEmpty ? '—' : notes, softWrap: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.maybePop(context),
                          child: const Text('Back')),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (showAcceptReschedule)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32)),
                              onPressed: () => _acceptPeerReschedule(_appointmentId!, m),
                              child: const Text('Accept Reschedule'),
                            ),
                          if (start != null && canReschedule)
                            FilledButton.tonal(
                              onPressed: () =>
                                  _reschedule(context, _appointmentId!, m),
                              child: const Text('Reschedule'),
                            ),
                          if (start != null && canCancel)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red),
                              onPressed: () =>
                                  _cancelExisting(_appointmentId!, start, statusRaw),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ Helper header ------------------------------ */

class _HelperHeader extends StatelessWidget {
  final String helperId;

  final String fallbackName;
  final String fallbackFaculty;
  final String fallbackEmail;
  final int fallbackSessions;
  final String fallbackPhotoUrl;
  final List<String> specializes;

  const _HelperHeader({
    required this.helperId,
    required this.fallbackName,
    required this.fallbackFaculty,
    required this.fallbackEmail,
    required this.fallbackSessions,
    required this.fallbackPhotoUrl,
    required this.specializes,
  });

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final profile = m['profile'];
    if (profile is Map<String, dynamic>) {
      for (final k in keys) {
        final v = profile[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  List<String> _extractInterestIds(Map<String, dynamic> m) {
    final out = <String>{};

    void absorb(dynamic v) {
      if (v == null) return;
      if (v is List) {
        for (final e in v) {
          if (e is String && e.trim().isNotEmpty) out.add(e.trim());
          else if (e is DocumentReference) out.add(e.id);
          else if (e is Map && e['id'] is String) {
            out.add((e['id'] as String).trim());
          }
        }
      } else if (v is Map) {
        for (final k in v.keys) {
          if (k is String && k.trim().isNotEmpty) out.add(k.trim());
        }
      } else if (v is String && v.trim().isNotEmpty) {
        out.add(v.trim());
      }
    }

    absorb(m['academicInterestIds']);
    absorb(m['interestIds']);
    absorb(m['interests']);

    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      absorb(prof['academicInterestIds']);
      absorb(prof['interestIds']);
      absorb(prof['interests']);
    }

    return out.toList();
  }

  Future<
      (String name, String facultyTitle, String email, int completedCount,
      String photoUrl, List<String> interestIds)> _load() async {
    String name = fallbackName;
    String facultyTitle = fallbackFaculty;
    String email = fallbackEmail;
    String photoUrl = fallbackPhotoUrl;
    int completedCount = fallbackSessions;
    List<String> interestIds = const <String>[];

    if (helperId.isEmpty) {
      return (name, facultyTitle, email, completedCount, photoUrl, interestIds);
    }

    final usersCol = FirebaseFirestore.instance.collection('users');
    final facCol = FirebaseFirestore.instance.collection('faculties');
    final appsCol = FirebaseFirestore.instance.collection('appointments');

    try {
      final uSnap = await usersCol.doc(helperId).get();
      final um = uSnap.data() ?? {};

      final pickedName = _pick(
          um, ['fullName', 'full_name', 'name', 'displayName', 'display_name']);
      if (pickedName.isNotEmpty) name = pickedName;

      final pickedEmail = _pick(um, ['email', 'emailAddress']);
      if (pickedEmail.isNotEmpty) email = pickedEmail;

      final pickedPhoto =
      (um['photoUrl'] ?? um['avatarUrl'] ?? '').toString().trim();
      if (pickedPhoto.isNotEmpty) photoUrl = pickedPhoto;

      final facultyId = (um['facultyId'] ?? '').toString();
      if (facultyId.isNotEmpty) {
        final facSnap = await facCol.doc(facultyId).get();
        final fm = facSnap.data() ?? {};
        final t = (fm['title'] ?? fm['name'] ?? '').toString().trim();
        if (t.isNotEmpty) facultyTitle = t;
      }

      final aSnap =
      await appsCol.where('helperId', isEqualTo: helperId).get();
      completedCount = aSnap.docs.where((d) {
        final status =
        (d.data()['status'] ?? '').toString().toLowerCase().trim();
        return status != 'cancelled';
      }).length;

      interestIds = _extractInterestIds(um);
    } catch (_) {
    }

    return (name, facultyTitle, email, completedCount, photoUrl, interestIds);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<(String, String, String, int, String, List<String>)>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data ??
            (fallbackName, fallbackFaculty, fallbackEmail, fallbackSessions,
            fallbackPhotoUrl, const <String>[]);

        return _helperShell(
          t: t,
          helperId: helperId,
          name: data.$1,
          faculty: data.$2,
          email: data.$3,
          sessionsFallback: data.$4,
          photoUrl: data.$5,
          interestIds: data.$6,
          specializesFallback: specializes,
        );
      },
    );
  }

  Widget _helperShell({
    required TextTheme t,
    required String helperId,
    required String name,
    required String faculty,
    required String email,
    required int sessionsFallback,
    required String photoUrl,
    required List<String> interestIds,
    required List<String> specializesFallback,
  }) {
    final sessionsCounter =
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: (helperId.isEmpty)
          ? const Stream.empty()
          : FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperId)
          .snapshots(),
      builder: (context, snap) {
        int count = sessionsFallback;
        if (snap.hasData) {
          count = 0;
          for (final d in snap.data!.docs) {
            final status =
            (d.data()['status'] ?? '').toString().toLowerCase().trim();
            if (status == 'cancelled') continue;
            count++;
          }
        }
        return Text('$count\nsessions',
            textAlign: TextAlign.center, style: t.labelSmall);
      },
    );

    final avatar = Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey.shade300,
          backgroundImage:
          (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child:
          (photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null,
        ),
        const SizedBox(height: 6),
        sessionsCounter,
      ],
    );

    final specializeLine = (interestIds.isEmpty)
        ? _SpecializeLine(items: specializesFallback)
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
      FirebaseFirestore.instance.collection('interests').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _SpecializeLine(items: specializesFallback);
        }
        final all = snap.data!.docs;
        final map = <String, String>{};
        for (final d in all) {
          final m = d.data();
          final title = (m['title'] ?? m['name'] ?? '')
              .toString()
              .trim();
          if (title.isNotEmpty) map[d.id] = title;
        }
        final resolved =
        interestIds.map((id) => map[id]).whereType<String>().toList();
        return _SpecializeLine(
            items: resolved.isNotEmpty ? resolved : specializesFallback);
      },
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(faculty.isEmpty ? '—' : faculty, style: t.bodySmall),
        Text(email.isEmpty ? '—' : email, style: t.bodySmall),
        const SizedBox(height: 6),
        specializeLine,
        const SizedBox(height: 4),
        Text('Bio: N/A', style: t.bodySmall),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (context, c) {
        final tight = c.maxWidth < 360;
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(child: info),
              ]),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(child: info),
          ],
        );
      }),
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _HopHeader extends StatelessWidget {
  const _HopHeader();

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => Navigator.maybePop(context),
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.arrow_back, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),

        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'PEERS',
            style: t.labelMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HOP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _logout(context),
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.logout, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child:
      Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final Widget child;
  const _FieldShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _SpecializeLine extends StatelessWidget {
  final List<String> items;
  const _SpecializeLine({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final boldCount = items.length >= 2 ? 2 : items.length;

    final spans = <TextSpan>[
      TextSpan(text: 'Specialize: ', style: t.bodySmall),
    ];
    for (var i = 0; i < items.length; i++) {
      final isBold = i < boldCount;
      spans.add(TextSpan(
        text: items[i],
        style: t.bodySmall
            ?.copyWith(fontWeight: isBold ? FontWeight.w800 : FontWeight.w400),
      ));
      if (i != items.length - 1) {
        spans.add(TextSpan(text: ', ', style: t.bodySmall));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _ReasonContainer extends StatelessWidget {
  final String label;
  final String reason;
  final bool isAlert;
  final bool isReschedule;

  const _ReasonContainer({
    required this.label,
    required this.reason,
    this.isAlert = false,
    this.isReschedule = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bgColor = isAlert
        ? const Color(0xFFFFE0E0)
        : (isReschedule ? const Color(0xFFE3F2FD) : const Color(0xFFF3E5F5));
    final borderColor = isAlert
        ? const Color(0xFFD32F2F)
        : (isReschedule ? const Color(0xFF1565C0) : const Color(0xFF9C27B0));
    final labelColor = isAlert
        ? const Color(0xFFD32F2F)
        : (isReschedule ? const Color(0xFF1565C0) : const Color(0xFF9C27B0));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: t.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: labelColor)),
          const SizedBox(height: 4),
          Text(reason.isEmpty ? '—' : reason, style: t.bodyMedium),
        ],
      ),
    );
  }
}