import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HopMyTutorsPage extends StatefulWidget {
  const HopMyTutorsPage({super.key});

  @override
  State<HopMyTutorsPage> createState() => _HopMyTutorsPageState();
}

class _HopMyTutorsPageState extends State<HopMyTutorsPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _interestsCol = FirebaseFirestore.instance.collection('interests');

  final Map<String, String> _interestTitleCache = {};
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<String> _currentFacultyId() async {
    if (_uid.isEmpty) return '';
    final snap = await _usersCol.doc(_uid).get();
    return ((snap.data() ?? {})['facultyId'] ?? '').toString();
  }

  Future<List<String>> _interestTitles(List<String> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      if (!_interestTitleCache.containsKey(id)) missing.add(id);
    }
    for (int i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, math.min(i + 10, missing.length));
      final snap = await _interestsCol
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        final t = (d['title'] ?? '').toString().trim();
        if (t.isNotEmpty) _interestTitleCache[d.id] = t;
      }
    }
    final out = <String>[];
    for (final id in ids) {
      final t = _interestTitleCache[id];
      if (t != null && t.isNotEmpty) out.add(t);
    }
    return out;
  }

  String _pickString(Map<String, dynamic> m, List<String> keys) {
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

  String? _pickPhotoUrl(Map<String, dynamic> m) {
    for (final k in const ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in const ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
        final v = prof[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }

  String _fmtDateShort(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    if (_uid.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Please sign in as HOP to view your tutors.', style: t.bodyMedium),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _currentFacultyId(),
      builder: (context, facSnap) {
        final facultyId = facSnap.data ?? '';
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HopHeader(),
                  const SizedBox(height: 16),

                  Text('My Tutors', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Manage your Tutors', style: t.bodySmall),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1BEE7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Remember: All information is confidential and personal',
                      style: t.bodySmall?.copyWith(color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (facSnap.connectionState == ConnectionState.waiting)
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    _TutorsListByUsers(
                      facultyId: facultyId,
                      query: _query,
                      pickName: (m) => _pickString(m, const [
                        'fullName','full_name','name','displayName','display_name'
                      ]),
                      pickPhoto: _pickPhotoUrl,
                      fmtDate: _fmtDateShort,
                      loadInterestTitles: _interestTitles,
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

/* --------------------------------- Header --------------------------------- */

class _HopHeader extends StatelessWidget {
  const _HopHeader();

  Future<void> _logout(BuildContext context) async {
    try { await FirebaseAuth.instance.signOut(); } catch (_) {}
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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
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

/* ------------------------- Tutors list (from users) ------------------------ */

class _TutorsListByUsers extends StatelessWidget {
  final String facultyId;
  final String query;
  final String Function(Map<String, dynamic>) pickName;
  final String? Function(Map<String, dynamic>) pickPhoto;
  final String Function(DateTime) fmtDate;
  final Future<List<String>> Function(List<String>) loadInterestTitles;

  const _TutorsListByUsers({
    required this.facultyId,
    required this.query,
    required this.pickName,
    required this.pickPhoto,
    required this.fmtDate,
    required this.loadInterestTitles,
  });

  // We only filter by role in Firestore to avoid composite-index errors,
  // and then filter by facultyId in memory.
  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'peer_tutor')
        .snapshots();
  }

  Future<DateTime?> _lastCompleted(String tutorId) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: tutorId)
        .orderBy('startAt', descending: true)
        .limit(10)
        .get();
    for (final d in snap.docs) {
      final st = (d['status'] ?? '').toString().toLowerCase().trim();
      final ts = d['startAt'];
      if (st == 'completed' && ts is Timestamp) {
        return ts.toDate();
      }
    }
    return null;
  }

  Future<void> _removeTutor(BuildContext context, String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this tutor?'),
        content: const Text('This will change their role to "peer".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'role': 'peer', 'updatedAt': FieldValue.serverTimestamp()});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutor removed.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        final userDocs = (snap.data?.docs ?? const [])
            .where((d) {
          final data = d.data();
          final fac = (data['facultyId'] ?? '').toString();
          if (facultyId.isNotEmpty && fac != facultyId) return false;
          final name = pickName(data).toLowerCase();
          if (query.isNotEmpty && !name.contains(query)) return false;
          return true;
        })
            .toList();

        if (userDocs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
            ),
            child: const Text('No tutors found.'),
          );
        }

        return Column(
          children: userDocs.map((d) {
            final u = d.data();
            final tutorId = d.id;

            final name = pickName(u).ifEmpty('Tutor');
            final photoUrl = pickPhoto(u);

            final ids = <String>[
              ...((u['academicInterestIds'] is List)
                  ? (u['academicInterestIds'] as List).map((e) => e.toString())
                  : const <String>[]),
              ...((u['interestsIds'] is List)
                  ? (u['interestsIds'] as List).map((e) => e.toString())
                  : const <String>[]),
            ].toSet().toList();

            return FutureBuilder<List<String>>(
              future: loadInterestTitles(ids),
              builder: (context, intSnap) {
                final interestTitles = intSnap.data ?? const <String>[];
                return FutureBuilder<DateTime?>(
                  future: _lastCompleted(tutorId),
                  builder: (context, lastSnap) {
                    final lastDt = lastSnap.data;
                    final lastStr = lastDt != null ? fmtDate(lastDt) : '—';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
                                child: (photoUrl == null || photoUrl!.isEmpty)
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    if (interestTitles.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Interests: ${interestTitles.join(', ')}',
                                          style: t.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 28,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFE53935),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _removeTutor(context, tutorId),
                                  child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Last Session: $lastStr', style: t.bodySmall?.copyWith(color: Colors.black54)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(
                                height: 32,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFA6B94A),
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/hop/make-appointment',
                                      arguments: {'tutorId': tutorId, 'tutorName': name,'specializes': interestTitles},
                                    );
                                  },
                                  child: const Text('Book', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 32,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/hop/my-tutors/detail',
                                      arguments: {'tutorId': tutorId},
                                    );
                                  },
                                  child: const Text('View', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

/* --------------------------- Tiny string helper --------------------------- */
extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
