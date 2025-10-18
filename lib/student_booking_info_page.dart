// lib/student_booking_info_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class StudentBookingInfoPage extends StatefulWidget {
  const StudentBookingInfoPage({super.key});

  @override
  State<StudentBookingInfoPage> createState() => _StudentBookingInfoPageState();
}

class _StudentBookingInfoPageState extends State<StudentBookingInfoPage> {
  final _notesCtrl = TextEditingController(text: 'Meet me at a cubicle on Level 3');

  bool _argsParsed = false;
  String? _appointmentId;
  String _helperId = '';

  String _fbName = '—', _fbFaculty = '—', _fbEmail = '—', _fbBio = '';
  int _fbSessions = 0;
  List<String> _fbSpecializes = const <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsParsed) return;
    _argsParsed = true;

    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    _appointmentId = (args['appointmentId'] as String?);
    _helperId = (args['userId'] as String?) ?? (args['helperId'] as String?) ?? _helperId;
    _fbName = (args['name'] as String?) ?? _fbName;
    _fbFaculty = (args['faculty'] as String?) ?? _fbFaculty;
    _fbEmail = (args['email'] as String?) ?? _fbEmail;
    _fbBio = (args['bio'] as String?) ?? _fbBio;
    _fbSessions = (args['sessions'] as int?) ?? _fbSessions;
    _fbSpecializes = (args['specializes'] as List<String>?) ?? _fbSpecializes;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    // Note: Timestamps are stored in UTC. .toDate() converts them to the device's local time.
    // To display in GMT+8, the device's timezone should be set to Kuala Lumpur time.
    return DateFormat('dd/MM/yyyy').format(d);
  }

  String _fmtTime(TimeOfDay t) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    return DateFormat.jm().format(dt);
  }

  Future<void> _cancelWithReason(String appointmentId, DateTime startAt) async {
    final now = DateTime.now();
    final isWithin24Hours = startAt.difference(now) < const Duration(hours: 24);

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(isWithin24Hours: isWithin24Hours),
    );

    if (reason != null && reason.isNotEmpty && mounted) {
      try {
        await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).update({
          'status': 'cancelled',
          'cancellationReason': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
        Navigator.maybePop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
      }
    }
  }

  Future<void> _rescheduleWithReason(
      BuildContext context, {
        required String apptId, required String helperId,
        required DateTime currentStart, required DateTime currentEnd,
      }) async {
    if (currentStart.difference(DateTime.now()) < const Duration(hours: 24)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reschedule not allowed within 24 hours.')));
      }
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RescheduleDialog(currentStart: currentStart, currentEnd: currentEnd),
    );

    if (result == null || !mounted) return;

    final DateTime newStart = result['start'];
    final DateTime newEnd = result['end'];
    final String reason = result['reason'];

    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required to reschedule.')));
      return;
    }

    if (await _hasOverlap(helperId: helperId, startDt: newStart, endDt: newEnd, excludeId: apptId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflicts with another booking.')));
      }
      return;
    }

    await FirebaseFirestore.instance.collection('appointments').doc(apptId).update({
      'startAt': Timestamp.fromDate(newStart),
      'endAt': Timestamp.fromDate(newEnd),
      'rescheduleReason': reason,
      'previousStartAt': Timestamp.fromDate(currentStart),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescheduled successfully.')));
    }
  }

  Future<bool> _hasOverlap({required String helperId, required DateTime startDt, required DateTime endDt, String? excludeId}) async {
    final snap = await FirebaseFirestore.instance.collection('appointments').where('helperId', isEqualTo: helperId).get();
    for (final d in snap.docs) {
      if (excludeId != null && d.id == excludeId) continue;
      final m = d.data();
      final status = (m['status'] ?? '').toString().toLowerCase();
      if (status != 'pending' && status != 'confirmed') continue;
      final tsStart = m['startAt'];
      final tsEnd = m['endAt'];
      if (tsStart is! Timestamp || tsEnd is! Timestamp) continue;
      if (tsStart.toDate().isBefore(endDt) && tsEnd.toDate().isAfter(startDt)) return true;
    }
    return false;
  }

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed': return 'Confirmed';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return 'Pending';
    }
  }

  (Color bg, Color fg) _statusColors(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed': return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'completed': return (const Color(0xFFC8F2D2), const Color(0xFF2E7D32));
      case 'cancelled': return (const Color(0xFFFFE0E0), const Color(0xFFD32F2F));
      default: return (const Color(0xFFEDEEF1), const Color(0xFF6B7280));
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
              Text('Booking Info', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Your booking details', style: t.bodySmall),
              const SizedBox(height: 12),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('appointments').doc(_appointmentId).snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator()));
                  }
                  if (!snap.hasData || !snap.data!.exists) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
                      child: const Text('Appointment not found.'),
                    );
                  }

                  final m = snap.data!.data()!;
                  final start = (m['startAt'] as Timestamp?)?.toDate();
                  final end = (m['endAt'] as Timestamp?)?.toDate();
                  final loc = (m['location'] ?? '').toString();
                  final notes = (m['notes'] ?? '').toString();
                  final statusRaw = (m['status'] ?? 'pending').toString();
                  final helperIdFromDoc = (m['helperId'] ?? '').toString();
                  final statusLbl = _statusLabel(statusRaw);
                  final (chipBg, chipFg) = _statusColors(statusRaw);

                  final canModify = start != null && start.difference(DateTime.now()) >= const Duration(hours: 24);
                  final statusOk = statusRaw.toLowerCase() == 'pending' || statusRaw.toLowerCase() == 'confirmed';
                  final canReschedule = statusOk && canModify;
                  final canCancel = statusOk;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          _HelperHeader(
                            helperId: helperIdFromDoc.isNotEmpty ? helperIdFromDoc : _helperId,
                            fallbackName: _fbName, fallbackFaculty: _fbFaculty, fallbackEmail: _fbEmail,
                            fallbackBio: _fbBio, fallbackSessions: _fbSessions, fallbackPhotoUrl: '',
                            specializes: _fbSpecializes,
                          ),
                          Positioned(right: 12, top: 12, child: _Chip(label: statusLbl, bg: chipBg, fg: chipFg)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _FieldShell(child: Row(children: [ Expanded(child: Text((start != null) ? _fmtDate(start) : '—', style: t.bodyMedium)), const Icon(Icons.calendar_month_outlined)])),
                      const SizedBox(height: 8),
                      _FieldShell(child: Row(children: [ Expanded(child: Text((start != null && end != null) ? '${_fmtTime(TimeOfDay.fromDateTime(start))}  to  ${_fmtTime(TimeOfDay.fromDateTime(end))}' : '—', style: t.bodyMedium)), const Icon(Icons.timer_outlined)])),
                      const SizedBox(height: 8),
                      _FieldShell(child: Row(children: [ Expanded(child: Text(loc.isEmpty ? '—' : loc, style: t.bodyMedium)), const Icon(Icons.place_outlined)])),
                      const SizedBox(height: 12),
                      Container(
                        height: 160,
                        decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: SingleChildScrollView(primary: false, child: SizedBox(width: double.infinity, child: Text(notes.isEmpty ? '—' : notes, softWrap: true))),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back')),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (canReschedule && start != null && end != null)
                                FilledButton.tonal(
                                  onPressed: () => _rescheduleWithReason(context, apptId: _appointmentId!, helperId: helperIdFromDoc.isNotEmpty ? helperIdFromDoc : _helperId, currentStart: start, currentEnd: end),
                                  child: const Text('Reschedule'),
                                ),
                              if (canCancel && start != null)
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => _cancelWithReason(_appointmentId!, start),
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
  final String fallbackName, fallbackFaculty, fallbackEmail, fallbackBio;
  final int fallbackSessions;
  final String fallbackPhotoUrl;
  final List<String> specializes;

  const _HelperHeader({
    required this.helperId,
    required this.fallbackName, required this.fallbackFaculty, required this.fallbackEmail,
    required this.fallbackBio, required this.fallbackSessions, required this.fallbackPhotoUrl,
    required this.specializes,
  });

  Future<(String name, String faculty, String email, String bio, String photo)> _load() async {
    String name = fallbackName, fac = fallbackFaculty, email = fallbackEmail,
        bio = fallbackBio, photo = fallbackPhotoUrl;
    if (helperId.isEmpty) return (name, fac, email, bio, photo);

    final usersCol = FirebaseFirestore.instance.collection('users');
    final facCol = FirebaseFirestore.instance.collection('faculties');

    try {
      final uSnap = await usersCol.doc(helperId).get();
      final u = uSnap.data() ?? {};
      name = (u['fullName'] ?? u['name'] ?? fallbackName).toString();
      email = (u['email'] ?? u['emailAddress'] ?? fallbackEmail).toString();
      bio = (u['about'] ?? fallbackBio).toString();
      photo = (u['photoUrl'] ?? u['avatarUrl'] ?? fallbackPhotoUrl).toString();

      final facId = (u['facultyId'] ?? '').toString();
      if (facId.isNotEmpty) {
        final fSnap = await facCol.doc(facId).get();
        fac = (fSnap.data()?['title'] ?? fSnap.data()?['name'] ?? fallbackFaculty).toString();
      }
    } catch (_) {}
    return (name, fac, email, bio, photo);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<(String, String, String, String, String)>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data ?? (fallbackName, fallbackFaculty, fallbackEmail, fallbackBio, fallbackPhotoUrl);
        return _helperShell(t: t, helperId: helperId, name: data.$1, faculty: data.$2, email: data.$3, bio: data.$4, sessionsFallback: fallbackSessions, photoUrl: data.$5, specializes: specializes);
      },
    );
  }

  Widget _helperShell({
    required TextTheme t, required String helperId, required String name, required String faculty,
    required String email, required String bio, required int sessionsFallback,
    required String photoUrl, required List<String> specializes,
  }) {
    final avatar = Column(children: [
      CircleAvatar(radius: 22, backgroundColor: Colors.grey.shade300, backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null, child: (photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white) : null),
      const SizedBox(height: 6),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: (helperId.isEmpty) ? const Stream.empty() : FirebaseFirestore.instance.collection('appointments').where('helperId', isEqualTo: helperId).snapshots(),
        builder: (context, snap) {
          int count = sessionsFallback;
          if (snap.hasData) {
            count = snap.data!.docs.where((d) => (d.data()['status'] ?? '').toString().toLowerCase() != 'cancelled').length;
          }
          return Text('$count\nsessions', textAlign: TextAlign.center, style: t.labelSmall);
        },
      ),
    ]);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      Text(faculty.isEmpty ? '—' : faculty, style: t.bodySmall),
      Text(email.isEmpty ? '—' : email, style: t.bodySmall),
      const SizedBox(height: 6),
      _SpecializeLine(items: specializes),
      const SizedBox(height: 4),
      Text('Bio: ${bio.isEmpty ? "N/A" : bio}', style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
    ]);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDDE6FF), width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 4))]),
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(width: 10), Expanded(child: info)]),
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
    return Row(children: [
      Material(color: Colors.white, borderRadius: BorderRadius.circular(10), child: InkWell(onTap: () => Navigator.maybePop(context), borderRadius: BorderRadius.circular(10), child: Ink(height: 36, width: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26)), child: const Icon(Icons.arrow_back, size: 20)))),
      const SizedBox(width: 10),
      Container(height: 48, width: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFFB388FF), Color(0xFF7C4DFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)), alignment: Alignment.center, child: Text('PEERS', style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Student', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium), Text('Portal', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))])),
      const SizedBox(width: 8),
      Material(color: Colors.white, borderRadius: BorderRadius.circular(10), child: InkWell(onTap: () => _logout(context), borderRadius: BorderRadius.circular(10), child: Ink(height: 36, width: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26)), child: const Icon(Icons.logout, size: 20)))),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withOpacity(.3))), child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)));
}

