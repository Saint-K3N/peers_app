// lib/hop_student_report_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HopStudentReportPage extends StatelessWidget {
  const HopStudentReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final studentId = (args['studentId'] as String?) ?? '';
    final studentName = (args['studentName'] as String?) ?? '';
    // ✅ default to the collection this app writes to
    final collection = (args['collection'] as String?) ?? 'student_progress';

    if (studentId.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Missing studentId.\nOpen this page by tapping a student’s View button.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              const SizedBox(height: 16),

              Text(
                'Student Report - ${studentName.isNotEmpty ? studentName : 'Student'}',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text('View student report managed by tutor', style: t.bodySmall),
              const SizedBox(height: 12),

              _ProgressStream(studentId: studentId, collection: collection),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------------------- Header -------------------------------- */

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
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
              style: tt.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 12),

        // titles
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HOP', style: tt.titleMedium),
            Text('Portal', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),

        const Spacer(),

        // share (placeholder)
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: const Icon(Icons.ios_share, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

/* ----------------------- Progress Loader + Renderer ---------------------- */

class _ProgressStream extends StatelessWidget {
  final String studentId;
  final String collection; // usually 'student_progress'
  const _ProgressStream({required this.studentId, required this.collection});

  Stream<List<_SubjectProgress>> _primary() {
    if (collection == 'users_progress') {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(studentId)
          .collection('progress')
          .snapshots()
          .map(_mapQuery);
    }
    // default: top-level collection with studentId field
    return FirebaseFirestore.instance
        .collection(collection)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map(_mapQuery);
  }

  Stream<List<_SubjectProgress>> _fallback() {
    // nested fallback
    return FirebaseFirestore.instance
        .collection('users')
        .doc(studentId)
        .collection('progress')
        .snapshots()
        .map(_mapQuery);
  }

  // Try primary; if first emission is empty, switch to fallback
  Stream<List<_SubjectProgress>> _stream() async* {
    List<_SubjectProgress>? first;
    await for (final p in _primary()) {
      first ??= p;
      if ((first ?? const []).isEmpty) {
        yield* _fallback();
        return;
      } else {
        yield p;
      }
    }
  }

  List<_SubjectProgress> _mapQuery(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs
        .map((d) => _SubjectProgress.fromMap(d.id, d.data()))
        .where((s) => s.title.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return StreamBuilder<List<_SubjectProgress>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
        }

        final subjects = snap.data ?? const <_SubjectProgress>[];
        if (subjects.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Text('No progress reported yet.'),
          );
        }

        return Column(
          children: [
            for (final s in subjects) ...[
              _ReportCard(subject: s),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/* ------------------------------- Data Models ------------------------------ */

class _SubjectProgress {
  final String id;
  final String title;
  final double currentPercent; // 0-100
  final List<_PrevGrade> previous; // label + percent
  final String prediction; // High | Average | Low | etc.

  _SubjectProgress({
    required this.id,
    required this.title,
    required this.currentPercent,
    required this.previous,
    required this.prediction,
  });

  factory _SubjectProgress.fromMap(String id, Map<String, dynamic> m) {
    double _toDouble(Object? x) {
      if (x is num) return x.toDouble();
      return double.tryParse(x?.toString() ?? '') ?? 0;
    }

    List<_PrevGrade> _parsePrev(Object? x) {
      // Supports:
      //  - [{'label':'Apr 2024','percent':92}, ...]  ✅ your current schema: pastGrades
      //  - {'Apr 2024': 92, 'Aug 2024': 86}
      //  - [92, 86, 79]  (no labels)
      final out = <_PrevGrade>[];
      if (x is List) {
        for (final e in x) {
          if (e is Map) {
            final mm = e.cast<String, dynamic>();
            out.add(_PrevGrade(
              label: (mm['label'] ?? mm['date'] ?? mm['title'] ?? '').toString(),
              percent: _toDouble(mm['percent'] ?? mm['value']),
            ));
          } else {
            out.add(_PrevGrade(label: '', percent: _toDouble(e)));
          }
        }
      } else if (x is Map) {
        final mm = x.cast<String, dynamic>();
        for (final entry in mm.entries) {
          out.add(_PrevGrade(label: entry.key, percent: _toDouble(entry.value)));
        }
      }
      return out;
    }

    return _SubjectProgress(
      id: id,
      title: (m['title'] ?? m['subject'] ?? m['course'] ?? '').toString(),
      currentPercent:
      _toDouble(m['current'] ?? m['currentPercent'] ?? m['grade']),
      // ✅ include 'pastGrades' in the accepted keys
      previous: _parsePrev(m['pastGrades'] ?? m['previous'] ?? m['previousGrades']),
      prediction:
      (m['prediction'] ?? m['predictionOfPassing'] ?? '').toString(),
    );
  }
}

class _PrevGrade {
  final String label;
  final double percent;
  _PrevGrade({required this.label, required this.percent});
}

/* -------------------------------- Widgets -------------------------------- */

class _ReportCard extends StatelessWidget {
  final _SubjectProgress subject;
  const _ReportCard({required this.subject});

  (Color, String) _predictionStyle(String p) {
    final v = p.trim().toLowerCase();
    if (v == 'high') return (const Color(0xFF2E7D32), 'High');
    if (v == 'average') return (const Color(0xFFF39C12), 'Average');
    if (v == 'low') return (const Color(0xFFC62828), 'Low');
    // fallback (keep whatever string was stored)
    return (const Color(0xFF6B7280), p.isEmpty ? '—' : subject.prediction);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (predColor, predText) = _predictionStyle(subject.prediction);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFD8DC), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject title
          Text(subject.title,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          // Current vs Previous
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current grade
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Grade',
                        style:
                        t.bodySmall?.copyWith(color: Colors.black54)),
                    Text('${subject.currentPercent.toStringAsFixed(0)}%',
                        style: t.titleMedium),
                  ],
                ),
              ),

              // Previous grades
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Previous grades',
                        style:
                        t.bodySmall?.copyWith(color: Colors.black54)),
                    const SizedBox(height: 2),
                    if (subject.previous.isEmpty)
                      Text('—', style: t.bodyMedium)
                    else
                      for (final g in subject.previous.take(6))
                        Text(
                          '${g.label.isNotEmpty ? '${g.label} ' : ''}${g.percent.toStringAsFixed(0)}%',
                          style: t.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Prediction of passing
          Text('Prediction of passing',
              style: t.bodySmall?.copyWith(color: Colors.black54)),
          const SizedBox(height: 2),
          Text(predText,
              style: t.bodyMedium
                  ?.copyWith(color: predColor, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
