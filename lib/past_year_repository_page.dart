// lib/past_year_repository_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter + Clipboard
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/* ------------------------------- Model -------------------------------- */

class PastPaper {
  final String id;
  final String title;
  final String code;           // e.g., PYP-SOC-0001
  final String facultyId;      // <-- stored as facultyId
  final String legacyFaculty;  // <-- optional: old 'faculty' string (for older docs)
  final int year;
  final String semester;       // Semester 1 | Semester 2 | Short
  final String category;       // Final Exam | Midterm | ...
  final DateTime uploadedAt;
  final String? fileUrl;       // Firebase Storage download URL
  final String? fileName;      // Original filename
  final String? storagePath;   // Storage path, used for delete

  PastPaper({
    required this.id,
    required this.title,
    required this.code,
    required this.facultyId,
    required this.legacyFaculty,
    required this.year,
    required this.semester,
    required this.category,
    required this.uploadedAt,
    this.fileUrl,
    this.fileName,
    this.storagePath,
  });

  factory PastPaper.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    final ts = data['uploadedAt'];
    return PastPaper(
      id: d.id,
      title: (data['title'] ?? '') as String,
      code: (data['code'] ?? '') as String,
      facultyId: ((data['facultyId'] ?? '') as String).trim(),
      legacyFaculty: ((data['faculty'] ?? '') as String).trim(), // for older docs
      year: (data['year'] ?? 0) as int,
      semester: (data['semester'] ?? '') as String,
      category: (data['category'] ?? '') as String,
      uploadedAt: ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      fileUrl: data['fileUrl'] as String?,
      fileName: data['fileName'] as String?,
      storagePath: data['storagePath'] as String?,
    );
  }
}

/* -------------------------------- Screen -------------------------------- */

class PastYearRepositoryPage extends StatefulWidget {
  const PastYearRepositoryPage({super.key});
  @override
  State<PastYearRepositoryPage> createState() => _PastYearRepositoryPageState();
}

class _PastYearRepositoryPageState extends State<PastYearRepositoryPage> {
  // Sorting + search
  final _sorts = const ['Most Recent', 'Oldest', 'A–Z'];
  String _selectedSort = 'Most Recent';
  String _search = '';

  // Filter by faculty (facultyId); null => All Faculties
  String? _selectedFacultyId;

  // Add new paper form
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  String? _newFacultyId;  // <-- facultyId chosen from faculties collection
  int? _newYear;
  String? _newSemester;
  String? _newCategory;

  final _years = List<int>.generate(7, (i) => DateTime.now().year - i);
  final _semesters = const ['Semester 1', 'Semester 2', 'Short'];
  final _categories = const ['Final Exam', 'Midterm', 'Quiz', 'Assignment'];

  // File picker / upload state
  PlatformFile? _pickedFile;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  /* ------------------------------- Firestore ------------------------------- */

  CollectionReference<Map<String, dynamic>> get _papersCol =>
      FirebaseFirestore.instance.collection('past_papers');

  CollectionReference<Map<String, dynamic>> get _facultiesCol =>
      FirebaseFirestore.instance.collection('faculties');

  /// Derive a prefix from faculty name for the paper code.
  String _facultyPrefixFromName(String facultyName) {
    final f = facultyName.toLowerCase();
    if (f.contains('comput')) return 'SOC';     // School of Computing
    if (f.contains('business')) return 'SOB';   // School of Business
    if (f.contains('design')) return 'SOD';     // School of Design
    return 'GEN';
  }

