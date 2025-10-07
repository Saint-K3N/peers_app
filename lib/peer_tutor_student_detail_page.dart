// lib/peer_tutor_student_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PeerTutorStudentDetailPage extends StatefulWidget {
  const PeerTutorStudentDetailPage({super.key});

  @override
  State<PeerTutorStudentDetailPage> createState() => _PeerTutorStudentDetailPageState();
}

class _PeerTutorStudentDetailPageState extends State<PeerTutorStudentDetailPage> {
  int _tab = 0; // 0 = Sessions, 1 = Progress

  // Progress form controllers (subject + current + dynamic "previous grades")
  final _subjectCtrl = TextEditingController();
  final _currentGradeCtrl = TextEditingController();
  final List<TextEditingController> _pastLabelCtrls = [];
  final List<TextEditingController> _pastPercentCtrls = [];

  String get _tutorUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _ensureMinPastRows(1); // start with one row for previous grades
  }

  void _ensureMinPastRows(int n) {
    while (_pastLabelCtrls.length < n) {
      _pastLabelCtrls.add(TextEditingController());
    }
    while (_pastPercentCtrls.length < n) {
      _pastPercentCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _currentGradeCtrl.dispose();
    for (final c in _pastLabelCtrls) c.dispose();
    for (final c in _pastPercentCtrls) c.dispose();
    super.dispose();
  }

  // ---- helpers -------------------------------------------------------------

  String _pickName(Map<String, dynamic> m) {
    for (final k in const ['fullName','full_name','name','displayName','display_name']) {
      final v = m[k]; if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in const ['fullName','full_name','name','displayName','display_name']) {
        final v = prof[k]; if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return 'Student';
  }

  String _pickEmail(Map<String, dynamic> m) {
    for (final k in const ['email','emailAddress']) {
      final v = m[k]; if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '—';
  }

  String _pickAvatar(Map<String, dynamic> m) {
    for (final k in const ['photoUrl','avatarUrl','photoURL']) {
      final v = m[k]; if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in const ['photoUrl','avatarUrl']) {
        final v = prof[k]; if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  // read common schemas: academicInterestIds & counselingTopicIds (plus fallbacks)
  List<String> _extractInterestIds(Map<String, dynamic> m) {
    final out = <String>{};
    void absorb(dynamic v) {
      if (v == null) return;
      if (v is List) {
        for (final e in v) {
          if (e is String && e.trim().isNotEmpty) out.add(e.trim());
          else if (e is Map && e['id'] is String) out.add((e['id'] as String).trim());
          else if (e is DocumentReference) out.add(e.id);
        }
      } else if (v is Map) {
        v.forEach((key, val) {
          if (key is String && key.trim().isNotEmpty) out.add(key.trim());
        });
      } else if (v is String && v.trim().isNotEmpty) {
        out.add(v.trim());
      }
    }
    absorb(m['academicInterestIds']);
    absorb(m['counselingTopicIds']);
    for (final k in const ['interestIds','interests','interest_ids','interests_ids']) {
      absorb(m[k]);
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      absorb(prof['academicInterestIds']);
      absorb(prof['counselingTopicIds']);
      for (final k in const ['interestIds','interests','interest_ids','interests_ids']) {
        absorb(prof[k]);
      }
    }
    return out.toList();
  }

  String _fmtDateLong(DateTime d) {
    const months = [
      'January','February','March','April','May','June','July','August','September','October','November','December'
    ];
    String ord(int n){
      if(n>=11 && n<=13) return 'th';
      switch(n%10){case 1:return 'st';case 2:return 'nd';case 3:return 'rd';default:return 'th';}
    }
    return '${d.day}${ord(d.day)} ${months[d.month-1]} ${d.year}';
  }

  String _fmtTime(TimeOfDay t){
    final h = t.hourOfPeriod==0?12:t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2,'0');
    final ap = t.period==DayPeriod.am?'AM':'PM';
    return '$h:$m $ap';
  }

  String _statusChipLabel(String statusRaw, DateTime start) {
    final s = statusRaw.toLowerCase();
    if (s == 'completed') return 'Completed';
    if (s == 'cancelled') return 'Cancelled';
    if (DateTime.now().isBefore(start)) return 'Upcoming';
    return 'Pending';
  }

  (Color bg, Color fg) _statusColors(String label){
    switch(label){
      case 'Upcoming': return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
      case 'Completed': return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'Cancelled': return (const Color(0xFFFFCDD2), const Color(0xFFC62828));
      default: return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
    }
  }

  String _passPrediction(num? currentPct){
    if (currentPct == null) return '—';
    if (currentPct >= 75) return 'High';
    if (currentPct >= 60) return 'Moderate';
    if (currentPct >= 50) return 'Borderline';
    return 'Low';
  }

  // save a grade entry
  Future<void> _saveGrade(String studentId) async {
    final subject = _subjectCtrl.text.trim();
    final currentPct = num.tryParse(_currentGradeCtrl.text.trim());

    if (subject.isEmpty || currentPct == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter subject and current grade (as %).')),
      );
      return;
    }

    // Collect all "previous grades" rows (label + percent)
    final past = <Map<String, dynamic>>[];
    final rows = (_pastLabelCtrls.length > _pastPercentCtrls.length)
        ? _pastLabelCtrls.length
        : _pastPercentCtrls.length;
    for (int i=0;i<rows;i++){
      final l = (i < _pastLabelCtrls.length) ? _pastLabelCtrls[i].text.trim() : '';
      final p = (i < _pastPercentCtrls.length) ? num.tryParse(_pastPercentCtrls[i].text.trim()) : null;
      if (l.isNotEmpty && p != null) {
        past.add({'label': l, 'percent': p});
      }
    }

    final nowClient = Timestamp.now();
    final doc = {
      'studentId': studentId,
      'tutorId': _tutorUid,
      'subject': subject,
      'currentPercent': currentPct,
      'pastGrades': past,                // <-- multiple previous grades saved here
      'prediction': _passPrediction(currentPct),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtClient': nowClient,      // for instant client-side sort
    };

    await FirebaseFirestore.instance.collection('student_progress').add(doc);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grade added.')));

    // clear form
    _subjectCtrl.clear();
    _currentGradeCtrl.clear();

    for (final c in _pastLabelCtrls) c.dispose();
    for (final c in _pastPercentCtrls) c.dispose();
    _pastLabelCtrls.clear();
    _pastPercentCtrls.clear();
    _ensureMinPastRows(1);

    setState((){});
  }

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final studentId = (args['studentId'] as String?) ?? '';

    return Scaffold(
      body: SafeArea(
        child: studentId.isEmpty
            ? const Center(child: Text('Missing studentId'))
            : _Body(
          studentId: studentId,
          tab: _tab,
          onTab: (i)=>setState(()=>_tab=i),

          // form controllers
          subjectCtrl: _subjectCtrl,
          currentGradeCtrl: _currentGradeCtrl,
          pastLabelCtrls: _pastLabelCtrls,
          pastPercentCtrls: _pastPercentCtrls,
          onAddPast: (){
            _pastLabelCtrls.add(TextEditingController());
            _pastPercentCtrls.add(TextEditingController());
            setState((){});
          },
          onSave: ()=>_saveGrade(studentId),

          // helpers
          pickName: _pickName,
          pickEmail: _pickEmail,
          pickAvatar: _pickAvatar,
          extractInterestIds: _extractInterestIds,

          statusChipLabel: _statusChipLabel,
          statusColors: _statusColors,
          fmtDateLong: _fmtDateLong,
          fmtTime: _fmtTime,
          passPrediction: _passPrediction,
        ),
      ),
    );
  }
}

/* ------------------------------- BODY WIDGET ------------------------------- */

class _Body extends StatelessWidget {
  final String studentId;
  final int tab;
  final void Function(int) onTab;

  // progress form plumbing
  final TextEditingController subjectCtrl;
  final TextEditingController currentGradeCtrl;
  final List<TextEditingController> pastLabelCtrls;
  final List<TextEditingController> pastPercentCtrls;
  final VoidCallback onAddPast;
  final VoidCallback onSave;

  // helpers passed in
  final String Function(Map<String, dynamic>) pickName;
  final String Function(Map<String, dynamic>) pickEmail;
  final String Function(Map<String, dynamic>) pickAvatar;
  final List<String> Function(Map<String, dynamic>) extractInterestIds;

  // other helpers
  final String Function(String, DateTime) statusChipLabel;
  final (Color, Color) Function(String) statusColors;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;
  final String Function(num?) passPrediction;

  const _Body({
  required this.studentId,
  required this.tab,
  required this.onTab,
  required this.subjectCtrl,
  required this.currentGradeCtrl,
  required this.pastLabelCtrls,
  required this.pastPercentCtrls,
  required this.onAddPast,
  required this.onSave,
  required this.pickName,
  required this.pickEmail,
  required this.pickAvatar,
  required this.extractInterestIds,
  required this.statusChipLabel,
  required this.statusColors,
  required this.fmtDateLong,
  required this.fmtTime,
  required this.passPrediction,
  });

  @override
  Widget build(BuildContext context) {
  final t = Theme.of(context).textTheme;

  final userDocStream = FirebaseFirestore.instance.collection('users').doc(studentId).snapshots();
  final interestsStream = FirebaseFirestore.instance.collection('interests').snapshots();

  return SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  const _HeaderBarDetail(),
  const SizedBox(height: 16),

  Text('My Students', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
  const SizedBox(height: 4),
  Text('Manage your students', style: t.bodySmall),
  const SizedBox(height: 10),

  // Top-right action button changes with tab (Remove vs Add Grade)
  Align(
  alignment: Alignment.centerRight,
  child: SizedBox(
  height: 32,
  child: FilledButton(
  style: FilledButton.styleFrom(
  backgroundColor: tab == 0 ? const Color(0xFFFF2D55) : Colors.black,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  onPressed: () async {
  if (tab == 0) {
  // Sessions tab: remove/hide student from list
  final tutorId = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (tutorId.isEmpty) return;
  final ok = await showDialog<bool>(
  context: context,
  builder: (_) => AlertDialog(
  title: const Text('Remove student'),
  content: const Text('This hides the student from your list (does not delete appointments).'),
  actions: [
  TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Close')),
  FilledButton(
  style: FilledButton.styleFrom(backgroundColor: Colors.red),
  onPressed: ()=>Navigator.pop(context,true),
  child: const Text('Remove'),
  ),
  ],
  ),
  );
  if (ok == true && context.mounted) {
  await FirebaseFirestore.instance.collection('tutor_student_links').doc('${tutorId}_$studentId').set({
  'helperId': tutorId,
  'studentId': studentId,
  'archived': true,
  'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student removed.')));
  Navigator.maybePop(context);
  }
  } else {
  // Progress tab: save grade
  onSave();
  }
  },
  child: Text(tab == 0 ? 'Remove' : '+  Add Grade'),
  ),
  ),
  ),
  const SizedBox(height: 10),

  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: userDocStream,
  builder: (context, userSnap) {
  if (userSnap.hasError) {
  return Text('Error: ${userSnap.error}', style: const TextStyle(color: Colors.red));
  }
  final udata = userSnap.data?.data() ?? <String, dynamic>{};
  final name = pickName(udata);
  final email = pickEmail(udata);
  final avatar = pickAvatar(udata);
  final ids = extractInterestIds(udata);

  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: interestsStream,
  builder: (context, intSnap) {
  if (intSnap.hasError) {
  return Text('Error: ${intSnap.error}', style: const TextStyle(color: Colors.red));
  }
  final imap = <String,String>{};
  for (final d in (intSnap.data?.docs ?? const [])) {
  final m = d.data();
  final id = d.id;
  final title = (m['title'] ?? m['name'] ?? '').toString();
  if (title.isNotEmpty) imap[id] = title;
  }
  final interestTitles = ids.map((id)=>imap[id]).whereType<String>().toList();

  // Last session date (compute from appointments)
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('appointments')
      .where('studentId', isEqualTo: studentId)
      .where('helperId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
      .snapshots(includeMetadataChanges: true),
  builder: (context, appsSnap) {
  if (appsSnap.hasError) {
  return Text('Error: ${appsSnap.error}', style: const TextStyle(color: Colors.red));
  }
  DateTime? last;
  for (final d in (appsSnap.data?.docs ?? const [])) {
  final ts = d.data()['startAt'];
  if (ts is Timestamp) {
  final dt = ts.toDate();
  if (last == null || dt.isAfter(last!)) last = dt;
  }
  }

  return Column(
  children: [
  _StudentHeaderCard(
  name: name,
  email: email,
  avatarUrl: avatar,
  interests: interestTitles,
  lastSession: last,
  ),
  const SizedBox(height: 12),

  _Tabs(active: tab, onTap: onTab),
  const SizedBox(height: 12),

  if (tab == 0)
  _SessionsList(
  studentId: studentId,
  fmtDateLong: fmtDateLong,
  fmtTime: fmtTime,
  statusChipLabel: statusChipLabel,
  statusColors: statusColors,
  )
  else
  _ProgressSection(
  studentId: studentId,
  subjectCtrl: subjectCtrl,
  currentGradeCtrl: currentGradeCtrl,
  pastLabelCtrls: pastLabelCtrls,
  pastPercentCtrls: pastPercentCtrls,
  onAddPast: onAddPast,
  passPrediction: passPrediction,
  ),
  ],
  );
  },
  );
  },
  );
  },
  ),
  ],
  ),
  );
  }
}

