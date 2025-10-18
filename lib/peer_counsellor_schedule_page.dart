// lib/peer_counsellor_schedule_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class PeerCounsellorSchedulePage extends StatefulWidget {
  const PeerCounsellorSchedulePage({super.key});
  @override
  State<PeerCounsellorSchedulePage> createState() => _PeerCounsellorSchedulePageState();
}

class _PeerCounsellorSchedulePageState extends State<PeerCounsellorSchedulePage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;
  String _sortBy = 'time'; // time | status | student
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day);
  }

  String _fmtDateLong(DateTime d) {
    const months = [
      'January','February','March','April','May','June','July','August','September','October','November','December'
    ];
    String ord(int n) {
      if (n >= 11 && n <= 13) return 'th';
      switch (n % 10) {case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th';}
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

  // UPDATED: Use status fields for Peers (cancelledBy: 'helper')
  Future<void> _updateStatus(String id, String status, {String? cancellationReason}) async {
    final updateData = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'proposedStartAt': FieldValue.delete(),
      'proposedEndAt': FieldValue.delete(),
      'rescheduleReasonPeer': FieldValue.delete(),
      'rescheduleReasonStudent': FieldValue.delete(),
      if (cancellationReason != null) 'cancellationReason': cancellationReason,
      if (cancellationReason != null) 'cancelledBy': 'helper',
    };
    await FirebaseFirestore.instance.collection('appointments').doc(id).set(
      updateData,
      SetOptions(merge: true),
    );
  }

  // NEW: Consolidated function to get 20-char reason. Uses 'context' from State.
  Future<String?> _getReason(String action) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context, // Uses the State's context
      builder: (_) => AlertDialog(
        title: Text('$action Reason'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          maxLength: 20, // Enforce max 20 characters
          decoration: const InputDecoration(
            hintText: 'Enter reason (Max 20 characters)',
            border: OutlineInputBorder(),
            counterText: '', // Hide built-in counter
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty || reason.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason (max 20 characters) is required.')));
                return;
              }
              Navigator.pop(context, reason);
            },
            child: Text('Confirm $action'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    return result;
  }

  // Overlap check helper (required for reschedule logic)
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
      final status = (m['status'] ?? '').toString();
      // Only check against currently active/pending slots
      if (status != 'pending' && status != 'confirmed' && !status.startsWith('pending_reschedule')) continue;

      List<DateTime?> checkStarts = [];
      List<DateTime?> checkEnds = [];

      final tsStart = m['startAt'];
      final tsEnd   = m['endAt'];
      if (tsStart is Timestamp && tsEnd is Timestamp) {
        checkStarts.add(tsStart.toDate());
        checkEnds.add(tsEnd.toDate());
      }

      final newTsStart = m['proposedStartAt'];
      final newTsEnd = m['proposedEndAt'];
      if (newTsStart is Timestamp && newTsEnd is Timestamp) {
        checkStarts.add(newTsStart.toDate());
        checkEnds.add(newTsEnd.toDate());
      }

      for (int i = 0; i < checkStarts.length; i++) {
        final existingStart = checkStarts[i];
        final existingEnd   = checkEnds[i];
        if (existingStart == null || existingEnd == null) continue;

        final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
        if (overlaps) return true;
      }
    }
    return false;
  }

  // FIX: Removed BuildContext parameter. Uses this.context (from State) internally.
  Future<void> _reschedule(String apptId, Map<String,dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();

    final origStart = (m['startAt'] as Timestamp?)?.toDate();
    final origEnd   = (m['endAt']   as Timestamp?)?.toDate();

    if (origStart == null || origEnd == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment time data is incomplete.')),
        );
      }
      return;
    }

    // --- CONDITION 1 CHECK ---
    final now = DateTime.now();
    if (origStart.difference(now).inHours <= 24) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours (Condition 1).')),
        );
      }
      return;
    }

    // Reschedule dialog uses this.context
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RescheduleDialogPeer(currentStart: origStart, currentEnd: origEnd),
    );
    if(result == null || !mounted) return;

    final startDt = result['start'];
    final endDt   = result['end'];
    final reason  = result['reason'];

    // Overlap check
    if (await _hasOverlap(helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proposed time conflicts with your existing schedule.')));
      }
      return;
    }

    // Save as pending student confirmation
    await FirebaseFirestore.instance.collection('appointments').doc(apptId).set({
      'status': 'pending_reschedule_peer', // Peer-initiated change needs student confirmation
      'proposedStartAt': Timestamp.fromDate(startDt), // Store proposed time separately
      'proposedEndAt': Timestamp.fromDate(endDt),
      'rescheduleReasonPeer': reason, // Peer's reason (max 20 chars enforced by dialog)
      'updatedAt': FieldValue.serverTimestamp(),
      'rescheduleReasonStudent': FieldValue.delete(), // Clear student reason if it existed
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule proposed. Waiting for student confirmation.')));
    }
  }

  // FIX: Removed BuildContext parameter. Uses this.context (from State) internally.
  Future<void> _confirmCancel(String apptId, Map<String, dynamic> m) async {
    final startTs = m['startAt'] as Timestamp?;
    final start = startTs?.toDate();

    if (start == null) return;

    // --- CONDITION 1 CHECK ---
    // Rule: If confirmed, Peers cannot cancel if <= 24 hours.
    final status = (m['status'] ?? '').toString().toLowerCase();
    final isConfirmed = status == 'confirmed';
    final isWithin24Hours = start.difference(DateTime.now()).inHours <= 24;

    if (isConfirmed && isWithin24Hours) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmed appointments cannot be cancelled by the Peer Counsellor within 24 hours (Condition 1).')),
        );
      }
      return;
    }

    final reason = await _getReason('Cancel'); // Uses State's context

    if (reason != null && mounted) {
      await _updateStatus(apptId, 'cancelled', cancellationReason: reason);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
    }
  }

  // FIX: Removed BuildContext parameter. Uses this.context (from State) internally.
  Future<void> _acceptReschedule(String apptId, Map<String, dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();

    final newStartTs = m['proposedStartAt'] as Timestamp?;
    final newEndTs   = m['proposedEndAt'] as Timestamp?;

    if (newStartTs == null || newEndTs == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule data is incomplete.')));
      return;
    }

    final newStartDt = newStartTs.toDate();
    final newEndDt   = newEndTs.toDate();

    if (await _hasOverlap(helperId: helperId, startDt: newStartDt, endDt: newEndDt, excludeId: apptId)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proposed time conflicts with your existing schedule.')));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('appointments').doc(apptId).set({
        'status': 'confirmed',
        'startAt': newStartTs,
        'endAt': newEndTs,
        'proposedStartAt': FieldValue.delete(),
        'proposedEndAt': FieldValue.delete(),
        'rescheduleReasonPeer': FieldValue.delete(),
        'rescheduleReasonStudent': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule confirmed and appointment updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Confirmation failed: $e')));
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
                helperUid: _uid,
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
                  DropdownButton<String>(
                    value: _sortBy,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'time', child: Text('Sort By: Time')),
                      DropdownMenuItem(value: 'status', child: Text('Sort By: Status')),
                      DropdownMenuItem(value: 'student', child: Text('Sort By: Student')),
                    ],
                    onChanged: (v) => setState(() => _sortBy = v ?? 'time'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _DayTasksList(
                helperUid: _uid,
                selectedDay: _selectedDay ?? DateTime.now(),
                sortBy: _sortBy,
                fmtDateLong: _fmtDateLong,
                fmtTime: _fmtTime,

                // Callbacks now match the expected (String, Map) signature
                onConfirm: (id, m) async {
                  final ts = m['startAt'];
                  if (ts is! Timestamp) return;
                  final start = ts.toDate();

                  if (!DateTime.now().isBefore(start)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You can only confirm before the session starts.')),
                      );
                    }
                    return;
                  }
                  await _updateStatus(id, 'confirmed');
                },

                onCancel: _confirmCancel,
                onReschedule: _reschedule,
                onAcceptReschedule: _acceptReschedule,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------------- Header Bar (with logout) -------------------------- */

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
            Text('Peer Counsellor', style: t.titleMedium),
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
  final String helperUid;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat format;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(CalendarFormat) onFormatChanged;
  final void Function(DateTime) onPageChanged;

  const _CalendarArea({
    required this.helperUid,
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
        .where('helperId', isEqualTo: helperUid)
        .snapshots();

    final eventsStream = FirebaseFirestore.instance
        .collection('counsellor_events') // Changed from tutor_events
        .where('userId', isEqualTo: helperUid)
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
              final ts = m['startAt'];
              if (ts is Timestamp) add(ts.toDate());

              final newTs = m['proposedStartAt'];
              if (newTs is Timestamp && ts is Timestamp && newTs.toDate().day != ts.toDate().day) add(newTs.toDate());
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
  final String helperUid;
  final DateTime selectedDay;
  final String sortBy;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;

  // The signatures for the functions passed from the State class (two arguments)
  final Future<void> Function(String id, Map<String, dynamic> m) onConfirm;
  final Future<void> Function(String id, Map<String, dynamic> m) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;
  final Future<void> Function(String id, Map<String,dynamic> m) onAcceptReschedule;


  const _DayTasksList({
    required this.helperUid,
    required this.selectedDay,
    required this.sortBy,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onConfirm,
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
        .where('helperId', isEqualTo: helperUid)
        .snapshots();

    final eventsStream = FirebaseFirestore.instance
        .collection('counsellor_events')
        .where('userId', isEqualTo: helperUid)
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
              final stTs = m['startAt'];
              final enTs = m['endAt'];
              final newStTs = m['proposedStartAt'];

              bool isScheduledForToday(Timestamp? ts) => ts is Timestamp && _key(ts.toDate()) == _key(selectedDay);
              final status = (m['status'] ?? 'pending').toString().toLowerCase().trim();

              if (stTs is Timestamp && enTs is Timestamp) {
                if (isScheduledForToday(stTs)) {
                  if (status == 'completed' || status == 'cancelled' || status == 'missed') {
                    if (stTs.toDate().isAfter(DateTime.now().subtract(const Duration(hours: 24)))) {
                      items.add(_TaskItem.appointment(d.id, m));
                    }
                  } else {
                    items.add(_TaskItem.appointment(d.id, m));
                  }
                }
                // Check proposed time if it's waiting for Peer action (Peer Reschedule is waiting for student)
                else if (status == 'pending_reschedule_student' && isScheduledForToday(newStTs)) {
                  items.add(_TaskItem.appointment(d.id, m));
                }
              }
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

            items.sort((a, b) {
              if (sortBy == 'status') {
                int sv(String s) {
                  switch (s) {
                    case 'pending': return 0;
                    case 'pending_reschedule_student': return 1;
                    case 'confirmed': return 2;
                    case 'event': return 3;
                    case 'completed': return 4;
                    case 'cancelled': return 5;
                    case 'missed': return 6;
                    default: return 7;
                  }
                }
                return sv(a.status).compareTo(sv(b.status));
              } else if (sortBy == 'student') {
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              }
              // Sort by display start time
              final aStart = a.data.containsKey('proposedStartAt') && a.status == 'pending_reschedule_student'
                  ? (a.data['proposedStartAt'] as Timestamp).toDate().millisecondsSinceEpoch
                  : a.start.millisecondsSinceEpoch;
              final bStart = b.data.containsKey('proposedStartAt') && b.status == 'pending_reschedule_student'
                  ? (b.data['proposedStartAt'] as Timestamp).toDate().millisecondsSinceEpoch
                  : b.start.millisecondsSinceEpoch;
              return aStart.compareTo(bStart);
            });

            return Column(
              children: [
                for (final it in items) ...[
                  _TaskCard(
                    item: it,
                    fmtDateLong: fmtDateLong,
                    fmtTime: fmtTime,
                    onConfirm: onConfirm,
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
  final String type; // appointment | event
  final Map<String, dynamic> data;

  final DateTime start; // original start time
  final DateTime end;   // original end time
  final String title;
  final String status; // pending/confirmed/... or 'event'
  final String venue;
  final String mode;

  final String studentId;
  final String studentName;

  _TaskItem._({
    required this.id,
    required this.type,
    required this.data,
    required this.start,
    required this.end,
    required this.title,
    required this.status,
    required this.venue,
    required this.mode,
    required this.studentId,
    required this.studentName,
  });

  factory _TaskItem.appointment(String id, Map<String,dynamic> m) {
    final st = (m['startAt'] as Timestamp).toDate();
    final en = (m['endAt'] as Timestamp).toDate();
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

    final studentId = (m['studentId'] ?? '').toString();
    final studentName = (m['studentName'] ?? '').toString();
    final isCounselling = (m['helperRole'] ?? '').toString().toLowerCase().contains('counsellor');


    return _TaskItem._(
      id: id,
      type: 'appointment',
      data: m,
      start: st,
      end: en,
      title: isCounselling ? 'Counselling Session' : 'Session',
      status: status,
      venue: venue,
      mode: mode.isEmpty ? 'physical' : mode,
      studentId: studentId,
      studentName: studentName,
    );
  }

  factory _TaskItem.event(String id, Map<String,dynamic> m) {
    final st = (m['startAt'] as Timestamp).toDate();
    final en = (m['endAt'] as Timestamp).toDate();
    final mode = (m['mode'] ?? 'physical').toString();
    final venue = mode == 'online' ? (m['meetUrl'] ?? 'Online').toString() : (m['venue'] ?? 'Campus').toString();
    return _TaskItem._(
      id: id,
      type: 'event',
      data: m,
      start: st,
      end: en,
      title: (m['title'] ?? 'Event').toString(),
      status: 'event',
      venue: venue,
      mode: mode,
      studentId: '',
      studentName: '',
    );
  }
}

class _TaskCard extends StatelessWidget {
  final _TaskItem item;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;
  final Future<void> Function(String id, Map<String, dynamic> m) onConfirm;
  final Future<void> Function(String id, Map<String, dynamic> m) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;
  final Future<void> Function(String id, Map<String,dynamic> m) onAcceptReschedule;


  const _TaskCard({
    required this.item,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onConfirm,
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

    final m = item.data;
    final isAppt = item.type == 'appointment';

    // Time calculations based on status
    final isPending = item.status == 'pending';
    final isConfirmed = item.status == 'confirmed';
    final isReschedulePendingStudent = item.status == 'pending_reschedule_peer'; // Peer proposed, student confirming
    final isReschedulePendingHelper = item.status == 'pending_reschedule_student'; // Student proposed, peer confirming
    final isTerminal = item.status == 'cancelled' || item.status == 'completed' || item.status == 'missed';

    // Display times: use proposed times if waiting for peer confirmation (student proposed), otherwise use original times
    final displayStart = isReschedulePendingHelper
        ? (m['proposedStartAt'] as Timestamp?)?.toDate() ?? item.start
        : item.start;
    final displayEnd = isReschedulePendingHelper
        ? (m['proposedEndAt'] as Timestamp?)?.toDate() ?? item.end
        : item.end;

    final date = fmtDateLong(displayStart);
    final time = '${fmtTime(TimeOfDay.fromDateTime(displayStart))} - ${fmtTime(TimeOfDay.fromDateTime(displayEnd))}';

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
          chipLabel = 'Pending Confirmation';
          chipBg = const Color(0xFFC9F2D9);
          chipFg = const Color(0xFF1B5E20);
          outline = Colors.transparent;
          break;
        case 'confirmed':
          chipLabel = 'Scheduled';
          chipBg = const Color(0xFFE3F2FD);
          chipFg = const Color(0xFF1565C0);
          outline = const Color(0xFF2F8D46);
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
          chipBg = const Color(0xFFC8F2D2);
          chipFg = const Color(0xFF2E7D32);
          outline = const Color(0xFF2E7D32);
          break;
        case 'pending_reschedule_peer':
          chipLabel = 'Counsellor Reschedule';
          chipBg = const Color(0xFFFFF3CD);
          chipFg = const Color(0xFF8A6D3B);
          outline = Colors.transparent;
          break;
        case 'pending_reschedule_student':
          chipLabel = 'Confirm Reschedule?';
          chipBg = const Color(0xFFFFCC80);
          chipFg = const Color(0xFFEF6C00);
          outline = Colors.transparent;
          break;
        default:
          chipLabel = 'Pending';
          chipBg = const Color(0xFFEDEEF1);
          chipFg = const Color(0xFF6B7280);
          outline = Colors.transparent;
      }
    }

    // --- PEER BUSINESS LOGIC (Conditions 1 & 2) ---
    final now = DateTime.now();
    final timeRemainingHours = item.start.difference(now).inHours;
    final isWithin24Hours = timeRemainingHours <= 24;
    final isUpcoming = item.start.isAfter(now);

    bool canConfirm = false;
    bool canPeerCancel = false;
    bool canPeerReschedule = false;

    if (isAppt && isUpcoming) {
      if (isPending) {
        // Condition 1 & 2: Pending appointments can always be confirmed/cancelled by Peer.
        canConfirm = true;
        canPeerCancel = true;
        canPeerReschedule = !isWithin24Hours; // Only reschedule if > 24 hours (Condition 2)
      } else if (isConfirmed) {
        // Condition 1: Confirmed <= 24h -> No Peer actions
        if (!isWithin24Hours) {
          // Condition 2: Confirmed > 24h -> Peer can cancel or reschedule
          canPeerCancel = true;
          canPeerReschedule = true;
        }
      }
    }

    // Title resolution logic remains the same
    Widget titleWidget;
    if (isAppt) {
      if (item.studentName.isNotEmpty) {
        titleWidget = Text('${item.title} with ${item.studentName}',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
      } else if (item.studentId.isNotEmpty) {
        titleWidget = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(item.studentId).get(),
          builder: (context, snap) {
            String name = '';
            if (snap.hasData && snap.data?.data() != null) {
              name = _pickName(snap.data!.data()!);
            }
            if (name.isEmpty) name = 'Student';
            return Text('${item.title} with $name',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
          },
        );
      } else {
        titleWidget = Text('${item.title} with Student',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
      }
    } else {
      titleWidget = Text(item.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
    }


    // FIX: Navigation to Peer Counsellor Booking Info Page (Scenario 2)
    void _openDetails() {
      if (isAppt) {
        Navigator.pushNamed(
          context,
          '/counsellor/booking', // Route mapped to PeerCounsellorBookingInfoPage
          arguments: {'appointmentId': item.id},
        );
      }
    }

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
          // Avatar for appointment/Icon for event
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black87, width: 2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(isAppt ? Icons.person_outline : Icons.event, color: Colors.black87, size: 26),
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
                Text('Date: $date', style: t.bodySmall),
                Text('Time: $time', style: t.bodySmall),
                Text('Venue: ${item.venue}', style: t.bodySmall),
                const SizedBox(height: 8),

                // Reschedule reason display
                if (isReschedulePendingStudent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Counsellor Reason: ${m['rescheduleReasonPeer'] ?? 'N/A'}',
                      style: t.bodySmall?.copyWith(color: chipFg),
                    ),
                  )
                else if (isReschedulePendingHelper)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Student Reason: ${m['rescheduleReasonStudent'] ?? 'N/A'}',
                      style: t.bodySmall?.copyWith(color: chipFg),
                    ),
                  ),

                // Cancellation reason display
                if (isTerminal && item.status == 'cancelled' && m.containsKey('cancellationReason'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Cancel Reason: ${m['cancellationReason'] ?? 'N/A'}',
                      style: t.bodySmall?.copyWith(color: const Color(0xFFC62828)),
                    ),
                  ),

                if (isAppt && isUpcoming)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        // Accept Reschedule (when student proposed, status: pending_reschedule_student)
                        if (isReschedulePendingHelper)
                          _SmallBtn(label: 'Accept Reschedule', color: const Color(0xFF2E7D32), onTap: () async => onAcceptReschedule(item.id, m)),

                        // Confirm (initial booking, status: pending)
                        if (canConfirm && isPending)
                          _SmallBtn(label: 'Confirm', color: const Color(0xFF2E7D32), onTap: () async => onConfirm(item.id, m)),

                        // Reschedule (only if outside 24h & confirmed/pending)
                        if (canPeerReschedule)
                          _SmallBtn(label: 'Reschedule', color: const Color(0xFF1565C0), onTap: () async => onReschedule(item.id, m)),

                        // Cancel (available if pending or confirmed > 24h)
                        if (canPeerCancel)
                          _SmallBtn(label: 'Cancel', color: const Color(0xFFEF6C00), onTap: () async => onCancel(item.id, m)),
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
        onTap: _openDetails, // Scenario 2: Card is clickable
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

// Reschedule Dialog definition (copied from peer_booking_info_page.dart for self-contained use)
class _RescheduleDialogPeer extends StatefulWidget {
  final DateTime currentStart, currentEnd;
  const _RescheduleDialogPeer({required this.currentStart, required this.currentEnd});
  @override
  State<_RescheduleDialogPeer> createState() => _RescheduleDialogPeerState();
}

class _RescheduleDialogPeerState extends State<_RescheduleDialogPeer> {
  late DateTime _date;
  late TimeOfDay _startTod, _endTod;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.currentStart.year, widget.currentStart.month, widget.currentStart.day);
    _startTod = TimeOfDay.fromDateTime(widget.currentStart);
    _endTod = TimeOfDay.fromDateTime(widget.currentEnd);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) => DateFormat.jm().format(DateTime(2025,1,1,t.hour, t.minute));

  Future<void> _pickDate() async {
    final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (p != null) setState(() => _date = p);
  }
  Future<void> _pickTime(bool isStart) async {
    final p = await showTimePicker(context: context, initialTime: isStart ? _startTod : _endTod);
    if (p != null) setState(() => isStart ? _startTod = p : _endTod = p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Propose Reschedule'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: const Text('New Date'), subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)),
          Row(children: [
            Expanded(child: ListTile(dense: true, title: const Text('Start'), subtitle: Text(_fmtTime(_startTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(true)))),
            Expanded(child: ListTile(dense: true, title: const Text('End'), subtitle: Text(_fmtTime(_endTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(false)))),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
                hintText: 'Reason for rescheduling (Max 20 characters)',
                border: OutlineInputBorder(),
                counterText: ''
            ),
            maxLines: 2,
            maxLength: 20, // Enforce max 20 characters
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: () {
          final start = DateTime(_date.year, _date.month, _date.day, _startTod.hour, _startTod.minute);
          final end = DateTime(_date.year, _date.month, _date.day, _endTod.hour, _endTod.minute);
          final reason = _reasonCtrl.text.trim();

          if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
            return;
          }
          if (start.isBefore(DateTime.now())) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New time must be in the future.')));
            return;
          }
          if (reason.isEmpty || reason.length > 20) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason (max 20 chars) is required.')));
            return;
          }

          Navigator.pop(context, {'start': start, 'end': end, 'reason': reason});
        }, child: const Text('Propose Change')),
      ],
    );
  }
}