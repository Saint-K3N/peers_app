// lib/admin_home_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderAdmin(
                onLogout: () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (_) {}
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                  }
                },
              ),
              const SizedBox(height: 16),
              const _GreetingCardAdminFirebase(),
              const SizedBox(height: 20),
              Text('Quick Actions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              const _AdminQuickActionsGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------------- Header --------------------------------- */

class _HeaderAdmin extends StatelessWidget {
  final VoidCallback onLogout;
  const _HeaderAdmin({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
            Text('Admin', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onLogout,
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

/* -------------------- Greeting + small stats (from Firebase) -------------------- */

class _GreetingCardAdminFirebase extends StatelessWidget {
  const _GreetingCardAdminFirebase();

  String _pickName(User? user, Map<String, dynamic>? udoc) {
    final full = (udoc?['fullName'] ?? udoc?['name'] ?? udoc?['displayName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    if (user?.displayName?.trim().isNotEmpty == true) return user!.displayName!.trim();
    if (user?.email?.trim().isNotEmpty == true) return user!.email!.trim();
    return 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid;

    // Make the stream explicitly typed and nullable
    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocStream = uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    final activeUsersQ = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: 'active');
    final pendingAppsQ = FirebaseFirestore.instance
        .collection('peer_applications')
        .where('status', isEqualTo: 'pending');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream, //
      builder: (context, userSnap) {
        final name = _pickName(authUser, userSnap.data?.data());

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
              Text('Hello, $name!',
                  style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Ready to manage PEERS?',
                  style: t.bodyMedium?.copyWith(color: Colors.white.withOpacity(.9))),
              const SizedBox(height: 16),

              // Two live stat tiles
              Row(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: activeUsersQ.snapshots(),
                      builder: (context, snap) {
                        final val = snap.hasData ? '${snap.data!.docs.length}' : '—';
                        return _StatTile(value: val, label: 'Active Users');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: pendingAppsQ.snapshots(),
                      builder: (context, snap) {
                        final val = snap.hasData ? '${snap.data!.docs.length}' : '—';
                        return _StatTile(value: val, label: 'Pending Applications');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

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
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 2,
              style: t.labelLarge?.copyWith(color: Colors.white.withOpacity(.95)),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------ Quick Actions ------------------------------ */

class _AdminQuickActionsGrid extends StatelessWidget {
  const _AdminQuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final items = <_AdminAction>[
      _AdminAction(
        color: const Color(0xFFE3F2FD),
        iconColor: const Color(0xFF1565C0),
        icon: Icons.menu_book_outlined,
        label: 'Past Year\nRepository',
        route: '/admin/repository',
      ),
      _AdminAction(
        color: const Color(0xFFE6FFFB),
        iconColor: const Color(0xFF159C8C),
        icon: Icons.group_add_outlined,
        label: 'Manage\nUsers',
        route: '/admin/users',
      ),
      _AdminAction(
        color: const Color(0xFFFFF3CD),
        iconColor: const Color(0xFF8A6D3B),
        icon: Icons.fact_check_outlined,
        label: 'Review\nApplication',
        route: '/admin/review-applications',
      ),
      _AdminAction(
        color: const Color(0xFFF0D6D6),
        iconColor: const Color(0xFF6D2B2B),
        icon: Icons.sell_outlined,
        label: 'Interests\nTopics',
        route: '/admin/interests',
      ),
      _AdminAction(
        color: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF2E7D32),
        icon: Icons.account_balance_outlined,
        label: 'Manage\nFaculty',
        route: '/admin/faculty',
      ),
      _AdminAction(
        color: const Color(0xFFF8D7DA),
        iconColor: const Color(0xFFB71C1C),
        icon: Icons.report_gmailerrorred_outlined,
        label: 'Review\nReports',
        route: '/admin/reports',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 74,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) => _AdminActionTile(item: items[i]),
    );
  }
}

class _AdminAction {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String label;
  final String route;
  const _AdminAction({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.route,
  });
}

class _AdminActionTile extends StatelessWidget {
  final _AdminAction item;
  const _AdminActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pushNamed(context, item.route),
      child: Ink(
        decoration: BoxDecoration(
          color: item.color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, color: item.iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
