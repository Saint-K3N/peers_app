import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'student_booking_info_page.dart';

class StudentHomePage extends StatelessWidget {
  const StudentHomePage({super.key});

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

              _GreetingCardLoader(uid: uid),

              const SizedBox(height: 20),
              Text('Quick Actions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              const _QuickActionsGrid(),
              const SizedBox(height: 20),

              Text("Your Appointments", style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),

              if (uid.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Text('Please sign in to see your appointments.'),
                )
              else
                _AppointmentsList(uid: uid),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------------------------- Header ----------------------------- */

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;

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
            style: textTheme.labelMedium?.copyWith(
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
            Text('Student', style: textTheme.titleMedium),
            Text('Portal', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            Navigator.pushNamed(context, '/student/personal_profile');
          },
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF9E9E9E),
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ],
    );
  }
}

/* ---------------------- Greeting / Stats + Role Counts --------------------- */

class _GreetingCardLoader extends StatelessWidget {
  final String uid;
  const _GreetingCardLoader({required this.uid});

  String _pickString(Map<String, dynamic> m, List<String> keys) {
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

  Future<Map<String, String>> _helperRolesByIds(Set<String> helperIds) async {
    if (helperIds.isEmpty) return {};
    final appsCol = FirebaseFirestore.instance.collection('peer_applications');

    final ids = helperIds.toList();
    final Map<String, String> out = {};

    // batch in <=10 chunks for whereIn
    for (int i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10);
      try {
        final snap = await appsCol.where('userId', whereIn: chunk).where('status', isEqualTo: 'approved').get();
        for (final d in snap.docs) {
          final m = d.data();
          final uid = (m['userId'] ?? '').toString();
          final raw = (m['requestedRole'] ?? '').toString().toLowerCase();
          out[uid] = raw;
        }
      } catch (_) {}
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const _GreetingCard(
        userName: 'Student',
        upcoming: 0,
        completed: 0,
        upcomingTutors: 0,
        upcomingCounsellors: 0,
      );
    }

    final userDocStream =
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    final apptsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('studentId', isEqualTo: uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, userSnap) {
        var name = 'Student';
        if (userSnap.hasData && userSnap.data != null) {
          final um = userSnap.data!.data() ?? {};
          final picked = _pickString(um, const [
            'fullName', 'full_name', 'name', 'displayName', 'display_name'
          ]);
          if (picked.isNotEmpty) name = picked;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: apptsStream,
          builder: (context, apptSnap) {
            final docs = apptSnap.data?.docs ?? const [];
            int upcoming = docs.where((d) => ['pending', 'confirmed'].contains((d['status'] ?? '').toString().toLowerCase())).length;
            int completed = docs.where((d) => (d['status'] ?? '').toString().toLowerCase() == 'completed').length;
            final upcomingDocs = docs.where((d) => ['pending', 'confirmed'].contains((d['status'] ?? '').toString().toLowerCase())).toList();
            final Set<String> helperIds = upcomingDocs.map((d) => (d['helperId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();

            return FutureBuilder<Map<String, String>>(
              future: _helperRolesByIds(helperIds),
              builder: (context, roleSnap) {
                int upcomingTutors = 0;
                int upcomingCounsellors = 0;
                final roles = roleSnap.data ?? const {};

                for (final d in upcomingDocs) {
                  final hid = (d['helperId'] ?? '').toString();
                  // ** Read role from appointment first, then fall back to roles map
                  final role = (d['role'] as String?) ?? roles[hid] ?? 'peer_tutor';
                  if (role == 'peer_counsellor') {
                    upcomingCounsellors++;
                  } else {
                    upcomingTutors++;
                  }
                }

                return _GreetingCard(
                  userName: name,
                  upcoming: upcoming,
                  completed: completed,
                  upcomingTutors: upcomingTutors,
                  upcomingCounsellors: upcomingCounsellors,
                );
              },
            );
          },
        );
      },
    );
  }
}


class _GreetingCard extends StatelessWidget {
  final String userName;
  final int upcoming;
  final int completed;

  final int upcomingTutors;
  final int upcomingCounsellors;

  const _GreetingCard({
    required this.userName,
    required this.upcoming,
    required this.completed,
    required this.upcomingTutors,
    required this.upcomingCounsellors,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hello, $userName!', style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Ready to start your day?', style: t.bodyMedium?.copyWith(color: Colors.white.withOpacity(.9))),
          if (upcomingTutors > 0 || upcomingCounsellors > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Upcoming by role — Tutors: $upcomingTutors • Counsellors: $upcomingCounsellors',
              style: t.bodySmall?.copyWith(color: Colors.white.withOpacity(.95)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatTile(value: '$upcoming', label: 'Upcoming Appointments')),
              const SizedBox(width: 12),
              Expanded(child: _StatTile(value: '$completed', label: 'Completed Appointments')),
            ],
          ),
        ],
      ),
    );
  }
}

