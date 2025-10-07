// lib/student_apply_peer_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

/* ============================== Models ============================== */

class InterestItem {
  final String id;
  final String title;
  final String code;
  final int seq;
  /// "academic" or "counseling"
  final String category;
  final bool active;

  InterestItem({
    required this.id,
    required this.title,
    required this.code,
    required this.seq,
    required this.category,
    this.active = true,
  });

  factory InterestItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return InterestItem(
      id: d.id,
      title: (data['title'] ?? '').toString(),
      code: (data['code'] ?? '').toString(),
      seq: (data['seq'] ?? 0) is int
          ? data['seq'] as int
          : int.tryParse('${data['seq'] ?? 0}') ?? 0,
      category: (data['category'] ?? '').toString(),
      active: (data['active'] ?? true) == true,
    );
  }
}

/* ============================== Screen ============================== */

class StudentApplyPeerPage extends StatefulWidget {
  const StudentApplyPeerPage({super.key});

  @override
  State<StudentApplyPeerPage> createState() => _StudentApplyPeerPageState();
}

enum _Role { tutor, counsellor }

class _StudentApplyPeerPageState extends State<StudentApplyPeerPage> {
  _Role _role = _Role.tutor; // default

  // Selected interests (document IDs)
  final Set<String> _selectedIds = <String>{};

  // Motivation
  final _motivationCtrl = TextEditingController(
    text:
    'I am passionate about helping fellow students and contributing to the PEERS community.',
  );

