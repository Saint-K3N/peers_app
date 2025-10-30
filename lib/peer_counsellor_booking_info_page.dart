// lib/peer_counsellor_booking_info_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class PeerCounsellorBookingInfoPage extends StatelessWidget {
  const PeerCounsellorBookingInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final apptId = (args['appointmentId'] as String?) ?? '';

    return Scaffold(
      body: SafeArea(
        child: apptId.isEmpty
            ? const _MissingIdView()
            : _PeerCounsellorBookingInfoBody(appointmentId: apptId),
      ),
    );
  }
}

/* ------------------------------- Body -------------------------------- */

class _PeerCounsellorBookingInfoBody extends StatefulWidget {
  final String appointmentId;
  const _PeerCounsellorBookingInfoBody({required this.appointmentId});

  @override
  State<_PeerCounsellorBookingInfoBody> createState() =>
      _PeerCounsellorBookingInfoBodyState();
}

class _PeerCounsellorBookingInfoBodyState
    extends State<_PeerCounsellorBookingInfoBody> {
  String _fmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String _fmtTime(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat.jm().format(dt);
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
      case 'pending_reschedule_peer':
        return 'Reschedule (You)';
      case 'pending_reschedule_student':
        return 'Reschedule (Student)';
      case 'pending_reschedule_sc':
        return 'Reschedule (SC)';
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
        return (const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      case 'pending_reschedule_peer':
      case 'pending_reschedule_student':
      case 'pending_reschedule_sc':
        return (const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      default:
        return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  // Helper to pick strings from user doc
  String _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v
          .trim()
          .isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in keys) {
        final v = prof[k];
        if (v is String && v
            .trim()
            .isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  // Helper to resolve topic IDs to titles
  Future<List<String>> _getTopicTitles(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('interests')
          .where(FieldPath.documentId, whereIn: ids.take(10).toList())
          .get();
      return snap.docs
          .map((d) =>
          (d.data()['title'] ?? d.data()['name'] ?? '').toString().trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _markCompleted(String id, DateTime start) async {
    // Only after the start time
    if (DateTime.now().isBefore(start)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
              Text('You can mark outcome only after the appointment time.')),
        );
      }
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .update({
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
            const SnackBar(content: Text('Marked as completed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to complete: $e')));
      }
    }
  }

  Future<void> _markMissed(String id, DateTime start) async {
    // Only after the start time
    if (DateTime.now().isBefore(start)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
              Text('You can mark outcome only after the appointment time.')),
        );
      }
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .update({
        'status': 'missed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Marked as missed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to mark missed: $e')));
      }
    }
  }

  // Confirm Appointment function
  Future<void> _confirmAppointment(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .update({
        'status': 'confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment confirmed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm: $e')),
        );
      }
    }
  }

  // Cancel function with 20-char dialog and Condition 1 check
  Future<void> _cancelWithReason(String id, DateTime start) async {
    // Condition 1 check: If confirmed, Peers cannot cancel if <= 24 hours.
    final doc = await FirebaseFirestore.instance.collection('appointments').doc(
        id).get();
    final status = (doc.data()?['status'] ?? '').toString().toLowerCase();
    final isConfirmed = status == 'confirmed';
    final hoursUntilStart = start
        .difference(DateTime.now())
        .inHours;
    final isWithin24Hours = hoursUntilStart <= 24;

    if (isConfirmed && isWithin24Hours) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'Confirmed appointments cannot be cancelled within 24 hours (Condition 1).')),
        );
      }
      return;
    }

    // Use the 20-character reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
      const _ReasonDialog(
        title: 'Cancel Booking',
        maxChars: 20,
        hint: 'Reason for cancellation (Max 20 characters)',
      ),
    );

    if (reason != null && mounted) {
      if (reason.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Please enter a reason (max 20 characters).')));
        }
        return;
      }
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(id)
            .update({
          'status': 'cancelled',
          'cancellationReason': reason,
          'cancelledBy': 'helper',
          'updatedAt': FieldValue.serverTimestamp(),
          'proposedStartAt': FieldValue.delete(),
          'proposedEndAt': FieldValue.delete(),
          'rescheduleReasonPeer': FieldValue.delete(),
          'rescheduleReasonStudent': FieldValue.delete(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking cancelled.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancel failed: $e')),
          );
        }
      }
    }
  }

  // Peer Reschedule function (initiates a change request to the student)
  Future<void> _rescheduleWithReason(String apptId, DateTime currentStart, DateTime currentEnd, String createdByRole) async {
    // Condition 1 & 2: Reschedule not allowed within 24 hours.
    final hoursUntilStart = currentStart
        .difference(DateTime.now())
        .inHours;
    if (hoursUntilStart <= 24) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Reschedule not allowed within 24 hours (Condition 1).')));
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _RescheduleDialogPeer(
              currentStart: currentStart, currentEnd: currentEnd),
    );

    if (result == null || !mounted) return;

    final DateTime newStart = result['start'];
    final DateTime newEnd = result['end'];
    final String reason = result['reason'];

    // Check overlap of the proposed time with *Peer's* existing schedule (excluding the current apptId)
    if (await _hasOverlap(helperId: FirebaseAuth.instance.currentUser!.uid,
        startDt: newStart,
        endDt: newEnd,
        excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
            'Proposed time conflicts with your existing schedule.')));
      }
      return;
    }

    try {
      // IMPORTANT: Keep original startAt and endAt, only add proposed times
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(apptId)
          .update({
        'proposedStartAt': Timestamp.fromDate(newStart),
        'proposedEndAt': Timestamp.fromDate(newEnd),
        'rescheduleReasonPeer': reason,
        'status': 'pending_reschedule_peer',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            'Reschedule proposed. Waiting for ${createdByRole == 'school_counsellor' ? 'School Counsellor' : 'Student'} confirmation.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reschedule failed: $e')));
      }
    }
  }

  // Accept Reschedule initiated by Student
  Future<void> _acceptStudentReschedule(String apptId,
      Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();
    final newStartTs = m['proposedStartAt'] as Timestamp?;
    final newEndTs = m['proposedEndAt'] as Timestamp?;

    if (newStartTs == null || newEndTs == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule data is incomplete.')));
      return;
    }

    final newStartDt = newStartTs.toDate();
    final newEndDt = newEndTs.toDate();

    if (await _hasOverlap(helperId: helperId,
        startDt: newStartDt,
        endDt: newEndDt,
        excludeId: apptId)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Proposed time conflicts with your existing schedule.')));
      return;
    }

    try {
      // Accept: Move proposed times to actual times, clear proposed fields
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(apptId)
          .update({
        'status': 'confirmed',
        'startAt': newStartTs,
        'endAt': newEndTs,
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reschedule confirmed and appointment updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Confirmation failed: $e')));
    }
  }

  // Reject Student Reschedule
  Future<void> _rejectStudentReschedule(String apptId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Reject Reschedule',
        maxChars: 20,
        hint: 'Reason for rejection',
      ),
    );

    if (reason == null || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
        'status': 'confirmed',
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
        'rejectionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule rejected. Original time retained.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject: $e')),
        );
      }
    }
  }

  // NEW: Accept Reschedule initiated by School Counsellor
  Future<void> _acceptSCReschedule(String apptId,
      Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();
    final newStartTs = m['proposedStartAt'] as Timestamp?;
    final newEndTs = m['proposedEndAt'] as Timestamp?;

    if (newStartTs == null || newEndTs == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule data is incomplete.')));
      return;
    }

    final newStartDt = newStartTs.toDate();
    final newEndDt = newEndTs.toDate();

    if (await _hasOverlap(helperId: helperId,
        startDt: newStartDt,
        endDt: newEndDt,
        excludeId: apptId)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Proposed time conflicts with your existing schedule.')));
      return;
    }

    try {
      // Accept: Move proposed times to actual times, clear proposed fields
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(apptId)
          .update({
        'status': 'confirmed',
        'startAt': newStartTs,
        'endAt': newEndTs,
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
        'rescheduleReasonSC': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reschedule confirmed and appointment updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Confirmation failed: $e')));
    }
  }

  // NEW: Cancel/Reject Reschedule Proposal
  Future<void> _cancelRescheduleProposal(String apptId, Map<String, dynamic> m) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Cancel Reschedule',
        maxChars: 20,
        hint: 'Reason for cancelling reschedule',
      ),
    );

    if (reason == null || !mounted) return;

    try {
      // Revert to confirmed status, keep original times, delete proposed fields
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(apptId)
          .update({
        'status': 'confirmed',
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
        'rescheduleReasonSC': FieldValue.delete(),
        'rescheduleRejectionReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule proposal cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel reschedule: $e')),
        );
      }
    }
  }

  Future<bool> _hasOverlap(
      {required String helperId, required DateTime startDt, required DateTime endDt, String? excludeId}) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .get();
    for (final d in snap.docs) {
      if (excludeId != null && d.id == excludeId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase();
      // Only check against confirmed/pending/pending_reschedule appointments (active slots)
      if (status != 'pending' && status != 'confirmed' &&
          status != 'pending_reschedule_peer' &&
          status != 'pending_reschedule_student') continue;
      final tsStart = m['startAt'];
      final tsEnd = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;
      if (tsStart.toDate().isBefore(endDt) && tsEnd.toDate().isAfter(startDt))
        return true;
    }
    return false;
  }

