// lib/student_progress_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'services/gemini_service.dart';

class StudentProgressPage extends StatefulWidget {
  const StudentProgressPage({super.key});

  @override
  State<StudentProgressPage> createState() => _StudentProgressPageState();
}

class _StudentProgressPageState extends State<StudentProgressPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  _Prediction _predictionFromString(String s) {
    switch (s.toLowerCase()) {
      case 'high':
        return _Prediction.high;
      case 'medium':
      case 'moderate':
      case 'borderline':
        return _Prediction.medium;
      case 'low':
        return _Prediction.low;
      default:
        return _Prediction.medium;
    }
  }

  // REMOVED: _predictionFromPercent(num? p) - now using Gemini instead

  int _bestEpoch(Map<String, dynamic> m) {
    Timestamp? ts;
    if (m['updatedAtClient'] is Timestamp) {
      ts = m['updatedAtClient'] as Timestamp;
    } else if (m['updatedAt'] is Timestamp) {
      ts = m['updatedAt'] as Timestamp;
    } else if (m['createdAt'] is Timestamp) {
      ts = m['createdAt'] as Timestamp;
    }
    return ts?.millisecondsSinceEpoch ?? 0;
  }

  String _monthYear(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  /// Convert latest doc's `pastGrades` into grade points (label + percent).
  List<_GradePoint> _pastFromLatestDoc(Map<String, dynamic> latest) {
    final out = <_GradePoint>[];
    final list = latest['pastGrades'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          final label = (e['label'] ?? '').toString().trim();
          final p = e['percent'];
          final pct = (p is num) ? p.toInt() : int.tryParse('$p' '');
          if (label.isNotEmpty && pct != null) {
            out.add(_GradePoint(label: label, percent: pct));
          }
        }
      }
    }
    return out;
  }

  /// Fallback: build up to 3 "previous grades" from historical snapshots.
  List<_GradePoint> _pastFromHistory(List<Map<String, dynamic>> list) {
    final out = <_GradePoint>[];
    for (final m in list.take(3)) {
      final ts = (m['updatedAtClient'] is Timestamp)
          ? m['updatedAtClient'] as Timestamp
          : (m['updatedAt'] is Timestamp)
          ? m['updatedAt'] as Timestamp
          : (m['createdAt'] is Timestamp)
          ? m['createdAt'] as Timestamp
          : null;
      final dt = ts?.toDate();
      final pct = (m['currentPercent'] is num)
          ? (m['currentPercent'] as num).toInt()
          : null;
      if (dt != null && pct != null) {
        out.add(_GradePoint(label: _monthYear(dt), percent: pct));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StudentHeader(),
              const SizedBox(height: 16),

              Text('Progress Tracker',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Monitor your academic performance based on grades',
                  style: t.bodySmall),
              const SizedBox(height: 12),

              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by subject',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (uid == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Text('Please sign in to view your progress.'),
                )
              else
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('student_progress')
                      .where('studentId', isEqualTo: uid)
                      .snapshots(includeMetadataChanges: true),
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
                      return Text(
                        'Error: ${snap.error}',
                        style: t.bodyMedium?.copyWith(color: Colors.red),
                      );
                    }

                    final docs = snap.data?.docs ?? const [];

                    // Group by subject
                    final Map<String, List<Map<String, dynamic>>> bySubject = {};
                    for (final d in docs) {
                      final m = d.data();
                      final subject =
                      (m['subject'] ?? '').toString().trim().isEmpty
                          ? 'Untitled Subject'
                          : (m['subject'] as String).trim();
                      (bySubject[subject] ??= <Map<String, dynamic>>[]).add(m);
                    }

                    // Build cards
                    final items = <_SubjectProgress>[];
                    bySubject.forEach((subject, list) {
                      list.sort((a, b) => _bestEpoch(b).compareTo(_bestEpoch(a)));

                      final latest = list.first;
                      final currentPct = (latest['currentPercent'] is num)
                          ? (latest['currentPercent'] as num).toInt()
                          : null;

                      final predictionStr =
                      (latest['prediction'] ?? '').toString();
                      final prediction = (predictionStr.isNotEmpty)
                          ? _predictionFromString(predictionStr)
                          : _Prediction.medium; // CHANGED: Default to medium, will be replaced by Gemini

                      // 1) prefer explicit pastGrades from the latest doc
                      var prev = _pastFromLatestDoc(latest);
                      // 2) if empty, fallback to historical snapshot-based
                      if (prev.isEmpty) prev = _pastFromHistory(list);

                      // ADDED: Prepare data for Gemini API
                      final pastGradesForAI = prev.map((gp) => {
                        'label': gp.label,
                        'percent': gp.percent,
                      }).toList();

                      items.add(_SubjectProgress(
                        name: subject,
                        currentPercent: currentPct ?? 0,
                        previous: prev,
                        prediction: prediction,
                        pastGradesForAI: pastGradesForAI,
                        savedPrediction: predictionStr.isNotEmpty ? predictionStr : null, // ADDED
                      ));
                    });

                    // Sort subjects by latest update (desc)
                    items.sort((a, b) {
                      DateTime epochOf(_SubjectProgress s) {
                        final list = bySubject[s.name]!;
                        final m = list.first;
                        final millis = _bestEpoch(m);
                        return DateTime.fromMillisecondsSinceEpoch(millis);
                      }

                      return epochOf(b).compareTo(epochOf(a));
                    });

                    // Search
                    final q = _searchCtrl.text.trim().toLowerCase();
                    final filtered = (q.isEmpty)
                        ? items
                        : items.where((s) => s.name.toLowerCase().contains(q)).toList();

                    if (filtered.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Text('No progress data found.'),
                      );
                    }

                    return Column(
                      children: filtered
                          .map((sp) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ProgressCard(subject: sp),
                      ))
                          .toList(),
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

