// lib/student_find_help_page.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StudentFindHelpPage extends StatefulWidget {
  const StudentFindHelpPage({super.key});

  @override
  State<StudentFindHelpPage> createState() => _StudentFindHelpPageState();
}

/* ---------------------------------- Model --------------------------------- */

enum MatchLevel { best, good, low }

class HelperProfile {
  final String userId;
  final String name;
  final String faculty;           // resolved faculty title
  final String email;
  final String bio;               // ** NEW: user's about/bio text
  final List<String> specializes; // interest titles
  final int sessions;             // total (non-cancelled) appointments
  final MatchLevel match;
  final Map<String, dynamic> rawUser; // extra user data if needed
  final String? photoUrl;         // profile photo url, if any

  HelperProfile({
    required this.userId,
    required this.name,
    required this.faculty,
    required this.email,
    required this.bio,
    required this.specializes,
    required this.sessions,
    required this.match,
    required this.rawUser,
    this.photoUrl,
  });
}

/* ---------------------------------- Page ---------------------------------- */

class _StudentFindHelpPageState extends State<StudentFindHelpPage> {
  String _query = '';
  int _tabIndex = 0; // 0 = tutors, 1 = counsellors
  bool _loadingInterests = true;
  bool _appliedInitArgs = false;

  // Student's interest IDs
  Set<String> _studentAcademicIds = {};
  Set<String> _studentCounselingIds = {};

  // Student's interest titles for current tab
  List<String> _studentInterestTitlesForTab = [];

  // Caches
  final Map<String, String> _interestTitleCache = {}; // interestId -> title
  final Map<String, String> _facultyTitleCache = {};  // facultyId -> title

  // Firestore refs
  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');
  CollectionReference<Map<String, dynamic>> get _interestsCol =>
      FirebaseFirestore.instance.collection('interests');
  CollectionReference<Map<String, dynamic>> get _facultiesCol =>
      FirebaseFirestore.instance.collection('faculties');

