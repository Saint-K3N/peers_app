// lib/student_review_applications_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// detail page expects: StudentReviewApplicationDetailPage({required String appId})
import 'student_review_application_detail_page.dart';

class StudentReviewApplicationsPage extends StatefulWidget {
  const StudentReviewApplicationsPage({super.key});

  @override
  State<StudentReviewApplicationsPage> createState() =>
      _StudentReviewApplicationsPageState();
}

class _StudentReviewApplicationsPageState
    extends State<StudentReviewApplicationsPage> {
  int _tab = 0; // 0 = Peer Tutor, 1 = Peer Counsellor

  String get _roleStr => _tab == 0 ? 'peer_tutor' : 'peer_counsellor';

  /// Pretty date like "3rd June 2025"
  String _prettyDate(DateTime d) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    String ordinal(int n) {
      if (n >= 11 && n <= 13) return '${n}th';
      switch (n % 10) {
        case 1:
          return '${n}st';
        case 2:
          return '${n}nd';
        case 3:
          return '${n}rd';
        default:
          return '${n}th';
      }
    }

    return '${ordinal(d.day)} ${months[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HeaderStudent(),
              const SizedBox(height: 16),

              Text('Review Applications',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                _tab == 0
                    ? 'Your Peer Tutor applications with HOP + Admin status'
                    : 'Your Peer Counsellor applications with School Counsellor + Admin status',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),

              _SegmentBar(
                left: 'Peer Tutor',
                right: 'Peer Counsellor',
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 12),

              _ProcessStrip(isTutor: _tab == 0),
              const SizedBox(height: 12),

              if (uid.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Text('Please sign in to view your applications.'),
                )
              else
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('peer_applications')
                      .where('userId', isEqualTo: uid)
                      .where('requestedRole', isEqualTo: _roleStr)
                  // NOTE: no orderBy here → no composite index required
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
                    final rawDocs = snap.data?.docs ?? const [];

                    if (rawDocs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          _tab == 0
                              ? 'You have no Peer Tutor applications.'
                              : 'You have no Peer Counsellor applications.',
                        ),
                      );
                    }

                    // Sort locally by submittedAt DESC
                    final docs = [...rawDocs]..sort((a, b) {
                      final at = (a.data()['submittedAt'] is Timestamp)
                          ? (a.data()['submittedAt'] as Timestamp)
                          .toDate()
                          .millisecondsSinceEpoch
                          : 0;
                      final bt = (b.data()['submittedAt'] is Timestamp)
                          ? (b.data()['submittedAt'] as Timestamp)
                          .toDate()
                          .millisecondsSinceEpoch
                          : 0;
                      return bt.compareTo(at);
                    });

                    return Column(
                      children: [
                        for (final d in docs) ...[
                          _buildCardFromDoc(
                            context: context,
                            doc: d,
                            isTutor: _tab == 0,
                            prettyDate: _prettyDate,
                          ),
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

  /// Build each application card using actual Firestore doc fields
  Widget _buildCardFromDoc({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required bool isTutor,
    required String Function(DateTime) prettyDate,
  }) {
    final data = doc.data();

    // Admin status (primary badge)
    final statusRaw = (data['status'] ?? 'pending').toString().toLowerCase();
    final AppStatus adminStatus = switch (statusRaw) {
      'approved' => AppStatus.approved,
      'rejected' => AppStatus.rejected,
      _ => AppStatus.pending,
    };

    // Stage approvals
    final hopApproved = (data['hopApproved'] ?? false) == true;
    final schoolApproved = (data['schoolCounsellorApproved'] ?? false) == true;

    // Submitted date
    DateTime submittedAt = DateTime.fromMillisecondsSinceEpoch(0);
    final ts = data['submittedAt'];
    if (ts is Timestamp) submittedAt = ts.toDate();

    // App code (fallback if missing)
    final appId = doc.id;
    final codeRaw = (data['appCode'] ?? '').toString().trim();
    final code = codeRaw.isEmpty
        ? 'APP-${isTutor ? 'PT' : 'PC'}-${appId.substring(0, appId.length >= 6 ? 6 : appId.length).toUpperCase()}'
        : codeRaw;

    // Title
    final title =
    isTutor ? 'Peer Tutor Application' : 'Peer Counsellor Application';

    // Footer: combine stage approvals + admin status text
    String footer;
    if (adminStatus == AppStatus.pending) {
      if (isTutor) {
        footer = hopApproved
            ? 'HOP Approved • Pending Admin Approval'
            : 'Pending';
      } else {
        footer = schoolApproved
            ? 'School Counsellor Approved • Pending Admin Approval'
            : 'Pending';
      }
    } else if (adminStatus == AppStatus.approved) {
      footer = 'Approved';
    } else {
      footer = 'Rejected by Admin';
    }

    return _ApplicationCard(
      title: title,
      dateApplied:
      submittedAt.millisecondsSinceEpoch == 0 ? '—' : prettyDate(submittedAt),
      applicationId: code,
      status: adminStatus,
      footerText: footer,
      onView: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentReviewApplicationDetailPage(appId: doc.id),
          ),
        );
      },
    );
  }
}


