import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // TODO: Integrate with your auth service (e.g., Firebase, custom API)
    // await FirebaseAuth.instance
    //     .sendPasswordResetEmail(email: _emailCtrl.text.trim());
    await Future.delayed(const Duration(seconds: 1)); // stub

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'If an account exists for ${_emailCtrl.text.trim()}, a reset link has been sent.',
        ),
      ),
    );
    Navigator.pop(context); // back to login
  }

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.of(context).size.height * 0.02;

    return Scaffold(
      // Headerless to match your login/registration screens
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
                    // Optional logo:
                    Image.asset('assets/images/logo.png', width: 72, height: 72),

                    Text(
                      'Reset your password',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your email address and we\'ll send you a password reset link.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing * 1.5),

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
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        final rx = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                        if (!rx.hasMatch(v.trim())) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    SizedBox(height: spacing * 1.5),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _sendResetLink,
                        child: _isLoading
                            ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Send reset link'),
                      ),
                    ),

                    const SizedBox(height: 12),

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
