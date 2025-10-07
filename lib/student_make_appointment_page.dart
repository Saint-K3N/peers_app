// lib/student_make_appointment_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StudentMakeAppointmentPage extends StatefulWidget {
  const StudentMakeAppointmentPage({super.key});

  @override
  State<StudentMakeAppointmentPage> createState() =>
      _StudentMakeAppointmentPageState();
}

class _StudentMakeAppointmentPageState extends State<StudentMakeAppointmentPage> {
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _sessionType;

  // Mode + venue
  String _mode = 'online'; // 'online' | 'physical'
  String? _venue; // required if _mode == 'physical'
  final List<String> _venueOptions = const [
    'Campus - Level 3',
    'Campus - Level 5',
    'Library - Discussion Room',
    'Student Centre',
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
              _endTime = TimeOfDay(
                hour: _startTime!.hour,
                minute: (_startTime!.minute + 30) % 60,
              );
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
          if (_endTime != null) {
            final start = _combine(_date ?? DateTime.now(), _startTime!);
            final end = _combine(_date ?? DateTime.now(), _endTime!);
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
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status != 'pending' && status != 'confirmed') continue;

      final tsStart = data['startAt'];
      final tsEnd = data['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;

      final existingStart = tsStart.toDate();
      final existingEnd = tsEnd.toDate();

      final overlaps = existingStart.isBefore(endDt) && existingEnd.isAfter(startDt);
      if (overlaps) return true;
    }
    return false;
  }

  Future<void> _book() async {
    if (_saving) return;

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

    final startDt = _combine(_date!, _startTime!);
    final endDt = _combine(_date!, _endTime!);
    if (!endDt.isAfter(startDt)) {
      _msg('End time must be after start time.');
      return;
    }

    final now = DateTime.now();
    if (!startDt.isAfter(now)) {
      _msg('Selected time is in the past. Please choose a future time.');
      return;
    }

    final student = FirebaseAuth.instance.currentUser;
    if (student == null) {
      _msg('You must be signed in.');
      return;
    }

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    final helperId = (args['userId'] as String?) ?? '';
    if (helperId.isEmpty) {
      _msg('Missing helper information.');
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
        _msg('That time overlaps with another appointment for this helper.');
        return;
      }

      final location =
      _mode == 'online' ? 'Online (Google Meet)' : (_venue ?? 'Campus');

      final appt = <String, dynamic>{
        'studentId': student.uid,
        'helperId': helperId,
        'date': Timestamp.fromDate(DateTime(_date!.year, _date!.month, _date!.day)),
        'startAt': Timestamp.fromDate(startDt),
        'endAt': Timestamp.fromDate(endDt),
        'sessionType': _sessionType,
        'mode': _mode,
        'venue': _mode == 'physical' ? _venue : null,
        'location': location, // nice display string used by tiles
        'notes': _notesCtrl.text.trim(),
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await FirebaseFirestore.instance.collection('appointments').add(appt);

      if (!mounted) return;
      _msg('Booked successfully.');
      setState(() => _saving = false);

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/student/home',
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _msg('Booking failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final name = (args?['name'] as String?) ?? '—';
    final faculty = (args?['faculty'] as String?) ?? '—';
    final email = (args?['email'] as String?) ?? '—';
    final sessionsFallback = (args?['sessions'] as int?) ?? 0; // fallback only
    final match = (args?['match'] as String?) ?? 'Best Match';
    final specializes =
        (args?['specializes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
            const <String>[];
    final helperId = (args?['userId'] as String?) ?? '';

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
                  const _StudentHeader(),
                  const SizedBox(height: 16),

                  Text('Make an Appointment',
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Book with selected user', style: t.bodySmall),
                  const SizedBox(height: 12),

                  // Display card (header is now dynamic)
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
                          fallbackFaculty: faculty,
                          fallbackEmail: email,
                          fallbackSessions: sessionsFallback,
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

                        // Time range
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

                        // Session type
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
                                  value: 'Assignment Discussion',
                                  child: Text('Assignment Discussion')),
                              DropdownMenuItem(
                                  value: 'Study Strategy',
                                  child: Text('Study Strategy')),
                              DropdownMenuItem(
                                  value: 'Exam Revision',
                                  child: Text('Exam Revision')),
                              DropdownMenuItem(
                                  value: 'Q&A / Doubts',
                                  child: Text('Q&A / Doubts')),
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
                            value: _mode,
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
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 10),
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

/* ----------------------- Dynamic helper header widget ----------------------- */

class _HelperHeader extends StatelessWidget {
  final String helperId;

  final String fallbackName;
  final String fallbackFaculty;
  final String fallbackEmail;
  final int fallbackSessions;
  final String fallbackPhotoUrl;
  final List<String> specializes;

  final Widget? trailing; // e.g. match chip

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
            _SpecializeLine(items: specializes),
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
            if (status == 'cancelled') continue; // count pending/confirmed/completed
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

        // titles
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

        // logout (replaces profile circle)
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
