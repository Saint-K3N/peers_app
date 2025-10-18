// lib/hop_home_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HopHomePage extends StatelessWidget {
  const HopHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 16),

              if (uid.isEmpty)
                const _GreetingCardHop(userName: 'HOP', tutors: 0, pendingApps: 0)
              else
                _GreetingLoaderHop(hopUid: uid),

              const SizedBox(height: 20),
              Text('Quick Actions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              const _QuickActions(),

              const SizedBox(height: 20),
              Text("Today's Schedule", style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),

              if (uid.isEmpty)
                _emptyBox('Sign in to see today\'s schedule.')
              else
                _TodayScheduleListHop(hopUid: uid),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _emptyBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(msg),
    );
  }
}

/* --------------------------------- Header --------------------------------- */

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;

    return Row(
      children: [
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
            style: t.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HOP', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => Navigator.pushNamed(context, '/hop/profile'),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF9E9E9E),
            backgroundImage: (user?.photoURL ?? '').isNotEmpty ? NetworkImage(user!.photoURL!) : null,
            child: (user?.photoURL ?? '').isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ],
    );
  }
}

/* ----------------------- Greeting / Stats (HOP) Card ---------------------- */

class _GreetingLoaderHop extends StatelessWidget {
  final String hopUid;
  const _GreetingLoaderHop({required this.hopUid});

  String _pickName(Map<String, dynamic> m) {
    for (final k in const ['fullName','full_name','name','displayName','display_name']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final p = m['profile'];
    if (p is Map) {
      for (final k in const ['fullName','full_name','name','displayName','display_name']) {
        final v = p[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return 'HOP';
  }

  @override
  Widget build(BuildContext context) {
    final usersCol = FirebaseFirestore.instance.collection('users');
    final appsCol  = FirebaseFirestore.instance.collection('peer_applications');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCol.doc(hopUid).snapshots(),
      builder: (context, userSnap) {
        final name = _pickName(userSnap.data?.data() ?? const {});

        final approvedQ = appsCol
            .where('requestedRole', isEqualTo: 'peer_tutor')
            .where('status', isEqualTo: 'approved');
        final pendingQ = appsCol
            .where('requestedRole', isEqualTo: 'peer_tutor')
            .where('status', isEqualTo: 'pending');

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: approvedQ.snapshots(),
          builder: (context, approvedSnap) {
            final tutors = approvedSnap.data?.docs.length ?? 0;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: pendingQ.snapshots(),
              builder: (context, pendingSnap) {
                final pending = pendingSnap.data?.docs.length ?? 0;
                return _GreetingCardHop(userName: name, tutors: tutors, pendingApps: pending);
              },
            );
          },
        );
      },
    );
  }
}

class _GreetingCardHop extends StatelessWidget {
  final String userName;
  final int tutors;
  final int pendingApps;

