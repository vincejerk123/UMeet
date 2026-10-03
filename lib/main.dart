import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';
import 'screens/auth_gate.dart';

const kSupabaseUrl = 'https://yvmhogfosldgkmywyhtt.supabase.co';
const kSupabaseAnonKey = 'sb_publishable_O-8TXR71nxcri1SapbqDBw_k5v53iKM';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const UMeetApp());
}

class UMeetApp extends StatelessWidget {
  const UMeetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UMeet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}
