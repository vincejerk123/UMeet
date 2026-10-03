import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'complete_profile_screen.dart';
import 'main_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // ─── 1. While the SDK is restoring the session,
        //      show a splash — do NOT decide yet ───
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }

        // ─── 2. Prefer the snapshot's session; fall back to
        //      the live one for safety ───
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        debugPrint(
          'AuthGate → event=${snapshot.data?.event} '
          'hasSession=${session != null} '
          'userId=${session?.user.id}',
        );

        // ─── 3. No session → login ───
        if (session == null) return const LoginScreen();

        // ─── 4. Session exists → check profile, forcing a fresh
        //      fetch keyed to the user id so switching accounts
        //      re-runs the gate ───
        return _ProfileGate(key: ValueKey(session.user.id));
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F7F7),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProfileGate extends StatefulWidget {
  const _ProfileGate({super.key});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    // Enforce UM-only domain
    final email = user.email?.toLowerCase();
    if (email != null && !email.endsWith('@umindanao.edu.ph')) {
      await Supabase.instance.client.auth.signOut();
      return null;
    }

    final res = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    return res;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        if (snap.data == null) return const CompleteProfileScreen();
        return const MainShell();
      },
    );
  }
}
