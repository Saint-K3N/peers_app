// lib/school_counsellor_booking_info_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SchoolCounsellorBookingInfoPage extends StatefulWidget {
  const SchoolCounsellorBookingInfoPage({super.key});

  @override
  State<SchoolCounsellorBookingInfoPage> createState() => _SchoolCounsellorBookingInfoPageState();
}

class _SchoolCounsellorBookingInfoPageState extends State<SchoolCounsellorBookingInfoPage> {
  // Args (once)
  bool _argsParsed = false;
  String? _appointmentId;

  // Fallbacks (if helper/user doc isn't available yet)
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

    // Optional fallbacks (not required—will be resolved live from Firestore)
    _fbName = (args['name'] as String?) ?? _fbName;
    _fbFaculty = (args['faculty'] as String?) ?? _fbFaculty;
    _fbEmail = (args['email'] as String?) ?? _fbEmail;
    _fbSessions = (args['sessions'] as int?) ?? _fbSessions;
    _fbSpecializes = (args['specializes'] as List?)?.map((e) => e.toString()).toList() ?? _fbSpecializes;
  }

  /* ------------------------------- Utilities ------------------------------- */

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed': return 'Confirmed';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'missed':    return 'Missed';
      case 'pending_reschedule_peer': return 'Reschedule Pending (Peer)';
      case 'pending_reschedule_sc': return 'Reschedule Pending (You)';
      default:          return 'Pending';
    }
  }

  (Color bg, Color fg) _statusColors(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed': return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'completed': return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'cancelled': return (const Color(0xFFFFE0E0), const Color(0xFFD32F2F));
      case 'missed':    return (const Color(0xFFFFF3E0), const Color(0xFFEF6C00));
      case 'pending_reschedule_peer':
      case 'pending_reschedule_sc':
        return (const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      default:          return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('appointments').doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
      if (status != 'pending' && status != 'confirmed' && status != 'pending_reschedule_peer' && status != 'pending_reschedule_sc') continue;

      final tsStart = m['startAt'];
      final tsEnd   = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;

      final existingStart = tsStart.toDate();
      final existingEnd   = tsEnd.toDate();
      final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }

  // SC Reschedule function with 20-char reason
  Future<void> _reschedule(BuildContext context, String apptId, Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();
    DateTime start = (m['startAt'] as Timestamp).toDate();
    DateTime end   = (m['endAt']   as Timestamp).toDate();

    // School Counsellor rule: no reschedule within 24h
    final hoursUntilStart = start.difference(DateTime.now()).inHours;
    if (hoursUntilStart <= 24) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours of the appointment.')),
        );
      }
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RescheduleDialogSC(currentStart: start, currentEnd: end),
    );

    if (result == null) return;

    final DateTime newStart = result['start'];
    final DateTime newEnd = result['end'];
    final String reason = result['reason'];

    if (!newStart.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New start time must be in the future.')));
      }
      return;
    }
    if (!newEnd.isAfter(newStart)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start.')));
      }
      return;
    }
    if (await _hasOverlap(helperId: helperId, startDt: newStart, endDt: newEnd, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflicts with another booking.')));
      }
      return;
    }

    // IMPORTANT: Keep original startAt/endAt, store proposed times
    await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
      'proposedStartAt': Timestamp.fromDate(newStart),
      'proposedEndAt': Timestamp.fromDate(newEnd),
      'rescheduleReasonSC': reason,
      'status': 'pending_reschedule_sc',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule proposed. Waiting for peer confirmation.')));
    }
  }

  // Accept Peer's Reschedule
  Future<void> _acceptPeerReschedule(String apptId, Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();
    final newStartTs = m['proposedStartAt'] as Timestamp?;
    final newEndTs   = m['proposedEndAt'] as Timestamp?;

    if (newStartTs == null || newEndTs == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule data is incomplete.')));
      return;
    }

    final newStartDt = newStartTs.toDate();
    final newEndDt   = newEndTs.toDate();

    if (await _hasOverlap(helperId: helperId, startDt: newStartDt, endDt: newEndDt, excludeId: apptId)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proposed time conflicts with counsellor schedule.')));
      return;
    }

    try {
      // Accept: Move proposed times to actual times, clear proposed fields
      await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
        'status': 'confirmed',
        'startAt': newStartTs,
        'endAt': newEndTs,
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonSC': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule confirmed and appointment updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Confirmation failed: $e')));
    }
  }

  // Cancel with 20-char reason
  Future<void> _cancelExisting(String appointmentId, DateTime startAt, String status) async {
    // Rule: can cancel only ≥ 24h before; not if already completed/cancelled
    final hoursUntilStart = startAt.difference(DateTime.now()).inHours;
    final canModify = hoursUntilStart >= 24;
    if (!canModify || status == 'completed' || status == 'cancelled' || status == 'missed') {
      _msg('Cancel not allowed now.');
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Cancel Booking',
        maxChars: 20,
        hint: 'Reason for cancellation (Max 20 characters)',
      ),
    );

    if (reason == null) return;

    if (reason.isEmpty) {
      _msg('Please enter a reason (max 20 characters).');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).update({
        'status': 'cancelled',
        'cancellationReason': reason,
        'cancelledBy': 'school_counsellor',
        'updatedAt': FieldValue.serverTimestamp(),
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonSC': FieldValue.delete(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
      Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      _msg('Cancel failed: $e');
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
            stream: FirebaseFirestore.instance.collection('appointments').doc(_appointmentId).snapshots(),
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
                    const _SCHeader(),
                    const SizedBox(height: 16),
                    Text('Booking Info', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
              final start = (m['startAt'] as Timestamp?)?.toDate();
              final end = (m['endAt'] as Timestamp?)?.toDate();

              // Proposed times (if rescheduling)
              final proposedStart = (m['proposedStartAt'] as Timestamp?)?.toDate();
              final proposedEnd = (m['proposedEndAt'] as Timestamp?)?.toDate();

              final loc = (m['location'] ?? '').toString();
              final notes = (m['notes'] ?? '').toString();
              final statusRaw = (m['status'] ?? 'pending').toString();
              final helperIdFromDoc = (m['helperId'] ?? '').toString();

              final cancellationReason = (m['cancellationReason'] ?? '').toString().trim();
              final rescheduleReasonPeer = (m['rescheduleReasonPeer'] ?? '').toString().trim();
              final rescheduleReasonSC = (m['rescheduleReasonSC'] ?? '').toString().trim();

              final statusLbl = _statusLabel(statusRaw);
              final (chipBg, chipFg) = _statusColors(statusRaw);

              final now = DateTime.now();
              final hasStart = start != null;
              final isConfirmed = statusRaw == 'confirmed';
              final isPending = statusRaw == 'pending';
              final isTerminal = statusRaw == 'cancelled' || statusRaw == 'completed' || statusRaw == 'missed';
              final isPast = hasStart && !now.isBefore(start!);
              final hoursUntilStart = hasStart ? start!.difference(now).inHours : 999;
              final isWithin24Hours = hoursUntilStart <= 24;

              // Can mark complete/missed after original start time, even if reschedule pending
              final canOutcome = hasStart && isPast && !isTerminal;

              // --- SC BUSINESS LOGIC (Conditions 1 & 2) ---
              bool canSCCancel = false;
              bool canSCReschedule = false;
              final isPendingPeerReschedule = statusRaw == 'pending_reschedule_peer';
              final isPendingSCReschedule = statusRaw == 'pending_reschedule_sc';

              if (hasStart && !isTerminal && !isPast) {
                if (isPendingPeerReschedule) {
                  // Special state: SC must confirm peer's proposal
                  canSCCancel = false;
                  canSCReschedule = false;
                } else if (isPendingSCReschedule) {
                  // Waiting for peer to confirm SC's proposal
                  canSCCancel = false;
                  canSCReschedule = false;
                } else if (isWithin24Hours) {
                  // Condition 1: <= 24 hours
                  if (isPending) {
                    // Rule: SC can cancel with reason before confirmation
                    canSCCancel = true;
                    canSCReschedule = false;
                  } else if (isConfirmed) {
                    // Rule: SC can cancel with reason, no reschedule
                    canSCCancel = true;
                    canSCReschedule = false;
                  }
                } else {
                  // Condition 2: > 24 hours
                  if (isPending) {
                    // Rule: SC can cancel with reason, no reschedule before confirmation
                    canSCCancel = true;
                    canSCReschedule = false;
                  } else if (isConfirmed) {
                    // Rule: SC can reschedule or cancel with reason
                    canSCCancel = true;
                    canSCReschedule = true;
                  }
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SCHeader(),
                  const SizedBox(height: 16),

                  Text('Booking Info', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Appointment details', style: t.bodySmall),
                  const SizedBox(height: 12),

                  // Header card + status chip
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

                  // Display Reschedule Reasons
                  if (rescheduleReasonSC.isNotEmpty) ...[
                    _ReasonContainer(label: 'Your Reschedule Reason', reason: rescheduleReasonSC, isReschedule: true),
                    const SizedBox(height: 12),
                  ] else if (rescheduleReasonPeer.isNotEmpty) ...[
                    _ReasonContainer(label: 'Peer Reschedule Reason', reason: rescheduleReasonPeer, isReschedule: true),
                    const SizedBox(height: 12),
                  ],

                  // Display Cancellation Reason
                  if (statusRaw == 'cancelled' && cancellationReason.isNotEmpty) ...[
                    _ReasonContainer(label: 'Cancellation Reason', reason: cancellationReason, isAlert: true),
                    const SizedBox(height: 12),
                  ],

                  // ORIGINAL DATE (always show)
                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(child: Text((start != null) ? 'Original Date: ${_fmtDate(start)}' : 'Date: —', style: t.bodyMedium)),
                        const Icon(Icons.calendar_month_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ORIGINAL TIME (always show)
                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (start != null && end != null)
                                ? 'Original Time: ${_fmtTime(TimeOfDay.fromDateTime(start))} to ${_fmtTime(TimeOfDay.fromDateTime(end))}'
                                : 'Time: —',
                            style: t.bodyMedium,
                          ),
                        ),
                        const Icon(Icons.timer_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // PROPOSED DATE (if reschedule pending)
                  if (proposedStart != null) ...[
                    _FieldShell(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Proposed Date: ${_fmtDate(proposedStart)}',
                              style: t.bodyMedium?.copyWith(color: const Color(0xFF8A6D3B), fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Icon(Icons.calendar_month_outlined, color: Color(0xFF8A6D3B)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // PROPOSED TIME (if reschedule pending)
                  if (proposedStart != null && proposedEnd != null) ...[
                    _FieldShell(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Proposed Time: ${_fmtTime(TimeOfDay.fromDateTime(proposedStart))} to ${_fmtTime(TimeOfDay.fromDateTime(proposedEnd))}',
                              style: t.bodyMedium?.copyWith(color: const Color(0xFF8A6D3B), fontWeight: FontWeight.w700),
                            ),
                          ),
                          const Icon(Icons.timer_outlined, color: Color(0xFF8A6D3B)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  _FieldShell(
                    child: Row(
                      children: [
                        Expanded(child: Text(loc.isEmpty ? '—' : loc, style: t.bodyMedium)),
                        const Icon(Icons.place_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Notes (read-only)
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: SingleChildScrollView(
                      primary: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(notes.isEmpty ? '—' : notes, softWrap: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Footer actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back')),
                      Wrap(
                        spacing: 8,
                        children: [
                          // Action: Accept Reschedule (when peer proposed)
                          if (isPendingPeerReschedule && start != null)
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                              onPressed: () => _acceptPeerReschedule(_appointmentId!, m),
                              child: const Text('Accept Reschedule'),
                            ),

                          // Action: Reschedule (only confirmed & > 24h)
                          if (canSCReschedule && start != null && end != null)
                            FilledButton.tonal(
                              onPressed: () => _reschedule(context, _appointmentId!, m),
                              child: const Text('Reschedule'),
                            ),

                          // Action: Cancel (with reason)
                          if (canSCCancel && start != null)
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => _cancelExisting(_appointmentId!, start, statusRaw),
                              child: const Text('Cancel Booking'),
                            ),

                          // Action: Mark Outcome (after original start time, even if reschedule pending)
                          if (canOutcome && start != null) ...[
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                              onPressed: () async {
                                await _updateStatus(_appointmentId!, 'completed');
                                if (mounted) _msg('Marked as completed.');
                              },
                              child: const Text('Complete'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A6D3B)),
                              onPressed: () async {
                                await _updateStatus(_appointmentId!, 'missed');
                                if (mounted) _msg('Marked as missed.');
                              },
                              child: const Text('Missed'),
                            ),
                          ],
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
  final List<String> specializes; // fallback list of titles

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
          else if (e is Map && e['id'] is String) out.add((e['id'] as String).trim());
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

  Future<(String name, String facultyTitle, String email, int completedCount,
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

      final pickedName = _pick(um, ['fullName','full_name','name','displayName','display_name']);
      if (pickedName.isNotEmpty) name = pickedName;

      final pickedEmail = _pick(um, ['email','emailAddress']);
      if (pickedEmail.isNotEmpty) email = pickedEmail;

      final pickedPhoto = (um['photoUrl'] ?? um['avatarUrl'] ?? '').toString().trim();
      if (pickedPhoto.isNotEmpty) photoUrl = pickedPhoto;

      final facultyId = (um['facultyId'] ?? '').toString();
      if (facultyId.isNotEmpty) {
        final facSnap = await facCol.doc(facultyId).get();
        final fm = facSnap.data() ?? {};
        final t = (fm['title'] ?? fm['name'] ?? '').toString().trim();
        if (t.isNotEmpty) facultyTitle = t;
      }

      final aSnap = await appsCol.where('helperId', isEqualTo: helperId).get();
      completedCount = aSnap.docs.where((d) {
        final status = (d.data()['status'] ?? '').toString().toLowerCase().trim();
        return status != 'cancelled';
      }).length;

      interestIds = _extractInterestIds(um);
    } catch (_) {
      // keep fallbacks
    }

    return (name, facultyTitle, email, completedCount, photoUrl, interestIds);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<(String, String, String, int, String, List<String>)>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data ?? (fallbackName, fallbackFaculty, fallbackEmail, fallbackSessions, fallbackPhotoUrl, const <String>[]);

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
    final sessionsCounter = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: (helperId.isEmpty)
          ? const Stream.empty()
          : FirebaseFirestore.instance.collection('appointments').where('helperId', isEqualTo: helperId).snapshots(),
      builder: (context, snap) {
        int count = sessionsFallback;
        if (snap.hasData) {
          count = 0;
          for (final d in snap.data!.docs) {
            final status = (d.data()['status'] ?? '').toString().toLowerCase().trim();
            if (status == 'cancelled') continue;
            count++;
          }
        }
        return Text('$count\nsessions', textAlign: TextAlign.center, style: t.labelSmall);
      },
    );

    final avatar = Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey.shade300,
          backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child: (photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null,
        ),
        const SizedBox(height: 6),
        sessionsCounter,
      ],
    );

    final specializeLine = (interestIds.isEmpty)
        ? _SpecializeLine(items: specializesFallback)
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('interests').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _SpecializeLine(items: specializesFallback);
        }
        final all = snap.data!.docs;
        final map = <String, String>{};
        for (final d in all) {
          final m = d.data();
          final title = (m['title'] ?? m['name'] ?? '').toString().trim();
          if (title.isNotEmpty) map[d.id] = title;
        }
        final resolved = interestIds.map((id) => map[id]).whereType<String>().toList();
        return _SpecializeLine(items: resolved.isNotEmpty ? resolved : specializesFallback);
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 4))],
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

class _SCHeader extends StatelessWidget {
  const _SCHeader();

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
        // back
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

        // logo
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
          child: Text('PEERS', style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),

        // title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('School Counsellor', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // logout button
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
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
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
    if (items.isEmpty) return Text('Specialize: —', style: t.bodySmall);

    final boldCount = items.length >= 2 ? 2 : items.length;
    final spans = <TextSpan>[TextSpan(text: 'Specialize: ', style: t.bodySmall)];
    for (var i = 0; i < items.length; i++) {
      final isBold = i < boldCount;
      spans.add(TextSpan(
        text: items[i],
        style: t.bodySmall?.copyWith(fontWeight: isBold ? FontWeight.w800 : FontWeight.w400),
      ));
      if (i != items.length - 1) spans.add(TextSpan(text: ', ', style: t.bodySmall));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

// Consolidated Reason Container (handles cancel and reschedule reasons)
class _ReasonContainer extends StatelessWidget {
  final String label;
  final String reason;
  final bool isAlert;
  final bool isReschedule;

  const _ReasonContainer({required this.label, required this.reason, this.isAlert = false, this.isReschedule = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bgColor = isAlert ? const Color(0xFFFFE0E0) : (isReschedule ? const Color(0xFFE3F2FD) : const Color(0xFFF3E5F5));
    final borderColor = isAlert ? const Color(0xFFD32F2F) : (isReschedule ? const Color(0xFF1565C0) : const Color(0xFF9C27B0));
    final labelColor = isAlert ? const Color(0xFFD32F2F) : (isReschedule ? const Color(0xFF1565C0) : const Color(0xFF9C27B0));

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
          Text(label, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: labelColor)),
          const SizedBox(height: 4),
          Text(reason.isEmpty ? '—' : reason, style: t.bodyMedium),
        ],
      ),
    );
  }
}

// Simplified _ReasonDialog to use only the 20-char text field
class _ReasonDialog extends StatelessWidget {
  final String title;
  final int maxChars;
  final String hint;
  const _ReasonDialog({required this.title, required this.maxChars, this.hint = 'Reason'});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Please provide a reason (Max $maxChars characters):'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            maxLines: 2,
            maxLength: maxChars,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Close')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            final reason = ctrl.text.trim();
            if (reason.isEmpty || reason.length > maxChars) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('A reason (max $maxChars characters) is required.')));
            } else {
              Navigator.pop(context, reason);
            }
          },
          child: Text(title.contains('Cancel') ? 'Confirm Cancel' : 'Confirm'),
        ),
      ],
    );
  }
}

