// lib/peer_counsellor_schedule_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

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
    return '${d.day}${_ordinal(d.day)} ${months[d.month-1]} ${d.year}';
  }
  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th';}
  }
  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _updateStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('appointments').doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status != 'pending' && status != 'confirmed') continue;
      final tsStart = m['startAt'];
      final tsEnd   = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;
      final existingStart = tsStart.toDate();
      final existingEnd   = tsEnd.toDate();
      final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }

  Future<void> _reschedule(BuildContext context, String apptId, Map<String,dynamic> m) async {
    final helperId = (m['helperId'] ?? '').toString();

    DateTime start = (m['startAt'] as Timestamp).toDate();
    DateTime end   = (m['endAt']   as Timestamp).toDate();

    // ❗ Block reschedule if within 24 hours of ORIGINAL start
    final now = DateTime.now();
    if (start.difference(now) < const Duration(hours: 24)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reschedule not allowed within 24 hours of the appointment.')),
        );
      }
      return;
    }

    DateTime date  = _dayKey(start);
    TimeOfDay startTod = TimeOfDay.fromDateTime(start);
    TimeOfDay endTod   = TimeOfDay.fromDateTime(end);

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          String fmtT(TimeOfDay t) => _fmtTime(t);
          return AlertDialog(
            title: const Text('Reschedule'),
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
                        subtitle: Text(fmtT(startTod)),
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
                        subtitle: Text(fmtT(endTod)),
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final startDt = DateTime(date.year, date.month, date.day, startTod.hour, startTod.minute);
    final endDt   = DateTime(date.year, date.month, date.day, endTod.hour, endTod.minute);

    // Prevent rescheduling into the past
    if (!startDt.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New start time must be in the future.')),
        );
      }
      return;
    }

    // End after start
    if (!endDt.isAfter(startDt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start.')));
      }
      return;
    }

    // Overlap check
    if (await _hasOverlap(helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflicts with another booking.')));
      }
      return;
    }

    await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
      'startAt': Timestamp.fromDate(startDt),
      'endAt': Timestamp.fromDate(endDt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescheduled.')));
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

                // Confirm: allowed any time BEFORE start
                onConfirm: (id) async {
                  final doc = await FirebaseFirestore.instance.collection('appointments').doc(id).get();
                  final m = doc.data() ?? {};
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

                // Cancel: only if >= 24h remain
                onCancel: (id) async {
                  final doc = await FirebaseFirestore.instance.collection('appointments').doc(id).get();
                  final m = doc.data() ?? {};
                  final ts = m['startAt'];
                  if (ts is! Timestamp) return;
                  final start = ts.toDate();
                  if (start.difference(DateTime.now()) < const Duration(hours: 24)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cancel not allowed within 24 hours of the appointment.')),
                      );
                    }
                    return;
                  }
                  await _updateStatus(id, 'cancelled');
                },

                onReschedule: (id, m) => _reschedule(context, id, m),
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

    // 👇 counsellor-specific events collection
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
            final markers = <DateTime, int>{};
            void add(DateTime dt) {
              final k = _key(dt);
              markers[k] = (markers[k] ?? 0) + 1;
            }
            for (final d in (appsSnap.data?.docs ?? const [])) {
              final m = d.data();
              final ts = m['startAt'];
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
  final String helperUid;
  final DateTime selectedDay;
  final String sortBy;
  final String Function(DateTime) fmtDateLong;
  final String Function(TimeOfDay) fmtTime;

  final Future<void> Function(String id) onConfirm;
  final Future<void> Function(String id) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;

  const _DayTasksList({
    required this.helperUid,
    required this.selectedDay,
    required this.sortBy,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onConfirm,
    required this.onCancel,
    required this.onReschedule,
  });

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final appsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('helperId', isEqualTo: helperUid)
        .snapshots();

    // 👇 counsellor-specific events collection
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

            items.sort((a, b) {
              if (sortBy == 'status') {
                int sv(String s) {
                  switch (s) {
                    case 'pending': return 0;
                    case 'confirmed': return 1;
                    case 'completed': return 2;
                    case 'cancelled': return 3;
                    default: return 4;
                  }
                }
                return sv(a.status).compareTo(sv(b.status));
              } else if (sortBy == 'student') {
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              }
              return a.start.millisecondsSinceEpoch.compareTo(b.start.millisecondsSinceEpoch);
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

  final DateTime start;
  final DateTime end;
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

    return _TaskItem._(
      id: id,
      type: 'appointment',
      data: m,
      start: st,
      end: en,
      title: 'Counselling with ${studentName.isNotEmpty ? studentName : 'Student'}',
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
  final Future<void> Function(String id) onConfirm;
  final Future<void> Function(String id) onCancel;
  final Future<void> Function(String id, Map<String,dynamic> m) onReschedule;

  const _TaskCard({
    required this.item,
    required this.fmtDateLong,
    required this.fmtTime,
    required this.onConfirm,
    required this.onCancel,
    required this.onReschedule,
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
          chipLabel = 'Confirmation Pending';
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
          chipBg = const Color(0xFFFFF3CD);
          chipFg = const Color(0xFF8A6D3B);
          outline = const Color(0xFF8A6D3B);
          break;
        default:
          chipLabel = 'Pending';
          chipBg = const Color(0xFFEDEEF1);
          chipFg = const Color(0xFF6B7280);
          outline = Colors.transparent;
      }
    }

    // Time-based permissions
    final now = DateTime.now();
    final canConfirm = now.isBefore(item.start); // confirm any time before start
    final canModify  = item.start.difference(now) >= const Duration(hours: 24); // cancel/reschedule >= 24h

    // Title
    Widget titleWidget;
    if (isAppt) {
      if (item.studentName.isNotEmpty) {
        titleWidget = Text('Counselling with ${item.studentName}',
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
            return Text('Counselling with $name',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
          },
        );
      } else {
        titleWidget = Text('Counselling with Student',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
      }
    } else {
      titleWidget = Text(item.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700));
    }

    void _openDetails() {
      if (isAppt) {
        Navigator.pushNamed(
          context,
          '/counsellor/booking', // route to booking details (adjust if different)
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
          Container(
            height: 44, width: 44,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black87, width: 2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.psychology_alt_outlined, color: Colors.black87, size: 26),
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
                if (isAppt)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (item.status == 'pending' && canConfirm)
                          _SmallBtn(label: 'Confirm', color: const Color(0xFF2E7D32), onTap: () async {
                            if (!canConfirm) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You can only confirm before the session starts.')),
                              );
                              return;
                            }
                            await onConfirm(item.id);
                          }),

                        if ((item.status == 'pending' || item.status == 'confirmed') && canModify)
                          _SmallBtn(label: 'Cancel', color: const Color(0xFFEF6C00), onTap: () async {
                            if (!canModify) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cancel not allowed within 24 hours of the appointment.')),
                              );
                              return;
                            }
                            await onCancel(item.id);
                          }),

                        if (item.status != 'cancelled' && canModify)
                          _SmallBtn(label: 'Reschedule', color: const Color(0xFF1565C0), onTap: () async {
                            if (!canModify) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reschedule not allowed within 24 hours of the appointment.')),
                              );
                              return;
                            }
                            await onReschedule(item.id, item.data);
                          }),
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
