// lib/student_profile_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

/* ------------------------------ Constants ------------------------------ */
const kFieldAbout = 'about';
const kFieldStudentId = 'studentId';
const kFieldFullName = 'fullName';
const kFieldEmail = 'email';
const kFieldPhotoUrl = 'photoUrl';
const kFieldPhotoUrlFallback = 'avatarUrl';

const kFieldAcademic = 'academicInterestIds';
const kFieldCounseling = 'counselingTopicIds';

/* ------------------------------ Models ------------------------------ */

class InterestItem {
  final String id;
  final String title;
  final int seq;
  final String category; // "academic" | "counseling"
  final bool active;

  InterestItem({
    required this.id,
    required this.title,
    required this.seq,
    required this.category,
    required this.active,
  });

  factory InterestItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return InterestItem(
      id: d.id,
      title: (data['title'] ?? '').toString(),
      seq: (data['seq'] ?? 0) is int
          ? data['seq'] as int
          : int.tryParse('${data['seq'] ?? 0}') ?? 0,
      category: (data['category'] ?? '').toString(),
      active: (data['active'] ?? true) == true,
    );
  }
}

/* ------------------------------ Page ------------------------------ */

class _StudentProfilePageState extends State<StudentProfilePage> {
  final _aboutCtrl = TextEditingController();

  bool _editing = false;
  bool _saving = false;

  bool _uploadingAvatar = false;
  double _avatarProgress = 0.0;

  final Set<String> _academicSel = <String>{};
  final Set<String> _counselingSel = <String>{};

  List<String> _savedAcademic = const <String>[];
  List<String> _savedCounseling = const <String>[];

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');
  CollectionReference<Map<String, dynamic>> get _interestsCol =>
      FirebaseFirestore.instance.collection('interests');

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _aboutCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Future<void> _saveAll() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _usersCol.doc(_uid).set(
        {
          kFieldAbout: _aboutCtrl.text.trim(),
          kFieldAcademic: _academicSel.toList(),
          kFieldCounseling: _counselingSel.toList(),
        },
        SetOptions(merge: true),
      );
      _savedAcademic = _academicSel.toList();
      _savedCounseling = _counselingSel.toList();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved.')));
      setState(() => _editing = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uid.isEmpty) return;
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (res == null || res.files.isEmpty) return;

      final file = res.files.single;
      final filename = file.name;
      final path =
          'users/$_uid/avatar_${DateTime.now().millisecondsSinceEpoch}_$filename';
      final ref = FirebaseStorage.instance.ref().child(path);

      setState(() {
        _uploadingAvatar = true;
        _avatarProgress = 0.0;
      });

