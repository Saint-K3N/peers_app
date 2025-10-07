// lib/register_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();

  String? _selectedFacultyId; // store faculty doc ID only
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _studentIdCtrl.dispose();
    super.dispose();
  }

  String _authErrorMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'weak-password':
        return 'Password is too weak (min 6 characters).';
      case 'operation-not-allowed':
        return 'Email/password accounts are disabled for this project.';
      default:
        return 'Registration failed: ${e.message ?? e.code}';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFacultyId == null || _selectedFacultyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Faculty')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      final studentId = _studentIdCtrl.text.trim();
      final facultyId = _selectedFacultyId!.trim();

      // 1) Create Firebase Auth user
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // 2) Update display name
      await cred.user!.updateDisplayName(name);

      // 3) Create Firestore profile — store ONLY facultyId
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'fullName': name,
        'email': email,
        'studentId': studentId,
        'facultyId': facultyId,          // <-- only ID
        'role': 'student',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created!')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_authErrorMsg(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Label for faculty dropdown (we show names, but save only ID)
  String _facLabel(Map<String, dynamic>? data) {
    if (data == null) return '(Unknown)';
    final n = (data['name'] ?? '').toString().trim();
    return n.isEmpty ? '(Unnamed faculty)' : n;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.of(context).size.height * 0.02;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Image.asset('assets/images/logo.png', width: 72, height: 72),
                    Text('Create your account', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Fill in your details to get started',
                        style: t.bodyMedium, textAlign: TextAlign.center),
                    SizedBox(height: spacing * 1.5),

                    // Full Name
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Full name is required';
                        if (v.trim().length < 3) return 'Enter a valid name';
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Student ID
                    TextFormField(
                      controller: _studentIdCtrl,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Student ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Student ID is required' : null,
                    ),
                    SizedBox(height: spacing),

                    // Faculty Dropdown (from Firestore) — saves facultyId only
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('faculties')
                          .orderBy('nameLower', descending: false)
                          .snapshots(),
                      builder: (context, snap) {
                        final disabled = snap.connectionState == ConnectionState.waiting || snap.hasError;
                        final items = <DropdownMenuItem<String>>[];

                        if (snap.hasData) {
                          for (final d in snap.data!.docs) {
                            final id = d.id; // we save this
                            final label = _facLabel(d.data());
                            items.add(DropdownMenuItem(value: id, child: Text(label)));
                          }
                        }

                        return DropdownButtonFormField<String>(
                          value: _selectedFacultyId,
                          items: items,
                          onChanged: disabled ? null : (v) => setState(() => _selectedFacultyId = v),
                          validator: (v) => v == null ? 'Please select a Faculty' : null,
                          decoration: InputDecoration(
                            labelText: 'Faculty',
                            prefixIcon: const Icon(Icons.school_outlined),
                            border: const OutlineInputBorder(),
                            hintText: snap.hasError
                                ? 'Failed to load faculties'
                                : (snap.connectionState == ConnectionState.waiting
                                ? 'Loading faculties...'
                                : 'Select Faculty'),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: spacing),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        final emailRx = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                        if (!emailRx.hasMatch(v.trim())) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Password
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure1,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                          icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 6) return 'Min 6 characters';
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Confirm Password
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure2,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                          icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm your password';
                        if (v != _passwordCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    SizedBox(height: spacing * 1.5),

                    // Create Account button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _register,
                        child: _isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Back to login
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to login'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
