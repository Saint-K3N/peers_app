// lib/hop_profile_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class HopProfilePage extends StatefulWidget {
  const HopProfilePage({super.key});

  @override
  State<HopProfilePage> createState() => _HopProfilePageState();
}

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

class _HopProfilePageState extends State<HopProfilePage> {
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
                  _HeaderHop(onLogout: () => _logout(context)),
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
                            Text('View or edit your information',
                                style: t.bodySmall),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 36,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18),
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
                          fullNameFallback: fullName.isNotEmpty
                              ? fullName
                              : 'HOP User',
                          editing: _editing,
                          uploading: _uploadingAvatar,
                          progress: _avatarProgress,
                          onPick: _pickAndUploadAvatar,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                  fullName.isNotEmpty
                                      ? fullName
                                      : 'Unknown HOP',
                                  style: t.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              if (email.isNotEmpty)
                                Text(email, style: t.bodySmall),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _aboutCtrl,
                                readOnly: !_editing,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText:
                                  'Add a short bio or note...',
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

                  // NOTE: Intentionally NOT including "My Tutors" or "My Counsellors" cards.
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

class _HeaderHop extends StatelessWidget {
  final VoidCallback onLogout;
  const _HeaderHop({required this.onLogout});

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
              Text('HOP', style: t.titleMedium),
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
            _initials(
                fullNameFallback.isNotEmpty ? fullNameFallback : 'H'),
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
            child: CircularProgressIndicator(
                value: progress == 0 ? null : progress),
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
