// lib/peer_counsellor_peer_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/* ---------- shared, top-level helpers (visible to all widgets in this file) --- */

String _fmtDateLong(DateTime d) {
  const months = [
    'January','February','March','April','May','June','July',
    'August','September','October','November','December'
  ];
  String ord(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) { case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th'; }
  }
  return '${d.day}${ord(d.day)} ${months[d.month-1]} ${d.year}';
}

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $ap';
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
  return 'Peer';
}

String _pickEmail(Map<String, dynamic> m) {
  for (final k in const ['email','emailAddress']) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '—';
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

/* ----------------------------------- PAGE ----------------------------------- */

class PeerCounsellorPeerDetailPage extends StatefulWidget {
  const PeerCounsellorPeerDetailPage({super.key});

  @override
  State<PeerCounsellorPeerDetailPage> createState() =>
      _PeerCounsellorPeerDetailPageState();
}

class _PeerCounsellorPeerDetailPageState
    extends State<PeerCounsellorPeerDetailPage> {
  int _tab = 0; // 0 = Sessions, 1 = Notes

  // Note form
  final _noteTitleCtrl = TextEditingController();
  final _noteBodyCtrl = TextEditingController();

  String get _helperUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _noteTitleCtrl.dispose();
    _noteBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNote(String peerId) async {
    final title = _noteTitleCtrl.text.trim();
    final body = _noteBodyCtrl.text.trim();

    if (title.isEmpty || body.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both title and note.')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('peer_notes').add({
      'helperId': _helperUid,
      'peerId': peerId,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtClient': Timestamp.now(),
    });

    if (!mounted) return;
    _noteTitleCtrl.clear();
    _noteBodyCtrl.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Note saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final peerId = (args['peerId'] as String?) ?? '';

    return Scaffold(
      body: SafeArea(
        child: peerId.isEmpty
            ? const Center(child: Text('Missing peerId'))
            : _Body(
          peerId: peerId,
          tab: _tab,
          onTab: (i) => setState(() => _tab = i),
          noteTitleCtrl: _noteTitleCtrl,
          noteBodyCtrl: _noteBodyCtrl,
          onSaveNote: () => _saveNote(peerId),
        ),
      ),
    );
  }
}

/* ----------------------------------- BODY ----------------------------------- */

class _Body extends StatelessWidget {
  final String peerId;
  final int tab;
  final void Function(int) onTab;

  final TextEditingController noteTitleCtrl;
  final TextEditingController noteBodyCtrl;
  final VoidCallback onSaveNote;

  const _Body({
    required this.peerId,
    required this.tab,
    required this.onTab,
    required this.noteTitleCtrl,
    required this.noteBodyCtrl,
    required this.onSaveNote,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final helperUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final userStream =
    FirebaseFirestore.instance.collection('users').doc(peerId).snapshots();

    // Last session date
    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperUid)
        .where('studentId', isEqualTo: peerId)
        .snapshots();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeaderBarDetail(),
          const SizedBox(height: 16),

          Text('My Peers',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Manage your Peers', style: t.bodySmall),
          const SizedBox(height: 10),

          // Peer header
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userStream,
            builder: (context, userSnap) {
              final um = userSnap.data?.data() ?? <String, dynamic>{};
              final name = _pickName(um);
              final email = _pickEmail(um);
              final avatar = _pickAvatar(um);

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: appsStream,
                builder: (context, appsSnap) {
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
                      _PeerHeaderCard(
                        name: name,
                        email: email,
                        avatarUrl: avatar,
                        lastSession: last,
                      ),
                      const SizedBox(height: 12),

                      _Tabs(active: tab, onTap: onTab),
                      const SizedBox(height: 12),

                      if (tab == 0)
                        _SessionsList(peerId: peerId)
                      else
                        _NotesSection(
                          peerId: peerId,
                          titleCtrl: noteTitleCtrl,
                          bodyCtrl: noteBodyCtrl,
                          onSave: onSaveNote,
                        ),
                    ],
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

/* --------------------------------- Header --------------------------------- */

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
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peer Counsellor', style: t.titleMedium),
            Text('Portal',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

/* ----------------------------- Peer header card ---------------------------- */

class _PeerHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String avatarUrl;
  final DateTime? lastSession;

  const _PeerHeaderCard({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.lastSession,
  });

  String _fmtShort(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

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
            height: 44,
            width: 44,
            decoration:
            BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
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
                  Expanded(
                      child: Text(name,
                          style: t.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700))),
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.black54, size: 20),
                ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last Session:',
                              style:
                              t.labelSmall?.copyWith(color: Colors.black54)),
                          Text(lastSession != null ? _fmtShort(lastSession!) : '—',
                              style: t.bodySmall),
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

/* ---------------------------------- Tabs ---------------------------------- */

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
            child: Text(label,
                style: t.labelMedium
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('Sessions', 0),
        const SizedBox(width: 8),
        btn('Notes', 1),
      ],
    );
  }
}

