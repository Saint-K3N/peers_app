// lib/hop_scheduling_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class HopSchedulingPage extends StatefulWidget {
  const HopSchedulingPage({super.key});
  @override
  State<HopSchedulingPage> createState() => _HopSchedulingPageState();
}

class _HopSchedulingPageState extends State<HopSchedulingPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _fmtDateLong(DateTime d) {
    const months = [
      'January','February','March','April','May','June','July','August',
      'September','October','November','December'
    ];
    String ord(int n) {
      if (n >= 11 && n <= 13) return 'th';
      switch (n % 10) { case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th'; }
    }
    return '${d.day}${ord(d.day)} ${months[d.month-1]} ${d.year}';
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _updateStatus(String id, String status, {String? cancellationReason}) async {
    final updateData = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonHop': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      if (cancellationReason != null) 'cancellationReason': cancellationReason,
      if (cancellationReason != null) 'cancelledBy': 'hop',
    };
    await FirebaseFirestore.instance.collection('appointments').doc(id).set(
      updateData,
      SetOptions(merge: true),
    );
  }

  // Get 20-character reason dialog
  Future<String?> _getReason(BuildContext context, String action) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action Reason'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: 'Enter reason (Max 20 characters)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, null), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty || reason.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A reason (max 20 characters) is required.')),
                );
                return;
              }
              Navigator.pop(dialogContext, reason);
            },
            child: Text('Confirm $action'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<bool> _hasOverlap({
    required String helperId,
    required DateTime startDt,
    required DateTime endDt,
    String? excludeId,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperId)
        .limit(500)
        .get();

    for (final d in snap.docs) {
      if (excludeId != null && d.id == excludeId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase().trim();
      if (status != 'pending' && status != 'confirmed' && !status.startsWith('pending_reschedule')) continue;

      // Check both Student appointment fields (startAt/endAt) and HOP appointment fields (start/end)
      final tsStart = m['startAt'] ?? m['start'];
      final tsEnd   = m['endAt'] ?? m['end'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;
      final existingStart = tsStart.toDate();
      final existingEnd   = tsEnd.toDate();
      final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;

      // Also check proposed times
      final propStart = m['proposedStartAt'];
      final propEnd = m['proposedEndAt'];
      if (propStart is Timestamp && propEnd is Timestamp) {
        final pStart = propStart.toDate();
        final pEnd = propEnd.toDate();
        if (pStart.isBefore(endDt) && pEnd.isAfter(startDt)) return true;
      }
    }
    return false;
  }

  // HOP Reschedule: propose new time
  Future<void> _reschedule(BuildContext context, String apptId, Map<String,dynamic> m) async {
    final helperId = (m['helperId'] ?? m['tutorId'] ?? '').toString();
    final origStart = (m['start'] as Timestamp).toDate();
    final origEnd   = (m['end']   as Timestamp).toDate();
    final status = (m['status'] ?? '').toString().toLowerCase().trim();

    // CONDITION 1: If <= 24h, cannot reschedule at all
    final hoursUntil = origStart.difference(DateTime.now()).inHours;
    if (hoursUntil <= 24) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours (Condition 1).')),
        );
      }
      return;
    }

    // CONDITION 2: Can only reschedule if confirmed
    if (status != 'confirmed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Can only reschedule after confirmation (Condition 2).')),
        );
      }
      return;
    }

    // Show reschedule dialog
    DateTime date  = _dayKey(origStart);
    TimeOfDay startTod = TimeOfDay.fromDateTime(origStart);
    TimeOfDay endTod   = TimeOfDay.fromDateTime(origEnd);

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now().add(const Duration(hours: 24)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) setState(() => date = picked);
    }

    Future<void> pickTime(bool isStart) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: isStart ? startTod : endTod,
      );
      if (picked != null) setState(() => isStart ? startTod = picked : endTod = picked);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          return AlertDialog(
            title: const Text('Propose Reschedule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Date'),
                  subtitle: Text(_fmtDateLong(date)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () async { await pickDate(); setStateDlg((){}); },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('Start'),
                        subtitle: Text(_fmtTime(startTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async { await pickTime(true); setStateDlg((){}); },
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        dense: true,
                        title: const Text('End'),
                        subtitle: Text(_fmtTime(endTod)),
                        trailing: IconButton(
                          icon: const Icon(Icons.timer_outlined),
                          onPressed: () async { await pickTime(false); setStateDlg((){}); },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Close')),
              FilledButton(onPressed: () {
                Navigator.pop(context, {
                  'date': date,
                  'startTod': startTod,
                  'endTod': endTod,
                });
              }, child: const Text('Next')),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    final startDt = DateTime(result['date'].year, result['date'].month, result['date'].day,
        result['startTod'].hour, result['startTod'].minute);
    final endDt   = DateTime(result['date'].year, result['date'].month, result['date'].day,
        result['endTod'].hour, result['endTod'].minute);

    if (!startDt.isAfter(DateTime.now().add(const Duration(hours: 24)))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New time must be at least 24 hours from now.')),
        );
      }
      return;
    }
    if (!endDt.isAfter(startDt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start.')),
        );
      }
      return;
    }

    // Check for conflicts
    if (await _hasOverlap(helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conflicts with another booking.')),
        );
      }
      return;
    }

    // Get reason
    final reason = await _getReason(context, 'Reschedule');
    if (reason == null || !mounted) return;

    // Save as pending peer confirmation
    await FirebaseFirestore.instance.collection('appointments').doc(apptId).set({
      'status': 'pending_reschedule_hop',
      'proposedStartAt': Timestamp.fromDate(startDt),
      'proposedEndAt': Timestamp.fromDate(endDt),
      'rescheduleReasonHop': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'rescheduleReasonPeer': FieldValue.delete(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reschedule proposed. Waiting for peer confirmation.')),
      );
    }
  }

  // Accept reschedule proposed by Peer
  Future<void> _acceptPeerReschedule(String apptId, Map<String, dynamic> m) async {
    final propStart = m['proposedStartAt'] as Timestamp?;
    final propEnd = m['proposedEndAt'] as Timestamp?;

    if (propStart == null || propEnd == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule data incomplete.')),
        );
      }
      return;
    }

    // Finalize reschedule
    await FirebaseFirestore.instance.collection('appointments').doc(apptId).set({
      'status': 'confirmed',
      'startAt': propStart,
      'endAt': propEnd,
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonHop': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reschedule accepted.')),
      );
    }
  }

  // HOP Cancel
  Future<void> _cancelAppointment(String apptId, Map<String, dynamic> m) async {
    final startTs = m['start'] as Timestamp?;
    if (startTs == null) return;

    final start = startTs.toDate();
    final status = (m['status'] ?? '').toString().toLowerCase().trim();
    final hoursUntil = start.difference(DateTime.now()).inHours;

    // CONDITION 1 & 2: Can cancel if pending, or confirmed with reason
    bool canCancel = status == 'pending' || status == 'confirmed';

    if (!canCancel) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot cancel this appointment.')),
        );
      }
      return;
    }

    // CONDITION 1: If confirmed and <= 24h, cannot reschedule but can cancel with reason
    // CONDITION 2: If confirmed and > 24h, can cancel with reason
    // Both cases require reason
    final reason = await _getReason(context, 'Cancel');
    if (reason == null || !mounted) return;

    await _updateStatus(apptId, 'cancelled', cancellationReason: reason);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment cancelled.')),
      );
    }
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
              const _HeaderBar(),
              const SizedBox(height: 16),

              Row(
                children: [
                  Text('Calendar', style: t.titleMedium),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),

              _CalendarArea(
                hopUid: _uid,
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                format: _format,
                onDaySelected: (sel, foc) => setState(() {
                  _selectedDay = _dayKey(sel);
                  _focusedDay = foc;
                }),
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (f) => setState(() => _focusedDay = f),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Text('All Tasks', style: t.titleMedium),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),

              _DayTasksList(
                hopUid: _uid,
                selectedDay: _selectedDay ?? DateTime.now(),
                fmtDateLong: _fmtDateLong,
                fmtTime: _fmtTime,
                onCancel: (id, m) => _cancelAppointment(id, m),
                onReschedule: (id, m) => _reschedule(context, id, m),
                onAcceptReschedule: (id, m) => _acceptPeerReschedule(id, m),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------------- Header Bar -------------------------- */

class _HeaderBar extends StatelessWidget {
  const _HeaderBar();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Future<void> _logout() async {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      }
    }

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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HOP', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: _logout,
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

/* ----------------------------- Calendar Area ----------------------------- */

class _CalendarArea extends StatelessWidget {
  final String hopUid;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat format;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(CalendarFormat) onFormatChanged;
  final void Function(DateTime) onPageChanged;

  const _CalendarArea({
    required this.hopUid,
    required this.focusedDay,
    required this.selectedDay,
    required this.format,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onPageChanged,
  });

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('bookerId', isEqualTo: hopUid)
        .snapshots();

    final eventsStream = FirebaseFirestore.instance
        .collection('hop_events')
        .where('hopId', isEqualTo: hopUid)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: appsStream,
      builder: (context, appsSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: eventsStream,
          builder: (context, evSnap) {
            final markers = <DateTime, int>{};
            void add(DateTime dt) {
              final k = _key(dt);
              markers[k] = (markers[k] ?? 0) + 1;
            }
            for (final d in (appsSnap.data?.docs ?? const [])) {
              final m = d.data();
              final ts = m['startAt'] ?? m['start'];
              if (ts is Timestamp) add(ts.toDate());
            }
            for (final d in (evSnap.data?.docs ?? const [])) {
              final m = d.data();
              final ts = m['startAt'];
              if (ts is Timestamp) add(ts.toDate());
            }

            return TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: focusedDay,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              calendarFormat: format,
              onFormatChanged: onFormatChanged,
              onPageChanged: onPageChanged,
              onDaySelected: onDaySelected,
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focused) {
                  final k = _key(day);
                  final count = markers[k] ?? 0;
                  return _DayCell(day: day, count: count, isSelected: isSameDay(selectedDay, day));
                },
                todayBuilder: (context, day, focused) {
                  final k = _key(day);
                  final count = markers[k] ?? 0;
                  return _DayCell(day: day, count: count, isToday: true, isSelected: isSameDay(selectedDay, day));
                },
                selectedBuilder: (context, day, focused) {
                  final k = _key(day);
                  final count = markers[k] ?? 0;
                  return _DayCell(day: day, count: count, isSelected: true);
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final int count;
  final bool isToday;
  final bool isSelected;
  const _DayCell({required this.day, required this.count, this.isToday = false, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFB2DFDB) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: const Color(0xFFFFA726), width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2F8D46), borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

/* ---------------------------- Day Tasks (List) ---------------------------- */

class _DayTasksList extends StatelessWidget {
  final String hopUid;
  final DateTime selectedDay;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;

  final Future<void> Function(String id, Map<String,dynamic> m) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;
  final Future<void> Function(String id, Map<String,dynamic> m) onAcceptReschedule;

  const _DayTasksList({
    required this.hopUid,
    required this.selectedDay,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onCancel,
    required this.onReschedule,
    required this.onAcceptReschedule,
  });

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('bookerId', isEqualTo: hopUid)
        .snapshots();

    final eventsStream = FirebaseFirestore.instance
        .collection('hop_events')
        .where('hopId', isEqualTo: hopUid)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: appsStream,
      builder: (context, appsSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: eventsStream,
          builder: (context, evSnap) {
            if (appsSnap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (appsSnap.hasError) {
              return Text('Error: ${appsSnap.error}', style: t.bodyMedium?.copyWith(color: Colors.red));
            }

            final items = <_TaskItem>[];

            for (final d in (appsSnap.data?.docs ?? const [])) {
              final m = d.data();
              final stTs = m['startAt'] ?? m['start'];
              final enTs = m['endAt'] ?? m['end'];
              if (stTs is! Timestamp || enTs is! Timestamp) continue;
              final st = stTs.toDate();
              if (_key(st) != _key(selectedDay)) continue;
              items.add(_TaskItem.appointment(d.id, m));
            }

            for (final d in (evSnap.data?.docs ?? const [])) {
              final m = d.data();
              final stTs = m['startAt'];
              final enTs = m['endAt'];
              if (stTs is! Timestamp || enTs is! Timestamp) continue;
              final st = stTs.toDate();
              if (_key(st) != _key(selectedDay)) continue;
              items.add(_TaskItem.event(d.id, m));
            }

            if (items.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12),
                ),
                child: const Text('No tasks for this day.'),
              );
            }

            items.sort((a, b) => a.start.millisecondsSinceEpoch.compareTo(b.start.millisecondsSinceEpoch));

            return Column(
              children: [
                for (final it in items) ...[
                  _TaskCard(
                    item: it,
                    fmtDateLong: fmtDateLong,
                    fmtTime: fmtTime,
                    onCancel: onCancel,
                    onReschedule: onReschedule,
                    onAcceptReschedule: onAcceptReschedule,
                  ),
                  const SizedBox(height: 12),
                ]
              ],
            );
          },
        );
      },
    );
  }
}

