// lib/peer_tutor_home_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PeerTutorHomePage extends StatelessWidget {
  const PeerTutorHomePage({super.key});

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
                _GreetingCardTutor(
                  userName: 'Tutor',
                  upcoming: 0,
                  pending: 0,
                  onTapUpcoming: null,
                  onTapPending: null,
                )
              else
                _GreetingLoader(helperUid: uid),

              const SizedBox(height: 20),
              Text('Quick Actions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              const _QuickActionsGrid(),
              const SizedBox(height: 20),

              Text("Today's Schedule", style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),

              if (uid.isEmpty)
                _emptyBox('Sign in to see today\'s schedule.')
              else
                _TodayScheduleList(helperUid: uid),
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
        color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
      ),
      child: Text(msg),
    );
  }
}

/* --------------------------------- Header --------------------------------- */

class _Header extends StatelessWidget {
  const _Header();

  String _pickPhotoUrl(Map<String, dynamic> m) {
    String? from(Map<String, dynamic> x) {
      for (final k in const ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
        final v = x[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final direct = from(m);
    if (direct != null) return direct;

    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      final p = from(prof);
      if (p != null) return p;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid ?? '';

    Widget buildRow(String photoUrl) {
      return Row(
        children: [
          // Logo
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
              style: textTheme.labelMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Peer Tutor', style: textTheme.titleMedium),
              Text('Portal', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          // Profile avatar (tap to profile page)
          InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => Navigator.pushNamed(context, '/tutor/personal_profile'),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF9E9E9E),
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? const Icon(Icons.person, color: Colors.white, size: 20)
                  : null,
            ),
          ),
        ],
      );
    }

    if (uid.isEmpty) return buildRow(authUser?.photoURL ?? '');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data() ?? const <String, dynamic>{};
        final fromFirestore = _pickPhotoUrl(m);
        final photoUrl = fromFirestore.isNotEmpty
            ? fromFirestore
            : (authUser?.photoURL ?? '');
        return buildRow(photoUrl);
      },
    );
  }
}


/* ----------------------- Greeting / Stats (live from Firestore) ------------ */

class _GreetingLoader extends StatelessWidget {
  final String helperUid;
  const _GreetingLoader({required this.helperUid});

  String _pickName(Map<String, dynamic> m) {
    String pick(Map<String, dynamic> x, List<String> keys) {
      for (final k in keys) {
        final v = x[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final direct = pick(m, const ['fullName', 'full_name', 'name', 'displayName', 'display_name']);
    if (direct.isNotEmpty) return direct;

    final profile = (m['profile'] is Map) ? (m['profile'] as Map).cast<String, dynamic>() : null;
    if (profile != null) {
      final prof = pick(profile, const ['fullName', 'full_name', 'name', 'displayName', 'display_name']);
      if (prof.isNotEmpty) return prof;
    }
    return 'Tutor';
  }

  @override
  Widget build(BuildContext context) {
    final userDocStream = FirebaseFirestore.instance.collection('users').doc(helperUid).snapshots();
    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperUid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, userSnap) {
        final name = _pickName(userSnap.data?.data() ?? {});
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: appsStream,
          builder: (context, appsSnap) {
            int upcoming = 0; // confirmed & future
            int pending  = 0; // pending   & future
            final now = DateTime.now();

            for (final d in (appsSnap.data?.docs ?? const [])) {
              final m = d.data();
              final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();

              // consider future only (endAt if present, else startAt)
              DateTime? end;
              final endTs = m['endAt'];
              final startTs = m['startAt'];
              if (endTs is Timestamp) {
                end = endTs.toDate();
              } else if (startTs is Timestamp) {
                end = startTs.toDate();
              }
              final isFuture = (end == null) || end.isAfter(now);
              if (!isFuture) continue;

              if (status == 'pending') pending++;
              if (status == 'confirmed') upcoming++;
            }

            return _GreetingCardTutor(
              userName: name,
              upcoming: upcoming,
              pending: pending,
              onTapUpcoming: () => Navigator.pushNamed(
                context, '/tutor/appointments', arguments: {'filter': 'upcoming'},
              ),
              onTapPending: () => Navigator.pushNamed(
                context, '/tutor/appointments', arguments: {'filter': 'pending'},
              ),
            );
          },
        );
      },
    );
  }
}

