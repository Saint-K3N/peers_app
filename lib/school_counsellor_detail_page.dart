// lib/school_counsellor_detail_page.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/* ==================== School Counsellor • Counsellor Detail ==================== */

class SchoolCounsellorDetailPage extends StatefulWidget {
  const SchoolCounsellorDetailPage({super.key});

  @override
  State<SchoolCounsellorDetailPage> createState() => _SchoolCounsellorDetailPageState();
}

class _SchoolCounsellorDetailPageState extends State<SchoolCounsellorDetailPage> {
  bool _tabSessions = true; // Sessions | Students

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final counsellorId = (args['counsellorId'] as String?) ?? (args['tutorId'] as String? ?? '');
    final t = Theme.of(context).textTheme;

    if (counsellorId.isEmpty) {
      return Scaffold(
        body: SafeArea(child: Center(child: Text('Missing counsellorId.', style: t.bodyMedium))),
      );
    }

    final usersCol = FirebaseFirestore.instance.collection('users');

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: usersCol.doc(counsellorId).snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final u = snap.data?.data() ?? {};
            final name = _pickName(u);
            final email = (u['email'] ?? u['emailAddress'] ?? '').toString();
            String? photoUrl;
            for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
              final v = u[k];
              if (v is String && v.trim().isNotEmpty) {
                photoUrl = v.trim();
                break;
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SCHeader(),
                  const SizedBox(height: 16),
                  Text('My Counsellors', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),

                  _DetailHeaderCard(
                    userId: counsellorId,
                    name: name,
                    email: email,
                    photoUrl: photoUrl,
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _TabButton(
                          label: 'Sessions',
                          selected: _tabSessions,
                          onTap: () => setState(() => _tabSessions = true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TabButton(
                          label: 'Students',
                          selected: !_tabSessions,
                          onTap: () => setState(() => _tabSessions = false),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  if (_tabSessions)
                    _SessionsList(helperId: counsellorId, helperName: name, kindLabel: 'Counselling Session')
                  else
                    _StudentsList(helperId: counsellorId, studentReportRoute: '/counsellor/student-report'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ================================= Helpers ================================= */

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
  return 'Counsellor';
}

// Extract a student id safely from many shapes. Returns null if no real student.
String? _studentIdOf(Map<String, dynamic> m) {
  dynamic v = m['studentId'] ??
      m['student_id'] ??
      m['studentUid'] ??
      m['studentUID'] ??
      m['userId'] ??
      m['student']; // might be Map or DocumentReference

  if (v == null) return null;

  if (v is String) {
    final s = v.trim();
    return s.isEmpty ? null : s;
  }
  if (v is DocumentReference) return v.id;

  if (v is Map) {
    for (final k in const ['id', 'uid', 'userId']) {
      final w = v[k];
      if (w is String && w.trim().isNotEmpty) return w.trim();
      if (w is DocumentReference) return w.id;
    }
  }
  return null;
}

/* =============================== Header bar =============================== */

class _SCHeader extends StatelessWidget {
  const _SCHeader();

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
            Text('School Counsellor', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 36, width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.exit_to_app, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: selected ? Colors.black : const Color(0xFFEDEEF1),
          foregroundColor: selected ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/* ============================ Detail header card ============================ */

class _DetailHeaderCard extends StatelessWidget {
  final String userId, name, email;
  final String? photoUrl;
  const _DetailHeaderCard({
    required this.userId,
    required this.name,
    required this.email,
    required this.photoUrl,
  });

  Future<String> _lastSession(String helperId) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .orderBy('startAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return '—';
    final ts = snap.docs.first.data()['startAt'];
    if (ts is! Timestamp) return '—';
    final d = ts.toDate();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  Future<List<String>> _interestTitles(Map<String, dynamic> u) async {
    final ids = <String>{
      ...((u['academicInterestIds'] is List)
          ? (u['academicInterestIds'] as List).map((e) => e.toString())
          : const <String>[]),
      ...((u['counselingTopicIds'] is List)
          ? (u['counselingTopicIds'] as List).map((e) => e.toString())
          : const <String>[]),
    }.where((e) => e.isNotEmpty).toList();

    if (ids.isEmpty) return const [];

    final col = FirebaseFirestore.instance.collection('interests');
    final map = <String, String>{};
    for (int i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, math.min(i + 10, ids.length));
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        final title = (d['title'] ?? '').toString().trim();
        if (title.isNotEmpty) map[d.id] = title;
      }
    }
    return ids.map((id) => map[id]).whereType<String>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, snap) {
        final u = snap.data?.data() ?? {};
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFDCE6FF), width: 2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
                    child: (photoUrl == null || photoUrl!.isEmpty)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if (email.isNotEmpty) Text(email, style: t.bodySmall),
                        const SizedBox(height: 6),
                        FutureBuilder<List<String>>(
                          future: _interestTitles(u),
                          builder: (_, s) => Text(
                            s.hasData && s.data!.isNotEmpty
                                ? 'Interests: ${s.data!.join(', ')}'
                                : 'Interests: —',
                            style: t.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MiniStatBox(
                    title: 'Students',
                    valueStream: FirebaseFirestore.instance
                        .collection('appointments')
                        .where('helperId', isEqualTo: userId)
                        .snapshots()
                        .map((s) {
                      final ids = <String>{};
                      for (final d in s.docs) {
                        final m = d.data();
                        final sid = _studentIdOf(m);
                        if (sid != null) ids.add(sid);
                      }
                      return ids.length;
                    }),
                  ),
                  const SizedBox(width: 12),
                  _MiniStatBox(
                    title: 'Total Sessions',
                    valueStream: FirebaseFirestore.instance
                        .collection('appointments')
                        .where('helperId', isEqualTo: userId)
                        .snapshots()
                        .map((s) => s.docs.length),
                  ),
                  const Spacer(),
                  FutureBuilder<String>(
                    future: _lastSession(userId),
                    builder: (_, s) => Text('Last Session: ${s.data ?? '—'}',
                        style: t.labelSmall?.copyWith(color: Colors.black54)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 100,
                  child: TextField(
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: 'Note:',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStatBox extends StatelessWidget {
  final String title;
  final Stream<int> valueStream;
  const _MiniStatBox({required this.title, required this.valueStream});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 92,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: StreamBuilder<int>(
        stream: valueStream,
        builder: (_, s) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${s.data ?? 0}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(title, style: t.labelSmall),
          ],
        ),
      ),
    );
  }
}

/* ============================== Sessions list ============================== */

class _SessionsList extends StatelessWidget {
  final String helperId;
  final String helperName;
  final String kindLabel; // e.g. "Counselling Session"
  const _SessionsList({required this.helperId, required this.helperName, required this.kindLabel});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: CircularProgressIndicator()),
          );
        }
        final docs = (snap.data?.docs ?? const [])
          ..sort((a, b) {
            final at = (a.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
            final bt = (b.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at); // latest first
          });

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
            child: const Text('No sessions to display.'),
          );
        }

        return Column(
          children: [
            for (final d in docs) ...[
              _SessionRow(m: d.data(), sessionTitle: '$kindLabel - $helperName'),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  final Map<String, dynamic> m;
  final String sessionTitle;
  const _SessionRow({required this.m, required this.sessionTitle});

  String _statusChip() {
    final s = (m['status'] ?? 'pending').toString().toLowerCase().trim();
    if (s == 'completed') return 'Completed';
    if (s == 'cancelled') return 'Cancelled';
    if (s == 'missed') return 'Missed';
    final start = (m['startAt'] as Timestamp?)?.toDate();
    if (start != null && DateTime.now().isBefore(start) && (s == 'pending' || s == 'confirmed')) {
      return 'Upcoming';
    }
    return s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);
  }

  (Color bg, Color fg) _chipColors() {
    final c = _statusChip();
    switch (c) {
      case 'Completed': return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'Cancelled': return (const Color(0xFFFFCDD2), const Color(0xFFC62828));
      case 'Missed': return (const Color(0xFFFFF3CD), const Color(0xFF8A6D3B));
      default: return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month-1]} ${d.year}';
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final start = (m['startAt'] as Timestamp?)?.toDate();
    final end = (m['endAt'] as Timestamp?)?.toDate();
    final venue = (m['venue'] ?? m['location'] ?? 'Campus').toString();
    final (bg, fg) = _chipColors();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sessionTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Date: ${start != null ? _fmtDate(start) : '—'}', style: t.bodySmall),
                Text(
                  'Time: ${start != null && end != null ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}' : '—'}',
                  style: t.bodySmall,
                ),
                Text('Venue: $venue', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: fg)),
            child: Text(_statusChip(), style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/* ============================== Students list ============================== */

class _StudentsList extends StatelessWidget {
  final String helperId;
  final String studentReportRoute; // e.g. '/counsellor/student-report'
  const _StudentsList({required this.helperId, required this.studentReportRoute});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperId)
          .get(),
      builder: (context, snap) {
        // Group by real studentId (ignore null / HOP-only appointments)
        final byStudent = <String, List<Map<String, dynamic>>>{};
        for (final d in (snap.data?.docs ?? const [])) {
          final m = d.data();
          final sid = _studentIdOf(m);
          if (sid == null) continue;
          (byStudent[sid] ??= <Map<String, dynamic>>[]).add(m);
        }

        if (byStudent.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
            ),
            child: const Text('No students yet.'),
          );
        }

        return Column(
          children: byStudent.entries.map((e) {
            final sid = e.key;
            final sessions = e.value;
            final completed = sessions
                .where((a) => (a['status'] ?? '').toString().toLowerCase().trim() == 'completed')
                .length;

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(sid).get(),
              builder: (context, us) {
                final um = us.data?.data() ?? {};
                final name = _pickName(um);
                String? photoUrl;
                for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
                  final v = um[k];
                  if (v is String && v.trim().isNotEmpty) {
                    photoUrl = v.trim();
                    break;
                  }
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE3EAFD)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
                        child: (photoUrl == null || photoUrl!.isEmpty)
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                            Text('$completed completed', style: t.bodySmall?.copyWith(color: Colors.black54)),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 30,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.black),
                          onPressed: () => Navigator.pushNamed(
                            context,
                            studentReportRoute,
                            arguments: {'studentId': sid},
                          ),
                          child: const Text('View'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}