  // Optional recommendation letter
  PlatformFile? _letter;
  bool _submitting = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _motivationCtrl.dispose();
    super.dispose();
  }

  /* ----------------------- Firestore references ---------------------- */

  CollectionReference<Map<String, dynamic>> get _interestsCol =>
      FirebaseFirestore.instance.collection('interests');

  CollectionReference<Map<String, dynamic>> get _appsCol =>
      FirebaseFirestore.instance.collection('peer_applications');

  /* ----------------------------- Helpers ----------------------------- */

  String get _roleCategory =>
      _role == _Role.tutor ? 'academic' : 'counseling';

  String get _roleString =>
      _role == _Role.tutor ? 'peer_tutor' : 'peer_counsellor';

  Future<void> _pickLetter() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _letter = res.files.single);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF attached.')),
      );
    }
  }

  void _switchRole(_Role r) {
    if (_role == r) return;
    setState(() {
      _role = r;
      _selectedIds.clear(); // reset when switching
    });
  }

  void _dialog(String title, String msg) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      _dialog('Logout failed', '$e');
    }
  }

  /* ------------------------- Submit application ---------------------- */

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _dialog('Not signed in', 'Please sign in first.');
      return;
    }

    if (_selectedIds.isEmpty) {
      _dialog('Select interests', 'Please select at least one interest.');
      return;
    }
    if (_motivationCtrl.text.trim().isEmpty) {
      _dialog('Add motivation', 'Please write a short motivation.');
      return;
    }

    // Read user's facultyId (must exist in users/{uid})
    String facultyId = '';
    try {
      final uSnap =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      facultyId = (uSnap.data()?['facultyId'] ?? '').toString();
    } catch (_) {}
    if (facultyId.isEmpty) {
      _dialog('Missing faculty', 'Your profile has no faculty selected. Please update your profile or contact admin.');
      return;
    }

    try {
      setState(() {
        _submitting = true;
        _uploadProgress = 0.0;
      });

      // Optional: upload letter
      String? letterUrl;
      String? letterName;
      if (_letter != null) {
        final fileName = _letter!.name;
        letterName = fileName;
        final path =
            'peer_applications/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        final ref = FirebaseStorage.instance.ref().child(path);

        UploadTask task;
        if (kIsWeb) {
          final bytes = _letter!.bytes;
          if (bytes == null) throw 'No file bytes for web upload.';
          task =
              ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
        } else {
          final filepath = _letter!.path;
          if (filepath == null || filepath.isEmpty) {
            throw 'Invalid file path.';
          }
          task =
              ref.putFile(File(filepath), SettableMetadata(contentType: 'application/pdf'));
        }

        task.snapshotEvents.listen((snap) {
          if (snap.totalBytes > 0) {
            setState(() => _uploadProgress = snap.bytesTransferred / snap.totalBytes);
          }
        });

        final snap = await task.whenComplete(() {});
        letterUrl = await snap.ref.getDownloadURL();
      }

      // 🔸 Save ONLY interest IDs + facultyId (no denormalized interests array)
      await _appsCol.add({
        'userId': user.uid,
        'facultyId': facultyId,                 // << store student's faculty
        'requestedRole': _roleString,           // "peer_tutor" | "peer_counsellor"
        'interestsIds': _selectedIds.toList(),  // << only IDs
        'motivation': _motivationCtrl.text.trim(),
        'letterUrl': letterUrl,
        'letterFileName': letterName,
        'status': 'pending', // admin updates later
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploadProgress = 0.0;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Application submitted.')));
      Navigator.maybePop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _dialog('Submit failed', '$e');
    }
  }

  /* ------------------------- Interests (chips) ------------------------ */

  Widget _interestsSection() {
    final t = Theme.of(context).textTheme;

    return _Section(
      title: _role == _Role.tutor ? 'Academic Interests' : 'Counseling Topics',
      subtitle: '(Loaded from Firebase)',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // IMPORTANT: no orderBy here to avoid composite index requirement.
        stream: _interestsCol
            .where('category', isEqualTo: _roleCategory) // "academic" | "counseling"
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return Text('Error: ${snap.error}',
                style: t.bodyMedium?.copyWith(color: Colors.red));
          }

          final items = snap.data?.docs
              .map((d) => InterestItem.fromDoc(d))
              .where((it) => it.active && it.title.trim().isNotEmpty)
              .toList() ??
              const <InterestItem>[];

          // Sort locally by seq so we don't need an index.
          items.sort((a, b) => a.seq.compareTo(b.seq));

          if (items.isEmpty) {
            return const Text('No interests configured yet.');
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) {
              final selected = _selectedIds.contains(it.id);
              return FilterChip(
                label: Text(
                  it.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedIds.add(it.id);
                    } else {
                      _selectedIds.remove(it.id);
                    }
                  });
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /* ------------------------------ Build ------------------------------ */

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderStudent(onLogout: _logout),
                  const SizedBox(height: 16),

                  Text('Apply to be a Peer',
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Application for being a Peer', style: t.bodySmall),
                  const SizedBox(height: 12),

                  const _ProcessStrip(),
                  const SizedBox(height: 12),

                  // Choose Role
                  _Section(
                    title: 'Choose Role',
                    child: Row(
                      children: [
                        Expanded(
                          child: _RoleCard(
                            title: 'Peer Tutor',
                            subtitle: 'Help students\nwith academic\nsubjects',
                            icon: Icons.edit_outlined,
                            selected: _role == _Role.tutor,
                            onTap: () => _switchRole(_Role.tutor),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleCard(
                            title: 'Peer Counsellor',
                            subtitle: 'Support students\nwith personal\nchallenges',
                            icon: Icons.psychology_alt_outlined,
                            selected: _role == _Role.counsellor,
                            onTap: () => _switchRole(_Role.counsellor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Interests
                  _interestsSection(),
                  const SizedBox(height: 12),

                  // Motivation
                  _Section(
                    title: _role == _Role.tutor
                        ? 'Motivation to be Tutor'
                        : 'Motivation to be Counsellor',
                    child: TextField(
                      controller: _motivationCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Letter
                  _Section(
                    title: 'Recommendation Letter by HOP (Optional)',
                    child: _UploadTile(
                      fileName: _letter?.name,
                      onPick: _submitting ? null : _pickLetter,
                    ),
                  ),

                  const SizedBox(height: 18),
                  Center(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _submitting ? null : _submit,
                        child: const Text('Submit Application',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_submitting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(.25),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (_letter != null) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: LinearProgressIndicator(
                              value: _uploadProgress == 0 ? null : _uploadProgress,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text('Uploading letter...'),
                        ],
                        const SizedBox(height: 10),
                        const Text('Submitting application...'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ============================== UI bits ============================== */

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
        IconButton(
          tooltip: 'Logout',
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }
}

class _ProcessStrip extends StatelessWidget {
  const _ProcessStrip();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Widget step(IconData icon, String label) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.06),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(label, style: t.labelSmall, textAlign: TextAlign.center),
        ],
      );
    }

    Widget arrow() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.arrow_forward),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFD7E6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            step(Icons.picture_as_pdf_outlined, 'Application\nSubmission'),
            arrow(),
            step(Icons.rate_review_outlined, 'HOP Review'),
            arrow(),
            step(Icons.verified_outlined, 'Admin Approval'),
            arrow(),
            step(Icons.email_outlined, 'Email\nNotification'),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Text(subtitle!,
                    style: t.bodySmall?.copyWith(color: Colors.black54)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const primary = Color(0xFF7C4DFF);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                colors: [Color(0xFFF2ECFF), Color(0xFFEDE7FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : null,
              color: selected ? null : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? primary : Colors.black26,
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: primary.withOpacity(.20),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withOpacity(.06),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? primary : Colors.black26,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: selected ? primary : Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? primary : null,
                        ),
                      ),
                      Text(subtitle, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Selected',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String? fileName;
  final VoidCallback? onPick;

  const _UploadTile({required this.fileName, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPick,
      child: Ink(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black26),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fileName ?? 'Upload file (PDF)',
                style: t.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.attach_file, size: 20),
          ],
        ),
      ),
    );
  }
}
