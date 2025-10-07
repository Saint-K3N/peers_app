// lib/hop_review_application_detail_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

class HopReviewApplicationDetailPage extends StatefulWidget {
  final String appId;
  const HopReviewApplicationDetailPage({super.key, required this.appId});

  @override
  State<HopReviewApplicationDetailPage> createState() =>
      _HopReviewApplicationDetailPageState();
}

class _HopReviewApplicationDetailPageState
    extends State<HopReviewApplicationDetailPage> {
  bool _working = false;

  CollectionReference<Map<String, dynamic>> get _appsCol =>
      FirebaseFirestore.instance.collection('peer_applications');
  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');
  CollectionReference<Map<String, dynamic>> get _interestsCol =>
      FirebaseFirestore.instance.collection('interests');

  /* ----------------------------- Helpers ----------------------------- */

  Future<Map<String, dynamic>?> _getUser(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _usersCol.doc(uid).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _getInterestTitlesByIds(List<dynamic>? ids) async {
    if (ids == null || ids.isEmpty) return const <String>[];
    final idStrs = ids.map((e) => e.toString()).toList();

    final chunks = <List<String>>[];
    for (var i = 0; i < idStrs.length; i += 10) {
      chunks.add(idStrs.sublist(i, (i + 10 > idStrs.length) ? idStrs.length : i + 10));
    }

    final Map<String, String> idToTitle = {};
    for (final chunk in chunks) {
      final q = await _interestsCol.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in q.docs) {
        final title = (d.data()['title'] ?? '').toString().trim();
        if (title.isNotEmpty) idToTitle[d.id] = title;
      }
    }

    final titles = <String>[];
    for (final id in idStrs) {
      final t = idToTitle[id];
      if (t != null && t.isNotEmpty) titles.add(t);
    }
    return titles;
  }

  String _readName(Map<String, dynamic>? u) {
    String pick(Map<String, dynamic>? m, List<String> keys) {
      if (m == null) return '';
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final direct = pick(u, ['fullName','full_name','name','displayName','display_name']);
    if (direct.isNotEmpty) return direct;

    final profile = (u?['profile'] is Map) ? (u?['profile'] as Map).cast<String, dynamic>() : null;
    final profName = pick(profile, ['fullName','full_name','name','displayName','display_name']);
    if (profName.isNotEmpty) return profName;

    final first = pick(u, ['firstName','first_name','givenName','given_name']);
    final last  = pick(u, ['lastName','last_name','familyName','family_name','surname']);
    final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (combo.isNotEmpty) return combo;

    final pFirst = pick(profile, ['firstName','first_name','givenName','given_name']);
    final pLast  = pick(profile, ['lastName','last_name','familyName','family_name','surname']);
    final pCombo = [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
    return pCombo;
  }

  String _readStudentId(Map<String, dynamic>? u, Map<String, dynamic> app) {
    String pick(Map<String, dynamic>? m, List<String> keys) {
      if (m == null) return '';
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final direct = pick(u, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (direct.isNotEmpty) return direct;

    final profile = (u?['profile'] is Map) ? (u?['profile'] as Map).cast<String, dynamic>() : null;
    final prof = pick(profile, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (prof.isNotEmpty) return prof;

    final fromApp = pick(app, ['studentId','studentID','student_id','sid']);
    return fromApp;
  }

  String _statusText(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'hop approve':
        return 'HOP Approve';
      case 'hop rejected':
        return 'HOP Rejected';
      default:
        return 'Pending';
    }
  }

  (Color border, Color badgeBg, Color badgeFg) _statusColors(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return (const Color(0xFF81C784), const Color(0xFF2E7D32), Colors.white);
      case 'rejected':
      case 'hop rejected':
        return (const Color(0xFFE57373), const Color(0xFFD32F2F), Colors.white);
      case 'hop approve':
        return (const Color(0xFF64B5F6), const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      default:
        return (const Color(0xFFE7C86D), const Color(0xFFEBD79E), const Color(0xFF5C4A00));
    }
  }

  Future<void> _openFileUrl(String? url) async {
    if (url == null || url.isEmpty) return;
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

      if (!opened && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the file. Link copied:\n$url')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the file. Link copied:\n$url')),
      );
    }
  }

  /* ----------------------- HOP Approve / Reject ----------------------- */

  Future<void> _hopApprove(String appId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'hop';
    setState(() => _working = true);
    try {
      await _appsCol.doc(appId).update({
        'hopApproved': true,
        'hopDecisionAt': FieldValue.serverTimestamp(),
        'hopDecisionBy': uid,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as HOP Approve. Forwarded to Admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _hopReject(String appId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'hop';
    setState(() => _working = true);
    try {
      await _appsCol.doc(appId).update({
        'status': 'HOP Rejected',
        'hopApproved': false,
        'hopDecisionAt': FieldValue.serverTimestamp(),
        'hopDecisionBy': uid,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as HOP Rejected.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /* --------------------------------- UI --------------------------------- */

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _appsCol.doc(widget.appId).snapshots(),
          builder: (context, appSnap) {
            if (appSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!appSnap.hasData || !appSnap.data!.exists) {
              return _ScaffoldWithHeader(
                title: 'HOP Review',
                child: const Center(child: Text('Application not found')),
              );
            }

            final app = appSnap.data!.data()!;
            final userId = (app['userId'] ?? '').toString();
            final requestedRole = (app['requestedRole'] ?? 'tutor').toString().toLowerCase();
            final isTutor = requestedRole == 'tutor';
            final hopApproved = (app['hopApproved'] ?? false) == true;

            final dynamicIds = (app['interestsIds'] is List)
                ? (app['interestsIds'] as List)
                : ((app['interests'] is List)
                ? (app['interests'] as List)
                .map((e) => (e is Map && e['id'] != null) ? e['id'].toString() : null)
                .where((x) => x != null)
                .toList()
                : const <dynamic>[]);

            return FutureBuilder(
              future: Future.wait([
                _getUser(userId),
                _getInterestTitlesByIds(dynamicIds),
              ]),
              builder: (context, futureSnap) {
                if (futureSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final user = (futureSnap.data is List && (futureSnap.data as List).isNotEmpty)
                    ? (futureSnap.data as List)[0] as Map<String, dynamic>?
                    : null;
                final interestTitles = (futureSnap.data is List && (futureSnap.data as List).length > 1)
                    ? ((futureSnap.data as List)[1] as List<String>)
                    : const <String>[];

                final name = _readName(user);
                final studentId = _readStudentId(user, app);
                final email = (user?['email'] ?? user?['emailAddress'] ?? '').toString();
                final appCode = (app['appCode'] ?? '').toString().trim().isEmpty
                    ? 'APP-${isTutor ? 'PT' : 'PC'}-${widget.appId.substring(0, widget.appId.length >= 6 ? 6 : widget.appId.length).toUpperCase()}'
                    : (app['appCode'] as String);
                final statusRaw = (app['status'] ?? 'pending').toString();
                final status = _statusText(statusRaw);
                final (borderClr, badgeBg, badgeFg) = _statusColors(statusRaw);
                final motivation = (app['motivation'] ?? '').toString();

                final fileName = (app['letterFileName'] ?? app['fileName'] ?? '').toString();
                final fileUrl =
                (app['letterFileUrl'] ?? app['fileUrl'] ?? app['letterUrl'] ?? '').toString();

                // NEW: Only allow actions when the application is currently pending
                final bool isPending = statusRaw.toLowerCase().trim() == 'pending';

                return _ScaffoldWithHeader(
                  title: 'HOP Review • ${isTutor ? "Peer Tutor" : "Peer Tutor"}',
                  onBack: () => Navigator.maybePop(context),
                  onLogout: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: borderClr, width: 2),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.06),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name.isNotEmpty ? name : 'Unknown',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: badgeFg.withOpacity(.25)),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(color: badgeFg, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(appCode, style: t.labelSmall),
                                    if (studentId.isNotEmpty) Text(studentId, style: t.bodySmall),
                                    if (email.isNotEmpty) Text(email, style: t.bodySmall),
                                    if (statusRaw.toLowerCase() != 'hop rejected' && hopApproved)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: _HopChip(),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Interests
                          _Section(
                            title: isTutor ? 'Academic Interest' : 'Counseling Topics',
                            child: interestTitles.isEmpty
                                ? Text('—', style: t.bodySmall)
                                : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: interestTitles
                                  .map((e) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2FF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFCEDCFB)),
                                ),
                                child: Text(e, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Motivation (read-only)
                          _Section(
                            title: 'Motivation to be ${isTutor ? "Tutor" : "Counsellor"}',
                            child: TextField(
                              controller: TextEditingController(text: motivation),
                              readOnly: true,
                              maxLines: 3,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                suffixIcon: const Icon(Icons.visibility_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Recommendation Letter
                          _Section(
                            title: 'Recommendation Letter by HOP',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _openFileUrl(fileUrl),
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
                                        (fileName.isNotEmpty
                                            ? fileName
                                            : (fileUrl.isNotEmpty ? 'Open file' : '—')),
                                        style: t.bodyMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.open_in_new, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // HOP Decision — SHOW BUTTONS ONLY WHEN status == pending
                          if (isPending)
                            _Section(
                              title: 'HOP Decision',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _working ? null : () => _hopApprove(widget.appId),
                                      child: const Text('Approve', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _working ? null : () => _hopReject(widget.appId),
                                      child: const Text('Reject', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // (If not pending, nothing is shown here—buttons are hidden)
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/* ------------------------------- Reusable UI ------------------------------- */

class _ScaffoldWithHeader extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onLogout;

  const _ScaffoldWithHeader({
    required this.title,
    required this.child,
    this.onBack,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _IconSquare(onTap: onBack ?? () => Navigator.maybePop(context), icon: Icons.arrow_back),
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
                    style: t.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HOP', style: t.titleMedium),
                    Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _IconSquare(onTap: onLogout ?? () {}, icon: Icons.logout),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

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
              Expanded(
                child: Text(title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
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

class _HopChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6E7A6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A3C00).withOpacity(.25)),
      ),
      child: const Text(
        'HOP Approved',
        style: TextStyle(color: Color(0xFF4A3C00), fontWeight: FontWeight.w700),
      ),
    );
  }
}
