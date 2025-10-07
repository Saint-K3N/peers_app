// lib/peer_tutor_past_year_repository_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/* ---------------------------- Page (Peer Tutor) --------------------------- */

class PeerTutorPastYearRepositoryPage extends StatefulWidget {
  const PeerTutorPastYearRepositoryPage({super.key});

  @override
  State<PeerTutorPastYearRepositoryPage> createState() =>
      _PeerTutorPastYearRepositoryPageState();
}

class _PeerTutorPastYearRepositoryPageState
    extends State<PeerTutorPastYearRepositoryPage> {
  final _searchCtrl = TextEditingController();
  String? _selectedFacultyId; // null = All Faculties
  String _sort = 'Most Recent'; // 'Most Recent' | 'Oldest' | 'A–Z'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // open link in in-app browser (with fallbacks)
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      bool opened = false;
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link:\n$url')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link:\n$url')),
      );
    }
  }

  // pretty "3rd Jun 2025"
  String _prettyDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    String suf(int n) {
      if (n >= 11 && n <= 13) return 'th';
      switch (n % 10) {
        case 1: return 'st';
        case 2: return 'nd';
        case 3: return 'rd';
        default: return 'th';
      }
    }
    return '${d.day}${suf(d.day)} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final facultiesCol = FirebaseFirestore.instance.collection('faculties');
    final papersCol = FirebaseFirestore.instance.collection('past_papers');

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TutorHeader(), // back + logo + "Peer Tutor Portal" + logout
              const SizedBox(height: 16),

              Text('Past Year Repository',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Access previous exam papers', style: t.bodySmall),
              const SizedBox(height: 12),

              // Faculties stream (for names + filter list)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: facultiesCol.orderBy('name').snapshots(),
                builder: (context, facSnap) {
                  final facDocs = facSnap.data?.docs ?? const [];
                  final facultyIdToName = <String, String>{
                    for (final d in facDocs)
                      d.id: (d.data()['name'] ?? '').toString()
                  };

                  return Column(
                    children: [
                      // Search
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search by title or code',
                          prefixIcon: const Icon(Icons.search),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filters
                      Row(
                        children: [
                          Expanded(
                            child: _DropdownShell<String?>(
                              value: _selectedFacultyId,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Faculties'),
                                ),
                                ...facultyIdToName.entries.map(
                                      (e) => DropdownMenuItem<String?>(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _selectedFacultyId = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DropdownShell<String>(
                              value: _sort,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Most Recent',
                                  child: Text('Most Recent'),
                                ),
                                DropdownMenuItem(
                                  value: 'Oldest',
                                  child: Text('Oldest'),
                                ),
                                DropdownMenuItem(
                                  value: 'A–Z',
                                  child: Text('A–Z'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _sort = v ?? 'Most Recent'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Papers list
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: papersCol
                            .orderBy('uploadedAt', descending: true)
                            .snapshots(),
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
                              child: Text(
                                'Error: ${snap.error}',
                                style: t.bodyMedium?.copyWith(color: Colors.red),
                              ),
                            );
                          }

                          final docs = snap.data?.docs ?? const [];
                          final items = <_Paper>[];
                          for (final d in docs) {
                            final m = d.data();

                            final title = (m['title'] ?? '').toString().trim();
                            final code = (m['code'] ?? '').toString().trim();
                            final facultyId = (m['facultyId'] ?? '').toString().trim();
                            final facultyName = facultyIdToName[facultyId] ?? '—';
                            final year = (m['year'] ?? 0) as int;
                            final semester = (m['semester'] ?? '').toString();
                            final category = (m['category'] ?? '').toString();
                            final fileUrl = (m['fileUrl'] ?? '').toString();
                            final ts = m['uploadedAt'];
                            final uploadedAt = (ts is Timestamp)
                                ? ts.toDate()
                                : DateTime.fromMillisecondsSinceEpoch(0);

                            items.add(_Paper(
                              title: title.isNotEmpty ? title : code,
                              code: code,
                              facultyName: facultyName,
                              facultyId: facultyId,
                              semesterYear: (year > 0 && semester.isNotEmpty)
                                  ? '$year $semester'
                                  : (semester.isNotEmpty ? semester : '$year'),
                              tag: category.isNotEmpty ? category : 'Paper',
                              uploadedAt: uploadedAt,
                              fileUrl: fileUrl.isNotEmpty ? fileUrl : null,
                            ));
                          }

                          // Filter + search
                          var filtered = items.where((p) {
                            final matchesFaculty =
                                _selectedFacultyId == null ||
                                    p.facultyId == _selectedFacultyId;
                            if (!matchesFaculty) return false;

                            final q = _searchCtrl.text.trim().toLowerCase();
                            if (q.isEmpty) return true;

                            return p.title.toLowerCase().contains(q) ||
                                p.code.toLowerCase().contains(q) ||
                                p.facultyName.toLowerCase().contains(q) ||
                                p.semesterYear.toLowerCase().contains(q);
                          }).toList();

                          // Sort
                          switch (_sort) {
                            case 'Most Recent':
                              filtered.sort((a, b) =>
                                  b.uploadedAt.compareTo(a.uploadedAt));
                              break;
                            case 'Oldest':
                              filtered.sort((a, b) =>
                                  a.uploadedAt.compareTo(b.uploadedAt));
                              break;
                            case 'A–Z':
                              filtered.sort((a, b) => a.title
                                  .toLowerCase()
                                  .compareTo(b.title.toLowerCase()));
                              break;
                          }

                          if (filtered.isEmpty) {
                            return const Text('No papers found.');
                          }

                          return Column(
                            children: [
                              for (final p in filtered) ...[
                                _PaperCard(
                                  paper: p,
                                  uploadedPretty: _prettyDate(p.uploadedAt),
                                  onPreview: p.fileUrl == null
                                      ? null
                                      : () => _openUrl(p.fileUrl!),
                                  onDownload: p.fileUrl == null
                                      ? null
                                      : () => _openUrl(p.fileUrl!),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
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

/* --------------------------------- Models --------------------------------- */

class _Paper {
  final String title;
  final String code;
  final String facultyName; // resolved from facultyId
  final String facultyId;   // for filtering
  final String semesterYear;
  final String tag;
  final DateTime uploadedAt;
  final String? fileUrl;

  const _Paper({
    required this.title,
    required this.code,
    required this.facultyName,
    required this.facultyId,
    required this.semesterYear,
    required this.tag,
    required this.uploadedAt,
    required this.fileUrl,
  });
}

/* -------------------------------- Widgets -------------------------------- */

class _TutorHeader extends StatelessWidget {
  const _TutorHeader();

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
        // Back
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

        // Logo
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

        // Title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Peer Tutor',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Logout button
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

class _DropdownShell<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownShell({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  final _Paper paper;
  final String uploadedPretty;
  final VoidCallback? onPreview;
  final VoidCallback? onDownload;

  const _PaperCard({
    required this.paper,
    required this.uploadedPretty,
    required this.onPreview,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final previewBtn = OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.black),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: onPreview,
      child: const Text('Preview'),
    );

    final downloadBtn = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: onDownload,
      child: const Text('Download'),
    );

    final uploaded = Text('Uploaded\n$uploadedPretty', style: t.labelSmall);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Title row + tag chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PdfThumb(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(paper.title,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(paper.facultyName, style: t.bodySmall),
                    Text(paper.semesterYear, style: t.bodySmall),
                    if (paper.code.isNotEmpty)
                      Text('Code: ${paper.code}', style: t.labelSmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TagChip(label: paper.tag),
            ],
          ),
          const SizedBox(height: 10),

          // Footer: uploaded + buttons
          LayoutBuilder(
            builder: (context, c) {
              final tight = c.maxWidth < 330;
              if (tight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: uploaded),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        previewBtn,
                        const SizedBox(width: 8),
                        downloadBtn,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: uploaded),
                  previewBtn,
                  const SizedBox(width: 8),
                  downloadBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PdfThumb extends StatelessWidget {
  const _PdfThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54),
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                ),
              ),
            ),
          ),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, size: 18),
                SizedBox(height: 2),
                Text('PDF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final fg = Colors.black87;
    final bg = Colors.black12;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(.25)),
      ),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
