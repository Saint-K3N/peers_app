import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/* -------------------------------- Helpers -------------------------------- */

String _pickString(Map<String, dynamic>? m, List<String> keys) {
  if (m == null) return '';
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

Map<String, dynamic>? _subMap(Map<String, dynamic>? m, String key) {
  final v = m?[key];
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

String _extractName(Map<String, dynamic>? u) {
  final direct = _pickString(u, ['fullName','full_name','name','displayName','display_name']);
  if (direct.isNotEmpty) return direct;
  final profile = _subMap(u, 'profile');
  final prof = _pickString(profile, ['fullName','full_name','name','displayName','display_name']);
  if (prof.isNotEmpty) return prof;
  final first = _pickString(u, ['firstName','first_name','givenName','given_name']);
  final last  = _pickString(u, ['lastName','last_name','familyName','family_name','surname']);
  final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
  if (combo.isNotEmpty) return combo;
  final pFirst = _pickString(profile, ['firstName','first_name','givenName','given_name']);
  final pLast  = _pickString(profile, ['lastName','last_name','familyName','family_name','surname']);
  return [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
}

String _extractStudentId(Map<String, dynamic>? u, Map<String, dynamic> app) {
  String sid = _pickString(u, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
  if (sid.isNotEmpty) return sid;
  final profile = _subMap(u, 'profile');
  sid = _pickString(profile, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
  if (sid.isNotEmpty) return sid;
  return _pickString(app, ['studentId','studentID','student_id','sid']);
}

String _statusStage(String raw) {
  final s = (raw).toLowerCase();
  if (s == 'approved') return 'Approved';
  if (s == 'rejected' || s == 'hop rejected') return 'Rejected';
  return 'Pending';
}

/* ------------------------------- Page -------------------------------- */

class SchoolCounsellorReviewApplicationsPage extends StatefulWidget {
  const SchoolCounsellorReviewApplicationsPage({super.key});

  @override
  State<SchoolCounsellorReviewApplicationsPage> createState() =>
      _SchoolCounsellorReviewApplicationsPageState();
}

class _SchoolCounsellorReviewApplicationsPageState
    extends State<SchoolCounsellorReviewApplicationsPage> {
  String _stage = 'All'; // All | Pending | Approved | Rejected

  final _appsCol = FirebaseFirestore.instance.collection('peer_applications');
  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _interestsCol = FirebaseFirestore.instance.collection('interests');

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchUser(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _usersCol.doc(uid).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _getInterestTitlesByIds(List<dynamic>? ids) async {
    if (ids == null || ids.isEmpty) return const <String>[];
    final idStrs = ids.map((e) => e.toString()).toList();

    // Firestore whereIn limit is 10
    final chunks = <List<String>>[];
    for (var i = 0; i < idStrs.length; i += 10) {
      chunks.add(idStrs.sublist(i, (i + 10 > idStrs.length) ? idStrs.length : i + 10));
    }

    final Map<String, String> idToTitle = {};
    for (final c in chunks) {
      final q = await _interestsCol.where(FieldPath.documentId, whereIn: c).get();
      for (final d in q.docs) {
        final title = (d.data()['title'] ?? '').toString().trim();
        if (title.isNotEmpty) idToTitle[d.id] = title;
      }
    }

    final titles = <String>[];
    for (final id in idStrs) {
      final t = idToTitle[id];
      if (t != null && t.isNotEmpty) titles.add(t);
    }
    return titles;
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
              _Header(onLogout: _logout),
              const SizedBox(height: 16),

              Text('Counsellor Review Applications',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Approve or reject peer counsellor applications', // (text tweak)
                  style: t.bodySmall),
              const SizedBox(height: 14),

              _StageFilterBar(
                selected: _stage,
                onSelect: (s) => setState(() => _stage = s),
              ),
              const SizedBox(height: 16),

              // Only show Peer Counsellor applications
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _appsCol
                    .where('requestedRole', isEqualTo: 'peer_counsellor')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Text('Error: ${snap.error}',
                        style: t.bodyMedium?.copyWith(color: Colors.red));
                  }

                  final docs = (snap.data?.docs ?? []).toList();

                  // Sort locally by submittedAt DESC
                  docs.sort((a, b) {
                    final at = (a.data()['submittedAt'] is Timestamp)
                        ? (a.data()['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch
                        : 0;
                    final bt = (b.data()['submittedAt'] is Timestamp)
                        ? (b.data()['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch
                        : 0;
                    return bt.compareTo(at);
                  });

                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Text('No applications found.'),
                    );
                  }

                  return Column(
                    children: [
                      for (final d in docs) ...[
                        _SCAppCardWrapper(
                          appDoc: d,
                          fetchUser: _fetchUser,
                          resolveInterests: _getInterestTitlesByIds,
                          stageFilter: _stage,
                        ),
                        const SizedBox(height: 12),
                      ],
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

/* ----------------------- Wrapper: per-card data load ---------------------- */

class _SCAppCardWrapper extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> appDoc;
  final Future<Map<String, dynamic>?> Function(String uid) fetchUser;
  final Future<List<String>> Function(List<dynamic>? ids) resolveInterests;
  final String stageFilter;

  const _SCAppCardWrapper({
    required this.appDoc,
    required this.fetchUser,
    required this.resolveInterests,
    required this.stageFilter,
  });

  @override
  Widget build(BuildContext context) {
    final data = appDoc.data() ?? {};
    final uid = (data['userId'] ?? '').toString();

    // Extra guard (legacy docs safety)
    final role = ((data['requestedRole'] ?? data['role'] ?? '') as String).toLowerCase();
    if (role != 'peer_counsellor') {
      return const SizedBox.shrink();
    }

    final dynamicIds = (data['interestsIds'] is List)
        ? (data['interestsIds'] as List)
        : ((data['interests'] is List)
        ? (data['interests'] as List)
        .map((e) => (e is Map && e['id'] != null) ? e['id'].toString() : null)
        .where((x) => x != null)
        .toList()
        : const <dynamic>[]);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        fetchUser(uid),               // [0] user data
        resolveInterests(dynamicIds), // [1] interest titles
      ]),
      builder: (context, snap) {
        final user = (snap.hasData && snap.data!.isNotEmpty)
            ? snap.data![0] as Map<String, dynamic>?
            : null;
        final interestTitles = (snap.hasData && snap.data!.length > 1)
            ? (snap.data![1] as List<String>)
            : const <String>[];

        final name = _extractName(user);
        final studentId = _extractStudentId(user, data);
        final rawStatus = (data['status'] ?? 'pending').toString();
        final stage = _statusStage(rawStatus);

        if (stageFilter != 'All' && stage != stageFilter) {
          return const SizedBox.shrink();
        }

        String footerNote;
        switch (stage) {
          case 'Approved':
            footerNote = 'Approved by Admin';
            break;
          case 'Rejected':
            footerNote = rawStatus.toLowerCase() == 'hop rejected'
                ? 'Rejected by HOP'
                : 'Rejected';
            break;
          default:
            footerNote = rawStatus.toLowerCase() == 'hop approve'
                ? 'HOP Approved • Pending Admin'
                : 'Application Forwarded to Admin';
        }

        return _ApplicationCard(
          name: name.isEmpty ? '—' : name,
          studentId: studentId.isNotEmpty ? studentId : 'Student ID not set',
          interests: interestTitles,
          stage: stage,          // Pending | Approved | Rejected
          footerNote: footerNote,
          onView: () => Navigator.pushNamed(
            context,
            '/counsellor/review/detail',
            arguments: appDoc.id, // pass the application id
          ),
        );
      },
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _Header extends StatelessWidget {
  final VoidCallback onLogout;
  const _Header({required this.onLogout});

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

        // logo
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
              )),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('School Counsellor',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // logout
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
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

class _StageFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _StageFilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, {bool filled = false}) {
      final sel = selected == label;
      final bg = sel ? Colors.black : (filled ? Colors.grey.shade200 : Colors.white);
      final fg = sel ? Colors.white : Colors.black87;

      return InkWell(
        onTap: () => onSelect(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('All', filled: true),
        chip('Pending', filled: true),
        chip('Approved', filled: true),
        chip('Rejected', filled: true),
      ],
    );
  }
}

/* ---------------------------- Application Card ---------------------------- */

class _ApplicationCard extends StatelessWidget {
  final String name;
  final String studentId;
  final List<String> interests;
  final String stage;     // Pending | Approved | Rejected
  final String footerNote;
  final VoidCallback onView;

  const _ApplicationCard({
    required this.name,
    required this.studentId,
    required this.interests,
    required this.stage,
    required this.footerNote,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    late Color borderColor;
    late _StatusChip chip;
    late Text footer;

    switch (stage) {
      case 'Approved':
        borderColor = const Color(0xFF3CB371);
        chip = const _StatusChip('Approved', bg: Color(0xFFC9F2D9), fg: Color(0xFF1B5E20));
        footer = Text(footerNote,
            style: t.labelSmall?.copyWith(color: const Color(0xFF1B5E20), fontWeight: FontWeight.w600));
        break;
      case 'Rejected':
        borderColor = const Color(0xFFE53935);
        chip = const _StatusChip('Rejected', bg: Color(0xFFF8D7DA), fg: Color(0xFFB71C1C));
        footer = Text(footerNote,
            style: t.labelSmall?.copyWith(color: const Color(0xFFB71C1C), fontWeight: FontWeight.w600));
        break;
      default:
        borderColor = const Color(0xFFE6C45E);
        chip = const _StatusChip('Pending', bg: Color(0xFFF1C184), fg: Color(0xFF5B3B00));
        footer = Text(footerNote,
            style: t.labelSmall?.copyWith(color: Colors.orange.shade700, fontWeight: FontWeight.w600));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final tight = c.maxWidth < 340;
                        final nm = Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
                        if (tight) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              nm,
                              const SizedBox(height: 6),
                              Align(alignment: Alignment.centerRight, child: chip),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: nm),
                            const SizedBox(width: 8),
                            chip,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(studentId, style: t.bodySmall),
                    Text(
                      interests.isEmpty ? 'Interest: —' : 'Interest: ${interests.join(', ')}',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, c) {
                        final viewBtn = FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: onView,
                          child: const Text('View', style: TextStyle(color: Colors.white)),
                        );

                        return Row(
                          children: [
                            Expanded(child: footer),
                            const SizedBox(width: 8),
                            viewBtn,
                          ],
                        );
                      },
                    )
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _StatusChip(this.label, {required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
