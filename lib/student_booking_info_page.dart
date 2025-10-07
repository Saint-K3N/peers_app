// lib/student_booking_info_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentBookingInfoPage extends StatefulWidget {
  const StudentBookingInfoPage({super.key});

  @override
  State<StudentBookingInfoPage> createState() => _StudentBookingInfoPageState();
}

class _StudentBookingInfoPageState extends State<StudentBookingInfoPage> {
  // Create-mode local state (used only when there's NO appointmentId)
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _location;
  final _notesCtrl =
  TextEditingController(text: 'Meet me at a cubicle on Level 3');

  // Args (set once)
  bool _argsParsed = false;
  String? _appointmentId; // when present -> view existing
  String _helperId = '';

  // Fallbacks from previous page (used if helper details can’t be resolved)
  String _fbName = '—';
  String _fbFaculty = '—';
  String _fbEmail = '—';
  int _fbSessions = 0;
  List<String> _fbSpecializes = const <String>[];

  @override
  void initState() {
    super.initState();
    // sensible defaults for create mode
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _startTime = const TimeOfDay(hour: 10, minute: 0);
    _endTime = const TimeOfDay(hour: 12, minute: 0);
    _location = 'Campus - Level 3';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsParsed) return;
    _argsParsed = true;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    _appointmentId = (args['appointmentId'] as String?);
    _helperId = (args['userId'] as String?) ?? _helperId;

    _fbName = (args['name'] as String?) ?? _fbName;
    _fbFaculty = (args['faculty'] as String?) ?? _fbFaculty;
    _fbEmail = (args['email'] as String?) ?? _fbEmail;
    _fbSessions = (args['sessions'] as int?) ?? _fbSessions;
    _fbSpecializes = (args['specializes'] as List<String>?) ?? _fbSpecializes;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _viewingExisting =>
      _appointmentId != null && _appointmentId!.isNotEmpty;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Future<void> _pickDate() async {
    if (_viewingExisting) return; // read-only in view mode
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    if (_viewingExisting) return; // read-only in view mode
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _startTime : _endTime) ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // ---------- NEW: overlap guard for rescheduling ----------
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
      if (status != 'pending' && status != 'confirmed') continue;

      final tsStart = m['startAt'];
      final tsEnd = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;

