// lib/register_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String? _selectedFacultyId;
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
        return 'The password is too weak.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Will create the user in Firebase Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      try {
        await cred.user?.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'A verification email has been sent. Please check your inbox.')),
          );
        }
      } catch (e) {
        debugPrint('Failed to send verification email: $e');
      }

      final uid = cred.user?.uid;
      if (uid == null || uid.isEmpty) throw Exception('User not created');

      // Save user details to "users" collection in Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fullName': _nameCtrl.text.trim(),
        'studentId': _studentIdCtrl.text.trim(),
        'facultyId': _selectedFacultyId,
        'email': _emailCtrl.text.trim(),
        'role': 'student', // Default role
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);

    } on FirebaseAuthException catch (e) {
      // To handle auth errors (ie: email is in use)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authErrorMsg(e))),
        );
      }
    } catch (e) {
      // To handle other errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.of(context).size.width * 0.05;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(spacing),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create Account',
                        style: Theme.of(context).textTheme.headlineMedium),
                    SizedBox(height: spacing * 1.5),

                    // Full Name
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                      // Validates and checks the restriction
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                    ),
                    SizedBox(height: spacing),

                    // Student ID
                    TextFormField(
                      controller: _studentIdCtrl,
                      maxLength: 9,
                      decoration: const InputDecoration(
                        labelText: 'Student ID / Staff ID',
                        counterText: "",
                      ),

                      // Validates and checks the restriction
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Student ID / Staff ID is required';
                        if (v.length != 9) return 'Student ID / Staff ID must be exactly 9 characters.';
                        final firstChar = v.substring(0, 1).toLowerCase();
                        if (firstChar != 'p' && firstChar != 'e') {
                          return 'Student ID / Staff ID must start with the letter P or E.';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Faculty Dropdown
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('faculties')
                            .orderBy('name')
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? const [];
                          final items = docs
                              .map((d) => DropdownMenuItem<String>(
                            value: d.id,
                            child: Text((d.data()['name'] ?? '').toString()),
                          ))
                              .toList();

                          return DropdownButtonFormField<String>(
                            value: _selectedFacultyId,
                            items: items,
                            onChanged: (v) => setState(() => _selectedFacultyId = v),
                            decoration: const InputDecoration(labelText: 'Faculty'),
                            validator: (v) => (v == null || v.isEmpty) ? 'Select a faculty' : null,
                          );
                        }),
                    SizedBox(height: spacing),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        final rx = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (!rx.hasMatch(v.trim())) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Password
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure1,
                      maxLength: 16,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'Must start with "iicp" followed by 12 characters.',
                        counterText: "",
                        suffixIcon: IconButton(
                          icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (!v.startsWith('iicp')) {
                          return 'Password must start with the prefix "iicp".';
                        }
                        if (v.length != 16) {
                          return 'Password must be 16 characters long in total.';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: spacing),

                    // Confirm Password
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure2,
                      maxLength: 16, // Added maxLength to match
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        counterText: "", // Hide the counter
                        suffixIcon: IconButton(
                          icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm your password';

                        // Added validation rules to match the first password field
                        if (!v.startsWith('iicp')) {
                          return 'Password must start with the prefix "iicp".';
                        }
                        if (v.length != 16) {
                          return 'Password must be 16 characters long in total.';
                        }

                        // Check if it matches the other password
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