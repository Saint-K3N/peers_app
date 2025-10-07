// lib/peer_profile_page.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PeerProfilePage extends StatelessWidget {
  const PeerProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final userId = (args['userId'] as String?) ?? '';
    if (userId.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Missing helper ID.\nOpen this page by tapping a tutor/counsellor card.',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _PeerProfileBody(userId: userId),
        ),
      ),
    );
  }
}

/* ------------------------------- Body -------------------------------- */

class _PeerProfileBody extends StatefulWidget {
  final String userId;
  const _PeerProfileBody({required this.userId});

  @override
  State<_PeerProfileBody> createState() => _PeerProfileBodyState();
}

class _PeerProfileBodyState extends State<_PeerProfileBody> {
  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _appsCol = FirebaseFirestore.instance.collection('peer_applications');
  final _interestsCol = FirebaseFirestore.instance.collection('interests');
  final _facultiesCol = FirebaseFirestore.instance.collection('faculties');

  // caches
  final Map<String, String> _interestTitleCache = {};
  final Map<String, String> _facultyTitleCache = {};

  Future<String> _facultyTitle(String id) async {
    if (id.isEmpty) return '';
    if (_facultyTitleCache[id] != null) return _facultyTitleCache[id]!;
    final snap = await _facultiesCol.doc(id).get();
    final data = snap.data() ?? {};
    final title = (data['title'] ?? data['name'] ?? '').toString().trim();
    if (title.isNotEmpty) _facultyTitleCache[id] = title;
    return _facultyTitleCache[id] ?? '';
  }

