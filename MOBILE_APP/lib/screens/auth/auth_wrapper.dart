import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import 'login_screen.dart';

/// Listens to Firebase auth state and routes to either
/// the main app (MainScreen) or the login screen.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF309249)),
            ),
          );
        }

        // User is signed in -> show main app
        if (snapshot.hasData) {
          return const MainScreen();
        }

        // Not signed in -> show login
        return const LoginScreen();
      },
    );
  }
}