/* ------------------------------ Stats Tile ------------------------------ */

class _StatTile extends StatelessWidget {
  final String value;
  final String label;

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
  }
}

/* ------------------------------ Quick Actions ------------------------------ */

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final items = <_QuickAction>[
      _QuickAction(color: const Color(0xFFE3F2FD), iconColor: const Color(0xFF1565C0), icon: Icons.search, label: 'Find Tutor', route: '/student/find-help', args: const {'initialTab': 0}),
      _QuickAction(color: const Color(0xFFE6FFFB), iconColor: const Color(0xFF159C8C), icon: Icons.psychology_alt_outlined, label: 'Find Counsellor', route: '/student/find-help', args: const {'initialTab': 1}),
      _QuickAction(color: const Color(0xFFFFF3CD), iconColor: const Color(0xFF8A6D3B), icon: Icons.show_chart, label: 'Progress', route: '/student/progress'),
      _QuickAction(color: const Color(0xFFFDE7EF), iconColor: const Color(0xFFAD1457), icon: Icons.menu_book_outlined, label: 'Past Year Papers', route: '/student/past-papers'),
      _QuickAction(color: const Color(0xFFE8F5E9), iconColor: const Color(0xFF2E7D32), icon: Icons.fact_check_outlined, label: 'Review Applications', route: '/student/review-applications'),
      _QuickAction(color: const Color(0xFFF3E5F5), iconColor: const Color(0xFF6A1B9A), icon: Icons.person_add_alt_1_outlined, label: 'Apply to be a Peer', route: '/student/apply-peer'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 74, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemBuilder: (context, i) => _QuickActionTile(item: items[i]),
    );
  }
}