/*---------------------PEER COUNSELLOR BOOKING INFO BODY-------------------*/
  @override
  Widget build(BuildContext context) {
    final t = Theme
        .of(context)
        .textTheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .snapshots(),
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;
        final notFound = !snap.hasData || !(snap.data?.exists ?? false);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CounsellorHeaderBar(),
              const SizedBox(height: 16),

              Text('Booking Info',
                  style:
                  t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('View details and take action', style: t.bodySmall),
              const SizedBox(height: 12),

              if (waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                if (notFound)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Text('Appointment not found.'),
                  )
                else
                  Builder(
                    builder: (_) {
                      final m = snap.data!.data()!;
                      final start = (m['startAt'] as Timestamp?)?.toDate();
                      final end = (m['endAt'] as Timestamp?)?.toDate();

                      // Proposed times (if rescheduling)
                      final proposedStart = (m['proposedStartAt'] as Timestamp?)
                          ?.toDate();
                      final proposedEnd = (m['proposedEndAt'] as Timestamp?)
                          ?.toDate();

                      // Prefer mode/meetUrl if present, else location/venue
                      final mode = (m['mode'] ?? 'physical')
                          .toString()
                          .toLowerCase();
                      final loc = () {
                        if (mode == 'online') {
                          final meet = (m['meetUrl'] ?? '').toString();
                          return meet.isNotEmpty ? 'Online ($meet)' : 'Online';
                        }
                        final v = (m['location'] ?? m['venue'] ?? '')
                            .toString();
                        return v.isNotEmpty ? v : 'Campus';
                      }();

                      final sessionType = 'Counselling';

                      final notes = (m['notes'] ?? '').toString();
                      final statusRaw =
                      (m['status'] ?? 'pending')
                          .toString()
                          .toLowerCase()
                          .trim();
                      final statusLbl = _statusLabel(statusRaw);
                      final (chipBg, chipFg) = _statusColors(statusRaw);

                      // FIX: Detect appointment type - School Counsellor OR Student
                      final studentId = (m['studentId'] ?? '').toString();
                      final schoolCounsellorId = (m['schoolCounsellorId'] ?? '').toString();

                      final cancellationReason = (m['cancellationReason'] ?? '')
                          .toString()
                          .trim();
                      final rescheduleReasonPeer = (m['rescheduleReasonPeer'] ??
                          '').toString().trim();
                      final rescheduleReasonStudent = (m['rescheduleReasonStudent'] ??
                          '').toString().trim();
                      final rescheduleReasonSC = (m['rescheduleReasonSC'] ?? '')
                          .toString()
                          .trim();

                      // FIX: Get the correct topic IDs based on appointment type
                      final interestIds = schoolCounsellorId.isNotEmpty
                          ? const <String>[
                      ] // School Counsellors don't have counseling topics
                          : ((m['counselingTopicIds'] ?? m['topicIds'] ?? [
                      ]) as List)
                          .map((e) => e.toString()).toList();

                      // --- TIME AND STATUS FLAGS ---
                      final now = DateTime.now();
                      final hasStart = start != null;
                      final isConfirmed = statusRaw == 'confirmed';
                      final isPending = statusRaw == 'pending';
                      final isTerminal = statusRaw == 'cancelled' ||
                          statusRaw == 'completed' || statusRaw == 'missed';
                      final isPast = hasStart && !now.isBefore(start!);
                      final hoursUntilStart = hasStart ? start!.difference(now)
                          .inHours : 999;
                      final isWithin24Hours = hoursUntilStart <= 24;

                      // Can mark complete/missed after original start time, even in reschedule pending
                      final canOutcome = hasStart && isPast && !isTerminal;

                      // --- PEER BUSINESS LOGIC (Conditions 1 & 2) ---

                      bool canConfirm = false;
                      bool canPeerCancel = false;
                      bool canPeerReschedule = false;
                      final isPendingStudentReschedule = statusRaw ==
                          'pending_reschedule_student';
                      final isPendingSCReschedule = statusRaw ==
                          'pending_reschedule_sc';
                      final isPendingPeerReschedule = statusRaw ==
                          'pending_reschedule_peer';

                      if (hasStart && !isTerminal && !isPast) {
                        if (isPendingStudentReschedule ||
                            isPendingSCReschedule) {
                          // Special state: Peer must confirm the proposal
                          canConfirm = false;
                          canPeerCancel = false;
                          canPeerReschedule = false;
                        } else if (isPendingPeerReschedule) {
                          // Waiting for student/SC to confirm peer's proposal
                          canConfirm = false;
                          canPeerCancel = false;
                          canPeerReschedule = false;
                        } else if (isWithin24Hours) {
                          // Condition 1: <= 24 hours
                          if (isPending) {
                            // Rule: Peers can choose to Confirm or Cancel
                            canConfirm = true;
                            canPeerCancel = true;
                            canPeerReschedule = false;
                          }
                          // If Confirmed: NO cancellation or rescheduling for Peers within 24h.
                        } else {
                          // Condition 2: > 24 hours
                          if (isPending) {
                            // Rule: Peers can choose to Confirm/Cancel/Reschedule
                            canConfirm = true;
                            canPeerCancel = true;
                            canPeerReschedule = true;
                          } else if (isConfirmed) {
                            // Rule: Peers can choose to Cancel or Reschedule
                            canPeerCancel = true;
                            canPeerReschedule = true;
                          }
                        }
                      }

                      // --- END PEER BUSINESS LOGIC ---


                      return FutureBuilder(
                          future: Future.wait([
                            // FIX: Fetch the correct user doc based on appointment type
                            (studentId.isNotEmpty
                                ? FirebaseFirestore.instance.collection('users').doc(studentId).get()
                                : (schoolCounsellorId.isNotEmpty
                                ? FirebaseFirestore.instance.collection('users').doc(schoolCounsellorId).get()
                                : Future.value(null))),
                            _getTopicTitles(interestIds),
                          ]),
                          builder: (context, infoSnap) {
                            final userDoc = infoSnap.data?[0] as DocumentSnapshot<Map<String, dynamic>>?;
                            final userMap = userDoc?.data() ?? {};
                            final userBio = _pickString(userMap, ['about']).ifEmpty('N/A');
                            final topicTitles = (infoSnap.data?[1] as List<String>?) ?? [];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    _StudentOrSchoolCounsellorInfoCard(
                                      studentId: studentId,
                                      schoolCounsellorId: schoolCounsellorId,
                                      userBio: userBio,
                                    ),
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: _Chip(label: statusLbl, bg: chipBg, fg: chipFg),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Display Reschedule Reasons (Peer, Student, or SC initiated)
                                if (rescheduleReasonPeer.isNotEmpty) ...[
                                  _ReasonContainer(
                                      label: 'Your Reschedule Reason',
                                      reason: rescheduleReasonPeer,
                                      isReschedule: true),
                                  const SizedBox(height: 12),
                                ] else
                                  if (rescheduleReasonStudent.isNotEmpty) ...[
                                    _ReasonContainer(
                                        label: 'Student Reschedule Reason',
                                        reason: rescheduleReasonStudent,
                                        isReschedule: true),
                                    const SizedBox(height: 12),
                                  ] else
                                    if (rescheduleReasonSC.isNotEmpty) ...[
                                      _ReasonContainer(
                                          label: 'School Counsellor Reschedule Reason',
                                          reason: rescheduleReasonSC,
                                          isReschedule: true),
                                      const SizedBox(height: 12),
                                    ],

                                // Display Cancellation Reason
                                if (statusRaw == 'cancelled' &&
                                    cancellationReason.isNotEmpty) ...[
                                  _ReasonContainer(label: 'Cancellation Reason',
                                      reason: cancellationReason,
                                      isAlert: true),
                                  const SizedBox(height: 12),
                                ],


                                // Session Type
                                _FieldShell(
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(
                                          'Session Type: $sessionType',
                                          style: t.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w700))),
                                      const Icon(Icons.psychology_alt_outlined),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Topics (only show for Student appointments)
                                if (studentId.isNotEmpty) ...[
                                  _FieldShell(
                                    height: 60,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment
                                          .start,
                                      mainAxisAlignment: MainAxisAlignment
                                          .center,
                                      children: [
                                        Text('Topics:',
                                            style: t.labelSmall?.copyWith(
                                                color: Colors.black54)),
                                        Text(topicTitles.isEmpty
                                            ? '—'
                                            : topicTitles.join(', '),
                                            style: t.bodyMedium,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // ORIGINAL DATE (always show)
                                _FieldShell(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (start != null)
                                              ? 'Original Date: ${_fmtDate(
                                              start)}'
                                              : 'Date: —',
                                          style: t.bodyMedium,
                                        ),
                                      ),
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
                                              ? 'Original Time: ${_fmtTime(
                                              TimeOfDay.fromDateTime(
                                                  start))} to ${_fmtTime(
                                              TimeOfDay.fromDateTime(end))}'
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
                                            'Proposed Date: ${_fmtDate(
                                                proposedStart)}',
                                            style: t.bodyMedium?.copyWith(
                                                color: const Color(0xFF8A6D3B),
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const Icon(
                                            Icons.calendar_month_outlined,
                                            color: Color(0xFF8A6D3B)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // PROPOSED TIME (if reschedule pending)
                                if (proposedStart != null &&
                                    proposedEnd != null) ...[
                                  _FieldShell(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Proposed Time: ${_fmtTime(
                                                TimeOfDay.fromDateTime(
                                                    proposedStart))} to ${_fmtTime(
                                                TimeOfDay.fromDateTime(
                                                    proposedEnd))}',
                                            style: t.bodyMedium?.copyWith(
                                                color: const Color(0xFF8A6D3B),
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const Icon(Icons.timer_outlined,
                                            color: Color(0xFF8A6D3B)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                _FieldShell(
                                  child: Row(
                                    children: [
                                      Expanded(
                                          child: Text(loc.isEmpty ? '—' : loc,
                                              style: t.bodyMedium)),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: SingleChildScrollView(
                                    primary: false,
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Text(notes.isEmpty ? '—' : notes,
                                          softWrap: true),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment
                                      .spaceBetween,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.maybePop(context),
                                      child: const Text('Back'),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        // Action: Accept Reschedule (when student proposed)
                                        if (isPendingStudentReschedule &&
                                            start != null)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                    0xFF2E7D32)),
                                            onPressed: () =>
                                                _acceptStudentReschedule(
                                                    widget.appointmentId, m),
                                            child: const Text(
                                                'Confirm'),
                                          ),

                                        // Action: Accept Reschedule (when SC proposed)
                                        if (isPendingSCReschedule &&
                                            start != null)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                    0xFF2E7D32)),
                                            onPressed: () =>
                                                _acceptSCReschedule(
                                                    widget.appointmentId, m),
                                            child: const Text(
                                                "Confirm"),
                                          ),

                                        // Action: Cancel Reschedule Proposal (Student or SC)
                                        if ((isPendingStudentReschedule || isPendingSCReschedule) && start != null)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: Colors.red),
                                            onPressed: () {
                                              if (isPendingStudentReschedule) {
                                                _rejectStudentReschedule(widget.appointmentId);
                                              } else {
                                                _cancelRescheduleProposal(
                                                    widget.appointmentId, m);
                                              }
                                            },
                                            child: const Text("Decline"),
                                          ),

                                        // Action: Confirm (initial booking)
                                        if (canConfirm)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                    0xFF2E7D32)),
                                            onPressed: () =>
                                                _confirmAppointment(
                                                    widget.appointmentId),
                                            child: const Text('Confirm'),
                                          ),

                                        // Action: Reschedule (only outside 24h)
                                        if (canPeerReschedule &&
                                            start != null && end != null)
                                          FilledButton.tonal(
                                            onPressed: () {
                                              final createdByRole = schoolCounsellorId.isNotEmpty ? 'school_counsellor' : 'student';
                                              _rescheduleWithReason(
                                                  widget.appointmentId, start,
                                                  end, createdByRole);
                                            },
                                            child: const Text('Reschedule'),
                                          ),

                                        // Action: Cancel
                                        if (canPeerCancel && start != null)
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: Colors.red),
                                            onPressed: () =>
                                                _cancelWithReason(
                                                    widget.appointmentId,
                                                    start),
                                            child: const Text('Cancel'),
                                          ),

                                        // Action: Mark Outcome (after original start time, even if reschedule pending)
                                        if (canOutcome && start != null) ...[
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                    0xFF2E7D32)),
                                            onPressed: () =>
                                                _markCompleted(
                                                    widget.appointmentId,
                                                    start),
                                            child: const Text('Completed'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                    0xFF8A6D3B)),
                                            onPressed: () =>
                                                _markMissed(
                                                    widget.appointmentId,
                                                    start),
                                            child: const Text('Missed'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

/* ------------------------------ Header Bar ------------------------------ */

class _CounsellorHeaderBar extends StatelessWidget {
  const _CounsellorHeaderBar();

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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peer Counsellor', style: t.titleMedium),
            Text('Portal',
                style:
                t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
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

/* ---------------------------- Student or School Counsellor Info Card --------------------------- */

class _StudentOrSchoolCounsellorInfoCard extends StatelessWidget {
  final String studentId;
  final String schoolCounsellorId;
  final String userBio;

  const _StudentOrSchoolCounsellorInfoCard({
    required this.studentId,
    required this.schoolCounsellorId,
    required this.userBio,
  });

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in keys) {
        final v = prof[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // FIX: Determine appointment type
    final isSchoolCounsellorAppointment = schoolCounsellorId.isNotEmpty;
    final userId = isSchoolCounsellorAppointment ? schoolCounsellorId : studentId;
    final label = isSchoolCounsellorAppointment ? 'School Counsellor' : 'Student';

    // Guard against empty IDs
    if (userId.isEmpty) {
      return _buildCard(t, label, '—', '', userBio, label);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? <String, dynamic>{};
        final name = _pick(m, const [
          'fullName',
          'full_name',
          'name',
          'displayName',
          'display_name'
        ]).ifEmpty(label);
        final email = _pick(m, const ['email', 'emailAddress']).ifEmpty('—');
        final photoUrl =
        ((m['photoUrl'] ?? m['avatarUrl'] ?? '') as String).trim();

        return _buildCard(t, name, email, photoUrl, userBio, label);
      },
    );
  }

  Widget _buildCard(TextTheme t, String name, String email, String photoUrl, String bio, String label) {
    final avatar = Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey.shade300,
          backgroundImage:
          (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child: (photoUrl.isEmpty)
              ? const Icon(Icons.person, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 6),
        Text(label, style: t.labelSmall),
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style:
            t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(email, style: t.bodySmall),
        const SizedBox(height: 6),
        Text('Bio: ${bio.ifEmpty('N/A')}', style: t.bodySmall),
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
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(child: info),
        ],
      ),
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

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
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final Widget child;
  final double height;
  const _FieldShell({required this.child, this.height = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
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
          Text(reason.ifEmpty('—'), style: t.bodyMedium),
        ],
      ),
    );
  }
}