class _FieldShell extends StatelessWidget {
  final Widget child;
  const _FieldShell({required this.child});
  @override
  Widget build(BuildContext context) => Container(height: 44, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 10), alignment: Alignment.centerLeft, child: child);
}

class _SpecializeLine extends StatelessWidget {
  final List<String> items;
  const _SpecializeLine({required this.items});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final boldCount = items.length >= 2 ? 2 : items.length;
    final spans = <TextSpan>[TextSpan(text: 'Specialize: ', style: t.bodySmall)];
    for (var i = 0; i < items.length; i++) {
      spans.add(TextSpan(text: items[i], style: t.bodySmall?.copyWith(fontWeight: i < boldCount ? FontWeight.w800 : FontWeight.w400)));
      if (i != items.length - 1) spans.add(TextSpan(text: ', ', style: t.bodySmall));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _CancelDialog extends StatefulWidget {
  final bool isWithin24Hours;
  const _CancelDialog({required this.isWithin24Hours});
  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reasonCtrl = TextEditingController();
  String? _selectedReason;
  final _predefinedReasons = ['Misclick', 'Too near to appointed date/time'];
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel Appointment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please provide a reason for cancellation.'),
          const SizedBox(height: 12),
          if (widget.isWithin24Hours)
            DropdownButtonFormField<String>(
              value: _selectedReason,
              hint: const Text('Select a reason'),
              items: _predefinedReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedReason = v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            )
          else
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(hintText: 'Reason for cancellation', border: OutlineInputBorder()),
              maxLines: 2,
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep')),
        FilledButton(onPressed: () {
          final reason = widget.isWithin24Hours ? _selectedReason : _reasonCtrl.text.trim();
          if (reason != null && reason.isNotEmpty) {
            Navigator.pop(context, reason);
          }
        }, child: const Text('Confirm Cancel')),
      ],
    );
  }
}