/* ------------------------------ Header Bars ------------------------------ */

class _HeaderBarDetail extends StatelessWidget {
  const _HeaderBarDetail();

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

/* --------------------------- Student Header Card -------------------------- */

class _StudentHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String avatarUrl;
  final List<String> interests;
  final DateTime? lastSession;

  const _StudentHeaderCard({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.interests,
    required this.lastSession,
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
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
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
                Row(children: [
                  Expanded(child: Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  const Icon(Icons.change_history, color: Colors.black54, size: 20),
                ]),
                const SizedBox(height: 4),
                Text(
                  interests.isNotEmpty
                      ? 'Interests: ${interests.take(3).join(', ')}${interests.length > 3 ? ', …' : ''}'
                      : 'Interests: —',
                  style: t.bodySmall,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Session:', style: t.labelSmall?.copyWith(color: Colors.black54)),
                          Text(lastSession != null ? _fmtDate(lastSession!) : '—', style: t.bodySmall),
                        ],
                      ),
                    ),
                    Text(email, style: t.bodySmall?.copyWith(color: Colors.black54)),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

/* --------------------------------- Tabs ---------------------------------- */

class _Tabs extends StatelessWidget {
  final int active;
  final void Function(int) onTap;
  const _Tabs({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Widget btn(String label, int i) {
      final selected = active == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.black87 : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label, style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('Sessions', 0),
        const SizedBox(width: 8),
        btn('Progress', 1),
      ],
    );
  }
}

/* ------------------------------- Sessions -------------------------------- */

class _SessionsList extends StatelessWidget {
  final String studentId;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;
  final String Function(String, DateTime) statusChipLabel;
  final (Color, Color) Function(String) statusColors;

  const _SessionsList({
  required this.studentId,
  required this.fmtDateLong,
  required this.fmtTime,
  required this.statusChipLabel,
  required this.statusColors,
  });

  @override
  Widget build(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final tutorId = FirebaseAuth.instance.currentUser?.uid ?? '';

  final q = FirebaseFirestore.instance
      .collection('appointments')
      .where('helperId', isEqualTo: tutorId)
      .where('studentId', isEqualTo: studentId);

  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: q.snapshots(includeMetadataChanges: true),
  builder: (context, snap) {
  if (snap.hasError) {
  return Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red));
  }
  if (snap.connectionState == ConnectionState.waiting) {
  return const Padding(
  padding: EdgeInsets.symmetric(vertical: 16),
  child: Center(child: CircularProgressIndicator()),
  );
  }
  final docs = (snap.data?.docs ?? const [])
  ..sort((a,b) {
  final at = (a.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
  final bt = (b.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
  return bt.compareTo(at); // newest first
  });

  if (docs.isEmpty) {
  return Container(
  width: double.infinity,
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
  color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
  ),
  child: const Text('No sessions yet.'),
  );
  }

  return Column(
  children: [
  for (final d in docs) ...[
  _SessionTile(
  m: d.data(),
  fmtDateLong: fmtDateLong,
  fmtTime: fmtTime,
  statusChipLabel: statusChipLabel,
  statusColors: statusColors,
  ),
  const SizedBox(height: 10),
  ],
  ],
  );
  },
  );
  }
}

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> m;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;
  final String Function(String, DateTime) statusChipLabel;
  final (Color, Color) Function(String) statusColors;

  const _SessionTile({
  required this.m,
  required this.fmtDateLong,
  required this.fmtTime,
  required this.statusChipLabel,
  required this.statusColors,
  });

  @override
  Widget build(BuildContext context) {
  final t = Theme.of(context).textTheme;

  final st = (m['startAt'] as Timestamp?)?.toDate();
  final en = (m['endAt'] as Timestamp?)?.toDate();
  final statusRaw = (m['status'] ?? 'pending').toString();
  final label = statusChipLabel(statusRaw, st ?? DateTime.now());
  final (bg, fg) = statusColors(label);

  final date = (st != null) ? fmtDateLong(st) : '—';
  final time = (st != null && en != null)
  ? '${fmtTime(TimeOfDay.fromDateTime(st))} - ${fmtTime(TimeOfDay.fromDateTime(en))}'
      : '—';

  // venue/mode
  final mode = (m['mode'] ?? '').toString().toLowerCase();
  final venue = () {
  if (mode == 'online') {
  final meet = (m['meetUrl'] ?? '').toString();
  return meet.isNotEmpty ? 'Online ($meet)' : 'Online';
  }
  final v = (m['venue'] ?? m['location'] ?? '').toString();
  return v.isNotEmpty ? v : 'Campus';
  }();

  return Container(
  decoration: BoxDecoration(
  color: Colors.white, borderRadius: BorderRadius.circular(10),
  border: Border.all(color: Colors.black12),
  ),
  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
  child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  Row(children: [
  Expanded(child: Text('Tutoring for ${m['studentName'] ?? 'Student'}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
  Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withOpacity(.3))),
  child: Text(label, style: t.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
  )
  ]),
  const SizedBox(height: 6),
  Text('Date: $date', style: t.bodySmall),
  Text('Time: $time', style: t.bodySmall),
  Text('Venue: $venue', style: t.bodySmall),
  ],
  ),
  );
  }
}