class _MissingIdView extends StatelessWidget {
  const _MissingIdView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Missing appointment ID.\nOpen this page from your tasks/schedule.',
          textAlign: TextAlign.center,
          style: t.bodyMedium,
        ),
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

// Reschedule Dialog (Peer/Helper initiated)
class _RescheduleDialogPeer extends StatefulWidget {
  final DateTime currentStart, currentEnd;
  const _RescheduleDialogPeer({required this.currentStart, required this.currentEnd});
  @override
  State<_RescheduleDialogPeer> createState() => _RescheduleDialogPeerState();
}

class _RescheduleDialogPeerState extends State<_RescheduleDialogPeer> {
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

  String _fmtTime(TimeOfDay t) => DateFormat.jm().format(DateTime(2025,1,1,t.hour, t.minute));

  Future<void> _pickDate() async {
    final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (p != null) setState(() => _date = p);
  }
  Future<void> _pickTime(bool isStart) async {
    final p = await showTimePicker(context: context, initialTime: isStart ? _startTod : _endTod);
    if (p != null) setState(() => isStart ? _startTod = p : _endTod = p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Propose Reschedule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: const Text('New Date'), subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)),
          Row(children: [
            Expanded(child: ListTile(dense: true, title: const Text('Start'), subtitle: Text(_fmtTime(_startTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(true)))),
            Expanded(child: ListTile(dense: true, title: const Text('End'), subtitle: Text(_fmtTime(_endTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(false)))),
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
        }, child: const Text('Propose Change')),
      ],
    );
  }
}


/* ------------------------------- helpers ------------------------------- */

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}