  /// Per-faculty counter: counters/pastpapers_<PREFIX> { value: <int> }
  Future<int> _nextSeqForPrefix(String prefix) async {
    final ref = FirebaseFirestore.instance
        .collection('counters')
        .doc('pastpapers_$prefix');

    return FirebaseFirestore.instance.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final cur = (snap.data()?['value'] ?? 0) as int;
      final next = cur + 1;
      tx.set(ref, {'value': next});
      return next;
    });
  }

  /* -------------------------------- Actions -------------------------------- */

  Future<void> _pickPdf() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: kIsWeb, // on web we upload bytes
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _pickedFile = res.files.single);
    }
  }

  /// Add paper: reads faculty name via facultyId → builds prefix → uploads PDF → stores doc with facultyId
  Future<void> _addPaper(Map<String, String> facultyIdToName) async {
    if (!_formKey.currentState!.validate()) return;
    if (_newFacultyId == null || _newYear == null || _newSemester == null || _newCategory == null) {
      _dialog('Missing fields', 'Please fill all dropdowns.');
      return;
    }
    if (_pickedFile == null) {
      _dialog('Attach PDF', 'Please attach a PDF file before adding.');
      return;
    }
    if (!kIsWeb && (_pickedFile!.path == null || _pickedFile!.path!.isEmpty)) {
      _dialog('File error', 'Could not read the selected file.');
      return;
    }

    final title = _titleCtrl.text.trim();

    // Resolve faculty name from id
    final facultyName = facultyIdToName[_newFacultyId!] ?? '';
    final prefix = _facultyPrefixFromName(facultyName);

    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      // Get next sequence + build code
      final seq = await _nextSeqForPrefix(prefix);
      final code = 'PYP-$prefix-${seq.toString().padLeft(4, '0')}';

      // Upload to Firebase Storage
      final fileName = _pickedFile!.name; // keep original name
      final storagePath = 'past_papers/$prefix/$code-$fileName';
      final ref = FirebaseStorage.instance.ref().child(storagePath);

      UploadTask task;
      if (kIsWeb) {
        final bytes = _pickedFile!.bytes;
        if (bytes == null) throw 'No file bytes for web upload.';
        task = ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      } else {
        final path = _pickedFile!.path!;
        task = ref.putFile(File(path), SettableMetadata(contentType: 'application/pdf'));
      }

      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          setState(() => _uploadProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });

      final snap = await task.whenComplete(() {});
      final fileUrl = await snap.ref.getDownloadURL();

      // Add Firestore doc (NOTE: faculty stored as facultyId)
      await _papersCol.add({
        'title': title,
        'code': code,
        'facultyId': _newFacultyId!, // <-- store facultyId
        'year': _newYear!,
        'semester': _newSemester!,
        'category': _newCategory!,
        'uploadedAt': FieldValue.serverTimestamp(),
        'fileUrl': fileUrl,
        'fileName': fileName,
        'storagePath': storagePath,
      });

      if (!mounted) return;
      _titleCtrl.clear();
      setState(() {
        _newFacultyId = null;
        _newYear = null;
        _newSemester = null;
        _newCategory = null;
        _pickedFile = null;
        _isUploading = false;
        _uploadProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "$title" ($code)')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  Future<void> _deletePaper(PastPaper p) async {
    final ok = await _confirm('Delete Paper', 'Delete "${p.title}" permanently?');
    if (ok != true) return;
    try {
      if (p.storagePath != null && p.storagePath!.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(p.storagePath!).delete().catchError((_) {});
      }
      await _papersCol.doc(p.id).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  /// Open in browser; fallback to external; then clipboard
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      bool opened = false;

      if (await canLaunchUrl(uri)) {
        opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (!opened) opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } else {
        opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      if (!opened) {
        await Clipboard.setData(ClipboardData(text: url));
        _dialog('Open failed',
            'Could not open the PDF in a browser.\nThe link has been copied to your clipboard:\n\n$url');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _dialog('Open failed',
          'Could not open the PDF in a browser.\nThe link has been copied to your clipboard:\n\n$url');
    }
  }

  /* ------------------------------- UI helpers ------------------------------ */

  List<PastPaper> _applyFiltersSortSearch(List<PastPaper> all) {
    var list = all.where((p) {
      final q = _search;
      final matchesSearch = q.isEmpty ||
          p.title.toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q);
      final matchesFaculty =
          _selectedFacultyId == null || p.facultyId == _selectedFacultyId;
      return matchesSearch && matchesFaculty;
    }).toList();

    switch (_selectedSort) {
      case 'Most Recent':
        list.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
        break;
      case 'Oldest':
        list.sort((a, b) => a.uploadedAt.compareTo(b.uploadedAt));
        break;
      case 'A–Z':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return list;
  }

  Future<bool?> _confirm(String title, String msg) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
  }

  void _dialog(String title, String msg) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')) ],
      ),
    );
  }

  String _prettyDate(DateTime d) {
    const months = [
      '', 'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    String ordinal(int n) {
      if (n >= 11 && n <= 13) return '${n}th';
      switch (n % 10) { case 1: return '${n}st'; case 2: return '${n}nd'; case 3: return '${n}rd'; default: return '${n}th'; }
    }
    return '${ordinal(d.day)} ${months[d.month]} ${d.year}';
  }

  /* --------------------------------- Build -------------------------------- */

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Load faculties ONCE and reuse everywhere below
            stream: _facultiesCol.orderBy('name').snapshots(),
            builder: (context, facSnap) {
              final facDocs = facSnap.data?.docs ?? const [];
              final facultyIdToName = <String, String>{
                for (final d in facDocs) d.id: (d.data()['name'] ?? '').toString()
              };

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderBar(
                      onBack: () => Navigator.maybePop(context),
                      onLogout: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                    ),
                    const SizedBox(height: 12),

                    // Title + Add Paper (IN HEADER, as requested)
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Past Year Repository',
                                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Manage previous exam papers', style: t.bodySmall),
                          ],
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: _isUploading ? null : () => _addPaper(facultyIdToName),
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Add Paper', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Search
                    _SearchField(
                      hint: 'Search by title or code',
                      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),

                    // Filters
                    Row(
                      children: [
                        // Faculty filter (by facultyId)
                        Expanded(
                          child: _DropdownPillNullable<String>(
                            value: _selectedFacultyId,
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('All Faculties')),
                              ...facultyIdToName.entries.map((e) =>
                                  DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
                            ],
                            onChanged: (v) => setState(() => _selectedFacultyId = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Sort
                        Expanded(
                          child: _DropdownPill<String>(
                            value: _selectedSort,
                            items: _sorts,
                            onChanged: (v) => setState(() => _selectedSort = v ?? 'Most Recent'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // --- Total Papers card ABOVE the Add New Paper card ---
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _papersCol.snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text('Error loading total: ${snap.error}',
                                style: t.bodySmall?.copyWith(color: Colors.red)),
                          );
                        }
                        final total = snap.data?.docs.length ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StatBox(count: total, label: 'Total Papers'),
                        );
                      },
                    ),

                    // Add New Paper card (form)
                    _AddPaperCard(
                      formKey: _formKey,
                      titleCtrl: _titleCtrl,
                      facultyDropdown: _DropdownLine<String>(
                        hint: 'Select Faculty',
                        value: _newFacultyId,
                        items: facultyIdToName.entries
                            .map((e) => _DropdownLineItem<String>(value: e.key, label: e.value))
                            .toList(),
                        onChanged: (v) => setState(() => _newFacultyId = v),
                      ),
                      yearDropdown: _DropdownLine<int>(
                        hint: 'Year',
                        value: _newYear,
                        items: _years.map((y) => _DropdownLineItem<int>(value: y, label: '$y')).toList(),
                        onChanged: (v) => setState(() => _newYear = v),
                      ),
                      semDropdown: _DropdownLine<String>(
                        hint: 'Semester',
                        value: _newSemester,
                        items: _semesters
                            .map((s) => _DropdownLineItem<String>(value: s, label: s))
                            .toList(),
                        onChanged: (v) => setState(() => _newSemester = v),
                      ),
                      catDropdown: _DropdownLine<String>(
                        hint: 'Category',
                        value: _newCategory,
                        items: _categories
                            .map((c) => _DropdownLineItem<String>(value: c, label: c))
                            .toList(),
                        onChanged: (v) => setState(() => _newCategory = v),
                      ),
                      // File attach UI
                      fileName: _pickedFile?.name,
                      onPickFile: _isUploading ? null : _pickPdf,
                      isUploading: _isUploading,
                      progress: _uploadProgress,
                    ),
                    const SizedBox(height: 16),

                    // Live list of papers
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _papersCol.orderBy('uploadedAt', descending: true).snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('Error: ${snap.error}', style: t.bodyMedium?.copyWith(color: Colors.red)),
                          );
                        }

                        final all = snap.data?.docs.map((d) => PastPaper.fromDoc(d)).toList()
                            ?? const <PastPaper>[];
                        final filtered = _applyFiltersSortSearch(all);

                        if (filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('No papers found.'),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in filtered) ...[
                              _PaperItemCard(
                                paper: p,
                                facultyLabel: facultyIdToName[p.facultyId] ??
                                    (p.legacyFaculty.isNotEmpty ? p.legacyFaculty : '—'),
                                prettyDate: _prettyDate(p.uploadedAt),
                                onOpen: p.fileUrl == null ? null : () => _openUrl(p.fileUrl!),
                                onDelete: () => _deletePaper(p),
                              ),
                              const SizedBox(height: 14),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/* -------------------------------- Widgets --------------------------------- */

class _HeaderBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _HeaderBar({required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        _IconSquare(onTap: onBack, icon: Icons.arrow_back),
        const SizedBox(width: 10),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text('PEERS', style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        _IconSquare(onTap: onLogout, icon: Icons.logout),
      ],
    );
  }
}

