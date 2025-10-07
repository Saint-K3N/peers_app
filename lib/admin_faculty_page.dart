import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/* -------------------------------- Model -------------------------------- */

class FacultyItem {
  final String id;           // Firestore doc id
  String name;
  String approverUid;        // <-- HOP user's uid (from users/{uid})
  String description;        // optional notes

  FacultyItem({
    required this.id,
    required this.name,
    required this.approverUid,
    required this.description,
  });

  factory FacultyItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return FacultyItem(
      id: d.id,
      name: (data['name'] ?? '').toString(),
      approverUid: (data['approverUid'] ?? '').toString(), // <-- read uid
      description: (data['description'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'approverUid': approverUid, // <-- persist uid
    'description': description,
    'nameLower': name.trim().toLowerCase(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/* ------------------------------ Page ------------------------------ */

class AdminFacultyPage extends StatefulWidget {
  const AdminFacultyPage({super.key});

  @override
  State<AdminFacultyPage> createState() => _AdminFacultyPageState();
}

class _AdminFacultyPageState extends State<AdminFacultyPage> {
  // Search
  String _search = '';
  String _filter = 'All Faculties';

  // Add form
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedHopUid; // <-- selected HOP uid for Add

  CollectionReference<Map<String, dynamic>> get _facultiesCol =>
      FirebaseFirestore.instance.collection('faculties');

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /* -------------------------- User helpers -------------------------- */

  Future<Map<String, dynamic>?> _getUser(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final snap = await _usersCol.doc(uid).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  String _readName(Map<String, dynamic>? u) {
    if (u == null) return '';
    String pick(Map<String, dynamic>? m, List<String> keys) {
      if (m == null) return '';
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final direct = pick(u, ['fullName','full_name','name','displayName','display_name']);
    if (direct.isNotEmpty) return direct;

    final profile = (u['profile'] is Map) ? (u['profile'] as Map).cast<String, dynamic>() : null;
    final profName = pick(profile, ['fullName','full_name','name','displayName','display_name']);
    if (profName.isNotEmpty) return profName;

    final first = pick(u, ['firstName','first_name','givenName','given_name']);
    final last  = pick(u, ['lastName','last_name','familyName','family_name','surname']);
    final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (combo.isNotEmpty) return combo;

    final pFirst = pick(profile, ['firstName','first_name','givenName','given_name']);
    final pLast  = pick(profile, ['lastName','last_name','familyName','family_name','surname']);
    final pCombo = [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
    return pCombo;
  }

  String _fallbackUserLabel(String uid, Map<String, dynamic>? u) {
    final name = _readName(u);
    if (name.isNotEmpty) return name;
    final email = (u?['email'] ?? u?['emailAddress'] ?? '').toString();
    if (email.isNotEmpty) return email;
    // short uid fallback
    return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
  }

  /* ------------------------------ Actions ------------------------------ */

  Future<void> _addFaculty() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final approverUid = (_selectedHopUid ?? '').trim();

    if (approverUid.isEmpty) {
      _showAlert('Missing field', 'Please select the Head of Program user.');
      return;
    }

    try {
      await _facultiesCol.add({
        'name': name,
        'description': desc,
        'approverUid': approverUid, // <-- store HOP uid
        'nameLower': name.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faculty added.')),
      );
      _nameCtrl.clear();
      _descCtrl.clear();
      setState(() => _selectedHopUid = null);
    } catch (e) {
      _showAlert('Add failed', '$e');
    }
  }

  Future<void> _editFaculty(FacultyItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final descCtrl = TextEditingController(text: item.description);
    String selectedUid = item.approverUid;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDlg) {
          return AlertDialog(
            title: const Text('Edit Faculty'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Faculty Name'),
                ),
                const SizedBox(height: 8),
                _HopUserDropdown(
                  value: selectedUid.isEmpty ? null : selectedUid,
                  onChanged: (v) => setStateDlg(() => selectedUid = v ?? ''),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                  minLines: 1,
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      try {
        await _facultiesCol.doc(item.id).update({
          'name': nameCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'approverUid': selectedUid.trim(),
          'nameLower': nameCtrl.text.trim().toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faculty updated.')),
        );
      } catch (e) {
        _showAlert('Update failed', '$e');
      }
    }
  }

  Future<void> _deleteFaculty(FacultyItem f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Faculty'),
        content: Text('Delete “${f.name}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _facultiesCol.doc(f.id).delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faculty deleted.')),
        );
      } catch (e) {
        _showAlert('Delete failed', '$e');
      }
    }
  }

  void _showAlert(String title, String msg) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  /* --------------------------------- Build -------------------------------- */

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    // Query with prefix search on nameLower.
    Query<Map<String, dynamic>> query = _facultiesCol.orderBy('nameLower');
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      query = query.startAt([q]).endAt(['$q\uf8ff']);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderBar(
                  onBack: () => Navigator.maybePop(context),
                  onLogout: () async {
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (_) {}
                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                  },
                ),
                const SizedBox(height: 12),

                // Title + Add button
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Faculty Management', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Manage academic faculties', style: t.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: _addFaculty,
                      icon: const Icon(Icons.add, size: 18, color: Colors.white),
                      label: const Text('Add Faculty', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search + (light) filter
                _SearchField(
                  hint: 'Search faculty',
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                _DropdownPill<String>(
                  value: _filter,
                  items: const ['All Faculties'],
                  onChanged: (v) => setState(() => _filter = v ?? 'All Faculties'),
                ),

                const SizedBox(height: 14),

                // Live list
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError) {
                      return Text(
                        'Error: ${snap.error}',
                        style: t.bodyMedium?.copyWith(color: Colors.red.shade700),
                      );
                    }

                    final items = (snap.data?.docs ?? []).map((d) => FacultyItem.fromDoc(d)).toList();

                    // Secondary description filter (optional)
                    final s = _search.trim().toLowerCase();
                    final filtered = items.where((f) {
                      if (s.isEmpty) return true;
                      return f.name.toLowerCase().contains(s) || f.description.toLowerCase().contains(s);
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(text: 'Faculty (${filtered.length})'),
                        const SizedBox(height: 10),

                        // Add New Faculty card
                        _AddFacultyCard(
                          formKey: _formKey,
                          nameCtrl: _nameCtrl,
                          descCtrl: _descCtrl,
                          approverInput: _HopUserDropdown(
                            value: _selectedHopUid,
                            onChanged: (v) => setState(() => _selectedHopUid = v),
                          ),
                        ),

                        const SizedBox(height: 14),
                        Center(child: Icon(Icons.arrow_downward, color: Colors.grey.shade600)),
                        const SizedBox(height: 10),

                        // Cards
                        for (final f in filtered) ...[
                          _FacultyTile(
                            item: f,
                            onEdit: () => _editFaculty(f),
                            onDelete: () => _deleteFaculty(f),
                            getUser: _getUser,
                            readName: _readName,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin', style: t.titleMedium),
            Text('Portal', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
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

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _DropdownPill<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  const _DropdownPill({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T>(
        isExpanded: true,
        underline: const SizedBox(),
        value: value,
        icon: const Icon(Icons.arrow_drop_down),
        items: items.map((e) => DropdownMenuItem<T>(value: e, child: Text('$e'))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _AddFacultyCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final Widget approverInput; // UID dropdown

  const _AddFacultyCard({
    required this.formKey,
    required this.nameCtrl,
    required this.descCtrl,
    required this.approverInput,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add New Faculty', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Create a new faculty', style: t.bodySmall),
            const SizedBox(height: 10),
            TextFormField(
              controller: nameCtrl,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Faculty name required' : null,
              decoration: InputDecoration(
                hintText: 'Insert Faculty Name',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 8),
            approverInput, // HOP dropdown
            const SizedBox(height: 8),
            TextFormField(
              controller: descCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Description (optional)',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacultyTile extends StatelessWidget {
  final FacultyItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<Map<String, dynamic>?> Function(String uid) getUser;
  final String Function(Map<String, dynamic>?) readName;

  const _FacultyTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.getUser,
    required this.readName,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onEdit,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),

              // Resolve HOP name from approverUid
              FutureBuilder<Map<String, dynamic>?>(
                future: getUser(item.approverUid),
                builder: (context, snap) {
                  final name = readName(snap.data);
                  final hopName = name.isNotEmpty
                      ? name
                      : (snap.connectionState == ConnectionState.waiting
                      ? '(loading...)'
                      : (item.approverUid.isNotEmpty ? item.approverUid : '—'));
                  return Text('HOP: $hopName', style: t.bodySmall);
                },
              ),

              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(item.description, style: t.bodySmall),
              ],

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 36,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onDelete,
                    child: const Text('Delete', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* --------------------- HOP user dropdown (role == hop) --------------------- */

class _HopUserDropdown extends StatelessWidget {
  final String? value;                      // selected uid
  final ValueChanged<String?> onChanged;

  const _HopUserDropdown({
    required this.value,
    required this.onChanged,
  });

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  String _readName(Map<String, dynamic>? u) {
    if (u == null) return '';
    String pick(Map<String, dynamic>? m, List<String> keys) {
      if (m == null) return '';
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }
    final direct = pick(u, ['fullName','full_name','name','displayName','display_name']);
    if (direct.isNotEmpty) return direct;
    final profile = (u['profile'] is Map) ? (u['profile'] as Map).cast<String, dynamic>() : null;
    final profName = pick(profile, ['fullName','full_name','name','displayName','display_name']);
    if (profName.isNotEmpty) return profName;
    final first = pick(u, ['firstName','first_name','givenName','given_name']);
    final last  = pick(u, ['lastName','last_name','familyName','family_name','surname']);
    final combo = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (combo.isNotEmpty) return combo;
    final pFirst = pick(profile, ['firstName','first_name','givenName','given_name']);
    final pLast  = pick(profile, ['lastName','last_name','familyName','family_name','surname']);
    final pCombo = [pFirst, pLast].where((s) => s.isNotEmpty).join(' ');
    return pCombo;
  }

  String _labelForDoc(String uid, Map<String, dynamic>? data) {
    final name = _readName(data);
    if (name.isNotEmpty) return name;
    final email = (data?['email'] ?? data?['emailAddress'] ?? '').toString();
    if (email.isNotEmpty) return email;
    return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Only users with role == 'hop'
      stream: _usersCol.where('role', isEqualTo: 'hop').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return DropdownButtonFormField<String>(
            items: const [],
            onChanged: null,
            decoration: const InputDecoration(
              labelText: 'Head of Program (HOP)',
              hintText: 'Loading HOP users...',
              border: OutlineInputBorder(),
            ),
          );
        }
        if (snap.hasError) {
          return DropdownButtonFormField<String>(
            items: const [],
            onChanged: null,
            decoration: InputDecoration(
              labelText: 'Head of Program (HOP)',
              hintText: 'Error: ${snap.error}',
              border: const OutlineInputBorder(),
            ),
          );
        }

        final docs = snap.data?.docs ?? const [];
        // Build items
        final items = <DropdownMenuItem<String>>[];
        for (final d in docs) {
          final uid = d.id;
          final data = d.data();
          final label = _labelForDoc(uid, data);
          items.add(DropdownMenuItem<String>(
            value: uid,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ));
        }

        // If the current value isn't in the list (e.g., role changed), add a temp item
        String? usedValue = value;
        final uidSet = docs.map((e) => e.id).toSet();
        if (usedValue != null && usedValue.isNotEmpty && !uidSet.contains(usedValue)) {
          items.insert(
            0,
            DropdownMenuItem<String>(
              value: usedValue,
              child: Text('Current (not in HOP list): $usedValue', overflow: TextOverflow.ellipsis),
            ),
          );
        }

        return DropdownButtonFormField<String>(
          isExpanded: true,
          value: usedValue?.isEmpty == true ? null : usedValue,
          items: items,
          onChanged: onChanged,
          validator: (v) => (v == null || v.isEmpty) ? 'Select a HOP user' : null,
          decoration: const InputDecoration(
            labelText: 'Head of Program (HOP)',
            hintText: 'Select HOP user',
            border: OutlineInputBorder(),
          ),
        );
      },
    );
  }
}