class _GreetingCardTutor extends StatelessWidget {
  final String userName;
  final int upcoming;
  final int pending;
  final VoidCallback? onTapUpcoming;
  final VoidCallback? onTapPending;

  const _GreetingCardTutor({
    required this.userName,
    required this.upcoming,
    required this.pending,
    required this.onTapUpcoming,
    required this.onTapPending,
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hello, $userName!', style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Ready to guide your students?', style: t.bodyMedium?.copyWith(color: Colors.white.withOpacity(.9))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '$upcoming',
                  label: 'Upcoming (Confirmed)',
                  onTap: onTapUpcoming,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  value: '$pending',
                  label: 'Pending Requests',
                  onTap: onTapPending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _StatTile({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tile = Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.25), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(value, textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 3,
            child: Text(label, maxLines: 2, style: t.labelLarge?.copyWith(color: Colors.white.withOpacity(.95))),
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: tile);
  }
}

/* ------------------------------ Quick Actions ------------------------------ */

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final items = <_QuickAction>[
      _QuickAction(
        color: const Color(0xFFE3F2FD), iconColor: const Color(0xFF1565C0),
        icon: Icons.event_note_outlined, label: 'Scheduling', route: '/tutor/scheduling',
      ),
      _QuickAction(
        color: const Color(0xFFE6FFFB), iconColor: const Color(0xFF159C8C),
        icon: Icons.group_add_outlined, label: 'My Students', route: '/tutor/students',
      ),
      _QuickAction(
        color: const Color(0xFFE3F2FD),
        iconColor: const Color(0xFF1565C0),
        icon: Icons.menu_book_outlined,
        label: 'Past Year\nRepository',
        route: '/tutor/pas_paper',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisExtent: 74, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) => _QuickActionTile(item: items[i]),
    );
  }
}

