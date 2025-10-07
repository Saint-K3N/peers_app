// lib/peer_counsellor_booking_info_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      default:
        return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  Future<void> _markCompleted(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .get();
      final m = doc.data() ?? {};
      final ts = m['startAt'];
      if (ts is! Timestamp) return;
      final start = ts.toDate();

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

      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .update({
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Marked as completed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to complete: $e')));
      }
    }
  }

  Future<void> _markMissed(String id) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(id)
          .get();
      final m = doc.data() ?? {};
      final ts = m['startAt'];
      if (ts is! Timestamp) return;
      final start = ts.toDate();

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

  Future<void> _cancelWithReason(String id) async {
    // Enforce 24h rule against current stored start time
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .doc(id)
        .get();
    final m0 = snap.data() ?? {};
    final ts = m0['startAt'];
    DateTime? start;
    if (ts is Timestamp) start = ts.toDate();

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Please provide a reason:'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g., Health reasons, schedule conflict, etc.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final reason = ctrl.text.trim();
      if (reason.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a reason.')));
        }
        return;
      }
      try {
        // Cancel allowed only if >= 24h remain
        if (start == null ||
            start.difference(DateTime.now()) < const Duration(hours: 24)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                Text('Cancel not allowed within 24 hours of the appointment.')));
          }
          return;
        }

        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(id)
            .update({
          'status': 'cancelled',
          'cancellationReason': reason,
          'cancelledBy': 'counsellor',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking cancelled.')),
          );
          Navigator.maybePop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

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
              else if (notFound)
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

                    // Prefer mode/meetUrl if present, else location/venue
                    final mode = (m['mode'] ?? '').toString().toLowerCase();
                    final loc = () {
                      if (mode == 'online') {
                        final meet = (m['meetUrl'] ?? '').toString();
                        return meet.isNotEmpty ? 'Online ($meet)' : 'Online';
                      }
                      final v = (m['location'] ?? m['venue'] ?? '').toString();
                      return v.isNotEmpty ? v : 'Campus';
                    }();

                    final notes = (m['notes'] ?? '').toString();
                    final statusRaw =
                    (m['status'] ?? 'pending').toString().toLowerCase().trim();
                    final statusLbl = _statusLabel(statusRaw);
                    final (chipBg, chipFg) = _statusColors(statusRaw);
                    final studentId = (m['studentId'] ?? '').toString();

                    // Time-based flags
                    final now = DateTime.now();
                    final hasStart = start != null;
                    final canOutcome =
                        hasStart && !now.isBefore(start!); // after or at start
                    final canCancel = hasStart &&
                        now.isBefore(start!) &&
                        start!.difference(now) >= const Duration(hours: 24) &&
                        statusRaw != 'cancelled' &&
                        statusRaw != 'completed' &&
                        statusRaw != 'missed';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            _StudentInfoCard(studentId: studentId),
                            Positioned(
                              right: 12,
                              top: 12,
                              child: _Chip(label: statusLbl, bg: chipBg, fg: chipFg),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.maybePop(context),
                              child: const Text('Back'),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                // Cancel: only if >= 24h remain and before start
                                if (canCancel)
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red),
                                    onPressed: () =>
                                        _cancelWithReason(widget.appointmentId),
                                    child: const Text('Cancel Booking'),
                                  ),

                                // Outcomes after start time
                                if (canOutcome &&
                                    statusRaw != 'cancelled' &&
                                    statusRaw != 'completed' &&
                                    statusRaw != 'missed')
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor:
                                        const Color(0xFF2E7D32)),
                                    onPressed: () =>
                                        _markCompleted(widget.appointmentId),
                                    child: const Text('Session held'),
                                  ),
                                if (canOutcome &&
                                    statusRaw != 'cancelled' &&
                                    statusRaw != 'completed' &&
                                    statusRaw != 'missed')
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor:
                                        const Color(0xFF8A6D3B)),
                                    onPressed: () =>
                                        _markMissed(widget.appointmentId),
                                    child: const Text('Session missed'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
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

/* ---------------------------- Student Info Card --------------------------- */

class _StudentInfoCard extends StatelessWidget {
  final String studentId;
  const _StudentInfoCard({required this.studentId});

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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: (studentId.isEmpty)
          ? const Stream.empty()
          : FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? <String, dynamic>{};
        final name = _pick(m, const [
          'fullName',
          'full_name',
          'name',
          'displayName',
          'display_name'
        ]).ifEmpty('Student');
        final email = _pick(m, const ['email', 'emailAddress']).ifEmpty('—');
        final photoUrl =
        ((m['photoUrl'] ?? m['avatarUrl'] ?? '') as String).trim();

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
            Text('Student', style: t.labelSmall),
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
      },
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

/* ------------------------------- helpers ------------------------------- */

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