/* ------------------------------- Progress -------------------------------- */

class _ProgressSection extends StatelessWidget {
  final String studentId;
  final TextEditingController subjectCtrl;
  final TextEditingController currentGradeCtrl;
  final List<TextEditingController> pastLabelCtrls;
  final List<TextEditingController> pastPercentCtrls;
  final VoidCallback onAddPast;
  final String Function(num?) passPrediction;

  const _ProgressSection({
    required this.studentId,
    required this.subjectCtrl,
    required this.currentGradeCtrl,
    required this.pastLabelCtrls,
    required this.pastPercentCtrls,
    required this.onAddPast,
    required this.passPrediction,
  });

  @override
  Widget build(BuildContext context) {
    final tutorId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) Entry form (preview removed; semester removed; MULTIPLE previous grades)
        _ProgressForm(
          subjectCtrl: subjectCtrl,
          currentGradeCtrl: currentGradeCtrl,
          pastLabelCtrls: pastLabelCtrls,
          pastPercentCtrls: pastPercentCtrls,
          onAddPast: onAddPast, // <-- Add More button
        ),
        const SizedBox(height: 12),

        // 2) All saved records (newest → oldest), below the form
        _ProgressList(studentId: studentId, tutorId: tutorId),
      ],
    );
  }
}

class _ProgressList extends StatelessWidget {
  final String studentId;
  final String tutorId;
  const _ProgressList({required this.studentId, required this.tutorId});

