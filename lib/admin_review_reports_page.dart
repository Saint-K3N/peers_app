// lib/admin_review_reports_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminReviewReportsPage extends StatefulWidget {
  const AdminReviewReportsPage({super.key});

  @override
  State<AdminReviewReportsPage> createState() => _AdminReviewReportsPageState();
}

class _AdminReviewReportsPageState extends State<AdminReviewReportsPage> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // To format Date/Time into readable string (12th October 2021)
  String _prettyDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderBar(
                onBack: () => Navigator.maybePop(context),
                onLogout: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (_) => false),
              ),
              const SizedBox(height: 16),

              // Title
              Text('Review Reports',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Manage user reports', style: t.bodySmall),
              const SizedBox(height: 14),

              // Search Bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: Colors.black54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search by reported user name...',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Stats Row with Total + Pending
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('reports')
                    .snapshots(),
                builder: (context, snap) {
                  final allReports = snap.data?.docs ?? [];
                  final pendingReports = allReports
                      .where((d) =>
                  (d.data()['status'] ?? 'pending').toString() ==
                      'pending')
                      .length;
                  final totalReports = allReports.length;

                  return Row(
                    children: [
                      _StatBox(
                        count: totalReports,
                        label: 'Total Reports',
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _StatBox(
                        count: pendingReports,
                        label: 'Pending Reports',
                        color: Colors.orange,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // List of reports (live with search filter)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: CircularProgressIndicator()));
                  }
                  if (snap.hasError) {
                    return Text('Error: ${snap.error}',
                        style: t.bodyMedium?.copyWith(color: Colors.red));
                  }

                  var reports = snap.data?.docs ?? [];

                  // Apply search filter
                  if (_searchQuery.isNotEmpty) {
                    reports = reports.where((report) {
                      final data = report.data();
                      final reportedName =
                      (data['reportedUserName'] ?? '').toString().toLowerCase();
                      return reportedName.contains(_searchQuery);
                    }).toList();
                  }

                  if (reports.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No reports found for "$_searchQuery"'
                              : 'No reports yet.',
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final report in reports) ...[
                        _ReportCard(
                          reportDoc: report,
                          prettyDate: _prettyDate((report.data()['createdAt']
                          as Timestamp?)
                              ?.toDate() ??
                              DateTime.now()),
                        ),
                        const SizedBox(height: 14),
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

/* --------------------------------- Header --------------------------------- */

class _HeaderBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _HeaderBar({required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onBack,
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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin', style: t.titleMedium),
            Text('Portal',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Material(
          color: Colors.transparent,
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

/* -------------------------------- Stat Box -------------------------------- */

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _StatBox({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Column(
          children: [
            Text('$count',
                style: t.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------- Report Card ------------------------------ */

class _ReportCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> reportDoc;
  final String prettyDate;

  const _ReportCard({
    required this.reportDoc,
    required this.prettyDate,
  });

  /// Toggle deactivate with email notification
  Future<void> _toggleDeactivate(BuildContext context) async {
    final data = reportDoc.data();
    final reportedUserId = (data['reportedUserId'] ?? '').toString();

    if (reportedUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user ID found')),
      );
      return;
    }

    try {
      // Get current user status
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(reportedUserId)
          .get();

      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final currentStatus = (userData['status'] ?? 'active').toString().toLowerCase();
      final userName = userData['name'] ?? userData['fullName'] ?? 'User';
      final userEmail = userData['email'] ?? '';
      final newStatus = currentStatus == 'active' ? 'inactive' : 'active';
      final actionWord = newStatus == 'inactive' ? 'Deactivate' : 'Reactivate';

      // Confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$actionWord Account?'),
          content: Text(
            'Are you sure you want to $actionWord the account for $userName?\n\n'
                '${newStatus == 'inactive'
                ? '⚠️ They will lose access and receive a deactivation email.'
                : '✅ They will regain full access to their account.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: newStatus == 'inactive' ? Colors.red : Colors.green,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Confirm $actionWord'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Update user status
      await FirebaseFirestore.instance
          .collection('users')
          .doc(reportedUserId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        if (newStatus == 'inactive') 'deactivatedAt': FieldValue.serverTimestamp(),
        if (newStatus == 'inactive') 'deactivatedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // Update report status if deactivating
      if (newStatus == 'inactive') {
        final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'system';
        await reportDoc.reference.set({
          'status': 'actioned',
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedBy': adminUid,
          'actionTaken': 'deactivated',
        }, SetOptions(merge: true));

        // ✅ NEW: Send deactivation email with report details
        if (userEmail.isNotEmpty) {
          await _sendReportDeactivationEmail(
            userEmail,
            userName,
            data['reason'] ?? 'No reason provided',
          );
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newStatus == 'inactive' ? Icons.block : Icons.check_circle,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    newStatus == 'inactive'
                        ? 'User deactivated and notification sent'
                        : 'User reactivated successfully',
                  ),
                ),
              ],
            ),
            backgroundColor: newStatus == 'inactive' ? Colors.red : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Send deactivation email for report-based action
  Future<void> _sendReportDeactivationEmail(
      String userEmail,
      String userName,
      String reportReason,
      ) async {
    try {
      await FirebaseFirestore.instance.collection('mail').add({
        'to': userEmail,
        'message': {
          'subject': 'PEERS Account Deactivated - Report Action',
          'html': '''
            <!DOCTYPE html>
            <html>
            <head>
              <style>
                body { 
                  font-family: Arial, sans-serif; 
                  line-height: 1.6; 
                  color: #333; 
                  margin: 0; 
                  padding: 0; 
                }
                .container { 
                  max-width: 600px; 
                  margin: 0 auto; 
                  background: white;
                }
                .header { 
                  background: linear-gradient(135deg, #B388FF, #7C4DFF); 
                  color: white; 
                  padding: 30px; 
                  text-align: center; 
                }
                .content { 
                  padding: 30px; 
                  background: #f9f9f9; 
                }
                .alert-box {
                  background: #f8d7da;
                  border-left: 4px solid #dc3545;
                  padding: 15px;
                  margin: 20px 0;
                }
                .info-box { 
                  background: white; 
                  border-left: 4px solid #7C4DFF; 
                  padding: 15px; 
                  margin: 20px 0; 
                }
                .footer { 
                  text-align: center; 
                  padding: 20px; 
                  color: #666; 
                  font-size: 12px; 
                }
                ul { 
                  padding-left: 20px; 
                }
                li { 
                  margin: 8px 0; 
                }
              </style>
            </head>
            <body>
              <div class="container">
                <div class="header">
                  <h1>PEERS</h1>
                </div>
                <div class="content">
                  <h2>Account Deactivated</h2>
                  <p>Dear $userName,</p>
                  
                  <div class="alert-box">
                    <strong>🚨 Important Notice</strong>
                    <p style="margin: 10px 0 0 0;">Your PEERS account has been deactivated following a report review by our administration team.</p>
                  </div>
                  
                  <div class="info-box">
                    <strong>Report Details:</strong><br>
                    Reason: $reportReason<br>
                    Account Status: <span style="color: #d32f2f;">Inactive</span>
                  </div>
                  
                  <p><strong>What this means:</strong></p>
                  <ul>
                    <li>You can no longer access the PEERS platform</li>
                    <li>All scheduled appointments have been cancelled</li>
                    <li>Your profile is no longer visible to other users</li>
                    <li>You cannot make or accept new bookings</li>
                  </ul>
                  
                  <p><strong>Appeal Process:</strong></p>
                  <p>If you would like to appeal this decision or discuss the circumstances, please contact:</p>
                  <ul>
                    <li>📧 Email: <a href="mailto:admin@gmail.com">admin@gmail.com</a></li>
                    <li>🏢 Visit: IT Services @ Level 3</li>
                  </ul>
                  
                  <p>We take all reports seriously and encourage all users to maintain respectful and appropriate conduct within the PEERS community.</p>
                  
                  <p>Best regards,<br>PEERS Admin Team</p>
                </div>
                <div class="footer">
                  <p>This is an automated message from PEERS.</p>
                  <p>Please do not reply to this email. Contact support using the details above.</p>
                </div>
              </div>
            </body>
            </html>
          ''',
        },
      });
    } catch (e) {
      // Log error but don't fail the deactivation
      debugPrint('Failed to send report deactivation email: $e');
    }
  }

  Future<void> _dismissReport(BuildContext context) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'system';
    try {
      await reportDoc.reference.set({
        'status': 'dismissed',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'actionTaken': 'dismissed',
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report dismissed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final data = reportDoc.data();

    final reportedUserName =
    (data['reportedUserName'] ?? 'Unknown').toString();
    final reportedByName = (data['reportedByName'] ?? 'Unknown').toString();
    final reason = (data['reason'] ?? 'No reason provided').toString();
    final status = (data['status'] ?? 'pending').toString();
    final reportedUserId = (data['reportedUserId'] ?? '').toString();

    final isPending = status == 'pending';
    final isDismissed = status == 'dismissed';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isPending ? Colors.orange : Colors.black12,
            width: isPending ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Name + Status badge + Report count
          Row(
            children: [
              Expanded(
                child: Text(reportedUserName,
                    style:
                    t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),

              // Report count badge
              if (reportedUserId.isNotEmpty)
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance
                      .collection('reports')
                      .where('reportedUserId', isEqualTo: reportedUserId)
                      .get(),
                  builder: (context, countSnap) {
                    final reportCount = countSnap.data?.docs.length ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: reportCount > 1
                            ? Colors.red.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: reportCount > 1 ? Colors.red : Colors.grey,
                            width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag,
                              size: 14,
                              color:
                              reportCount > 1 ? Colors.red : Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '$reportCount',
                            style: TextStyle(
                              color:
                              reportCount > 1 ? Colors.red : Colors.grey,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // Status badge
              if (!isPending)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDismissed
                        ? Colors.orange.shade100
                        : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDismissed ? Colors.orange : Colors.green,
                        width: 1),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: isDismissed ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),
          Text('Reported by: $reportedByName', style: t.bodySmall),
          Text('Date: $prettyDate', style: t.bodySmall),
          const SizedBox(height: 6),
          Text('Reason: $reason', style: t.bodySmall),
          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerRight,
            child: Text('Report ID: ${reportDoc.id}',
                style: t.bodySmall?.copyWith(color: Colors.black54)),
          ),

          if (reportedUserId.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(reportedUserId)
                  .get(),
              builder: (context, userSnap) {
                final userStatus =
                (userSnap.data?.data()?['status'] ?? 'active')
                    .toString()
                    .toLowerCase();
                final isActive = userStatus == 'active';

                return Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed:
                          isPending ? () => _dismissReport(context) : null,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Dismiss'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: FilledButton.icon(
                          onPressed: () => _toggleDeactivate(context),
                          icon: Icon(
                              isActive ? Icons.block : Icons.check_circle,
                              size: 18),
                          label: Text(isActive ? 'Deactivate' : 'Reactivate'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                            isActive ? Colors.red : Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}