      final existingStart = tsStart.toDate();
      final existingEnd = tsEnd.toDate();
      final overlaps =
          existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }

  // ---------- UPDATED: cancel with 24h rule ----------
  Future<void> _cancelExisting(
      String appointmentId, DateTime startAt, String statusRaw) async {
    // only if ≥ 24h and status pending/confirmed
    final canModify =
        startAt.difference(DateTime.now()) >= const Duration(hours: 24);
    final status = statusRaw.toLowerCase();
    if (!canModify || (status != 'pending' && status != 'confirmed')) {
      _msg('Cancel not allowed within 24 hours of the appointment.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointmentId)
            .update({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Appointment cancelled.')));
        Navigator.maybePop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
      }
    }
  }

  // ---------- NEW: reschedule with 24h rule ----------
  Future<void> _reschedule(
      BuildContext context, {
        required String apptId,
        required String helperId,
        required DateTime currentStart,
        required DateTime currentEnd,
      }) async {
    // Only allowed if ≥ 24h before the current start
    if (currentStart.difference(DateTime.now()) < const Duration(hours: 24)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Reschedule not allowed within 24 hours of the appointment.')),
        );
      }
      return;
    }

    DateTime date =
    DateTime(currentStart.year, currentStart.month, currentStart.day);
    TimeOfDay startTod = TimeOfDay.fromDateTime(currentStart);
    TimeOfDay endTod = TimeOfDay.fromDateTime(currentEnd);

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) date = picked;
    }

    Future<void> pickTime(bool isStart) async {
      final picked = await showTimePicker(
        context: context,
        initialTime: isStart ? startTod : endTod,
      );
      if (picked != null) {
        if (isStart) {
          startTod = picked;
        } else {
          endTod = picked;
        }
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          return AlertDialog(
            title: const Text('Reschedule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: const Text('Date'),
                  subtitle: Text(_fmtDate(date)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () async {
                      await pickDate();
                      setStateDlg(() {});
                    },
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
                          onPressed: () async {
                            await pickTime(true);
                            setStateDlg(() {});
                          },
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
                          onPressed: () async {
                            await pickTime(false);
                            setStateDlg(() {});
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Close')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    final startDt = DateTime(
        date.year, date.month, date.day, startTod.hour, startTod.minute);
    final endDt =
    DateTime(date.year, date.month, date.day, endTod.hour, endTod.minute);

    if (!startDt.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('New start time must be in the future.')),
        );
      }
      return;
    }
    if (!endDt.isAfter(startDt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End time must be after start.')));
      }
      return;
    }
    if (await _hasOverlap(
        helperId: helperId, startDt: startDt, endDt: endDt, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conflicts with another booking.')));
      }
      return;
    }

    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(apptId)
        .update({
      'startAt': Timestamp.fromDate(startDt),
      'endAt': Timestamp.fromDate(endDt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rescheduled.')));
    }
  }

  Future<void> _confirmCreate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _msg('Please sign in first.');
      return;
    }
    if (_helperId.isEmpty) {
      _msg('Missing helper info.');
      return;
    }
    if (_date == null || _startTime == null || _endTime == null) {
      _msg('Please select date and time.');
      return;
    }
    if (_location == null || _location!.trim().isEmpty) {
      _msg('Please pick a location.');
      return;
    }

    final start = DateTime(_date!.year, _date!.month, _date!.day,
        _startTime!.hour, _startTime!.minute);
    final end = DateTime(_date!.year, _date!.month, _date!.day, _endTime!.hour,
        _endTime!.minute);

    if (!end.isAfter(start)) {
      _msg('End time must be after start time.');
      return;
    }
    if (start.isBefore(DateTime.now())) {
      _msg('Start time is in the past.');
      return;
    }

    // Double-booking guard (index-free; filter client-side)
    try {
      final apps = await FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: _helperId)
          .get();

      bool overlap = false;
      for (final d in apps.docs) {
        final m = d.data();
        final status = (m['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'pending' && status != 'confirmed') continue;

        final st = (m['startAt'] as Timestamp?)?.toDate();
        final et = (m['endAt'] as Timestamp?)?.toDate();
        if (st == null || et == null) continue;

        final sameDay = st.year == _date!.year &&
            st.month == _date!.month &&
            st.day == _date!.day;
        if (!sameDay) continue;

        // intervals overlap?
        final noOverlap = (et.isAtSameMomentAs(start) || et.isBefore(start)) ||
            (st.isAtSameMomentAs(end) || st.isAfter(end));
        if (!noOverlap) {
          overlap = true;
          break;
        }
      }
      if (overlap) {
        _msg('This time conflicts with another booking for this helper.');
        return;
      }

      final payload = {
        'studentId': uid,
        'helperId': _helperId,
        'status': 'pending',
        'startAt': Timestamp.fromDate(start),
        'endAt': Timestamp.fromDate(end),
        'location': _location,
        'notes': _notesCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final ref = await FirebaseFirestore.instance
          .collection('appointments')
          .add(payload);

      if (!mounted) return;
      _msg('Booking sent!');
      // After creating, stay here and show the newly created appointment in view mode.
      setState(() {
        _appointmentId = ref.id;
      });
    } catch (e) {
      _msg('Failed to book: $e');
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  (Color bg, Color fg) _statusColors(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'completed':
        return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'cancelled':
        return (const Color(0xFFFFE0E0), const Color(0xFFD32F2F));
      default:
        return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
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
              const _StudentHeader(),
              const SizedBox(height: 16),
              Text('Booking Info',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  _viewingExisting
                      ? 'Your booking details'
                      : 'Set up a new booking',
                  style: t.bodySmall),
              const SizedBox(height: 12),

              if (_viewingExisting)
              // ---------- VIEW EXISTING APPOINTMENT ----------
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(_appointmentId)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: CircularProgressIndicator(),
                          ));
                    }
                    if (!snap.hasData || !snap.data!.exists) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Text('Appointment not found.'),
                      );
                    }

                    final m = snap.data!.data()!;
                    final start = (m['startAt'] as Timestamp?)?.toDate();
                    final end = (m['endAt'] as Timestamp?)?.toDate();
                    final loc = (m['location'] ?? '').toString();
                    final notes = (m['notes'] ?? '').toString();
                    final statusRaw =
                    (m['status'] ?? 'pending').toString();
                    final helperIdFromDoc = (m['helperId'] ?? '').toString();
                    final statusLbl = _statusLabel(statusRaw);
                    final (chipBg, chipFg) = _statusColors(statusRaw);

                    final header = _HelperHeader(
                      helperId: helperIdFromDoc.isNotEmpty
                          ? helperIdFromDoc
                          : _helperId,
                      fallbackName: _fbName,
                      fallbackFaculty: _fbFaculty,
                      fallbackEmail: _fbEmail,
                      fallbackSessions: _fbSessions,
                      fallbackPhotoUrl: '',
                      specializes: _fbSpecializes,
                    );

                    // 24h rule gating
                    final now = DateTime.now();
                    final canModify = start != null &&
                        start.difference(now) >= const Duration(hours: 24);
                    final lowered = statusRaw.toLowerCase();
                    final canCancel =
                        (lowered == 'pending' || lowered == 'confirmed') &&
                            canModify;
                    final canReschedule =
                        (lowered == 'pending' || lowered == 'confirmed') &&
                            canModify &&
                            start != null &&
                            end != null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row + status
                        Stack(
                          children: [
                            header,
                            Positioned(
                              right: 12,
                              top: 12,
                              child: _Chip(
                                  label: statusLbl, bg: chipBg, fg: chipFg),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Date (read-only)
                        _FieldShell(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (start != null) ? _fmtDate(start) : '—',
                                  style: t.bodyMedium,
                                ),
                              ),
                              const Icon(Icons.calendar_month_outlined),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Time (read-only)
                        _FieldShell(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (start != null && end != null)
                                      ? '${_fmtTime(TimeOfDay.fromDateTime(start))}  to  ${_fmtTime(TimeOfDay.fromDateTime(end))}'
                                      : '—',
                                  style: t.bodyMedium,
                                ),
                              ),
                              const Icon(Icons.timer_outlined),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Location (read-only)
                        _FieldShell(
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      loc.isEmpty ? '—' : loc,
                                      style: t.bodyMedium)),
                              const Icon(Icons.place_outlined),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Notes (read-only)
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: SingleChildScrollView(
                            primary: false,
                            child: SizedBox(
                              width: double.infinity,
                              child: Text(
                                notes.isEmpty ? '—' : notes,
                                softWrap: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Footer actions — Cancel/Reschedule only when ≥ 24h and allowed statuses
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                                onPressed: () => Navigator.maybePop(context),
                                child: const Text('Back')),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (canReschedule)
                                  FilledButton.tonal(
                                    onPressed: () => _reschedule(
                                      context,
                                      apptId: _appointmentId!,
                                      helperId: helperIdFromDoc.isNotEmpty
                                          ? helperIdFromDoc
                                          : _helperId,
                                      currentStart: start!,
                                      currentEnd: end!,
                                    ),
                                    child: const Text('Reschedule'),
                                  ),
                                if (canCancel)
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red),
                                    onPressed: () => _cancelExisting(
                                      _appointmentId!,
                                      start!,
                                      statusRaw,
                                    ),
                                    child: const Text('Cancel Booking'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                )
              else
              // ---------- CREATE NEW APPOINTMENT ----------
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HelperHeader(
                      helperId: _helperId,
                      fallbackName: _fbName,
                      fallbackFaculty: _fbFaculty,
                      fallbackEmail: _fbEmail,
                      fallbackSessions: _fbSessions,
                      fallbackPhotoUrl: '',
                      specializes: _fbSpecializes,
                    ),

                    const SizedBox(height: 12),

                    _FieldShell(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null ? 'Date' : _fmtDate(_date!),
                              style: t.bodyMedium?.copyWith(
                                  color: _date == null
                                      ? Colors.black54
                                      : Colors.black),
                            ),
                          ),
                          IconButton(
                            onPressed: _pickDate,
                            icon:
                            const Icon(Icons.calendar_month_outlined),
                            tooltip: 'Pick date',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    LayoutBuilder(builder: (context, c) {
                      final tight = c.maxWidth < 360;

                      final fromField = _FieldShell(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _startTime == null
                                    ? 'Time'
                                    : _fmtTime(_startTime!),
                                style: t.bodyMedium?.copyWith(
                                  color: _startTime == null
                                      ? Colors.black54
                                      : Colors.black,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _pickTime(true),
                              icon: const Icon(Icons.timer_outlined),
                              tooltip: 'Start time',
                            ),
                          ],
                        ),
                      );

                      final toField = _FieldShell(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _endTime == null
                                    ? 'Time'
                                    : _fmtTime(_endTime!),
                                style: t.bodyMedium?.copyWith(
                                  color: _endTime == null
                                      ? Colors.black54
                                      : Colors.black,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _pickTime(false),
                              icon: const Icon(Icons.timer_outlined),
                              tooltip: 'End time',
                            ),
                          ],
                        ),
                      );

                      if (tight) {
                        return Column(
                          children: [
                            fromField,
                            const SizedBox(height: 8),
                            toField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: fromField),
                          const SizedBox(width: 8),
                          const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text('to')),
                          const SizedBox(width: 8),
                          Expanded(child: toField),
                        ],
                      );
                    }),

                    const SizedBox(height: 8),

                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: DropdownButton<String>(
                        value: _location,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('Select Location'),
                        items: const [
                          DropdownMenuItem(
                              value: 'Campus - Level 3',
                              child: Text('Campus - Level 3')),
                          DropdownMenuItem(
                              value: 'Campus - Level 5',
                              child: Text('Campus - Level 5')),
                          DropdownMenuItem(
                              value: 'Online (Google Meet)',
                              child: Text('Online (Google Meet)')),
                        ],
                        onChanged: (v) => setState(() => _location = v),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Notes (edit)
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _notesCtrl,
                        expands: true,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Additional Notes (optional)',
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.maybePop(context),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: _confirmCreate,
                            child: const Text('Confirm Booking')),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ Helper header ------------------------------ */

