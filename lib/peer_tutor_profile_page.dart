// lib/peer_tutor_profile_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/* ------------------------------ Constants ------------------------------ */
const kFieldAbout = 'about';
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

class PeerTutorProfilePage extends StatefulWidget {
  const PeerTutorProfilePage({super.key});

  @override
  State<PeerTutorProfilePage> createState() => _PeerTutorProfilePageState();
}

class _PeerTutorProfilePageState extends State<PeerTutorProfilePage> {
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
            final email = (u[kFieldEmail] ?? u['emailAddress'] ?? '').toString();
            final about = (u[kFieldAbout] ?? '').toString();
            final photoUrl =
            (u[kFieldPhotoUrl] ?? u[kFieldPhotoUrlFallback] ?? '').toString();

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
                  _HeaderTutor(onLogout: () => _logout(context)),
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
                            Text('View or edit your settings', style: t.bodySmall),
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
                            _editing ? (_saving ? 'Saving...' : 'Save') : 'Edit',
                            style: const TextStyle(color: Colors.white),
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
                          fullName.isNotEmpty ? fullName : 'Tutor',
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
                                    : 'Unknown Tutor',
                                style: t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (email.isNotEmpty)
                                Text(email, style: t.bodySmall),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _aboutCtrl,
                                readOnly: !_editing,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'Tell students about yourself...',
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
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

                  /* ------------------- Past Tutoring Sessions (LIVE) ------------------- */
                  _PastSessionsCardTutor(helperId: _uid),

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

                  /* ------------------------- My Students (LIVE) ------------------------ */
                  _StudentsYouWorkedWith(helperId: _uid),
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

class _HeaderTutor extends StatelessWidget {
  final VoidCallback onLogout;
  const _HeaderTutor({required this.onLogout});

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
              Text('Peer Tutor', style: t.titleMedium),
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
            _initials(fullNameFallback.isNotEmpty ? fullNameFallback : 'T'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
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

/* -------------------- Past Tutoring Sessions (helperId=me) ------------------- */

class _PastSessionsCardTutor extends StatelessWidget {
  final String helperId;
  const _PastSessionsCardTutor({required this.helperId});

  Future<void> _deleteAllCompleted(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all completed sessions?'),
        content: const Text('This will permanently remove all your completed tutoring sessions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperId);

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

    final stream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
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
              .where((d) => ((d.data()['status'] ?? '') as Object?)
              .toString()
              .toLowerCase()
              .trim() == 'completed')
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
                    child: Text('Past Tutoring Sessions ($total)',
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
                      _PastTutorSessionRow(appDoc: d),
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

class _PastTutorSessionRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> appDoc;
  const _PastTutorSessionRow({required this.appDoc});

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
    final studentId = (m['studentId'] ?? '').toString();
    final startTs = m['startAt'] as Timestamp?;
    final endTs = m['endAt'] as Timestamp?;
    final location = (m['location'] ?? m['venue'] ?? 'Campus').toString();

    final start = startTs?.toDate();
    final end = endTs?.toDate();
    final date = (start != null) ? _fmtDate(start) : '—';
    final time = (start != null && end != null)
        ? '${_fmtTime(TimeOfDay.fromDateTime(start))} - ${_fmtTime(TimeOfDay.fromDateTime(end))}'
        : '—';

    return FutureBuilder(
      future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        String studentName = 'Student';
        String? photoUrl;

        if (snap.hasData) {
          final userMap = (snap.data as DocumentSnapshot<Map<String, dynamic>>?)
              ?.data() ??
              {};
          studentName = _pickString(userMap, [
            'fullName',
            'full_name',
            'name',
            'displayName',
            'display_name'
          ]) ??
              studentName;

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
        }

        final icon = Icons.person_outline;
        final title = 'Tutoring with $studentName';

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

/* --------------------- Students you worked with (LIVE) -------------------- */

class _StudentsYouWorkedWith extends StatelessWidget {
  final String helperId;
  const _StudentsYouWorkedWith({required this.helperId});

  Future<List<_StudentMini>> _loadStudents() async {
    // Get all appointments (any status) for this helper
    final appts = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .get();

    final byStudent =
    <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in appts.docs) {
      final s = (d['studentId'] ?? '').toString();
      if (s.isEmpty) continue;
      (byStudent[s] ??= []).add(d);
    }
    if (byStudent.isEmpty) return [];

    final students = <_StudentMini>[];

    // For each student, fetch user + completed count (with this tutor)
    for (final entry in byStudent.entries) {
      final studentId = entry.key;
      final apptsWithStudent = entry.value;

      final userSnap =
      await FirebaseFirestore.instance.collection('users').doc(studentId).get();
      final userMap = userSnap.data() ?? {};
      final name = _pickString(userMap, [
        'fullName',
        'full_name',
        'name',
        'displayName',
        'display_name'
      ]) ??
          'Student';

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

      // completed sessions count (with THIS student), case-insensitive
      final completedCount = apptsWithStudent
          .where((a) =>
      (a['status'] ?? '').toString().toLowerCase().trim() == 'completed')
          .length;

      students.add(_StudentMini(
        studentId: studentId,
        name: name,
        photoUrl: photoUrl,
        sessionsWithMe: completedCount,
      ));
    }

    // sort: most sessions first
    students.sort((a, b) => b.sessionsWithMe.compareTo(a.sessionsWithMe));
    return students;
  }

  void _openStudentDetail(BuildContext context, _StudentMini s) {
    Navigator.pushNamed(
      context,
      '/peer_tutor/student_detail',
      arguments: {'studentId': s.studentId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<List<_StudentMini>>(
      future: _loadStudents(),
      builder: (context, snap) {
        final students = snap.data ?? const <_StudentMini>[];

        return _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Students',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (students.isEmpty)
                Text('No students yet.', style: t.bodySmall)
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: students.map((s) {
                    return InkWell(
                      onTap: () => _openStudentDetail(context, s),
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                              backgroundImage:
                              (s.photoUrl != null && s.photoUrl!.isNotEmpty)
                                  ? NetworkImage(s.photoUrl!)
                                  : null,
                              child: (s.photoUrl == null || s.photoUrl!.isEmpty)
                                  ? const Icon(Icons.person, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: t.labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                Text('${s.sessionsWithMe} completed',
                                    style: t.bodySmall
                                        ?.copyWith(color: Colors.black54)),
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

class _StudentMini {
  final String studentId;
  final String name;
  final String? photoUrl;
  final int sessionsWithMe;

  _StudentMini({
    required this.studentId,
    required this.name,
    required this.photoUrl,
    required this.sessionsWithMe,
  });
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