class _QuickAction {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String label;
  final String route;
  final Object? args;
  const _QuickAction({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.route,
    this.args,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction item;
  const _QuickActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pushNamed(context, item.route, arguments: item.args),
      child: Ink(
        decoration: BoxDecoration(
          color: item.color, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                height: 38, width: 38,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(item.icon, color: item.iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(item.label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------------------- Today's Schedule List ------------------------ */

class _TodayScheduleList extends StatelessWidget {
  final String helperUid;
  const _TodayScheduleList({required this.helperUid});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        final now = DateTime.now();
        final docs = (snap.data?.docs ?? const [])
            .where((d) {
          final m = d.data();
          final startTs = m['startAt'];
          if (startTs is! Timestamp) return false;
          final dt = startTs.toDate();
          final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;

          final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();
          // show "active" items (pending/confirmed) even if earlier today (to allow outcomes)
          final active = status == 'pending' || status == 'confirmed';
          return sameDay && active;
        })
            .toList()
          ..sort((a, b) {
            int aMillis = 0, bMillis = 0;
            final aTs = a.data()['startAt'];
            final bTs = b.data()['startAt'];
            if (aTs is Timestamp) aMillis = aTs.toDate().millisecondsSinceEpoch;
            if (bTs is Timestamp) bMillis = bTs.toDate().millisecondsSinceEpoch;
            return aMillis.compareTo(bMillis);
          });

        if (docs.isEmpty) {
          return PeerTutorHomePage._emptyBox("No appointments for today.");
        }

        return Column(
          children: [
            for (final d in docs) ...[
              _TutorScheduleTile(appDoc: d),
              const SizedBox(height: 12),
            ]
          ],
        );
      },
    );
  }
}

/* ------------------------------ Schedule Tile ----------------------------- */

class _TutorScheduleTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> appDoc;
  const _TutorScheduleTile({required this.appDoc});

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  /* -------------------- Shared Firestore helpers -------------------- */

  Future<void> _updateStatus(BuildContext context, String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('appointments').doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to $status.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _markCompleted(BuildContext context, String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('appointments').doc(id).get();
      final m = doc.data() ?? {};
      final ts = m['startAt'];
      if (ts is! Timestamp) return;
      final start = ts.toDate();
      if (DateTime.now().isBefore(start)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can mark outcome only after the appointment time.')),
          );
        }
        return;
      }
      await _updateStatus(context, id, 'completed');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _markMissed(BuildContext context, String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('appointments').doc(id).get();
      final m = doc.data() ?? {};
      final ts = m['startAt'];
      if (ts is! Timestamp) return;
      final start = ts.toDate();
      if (DateTime.now().isBefore(start)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can mark outcome only after the appointment time.')),
          );
        }
        return;
      }
      await _updateStatus(context, id, 'missed');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<bool> _hasOverlap({
    required String helperId,
    required DateTime startDt,
    required DateTime endDt,
    required String excludeId,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .limit(500)
        .get();

    for (final d in snap.docs) {
      if (d.id == excludeId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status != 'pending' && status != 'confirmed') continue;
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

  /* -------------------- Actions with policy guards -------------------- */

  Future<void> _reschedule(BuildContext context, Map<String, dynamic> m) async {
    final apptId   = appDoc.id;
    final helperId = (m['helperId'] ?? '').toString();

    final origStart = (m['startAt'] is Timestamp) ? (m['startAt'] as Timestamp).toDate() : null;
    final origEnd   = (m['endAt']   is Timestamp) ? (m['endAt']   as Timestamp).toDate() : null;

    // Block reschedule if within 24 hours of the ORIGINAL start
    if (origStart != null && origStart.difference(DateTime.now()) < const Duration(hours: 24)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours of the appointment.')),
        );
      }
      return;
    }

    DateTime date = origStart ?? DateTime.now();
    TimeOfDay startTod = TimeOfDay.fromDateTime(origStart ?? DateTime.now());
    TimeOfDay endTod   = TimeOfDay.fromDateTime(
      (origEnd ?? (origStart ?? DateTime.now()).add(const Duration(hours: 1))),
    );

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) date = picked;
    }

    Future<void> pickTime(bool start) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: start ? startTod : endTod,
      );
      if (picked != null) {
        if (start) startTod = picked; else endTod = picked;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          String fmt(DateTime d) => _fmtDate(d);
          String fmtT(TimeOfDay t) => _fmtTime(t);

          return AlertDialog(
            title: const Text('Reschedule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Date'),
                  subtitle: Text(fmt(date)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () async { await pickDate(); setStateDlg((){}); },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('Start'),
                        subtitle: Text(fmtT(startTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async { await pickTime(true); setStateDlg((){}); },
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('End'),
                        subtitle: Text(fmtT(endTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async { await pickTime(false); setStateDlg((){}); },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      final startDt = DateTime(date.year, date.month, date.day, startTod.hour, startTod.minute);
      final endDt   = DateTime(date.year, date.month, date.day, endTod.hour, endTod.minute);

      // Prevent rescheduling into the past
      if (!startDt.isAfter(DateTime.now())) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New start time must be in the future.')),
          );
        }
        return;
      }

      // End after start
      if (!endDt.isAfter(startDt)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start.')));
        }
        return;
      }

      // Overlap guard
      if (await _hasOverlap(helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflicts with another booking.')));
        }
        return;
      }

      try {
        await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
          'startAt': Timestamp.fromDate(startDt),
          'endAt': Timestamp.fromDate(endDt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescheduled successfully.')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reschedule failed: $e')));
        }
      }
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    // Enforce 24h rule
    final m = appDoc.data();
    final startTs = m['startAt'] as Timestamp?;
    final start = startTs?.toDate();

    if (start == null || start.difference(DateTime.now()) < const Duration(hours: 24)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancel not allowed within 24 hours of the appointment.')),
        );
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _updateStatus(context, appDoc.id, 'cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = appDoc.data();

    final studentId = (m['studentId'] ?? '').toString();
    final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();

    final startTs = m['startAt'] as Timestamp?;
    final endTs   = m['endAt'] as Timestamp?;
    final start   = startTs?.toDate();
    final end     = endTs?.toDate();

    final date = (start != null) ? _fmtDate(start) : '—';
    final time = (start != null && end != null)
        ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}'
        : '—';

    // venue/mode resolving
    final mode = (m['mode'] ?? '').toString().toLowerCase();
    final venue = () {
      if (mode == 'online') {
        final meet = (m['meetUrl'] ?? '').toString();
        return meet.isNotEmpty ? 'Online ($meet)' : 'Online (Video Call)';
      }
      final v = (m['venue'] ?? m['location'] ?? '').toString();
      return v.isNotEmpty ? v : 'Campus';
    }();

    // Chip visuals
    final (chipLabel, chipBg, chipFg) = switch (status) {
      'pending'   => ('Confirmation Pending',   const Color(0xFFEDEEF1), const Color(0xFF6B7280)),
      'confirmed' => ('Confirmed', const Color(0xFFC9F2D9), const Color(0xFF1B5E20)),
      'cancelled' => ('Cancelled', const Color(0xFFFFCDD2), const Color(0xFFC62828)),
      'completed' => ('Completed', const Color(0xFFC8F2D2), const Color(0xFF2E7D32)),
      'missed'    => ('Missed',    const Color(0xFFFFF3CD), const Color(0xFF8A6D3B)),
      _           => ('Pending',   const Color(0xFFEDEEF1), const Color(0xFF6B7280)),
    };

    // Time-based permissions
    final now = DateTime.now();
    final canConfirm = start != null && now.isBefore(start); // confirm only before start
    final canModify  = start != null && start!.difference(now) >= const Duration(hours: 24); // cancel/reschedule >=24h
    final canOutcome = start != null && !now.isBefore(start!); // after or at start time

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        final um = snap.data?.data() ?? const {};
        final studentName = _pickStudentName(um);
        final photoUrl = ((um['photoUrl'] ?? um['avatarUrl'] ?? '') as String).trim();
        final title = 'Session with $studentName';

        final isPending = status == 'pending';
        final isConfirmed = status == 'confirmed';
        final isTerminal = status == 'cancelled' || status == 'completed' || status == 'missed';

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isConfirmed
                  ? const Color(0xFF2F8D46)
                  : (status == 'cancelled' ? const Color(0xFFC62828) : Colors.transparent),
              width: isConfirmed || status == 'cancelled' ? 2 : 0.5,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left avatar (student)
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/tutor/students');
                },
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFEEEEEE),
                  backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                  child: (photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,
                ),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        _StatusChip(label: chipLabel, bg: chipBg, fg: chipFg),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Date: $date', style: Theme.of(context).textTheme.bodySmall),
                    Text('Time: $time', style: Theme.of(context).textTheme.bodySmall),
                    Text('Venue: $venue', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),

                    // Actions row with policy gates
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Confirm only before start & when pending
                        if (isPending && canConfirm)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _SmallButton(
                              label: 'Confirm',
                              color: const Color(0xFF2E7D32),
                              onPressed: () async {
                                if (!canConfirm) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('You can only confirm before the session starts.')),
                                    );
                                  }
                                  return;
                                }
                                await _updateStatus(context, appDoc.id, 'confirmed');
                              },
                            ),
                          ),

                        // Reschedule only if >=24h remain (pending or confirmed)
                        if ((isPending || isConfirmed) && canModify)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _SmallButton(
                              label: 'Reschedule',
                              color: const Color(0xFF1565C0),
                              onPressed: () => _reschedule(context, m),
                            ),
                          ),

                        // Cancel only if >=24h remain (not terminal)
                        if (!isTerminal && canModify)
                          Padding(
                            padding: const EdgeInsets.only(right: 0),
                            child: _SmallButton(
                              label: 'Cancel',
                              color: const Color(0xFFEF6C00),
                              onPressed: () => _confirmCancel(context),
                            ),
                          ),

                        // After start: outcomes (if not already terminal)
                        if (!isTerminal && canOutcome) ...[
                          const SizedBox(width: 8),
                          _SmallButton(
                            label: 'Class delivered',
                            color: const Color(0xFF2E7D32),
                            onPressed: () => _markCompleted(context, appDoc.id),
                          ),
                          const SizedBox(width: 8),
                          _SmallButton(
                            label: 'Class missed',
                            color: const Color(0xFF8A6D3B),
                            onPressed: () => _markMissed(context, appDoc.id),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _pickStudentName(Map<String, dynamic> m) {
    String pick(Map<String, dynamic> x, List<String> keys) {
      for (final k in keys) {
        final v = x[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }
    final direct = pick(m, const ['fullName','full_name','name','displayName','display_name']);
    if (direct.isNotEmpty) return direct;
    final profile = (m['profile'] is Map) ? (m['profile'] as Map).cast<String, dynamic>() : null;
    if (profile != null) {
      final p = pick(profile, const ['fullName','full_name','name','displayName','display_name']);
      if (p.isNotEmpty) return p;
    }
    return 'Student';
  }
}

/* ------------------------------- Status Chip ------------------------------ */

class _StatusChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _StatusChip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withOpacity(.3))),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _SmallButton({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