class _HelperHeader extends StatelessWidget {
  final String helperId;

  final String fallbackName;
  final String fallbackFaculty;
  final String fallbackEmail;
  final int fallbackSessions;
  final String fallbackPhotoUrl;
  final List<String> specializes;

  const _HelperHeader({
    required this.helperId,
    required this.fallbackName,
    required this.fallbackFaculty,
    required this.fallbackEmail,
    required this.fallbackSessions,
    required this.fallbackPhotoUrl,
    required this.specializes,
  });

  Future<(String name, String facultyTitle, String email, int completedCount,
  String photoUrl)> _load() async {
    // Fallbacks
    String name = fallbackName;
    String facultyTitle = fallbackFaculty;
    String email = fallbackEmail;
    String photoUrl = fallbackPhotoUrl;
    int completedCount = fallbackSessions;

    if (helperId.isEmpty) {
      return (name, facultyTitle, email, completedCount, photoUrl);
    }

    final usersCol = FirebaseFirestore.instance.collection('users');
    final facCol = FirebaseFirestore.instance.collection('faculties');
    final appsCol = FirebaseFirestore.instance.collection('appointments');

    String pick(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      final profile = m['profile'];
      if (profile is Map<String, dynamic>) {
        for (final k in keys) {
          final v = profile[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
      return '';
    }

    try {
      final uSnap = await usersCol.doc(helperId).get();
      final um = uSnap.data() ?? {};

      final pickedName = pick(
          um, ['fullName', 'full_name', 'name', 'displayName', 'display_name']);
      if (pickedName.isNotEmpty) name = pickedName;

      final pickedEmail = pick(um, ['email', 'emailAddress']);
      if (pickedEmail.isNotEmpty) email = pickedEmail;

      final pickedPhoto =
      (um['photoUrl'] ?? um['avatarUrl'] ?? '').toString().trim();
      if (pickedPhoto.isNotEmpty) photoUrl = pickedPhoto;

      // Resolve faculty title
      final facultyId = (um['facultyId'] ?? '').toString();
      if (facultyId.isNotEmpty) {
        final facSnap = await facCol.doc(facultyId).get();
        final fm = facSnap.data() ?? {};
        final t = (fm['title'] ?? fm['name'] ?? '').toString().trim();
        if (t.isNotEmpty) facultyTitle = t;
      }

      // Completed sessions count (index-free) — kept as fallback boot number
      final aSnap =
      await appsCol.where('helperId', isEqualTo: helperId).get();
      completedCount = aSnap.docs.where((d) {
        final status =
        (d.data()['status'] ?? '').toString().toLowerCase().trim();
        return status == 'completed';
      }).length;
    } catch (_) {
      // keep fallbacks
    }

    return (name, facultyTitle, email, completedCount, photoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<
        (String name, String facultyTitle, String email, int completedCount,
        String photoUrl)>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _helperShell(
            t: t,
            helperId: helperId,
            name: fallbackName,
            faculty: fallbackFaculty,
            email: fallbackEmail,
            sessionsFallback: fallbackSessions,
            photoUrl: fallbackPhotoUrl,
            specializes: specializes,
          );
        }

        final data = snap.data ??
            (fallbackName, fallbackFaculty, fallbackEmail, fallbackSessions,
            fallbackPhotoUrl);

        return _helperShell(
          t: t,
          helperId: helperId,
          name: data.$1,
          faculty: data.$2,
          email: data.$3,
          sessionsFallback: data.$4,
          photoUrl: data.$5,
          specializes: specializes,
        );
      },
    );
  }

  Widget _helperShell({
    required TextTheme t,
    required String helperId, // stream uses this
    required String name,
    required String faculty,
    required String email,
    required int sessionsFallback,
    required String photoUrl,
    required List<String> specializes,
  }) {
    // COUNT ACTIVE APPOINTMENTS (pending/confirmed/completed) FOR THIS HELPER
    final sessionsCounter =
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: (helperId.isEmpty)
          ? const Stream.empty()
          : FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperId)
          .snapshots(),
      builder: (context, snap) {
        int count = sessionsFallback; // fallback while loading
        if (snap.hasData) {
          count = 0;
          for (final d in snap.data!.docs) {
            final status = (d.data()['status'] ?? '')
                .toString()
                .toLowerCase()
                .trim();
            if (status == 'cancelled') continue;
            // count pending, confirmed, completed
            count++;
          }
        }
        return Text(
          '$count\nsessions',
          textAlign: TextAlign.center,
          style: t.labelSmall,
        );
      },
    );

    final avatar = Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey.shade300,
          backgroundImage:
          (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
          child: (photoUrl.isEmpty)
              ? const Icon(Icons.person, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 6),
        sessionsCounter,
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(faculty.isEmpty ? '—' : faculty, style: t.bodySmall),
        Text(email.isEmpty ? '—' : email, style: t.bodySmall),
        const SizedBox(height: 6),
        _SpecializeLine(items: specializes),
        const SizedBox(height: 4),
        Text('Bio: N/A', style: t.bodySmall),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (context, c) {
        final tight = c.maxWidth < 360;
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(child: info),
              ]),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(child: info),
          ],
        );
      }),
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

class _StudentHeader extends StatelessWidget {
  const _StudentHeader();

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
        // back
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
          child: Text(
            'PEERS',
            style: t.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Student',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // logout button (replaces profile circle)
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

class _Chip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(.3)),
      ),
      child:
      Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _FieldShell extends StatelessWidget {
  final Widget child;
  const _FieldShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: child,
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