class _TaskItem {
  final String id;
  final String type;
  final Map<String, dynamic> data;

  final DateTime start;
  final DateTime end;
  final String status;
  final String venue;
  final String mode;

  final String helperId;
  final String helperName;
  final String title;

  _TaskItem._({
    required this.id,
    required this.type,
    required this.data,
    required this.start,
    required this.end,
    required this.status,
    required this.venue,
    required this.mode,
    required this.helperId,
    required this.helperName,
    required this.title,
  });

  factory _TaskItem.appointment(String id, Map<String,dynamic> m) {
    final st = ((m['startAt'] ?? m['start']) as Timestamp).toDate();
    final en = ((m['endAt'] ?? m['end']) as Timestamp).toDate();
    final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();
    final mode = (m['mode'] ?? '').toString().toLowerCase();
    final venue = () {
      if (mode == 'online') {
        final url = (m['meetUrl'] ?? '').toString();
        return url.isNotEmpty ? 'Online ($url)' : 'Online';
      }
      final v = (m['venue'] ?? m['location'] ?? '').toString();
      return v.isNotEmpty ? v : 'Campus';
    }();

    final helperId = (m['helperId'] ?? m['tutorId'] ?? '').toString().trim();
    final helperName = (m['tutorName'] ?? m['helperName'] ?? '').toString();

    return _TaskItem._(
      id: id,
      type: 'appointment',
      data: m,
      start: st,
      end: en,
      status: status,
      venue: venue,
      mode: mode.isEmpty ? 'physical' : mode,
      helperId: helperId,
      helperName: helperName,
      title: '',
    );
  }