class _QuickAction {
  final Color color, iconColor; final IconData icon; final String label, route; final Object? args;
  const _QuickAction({required this.color, required this.iconColor, required this.icon, required this.label, required this.route, this.args});
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
        decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 6, offset: const Offset(0, 3))]),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(height: 38, width: 38, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: Icon(item.icon, color: item.iconColor)),
            const SizedBox(width: 10),
            Expanded(child: Text(item.label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

/* ------------------------------- Appointments ------------------------------ */

class _AppointmentsList extends StatelessWidget {
  final String uid;
  const _AppointmentsList({required this.uid});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('appointments').where('studentId', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red)));

        final now = DateTime.now();
        final docs = (snap.data?.docs ?? const [])
            .where((d) {
          final status = (d.data()['status'] ?? '').toString().toLowerCase();
          if(status == 'completed') return false; // Hide completed
          final endTs = d.data()['endAt'];
          return endTs is Timestamp ? endTs.toDate().isAfter(now) : true;
        })
            .toList()
          ..sort((a, b) {
            Timestamp? aTs = a.data()['startAt'];
            Timestamp? bTs = b.data()['startAt'];
            return (aTs?.millisecondsSinceEpoch ?? 0).compareTo(bTs?.millisecondsSinceEpoch ?? 0);
          });

        if (docs.isEmpty) return Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)), child: const Text('No upcoming appointments yet.'));

        return Column(children: [for (final d in docs) ...[ _AppointmentTile(appDoc: d), const SizedBox(height: 12)]]);
      },
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> appDoc;
  const _AppointmentTile({required this.appDoc});

  String _fmtDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
  String _fmtTime(TimeOfDay t) => DateFormat.jm().format(DateTime(2025,1,1,t.hour, t.minute));

  Future<void> _cancel(BuildContext context, {required String apptId, required DateTime start}) async {
    final isWithin24Hours = start.difference(DateTime.now()) < const Duration(hours: 24);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(isWithin24Hours: isWithin24Hours),
    );

    if (reason != null && reason.isNotEmpty && context.mounted) {
      await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
        'status': 'cancelled',
        'cancellationReason': reason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
    }
  }

  Future<void> _reschedule(BuildContext context, {required String apptId, required String helperId, required DateTime currentStart, required DateTime currentEnd}) async {
    if (currentStart.difference(DateTime.now()) < const Duration(hours: 24)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule not allowed within 24 hours.')));
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RescheduleDialog(currentStart: currentStart, currentEnd: currentEnd),
    );
    if(result == null || !context.mounted) return;

    final DateTime newStart = result['start'];
    final DateTime newEnd = result['end'];
    final String reason = result['reason'];

    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required to reschedule.')));
      return;
    }

    final snap = await FirebaseFirestore.instance.collection('appointments').where('helperId', isEqualTo: helperId).get();
    for(final d in snap.docs){
      if(d.id == apptId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase();
      if(status != 'pending' && status != 'confirmed') continue;
      final tsStart = m['startAt'];
      final tsEnd = m['endAt'];
      if(tsStart is Timestamp && tsEnd is Timestamp){
        if(tsStart.toDate().isBefore(newEnd) && tsEnd.toDate().isAfter(newStart)){
          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflicts with another booking.')));
          return;
        }
      }
    }

    await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
      'startAt': Timestamp.fromDate(newStart), 'endAt': Timestamp.fromDate(newEnd),
      'rescheduleReason': reason, 'previousStartAt': Timestamp.fromDate(currentStart),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescheduled.')));
  }

  @override
  Widget build(BuildContext context) {
    final m = appDoc.data();
    final helperId = (m['helperId'] ?? '').toString();
    final startTs = m['startAt'] as Timestamp?;
    final endTs = m['endAt'] as Timestamp?;
    final status = (m['status'] ?? 'pending').toString().toLowerCase();
    final location = (m['location'] ?? 'Campus').toString();
    final start = startTs?.toDate();
    final end = endTs?.toDate();
    final date = (start != null) ? _fmtDate(start) : '—';
    final time = (start != null && end != null) ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}' : '—';

    final (chipLabel, chipBg, chipFg) = switch (status) {
      'confirmed' => ('Confirmed', const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'completed' => ('Completed', const Color(0xFFC8F2D2), const Color(0xFF2E7D32)),
      'cancelled' => ('Cancelled', const Color(0xFFFFE0E0), const Color(0xFFD32F2F)),
      _ => ('Pending', Colors.grey.shade300, Colors.black87),
    };

    return FutureBuilder(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(helperId).get(),
        FirebaseFirestore.instance.collection('peer_applications').where('userId', isEqualTo: helperId).where('status', isEqualTo: 'approved').limit(1).get(),
      ]),
      builder: (context, snap) {
        String helperName = 'Helper', role = (m['role'] as String?) ?? 'peer_tutor', photoUrl = '';
        if (snap.hasData) {
          final userSnap = snap.data![0] as DocumentSnapshot<Map<String, dynamic>>;
          final appsSnap = snap.data![1] as QuerySnapshot<Map<String, dynamic>>;
          final userMap = userSnap.data() ?? {};
          helperName = (userMap['fullName'] ?? userMap['name'] ?? helperName).toString();
          photoUrl = (userMap['photoUrl'] ?? userMap['avatarUrl'] ?? '').toString();
          if (m['role'] == null && appsSnap.docs.isNotEmpty) role = (appsSnap.docs.first.data()['requestedRole'] ?? 'peer_tutor').toString();
        }

        final isTutor = role == 'peer_tutor';
        final title = isTutor ? 'Tutoring with $helperName' : 'Counselling with $helperName';
        final canReschedule = status != 'cancelled' && status != 'completed' && start != null && start.difference(DateTime.now()) >= const Duration(hours: 24);
        final canCancel = status != 'cancelled' && status != 'completed';

        return _ScheduleCard(
          avatarUrl: photoUrl, onAvatarTap: () {/* Navigate to peer profile */},
          icon: isTutor ? Icons.person_outline : Icons.psychology_alt_outlined,
          iconColor: isTutor ? Colors.black87 : const Color(0xFF2F8D46),
          title: title, date: date, time: time, venue: location,
          borderColor: isTutor ? Colors.transparent : const Color(0xFF2F8D46),
          chipLabel: chipLabel, chipColor: chipBg, chipTextColor: chipFg,
          showCancel: canCancel, showReschedule: canReschedule,
          onCancel: (start != null) ? () => _cancel(context, apptId: appDoc.id, start: start) : null,
          onReschedule: (start != null && end != null) ? () => _reschedule(context, apptId: appDoc.id, helperId: helperId, currentStart: start, currentEnd: end) : null,
          onTap: () => Navigator.pushNamed(context, '/student/booking-info', arguments: {'appointmentId': appDoc.id, 'helperId': helperId}),
        );
      },
    );
  }
}

/* ------------------------------ Card Widgets ------------------------------ */

class _ScheduleCard extends StatelessWidget {
  final String? avatarUrl; final VoidCallback? onAvatarTap;
  final IconData icon; final Color iconColor;
  final String title, date, time, venue;
  final Color borderColor;
  final String chipLabel; final Color chipColor, chipTextColor;
  final bool showCancel, showReschedule;
  final VoidCallback? onCancel, onReschedule, onTap;