/* --------------------------------- Models -------------------------------- */

class _SubjectProgress {
  final String name;
  final int currentPercent;
  final List<_GradePoint> previous;
  final _Prediction prediction;
  final List<Map<String, dynamic>> pastGradesForAI;
  final String? savedPrediction; // ADDED: Prediction from Firebase

  const _SubjectProgress({
    required this.name,
    required this.currentPercent,
    required this.previous,
    required this.prediction,
    required this.pastGradesForAI,
    this.savedPrediction, // ADDED
  });
}

class _GradePoint {
  final String label; // label from pastGrades OR month-year fallback
  final int percent;

  const _GradePoint({required this.label, required this.percent});
}

enum _Prediction { high, medium, low }

/* -------------------------------- Widgets -------------------------------- */

class _StudentHeader extends StatelessWidget {
  const _StudentHeader();

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
          child: Text(
            'PEERS',
            style: t.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student', style: t.titleMedium),
              Text('Portal',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // logout (matches other screens)
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _logout(context),
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

// CHANGED: StatelessWidget -> StatefulWidget to fetch Gemini prediction
class _ProgressCard extends StatefulWidget {
  final _SubjectProgress subject;
  const _ProgressCard({required this.subject});

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  String? _geminiPrediction; // ADDED: Store the Gemini result
  bool _isLoading = true; // ADDED: Loading state

  @override
  void initState() {
    super.initState();
    _fetchPrediction(); // ADDED: Fetch prediction on init
  }

  // ADDED: Fetch prediction from Gemini (only if not saved in Firebase)
  Future<void> _fetchPrediction() async {
    // If prediction already saved in Firebase, use it (no API call needed)
    if (widget.subject.savedPrediction != null && widget.subject.savedPrediction!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _geminiPrediction = widget.subject.savedPrediction;
          _isLoading = false;
        });
      }
      print('✅ Using saved prediction from Firebase: ${widget.subject.savedPrediction}');
      return;
    }

    // Only call API if prediction not in Firebase
    print('⚠️ No saved prediction, calling Gemini API...');
    try {
      final result = await GeminiService.getPrediction(
        subject: widget.subject.name,
        currentGrade: widget.subject.currentPercent,
        pastGrades: widget.subject.pastGradesForAI,
      );
      if (mounted) {
        setState(() {
          _geminiPrediction = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching Gemini prediction: $e');
      if (mounted) {
        setState(() {
          _geminiPrediction = '—';
          _isLoading = false;
        });
      }
    }
  }

  Color _predictionColor(_Prediction p) {
    switch (p) {
      case _Prediction.high:
        return const Color(0xFF2E7D32);
      case _Prediction.medium:
        return const Color(0xFFF57C00);
      case _Prediction.low:
        return const Color(0xFFC62828);
    }
  }

  String _predictionText(_Prediction p) {
    switch (p) {
      case _Prediction.high:
        return 'High';
      case _Prediction.medium:
        return 'Medium';
      case _Prediction.low:
        return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final labelStyle = t.bodySmall?.copyWith(color: Colors.black45);

    final leftBox = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Current Grade', style: labelStyle),
        const SizedBox(height: 4),
        Text('${widget.subject.currentPercent}%',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Text('Prediction of passing', style: labelStyle),
        const SizedBox(height: 4),
        // CHANGED: Display Gemini prediction instead of hardcoded value
        _isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Text(
          _geminiPrediction ?? '—',
          style: t.titleMedium?.copyWith(
            color: _predictionColor(widget.subject.prediction),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    final rightBox = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Previous grades', style: labelStyle),
        const SizedBox(height: 4),
        if (widget.subject.previous.isEmpty)
          Text('—', style: t.bodyMedium)
        else
          for (final gp in widget.subject.previous)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(gp.label, style: t.bodyMedium)),
                  const SizedBox(width: 12),
                  Text('${gp.percent}%', style: t.bodyMedium),
                ],
              ),
            ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subject.name,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 360;

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leftBox,
                    const SizedBox(height: 12),
                    rightBox,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftBox),
                  const SizedBox(width: 12),
                  Expanded(child: rightBox),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}