// lib/peer_tutor_students_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PeerTutorStudentsPage extends StatefulWidget {
  const PeerTutorStudentsPage({super.key});

  @override
  State<PeerTutorStudentsPage> createState() => _PeerTutorStudentsPageState();
}

class _PeerTutorStudentsPageState extends State<PeerTutorStudentsPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

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
              const _HeaderBar(),
              const SizedBox(height: 16),
              Text('My Students', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Manage your students', style: t.bodySmall),
              const SizedBox(height: 12),

              // Search
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search by name',
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_uid.isEmpty)
                _emptyBox('Sign in to see your students.')
              else
                _StudentsList(helperUid: _uid, search: _searchCtrl.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyBox(String msg) {
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

/* -------------------------------- Header -------------------------------- */

class _HeaderBar extends StatelessWidget {
  const _HeaderBar();

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
              height: 36, width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.arrow_back, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // PEERS gradient logo
        Container(
          height: 48, width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text('PEERS', style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peer Tutor', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        // logout
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _logout(context),
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 36, width: 36,
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

/* ---------------------------- Students List ---------------------------- */

class _StudentsList extends StatelessWidget {
  final String helperUid;
  final String search;
  const _StudentsList({required this.helperUid, required this.search});

  /// Extract interest IDs from a user doc (supports your schema + fallbacks)
  List<String> _extractInterestIds(Map<String, dynamic> m) {
    final out = <String>{};

    void absorb(dynamic v) {
      if (v == null) return;

      // List<dynamic>: strings, maps, doc refs
      if (v is List) {
        for (final e in v) {
          if (e is String && e.trim().isNotEmpty) out.add(e.trim());
          else if (e is Map && e['id'] is String && (e['id'] as String).trim().isNotEmpty) {
            out.add((e['id'] as String).trim());
          } else if (e is DocumentReference) {
            out.add(e.id);
          }
        }
      }

      // Map<String, bool|num|any>: take keys where truthy
      if (v is Map) {
        v.forEach((key, val) {
          if (key is! String) return;
          final k = key.trim();
          if (k.isEmpty) return;
          final truthy = switch (val) {
            bool b => b,
            num n => n != 0,
            String s => s.isNotEmpty && s.toLowerCase() != 'false' && s != '0',
            _ => true,
          };
          if (truthy) out.add(k);
        });
      }

      // Direct string (unlikely)
      if (v is String && v.trim().isNotEmpty) out.add(v.trim());
    }

    // ✅ Your explicit fields
    absorb(m['academicInterestIds']);
    absorb(m['counselingTopicIds']);

    // Fallbacks
    for (final key in const [
      'interestIds','interest_ids','interestsIds','interests_ids',
      'interestsId','interests_id','interests',
    ]) {
      absorb(m[key]);
    }

    // Also check under profile.*
    final profile = m['profile'];
    if (profile is Map<String, dynamic>) {
      absorb(profile['academicInterestIds']);
      absorb(profile['counselingTopicIds']);
      for (final key in const [
        'interestIds','interest_ids','interestsIds','interests_ids',
        'interestsId','interests_id','interests',
      ]) {
        absorb(profile[key]);
      }
    }

    return out.toList();
  }

  String _pickName(Map<String, dynamic> m) {
    for (final k in const ['fullName','full_name','name','displayName','display_name']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in const ['fullName','full_name','name','displayName','display_name']) {
        final v = prof[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return 'Student';
  }

  String _pickAvatar(Map<String, dynamic> m) {
    for (final k in const ['photoUrl','avatarUrl','photoURL']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in const ['photoUrl','avatarUrl']) {
        final v = prof[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // MODIFICATION: Only fetch appointments that have been completed.
    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperUid)
        .where('status', isEqualTo: 'completed') // <-- ADDED THIS FILTER
        .snapshots();

    // All interests (ID -> display title)
    final interestsStream = FirebaseFirestore.instance
        .collection('interests')
        .snapshots();

    // "Removed" links (soft-hide)
    final removedStream = FirebaseFirestore.instance
        .collection('tutor_student_links')
        .where('helperId', isEqualTo: helperUid)
        .where('archived', isEqualTo: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: appsStream,
      builder: (context, appsSnap) {
        if (appsSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (appsSnap.hasError) {
          return Text('Error: ${appsSnap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        // Unique student IDs + last session map (latest startAt)
        final Map<String, DateTime> lastSession = {};
        final Set<String> studentIds = {};

        for (final d in (appsSnap.data?.docs ?? const [])) {
          final m = d.data();
          final sid = (m['studentId'] ?? '').toString();
          if (sid.isEmpty) continue;
          studentIds.add(sid);

          final ts = (m['startAt'] is Timestamp) ? (m['startAt'] as Timestamp).toDate() : null;
          if (ts == null) continue;

          final current = lastSession[sid];
          if (current == null || ts.isAfter(current)) {
            lastSession[sid] = ts;
          }
        }

        if (studentIds.isEmpty) {
          // Changed message to reflect the new logic
          return _emptyBox('No students with completed sessions yet.');
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: removedStream,
          builder: (context, removedSnap) {
            final removed = <String>{};
            for (final d in (removedSnap.data?.docs ?? const [])) {
              final m = d.data();
              if ((m['archived'] ?? false) == true) {
                final sid = (m['studentId'] ?? '').toString();
                if (sid.isNotEmpty) removed.add(sid);
              }
            }

            final activeIds = studentIds.where((id) => !removed.contains(id)).toList();
            if (activeIds.isEmpty) {
              return _emptyBox('No active students.');
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: interestsStream,
              builder: (context, intSnap) {
                // interests map: id -> display name (title/name)
                final interestMap = <String, String>{};
                for (final d in (intSnap.data?.docs ?? const [])) {
                  final m = d.data();
                  final id = d.id;
                  final title = (m['title'] ?? m['name'] ?? '').toString();
                  if (title.isNotEmpty) interestMap[id] = title;
                }

                return Column(
                  children: [
                    for (final sid in activeIds) ...[
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: FirebaseFirestore.instance.collection('users').doc(sid).get(),
                        builder: (context, snap) {
                          final um = snap.data?.data() ?? <String, dynamic>{};
                          final name = _pickName(um);
                          final avatar = _pickAvatar(um);

                          // interest IDs from user doc (robust)
                          final ids = _extractInterestIds(um);

                          // map to titles
                          final interestTitles = ids
                              .map((id) => interestMap[id])
                              .whereType<String>()
                              .toList();

                          // search filter
                          if (search.trim().isNotEmpty &&
                              !name.toLowerCase().contains(search.trim().toLowerCase())) {
                            return const SizedBox.shrink();
                          }

                          final last = lastSession[sid];
                          return _StudentCard(
                            studentId: sid,
                            name: name,
                            avatarUrl: avatar,
                            interests: interestTitles,
                            lastSessionDate: last,
                            onView: () {
                              // Functionality to redirect to Student Details page is preserved
                              Navigator.pushNamed(context, '/tutor/students/detail', arguments: {'studentId': sid});
                            },
                            onRemove: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Remove student'),
                                  content: const Text('This hides the student from your list (does not delete appointments).'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await FirebaseFirestore.instance
                                    .collection('tutor_student_links')
                                    .doc('${helperUid}_$sid')
                                    .set({
                                  'helperId': helperUid,
                                  'studentId': sid,
                                  'archived': true,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _emptyBox(String msg) {
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

/* ------------------------------ Student Card ----------------------------- */

class _StudentCard extends StatelessWidget {
  final String studentId;
  final String name;
  final String avatarUrl;
  final List<String> interests;
  final DateTime? lastSessionDate;
  final VoidCallback onView;
  final VoidCallback onRemove;

  const _StudentCard({
    required this.studentId,
    required this.name,
    required this.avatarUrl,
    required this.interests,
    required this.lastSessionDate,
    required this.onView,
    required this.onRemove,
  });

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2FF), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: (avatarUrl.isNotEmpty)
                ? Image.network(avatarUrl, fit: BoxFit.cover)
                : const Icon(Icons.person_outline, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          // info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // name + remove
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(
                      height: 28,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF2D55),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: onRemove,
                        child: const Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // interests line (combine academic + counseling)
                Text(
                  interests.isNotEmpty
                      ? 'Interests: ${interests.take(3).join(', ')}${interests.length > 3 ? ', …' : ''}'
                      : 'Interests: —',
                  style: t.bodySmall,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // last session + view
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Session:', style: t.labelSmall?.copyWith(color: Colors.black54)),
                          Text(lastSessionDate != null ? _fmtDate(lastSessionDate!) : '—', style: t.bodySmall),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: onView,
                        child: const Text('View', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}