  int _epoch(Map<String, dynamic> m) {
    Timestamp? ts;
    if (m['updatedAtClient'] is Timestamp) ts = m['updatedAtClient'] as Timestamp;
    else if (m['updatedAt'] is Timestamp) ts = m['updatedAt'] as Timestamp;
    else if (m['createdAt'] is Timestamp) ts = m['createdAt'] as Timestamp;
    return ts?.millisecondsSinceEpoch ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final q = FirebaseFirestore.instance
        .collection('student_progress')
        .where('studentId', isEqualTo: studentId)
        .where('tutorId', isEqualTo: tutorId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = (snap.data?.docs ?? const []);
        if (docs.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Text('No saved progress yet. Add a grade to create the first record.', style: t.bodySmall),
          );
        }

        docs.sort((a, b) => _epoch(b.data()).compareTo(_epoch(a.data())));

        return Column(
          children: [
            for (final d in docs) ...[
              _ProgressCard(m: d.data()),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final Map<String, dynamic> m;
  const _ProgressCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final subject = (m['subject'] ?? '').toString();
    final current = (m['currentPercent'] is num) ? (m['currentPercent'] as num).toDouble() : null;
    final prediction = (m['prediction'] ?? '').toString();

    final past = <String>[];
    if (m['pastGrades'] is List) {
      for (final g in (m['pastGrades'] as List)) {
        if (g is Map) {
          final label = (g['label'] ?? '').toString();
          final pct = (g['percent'] is num) ? (g['percent'] as num).toString() : '';
          if (label.isNotEmpty && pct.isNotEmpty) past.add('$label ${pct}%');
        }
      }
    }

    Color predColor() {
      switch (prediction) {
        case 'High': return const Color(0xFF2E7D32);
        case 'Moderate': return const Color(0xFF8A6D3B);
        case 'Borderline': return const Color(0xFF8A6D3B);
        case 'Low': return const Color(0xFFC62828);
        default: return Colors.black87;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject.isEmpty ? 'Subject' : subject, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Grade', style: t.labelSmall?.copyWith(color: Colors.black54)),
                    Text(current != null ? '${current.toStringAsFixed(0)}%' : '—', style: t.bodyLarge),
                    const SizedBox(height: 8),
                    Text('Prediction of passing', style: t.labelSmall?.copyWith(color: Colors.black54)),
                    Text(prediction.isEmpty ? '—' : prediction,
                        style: t.bodyMedium?.copyWith(color: predColor())),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Previous grades', style: t.labelSmall?.copyWith(color: Colors.black54)),
                    if (past.isEmpty) Text('—', style: t.bodyMedium)
                    else ...past.map((s) => Text(s, style: t.bodyMedium)),
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

class _ProgressForm extends StatelessWidget {
  final TextEditingController subjectCtrl;
  final TextEditingController currentGradeCtrl;
  final List<TextEditingController> pastLabelCtrls;
  final List<TextEditingController> pastPercentCtrls;
  final VoidCallback onAddPast;

  const _ProgressForm({
    required this.subjectCtrl,
    required this.currentGradeCtrl,
    required this.pastLabelCtrls,
    required this.pastPercentCtrls,
    required this.onAddPast,
  });

  TextEditingController _getOrCreate(List<TextEditingController> list, int index) {
    while (list.length <= index) { list.add(TextEditingController()); }
    return list[index];
  }

  Widget _shell(Widget child) => Container(
    height: 44,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black26),
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          _shell(TextField(
            controller: subjectCtrl,
            decoration: const InputDecoration.collapsed(hintText: 'Insert Subject Title'),
          )),
          const SizedBox(height: 8),
          _shell(TextField(
            controller: currentGradeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration.collapsed(hintText: 'Insert Current Grade (e.g., 80)'),
          )),
          const SizedBox(height: 8),

          // First previous grade row
          Row(
            children: [
              Expanded(child: _shell(TextField(
                controller: _getOrCreate(pastLabelCtrls, 0),
                decoration: const InputDecoration.collapsed(hintText: 'Subject Name'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _shell(TextField(
                controller: _getOrCreate(pastPercentCtrls, 0),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration.collapsed(hintText: 'Percent (e.g., 86)'),
              ))),
            ],
          ),
          const SizedBox(height: 8),

          // Additional dynamic rows (beyond the first)
          if (pastLabelCtrls.length > 1 || pastPercentCtrls.length > 1)
            Column(
              children: [
                for (int i = 1; i < (pastLabelCtrls.length > pastPercentCtrls.length ? pastLabelCtrls.length : pastPercentCtrls.length); i++) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _shell(TextField(
                        controller: _getOrCreate(pastLabelCtrls, i),
                        decoration: const InputDecoration.collapsed(hintText: 'Subject Name'),
                      ))),
                      const SizedBox(width: 8),
                      Expanded(child: _shell(TextField(
                        controller: _getOrCreate(pastPercentCtrls, i),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration.collapsed(hintText: 'Percent'),
                      ))),
                    ],
                  ),
                ]
              ],
            ),

          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: onAddPast,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('+  Add More'),
            ),
          ),
        ],
      ),
    );
  }
}
