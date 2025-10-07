// lib/hop_review_applications_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Fallback: reuse admin detail page until HOP detail exists.
import 'hop_review_application_detail_page.dart';

/* ------------------------------- Model ------------------------------- */

enum AppType { peerTutor, peerCounselor }
enum AppStatus { pending, approved, rejected }

class PeerApplication {
  final String id;                // Firestore doc id
  final String userId;
  final String name;              // resolved from users/{uid}
  final String studentId;         // resolved from users/{uid}
  final String appCode;           // appCode field or derived
  final List<String> interests;   // titles only (resolved from interestsIds)
  final AppType type;             // requestedRole: tutor | counsellor
  final AppStatus status;         // pending | approved | rejected
  final bool hopApproved;         // HOP approved, still pending admin
  final DateTime submittedAt;

  PeerApplication({
    required this.id,
    required this.userId,
    required this.name,
    required this.studentId,
    required this.appCode,
    required this.interests,
    required this.type,
    required this.status,
    required this.hopApproved,
    required this.submittedAt,
  });

  static AppType _toType(String? role) {
    switch ((role ?? '').toLowerCase()) {
      case 'peer_tutor':
        return AppType.peerTutor;
      case 'peer_counsellor':
        return AppType.peerCounselor;
      default:
        return AppType.peerTutor;
    }
  }