  String get _roleString => _tabIndex == 0 ? 'peer_tutor' : 'peer_counsellor';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedInitArgs) return;

    final args = ModalRoute.of(context)?.settings.arguments;

    int? tabFromArgs;
    if (args is Map) {
      if (args['initialTab'] is int) tabFromArgs = args['initialTab'] as int;
      if (args['tab'] is int) tabFromArgs = (tabFromArgs ?? args['tab']) as int;
      final role = (args['role'] ?? args['initialRole'] ?? '').toString().toLowerCase();
      if (tabFromArgs == null && role.isNotEmpty) {
        tabFromArgs = (role.contains('counsel')) ? 1 : 0;
      }
    } else if (args is int) {
      tabFromArgs = args;
    }

    if (tabFromArgs != null && (tabFromArgs == 0 || tabFromArgs == 1)) {
      _tabIndex = tabFromArgs;
      _resolveStudentInterestTitlesForTab();
    }

    _appliedInitArgs = true;
  }

  @override
  void initState() {
    super.initState();
    _loadStudentInterests();
  }

  Future<void> _loadStudentInterests() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingInterests = false);
      return;
    }

    try {
      final snap = await _usersCol.doc(uid).get();
      final data = snap.data() ?? {};

      List<String> _readIds(dynamic v) {
        if (v is List) {
          return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        }
        return const <String>[];
      }

      // accept both common variants (plural/singular)
      final acadIds = {
        ..._readIds(data['academicInterestIds']),
        ..._readIds(data['academicInterestsIds']),
      };
      final counIds = {
        ..._readIds(data['counselingTopicIds']),
        ..._readIds(data['counselingTopicsIds']),
      };

      _studentAcademicIds = acadIds.toSet();
      _studentCounselingIds = counIds.toSet();

      await _resolveStudentInterestTitlesForTab();
      setState(() => _loadingInterests = false);
    } catch (_) {
      setState(() => _loadingInterests = false);
    }
  }

  Future<void> _resolveStudentInterestTitlesForTab() async {
    final ids = _tabIndex == 0 ? _studentAcademicIds : _studentCounselingIds;
    _studentInterestTitlesForTab = await _getInterestTitlesByIds(ids.toList());
    setState(() {});
  }

  /// Resolve interest titles, chunking whereIn (10 per query)
  Future<List<String>> _getInterestTitlesByIds(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];

    final missing = <String>[];

    for (final id in ids) {
      if (_interestTitleCache[id] == null) missing.add(id);
    }

    for (int i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, math.min(i + 10, missing.length));
      final q = await _interestsCol
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final d in q.docs) {
        final title = (d.data()['title'] ?? d.data()['name'] ?? '').toString().trim();
        if (title.isNotEmpty) {
          _interestTitleCache[d.id] = title;
        }
      }
    }

    final out = <String>[];
    for (final id in ids) {
      final t = _interestTitleCache[id];
      if (t != null && t.isNotEmpty) out.add(t);
    }
    return out;
  }

  Future<String> _getFacultyTitle(String facultyId) async {
    if (facultyId.isEmpty) return '';
    final cached = _facultyTitleCache[facultyId];
    if (cached != null) return cached;

    try {
      final snap = await _facultiesCol.doc(facultyId).get();
      final data = snap.data() ?? {};
      final title = (data['title'] ?? data['name'] ?? '').toString().trim();
      if (title.isNotEmpty) {
        _facultyTitleCache[facultyId] = title;
        return title;
      }
    } catch (_) {}
    return '';
  }

  MatchLevel _matchFromOverlap(int overlap) {
    if (overlap >= 2) return MatchLevel.best;
    if (overlap == 1) return MatchLevel.good;
    return MatchLevel.low;
  }

  /// Build one helper card from a **user** document (approved peer in users.role + status).
  Widget _buildHelperFromUserDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
      ) {
    final helperData = userDoc.data();

    // Relevant helper interest IDs by tab
    final helperInterestIds = _tabIndex == 0
        ? _readIdsFlexible(helperData, keys: const [
      'academicInterestIds',
      'academicInterestsIds',
      'profile.academicInterestIds',
    ])
        : _readIdsFlexible(helperData, keys: const [
      'counselingTopicIds',
      'counselingTopicsIds',
      'profile.counselingTopicIds',
    ]);

    final studentIds =
    _tabIndex == 0 ? _studentAcademicIds : _studentCounselingIds;

    return FutureBuilder(
      future: Future.wait([
        _getInterestTitlesByIds(helperInterestIds), // interest titles
        FirebaseFirestore.instance
            .collection('appointments')
            .where('helperId', isEqualTo: userDoc.id)
            .get(), // count non-cancelled
      ]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Opacity(
            opacity: .6,
            child: _HelperCard(
              p: HelperProfile(
                userId: userDoc.id,
                name: 'Loading…',
                faculty: '',
                email: '',
                bio: '',
                specializes: const [],
                sessions: 0,
                match: MatchLevel.low,
                rawUser: const {},
                photoUrl: null,
              ),
              onBook: () {},
            ),
          );
        }
        if (!snap.hasData) return const SizedBox.shrink();

        final titles = (snap.data![0] as List<String>);
        final allApptsSnap =
        snap.data![1] as QuerySnapshot<Map<String, dynamic>>;

        // --- SESSION CALCULATION ---
        int totalNonCancelled = 0;
        for (final d in allApptsSnap.docs) {
          final st = (d.data()['status'] ?? '').toString().toLowerCase().trim();
          if (st == 'cancelled') continue;
          totalNonCancelled++;
        }

        //IF INTEREST OVERLAPS
        final overlap =
            helperInterestIds.where((id) => studentIds.contains(id)).length;
        final match = _matchFromOverlap(overlap);

        final name = _pickString(helperData, [
          'fullName',
          'full_name',
          'name',
          'displayName',
          'display_name'
        ]).ifEmpty('—');

        final email =
        _pickString(helperData, ['email', 'emailAddress']).ifEmpty('—');

        final bio = (helperData['about'] ?? '').toString();

        final facultyId = (helperData['facultyId'] ?? '').toString();

        // resolve photo url
        String? photoUrl;
        const possiblePhotoKeys = ['photoURL', 'photoUrl', 'avatarUrl', 'avatar'];
        for (final k in possiblePhotoKeys) {
          final v = helperData[k];
          if (v is String && v.trim().isNotEmpty) {
            photoUrl = v.trim();
            break;
          }
        }
        if ((photoUrl == null || photoUrl!.isEmpty) &&
            helperData['profile'] is Map<String, dynamic>) {
          final prof = helperData['profile'] as Map<String, dynamic>;
          for (final k in possiblePhotoKeys) {
            final v = prof[k];
            if (v is String && v.trim().isNotEmpty) {
              photoUrl = v.trim();
              break;
            }
          }
        }

        return FutureBuilder<String>(
          future: _getFacultyTitle(facultyId),
          builder: (context, facSnap) {
            final facultyTitle = (facSnap.data ?? '').trim();

            final profile = HelperProfile(
              userId: userDoc.id,
              name: name,
              faculty: facultyTitle,
              email: email,
              bio: bio,
              specializes: titles,
              sessions: totalNonCancelled, // non-cancelled
              match: match,
              rawUser: helperData,
              photoUrl: photoUrl,
            );

            // Search filter
            final q = _query.trim().toLowerCase();
            if (q.isNotEmpty) {
              final inName = profile.name.toLowerCase().contains(q);
              final inSpec = profile.specializes
                  .any((s) => s.toLowerCase().contains(q));
              if (!inName && !inSpec) return const SizedBox.shrink();
            }

            return _HelperCard(
              p: profile,
              onBook: () => _openBooking(profile),
            );
          },
        );
      },
    );
  }

  void _openBooking(HelperProfile p) {
    Navigator.pushNamed(
      context,
      '/student/appointment',
      arguments: {
        'name': p.name,
        'faculty': p.faculty,
        'email': p.email,
        'bio': p.bio,
        'sessions': p.sessions,
        'match': _matchLabel(p.match),
        'specializes': p.specializes,
        'userId': p.userId,
        'photoUrl': p.photoUrl,
        'role': _roleString, // ** Pass role for session types
      },
    );
  }

  String _matchLabel(MatchLevel m) => switch (m) {
    MatchLevel.best => 'Best Match',
    MatchLevel.good => 'Good Match',
    MatchLevel.low => 'Low Match',
  };

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
              const _HeaderStudent(),
              const SizedBox(height: 16),

              Text('Find Help',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Matched based on your interest (edit in Profile)',
                  style: t.bodySmall),
              const SizedBox(height: 12),

              // Search
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search by name or topic',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),

              // Interests (from student profile)
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _loadingInterests
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(),
                  ),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tabIndex == 0
                          ? 'Your academic interests'
                          : 'Your counseling topics',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (_studentInterestTitlesForTab.isEmpty)
                      Text('No interests selected yet.',
                          style: t.bodySmall)
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._studentInterestTitlesForTab
                              .take(4)
                              .map((e) => _pill(e)),
                          if (_studentInterestTitlesForTab.length > 4)
                            _viewMorePill(),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Tabs
              _SegmentBar(
                left: 'Find Peer Tutors',
                right: 'Find Peer Counsellors',
                index: _tabIndex,
                onChanged: (i) async {
                  setState(() => _tabIndex = i);
                  await _resolveStudentInterestTitlesForTab();
                },
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
                  child: const Text('Please sign in to see available helpers.'),
                )
              else
              // 🔄 SEARCH **USERS** (approved peers) instead of peer_applications
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _usersCol
                      .where('status', isEqualTo: 'active')
                      .where('role', isEqualTo: _roleString) // 'peer_tutor' | 'peer_counsellor'
                      .snapshots(),
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
                      return Text('Error: ${snap.error}',
                          style: t.bodyMedium?.copyWith(color: Colors.red));
                    }

                    final docs = (snap.data?.docs ?? const [])
                        .where((d) => d.id != uid) // hide myself
                        .toList();

                    if (docs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          _tabIndex == 0
                              ? 'No peer tutors found yet.'
                              : 'No peer counsellors found yet.',
                        ),
                      );
                    }

                    final gap =
                    _tabIndex == 0 ? 6.0 : 12.0; // tighter gap for tutors
                    return Column(
                      children: [
                        for (final d in docs) ...[
                          _buildHelperFromUserDoc(d),
                          SizedBox(height: gap),
                        ],
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

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFCEDCFB)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _viewMorePill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE6C7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text('View More',
        style: TextStyle(fontWeight: FontWeight.w700)),
  );

  // extract string from multiple possible keys (user name/email)
  String _pickString(Map<String, dynamic> m, List<String> keys) {
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
    return '';
  }

  /// Reads IDs from multiple possible keys (supports nested `profile.*` keys).
  List<String> _readIdsFlexible(Map<String, dynamic> m,
      {required List<String> keys}) {
    final out = <String>{};

    void absorb(dynamic v) {
      if (v == null) return;
      if (v is List) {
        for (final e in v) {
          final s = '$e'.trim();
          if (s.isNotEmpty) out.add(s);
        }
      } else if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) out.add(s);
      }
    }

    Map<String, dynamic>? profile;
    if (m['profile'] is Map<String, dynamic>) {
      profile = (m['profile'] as Map<String, dynamic>);
    }

    for (final k in keys) {
      if (k.startsWith('profile.')) {
        final kk = k.substring('profile.'.length);
        absorb(profile?[kk]);
      } else {
        absorb(m[k]);
      }
    }
    return out.toList();
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _HeaderStudent extends StatelessWidget {
  const _HeaderStudent();

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
              Text('Student',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // logout button
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

class _SegmentBar extends StatelessWidget {
  final String left, right;
  final int index;
  final ValueChanged<int> onChanged;
  const _SegmentBar(
      {required this.left,
        required this.right,
        required this.index,
        required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final activeClr = Colors.black;
    final inactiveClr = Colors.white;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(0),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: index == 0 ? activeClr : inactiveClr,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                border: Border.all(color: Colors.black26),
              ),
              alignment: Alignment.center,
              child: Text(left,
                  style: TextStyle(
                      color: index == 0 ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(1),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: index == 1 ? activeClr : inactiveClr,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: Colors.black26),
              ),
              alignment: Alignment.center,
              child: Text(right,
                  style: TextStyle(
                      color: index == 1 ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}

class _HelperCard extends StatelessWidget {
  final HelperProfile p;
  final VoidCallback onBook; // tap Book button only
  const _HelperCard({required this.p, required this.onBook});

  void _openProfile(BuildContext context) {
    // This will navigate to a generic peer profile viewer, not implemented here.
    // For now, it could show a dialog or just do nothing.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Viewing ${p.name}'s profile.")));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const borderClr = Color(0xFFDDE6FF);

    final (chipText, chipBg, chipFg) = switch (p.match) {
      MatchLevel.best => ('Best Match', const Color(0xFFC9F2D9), const Color(0xFF1B5E20)),
      MatchLevel.good => ('Good Match', const Color(0xFFFCE8C1), const Color(0xFF6D4C00)),
      MatchLevel.low => ('Low Match', const Color(0xFFE4E6EB), const Color(0xFF424242)),
    };

    final bookBtn = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFB9C85B),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        elevation: 0,
      ),
      onPressed: onBook,
      child: const Text('Book'),
    );

    final avatar = GestureDetector(
      onTap: () => _openProfile(context),
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade300,
            backgroundImage:
            (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                ? NetworkImage(p.photoUrl!)
                : null,
            child: (p.photoUrl == null || p.photoUrl!.isEmpty)
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 6),
          Text('${p.sessions}\nsessions',
              textAlign: TextAlign.center, style: t.labelSmall),
        ],
      ),
    );

    final info = GestureDetector(
      onTap: () => _openProfile(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text('Faculty: ${p.faculty.isEmpty ? '—' : p.faculty}',
              style: t.bodySmall),
          const SizedBox(height: 6),
          _SpecializeLine(items: p.specializes),
          const SizedBox(height: 6),
          Text(
            'Bio: ${p.bio.isEmpty ? "N/A" : p.bio}',
            style: t.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final chip = _StatusChip(label: chipText, bg: chipBg, fg: chipFg);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderClr, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 360;

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(child: info),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: chip,
                        ),
                      ),
                      const SizedBox(width: 8),
                      bookBtn,
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(child: info),
                const SizedBox(width: 8),
                chip,
                const SizedBox(width: 8),
                bookBtn,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _StatusChip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child:
      Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _SpecializeLine extends StatelessWidget {
  final List<String> items;
  const _SpecializeLine({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final boldCount = items.length >= 2 ? 2 : items.length;
    final spans = <TextSpan>[
      TextSpan(text: 'Specialize: ', style: t.bodySmall),
    ];
    for (var i = 0; i < items.length; i++) {
      final isBold = i < boldCount;
      spans.add(TextSpan(
        text: items[i],
        style: t.bodySmall?.copyWith(
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
        ),
      ));
      if (i != items.length - 1) {
        spans.add(TextSpan(text: ', ', style: t.bodySmall));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}

/* ------------------------------- helpers ------------------------------- */

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