  Future<List<String>> _interestTitles(List<String> ids) async {
    // whereIn max 10 — chunk the queries
    final missing = <String>[];
    final result = <String>[];
    for (final id in ids) {
      if (_interestTitleCache[id] != null) {
        result.add(_interestTitleCache[id]!);
      } else {
        missing.add(id);
      }
    }
    for (int i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, math.min(i + 10, missing.length));
      final snap = await _interestsCol
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        final title = (d['title'] ?? '').toString().trim();
        if (title.isNotEmpty) _interestTitleCache[d.id] = title;
      }
    }
    final out = <String>[];
    for (final id in ids) {
      final t = _interestTitleCache[id];
      if (t != null && t.isNotEmpty) out.add(t);
    }
    return out;
  }

  String _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final prof = m['profile'];
    if (prof is Map<String, dynamic>) {
      for (final k in keys) {
        final v = prof[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeaderPeerProfile(),
        const SizedBox(height: 16),

        Text('Profile',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Tutor/Counsellor details', style: t.bodySmall),
        const SizedBox(height: 12),

        // Load user + approved application + non-cancelled session count
        FutureBuilder(
          future: Future.wait([
            _usersCol.doc(widget.userId).get(),
            _appsCol
                .where('userId', isEqualTo: widget.userId)
                .where('status', isEqualTo: 'approved')
                .limit(1)
                .get(),
            FirebaseFirestore.instance
                .collection('appointments')
                .where('helperId', isEqualTo: widget.userId)
                .get(),
          ]),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (!snap.hasData) {
              return const Text('Failed to load profile.');
            }

            final userSnap =
            snap.data![0] as DocumentSnapshot<Map<String, dynamic>>;
            final appsSnap =
            snap.data![1] as QuerySnapshot<Map<String, dynamic>>;
            final apptSnap =
            snap.data![2] as QuerySnapshot<Map<String, dynamic>>;

            final u = userSnap.data() ?? {};
            final name = _pickString(u, [
              'fullName',
              'full_name',
              'name',
              'displayName',
              'display_name'
            ]).isEmpty
                ? 'Helper'
                : _pickString(u, [
              'fullName',
              'full_name',
              'name',
              'displayName',
              'display_name'
            ]);
            final email = _pickString(u, ['email', 'emailAddress']);
            final facultyId = (u['facultyId'] ?? '').toString();
            final about =
            (u['about'] ?? (u['profile'] is Map ? u['profile']['about'] : ''))
                .toString();

            String? photoUrl;
            for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
              final v = u[k];
              if (v is String && v.trim().isNotEmpty) {
                photoUrl = v.trim();
                break;
              }
            }
            if ((photoUrl == null || photoUrl!.isEmpty) &&
                u['profile'] is Map<String, dynamic>) {
              final prof = u['profile'] as Map<String, dynamic>;
              for (final k in ['photoUrl', 'photoURL', 'avatarUrl', 'avatar']) {
                final v = prof[k];
                if (v is String && v.trim().isNotEmpty) {
                  photoUrl = v.trim();
                  break;
                }
              }
            }

            final role = appsSnap.docs.isNotEmpty
                ? (appsSnap.docs.first.data()['requestedRole'] ?? 'peer')
                .toString()
                : 'peer';

            final interestsIds = appsSnap.docs.isNotEmpty &&
                (appsSnap.docs.first.data()['interestsIds'] is List)
                ? (appsSnap.docs.first.data()['interestsIds'] as List)
                .map((e) => e.toString())
                .toList()
                : const <String>[];

            // session count (non-cancelled)
            int sessions = 0;
            for (final d in apptSnap.docs) {
              final st =
              (d.data()['status'] ?? '').toString().toLowerCase().trim();
              if (st == 'cancelled') continue;
              sessions++;
            }

            return FutureBuilder(
              future: Future.wait([
                _facultyTitle(facultyId),
                _interestTitles(interestsIds),
              ]),
              builder: (context, infoSnap) {
                if (infoSnap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final facultyTitle = (infoSnap.data?[0] as String?) ?? '';
                final interestTitles =
                (infoSnap.data?[1] as List<String>? ?? const []);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage:
                                (photoUrl != null && photoUrl!.isNotEmpty)
                                    ? NetworkImage(photoUrl!)
                                    : null,
                                child: (photoUrl == null || photoUrl!.isEmpty)
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                    if (facultyTitle.isNotEmpty)
                                      Text(facultyTitle,
                                          style: Theme.of(context).textTheme.bodySmall),
                                    if (email.isNotEmpty)
                                      Text(email,
                                          style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(height: 6),
                                    _SpecializeLine(items: interestTitles),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _RoleChip(role: role),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(label: 'Sessions', value: '$sessions'),
                          const SizedBox(height: 8),
                          Text('Bio', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black26),
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.white,
                            ),
                            child: Text(
                              about.isEmpty ? 'N/A' : about,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB9C85B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 10),
                                elevation: 0,
                              ),
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  '/student/appointment',
                                  arguments: {
                                    'userId': widget.userId,
                                    'name': name,
                                    'faculty': facultyTitle,
                                    'email': email,
                                    'sessions': sessions,
                                    'match': 'Good Match',
                                    'specializes': interestTitles,
                                    'photoUrl': photoUrl,
                                  },
                                );
                              },
                              child: const Text('Book'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _HeaderPeerProfile extends StatelessWidget {
  const _HeaderPeerProfile();

  Future<void> _logout(BuildContext context) async {
    // Sign out and return to login
    try {
      // if using FirebaseAuth:
      // await FirebaseAuth.instance.signOut();
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (_) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        // back button
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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 12),

        // titles
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Peer Portal', style: t.titleMedium),
              Text('Profile',
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

class _RoleChip extends StatelessWidget {
  final String role; // peer_tutor | peer_counsellor | peer
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final isTutor = role == 'peer_tutor';
    final isCounsellor = role == 'peer_counsellor';
    final text = isTutor
        ? 'Peer Tutor'
        : (isCounsellor ? 'Peer Counsellor' : 'Peer');
    final (bg, fg) = isTutor
        ? (const Color(0xFFC9F2D9), const Color(0xFF1B5E20))
        : (const Color(0xFFFCE8C1), const Color(0xFF6D4C00));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Text('$label: ', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(value, style: t.bodySmall),
      ],
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
        style: t.bodySmall
            ?.copyWith(fontWeight: isBold ? FontWeight.w800 : FontWeight.w400),
      ));
      if (i != items.length - 1) {
        spans.add(TextSpan(text: ', ', style: t.bodySmall));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