  static AppStatus _toStatus(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'approved':
        return AppStatus.approved;
      case 'rejected':
        return AppStatus.rejected;
      default:
        return AppStatus.pending;
    }
  }

  static String _deriveCode(String? appCode, AppType t, String docId) {
    if (appCode != null && appCode.trim().isNotEmpty) return appCode;
    final role = t == AppType.peerTutor ? 'PT' : 'PC';
    final short = docId.length >= 6 ? docId.substring(0, 6).toUpperCase() : docId.toUpperCase();
    return 'APP-$role-$short';
  }

  static String _getString(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static Map<String, dynamic>? _sub(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }

  static String _extractName(Map<String, dynamic>? u) {
    if (u == null) return '—';

    final direct = _getString(u, [
      'fullName','full_name','name','displayName','display_name'
    ]);
    if (direct.isNotEmpty) return direct;

    final profile = _sub(u, 'profile');
    final profileName = _getString(profile, [
      'fullName','full_name','name','displayName','display_name'
    ]);
    if (profileName.isNotEmpty) return profileName;

    final first = _getString(u, ['firstName','first_name','givenName','given_name']);
    final last  = _getString(u, ['lastName','last_name','familyName','family_name','surname']);
    final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (combo.isNotEmpty) return combo;

    final pFirst = _getString(profile, ['firstName','first_name','givenName','given_name']);
    final pLast  = _getString(profile, ['lastName','last_name','familyName','family_name','surname']);
    final pCombo = [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
    if (pCombo.isNotEmpty) return pCombo;

    return '—';
  }

  static String _extractStudentId(Map<String, dynamic>? u, Map<String, dynamic> app) {
    String sid = _getString(u, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (sid.isNotEmpty) return sid;

    sid = _getString(_sub(u, 'profile'), ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (sid.isNotEmpty) return sid;

    sid = _getString(app, ['studentId','studentID','student_id','sid']);
    return sid;
  }

  /// Build from Firestore doc. Pass resolved [interestTitlesOverride] (from interestsIds).
  factory PeerApplication.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d, {
        Map<String, dynamic>? userData,
        List<String>? interestTitlesOverride,
      }) {
    final data = d.data() ?? {};
    final type = _toType(data['requestedRole'] as String?);
    final status = _toStatus(data['status'] as String?);
    final ts = data['submittedAt'];
    final submittedAt = ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

    final name = _extractName(userData);
    final sid  = _extractStudentId(userData, data);
    final appCode = _deriveCode(data['appCode'] as String?, type, d.id);

    return PeerApplication(
      id: d.id,
      userId: (data['userId'] ?? '').toString(),
      name: name.isEmpty ? '—' : name,
      studentId: sid,
      appCode: appCode,
      interests: (interestTitlesOverride ?? const <String>[]),
      type: type,
      status: status,
      hopApproved: (data['hopApproved'] ?? false) == true,
      submittedAt: submittedAt,
    );
  }

  PeerApplication copyWith({String? name, String? studentId, List<String>? interests}) => PeerApplication(
    id: id,
    userId: userId,
    name: name ?? this.name,
    studentId: studentId ?? this.studentId,
    appCode: appCode,
    interests: interests ?? this.interests,
    type: type,
    status: status,
    hopApproved: hopApproved,
    submittedAt: submittedAt,
  );
}

/* ------------------------------ Page ------------------------------ */

class HopReviewApplicationsPage extends StatefulWidget {
  const HopReviewApplicationsPage({super.key});

  @override
  State<HopReviewApplicationsPage> createState() =>
      _HopReviewApplicationsPageState();
}

class _HopReviewApplicationsPageState extends State<HopReviewApplicationsPage> {
  String _stage = 'All'; // All | Pending | Approved | Rejected

  static const bool kUseAdminDetailAsFallback = true;

  CollectionReference<Map<String, dynamic>> get _appsCol =>
      FirebaseFirestore.instance.collection('peer_applications');

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  CollectionReference<Map<String, dynamic>> get _interestsCol =>
      FirebaseFirestore.instance.collection('interests');

  CollectionReference<Map<String, dynamic>> get _facultiesCol =>
      FirebaseFirestore.instance.collection('faculties');

  // Cache: facultyId -> Future<bool> (does this faculty belong to me as approver?)
  final Map<String, Future<bool>> _facultyApproverCheck = {};

  // Lock to Peer Tutor only (tab removed)
  AppType get _currentType => AppType.peerTutor;
  String get _currentRoleStr => 'peer_tutor';

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      _dialog('Logout failed', '$e');
    }
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

  Future<Map<String, dynamic>?> _fetchUserData(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final doc = await _usersCol.doc(uid).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// Fetch interest titles for a list of interest IDs using batched whereIn (max 10).
  Future<List<String>> _fetchInterestTitles(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];
    final rows = <Map<String, dynamic>>[];

    for (int i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, math.min(i + 10, ids.length));
      final snap = await _interestsCol
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final title = (data['title'] ?? '').toString().trim();
        final seq = (data['seq'] ?? 0);
        if (title.isNotEmpty) {
          rows.add({'title': title, 'seq': seq is int ? seq : 0});
        }
      }
    }

    rows.sort((a, b) {
      final sa = (a['seq'] ?? 0) as int;
      final sb = (b['seq'] ?? 0) as int;
      final c = sa.compareTo(sb);
      if (c != 0) return c;
      return (a['title'] as String).toLowerCase().compareTo((b['title'] as String).toLowerCase());
    });

    return rows.map((e) => e['title'] as String).toList();
  }

  /// Is faculties/{facultyId}.approverUid == myUid ?
  Future<bool> _isFacultyApprovedByMe(String facultyId, String myUid) {
    if (facultyId.isEmpty || myUid.isEmpty) return Future.value(false);
    return _facultyApproverCheck.putIfAbsent(facultyId, () async {
      try {
        final d = await _facultiesCol.doc(facultyId).get();
        if (!d.exists) return false;
        final data = d.data();
        if (data == null) return false;
        final approver = (data['approverUid'] ?? '').toString().trim();
        return approver.isNotEmpty && approver == myUid;
      } catch (_) {
        return false;
      }
    });
  }

  /// Load user data + interest titles + faculty gate for THIS login user
  Future<({
  Map<String, dynamic>? userData,
  List<String> interestTitles,
  bool facultyApprovedByMe,
  })> _fetchExtrasForApp(
      DocumentSnapshot<Map<String, dynamic>> d,
      String myUid,
      ) async {
    final data = d.data() ?? {};
    final uid = (data['userId'] ?? '').toString();
    final applicantFacultyId = (data['facultyId'] ?? '').toString();

    final rawIds = (data['interestsIds'] is List)
        ? List<String>.from((data['interestsIds'] as List).map((e) => e.toString()))
        : <String>[];

    final userF   = _fetchUserData(uid);
    final titlesF = _fetchInterestTitles(rawIds);
    final gateF   = _isFacultyApprovedByMe(applicantFacultyId, myUid);

    final res = await Future.wait([userF, titlesF, gateF]);
    return (
    userData: res[0] as Map<String, dynamic>?,
    interestTitles: res[1] as List<String>,
    facultyApprovedByMe: res[2] as bool,
    );
  }

  void _openDetail(String appId) {
    if (kUseAdminDetailAsFallback) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HopReviewApplicationDetailPage(appId: appId),
        ),
      );
    } else {
      // Navigator.pushNamed(context, '/hop/review/view', arguments: appId);
    }
  }

  /// Build one card with lookups (user + interests) and *faculty approver* check (must be me).
  Widget _buildCardWithLookups(
      DocumentSnapshot<Map<String, dynamic>> d, {
        required String myUid,
      }) {
    return FutureBuilder<
        ({
        Map<String, dynamic>? userData,
        List<String> interestTitles,
        bool facultyApprovedByMe,
        })>(
      future: _fetchExtrasForApp(d, myUid),
      builder: (context, snap) {
        final extras = snap.data;

        // Skeleton shell while loading
        final appShell = PeerApplication.fromDoc(
          d,
          userData: extras?.userData,
          interestTitlesOverride: extras?.interestTitles ?? const <String>[],
        );

        if (snap.connectionState == ConnectionState.waiting) {
          return Opacity(
            opacity: .6,
            child: _ApplicationCard(
              app: appShell.copyWith(name: appShell.name == '—' ? 'Loading...' : appShell.name),
              onView: () {},
            ),
          );
        }

        // Gate: show only if faculties/{facultyId}.approverUid == myUid
        if (extras == null || !extras.facultyApprovedByMe) {
          return const SizedBox.shrink();
        }

        final app = PeerApplication.fromDoc(
          d,
          userData: extras.userData,
          interestTitlesOverride: extras.interestTitles,
        );

        // Stage filter
        if (_stage == 'Approved' && app.status != AppStatus.approved) {
          return const SizedBox.shrink();
        }
        if (_stage == 'Rejected' && app.status != AppStatus.rejected) {
          return const SizedBox.shrink();
        }
        if (_stage == 'Pending' && app.status != AppStatus.pending) {
          return const SizedBox.shrink();
        }

        return _ApplicationCard(
          app: app,
          onView: () => _openDetail(app.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderBar(
                onBack: () => Navigator.maybePop(context),
                onLogout: _logout,
              ),
              const SizedBox(height: 12),

              // Title
              Text('HOP Review Applications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Review peer tutor applications (filtered by your faculty approvals)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),

              const SizedBox(height: 14),

              _StageFilterBar(selected: _stage, onSelect: (s) => setState(() => _stage = s)),
              const SizedBox(height: 16),

              // Live list from Firestore (by role). We filter by faculty approver == me (client-side).
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _appsCol
                    .where('requestedRole', isEqualTo: _currentRoleStr)
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
                  final docs = snap.data?.docs ?? const [];

                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Text('No applications found.'),
                    );
                  }

                  // Sort locally by submittedAt DESC
                  docs.sort((a, b) {
                    final at = (a.data()['submittedAt'] is Timestamp)
                        ? (a.data()['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch
                        : 0;
                    final bt = (b.data()['submittedAt'] is Timestamp)
                        ? (b.data()['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch
                        : 0;
                    return bt.compareTo(at);
                  });

                  final cards = docs
                      .map((d) => _buildCardWithLookups(d, myUid: user.uid))
                      .toList();

                  return Column(
                    children: [
                      for (final c in cards) ...[
                        c,
                        const SizedBox(height: 12),
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
}

/* -------------------------------- Widgets -------------------------------- */

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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HOP', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),

        const SizedBox(width: 8),
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

class _StageFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _StageFilterBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label) {
      final sel = selected == label;
      return InkWell(
        onTap: () => onSelect(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: sel ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('All'),
        chip('Pending'),
        chip('Approved'),
        chip('Rejected'),
      ],
    );
  }
}

/* ---------------------------- Application Card ---------------------------- */

class _ApplicationCard extends StatelessWidget {
  final PeerApplication app;
  final VoidCallback onView;

  const _ApplicationCard({required this.app, required this.onView});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // Visual mapping and HOP-specific notes
    late Color borderColor;
    late Widget footerNote;
    Widget? statusChip;

    switch (app.status) {
      case AppStatus.pending:
        borderColor = const Color(0xFFE6C45E);
        final awaitingHop = !app.hopApproved;
        footerNote = Text(
          awaitingHop ? 'Awaiting HOP Review' : 'Forwarded to Admin',
          style: t.labelSmall?.copyWith(
            color: awaitingHop ? Colors.orange.shade700 : const Color(0xFF1565C0),
            fontWeight: FontWeight.w600,
          ),
        );
        if (app.hopApproved) {
          statusChip = _StatusChip(
            label: 'HOP Approved',
            bg: const Color(0xFFF6E7A6),
            fg: const Color(0xFF4A3C00),
          );
        }
        break;
      case AppStatus.approved:
        borderColor = const Color(0xFF62A86E);
        footerNote = Text('Approved by Admin',
            style: t.labelSmall?.copyWith(
                color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600));
        statusChip =
            _StatusChip(label: 'Approved', bg: const Color(0xFFE3F2FD), fg: const Color(0xFF1565C0));
        break;
      case AppStatus.rejected:
        borderColor = const Color(0xFFE53935);
        footerNote = Text('Rejected',
            style: t.labelSmall?.copyWith(color: Colors.red, fontWeight: FontWeight.w600));
        statusChip =
            _StatusChip(label: 'Rejected', bg: const Color(0xFFF8D7DA), fg: const Color(0xFFB71C1C));
        break;
    }

    final studentIdText = app.studentId.isNotEmpty ? app.studentId : 'Student ID not set';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 10,
              offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final tight = c.maxWidth < 360;
                        final name = Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        );
                        final appIdText = Text(app.appCode, style: t.labelSmall);

                        if (tight) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: name),
                                  const SizedBox(width: 8),
                                  Flexible(child: appIdText),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (statusChip != null)
                                Align(alignment: Alignment.centerLeft, child: statusChip),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: name),
                            const SizedBox(width: 8),
                            Flexible(child: appIdText),
                            const SizedBox(width: 8),
                            if (statusChip != null) statusChip!,
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 4),
                    Text(studentIdText, style: t.bodySmall),
                    Text(
                      app.interests.isEmpty
                          ? 'Interest: —'
                          : 'Interest: ${app.interests.join(', ')}',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 10),

                    LayoutBuilder(
                      builder: (context, c) {
                        final tight = c.maxWidth < 320;
                        final viewBtn = FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: onView,
                          child: const Text('View', style: TextStyle(color: Colors.white)),
                        );

                        if (tight) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(alignment: Alignment.centerLeft, child: footerNote),
                              const SizedBox(height: 8),
                              Align(alignment: Alignment.centerRight, child: viewBtn),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: footerNote),
                            viewBtn,
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
  final Color bg;
  final Color fg;
  const _StatusChip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
