// lib/school_counsellor_application_detail_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/email_notification_service.dart';

/* ------------------------------- Page ------------------------------- */

class SchoolCounsellorApplicationDetailPage extends StatefulWidget {
  final String appId;
  const SchoolCounsellorApplicationDetailPage({super.key, required this.appId});

  @override
  State<SchoolCounsellorApplicationDetailPage> createState() =>
      _SchoolCounsellorApplicationDetailPageState();
}

class _SchoolCounsellorApplicationDetailPageState
    extends State<SchoolCounsellorApplicationDetailPage> {
  bool _working = false;

  final _appsCol = FirebaseFirestore.instance.collection('peer_applications');
  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _interestsCol = FirebaseFirestore.instance.collection('interests');

  /* ----------------------------- Helpers ----------------------------- */

  bool _isPeerCounsellorApp(Map<String, dynamic> app) {
    final role = ((app['requestedRole'] ?? app['role'] ?? '') as String).toLowerCase();
    return role == 'peer_counsellor';
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }

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

  String _pick(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _readName(Map<String, dynamic>? u) {
    final direct = _pick(u, ['fullName','full_name','name','displayName','display_name']);
    if (direct.isNotEmpty) return direct;
    final profile = (u?['profile'] is Map) ? (u?['profile'] as Map).cast<String, dynamic>() : null;
    final profName = _pick(profile, ['fullName','full_name','name','displayName','display_name']);
    if (profName.isNotEmpty) return profName;
    final first = _pick(u, ['firstName','first_name','givenName','given_name']);
    final last  = _pick(u, ['lastName','last_name','familyName','family_name','surname']);
    final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (combo.isNotEmpty) return combo;
    final pFirst = _pick(profile, ['firstName','first_name','givenName','given_name']);
    final pLast  = _pick(profile, ['lastName','last_name','familyName','family_name','surname']);
    return [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
  }

  String _readStudentId(Map<String, dynamic>? u, Map<String, dynamic> app) {
    String sid = _pick(u, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (sid.isNotEmpty) return sid;
    final profile = (u?['profile'] is Map) ? (u?['profile'] as Map).cast<String, dynamic>() : null;
    sid = _pick(profile, ['studentId','studentID','student_id','sid','matric','matricNo','matric_no']);
    if (sid.isNotEmpty) return sid;
    return _pick(app, ['studentId','studentID','student_id','sid']);
  }

  Future<void> _openFileUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file link.')),
      );
    }
  }

  /* --------- Approve / Reject guarded to peer_counsellor only ---------- */

  Future<void> _scApprove() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'school_counsellor';
    setState(() => _working = true);
    try {
      final ref = _appsCol.doc(widget.appId);
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final data = snap.data() as Map<String, dynamic>?;
        final role = ((data?['requestedRole'] ?? data?['role'] ?? '') as String).toLowerCase();
        if (role != 'peer_counsellor') {
          throw 'This is not a peer_counsellor application.';
        }
        txn.update(ref, {
          'schoolCounsellorApproved': true,
          'schoolCounsellorDecisionAt': FieldValue.serverTimestamp(),
          'schoolCounsellorDecisionBy': uid,
        });
      });

      // Send email notification to student about school counsellor approval
      try {
        final appDoc = await _appsCol.doc(widget.appId).get();
        final appData = appDoc.data();

        if (appData != null) {
          final studentId = appData['userId'] ?? '';
          final roleAppliedFor = appData['requestedRole'] ?? 'Peer Counsellor';

          final studentDoc = await _usersCol.doc(studentId).get();
          final studentData = studentDoc.data();

          if (studentData != null) {
            final studentEmail = studentData['email'] ?? '';
            final studentName = studentData['fullName'] ?? studentData['name'] ?? 'Student';

            if (studentEmail.isNotEmpty) {
              await EmailNotificationService.sendSchoolCounsellorApprovalToStudent(
                studentEmail: studentEmail,
                studentName: studentName,
                roleAppliedFor: roleAppliedFor,
              );
            }
          }
        }
      } catch (emailError) {
        debugPrint('Failed to send approval email: $emailError');
        // Don't fail the approval if email fails
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as approved by School Counsellor.')),
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

  Future<void> _scReject() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'school_counsellor';
    setState(() => _working = true);
    try {
      final ref = _appsCol.doc(widget.appId);
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final data = snap.data() as Map<String, dynamic>?;
        final role = ((data?['requestedRole'] ?? data?['role'] ?? '') as String).toLowerCase();
        if (role != 'peer_counsellor') {
          throw 'This is not a peer_counsellor application.';
        }
        txn.update(ref, {
          'schoolCounsellorApproved': false,
          'schoolCounsellorDecisionAt': FieldValue.serverTimestamp(),
          'schoolCounsellorDecisionBy': uid,
        });
      });

      // Send email notification to student about school counsellor rejection
      try {
        final appDoc = await _appsCol.doc(widget.appId).get();
        final appData = appDoc.data();

        if (appData != null) {
          final studentId = appData['userId'] ?? '';
          final roleAppliedFor = appData['requestedRole'] ?? 'Peer Counsellor';

          final studentDoc = await _usersCol.doc(studentId).get();
          final studentData = studentDoc.data();

          if (studentData != null) {
            final studentEmail = studentData['email'] ?? '';
            final studentName = studentData['fullName'] ?? studentData['name'] ?? 'Student';

            if (studentEmail.isNotEmpty) {
              await EmailNotificationService.sendSchoolCounsellorRejectionToStudent(
                studentEmail: studentEmail,
                studentName: studentName,
                roleAppliedFor: roleAppliedFor,
              );
            }
          }
        }
      } catch (emailError) {
        debugPrint('Failed to send rejection email: $emailError');
        // Don't fail the rejection if email fails
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as rejected by School Counsellor.')),
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
                title: 'Peer Counsellor Review',
                onLogout: _logout,
                child: const Center(child: Text('Application not found')),
              );
            }

            final app = appSnap.data!.data()!;

            // 🔒 Show ONLY peer_counsellor applications
            if (!_isPeerCounsellorApp(app)) {
              return _ScaffoldWithHeader(
                title: 'School Counsellor Review',
                onLogout: _logout,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'This application is not for Peer Counsellor.',
                          style: t.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Only Peer Counsellor applications are visible on this page.',
                          style: t.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.maybePop(context),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final userId = (app['userId'] ?? '').toString();

            final dynamicIds = (app['interestsIds'] is List)
                ? (app['interestsIds'] as List)
                : ((app['interests'] is List)
                ? (app['interests'] as List)
                .map((e) => (e is Map && e['id'] != null) ? e['id'].toString() : null)
                .where((x) => x != null)
                .toList()
                : const <dynamic>[]);

            return FutureBuilder(
              future: Future.wait([_getUser(userId), _getInterestTitlesByIds(dynamicIds)]),
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

                final motivation = (app['motivation'] ?? '').toString();
                final fileName = (app['letterFileName'] ?? app['fileName'] ?? '').toString();
                final fileUrl = (app['letterFileUrl'] ?? app['fileUrl'] ?? app['letterUrl'] ?? '').toString();

                final statusRaw = (app['status'] ?? 'pending').toString().toLowerCase();
                String statusLabel;
                Color border;
                if (statusRaw == 'approved') {
                  statusLabel = 'Approved';
                  border = const Color(0xFF62A86E);
                } else if (statusRaw == 'rejected' || statusRaw == 'hop rejected') {
                  statusLabel = statusRaw == 'hop rejected' ? 'HOP Rejected' : 'Rejected';
                  border = const Color(0xFFE53935);
                } else if (statusRaw == 'hop approve') {
                  statusLabel = 'HOP Approved';
                  border = const Color(0xFF64B5F6);
                } else {
                  statusLabel = 'Pending';
                  border = const Color(0xFFE6C45E);
                }

                final scApproved = (app['schoolCounsellorApproved'] ?? null);

                // Check if decision has been made
                final isDecided = scApproved != null;

                return _ScaffoldWithHeader(
                  title: 'School Counsellor Review',
                  onLogout: _logout,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: border, width: 2),
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
                          // Header row with status
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
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: border),
                                          ),
                                          child: Text(statusLabel,
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (studentId.isNotEmpty) Text(studentId, style: t.bodySmall),
                                    if (email.isNotEmpty) Text(email, style: t.bodySmall),
                                    if (scApproved != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          scApproved == true
                                              ? 'School Counsellor: Approved'
                                              : 'School Counsellor: Rejected',
                                          style: t.labelMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: scApproved == true ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Interests
                          _Section(
                            title: 'Counseling Topics',
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
                            title: 'Motivation',
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
                            title: 'Recommendation Letter',
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
                          const SizedBox(height: 16),

                          // Actions
                          Row(
                            children: [
                              Expanded(
                                child: Opacity(
                                  opacity: isDecided ? 0.4 : 1.0,
                                  child: ElevatedButton(
                                    onPressed: (_working || isDecided) ? null : _scApprove,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF43A047),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Opacity(
                                  opacity: isDecided ? 0.4 : 1.0,
                                  child: ElevatedButton(
                                    onPressed: (_working || isDecided) ? null : _scReject,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFB71C1C),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: const Text('Reject'),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                    Text('School Counsellor', style: t.titleMedium),
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

  const _Section({required this.title, required this.child});

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
          Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
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