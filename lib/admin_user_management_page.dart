// lib/admin_user_management_page.dart
//

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/* --------------------------------- Models --------------------------------- */

enum UserRole {
  student,
  peerTutor,
  hop,
  peerCounsellor,
  schoolCounsellor,
  admin,
}

class AppUser {
  String name;
  String id;
  String email;
  String facultyId;
  String facultyName;
  UserRole role;
  String? uid;
  String? status;

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
    // Confirmation dialog before role change
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change User Role'),
        content: Text(
          'Are you sure you want to change this user\'s role to $newRoleLabel?\n\n'
              'This will update their permissions and access level immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Change'),
          ),
        ],
      ),
    );

    if (ok != true) return;

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

  /// ✅ UPDATED: Toggleable status helper with email notification
  Future<void> _setUserStatusByEmail(String email, String status, String userName) async {
    // Double confirmation dialog
    final action = status == 'active' ? 'activate' : 'deactivate';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${action == 'activate' ? 'Activate' : 'Deactivate'} User Account'),
        content: Text(
          'Are you sure you want to $action the account for $userName?\n\n'
              '${status == 'inactive' ? '⚠️ They will lose access to their account and must contact admin to regain access.' : '✅ They will regain full access to their account.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status == 'inactive' ? Colors.red : Colors.green,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm ${action == 'activate' ? 'Activate' : 'Deactivate'}'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: _normEmail(email))
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        throw Exception('User not found');
      }

      final userDoc = qs.docs.first;

      // Update user status
      await userDoc.reference.update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'inactive') 'deactivatedAt': FieldValue.serverTimestamp(),
        if (status == 'inactive') 'deactivatedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // ✅ NEW: Send email notification if deactivating
      if (status == 'inactive' && email.isNotEmpty) {
        await _sendDeactivationEmail(email, userName);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                status == 'active' ? Icons.check_circle : Icons.block,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status == 'active'
                      ? 'User activated successfully'
                      : 'User deactivated and notification sent',
                ),
              ),
            ],
          ),
          backgroundColor: status == 'active' ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update user status: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// ✅ NEW: Send deactivation email notification
  Future<void> _sendDeactivationEmail(String userEmail, String userName) async {
    try {
      await FirebaseFirestore.instance.collection('mail').add({
        'to': userEmail,
        'message': {
          'subject': 'PEERS Account Deactivated',
          'html': '''
            <!DOCTYPE html>
            <html>
            <head>
              <style>
                body { 
                  font-family: Arial, sans-serif; 
                  line-height: 1.6; 
                  color: #333; 
                  margin: 0; 
                  padding: 0; 
                }
                .container { 
                  max-width: 600px; 
                  margin: 0 auto; 
                  background: white;
                }
                .header { 
                  background: linear-gradient(135deg, #B388FF, #7C4DFF); 
                  color: white; 
                  padding: 30px; 
                  text-align: center; 
                }
                .content { 
                  padding: 30px; 
                  background: #f9f9f9; 
                }
                .info-box { 
                  background: white; 
                  border-left: 4px solid #7C4DFF; 
                  padding: 15px; 
                  margin: 20px 0; 
                }
                .warning-box {
                  background: #fff3cd;
                  border-left: 4px solid #ffc107;
                  padding: 15px;
                  margin: 20px 0;
                }
                .footer { 
                  text-align: center; 
                  padding: 20px; 
                  color: #666; 
                  font-size: 12px; 
                }
                ul { 
                  padding-left: 20px; 
                }
                li { 
                  margin: 8px 0; 
                }
              </style>
            </head>
            <body>
              <div class="container">
                <div class="header">
                  <h1>PEERS</h1>
                  <p>Peer Education and Emotional Resource System</p>
                </div>
                <div class="content">
                  <h2>Account Deactivated</h2>
                  <p>Dear $userName,</p>
                  <p>We're writing to inform you that your PEERS account has been deactivated by an administrator.</p>
                  
                  <div class="info-box">
                    <strong>Account Details:</strong><br>
                    Email: $userEmail<br>
                    Status: <span style="color: #d32f2f;">Inactive</span>
                  </div>
                  
                  <div class="warning-box">
                    <strong>⚠️ What this means:</strong>
                    <ul style="margin: 10px 0;">
                      <li>You can no longer access the PEERS platform</li>
                      <li>All scheduled appointments have been cancelled</li>
                      <li>Your profile is no longer visible to other users</li>
                      <li>You cannot make or accept new bookings</li>
                    </ul>
                  </div>
                  
                  <p><strong>Need Help?</strong></p>
                  <p>If you believe this is a mistake or would like to request reactivation, please contact support:</p>
                  <ul>
                    <li>📧 Email: <a href="mailto:admin@gmail.com">admin@gmail.com</a></li>
                    <li>🏢 Visit: IT Services @ Level 3</li>
                  </ul>
                  
                  <p>Thank you for your understanding.</p>
                  <p>Best regards,<br>PEERS Admin Team</p>
                </div>
                <div class="footer">
                  <p>This is an automated message from PEERS.</p>
                  <p>Please do not reply to this email. Contact support using the details above.</p>
                </div>
              </div>
            </body>
            </html>
          ''',
        },
      });
    } catch (e) {
      // Log error but don't fail the deactivation
      debugPrint('Failed to send deactivation email: $e');
    }
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
                        Text('User Management',
                            style: t.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Manage users in the system',
                            style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search bar
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.black54, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search by name or ID...',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => setState(() => _search = val),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Role filter
              Row(
                children: [
                  Text('Filter by role: ', style: t.bodyMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedRoleFilter,
                        underline: const SizedBox(),
                        isExpanded: true,
                        items: _roleLabelsForFilter
                            .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedRoleFilter = v ?? 'All Roles'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Faculty filter
              _FacultyDropdown(
                selectedValue: _selectedFacultyFilter,
                onChanged: (v) =>
                    setState(() => _selectedFacultyFilter = v ?? 'All Faculties'),
              ),
              const SizedBox(height: 20),

              // Stats row
              _LiveStatsRow(roleLabel: _roleToLabel),
              const SizedBox(height: 16),

              // User list
              _UsersFromFirestoreList(
                search: _search,
                selectedRoleFilter: _selectedRoleFilter,
                selectedFacultyFilter: _selectedFacultyFilter,
                roleToLabel: _roleToLabel,
                readRole: _readRole,
                onRoleChange: _updateUserRoleByEmail,
                onToggleStatus: _setUserStatusByEmail,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------------------------- Header with back + logout ----------------------------- */

class _HeaderBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _HeaderBar({required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onBack,
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
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              )),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin', style: t.titleMedium),
            Text('Portal',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

/* -------------------------- Faculty Dropdown (live from DB) ------------------------- */

class _FacultyDropdown extends StatelessWidget {
  final String selectedValue;
  final ValueChanged<String?> onChanged;
  const _FacultyDropdown({
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('faculties').snapshots(),
      builder: (context, snap) {
        final items = <String>['All Faculties'];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final name = (d.data()['name'] ?? '').toString();
            if (name.isNotEmpty) items.add(name);
          }
        }
        return Row(
          children: [
            Text('Filter by faculty: ', style: t.bodyMedium),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: items.contains(selectedValue) ? selectedValue : items.first,
                  underline: const SizedBox(),
                  isExpanded: true,
                  items: items
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/* ----------------------- Users Firestore Query + Filter ---------------------- */

class _UsersFromFirestoreList extends StatefulWidget {
  final String search;
  final String selectedRoleFilter;
  final String selectedFacultyFilter;
  final String Function(UserRole) roleToLabel;
  final UserRole Function(String?) readRole;
  final Future<void> Function(String email, String newRoleLabel) onRoleChange;
  final Future<void> Function(String email, String status, String userName) onToggleStatus;

  const _UsersFromFirestoreList({
    required this.search,
    required this.selectedRoleFilter,
    required this.selectedFacultyFilter,
    required this.roleToLabel,
    required this.readRole,
    required this.onRoleChange,
    required this.onToggleStatus,
  });

  @override
  State<_UsersFromFirestoreList> createState() =>
      _UsersFromFirestoreListState();
}

class _UsersFromFirestoreListState extends State<_UsersFromFirestoreList> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}',
              style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        var users = _buildUserList(snap.data?.docs ?? []);
        users = _applyFilters(users);

        if (users.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Center(child: Text('No users found')),
          );
        }

        return Column(
          children: [
            for (final u in users) ...[
              _UserItemCard(
                user: u,
                onRoleChanged: (newLabel) {
                  if (newLabel != null) {
                    widget.onRoleChange(u.email, newLabel);
                  }
                },
                onToggleStatus: widget.onToggleStatus,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  List<AppUser> _buildUserList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.map<AppUser>((d) {
      final data = d.data();
      return AppUser(
        name: (data['name'] ?? data['fullName'] ?? 'Unknown').toString(),
        id: (data['studentId'] ?? data['id'] ?? 'N/A').toString(),
        email: (data['email'] ?? '').toString(),
        facultyId: (data['facultyId'] ?? '').toString(),
        facultyName: (data['faculty'] ?? '').toString(),
        role: widget.readRole(data['role'] as String?),
        uid: d.id,
        status: (data['status'] ?? 'active').toString(),
      );
    }).toList();
  }

  List<AppUser> _applyFilters(List<AppUser> users) {
    var filtered = users;

    // Search filter
    if (widget.search.isNotEmpty) {
      final query = widget.search.toLowerCase();
      filtered = filtered.where((u) {
        return u.name.toLowerCase().contains(query) ||
            u.id.toLowerCase().contains(query);
      }).toList();
    }

    // Role filter
    if (widget.selectedRoleFilter != 'All Roles') {
      final targetRole = _labelToRole(widget.selectedRoleFilter);
      filtered = filtered.where((u) => u.role == targetRole).toList();
    }

    // Faculty filter
    if (widget.selectedFacultyFilter != 'All Faculties') {
      filtered = filtered.where((u) => u.facultyName == widget.selectedFacultyFilter).toList();
    }

    return filtered;
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
  final Future<void> Function(String email, String status, String userName) onToggleStatus;

  const _UserItemCard({
    required this.user,
    required this.onRoleChanged,
    required this.onToggleStatus,
  });

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final allowedRoles = const ['HOP', 'School Counsellor','Student'];
    final currentLabel = _roleToLabel(user.role);
    final dropdownValue = allowedRoles.contains(currentLabel) ? currentLabel : null;

    final isActive = (user.status ?? 'active') == 'active';
    final isAdmin = user.role == UserRole.admin;

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
          Text(user.facultyName, style: t.bodySmall),
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

          if (!isAdmin) ...[
            Row(
              children: [
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

                SizedBox(
                  height: 36,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: isActive ? Colors.red : Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => onToggleStatus(
                      user.email,
                      isActive ? 'inactive' : 'active',
                      user.name,
                    ),
                    child: Text(isActive ? 'Deactivate' : 'Activate',
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Admin accounts cannot be modified from this page',
                      style: t.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}