      UploadTask task;
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) throw 'No bytes for web upload.';
        task = ref.putData(bytes, SettableMetadata(contentType: _guessMime(filename)));
      } else {
        final fp = file.path;
        if (fp == null || fp.isEmpty) throw 'Invalid file path.';
        task = ref.putFile(File(fp), SettableMetadata(contentType: _guessMime(filename)));
      }

      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          setState(() => _avatarProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });

      final done = await task.whenComplete(() {});
      final url = await done.ref.getDownloadURL();

      await _usersCol.doc(_uid).set({kFieldPhotoUrl: url}, SetOptions(merge: true));
      try {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Avatar upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _avatarProgress = 0.0;
        });
      }
    }
  }

  String _guessMime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: _uid.isEmpty
            ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Please sign in to view your profile.'),
          ),
        )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _usersCol.doc(_uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final u = userSnap.data?.data() ?? <String, dynamic>{};

            // Base fields
            final fullName = (u[kFieldFullName] ??
                u['displayName'] ??
                u['name'] ??
                '')
                .toString();
            final studentId =
            (u[kFieldStudentId] ?? u['matric'] ?? u['sid'] ?? '')
                .toString();
            final email =
            (u[kFieldEmail] ?? u['emailAddress'] ?? '').toString();
            final about = (u[kFieldAbout] ?? '').toString();
            final photoUrl =
            (u[kFieldPhotoUrl] ?? u[kFieldPhotoUrlFallback] ?? '')
                .toString();

            if (!_editing) _aboutCtrl.text = about;

            final acad = <String>[
              ...((u[kFieldAcademic] is List)
                  ? (u[kFieldAcademic] as List)
                  .map((e) => e.toString())
                  .toList()
                  : const <String>[]),
            ];
            final coun = <String>[
              ...((u[kFieldCounseling] is List)
                  ? (u[kFieldCounseling] as List)
                  .map((e) => e.toString())
                  .toList()
                  : const <String>[]),
            ];

            if (_savedAcademic.isEmpty && _academicSel.isEmpty) {
              _savedAcademic = acad;
              _academicSel.addAll(acad);
            }
            if (_savedCounseling.isEmpty && _counselingSel.isEmpty) {
              _savedCounseling = coun;
              _counselingSel.addAll(coun);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderStudent(onLogout: () => _logout(context)),
                  const SizedBox(height: 16),

                  // Title + Edit
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Profile',
                                style: t.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('View or edit your settings',
                                style: t.bodySmall),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 36,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding:
                            const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _saving
                              ? null
                              : () {
                            if (_editing) {
                              _saveAll();
                            } else {
                              setState(() => _editing = true);
                            }
                          },
                          child: Text(
                            _editing
                                ? (_saving ? 'Saving...' : 'Save')
                                : 'Edit',
                            style:
                            const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Profile card
                  _CardShell(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AvatarBlock(
                          photoUrl: photoUrl,
                          fullNameFallback:
                          fullName.isNotEmpty ? fullName : 'Student',
                          editing: _editing,
                          uploading: _uploadingAvatar,
                          progress: _avatarProgress,
                          onPick: _pickAndUploadAvatar,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  fullName.isNotEmpty
                                      ? fullName
                                      : 'Unknown Student',
                                  style: t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              if (studentId.isNotEmpty)
                                Text(studentId, style: t.bodySmall),
                              if (email.isNotEmpty)
                                Text(email, style: t.bodySmall),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _aboutCtrl,
                                readOnly: !_editing,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText:
                                  'Tell us about yourself...',
                                  contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                    BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  /* ----------------------- Past Sessions (LIVE) ----------------------- */
                  _PastSessionsCard(studentId: _uid),

                  const SizedBox(height: 12),

                  // Academic Interests
                  _InterestsChipsSection(
                    title: 'Academic Interest',
                    category: 'academic',
                    selected: _academicSel,
                    enabled: _editing && !_saving,
                    onChanged: (id, selected) {
                      if (!_editing) return;
                      setState(() {
                        if (selected) {
                          _academicSel.add(id);
                        } else {
                          _academicSel.remove(id);
                        }
                      });
                    },
                    interestsCol: _interestsCol,
                  ),

                  const SizedBox(height: 12),

                  // Counseling Topics
                  _InterestsChipsSection(
                    title: 'Counseling Topics',
                    category: 'counseling',
                    selected: _counselingSel,
                    enabled: _editing && !_saving,
                    onChanged: (id, selected) {
                      if (!_editing) return;
                      setState(() {
                        if (selected) {
                          _counselingSel.add(id);
                        } else {
                          _counselingSel.remove(id);
                        }
                      });
                    },
                    interestsCol: _interestsCol,
                  ),

                  const SizedBox(height: 12),

                  /* -------- My Tutors & My Counsellors (functional) -------- */
                  _PeopleYouWorkedWith(studentId: _uid),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ------------------------------ Sub-widgets ------------------------------ */

class _HeaderStudent extends StatelessWidget {
  final VoidCallback onLogout;
  const _HeaderStudent({required this.onLogout});

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

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/* ----------------------- Avatar with edit/loader ----------------------- */

class _AvatarBlock extends StatelessWidget {
  final String photoUrl;
  final String fullNameFallback;
  final bool editing;
  final bool uploading;
  final double progress;
  final VoidCallback onPick;

  const _AvatarBlock({
    required this.photoUrl,
    required this.fullNameFallback,
    required this.editing,
    required this.uploading,
    required this.progress,
    required this.onPick,
  });

  String _initials(String name) {
    final parts =
    name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return (s.characters.take(2).toString()).toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 64,
        height: 64,
        color: const Color(0xFFEEEEEE),
        child: photoUrl.isNotEmpty
            ? Image.network(photoUrl, width: 64, height: 64, fit: BoxFit.cover)
            : Center(
          child: Text(
            _initials(fullNameFallback.isNotEmpty ? fullNameFallback : 'S'),
            style:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
      ),
    );

    final stack = Stack(
      alignment: Alignment.center,
      children: [
        avatar,
        if (uploading) ...[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.35),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(value: progress == 0 ? null : progress),
          ),
        ] else if (editing) ...[
          PositionedFillAvatar(onPick: onPick),
        ],
      ],
    );

    return InkWell(
      onTap: editing && !uploading ? onPick : null,
      borderRadius: BorderRadius.circular(40),
      child: stack,
    );
  }
}

class PositionedFillAvatar extends StatelessWidget {
  final VoidCallback onPick;
  const PositionedFillAvatar({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(.15),
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(40),
          child: const Icon(Icons.camera_alt_outlined, color: Colors.white),
        ),
      ),
    );
  }
}

/* ----------------------- Past Sessions (fixed logic) ----------------------- */

class _PastSessionsCard extends StatelessWidget {
  final String studentId;
  const _PastSessionsCard({required this.studentId});

  Future<void> _deleteAllCompleted(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all completed sessions?'),
        content: const Text('This will permanently remove all your completed sessions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // Fetch all for this student; delete those with status == 'completed' (case-insensitive)
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('appointments')
          .where('studentId', isEqualTo: studentId);

      while (true) {
        final snap = await q.limit(400).get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        int toDelete = 0;

        for (final d in snap.docs) {
          final status = (d.data()['status'] ?? '').toString().toLowerCase().trim();
          if (status == 'completed') {
            batch.delete(d.reference);
            toDelete++;
          }
        }

        if (toDelete > 0) await batch.commit();
        if (snap.docs.length < 400) break;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted all completed sessions.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // IMPORTANT: Do NOT filter by status here; filter client-side (case-insensitive)
    final stream = FirebaseFirestore.instance
        .collection('appointments')
        .where('studentId', isEqualTo: studentId)
        .snapshots();

    return _CardShell(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snap.hasError) {
            return Text('Error: ${snap.error}',
                style: t.bodyMedium?.copyWith(color: Colors.red));
          }

          final all = snap.data?.docs ?? const [];
          final docs = all
              .where((d) =>
          ((d.data()['status'] ?? '') as Object?)
              .toString()
              .toLowerCase()
              .trim() ==
              'completed')
              .toList()
            ..sort((a, b) {
              int at = 0, bt = 0;
              final aTs = a.data()['startAt'];
              final bTs = b.data()['startAt'];
              if (aTs is Timestamp) at = aTs.toDate().millisecondsSinceEpoch;
              if (bTs is Timestamp) bt = bTs.toDate().millisecondsSinceEpoch;
              return bt.compareTo(at); // latest first
            });

          final total = docs.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Past Sessions ($total)',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF5350),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: docs.isEmpty ? null : () => _deleteAllCompleted(context),
                    child: const Text('Delete All', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (docs.isEmpty)
                Text('No completed sessions yet.', style: t.bodySmall)
              else
                Column(
                  children: [
                    for (final d in docs) ...[
                      _PastSessionRow(appDoc: d),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PastSessionRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> appDoc;
  const _PastSessionRow({required this.appDoc});

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final m = appDoc.data();
    final helperId = (m['helperId'] ?? '').toString();
    final startTs = m['startAt'] as Timestamp?;
    final endTs = m['endAt'] as Timestamp?;
    final location = (m['location'] ?? 'Campus').toString();

    final start = startTs?.toDate();
    final end = endTs?.toDate();
    final date = (start != null) ? _fmtDate(start) : '—';
    final time = (start != null && end != null)
        ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}'
        : '—';

    return FutureBuilder(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(helperId).get(),
        FirebaseFirestore.instance
            .collection('peer_applications')
            .where('userId', isEqualTo: helperId)
            .where('status', isEqualTo: 'approved')
            .limit(1)
            .get(),
      ]),
      builder: (context, snap) {
        String helperName = 'Helper';
        String role = 'peer';
        String? photoUrl;

        if (snap.hasData) {
          final userSnap = snap.data![0] as DocumentSnapshot<Map<String, dynamic>>;
          final appsSnap = snap.data![1] as QuerySnapshot<Map<String, dynamic>>;

          final userMap = userSnap.data() ?? {};
          helperName = _pickString(userMap, [
            'fullName',
            'full_name',
            'name',
            'displayName',
            'display_name'
          ]) ??
              helperName;

          // photo
          for (final key in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
            final v = userMap[key];
            if (v is String && v.trim().isNotEmpty) {
              photoUrl = v.trim();
              break;
            }
          }
          if ((photoUrl == null || photoUrl!.isEmpty) &&
              userMap['profile'] is Map<String, dynamic>) {
            final prof = userMap['profile'] as Map<String, dynamic>;
            for (final key in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
              final v = prof[key];
              if (v is String && v.trim().isNotEmpty) {
                photoUrl = v.trim();
                break;
              }
            }
          }

          if (appsSnap.docs.isNotEmpty) {
            role =
                (appsSnap.docs.first.data()['requestedRole'] ?? 'peer').toString();
          }
        }

        final isTutor = role == 'peer_tutor';
        final icon =
        isTutor ? Icons.person_outline : Icons.psychology_alt_outlined;
        final title =
            '${isTutor ? 'Tutoring' : 'Counselling'} with $helperName';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FFFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF50B46A), width: 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar/icon
              CircleAvatar(
                radius: 21,
                backgroundColor: Colors.white,
                backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                    ? NetworkImage(photoUrl!)
                    : null,
                child: (photoUrl == null || photoUrl!.isEmpty)
                    ? Icon(icon, color: const Color(0xFF50B46A))
                    : null,
              ),
              const SizedBox(width: 10),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8F2D2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2E7D32)),
                          ),
                          child: Text('Completed',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Date: $date',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('Time: $time',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('Venue: $location',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final profile = m['profile'];
    if (profile is Map<String, dynamic>) {
      for (final k in keys) {
        final v = profile[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }
}

/* ----------------- People you worked with (functional) ----------------- */

class _PeopleYouWorkedWith extends StatelessWidget {
  final String studentId;
  const _PeopleYouWorkedWith({required this.studentId});

  Future<Map<String, List<_PersonMini>>> _loadPeople() async {
    // Get all appointments (any status) for this student
    final appts = await FirebaseFirestore.instance
        .collection('appointments')
        .where('studentId', isEqualTo: studentId)
        .get();

    final byHelper =
    <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in appts.docs) {
      final h = (d['helperId'] ?? '').toString();
      if (h.isEmpty) continue;
      (byHelper[h] ??= []).add(d);
    }
    if (byHelper.isEmpty) return {'tutors': [], 'counsellors': []};

    final tutors = <_PersonMini>[];
    final counsellors = <_PersonMini>[];

    // For each helper, fetch role + user + completed count (with this student)
    for (final entry in byHelper.entries) {
      final helperId = entry.key;
      final apptsWithHelper = entry.value;

      final appsSnap = await FirebaseFirestore.instance
          .collection('peer_applications')
          .where('userId', isEqualTo: helperId)
          .where('status', isEqualTo: 'approved')
          .limit(1)
          .get();

      String role = appsSnap.docs.isNotEmpty
          ? (appsSnap.docs.first.data()['requestedRole'] ?? 'peer').toString()
          : 'peer';

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(helperId)
          .get();
      final userMap = userSnap.data() ?? {};
      final name = _pickString(userMap, [
        'fullName',
        'full_name',
        'name',
        'displayName',
        'display_name'
      ]) ??
          'Helper';

      String? photoUrl;
      for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
        final v = userMap[k];
        if (v is String && v.trim().isNotEmpty) {
          photoUrl = v.trim();
          break;
        }
      }
      if ((photoUrl == null || photoUrl!.isEmpty) &&
          userMap['profile'] is Map<String, dynamic>) {
        final prof = userMap['profile'] as Map<String, dynamic>;
        for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
          final v = prof[k];
          if (v is String && v.trim().isNotEmpty) {
            photoUrl = v.trim();
            break;
          }
        }
      }

      // completed sessions count (with THIS student & helper), case-insensitive
      final completedCount = apptsWithHelper
          .where((a) =>
      (a['status'] ?? '').toString().toLowerCase().trim() ==
          'completed')
          .length;

      final person = _PersonMini(
        helperId: helperId,
        name: name,
        photoUrl: photoUrl,
        sessionsWithMe: completedCount,
        role: role,
      );

      if (role == 'peer_counsellor') {
        counsellors.add(person);
      } else if (role == 'peer_tutor') {
        tutors.add(person);
      }
    }

    // sort: most sessions first
    tutors.sort((a, b) => b.sessionsWithMe.compareTo(a.sessionsWithMe));
    counsellors.sort((a, b) => b.sessionsWithMe.compareTo(a.sessionsWithMe));

    return {'tutors': tutors, 'counsellors': counsellors};
  }

  void _bookAgain(BuildContext context, _PersonMini p) {
    Navigator.pushNamed(
      context,
      '/student/appointment',
      arguments: {
        'userId': p.helperId,
        'name': p.name,
        'sessions': p.sessionsWithMe,
        'match': 'Good Match',
        'specializes': const <String>[],
        'photoUrl': p.photoUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<Map<String, List<_PersonMini>>>(
      future: _loadPeople(),
      builder: (context, snap) {
        final tutors = snap.data?['tutors'] ?? const <_PersonMini>[];
        final counsellors = snap.data?['counsellors'] ?? const <_PersonMini>[];

        return Column(
          children: [
            _PeopleCard(
              title: 'My Tutors',
              people: tutors,
              onTap: (p) => _bookAgain(context, p),
              emptyText: 'No tutors yet.',
            ),
            const SizedBox(height: 12),
            _PeopleCard(
              title: 'My Counsellors',
              people: counsellors,
              onTap: (p) => _bookAgain(context, p),
              emptyText: 'No counsellors yet.',
            ),
          ],
        );
      },
    );
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final profile = m['profile'];
    if (profile is Map<String, dynamic>) {
      for (final k in keys) {
        final v = profile[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }
}

class _PersonMini {
  final String helperId;
  final String name;
  final String? photoUrl;
  final int sessionsWithMe; // completed sessions with this student
  final String role; // peer_tutor | peer_counsellor | peer

  _PersonMini({
    required this.helperId,
    required this.name,
    required this.photoUrl,
    required this.sessionsWithMe,
    required this.role,
  });
}

class _PeopleCard extends StatelessWidget {
  final String title;
  final List<_PersonMini> people;
  final String emptyText;
  final void Function(_PersonMini) onTap;

  const _PeopleCard({
    required this.title,
    required this.people,
    required this.onTap,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (people.isEmpty)
            Text(emptyText, style: t.bodySmall)
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: people.map((p) {
                return InkWell(
                  onTap: () => onTap(p),
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3EAFD)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                              ? NetworkImage(p.photoUrl!)
                              : null,
                          child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                            Text('${p.sessionsWithMe} completed',
                                style: t.bodySmall?.copyWith(color: Colors.black54)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

/* ----------------------- Interests Chips Section ----------------------- */

class _InterestsChipsSection extends StatelessWidget {
  final String title;
  final String category; // "academic" | "counseling"
  final Set<String> selected;
  final bool enabled;
  final void Function(String id, bool select) onChanged;
  final CollectionReference<Map<String, dynamic>> interestsCol;

  const _InterestsChipsSection({
    required this.title,
    required this.category,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.interestsCol,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
            interestsCol.where('category', isEqualTo: category).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Text('Error: ${snap.error}',
                    style: t.bodyMedium?.copyWith(color: Colors.red));
              }
              final items = (snap.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .map((d) => InterestItem.fromDoc(d))
                  .where((it) => it.active && it.title.trim().isNotEmpty)
                  .toList();
              items.sort((a, b) {
                final c = a.seq.compareTo(b.seq);
                if (c != 0) return c;
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              });

              if (items.isEmpty) {
                return Text(
                  'No ${category == "academic" ? "academic interests" : "counseling topics"} configured.',
                  style: t.bodySmall,
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((it) {
                  final sel = selected.contains(it.id);
                  return FilterChip(
                    label: Text(
                      it.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    selected: sel,
                    onSelected: enabled ? (v) => onChanged(it.id, v) : null,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/* --------------------------- Utility Extensions --------------------------- */

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
