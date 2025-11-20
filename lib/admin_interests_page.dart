// lib/admin_interests_page.dart
//

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminInterestsPage extends StatefulWidget {
  const AdminInterestsPage({super.key});

  @override
  State<AdminInterestsPage> createState() => _AdminInterestsPageState();
}

/* ------------------------------- Model ------------------------------- */

class InterestItem {
  String id;
  String title;
  String code;
  int seq;
  String category;
  InterestItem({
    required this.id,
    required this.title,
    required this.code,
    required this.seq,
    required this.category,
  });

  factory InterestItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return InterestItem(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      code: (d['code'] ?? '') as String,
      seq: (d['seq'] ?? 0) as int,
      category: (d['category'] ?? '') as String,
    );
  }
}

/* ------------------------------ Page State ------------------------------ */

class _AdminInterestsPageState extends State<AdminInterestsPage> {
  int _tabIndex = 0;

  String _search = '';
  String _filter = 'Show all';

  final _formKey = GlobalKey<FormState>();
  final _newCtrl = TextEditingController();

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  String get _sectionTitle =>
      _tabIndex == 0 ? 'Academic Interests' : 'Counseling Topics';

  String get _addHint =>
      _tabIndex == 0 ? 'Add academic interest' : 'Add counseling topic';

  String get _category => _tabIndex == 0 ? 'academic' : 'counseling';
  String get _codePrefix => _tabIndex == 0 ? 'ACI' : 'CT';
  String get _totalLabel => 'Total ${_tabIndex == 0 ? 'Academic' : 'Counseling'}';

  /* ------------------------------ Firestore ------------------------------ */

  Stream<List<InterestItem>> _categoryStream(String category) {
    final q = FirebaseFirestore.instance
        .collection('interests')
        .where('category', isEqualTo: category);
    return q.snapshots().map((snap) {
      final items = snap.docs.map((d) => InterestItem.fromDoc(d)).toList();
      items.sort((a, b) => b.seq.compareTo(a.seq));
      final s = _search.trim().toLowerCase();
      return items.where((e) {
        final matchesSearch = s.isEmpty ||
            e.title.toLowerCase().contains(s) ||
            e.code.toLowerCase().contains(s);
        final matchesFilter = _filter == 'Show all';
        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  Future<int> _nextSeq(String category) async {
    final countersRef =
    FirebaseFirestore.instance.collection('meta').doc('counters');
    return FirebaseFirestore.instance.runTransaction<int>((tx) async {
      final snap = await tx.get(countersRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final field = category == 'academic' ? 'academicSeq' : 'counselingSeq';
      final current = (data[field] ?? 0) as int;
      final next = current + 1;
      tx.set(countersRef, {field: next}, SetOptions(merge: true));
      return next;
    });
  }

  Future<void> _addItem() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _newCtrl.text.trim();
    try {
      final seq = await _nextSeq(_category);
      final code = '$_codePrefix-$seq';
      final ref = FirebaseFirestore.instance.collection('interests').doc();
      await ref.set({
        'title': title,
        'code': code,
        'seq': seq,
        'category': _category,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _newCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "$title" ($code)')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firestore error (${e.code}): ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    }
  }

  Future<void> _editItem(InterestItem item) async {
    final ctrl = TextEditingController(text: item.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final newTitle = ctrl.text.trim();
      if (newTitle.isEmpty || newTitle == item.title) return;
      try {
        await FirebaseFirestore.instance
            .collection('interests')
            .doc(item.id)
            .update({
          'title': newTitle,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firestore error (${e.code}): ${e.message ?? ''}')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
      }
    }
  }

  Future<void> _deleteItem(InterestItem item) async {
    // ✅ ENHANCED: More explicit double confirmation with warnings
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Delete Interest/Topic'),
        content: Text(
          'Are you sure you want to PERMANENTLY DELETE "${item.title}" (${item.code})?\n\n'
              '⚠️ This action will:\n'
              '• Remove this interest/topic from the system\n'
              '• Affect all users and applications linked to it\n'
              '• CANNOT be undone\n\n'
              'Please confirm you want to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Delete Permanently'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await FirebaseFirestore.instance
            .collection('interests')
            .doc(item.id)
            .delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interest/Topic deleted.')),
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Firestore error (${e.code}): ${e.message ?? ''}')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
      }
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

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
                  onLogout: _logout,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Interest & Topics',
                              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Manage academic interests and counseling topics', style: t.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: _addItem,
                      icon: const Icon(Icons.add, size: 18, color: Colors.white),
                      label: const Text('Add', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _TabSwitcher(
                  index: _tabIndex,
                  onChanged: (i) => setState(() => _tabIndex = i),
                ),
                const SizedBox(height: 12),

                _SearchField(
                  hint: _tabIndex == 0 ? 'Search Academic Interests' : 'Search Counseling Topics',
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _DropdownPill<String>(
                        value: _filter,
                        items: const ['Show all'],
                        onChanged: (v) => setState(() => _filter = v ?? 'Show all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CategoryTotalBox(category: _category, label: _totalLabel),
                  ],
                ),
                const SizedBox(height: 14),

                _SectionLabel(text: '$_sectionTitle'),
                const SizedBox(height: 10),

                _AddCard(
                  formKey: _formKey,
                  controller: _newCtrl,
                  hint: _addHint,
                ),
                const SizedBox(height: 14),
                Center(child: Icon(Icons.arrow_downward, color: Colors.grey.shade600)),
                const SizedBox(height: 10),

                StreamBuilder<List<InterestItem>>(
                  stream: _categoryStream(_category),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ));
                    }
                    if (snap.hasError) {
                      return Text(
                        'Failed to load: ${snap.error}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      );
                    }
                    final list = snap.data ?? const <InterestItem>[];
                    if (list.isEmpty) {
                      return const Text('No items yet.');
                    }
                    return Column(
                      children: [
                        for (final item in list) ...[
                          _InterestTile(
                            item: item,
                            onEdit: () => _editItem(item),
                            onDelete: () => _deleteItem(item),
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
          child: Text('PEERS',
              style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
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

class _TabSwitcher extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _TabSwitcher({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.onSurface;
    final inactive = Colors.black54;

    Widget btn(String label, int i) {
      final selected = i == index;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(i),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? active : inactive)),
                const SizedBox(height: 6),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? Colors.black : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('Academic Interest', 0),
        const SizedBox(width: 10),
        btn('Counseling Topics', 1),
      ],
    );
  }
}

//Search Box
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

class _StatBox extends StatelessWidget {
  final int count;
  final String label;
  const _StatBox({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 140,
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

class _CategoryTotalBox extends StatelessWidget {
  final String category;
  final String label;
  const _CategoryTotalBox({required this.category, required this.label});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('interests')
        .where('category', isEqualTo: category);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return _StatBox(count: count, label: label);
      },
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

class _AddCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final String hint;

  const _AddCard({required this.formKey, required this.controller, required this.hint});

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
            Text('Add New', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Create a new ${hint.replaceFirst('Add ', '').toLowerCase()}',
                style: t.bodySmall),
            const SizedBox(height: 10),
            TextFormField(
              controller: controller,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              decoration: InputDecoration(
                hintText: hint,
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

class _InterestTile extends StatelessWidget {
  final InterestItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InterestTile({required this.item, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 8, offset: const Offset(0, 4)),
        ],
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
              Text(item.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(item.code, style: t.bodySmall),
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