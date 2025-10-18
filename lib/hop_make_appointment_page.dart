// lib/hop_make_appointment_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class HopMakeAppointmentPage extends StatefulWidget {
  const HopMakeAppointmentPage({super.key});

  @override
  State<HopMakeAppointmentPage> createState() => _HopMakeAppointmentPageState();
}

// COMBINED STATE CLASS
class _HopMakeAppointmentPageState extends State<HopMakeAppointmentPage> {
  // OLD UI STATE
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _sessionType;
  String _mode = 'online'; // 'online' | 'physical'
  String? _venue; // only when _mode == 'physical'
  final List<String> _venueOptions = const [
    'Campus - Level 2 ',
    'Campus - Level 3 Cubicles',
    'Campus - Level 4 Cubicles',
    'Campus - Level 5 ',
    'Campus - Level 6 ',
    'Library - Discussion Room',
    'Campus - Rooftop',
    '',
  ];

  // NEW LOGIC STATE/CACHING
  bool _argsParsed = false;
  String? _appointmentId; //
  String _helperId = '';
  // Caching helper info for saving
  String _helperName = '';
  String _helperFacultyId = '';
  String _helperRole = ''; // Used to determine session types

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Fallbacks (for _HelperHeader in the build method)
  String _fbName = '—';
  List<String> _fbSpecializes = const <String>[];

  // Session types (depend on helper role, from new logic)
  final List<String> _tutorSessionTypes = const [
    'Assignment Discussion', 'Study Strategy', 'Exam Revision', 'Q&A / Doubts'
  ];
  final List<String> _counsellorSessionTypes = const [
    'Stress & Anxiety Management', 'Academic Pressure', 'Personal Growth', 'Relationship Advice'
  ];
  List<String> get _sessionTypeOptions => _helperRole == 'peer_counsellor'
      ? _counsellorSessionTypes : _tutorSessionTypes;

  // OLD UI: Controller for notes
  final _notesCtrl = TextEditingController();
  bool _saving = false;


