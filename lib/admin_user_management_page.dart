// lib/admin_user_management_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/* --------------------------------- Models --------------------------------- */

enum UserRole {
  student,
  peerTutor,
  hop, // Head of Programme
  peerCounsellor,
  schoolCounsellor,
  admin,
}

class AppUser {
  String name;
  String id;           // studentId
  String email;
  String facultyId;    // from users.facultyId
  String facultyName;  // resolved via faculties/{id}.name
  UserRole role;
  String? uid;         // users/{uid}
  String? status;      // active/inactive

  AppUser({
    required this.name,
    required this.id,
    required this.email,
    required this.facultyId,
    required this.facultyName,
    required this.role,
    this.uid,
    this.status,
  });
}

/* ------------------------------ Main Stateful ------------------------------ */

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  State<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  String _search = '';
  String _selectedRoleFilter = 'All Roles';
  String _selectedFacultyFilter = 'All Faculties';

  String _roleToLabel(UserRole r) {
    switch (r) {
      case UserRole.student:
        return 'Student';
      case UserRole.peerTutor:
        return 'Peer Tutor';
      case UserRole.hop:
        return 'HOP';
      case UserRole.peerCounsellor:
        return 'Peer Counsellor';
      case UserRole.schoolCounsellor:
        return 'School Counsellor';
      case UserRole.admin:
        return 'Admin';
    }
  }

  UserRole _labelToRole(String label) {
    switch (label) {
      case 'Student':
        return UserRole.student;
      case 'Peer Tutor':
        return UserRole.peerTutor;
      case 'HOP':
        return UserRole.hop;
      case 'Peer Counsellor':
        return UserRole.peerCounsellor;
      case 'School Counsellor':
        return UserRole.schoolCounsellor;
      case 'Admin':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }

  String _storeRole(UserRole r) {
    switch (r) {
      case UserRole.student:
        return 'student';
      case UserRole.peerTutor:
        return 'peer_tutor';
      case UserRole.hop:
        return 'hop';
      case UserRole.peerCounsellor:
        return 'peer_counsellor';
      case UserRole.schoolCounsellor:
        return 'school_counsellor';
      case UserRole.admin:
        return 'admin';
    }
  }

  UserRole _readRole(String? s) {
    final key =
    (s ?? 'student').toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    switch (key) {
      case 'peertutor':
        return UserRole.peerTutor;
      case 'hop':
        return UserRole.hop;
      case 'peercounsellor':
      case 'peercounselor':
        return UserRole.peerCounsellor;
      case 'schoolcounsellor':
      case 'schoolcounselor':
      case 'counsellor':
      case 'counselor':
        return UserRole.schoolCounsellor;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }

  List<String> get _roleLabelsForFilter => const [
    'All Roles',
    'Student',
    'Peer Tutor',
    'HOP',
    'Peer Counsellor',
    'School Counsellor',
    'Admin',
  ];

  String _normEmail(String e) => e.trim().toLowerCase();

  Future<void> _updateUserRoleByEmail(
      String email, String newRoleLabel) async {
    // Only allow HOP or School Counsellor to be assigned from this screen
    if (newRoleLabel != 'HOP' && newRoleLabel != 'School Counsellor') return;

    final newRoleStored = _storeRole(_labelToRole(newRoleLabel));
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: _normEmail(email))
        .limit(1)
        .get();

    if (qs.docs.isNotEmpty) {
      await qs.docs.first.reference.update({
        'role': newRoleStored,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role updated to $newRoleLabel')),
      );
    }
  }

  /// Toggleable status helper
  Future<void> _setUserStatusByEmail(String email, String status) async {
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: _normEmail(email))
        .limit(1)
        .get();

    if (qs.docs.isNotEmpty) {
      await qs.docs.first.reference.update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('User ${status == 'active' ? 'activated' : 'deactivated'}')),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderBar(
                onBack: () => Navigator.maybePop(context),
                onLogout: _logout,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Management',
                          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search users, view current role, set role (HOP / School Counsellor), activate or deactivate accounts',
                          style: t.bodySmall,
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _SearchField(
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 10),

              // Load faculties once; drive filter + user list with it
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('faculties')
                    .orderBy('nameLower')
                    .snapshots(),
                builder: (context, facSnap) {
                  final facDocs = facSnap.data?.docs ?? const [];
                  final facultyIdToName = <String, String>{
                    for (final d in facDocs)
                      d.id: (d.data()['name'] ?? '').toString()
                  };

                  final facultyFilterItems = <String>[
                    'All Faculties',
                    ...facultyIdToName.values
                  ];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _DropdownPill<String>(
                              value: _selectedRoleFilter,
                              items: _roleLabelsForFilter,
                              onChanged: (v) =>
                                  setState(() => _selectedRoleFilter = v!),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DropdownPill<String>(
                              value: _selectedFacultyFilter,
                              items: facultyFilterItems,
                              onChanged: (v) =>
                                  setState(() => _selectedFacultyFilter = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stats (fixed parsing of counsellor roles)
                      _LiveStatsRow(roleLabel: (r) => _roleToLabel(r)),

                      const SizedBox(height: 16),
                      const _SectionLabel(text: 'Users'),
                      const SizedBox(height: 10),

                      _UsersFromFirestoreList(
                        search: _search,
                        roleFilter: _selectedRoleFilter,
                        facFilter: _selectedFacultyFilter,
                        onRoleChange: _updateUserRoleByEmail,
                        onToggleStatus: _setUserStatusByEmail, // <--- pass toggle
                        readRole: _readRole,
                        facultyIdToName: facultyIdToName,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------------- Widgets -------------------------------- */

class _HeaderBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _HeaderBar({required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        _IconSquare(onTap: onBack, icon: Icons.arrow_back),
        const SizedBox(width: 10),

        // PEERS logo square
        Container(
          height: 44,
          width: 44,
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
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Admin Portal label
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin', style: t.titleMedium),
            Text('Portal',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),

        const Spacer(),
        _IconSquare(onTap: onLogout, icon: Icons.logout),
      ],
    );
  }
}


class _IconSquare extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _IconSquare({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search users',
        prefixIcon: const Icon(Icons.search),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _DropdownPill<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  const _DropdownPill(
      {required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T>(
        isExpanded: true,
        underline: const SizedBox(),
        value: value,
        icon: const Icon(Icons.arrow_drop_down),
        items: items
            .map((e) => DropdownMenuItem<T>(value: e, child: Text('$e')))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/* ----------------------------- Live Users List ----------------------------- */

class _UsersFromFirestoreList extends StatelessWidget {
  final String search, roleFilter, facFilter;
  final Future<void> Function(String email, String newRoleLabel) onRoleChange;
  final Future<void> Function(String email, String status) onToggleStatus; // <--- NEW
  final UserRole Function(String? s) readRole;
  final Map<String, String> facultyIdToName;

  const _UsersFromFirestoreList({
    required this.search,
    required this.roleFilter,
    required this.facFilter,
    required this.onRoleChange,
    required this.onToggleStatus,
    required this.readRole,
    required this.facultyIdToName,
  });

  @override
  Widget build(BuildContext context) {
    final baseQuery =
    FirebaseFirestore.instance.collection('users').orderBy('fullName');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: baseQuery.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;

        List<AppUser> users = docs.map((d) {
          final data = d.data();
          final facultyId = (data['facultyId'] ?? '').toString().trim();
          final facultyName = facultyIdToName[facultyId] ?? '—';
          return AppUser(
            uid: d.id,
            name: (data['fullName'] ?? '') as String,
            id: (data['studentId'] ?? '') as String,
            email: (data['email'] ?? '') as String,
            facultyId: facultyId,
            facultyName: facultyName,
            role: readRole(data['role'] as String?),
            status: (data['status'] ?? 'active') as String?,
          );
        }).toList();

        final s = search.trim().toLowerCase();
        users = users.where((u) {
          final matchesSearch = s.isEmpty ||
              u.name.toLowerCase().contains(s) ||
              u.id.toLowerCase().contains(s) ||
              u.email.toLowerCase().contains(s);
          final matchesRole = roleFilter == 'All Roles' ||
              _roleToLabelStatic(u.role) == roleFilter;
          final matchesFac =
              facFilter == 'All Faculties' || u.facultyName == facFilter;
          return matchesSearch && matchesRole && matchesFac;
        }).toList();

        if (users.isEmpty) {
          return const Text('No users found.');
        }

        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Found ${users.length} users',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            for (final u in users) ...[
              _UserItemCard(
                user: u,
                onRoleChanged: (label) async {
                  if (label == null) return;
                  await onRoleChange(u.email, label);
                },
                onToggleStatus: onToggleStatus, // pass through
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  static String _roleToLabelStatic(UserRole r) {
    switch (r) {
      case UserRole.student:
        return 'Student';
      case UserRole.peerTutor:
        return 'Peer Tutor';
      case UserRole.hop:
        return 'HOP';
      case UserRole.peerCounsellor:
        return 'Peer Counsellor';
      case UserRole.schoolCounsellor:
        return 'School Counsellor';
      case UserRole.admin:
        return 'Admin';
    }
  }
}

/* ------------------------------ Live Stats Row ----------------------------- */

class _LiveStatsRow extends StatelessWidget {
  final String Function(UserRole) roleLabel;
  const _LiveStatsRow({required this.roleLabel});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('users');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final counts = <UserRole, int>{
          for (var r in UserRole.values) r: 0,
        };
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final roleStr = (d.data()['role'] ?? 'student').toString();
            final r = _read(roleStr);
            counts[r] = (counts[r] ?? 0) + 1;
          }
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatBox(count: counts[UserRole.student] ?? 0, label: 'Total Student'),
            _StatBox(count: counts[UserRole.peerTutor] ?? 0, label: 'Total Peer Tutor'),
            _StatBox(count: counts[UserRole.hop] ?? 0, label: 'Total HOP'),
            _StatBox(count: counts[UserRole.peerCounsellor] ?? 0, label: 'Total Peer Counsellor'),
            _StatBox(count: counts[UserRole.schoolCounsellor] ?? 0, label: 'Total School Counsellor'),
            _StatBox(count: counts[UserRole.admin] ?? 0, label: 'Total Admin'),
          ],
        );
      },
    );
  }

  UserRole _read(String s) {
    final key = s.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    switch (key) {
      case 'peertutor':
        return UserRole.peerTutor;
      case 'hop':
        return UserRole.hop;
      case 'peercounsellor':
      case 'peercounselor':
        return UserRole.peerCounsellor;
      case 'schoolcounsellor':
      case 'schoolcounselor':
      case 'counsellor':
      case 'counselor':
        return UserRole.schoolCounsellor;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }
}

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  const _StatBox({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 156,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Text('$count', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: t.bodySmall),
        ],
      ),
    );
  }
}

/* ------------------------------- User Card UI ------------------------------ */

class _UserItemCard extends StatelessWidget {
  final AppUser user;
  final ValueChanged<String?> onRoleChanged;
  final Future<void> Function(String email, String status) onToggleStatus;

  const _UserItemCard({
    required this.user,
    required this.onRoleChanged,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // Only allow HOP and School Counsellor assignments
    final allowedRoles = const ['HOP', 'School Counsellor','Student'];
    final currentLabel = _UsersFromFirestoreList._roleToLabelStatic(user.role);
    final dropdownValue = allowedRoles.contains(currentLabel) ? currentLabel : null;

    final isActive = (user.status ?? 'active') == 'active';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('ID: ${user.id}', style: t.bodySmall),
          Text(user.email, style: t.bodySmall),
          Text(user.facultyName, style: t.bodySmall), // resolved faculty name
          const SizedBox(height: 4),

          Row(
            children: [
              Text('Current role: ', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(currentLabel, style: t.bodySmall),
              if (!isActive) ...[
                const SizedBox(width: 8),
                Text('(inactive)', style: t.bodySmall?.copyWith(color: Colors.red)),
              ]
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              // Restricted role dropdown
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: dropdownValue,
                  underline: const SizedBox(),
                  hint: const Text("Set Role"),
                  items: allowedRoles
                      .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                      .toList(),
                  onChanged: onRoleChanged,
                ),
              ),
              const Spacer(),

              // Toggle Activate/Deactivate
              SizedBox(
                height: 36,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isActive ? Colors.red : Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => onToggleStatus(user.email, isActive ? 'inactive' : 'active'),
                  child: Text(isActive ? 'Deactivate' : 'Activate',
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