  const _GreetingCardHop({
    required this.userName,
    required this.tutors,
    required this.pendingApps,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFD1C4E9), Color(0xFFBA68C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hello, $userName!',
              style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Ready to oversee your tutoring program?',
              style: t.bodyMedium?.copyWith(color: Colors.white.withOpacity(.9))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatTile(value: '$tutors', label: 'Tutors')),
              const SizedBox(width: 12),
              Expanded(child: _StatTile(value: '$pendingApps', label: 'Pending Applications')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value, label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value,
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 3,
            child: Text(label,
                maxLines: 2, style: t.labelLarge?.copyWith(color: Colors.white.withOpacity(.95))),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------ Quick Actions ----------------------------- */

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                color: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF1565C0),
                icon: Icons.event_note_outlined,
                label: 'Scheduling',
                onTap: () => Navigator.pushNamed(context, '/hop/scheduling'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionTile(
                color: const Color(0xFFE6FFFB),
                iconColor: const Color(0xFF159C8C),
                icon: Icons.group_outlined,
                label: 'My Tutors',
                onTap: () => Navigator.pushNamed(context, '/hop/my-tutors'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _QuickActionTile(
          color: const Color(0xFFFFECB3),
          iconColor: const Color(0xFF8A6D3B),
          icon: Icons.fact_check_outlined,
          label: 'Review Application',
          fullWidth: true,
          onTap: () => Navigator.pushNamed(context, '/hop/review-applications'),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final Color color, iconColor;
  final IconData icon;
  final String label;
  final bool fullWidth;
  final VoidCallback onTap;

  const _QuickActionTile({
    super.key,
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        width: double.infinity,
        height: 74,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: fullWidth ? MainAxisAlignment.start : MainAxisAlignment.start,
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ Today's Schedule -------------------------- */

class _TodayScheduleListHop extends StatelessWidget {
  final String hopUid;
  const _TodayScheduleListHop({required this.hopUid});

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final sod = _startOfDay(now);
    final eod = _endOfDay(now);

    // Query appointments where HOP is the booker
    final stream = FirebaseFirestore.instance
        .collection('appointments')
        .where('bookerId', isEqualTo: hopUid)
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(sod))
        .where('startAt', isLessThanOrEqualTo: Timestamp.fromDate(eod))
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        final docs = (snap.data?.docs ?? const [])
            .where((d) {
          final m = d.data();
          final status = (m['status'] ?? '').toString().toLowerCase().trim();
          // Show active appointments (not terminal states)
          return status == 'pending' || status == 'confirmed' ||
              status == 'pending_reschedule_hop' || status == 'pending_reschedule_peer';
        })
            .toList()
          ..sort((a, b) {
            int aMs = 0, bMs = 0;
            final aTs = a.data()['startAt'];
            final bTs = b.data()['startAt'];
            if (aTs is Timestamp) aMs = aTs.toDate().millisecondsSinceEpoch;
            if (bTs is Timestamp) bMs = bTs.toDate().millisecondsSinceEpoch;
            return aMs.compareTo(bMs);
          });

        if (docs.isEmpty) {
          return HopHomePage._emptyBox("No appointments for today.");
        }

        return Column(
          children: [
            for (final d in docs) ...[
              _HopScheduleTile(appDoc: d),
              const SizedBox(height: 12),
            ]
          ],
        );
      },
    );
  }
}

/* ------------------------------ Schedule Tile ----------------------------- */

class _HopScheduleTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> appDoc;
  const _HopScheduleTile({required this.appDoc});

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  (Color border, Color dot, String chip, Color chipBg, Color chipFg) _styleFor(String status) {
    switch (status) {
      case 'pending':
        return (const Color(0xFF2F8D46), const Color(0xFF2F8D46), 'Awaiting Confirmation',
        const Color(0xFFC9F2D9), const Color(0xFF1B5E20));
      case 'confirmed':
        return (const Color(0xFF2F8D46), const Color(0xFF2F8D46), 'Scheduled',
        const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'pending_reschedule_hop':
        return (const Color(0xFF8A6D3B), const Color(0xFF8A6D3B), 'Reschedule Pending',
        const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      case 'pending_reschedule_peer':
        return (const Color(0xFFEF6C00), const Color(0xFFEF6C00), 'Confirm Reschedule?',
        const Color(0xFFFFCC80), const Color(0xFFEF6C00));
      case 'cancelled':
        return (const Color(0xFFE53935), const Color(0xFFE53935), 'Cancelled',
        const Color(0xFFFFCDD2), const Color(0xFFC62828));
      default:
        return (const Color(0xFF6B7280), const Color(0xFF6B7280), 'Pending',
        const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  Future<void> _updateStatus(BuildContext context, String id, String status, {String? cancellationReason}) async {
    try {
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $status.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<String?> _getReason(BuildContext context, String action) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty || reason.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason (max 20 characters) is required.')));
                return;
              }
              Navigator.pop(context, reason);
            },
            child: Text('Confirm $action'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _confirmCancel(BuildContext context, Map<String, dynamic> m) async {
    final startTs = m['startAt'] as Timestamp?;
    final start = startTs?.toDate();

    if (start == null) return;

    final status = (m['status'] ?? '').toString().toLowerCase();
    final canCancel = status == 'pending' || status == 'confirmed';

    if (!canCancel) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot cancel this appointment.')),
        );
      }
      return;
    }

    final reason = await _getReason(context, 'Cancel');
    if (reason == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _updateStatus(context, appDoc.id, 'cancelled', cancellationReason: reason);
    }
  }

  Future<void> _acceptReschedule(BuildContext context, Map<String, dynamic> m) async {
    final propStart = m['proposedStartAt'] as Timestamp?;
    final propEnd = m['proposedEndAt'] as Timestamp?;

    if (propStart == null || propEnd == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule data incomplete.')),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('appointments').doc(appDoc.id).set({
      'status': 'confirmed',
      'startAt': propStart,
      'endAt': propEnd,
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonHop': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reschedule accepted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = appDoc.data();

    final helperId = (m['helperId'] ?? '').toString();
    final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();

    final startTs = m['startAt'] as Timestamp?;
    final endTs   = m['endAt'] as Timestamp?;
    final start   = startTs?.toDate();
    final end     = endTs?.toDate();

    final date = (start != null) ? _fmtDate(start) : '—';
    final time = (start != null && end != null)
        ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}'
        : '—';

    final venue = (() {
      final mode = (m['mode'] ?? '').toString().toLowerCase();
      if (mode == 'online') {
        final meet = (m['meetUrl'] ?? '').toString();
        return meet.isNotEmpty ? 'Online ($meet)' : 'Online (Video Call)';
      }
      final v = (m['venue'] ?? m['location'] ?? '').toString();
      return v.isNotEmpty ? v : 'Campus';
    })();

    final (border, dot, chipText, chipBg, chipFg) = _styleFor(status);

    // HOP BUSINESS LOGIC (Conditions 1, 2, 3)
    final now = DateTime.now();
    final hoursUntil = start != null ? start.difference(now).inHours : 0;
    final isWithin24Hours = hoursUntil <= 24;
    final isPending = status == 'pending';
    final isConfirmed = status == 'confirmed';
    final isPendingReschedulePeer = status == 'pending_reschedule_peer';

    bool canCancel = false;
    bool showAcceptReschedule = false;

    if (start != null && start.isAfter(now)) {
      if (isPending || isConfirmed) {
        // Can always cancel pending or confirmed with reason
        canCancel = true;
      } else if (isPendingReschedulePeer) {
        // Peer proposed reschedule
        showAcceptReschedule = true;
        canCancel = true;
      }
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(helperId).get(),
      builder: (context, userSnap) {
        final u = userSnap.data?.data() ?? const {};
        String tutorName = () {
          for (final k in ['fullName','full_name','name','displayName','display_name']) {
            final v = u[k];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          final p = u['profile'];
          if (p is Map) {
            for (final k in ['fullName','full_name','name','displayName','display_name']) {
              final v = p[k];
              if (v is String && v.trim().isNotEmpty) return v.trim();
            }
          }
          return 'Tutor';
        }();

        final title = 'Tutor Meeting - $tutorName';

        final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: chipFg.withOpacity(.3)),
          ),
          child: Text(chipText, style: t.labelMedium?.copyWith(color: chipFg, fontWeight: FontWeight.w700)),
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: Offset(0, 6))],
          ),
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/hop/booking',
                arguments: {'appointmentId': appDoc.id},
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Stack(
                children: [
                  Positioned(
                    left: -2, top: 8,
                    child: Container(width: 14, height: 14, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 44, width: 44,
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black87, width: 2), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_outline, color: Colors.black87, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                                const SizedBox(width: 8),
                                Flexible(child: Align(alignment: Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: chip))),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Date: $date', style: t.bodySmall),
                            Text('Time: $time', style: t.bodySmall),
                            Text('Venue: $venue', style: t.bodySmall),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  if (showAcceptReschedule)
                                    SizedBox(
                                      height: 34,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF2E7D32),
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _acceptReschedule(context, m),
                                        child: const Text('Accept Reschedule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  if (canCancel)
                                    SizedBox(
                                      height: 34,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFFEF6C00),
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _confirmCancel(context, m),
                                        child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}