  /* ---------------------- NEW LOGIC: DID CHANGED DEPENDENCIES --------------------- */

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsParsed) return;
    _argsParsed = true;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    _appointmentId = (args['appointmentId'] as String?);
    _helperId = (args['tutorId'] ?? args['helperId'] ?? args['userId'] ?? '').toString();

    // Set fallbacks for the UI (from old code's args parsing)
    _fbName = (args['tutorName'] ?? args['name'] ?? '—').toString();
    _fbSpecializes = switch (args['specializes']) {
      List l => l.map((e) => e.toString()).toList(),
      _ => const <String>[],
    };

    // If editing, load existing data
    if (_appointmentId != null && _appointmentId!.isNotEmpty) {
      _loadExistingData(_appointmentId!);
    }
  }

  // NEW LOGIC: Load appointment data when editing
  Future<void> _loadExistingData(String id) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('appointments').doc(id).get();
      if (!snap.exists) return;

      final m = snap.data() ?? {};
      // Note: New schema uses 'start'/'end', old one used 'startAt'/'endAt'
      final start = (m['start'] as Timestamp?)?.toDate();
      final end = (m['end'] as Timestamp?)?.toDate();

      setState(() {
        _helperId = (m['helperId'] ?? '').toString();
        _sessionType = (m['sessionType'] as String?);
        _mode = (m['mode'] as String?) ?? 'online';
        _venue = (m['venue'] as String?);
        _notesCtrl.text = (m['notes'] as String?) ?? '';

        if (start != null) {
          _date = start;
          _startTime = TimeOfDay.fromDateTime(start);
        }
        if (end != null) {
          _endTime = TimeOfDay.fromDateTime(end);
        }
      });
    } catch (e) {
      debugPrint('Error loading appointment: $e');
    }
  }

  // NEW LOGIC: Helper to get HOP's name, role, and faculty from the 'users' collection
  Future<Map<String, String>> _getBookerInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return {'name': 'HOP User', 'role': 'hop', 'facultyId': ''};
    // Prioritize display name fields
    String name = 'HOP User', role = 'hop', facultyId = '';

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      name = (data['fullName'] ?? data['name'] ?? data['displayName'] ?? 'HOP User').toString();
      role = (data['role'] ?? 'hop').toString();
      facultyId = (data['facultyId'] ?? '').toString();

      // Normalize role for data saving (keep the new simpler role for data model)
      if (role.toLowerCase().trim() == 'head of program') role = 'hop';

    } catch (e) {
      debugPrint('Error fetching booker info: $e');
    }
    return {'name': name, 'role': role, 'facultyId': facultyId};
  }


  /* -------------------------- OLD UI HELPER METHODS ------------------------- */

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


  /* ------------------- COMBINED LOGIC: DATE/TIME PICKERS ------------------ */

  // Uses OLD UI logic for initial time calculation
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
        // The complex time validation logic from old code is retained here
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

  // Uses OLD UI logic for initial time calculation
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


  /* ----------------------- NEW LOGIC: SUBMIT FUNCTION ----------------------- */

  // Removed the OLD _hasOverlap check (as it wasn't in the new logic)
  void _msg(String m, {bool success = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: success ? Colors.green : Colors.red,
      ));

  Future<void> _submit() async {
    if (_saving) return;

    if (_date == null || _startTime == null || _endTime == null) {
      _msg('Please select date and time.');
      return;
    }
    // Uses new logic: check against role-based options
    if (_sessionType == null || !_sessionTypeOptions.contains(_sessionType)) {
      _msg('Please choose a valid session type.');
      return;
    }
    if (_mode == 'physical' && (_venue == null || _venue!.trim().isEmpty)) {
      _msg('Please select a venue for a physical session.');
      return;
    }
    if (_helperId.isEmpty) {
      _msg('Missing helper information.');
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

    final hopUser = FirebaseAuth.instance.currentUser;
    if (hopUser == null) {
      _msg('You must be signed in.');
      return;
    }

    try {
      setState(() => _saving = true);

      // No overlap check as it was missing from the new code, but retaining the old structure
      // final conflict = await _hasOverlap(...) // <- Omitted

      final bookerInfo = await _getBookerInfo(); // <-- FETCH HOP INFO

      // Use the cached helper info (resolved in the build method's StreamBuilder)
      final location =
      _mode == 'online' ? 'Online (Google Meet)' : (_venue?.trim() ?? 'Campus');

      final appt = <String, dynamic>{
        // NEW: Booker/HOP details for Peer Tutor display
        'bookerId': hopUser.uid,
        'bookerName': bookerInfo['name'],
        'bookerRole': bookerInfo['role'], // 'hop'
        'bookerFacultyId': bookerInfo['facultyId'],

        // Helper details (cached from StreamBuilder or args)
        'helperId': _helperId,
        'helperName': _helperName,
        'helperRole': _helperRole,
        'helperFacultyId': _helperFacultyId,

        // Datetimes (using the new schema keys: 'start', 'end')
        'start': Timestamp.fromDate(startDt),
        'end': Timestamp.fromDate(endDt),

        // Meta
        'sessionType': _sessionType,
        'mode': _mode,
        // Using the OLD UI field for venue
        'venue': _mode == 'physical' ? _venue?.trim() : null,
        'location': location,
        'notes': _notesCtrl.text.trim(),
        'status': 'pending', // NEW LOGIC: always pending
        'createdByRole': 'hop',
        'createdAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance.collection('appointments');

      if (_appointmentId != null) {
        await col.doc(_appointmentId!).update(appt);
      } else {
        await col.add(appt);
      }


      if (!mounted) return;
      _msg(_appointmentId == null ? 'Booked successfully.' : 'Updated successfully.', success: true);
      setState(() => _saving = false);

      Navigator.pushNamedAndRemoveUntil(context, '/hop/home', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _msg('Booking failed: $e');
    }
  }

  /* ---------------------------- COMBINED BUILD METHOD --------------------------- */

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // OLD UI ARG PARSING (for display)
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final helperId = _helperId; // Use the parsed/loaded ID
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
                  const _HopHeader(), // OLD UI: Header
                  const SizedBox(height: 16),

                  Text(
                    _appointmentId == null ? 'Make an Appointment' : 'Reschedule Appointment',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Book with selected user', style: t.bodySmall),
                  const SizedBox(height: 12),

                  // OLD UI: Helper Card Container
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
                        // OLD UI: _HelperHeader combined with NEW LOGIC caching
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: helperId.isEmpty
                              ? null
                              : FirebaseFirestore.instance.collection('users').doc(helperId).snapshots(),
                          builder: (context, snap) {
                            if (snap.hasData) {
                              final d = snap.data?.data() ?? {};
                              // CACHING FOR SUBMIT
                              _helperRole = (d['role'] ?? _helperRole).toString();
                              _helperName = (d['fullName'] ?? d['name'] ?? _fbName).toString();
                              _helperFacultyId = (d['facultyId'] ?? '').toString();
                            }

                            return _HelperHeader(
                              helperId: helperId,
                              fallbackName: _fbName,
                              fallbackFaculty: '—',
                              fallbackEmail: '—',
                              fallbackSessions: 0,
                              fallbackPhotoUrl: '',
                              specializes: _fbSpecializes, // <- from Navigator args/fallbacks
                              trailing: _Chip(label: match, bg: chipBg, fg: chipFg),
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Date (OLD UI)
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

                        // Times (OLD UI)
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

                        // Session type (OLD UI with NEW LOGIC options)
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButton<String>(
                            value: _sessionType, // null until picked
                            isExpanded: true,
                            underline: const SizedBox(),
                            hint: const Text('Session Type'),
                            // Dynamically uses the session types based on helper role
                            items: _sessionTypeOptions.map((type) =>
                                DropdownMenuItem(value: type, child: Text(type))
                            ).toList(),
                            onChanged: (v) => setState(() => _sessionType = v),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Mode (OLD UI)
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

                        // Venue (only for physical, OLD UI)
                        if (_mode == 'physical')
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: DropdownButton<String>(
                              value: _venue, // keep null until selected
                              isExpanded: true,
                              underline: const SizedBox(),
                              hint: const Text('Select Venue'),
                              // Retains the old venue list, including the empty string option
                              items: _venueOptions
                                  .map((v) => DropdownMenuItem(
                                  value: v.isEmpty ? ' ' : v, // Use ' ' for empty string value
                                  child: Text(v.isEmpty ? 'Other (Please specify)' : v))
                              )
                                  .toList(),
                              onChanged: (v) => setState(() => _venue = v),
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Notes (OLD UI)
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

                        // Submit Button (OLD UI with NEW LOGIC text)
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
                            onPressed: _saving ? null : _submit,
                            child: Text(
                              _saving
                                  ? 'Booking…'
                                  : (_appointmentId == null ? 'Book' : 'Save Changes'),
                            ),
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

/* ------------------------------ Header (HOP) ------------------------------ */

class _HopHeader extends StatelessWidget {
  const _HopHeader();

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      // Assuming '/login' is the route for the login page
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
              Text('HOP', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
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

  Future<(String name, String facultyTitle, String email, String photoUrl)>
  _load() async {
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

      final pickedName =
      _pickString(u, ['fullName', 'full_name', 'name', 'displayName', 'display_name']);
      if (pickedName.isNotEmpty) name = pickedName;

      final pickedEmail = _pickString(u, ['email', 'emailAddress']);
      if (pickedEmail.isNotEmpty) email = pickedEmail;

      // photo
      final possiblePhotoKeys = ['photoURL', 'photoUrl', 'avatarUrl', 'avatar'];
      for (final k in possiblePhotoKeys) {
        final v = u[k];
        if (v is String && v.trim().isNotEmpty) {
          photoUrl = v.trim();
          break;
        }
      }
      if (photoUrl.isEmpty && u['profile'] is Map<String, dynamic>) {
        final prof = u['profile'] as Map<String, dynamic>;
        for (final k in possiblePhotoKeys) {
          final v = prof[k];
          if (v is String && v.trim().isNotEmpty) {
            photoUrl = v.trim();
            break;
          }
        }
      }

      // faculty title
      final facultyId = (u['facultyId'] ?? '').toString();
      if (facultyId.isNotEmpty) {
        final fSnap = await facCol.doc(facultyId).get();
        final fm = fSnap.data() ?? {};
        final t = (fm['title'] ?? fm['name'] ?? '').toString().trim();
        if (t.isNotEmpty) facTitle = t;
      }
    } catch (_) {
      // keep fallbacks
    }

    return (name, facTitle, email, photoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FutureBuilder<(String, String, String, String)>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data ??
            (fallbackName, fallbackFaculty, fallbackEmail, fallbackPhotoUrl);

        final avatar = Column(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: data.$4.isNotEmpty ? NetworkImage(data.$4) : null,
              child: data.$4.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            _SessionsBadge(helperId: helperId, fallback: fallbackSessions),
          ],
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.$1,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(data.$2.isEmpty ? '—' : data.$2, style: t.bodySmall),
            Text(data.$3.isEmpty ? '—' : data.$3, style: t.bodySmall),
            const SizedBox(height: 6),
            _SpecializeLine(items: specializes), // <- uses passed list directly
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
      return Text('$fallback\nsessions',
          textAlign: TextAlign.center, style: t.labelSmall);
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
            final status =
            (d.data()['status'] ?? '').toString().toLowerCase().trim();
            if (status == 'cancelled') continue;
            count++;
          }
        }
        return Text('$count\nsessions',
            textAlign: TextAlign.center, style: t.labelSmall);
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
      child: Text(label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
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
    if (items.isEmpty) {
      return Text('Specialize: —', style: t.bodySmall);
    }
    final boldCount = items.length >= 2 ? 2 : items.length;

    final spans = <TextSpan>[
      TextSpan(text: 'Specialize: ', style: t.bodySmall),
    ];
    for (var i = 0; i < items.length; i++) {
      final isBold = i < boldCount;
      spans.add(TextSpan(
        text: items[i],
        style: t.bodySmall?.copyWith(
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
        ),
      ));
      if (i != items.length - 1) {
        spans.add(TextSpan(text: ', ', style: t.bodySmall));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}