  const _ScheduleCard({
    this.avatarUrl, this.onAvatarTap, required this.icon, required this.iconColor,
    required this.title, required this.date, required this.time, required this.venue,
    required this.borderColor, required this.chipLabel, required this.chipColor, required this.chipTextColor,
    required this.showCancel, required this.showReschedule, this.onCancel, this.onReschedule, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget leading = (avatarUrl != null && avatarUrl!.isNotEmpty)
        ? InkWell(onTap: onAvatarTap, borderRadius: BorderRadius.circular(24), child: Stack(clipBehavior: Clip.none, children: [ CircleAvatar(radius: 24, backgroundColor: Colors.grey.shade200, backgroundImage: NetworkImage(avatarUrl!)), Positioned(right: -2, bottom: -2, child: Container(height: 22, width: 22, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.black12)), alignment: Alignment.center, child: Icon(icon, color: iconColor, size: 14)))]))
        : Container(height: 48, width: 48, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: iconColor, width: 2), shape: BoxShape.circle), alignment: Alignment.center, child: Icon(icon, color: iconColor, size: 26));
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Ink(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor, width: borderColor == Colors.transparent ? 0.5 : 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: const Offset(0, 6))]),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        leading, const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [ Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))), _StatusChip(label: chipLabel, bg: chipColor, fg: chipTextColor)]),
          const SizedBox(height: 6),
          Text('Date: $date', style: t.bodySmall), Text('Time: $time', style: t.bodySmall), Text('Venue: $venue', style: t.bodySmall), const SizedBox(height: 8),
          if (showCancel || showReschedule) Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: [
            if (showReschedule) _SmallButton(label: 'Reschedule', color: const Color(0xFF1565C0), onPressed: onReschedule ?? (){}),
            if (showCancel) _SmallButton(label: 'Cancel', color: Colors.red, onPressed: onCancel ?? (){}),
          ])),
        ])),
      ]),
    )));
  }
}


class _StatusChip extends StatelessWidget {
  final String label; final Color bg, fg;
  const _StatusChip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withOpacity(.3))), child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)));
}

class _SmallButton extends StatelessWidget {
  final String label; final Color color; final VoidCallback onPressed;
  const _SmallButton({required this.label, required this.color, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(height: 34, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: onPressed, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
}

/* ------------------------------ Dialog Widgets (Copied from student_booking_info_page.dart) ------------------------------ */

class _CancelDialog extends StatefulWidget {
  final bool isWithin24Hours;
  const _CancelDialog({required this.isWithin24Hours});
  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reasonCtrl = TextEditingController();
  String? _selectedReason;
  final _predefinedReasons = ['Misclick', 'Too near to appointed date/time'];

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel Appointment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please provide a reason for cancellation.'),
          const SizedBox(height: 12),
          if (widget.isWithin24Hours)
            DropdownButtonFormField<String>(
              value: _selectedReason,
              hint: const Text('Select a reason'),
              items: _predefinedReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedReason = v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            )
          else
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(hintText: 'Reason for cancellation', border: OutlineInputBorder()),
              maxLines: 2,
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep')),
        FilledButton(onPressed: () {
          final reason = widget.isWithin24Hours ? _selectedReason : _reasonCtrl.text.trim();
          if (reason != null && reason.isNotEmpty) {
            Navigator.pop(context, reason);
          }
        }, child: const Text('Confirm Cancel')),
      ],
    );
  }
}

class _RescheduleDialog extends StatefulWidget {
  final DateTime currentStart, currentEnd;
  const _RescheduleDialog({required this.currentStart, required this.currentEnd});
  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
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
      title: const Text('Reschedule Appointment'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: const Text('Date'), subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)),
          Row(children: [
            Expanded(child: ListTile(dense: true, title: const Text('Start'), subtitle: Text(_fmtTime(_startTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(true)))),
            Expanded(child: ListTile(dense: true, title: const Text('End'), subtitle: Text(_fmtTime(_endTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(false)))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _reasonCtrl, decoration: const InputDecoration(hintText: 'Reason for rescheduling', border: OutlineInputBorder()), maxLines: 2),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: () {
          final start = DateTime(_date.year, _date.month, _date.day, _startTod.hour, _startTod.minute);
          final end = DateTime(_date.year, _date.month, _date.day, _endTod.hour, _endTod.minute);
          if (end.isBefore(start) || end.isAtSameMomentAs(start)) return;
          if (start.isBefore(DateTime.now())) return;
          Navigator.pop(context, {'start': start, 'end': end, 'reason': _reasonCtrl.text.trim()});
        }, child: const Text('Save')),
      ],
    );
  }
}