// Reschedule Dialog (SC initiated)
class _RescheduleDialogSC extends StatefulWidget {
  final DateTime currentStart, currentEnd;
  const _RescheduleDialogSC({required this.currentStart, required this.currentEnd});
  @override
  State<_RescheduleDialogSC> createState() => _RescheduleDialogSCState();
}

class _RescheduleDialogSCState extends State<_RescheduleDialogSC> {
  late DateTime _date;
  late TimeOfDay _startTod, _endTod;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.currentStart.year, widget.currentStart.month, widget.currentStart.day);
    _startTod = TimeOfDay.fromDateTime(widget.currentStart);
    _endTod = TimeOfDay.fromDateTime(widget.currentEnd);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365))
    );
    if (p != null) setState(() => _date = p);
  }

  Future<void> _pickTime(bool isStart) async {
    final p = await showTimePicker(context: context, initialTime: isStart ? _startTod : _endTod);
    if (p != null) setState(() => isStart ? _startTod = p : _endTod = p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reschedule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              dense: true,
              title: const Text('Date'),
              subtitle: Text(_fmtDate(_date)),
              trailing: IconButton(icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickDate)
          ),
          Row(children: [
            Expanded(
                child: ListTile(
                    dense: true,
                    title: const Text('Start'),
                    subtitle: Text(_fmtTime(_startTod)),
                    trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(true))
                )
            ),
            Expanded(
                child: ListTile(
                    dense: true,
                    title: const Text('End'),
                    subtitle: Text(_fmtTime(_endTod)),
                    trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(false))
                )
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
                hintText: 'Reason for rescheduling (Max 20 characters)',
                border: OutlineInputBorder(),
                counterText: ''
            ),
            maxLines: 2,
            maxLength: 20,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: () {
          final start = DateTime(_date.year, _date.month, _date.day, _startTod.hour, _startTod.minute);
          final end = DateTime(_date.year, _date.month, _date.day, _endTod.hour, _endTod.minute);
          final reason = _reasonCtrl.text.trim();

          if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
            return;
          }
          if (start.isBefore(DateTime.now())) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New time must be in the future.')));
            return;
          }
          if (reason.isEmpty || reason.length > 20) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason (max 20 chars) is required.')));
            return;
          }

          Navigator.pop(context, {'start': start, 'end': end, 'reason': reason});
        }, child: const Text('Save')),
      ],
    );
  }
}