/* -------------------------------- Sessions -------------------------------- */

class _SessionsList extends StatelessWidget {
  final String peerId;
  const _SessionsList({required this.peerId});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final helperId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final q = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .where('studentId', isEqualTo: peerId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(includeMetadataChanges: true),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}',
              style: const TextStyle(color: Colors.red));
        }

        final docs = (snap.data?.docs ?? const [])
          ..sort((a, b) {
            final at = (a.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
            final bt = (b.data()['startAt'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });

        if (docs.isEmpty) {
          return _emptyBox('No sessions yet.');
        }

        return Column(
          children: [
            for (final d in docs) ...[
              _SessionTile(m: d.data()),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
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

class _SessionTile extends StatelessWidget {
  final Map<String, dynamic> m;
  const _SessionTile({required this.m});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final st = (m['startAt'] as Timestamp?)?.toDate();
    final en = (m['endAt'] as Timestamp?)?.toDate();

    final date = (st != null) ? _fmtDateLong(st) : '—';
    final time = (st != null && en != null)
        ? '${_fmtTime(TimeOfDay.fromDateTime(st))} - ${_fmtTime(TimeOfDay.fromDateTime(en))}'
        : '—';

    final mode = (m['mode'] ?? '').toString().toLowerCase();
    final venue = () {
      if (mode == 'online') {
        final meet = (m['meetUrl'] ?? '').toString();
        return meet.isNotEmpty ? 'Online ($meet)' : 'Online';
      }
      final v = (m['venue'] ?? m['location'] ?? '').toString();
      return v.isNotEmpty ? v : 'Campus';
    }();

    return SizedBox( // <-- forces full width inside Column
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Counselling Session', // generic title
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Date: $date', style: t.bodySmall),
            Text('Time: $time', style: t.bodySmall),
            Text('Venue: $venue', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}

/* ---------------------------------- Notes ---------------------------------- */

class _NotesSection extends StatelessWidget {
  final String peerId;
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final VoidCallback onSave;

  const _NotesSection({
    required this.peerId,
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final helperId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final q = FirebaseFirestore.instance
        .collection('peer_notes')
        .where('helperId', isEqualTo: helperId)
        .where('peerId', isEqualTo: peerId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NoteForm(titleCtrl: titleCtrl, bodyCtrl: bodyCtrl, onSave: onSave),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(includeMetadataChanges: true),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}',
                  style: const TextStyle(color: Colors.red));
            }

            final docs = (snap.data?.docs ?? const []);
            if (docs.isEmpty) {
              return _emptyBox('No notes yet. Add your first note above.');
            }

            docs.sort((a, b) {
              Timestamp? ta = a.data()['createdAtClient'] ?? a.data()['createdAt'];
              Timestamp? tb = b.data()['createdAtClient'] ?? b.data()['createdAt'];
              return (tb?.millisecondsSinceEpoch ?? 0)
                  .compareTo(ta?.millisecondsSinceEpoch ?? 0);
            });

            return Column(
              children: [
                for (final d in docs) ...[
                  _NoteCard(m: d.data()),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
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

class _NoteForm extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final VoidCallback onSave;

  const _NoteForm({
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.onSave,
  });

  Widget _shell(Widget child, {double height = 44}) => Container(
    height: height,
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
    return SizedBox(
      width: double.infinity, // full width
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            _shell(TextField(
              controller: titleCtrl,
              decoration: const InputDecoration.collapsed(hintText: 'Insert Title'),
            )),
            const SizedBox(height: 8),
            _shell(
              TextField(
                controller: bodyCtrl,
                maxLines: 5,
                decoration: const InputDecoration.collapsed(
                    hintText: 'Insert Notes/Description'),
              ),
              height: 120,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 36,
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Map<String, dynamic> m;
  const _NoteCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final title = (m['title'] ?? '').toString();
    final body = (m['body'] ?? '').toString();
    final ts = (m['createdAt'] is Timestamp)
        ? m['createdAt'] as Timestamp
        : (m['createdAtClient'] as Timestamp?);
    final created = ts?.toDate();

    return SizedBox( // <-- ensures full width inside a Column/ScrollView
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (created != null)
              Text(
                _fmtDateLong(created),
                style: t.labelSmall?.copyWith(color: Colors.black54),
              ),
            if (created != null) const SizedBox(height: 6),
            Text(title.isEmpty ? 'Untitled' : title,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body.isEmpty ? '—' : body, style: t.bodyMedium),
          ],
        ),
      ),
    );
  }
}
