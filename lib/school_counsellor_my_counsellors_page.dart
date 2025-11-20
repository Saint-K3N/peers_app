// lib/school_counsellor_my_counsellors_page.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
class SchoolCounsellorMyCounsellorsPage extends StatefulWidget {
  const SchoolCounsellorMyCounsellorsPage({super.key});

  @override
  State<SchoolCounsellorMyCounsellorsPage> createState() =>
      _SchoolCounsellorMyCounsellorsPageState();
}

/* --------------------------------- Helpers -------------------------------- */

String _pickName(Map<String, dynamic> m) {
  for (final k in const ['fullName','full_name','name','displayName','display_name']) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  final p = m['profile'];
  if (p is Map<String, dynamic>) {
    for (final k in const ['fullName','full_name','name','displayName','display_name']) {
      final v = p[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
  }
  return 'Counsellor';
}

String? _pickPhoto(Map<String, dynamic> m) {
  for (final k in const ['photoUrl','photoURL','avatarUrl','avatar']) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  final p = m['profile'];
  if (p is Map<String, dynamic>) {
    for (final k in const ['photoUrl','photoURL','avatarUrl','avatar']) {
      final v = p[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
  }
  return null;
}

Future<List<String>> _interestTitlesByIds(List<dynamic>? ids) async {
  try {
    if (ids == null || ids.isEmpty) return const <String>[];
    final idStrs = ids.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    if (idStrs.isEmpty) return const <String>[];

    final col = FirebaseFirestore.instance.collection('interests');
    final Map<String, String> idToTitle = {};
    for (int i = 0; i < idStrs.length; i += 10) {
      final chunk = idStrs.sublist(i, math.min(i + 10, idStrs.length));
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        final title = (d.data()['title'] ?? '').toString().trim();
        if (title.isNotEmpty) idToTitle[d.id] = title;
      }
    }
    return idStrs.map((id) => idToTitle[id]).whereType<String>().toList();
  } catch (_) {
    return const <String>[];
  }
}

Future<DateTime?> _lastSessionFor(String counsellorUid) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: counsellorUid)
        .orderBy('startAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final ts = snap.docs.first.data()['startAt'];
    if (ts is Timestamp) return ts.toDate();
  } catch (_) {}
  return null;
}

String _prettyDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

/* ---------------------------------- Page ---------------------------------- */

class _SchoolCounsellorMyCounsellorsPageState
    extends State<SchoolCounsellorMyCounsellorsPage> {
  String _query = '';
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _removeCounsellor(BuildContext context, String counsellorId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Counsellor'),
        content: const Text('Are you sure you want to remove this counsellor from your list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(counsellorId)
          .update({'role': 'student', 'status': 'active'});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Counsellor removed successfully')),
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

    // Accept both spellings
    final appsStream = FirebaseFirestore.instance
        .collection('peer_applications')
        .where('requestedRole', whereIn: ['peer_counsellor', 'peer_counselor'])
        .snapshots();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 16),

              Text('My Counsellors',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Manage your counsellors', style: t.bodySmall),
              const SizedBox(height: 12),

              // Search
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),

              // Info banner
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0C8FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Remember: All information is confidential and personal',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),

              // Filter active , approved PEER COUNSELLORS
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: appsStream,
                builder: (context, appSnap) {
                  // Hide progress bar completely
                  if (appSnap.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  if (appSnap.hasError) {
                    return Text('Error: ${appSnap.error}',
                        style: t.bodyMedium?.copyWith(color: Colors.red));
                  }

                  // Include approved OR schoolCounsellorApproved==true
                  final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  final seenUsers = <String>{};

                  for (final d in (appSnap.data?.docs ?? const [])) {
                    final m = d.data();
                    final role =
                    (m['requestedRole'] ?? '').toString().toLowerCase().trim();
                    if (role != 'peer_counsellor' && role != 'peer_counselor') {
                      continue;
                    }
                    final userId = (m['userId'] ?? '').toString();
                    if (userId.isEmpty) continue;

                    final status =
                    (m['status'] ?? '').toString().toLowerCase().trim();
                    final scApproved =
                        (m['schoolCounsellorApproved'] ?? false) == true;

                    final include = status == 'approved' && scApproved;
                    if (!include) continue;

                    // dedupe by userId
                    if (seenUsers.add(userId)) filtered.add(d);
                  }

                  if (filtered.isEmpty) {
                    return _emptyBox('No counsellors found.');
                  }

                  return Column(
                    children: filtered.map((d) {
                      final app = d.data();
                      final counsellorUid = (app['userId'] ?? '').toString();
                      final interestsIds = (app['interestsIds'] is List)
                          ? (app['interestsIds'] as List)
                          : ((app['interests'] is List)
                          ? (app['interests'] as List)
                          .map((e) => (e is Map && e['id'] != null)
                          ? e['id'].toString()
                          : null)
                          .where((x) => x != null)
                          .toList()
                          : const <dynamic>[]);

                      return _CounsellorTile(
                        counsellorUid: counsellorUid,
                        interestsIds: interestsIds,
                        query: _query,
                        onRemove: () => _removeCounsellor(context, counsellorUid),
                      );
                    }).toList(),
                  );
                },
              ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(msg),
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _Header extends StatelessWidget {
  const _Header();
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
            Text('School Counsellor', style: t.titleMedium),
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

class _CounsellorTile extends StatelessWidget {
  final String counsellorUid;
  final List<dynamic> interestsIds;
  final String query;
  final VoidCallback onRemove;

  const _CounsellorTile({
    required this.counsellorUid,
    required this.interestsIds,
    required this.query,
    required this.onRemove,
  });

  Future<(_UserBits, List<String>, DateTime?)> _load() async {
    DocumentSnapshot<Map<String, dynamic>>? uSnap;
    try {
      uSnap =
      await FirebaseFirestore.instance.collection('users').doc(counsellorUid).get();
    } catch (_) {}
    final ints = await _interestTitlesByIds(interestsIds);
    final last = await _lastSessionFor(counsellorUid);
    final user = _UserBits.fromSnap(uSnap);
    return (user, ints, last);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<(_UserBits, List<String>, DateTime?)>(
      future: _load(),
      builder: (context, snap) {
        // Hide progress bar while loading
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final user = snap.data?.$1 ?? const _UserBits();
        final interestTitles = snap.data?.$2 ?? const <String>[];
        final last = snap.data?.$3;

        final name = user.name ?? 'Counsellor';
        final photoUrl = user.photoUrl;

        // Search filter (by name)
        final q = query.trim().toLowerCase();
        if (q.isNotEmpty && !name.toLowerCase().contains(q)) {
          return const SizedBox.shrink();
        }

        return _CounsellorCard(
          name: name,
          photoUrl: photoUrl,
          interests: interestTitles,
          lastSessionText: last != null ? _prettyDate(last) : '-',
          onBook: () {
            Navigator.pushNamed(
              context,
              '/school-counsellor//appointment',
              arguments: {'userId': counsellorUid, 'name': name, 'photoUrl': photoUrl},
            );
          },
          onView: () {
            Navigator.pushNamed(
              context,
              '/school_counsellor/detail_page',
              arguments: {'counsellorId': counsellorUid, 'name': name},
            );
          },
          onRemove: onRemove,
        );
      },
    );
  }
}

class _UserBits {
  final String? name;
  final String? photoUrl;
  const _UserBits({this.name, this.photoUrl});

  factory _UserBits.fromSnap(DocumentSnapshot<Map<String, dynamic>>? s) {
    final m = s?.data() ?? const <String, dynamic>{};
    return _UserBits(
      name: _pickName(m),
      photoUrl: _pickPhoto(m),
    );
  }
}

class _CounsellorCard extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final List<String> interests;
  final String lastSessionText;
  final VoidCallback onRemove, onBook, onView;

  const _CounsellorCard({
    required this.name,
    required this.photoUrl,
    required this.interests,
    required this.lastSessionText,
    required this.onRemove,
    required this.onBook,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final borderClr = const Color(0xFFDDE6FF);

    final removeBtn = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onRemove,
      child: const Text('Remove', style: TextStyle(color: Colors.white)),
    );

    final avatar = CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey.shade300,
      backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? const Icon(Icons.psychology_alt_outlined, color: Colors.white)
          : null,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderClr, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, cstr) {
              final tight = cstr.maxWidth < 350;

              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    interests.isNotEmpty
                        ? 'Interest: ${interests.join(', ')}'
                        : 'Interest: —',
                    style: t.bodySmall,
                  ),
                ],
              );

              if (tight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const SizedBox(width: 10),
                        Expanded(child: info),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: removeBtn,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(child: info),
                  const SizedBox(width: 8),
                  removeBtn,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, cstr) {
              final tight = cstr.maxWidth < 340;

              final lastSession = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last Session:', style: t.labelSmall),
                  Text(lastSessionText, style: t.labelSmall),
                ],
              );

              final bookBtn = ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB9C85B),
                  foregroundColor: Colors.white,
                  shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  elevation: 0,
                ),
                onPressed: onBook,
                child: const Text('Book'),
              );

              final viewBtn = FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onView,
                child: const Text('View', style: TextStyle(color: Colors.white)),
              );

              if (tight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    lastSession,
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [bookBtn, viewBtn],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: lastSession),
                  bookBtn,
                  const SizedBox(width: 8),
                  viewBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}