class _RescheduleDialog extends StatefulWidget {
  final DateTime currentStart, currentEnd;
  const _RescheduleDialog({required this.currentStart, required this.currentEnd});
  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
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
      title: const Text('Reschedule Appointment'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(dense: true, title: const Text('Date'), subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)), trailing: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDate)),
          Row(children: [
            Expanded(child: ListTile(dense: true, title: const Text('Start'), subtitle: Text(_fmtTime(_startTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(true)))),
            Expanded(child: ListTile(dense: true, title: const Text('End'), subtitle: Text(_fmtTime(_endTod)), trailing: IconButton(icon: const Icon(Icons.timer_outlined), onPressed: () => _pickTime(false)))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _reasonCtrl, decoration: const InputDecoration(hintText: 'Reason for rescheduling', border: OutlineInputBorder()), maxLines: 2),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: () {
          final start = DateTime(_date.year, _date.month, _date.day, _startTod.hour, _startTod.minute);
          final end = DateTime(_date.year, _date.month, _date.day, _endTod.hour, _endTod.minute);
          if (end.isBefore(start) || end.isAtSameMomentAs(start)) return;
          if (start.isBefore(DateTime.now())) return;
          Navigator.pop(context, {'start': start, 'end': end, 'reason': _reasonCtrl.text.trim()});
        }, child: const Text('Save')),
      ],
    );
  }
}
