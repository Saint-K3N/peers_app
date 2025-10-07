// lib/admin_review_reports_page.dart
import 'package:flutter/material.dart';

class AdminReviewReportsPage extends StatefulWidget {
  const AdminReviewReportsPage({super.key});

  @override
  State<AdminReviewReportsPage> createState() => _AdminReviewReportsPageState();
}

/* ------------------------------- Mock Model ------------------------------- */

class ReportItem {
  String reportedUser;
  String reportedBy;
  DateTime date;
  String reason;
  String reportId;
  bool temporarilyDisabled;

  ReportItem({
    required this.reportedUser,
    required this.reportedBy,
    required this.date,
    required this.reason,
    required this.reportId,
    this.temporarilyDisabled = false,
  });
}

/* ---------------------------------- Page ---------------------------------- */

class _AdminReviewReportsPageState extends State<AdminReviewReportsPage> {
  final List<ReportItem> _reports = [
    ReportItem(
      reportedUser: 'Justin',
      reportedBy: 'Ken',
      date: DateTime(2025, 6, 4),
      reason: 'Constant cancelling appointments',
      reportId: '11111',
      temporarilyDisabled: true,
    ),
  ];

  String _prettyDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    String ordinal(int n) {
      if (n >= 11 && n <= 13) return '${n}th';
      switch (n % 10) {
        case 1: return '${n}st';
        case 2: return '${n}nd';
        case 3: return '${n}rd';
        default: return '${n}th';
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
                onLogout: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
              ),
              const SizedBox(height: 16),

              // Title
              Text('Review Report', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Manage reports', style: t.bodySmall),
              const SizedBox(height: 14),

              // Total reports stat
              _StatBox(count: _reports.length, label: 'Total Reports'),
              const SizedBox(height: 16),

              // List
              for (final r in _reports) ...[
                _ReportCard(
                  item: r,
                  prettyDate: _prettyDate(r.date),
                  onToggleDisable: () => setState(() => r.temporarilyDisabled = !r.temporarilyDisabled),
                ),
                const SizedBox(height: 14),
              ],
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
          child: Text('PEERS', style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),

        // Flexible title column (prevents right overflow)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  const _StatBox({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 128,
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

class _ReportCard extends StatelessWidget {
  final ReportItem item;
  final String prettyDate;
  final VoidCallback onToggleDisable;

  const _ReportCard({
    required this.item,
    required this.prettyDate,
    required this.onToggleDisable,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final border = Border.all(color: Colors.black12);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: border,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: username + red pill on the right (wrap-safe)
          LayoutBuilder(
            builder: (context, c) {
              final tight = c.maxWidth < 350;
              final name = Text(item.reportedUser, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));

              final pill = _DisablePill(
                enabled: item.temporarilyDisabled,
                onTap: onToggleDisable,
              );

              if (tight) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: pill),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 8),
                  FittedBox(child: pill),
                ],
              );
            },
          ),

          const SizedBox(height: 8),
          Text('Reported by: ${item.reportedBy}', style: t.bodySmall),
          Text('Date Reported: $prettyDate', style: t.bodySmall),
          const SizedBox(height: 6),
          Text('Reason: ${item.reason}', style: t.bodySmall),
          const SizedBox(height: 10),

          // Report ID on the right (no overflow)
          Align(
            alignment: Alignment.centerRight,
            child: Text('Report ID: ${item.reportId}', style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _DisablePill extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _DisablePill({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = 'Temporary Disable\nReported User Account';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // two-line label
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.1),
            ),
            const SizedBox(width: 8),
            // small black circle with check when enabled, outline otherwise
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: enabled ? Colors.black : Colors.transparent,
                border: Border.all(color: Colors.black, width: 2),
                shape: BoxShape.circle,
              ),
              child: enabled
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
