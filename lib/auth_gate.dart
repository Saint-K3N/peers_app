import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart'; // MyHomePage(title: 'Login')

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _navigated = false;

  // If want to block login until users verify email
  static const bool requireEmailVerified = false;

  // If use a 'status' field in Firestore and only allow 'active' users, set it to "true"
  static const bool requireActiveStatus = true;

  String _normalizeRole(String? raw) {
    final r = (raw ?? 'student').toLowerCase().trim();

    // Support multiple spellings from various parts of the app/DB
    if (r == 'peertutor' || r == 'peer_tutor' || r == 'peer tutor') return 'peer_tutor';
    if (r == 'peercounsellor' || r == 'peer_counsellor' || r == 'peer counsellor') {
      return 'peer_counsellor';
    }
    if (r == 'hop' || r == 'head_of_programme' || r == 'head of programme') return 'hop';
    if (r == 'admin' || r == 'administrator') return 'admin';
    // Student variations
    if (r == 'student' || r == 'students') {
      return 'student';
    }

    // Counsellor / counselor variations
    if (r == 'counsellor' || r == 'counselor' || r =='school_counsellor') {
      return 'counsellor';
    }

    // Default
    return r;
  }

  String _routeForRole(String role) {
    switch (role) {
      case 'student':
        return '/student/home';
      case 'peer_tutor':
        return '/peer_tutor/home';
      case 'peer_counsellor':
        return '/peer_counsellor/home';
      case 'hop':
        return '/hop/home';
      case 'admin':
        return '/admin/home';
      case 'counsellor':
        return '/counsellor/home';
      default:
        return '/student/home';
    }
  }

  void _navigateOnce(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        // Not signed in → show login screen
        if (!authSnap.hasData) {
          _navigated = false; // reset guard when user logs out
          return const MyHomePage(title: 'Login');
        }

        final user = authSnap.data!;
        if (requireEmailVerified && !(user.emailVerified)) {
          // If enforcing email verification, keep user at a simple screen
          // or return a page that lets them re-send verification.
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Please verify your email to continue.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await user.sendEmailVerification();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Verification email sent.')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to send email: $e')),
                        );
                      }
                    },
                    child: const Text('Resend verification email'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
        }

        // Signed in → get profile doc
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = roleSnap.data?.data() ?? {};
            final status = (data['status'] as String?)?.toLowerCase().trim() ?? 'active';
            final normalizedRole = _normalizeRole(data['role'] as String?);

            if (requireActiveStatus && status != 'active') {
              // Block inactive/disabled accounts
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Your account is not active. Contact support.'),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async => FirebaseAuth.instance.signOut(),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final route = _routeForRole(normalizedRole);
            WidgetsBinding.instance.addPostFrameCallback((_) => _navigateOnce(route));

            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          },
        );
      },
    );
  }
}