class _IconSquare extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _IconSquare({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black26),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _DropdownPill<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  const _DropdownPill({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T>(
        isDense: true,
        isExpanded: true,
        underline: const SizedBox(),
        value: value,
        icon: const Icon(Icons.arrow_drop_down),
        items: items.map((e) => DropdownMenuItem<T>(value: e, child: Text('$e'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// DropdownPill that supports a `null` value (e.g. "All Faculties")
class _DropdownPillNullable<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?> onChanged;
  const _DropdownPillNullable({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T?>(
        isDense: true,
        isExpanded: true,
        underline: const SizedBox(),
        value: value,
        icon: const Icon(Icons.arrow_drop_down),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  const _StatBox({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 156,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Text('$count', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: t.bodySmall),
        ],
      ),
    );
  }
}

/* -------------------------- Add Paper Card (Form) -------------------------- */

class _DropdownLineItem<T> {
  final T value;
  final String label;
  _DropdownLineItem({required this.value, required this.label});
}

class _AddPaperCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final _DropdownLine<String> facultyDropdown;
  final _DropdownLine<int> yearDropdown;
  final _DropdownLine<String> semDropdown;
  final _DropdownLine<String> catDropdown;

  final String? fileName;
  final VoidCallback? onPickFile;
  final bool isUploading;
  final double progress;

  const _AddPaperCard({
    required this.formKey,
    required this.titleCtrl,
    required this.facultyDropdown,
    required this.yearDropdown,
    required this.semDropdown,
    required this.catDropdown,
    required this.fileName,
    required this.onPickFile,
    required this.isUploading,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add New Paper', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Attach a PDF and fill details', style: t.bodySmall),
            const SizedBox(height: 10),
            TextFormField(
              controller: titleCtrl,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              enableSuggestions: true,
              autocorrect: true,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Paper title required' : null,
              decoration: InputDecoration(
                hintText: 'Insert Paper Title',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 8),
            facultyDropdown,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: yearDropdown),
                const SizedBox(width: 10),
                Expanded(child: semDropdown),
              ],
            ),
            const SizedBox(height: 8),
            catDropdown,
            const SizedBox(height: 10),

            // File attach row
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: isUploading ? null : onPickFile,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach PDF'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName == null ? 'No file selected' : fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: fileName == null ? Colors.red : Colors.black87),
                  ),
                ),
              ],
            ),

            if (isUploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress == 0.0 ? null : progress),
              const SizedBox(height: 4),
              Text('Uploading...', style: t.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _DropdownLine<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final List<_DropdownLineItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownLine({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T>(
        isDense: true,
        isExpanded: true,
        value: value,
        hint: Text(hint),
        underline: const SizedBox(),
        items: items
            .map((e) => DropdownMenuItem<T>(
          value: e.value,
          child: Text(e.label),
        ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _PaperItemCard extends StatelessWidget {
  final PastPaper paper;
  final String facultyLabel; // resolved via facultyId → name
  final String prettyDate;
  final VoidCallback? onOpen;
  final VoidCallback onDelete;

  const _PaperItemCard({
    required this.paper,
    required this.facultyLabel,
    required this.prettyDate,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB9CCF3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          Positioned(right: 0, top: 0, child: _StatusChip(label: paper.category)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PDF Badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFB9CCF3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf, size: 20, color: Colors.black87),
                    const SizedBox(height: 2),
                    Text('PDF', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paper.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(paper.code, style: t.bodySmall),
                    Text(facultyLabel, style: t.bodySmall), // show resolved faculty name
                    Text('${paper.year} ${paper.semester}', style: t.bodySmall),
                    if (paper.fileName != null) ...[
                      const SizedBox(height: 4),
                      Text('File: ${paper.fileName}', style: t.labelSmall),
                    ],
                    const SizedBox(height: 8),

                    LayoutBuilder(
                      builder: (context, c) {
                        final tight = c.maxWidth < 360;
                        final info = Text('Uploaded\n$prettyDate', style: t.labelSmall);
                        final openBtn = OutlinedButton(
                          onPressed: onOpen,
                          child: const Text('Open'),
                        );
                        final deleteBtn = FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: onDelete,
                          child: const Text('Delete'),
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            info,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: tight
                                  ? Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                runAlignment: WrapAlignment.end,
                                children: [
                                  openBtn,
                                  deleteBtn,
                                ],
                              )
                                  : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  openBtn,
                                  const SizedBox(width: 8),
                                  deleteBtn,
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
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
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