/* ------------------------------- Header ------------------------------- */

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
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }
}


/* ----------------------------- Segment Bar ---------------------------- */

class _SegmentBar extends StatelessWidget {
  final String left, right;
  final int index;
  final ValueChanged<int> onChanged;

  const _SegmentBar({
    required this.left,
    required this.right,
    required this.index,
    required this.onChanged,
  });

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
              child: Text(
                left,
                style: TextStyle(
                  color: index == 0 ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
              child: Text(
                right,
                style: TextStyle(
                  color: index == 1 ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* --------------------------- Process Strip ---------------------------- */

class _ProcessStrip extends StatelessWidget {
  final bool isTutor;
  const _ProcessStrip({this.isTutor = true});

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
        child: Icon(Icons.arrow_forward));

    // Tutor: HOP review; Counsellor: School Counsellor review
    final reviewer = isTutor ? 'HOP Review' : 'School Counsellor Review';

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
            step(Icons.rate_review_outlined, reviewer),
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

/* --------------------------- Application Card -------------------------- */

enum AppStatus { pending, rejected, approved }

class _ApplicationCard extends StatelessWidget {
  final String title;
  final String dateApplied;
  final String applicationId;
  final AppStatus status;
  final String footerText;
  final VoidCallback onView;

  const _ApplicationCard({
    required this.title,
    required this.dateApplied,
    required this.applicationId,
    required this.status,
    required this.footerText,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final (border, badgeBg, badgeFg, footerFg) = switch (status) {
      AppStatus.pending => (
      const Color(0xFFE7C86D),
      const Color(0xFFEBD79E),
      const Color(0xFF5C4A00),
      const Color(0xFFE39200),
      ),
      AppStatus.rejected => (
      const Color(0xFFE57373),
      const Color(0xFFD32F2F),
      Colors.white,
      const Color(0xFFD32F2F),
      ),
      AppStatus.approved => (
      const Color(0xFF81C784),
      const Color(0xFF2E7D32),
      Colors.white,
      const Color(0xFF2E7D32),
      ),
    };

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeFg.withOpacity(.25)),
      ),
      child: Text(
        switch (status) {
          AppStatus.pending => 'Pending',
          AppStatus.rejected => 'Rejected',
          AppStatus.approved => 'Approved',
        },
        style: TextStyle(color: badgeFg, fontWeight: FontWeight.w700),
      ),
    );

    final viewBtn = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onView,
      child: const Text('View',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(fit: BoxFit.scaleDown, child: badge),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Date Applied: $dateApplied', style: t.bodySmall),
          Text('Application ID: $applicationId', style: t.bodySmall),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final tight = c.maxWidth < 330;
              final footer = Text(
                footerText,
                style: t.bodySmall?.copyWith(color: footerFg),
              );
              if (tight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: footer),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: viewBtn),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: footer),
                  viewBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