  factory _TaskItem.event(String id, Map<String,dynamic> m) {
    final st = (m['startAt'] as Timestamp).toDate();
    final en = (m['endAt'] as Timestamp).toDate();
    final mode = (m['mode'] ?? 'physical').toString();
    final venue = mode == 'online'
        ? (m['meetUrl'] ?? 'Online').toString()
        : (m['venue'] ?? 'Campus').toString();
    return _TaskItem._(
      id: id,
      type: 'event',
      data: m,
      start: st,
      end: en,
      status: 'event',
      venue: venue,
      mode: mode,
      helperId: '',
      helperName: '',
      title: (m['title'] ?? 'Event').toString(),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final _TaskItem item;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;
  final Future<void> Function(String id, Map<String, dynamic> m) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;
  final Future<void> Function(String id, Map<String,dynamic> m) onAcceptReschedule;

  const _TaskCard({
    required this.item,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onCancel,
    required this.onReschedule,
    required this.onAcceptReschedule,
  });

  String _pickName(Map<String, dynamic> m) {
    for (final k in const ['fullName','full_name','name','displayName','display_name']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final profile = m['profile'];
    if (profile is Map<String, dynamic>) {
      for (final k in const ['fullName','full_name','name','displayName','display_name']) {
        final v = profile[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final date = fmtDateLong(item.start);
    final time = '${fmtTime(TimeOfDay.fromDateTime(item.start))} - ${fmtTime(TimeOfDay.fromDateTime(item.end))}';
    final isAppt = item.type == 'appointment';

    String chipLabel;
    Color chipBg;
    Color chipFg;
    Color outline;

    if (!isAppt) {
      chipLabel = 'Event';
      chipBg = const Color(0xFFEDEEF1);
      chipFg = const Color(0xFF6B7280);
      outline = Colors.transparent;
    } else {
      switch (item.status) {
        case 'pending':
          chipLabel = 'Awaiting Confirmation';
          chipBg = const Color(0xFFC9F2D9);
          chipFg = const Color(0xFF1B5E20);
          outline = const Color(0xFF2F8D46);
          break;
        case 'confirmed':
          chipLabel = 'Scheduled';
          chipBg = const Color(0xFFE3F2FD);
          chipFg = const Color(0xFF1565C0);
          outline = const Color(0xFF2F8D46);
          break;
        case 'pending_reschedule_hop':
          chipLabel = 'Reschedule Pending';
          chipBg = const Color(0xFFFFF3CD);
          chipFg = const Color(0xFF8A6D3B);
          outline = Colors.transparent;
          break;
        case 'pending_reschedule_peer':
          chipLabel = 'Confirm Reschedule?';
          chipBg = const Color(0xFFFFCC80);
          chipFg = const Color(0xFFEF6C00);
          outline = Colors.transparent;
          break;
        case 'cancelled':
          chipLabel = 'Cancelled';
          chipBg = const Color(0xFFFFCDD2);
          chipFg = const Color(0xFFC62828);
          outline = const Color(0xFFC62828);
          break;
        case 'completed':
          chipLabel = 'Completed';
          chipBg = const Color(0xFFC8F2D2);
          chipFg = const Color(0xFF2E7D32);
          outline = const Color(0xFF2E7D32);
          break;
        case 'missed':
          chipLabel = 'Missed';
          chipBg = const Color(0xFFFFF3E0);
          chipFg = const Color(0xFFEF6C00);
          outline = const Color(0xFFEF6C00);
          break;
        default:
          chipLabel = 'Pending';
          chipBg = const Color(0xFFEDEEF1);
          chipFg = const Color(0xFF6B7280);
          outline = Colors.transparent;
      }
    }

    final now = DateTime.now();
    final hoursUntil = item.start.difference(now).inHours;
    final isWithin24Hours = hoursUntil <= 24;
    final isUpcoming = item.start.isAfter(now);

    // HOP BUSINESS LOGIC (Conditions 1, 2, 3)
    bool canCancel = false;
    bool canReschedule = false;
    bool showAcceptReschedule = false;

    if (isAppt && isUpcoming) {
      if (item.status == 'pending') {
        // CONDITION 1 & 2: Pending appointments
        if (isWithin24Hours) {
          // <= 24h: Wait for confirmation, can cancel with reason
          canCancel = true;
        } else {
          // > 24h: Wait for confirmation, can cancel with reason
          canCancel = true;
        }
      } else if (item.status == 'confirmed') {
        // CONDITION 1: <= 24h, confirmed - can only cancel
        if (isWithin24Hours) {
          canCancel = true;
        } else {
          // CONDITION 2: > 24h, confirmed - can reschedule and cancel
          canCancel = true;
          canReschedule = true;
        }
      } else if (item.status == 'pending_reschedule_peer') {
        // Peer proposed reschedule, HOP needs to confirm
        showAcceptReschedule = true;
        canCancel = true;
      }
    }

    // Title
    Widget titleWidget;
    if (isAppt) {
      if (item.helperName.isNotEmpty) {
        titleWidget = Text('Tutor Meeting – ${item.helperName}',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
      } else if (item.helperId.isNotEmpty) {
        titleWidget = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(item.helperId).get(),
          builder: (context, snap) {
            String name = '';
            if (snap.hasData && snap.data?.data() != null) {
              name = _pickName(snap.data!.data()!);
            }
            if (name.isEmpty) name = 'Tutor';
            return Text('Tutor Meeting – $name',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
          },
        );
      } else {
        titleWidget = Text('Tutor Meeting – Tutor',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
      }
    } else {
      titleWidget = Text(item.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
    }

    void _openDetails() {
      if (isAppt) {
        Navigator.pushNamed(
          context,
          '/hop/booking',
          arguments: {'appointmentId': item.id},
        );
      }
    }

    // Display reschedule reason if applicable
    final rescheduleReasonPeer = (item.data['rescheduleReasonPeer'] ?? '').toString().trim();

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outline, width: outline == Colors.transparent ? 0.5 : 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black87, width: 2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.person_outline, color: Colors.black87, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: titleWidget),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: chipFg.withOpacity(.3))),
                      child: Text(chipLabel, style: t.labelMedium?.copyWith(color: chipFg, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Date: ${fmtDateLong(item.start)}', style: t.bodySmall),
                Text('Time: $time', style: t.bodySmall),
                Text('Venue: ${item.venue}', style: t.bodySmall),

                // Show peer's reschedule reason
                if (rescheduleReasonPeer.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Peer Reason: $rescheduleReasonPeer',
                      style: t.bodySmall?.copyWith(color: chipFg, fontWeight: FontWeight.w600)),
                ],

                const SizedBox(height: 8),
                if (isAppt)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (showAcceptReschedule)
                          _SmallBtn(
                            label: 'Accept Reschedule',
                            color: const Color(0xFF2E7D32),
                            onTap: () async => onAcceptReschedule(item.id, item.data),
                          ),
                        if (canReschedule)
                          _SmallBtn(
                            label: 'Reschedule',
                            color: const Color(0xFF1565C0),
                            onTap: () async => onReschedule(item.id, item.data),
                          ),
                        if (canCancel)
                          _SmallBtn(
                            label: 'Cancel',
                            color: const Color(0xFFEF6C00),
                            onTap: () async => onCancel(item.id, item.data),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openDetails,
        child: card,
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}