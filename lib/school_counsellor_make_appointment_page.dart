// lib/school_counsellor_make_appointment_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'services/email_notification_service.dart';
class SchoolCounsellorMakeAppointmentPage extends StatefulWidget {
  const SchoolCounsellorMakeAppointmentPage({super.key});

  @override
  State<SchoolCounsellorMakeAppointmentPage> createState() =>
      _SchoolCounsellorMakeAppointmentPageState();
}

class _SchoolCounsellorMakeAppointmentPageState
    extends State<SchoolCounsellorMakeAppointmentPage> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _sessionType;

  String _mode = 'online'; // 'online' | 'physical'
  String? _venue; // only when _mode == 'physical'
  final List<String> _venueOptions = const [
    'Counselling Room A',
    'Counselling Room B',
    'Student Centre',
    'Library - Discussion Room',
  ];

  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  DateTime _combine(DateTime date, TimeOfDay tod) =>
      DateTime(date.year, date.month, date.day, tod.hour, tod.minute);

  DateTime _ceilToQuarter(DateTime dt) {
    final add = (15 - (dt.minute % 15)) % 15;
    final rounded = DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute + add);
    return rounded.isAfter(dt) ? rounded : rounded.add(const Duration(minutes: 15));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        if (_isToday(picked)) {
          final ceil = _ceilToQuarter(DateTime.now());
          _startTime ??= TimeOfDay(hour: ceil.hour, minute: ceil.minute);
          if (_endTime != null) {
            final startDT = _combine(picked, _startTime!);
            final endDT = _combine(picked, _endTime!);
            if (!endDT.isAfter(startDT)) {
              final bumped = startDT.add(const Duration(minutes: 30));
              _endTime = TimeOfDay(hour: bumped.hour, minute: bumped.minute);
            }
          }
        }
      });
    }
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  TimeOfDay _initialTimeFor(bool isStart) {
    final now = DateTime.now();
    if (_date != null && _isToday(_date!)) {
      final ceil = _ceilToQuarter(now);
      final t = TimeOfDay(hour: ceil.hour, minute: ceil.minute);
      if (isStart) return _startTime ?? t;
      return _endTime ?? TimeOfDay(hour: t.hour, minute: (t.minute + 30) % 60);
    }
    return (isStart ? _startTime : _endTime) ?? TimeOfDay.now();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _initialTimeFor(isStart),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
          if (_date != null && _endTime != null) {
            final start = _combine(_date!, _startTime!);
            final end = _combine(_date!, _endTime!);
            if (!end.isAfter(start)) {
              final bumped = start.add(const Duration(minutes: 30));
              _endTime = TimeOfDay(hour: bumped.hour, minute: bumped.minute);
            }
          }
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));


  Future<bool> _hasOverlap({
    required String helperId,
    required DateTime startDt,
    required DateTime endDt,
  }) async {
    final col = FirebaseFirestore.instance.collection('appointments');
    final snap = await col.where('helperId', isEqualTo: helperId).limit(500).get();

    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString().toLowerCase().trim();
      if (status != 'pending' && status != 'confirmed') continue;

      final tsStart = data['startAt'];
      final tsEnd = data['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue; // <-- fixed

      final existingStart = tsStart.toDate();
      final existingEnd = tsEnd.toDate();
      final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }


  Future<void> _book() async {
    if (_saving) return;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final helperId =
    (args['userId'] ?? args['helperId'] ?? args['tutorId'] ?? '').toString();

    if (_date == null || _startTime == null || _endTime == null) {
      _msg('Please select date and time.');
      return;
    }
    if (_sessionType == null) {
      _msg('Please choose a session type.');
      return;
    }
    if (_mode == 'physical' && (_venue == null || _venue!.trim().isEmpty)) {
      _msg('Please select a venue for a physical session.');
      return;
    }
    if (helperId.isEmpty) {
      _msg('Missing counsellor information.');
      return;
    }

    final startDt = _combine(_date!, _startTime!);
    final endDt = _combine(_date!, _endTime!);
    if (!endDt.isAfter(startDt)) {
      _msg('End time must be after start time.');
      return;
    }
    if (!startDt.isAfter(DateTime.now())) {
      _msg('Selected time is in the past. Please choose a future time.');
      return;
    }

    final scUser = FirebaseAuth.instance.currentUser;
    if (scUser == null) {
      _msg('You must be signed in.');
      return;
    }

    try {
      setState(() => _saving = true);

      final conflict = await _hasOverlap(
        helperId: helperId,
        startDt: startDt,
        endDt: endDt,
      );
      if (conflict) {
        setState(() => _saving = false);
        _msg('That time overlaps with another appointment for this counsellor.');
        return;
      }

      // Fetch school counsellor details for the booking
      final scUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(scUser.uid)
          .get();
      final scData = scUserDoc.data() ?? {};

      // Extract booker name
      String bookerName = 'School Counsellor';
      for (final k in const ['fullName', 'full_name', 'name', 'displayName', 'display_name']) {
        final v = scData[k];
        if (v is String && v.trim().isNotEmpty) {
          bookerName = v.trim();
          break;
        }
      }

      // Extract booker faculty
      String? bookerFacultyId;
      final facultyId = scData['facultyId'] ?? scData['faculty_id'] ?? scData['faculty'];
      if (facultyId is String && facultyId.trim().isNotEmpty) {
        bookerFacultyId = facultyId.trim();
      }

      // Fetch helper details
      final helperDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(helperId)
          .get();
      final helperData = helperDoc.data() ?? {};

      String helperName = 'Peer Counsellor';
      for (final k in const ['fullName', 'full_name', 'name', 'displayName', 'display_name']) {
        final v = helperData[k];
        if (v is String && v.trim().isNotEmpty) {
          helperName = v.trim();
          break;
        }
      }

      String? helperFacultyId;
      final hFacultyId = helperData['facultyId'] ?? helperData['faculty_id'] ?? helperData['faculty'];
      if (hFacultyId is String && hFacultyId.trim().isNotEmpty) {
        helperFacultyId = hFacultyId.trim();
      }

      final now = DateTime.now();
      final location =
      _mode == 'online' ? 'Online (Video Call)' : (_venue ?? 'Campus');

      final appt = <String, dynamic>{
        // Booker (School Counsellor) details - matching HOP-Peer Tutor schema
        'bookerId': scUser.uid,
        'bookerName': bookerName,
        'bookerRole': 'school_counsellor',
        if (bookerFacultyId != null) 'bookerFacultyId': bookerFacultyId,

        // Helper (Peer Counsellor) details
        'helperId': helperId,
        'helperName': helperName,
        'helperRole': 'peer_counsellor',
        if (helperFacultyId != null) 'helperFacultyId': helperFacultyId,

        // Legacy field for backward compatibility
        'schoolCounsellorId': scUser.uid,

        // Times
        'start': Timestamp.fromDate(startDt),
        'end': Timestamp.fromDate(endDt),
        'startAt': Timestamp.fromDate(startDt),  // Keep for backward compatibility
        'endAt': Timestamp.fromDate(endDt),      // Keep for backward compatibility

        // Meta
        'sessionType': _sessionType,
        'mode': _mode,
        'venue': _mode == 'physical' ? _venue : null,
        'location': location,
        'notes': _notesCtrl.text.trim(),
        'status': 'pending',
        'createdByRole': 'school_counsellor',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await FirebaseFirestore.instance.collection('appointments').add(appt);

      // Send email notification to peer counsellor about new appointment request
      try {
        final counsellorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(helperId)
            .get();

        final counsellorData = counsellorDoc.data();
        if (counsellorData != null) {
          final counsellorEmail = counsellorData['email'] ?? '';
          final counsellorName = counsellorData['fullName'] ?? counsellorData['name'] ?? 'Counsellor';

          final currentScUser = FirebaseAuth.instance.currentUser;
          final scDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentScUser?.uid ?? '')
              .get();

          final scData = scDoc.data();
          final scName = scData?['fullName'] ?? scData?['name'] ?? 'School Counsellor';

          if (counsellorEmail.isNotEmpty) {
            await EmailNotificationService.sendNewAppointmentToPeer(
              peerEmail: counsellorEmail,
              peerName: counsellorName,
              studentName: scName,
              studentRole: 'School Counsellor',
              appointmentDate: _fmtDate(_date!),
              appointmentTime: '${_fmtTime(_startTime!)} - ${_fmtTime(_endTime!)}',
              purpose: _sessionType ?? 'Not specified',
            );
          }
        }
      } catch (emailError) {
        debugPrint('Failed to send email notification: $emailError');
        // Don't fail the booking if email fails
      }

      if (!mounted) return;
      _msg('Booked successfully.');
      setState(() => _saving = false);
      Navigator.pushNamedAndRemoveUntil(context, '/counsellor/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _msg('Booking failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final helperId =
    (args['userId'] ?? args['helperId'] ?? args['tutorId'] ?? '').toString();
    final name = (args['name'] ?? args['tutorName'] ?? '—').toString();
    final specializes = switch (args['specializes']) {
      List l => l.map((e) => e.toString()).toList(),
      _ => const <String>[],
    };

    final match = (args['match'] as String?) ?? 'Best Match';
    final (chipBg, chipFg) = switch (match.toLowerCase()) {
      'best match' => (const Color(0xFFC9F2D9), const Color(0xFF1B5E20)),
      'good match' => (const Color(0xFFFCE8C1), const Color(0xFF6D4C00)),
      _ => (const Color(0xFFE4E6EB), const Color(0xFF424242)),
    };

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SCHeader(),
                  const SizedBox(height: 16),

                  Text('Make an Appointment',
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Book with selected counsellor', style: t.bodySmall),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDE6FF), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.05),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HelperHeader(
                          helperId: helperId,
                          fallbackName: name,
                          fallbackFaculty: '—',
                          fallbackEmail: '—',
                          fallbackSessions: 0,
                          fallbackPhotoUrl: '',
                          specializes: specializes,
                          trailing: _Chip(label: match, bg: chipBg, fg: chipFg),
                        ),
                        const SizedBox(height: 12),

                        // Date
                        _FieldShell(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _date == null ? 'Date' : _fmtDate(_date!),
                                  style: t.bodyMedium?.copyWith(
                                    color: _date == null ? Colors.black54 : Colors.black,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_month_outlined),
                                tooltip: 'Pick date',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Times
                        LayoutBuilder(builder: (context, c) {
                          final tight = c.maxWidth < 360;

                          final fromField = _FieldShell(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _startTime == null ? 'Time' : _fmtTime(_startTime!),
                                    style: t.bodyMedium?.copyWith(
                                      color: _startTime == null ? Colors.black54 : Colors.black,
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
                                    _endTime == null ? 'Time' : _fmtTime(_endTime!),
                                    style: t.bodyMedium?.copyWith(
                                      color: _endTime == null ? Colors.black54 : Colors.black,
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
                                child: Text('to'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: toField),
                            ],
                          );
                        }),
                        const SizedBox(height: 8),

                        // Session type (counsellor-management themed)
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButton<String>(
                            value: _sessionType,
                            isExpanded: true,
                            underline: const SizedBox(),
                            hint: const Text('Session Type'),
                            items: const [
                              DropdownMenuItem(
                                value: 'Supervision',
                                child: Text('Supervision'),
                              ),
                              DropdownMenuItem(
                                value: 'Case Review',
                                child: Text('Case Review'),
                              ),
                              DropdownMenuItem(
                                value: 'Training / Coaching',
                                child: Text('Training / Coaching'),
                              ),
                              DropdownMenuItem(
                                value: 'General Check-in',
                                child: Text('General Check-in'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _sessionType = v),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Mode
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButton<String>(
                            value: (_mode == 'online' || _mode == 'physical') ? _mode : 'online',
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'online', child: Text('Online')),
                              DropdownMenuItem(value: 'physical', child: Text('Physical')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _mode = v;
                                if (_mode == 'online') _venue = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Venue (only for physical)
                        if (_mode == 'physical')
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: DropdownButton<String>(
                              value: _venue,
                              isExpanded: true,
                              underline: const SizedBox(),
                              hint: const Text('Select Venue'),
                              items: _venueOptions
                                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => setState(() => _venue = v),
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Notes
                        Container(
                          height: 150,
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

                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB9C85B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                              elevation: 0,
                            ),
                            onPressed: _saving ? null : _book,
                            child: Text(_saving ? 'Booking…' : 'Book'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_saving)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(.05),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ Header (SC) ------------------------------ */

class _SCHeader extends StatelessWidget {
  const _SCHeader();

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
              Text('School Counsellor', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              Text('Portal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 8),
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

/* ----------------------- Dynamic helper header widget ---------------------- */

class _HelperHeader extends StatelessWidget {
  final String helperId;

  final String fallbackName;
  final String fallbackFaculty;
  final String fallbackEmail;
  final int fallbackSessions;
  final String fallbackPhotoUrl;
  final List<String> specializes;

  final Widget? trailing; // e.g., match chip

  const _HelperHeader({
    required this.helperId,
    required this.fallbackName,
    required this.fallbackFaculty,
    required this.fallbackEmail,
    required this.fallbackSessions,
    required this.fallbackPhotoUrl,
    required this.specializes,
    this.trailing,
  });

  String _pickString(Map<String, dynamic> m, List<String> keys) {
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

  Future<(String name, String facultyTitle, String email, String photoUrl)> _loadBasics() async {
    String name = fallbackName;
    String facTitle = fallbackFaculty;
    String email = fallbackEmail;
    String photoUrl = fallbackPhotoUrl;

    if (helperId.isEmpty) return (name, facTitle, email, photoUrl);

    final usersCol = FirebaseFirestore.instance.collection('users');
    final facCol = FirebaseFirestore.instance.collection('faculties');

    try {
      final uSnap = await usersCol.doc(helperId).get();
      final u = uSnap.data() ?? {};

      final pickedName = _pickString(u, ['fullName','full_name','name','displayName','display_name']);
      if (pickedName.isNotEmpty) name = pickedName;

      final pickedEmail = _pickString(u, ['email','emailAddress']);
      if (pickedEmail.isNotEmpty) email = pickedEmail;

      for (final k in const ['photoURL','photoUrl','avatarUrl','avatar']) {
        final v = u[k];
        if (v is String && v.trim().isNotEmpty) { photoUrl = v.trim(); break; }
      }
      if (photoUrl.isEmpty && u['profile'] is Map<String, dynamic>) {
        final prof = u['profile'] as Map<String, dynamic>;
        for (final k in const ['photoURL','photoUrl','avatarUrl','avatar']) {
          final v = prof[k];
          if (v is String && v.trim().isNotEmpty) { photoUrl = v.trim(); break; }
        }
      }

      final facultyId = (u['facultyId'] ?? '').toString();
      if (facultyId.isNotEmpty) {
        final fSnap = await facCol.doc(facultyId).get();
        final fm = fSnap.data() ?? {};
        final t = (fm['title'] ?? fm['name'] ?? '').toString().trim();
        if (t.isNotEmpty) facTitle = t;
      }
    } catch (_) {}
    return (name, facTitle, email, photoUrl);
  }

  Future<List<String>> _interestTitlesByIds(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];
    final col = FirebaseFirestore.instance.collection('interests');
    final map = <String, String>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, math.min(i + 10, ids.length));
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        final title = (d.data()['title'] ?? '').toString().trim();
        if (title.isNotEmpty) map[d.id] = title;
      }
    }
    return ids.map((id) => map[id]).whereType<String>().toList();
  }

  // Try many shapes: IDs or titles from peer_applications, else fallback to users doc.
  Future<List<String>> _resolveSpecializes() async {
    // If caller already provided, use it.
    if (specializes.isNotEmpty) {
      return specializes.where((s) => s.trim().isNotEmpty).toSet().toList();
    }
    if (helperId.isEmpty) return const <String>[];

    // 1) From approved peer counsellor application (both spellings)
    final appsQ = await FirebaseFirestore.instance
        .collection('peer_applications')
        .where('userId', isEqualTo: helperId)
        .where('requestedRole', whereIn: ['peer_counsellor', 'peer_counselor'])
        .where('status', isEqualTo: 'approved')
    // keep the constraint if present; if the field is missing we still accept the doc
        .get();

    Map<String, dynamic>? app;
    for (final d in appsQ.docs) {
      final m = d.data();
      final scApproved = m['schoolCounsellorApproved'];
      if (scApproved == true || scApproved == null) { // accept true, and also accept if field absent
        app = m;
        break;
      }
    }

    Future<List<String>> titlesFromApp(Map<String, dynamic> m) async {
      // Plain titles list?
      if (m['specializes'] is List) {
        final titles = (m['specializes'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        if (titles.isNotEmpty) return titles.toSet().toList();
      }
      if (m['specializations'] is List) {
        final titles = (m['specializations'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        if (titles.isNotEmpty) return titles.toSet().toList();
      }
      // Interests as titles directly?
      if (m['interests'] is List && (m['interests'] as List).isNotEmpty) {
        final list = m['interests'] as List;
        // If list is List<String>
        if (list.isNotEmpty && list.first is String) {
          final titles = list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          if (titles.isNotEmpty) return titles.toSet().toList();
        }
        // If list is List<Map> with {title} or {id}
        final mapTitles = <String>[];
        final idCandidates = <String>[];
        for (final e in list) {
          if (e is Map) {
            final t = (e['title'] ?? '').toString().trim();
            if (t.isNotEmpty) mapTitles.add(t);
            final id = (e['id'] ?? '').toString().trim();
            if (id.isNotEmpty) idCandidates.add(id);
          }
        }
        if (mapTitles.isNotEmpty) return mapTitles.toSet().toList();
        if (idCandidates.isNotEmpty) {
          final resolved = await _interestTitlesByIds(idCandidates);
          if (resolved.isNotEmpty) return resolved.toSet().toList();
        }
      }

      // Interests by ID fields
      final idFields = [
        'interestsIds', 'interestIds',
        'counselingTopicIds', 'counsellingTopicIds',
        'topicIds'
      ];
      final ids = <String>[];
      for (final f in idFields) {
        final v = m[f];
        if (v is List) {
          ids.addAll(v.map((e) => e.toString()).where((s) => s.trim().isNotEmpty));
        }
      }
      return _interestTitlesByIds(ids.toSet().toList());
    }

    if (app != null) {
      final titles = await titlesFromApp(app!);
      if (titles.isNotEmpty) return titles;
    }

    // 2) Fallback to user doc fields
    final uSnap = await FirebaseFirestore.instance.collection('users').doc(helperId).get();
    final u = uSnap.data() ?? {};

    // Plain title fields that might be stored directly on the user:
    for (final k in const ['specializes', 'specializations', 'skills', 'tags']) {
      final v = u[k];
      if (v is List && v.isNotEmpty) {
        final titles = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        if (titles.isNotEmpty) return titles.toSet().toList();
      }
    }

    // ID fields on user
    final idCandidates = <String>{
      ...((u['counselingTopicIds'] is List) ? (u['counselingTopicIds'] as List).map((e) => e.toString()) : const <String>[]),
      ...((u['counsellingTopicIds'] is List) ? (u['counsellingTopicIds'] as List).map((e) => e.toString()) : const <String>[]),
      ...((u['academicInterestIds'] is List) ? (u['academicInterestIds'] as List).map((e) => e.toString()) : const <String>[]),
    }.where((s) => s.trim().isNotEmpty).toSet();

    if (idCandidates.isEmpty) return const <String>[];
    final resolved = await _interestTitlesByIds(idCandidates.toList());
    return resolved.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<(String, String, String, String)>(
      future: _loadBasics(),
      builder: (context, snap) {
        final data = snap.data ?? (fallbackName, fallbackFaculty, fallbackEmail, fallbackPhotoUrl);

        final avatar = Column(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: data.$4.isNotEmpty ? NetworkImage(data.$4) : null,
              child: data.$4.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
            ),
            const SizedBox(height: 6),
            _SessionsBadge(helperId: helperId, fallback: fallbackSessions),
          ],
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.$1, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(data.$2.isEmpty ? '—' : data.$2, style: t.bodySmall),
            Text(data.$3.isEmpty ? '—' : data.$3, style: t.bodySmall),
            const SizedBox(height: 6),
            FutureBuilder<List<String>>(
              future: _resolveSpecializes(),
              builder: (_, s) => _SpecializeLine(items: (s.data ?? const <String>[])),
            ),
            const SizedBox(height: 4),
            Text('Bio: N/A', style: t.bodySmall),
          ],
        );

        return LayoutBuilder(builder: (context, c) {
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
                if (trailing != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: trailing),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(child: info),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          );
        });
      },
    );
  }
}



/* ----------------------- Live sessions badge widget ----------------------- */

class _SessionsBadge extends StatelessWidget {
  final String helperId;
  final int fallback;
  const _SessionsBadge({required this.helperId, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (helperId.isEmpty) {
      return Text('$fallback\nsessions', textAlign: TextAlign.center, style: t.labelSmall);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('helperId', isEqualTo: helperId)
          .snapshots(),
      builder: (context, snap) {
        int count = fallback;
        if (snap.hasData) {
          count = 0;
          for (final d in snap.data!.docs) {
            final status = (d.data()['status'] ?? '').toString().toLowerCase().trim();
            if (status == 'cancelled') continue;
            count++;
          }
        }
        return Text('$count\nsessions', textAlign: TextAlign.center, style: t.labelSmall);
      },
    );
  }
}

/* -------------------------------- Widgets -------------------------------- */

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
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
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
    if (items.isEmpty) return Text('Specialize: —', style: t.bodySmall);

    final boldCount = items.length >= 2 ? 2 : items.length;
    final spans = <TextSpan>[TextSpan(text: 'Specialize: ', style: t.bodySmall)];
    for (var i = 0; i < items.length; i++) {
      final isBold = i < boldCount;
      spans.add(TextSpan(
        text: items[i],
        style: t.bodySmall?.copyWith(fontWeight: isBold ? FontWeight.w800 : FontWeight.w400),
      ));
      if (i != items.length - 1) spans.add(TextSpan(text: ', ', style: t.bodySmall));
    }
    return Text.rich(TextSpan(children: spans));
  }
}