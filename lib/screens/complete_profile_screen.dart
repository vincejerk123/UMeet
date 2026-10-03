import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'main_shell.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _displayName = TextEditingController();
  final _studentId = TextEditingController();
  String? _program;
  int? _year;
  File? _avatar;
  bool _saving = false;

  // ─── Programs (full names, "BS" kept as acronym) ───
  static const _programs = [
    'BS in Information Technology',
    'BS in Computer Science',
    'BS in Information Systems',
    'BS in Accountancy',
    'BS in Business Administration',
    'BS in Education',
    'BE in Elementary Education',
    'BS in Civil Engineering',
    'BS in Electrical Engineering',
    'BS in Mechanical Engineering',
    'BS in Nursing',
    'BS in Psychology',
    'BS in Criminology',
    'Other',
  ];

  // ─── Years 1–5 ───
  static const _years = [1, 2, 3, 4, 5];

  // Helpers for display
  String _yearLabel(int y) {
    switch (y) {
      case 1:
        return '1st Year';
      case 2:
        return '2nd Year';
      case 3:
        return '3rd Year';
      case 4:
        return '4th Year';
      case 5:
        return '5th Year';
      default:
        return 'Year $y';
    }
  }

  Future<void> _pickAvatar() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (f != null) setState(() => _avatar = File(f.path));
  }

  Future<void> _save() async {
    if (_displayName.text.trim().isEmpty || _program == null || _year == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill out the required fields.')),
      );
      return;
    }
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    try {
      String? avatarUrl;
      if (_avatar != null) {
        final path = 'avatars/${user.id}.jpg';
        await client.storage
            .from('avatars')
            .upload(
              path,
              _avatar!,
              fileOptions: const FileOptions(upsert: true),
            );
        avatarUrl = client.storage.from('avatars').getPublicUrl(path);
      }

      await client.from('profiles').upsert({
        'id': user.id,
        'display_name': _displayName.text.trim(),
        'avatar_url': avatarUrl,
        'program': _program,
        'year_level': _year,
      });

      await client.from('profiles_private').upsert({
        'id': user.id,
        'real_name': user.userMetadata?['full_name'] ?? '',
        'student_id': _studentId.text.trim(),
      });

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Image.asset(
                'assets/images/logo.png',
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              const Text(
                'Complete your profile',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 24),

              // ─── Avatar ─────────────────────────────
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400, width: 1.5),
                    image: _avatar != null
                        ? DecorationImage(
                            image: FileImage(_avatar!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _avatar == null
                      ? const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 32,
                          color: Colors.grey,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 28),

              // ─── Display name ──────────────────────
              _label('Display Name'),
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),

              // ─── Program ───────────────────────────
              _label('Program'),
              DropdownButtonFormField<String>(
                value: _program,
                isExpanded: true,
                items: _programs
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _program = v),
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),

              // ─── Year + Student ID ─────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Year'),
                        DropdownButtonFormField<int>(
                          value: _year,
                          items: _years
                              .map(
                                (y) => DropdownMenuItem(
                                  value: y,
                                  child: Text(_yearLabel(y)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _year = v),
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Student ID'),
                        TextField(
                          controller: _studentId,
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ─── Buttons ───────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        foregroundColor: AppColors.red,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        s,
        style: const TextStyle(fontSize: 12, color: Colors.black87),
      ),
    ),
  );
}
