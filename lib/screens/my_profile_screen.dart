import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/post_card.dart';
import 'reply_screen.dart';
import 'connections_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  int _followersCount = 0;
  int _friendsCount = 0;
  int _likes = 0;
  bool _loading = true;
  bool _uploadingAvatar = false;

  String _yearLabel(dynamic y) {
    if (y == null) return '-';
    final n = (y as num).toInt();
    switch (n) {
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
        return 'Year $n';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;

      final p = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      final posts = await _client
          .from('posts_with_counts')
          .select(
            '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)',
          )
          .eq('author_id', uid)
          .order('created_at', ascending: false);

      final followersData = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', uid)
          .eq('status', 'accepted');
      final followerIds = (followersData as List)
          .map((r) => r['follower_id'] as String)
          .toSet();

      final followingData = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted');
      final followingIds = (followingData as List)
          .map((r) => r['following_id'] as String)
          .toSet();

      final friendsCount = followerIds.intersection(followingIds).length;

      int likes = 0;
      for (final post in posts) {
        likes += (post['like_count'] as num?)?.toInt() ?? 0;
      }

      if (!mounted) return;
      setState(() {
        _profile = p;
        _posts = List<Map<String, dynamic>>.from(posts);
        _followersCount = followerIds.length;
        _friendsCount = friendsCount;
        _likes = likes;
        _loading = false;
      });
    } catch (e) {
      print('MY PROFILE LOAD ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ══════════════════════════════════════════════
  //  Avatar picker / upload / remove
  // ══════════════════════════════════════════════
  Future<void> _changeAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_profile?['avatar_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove current photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _removeAvatar();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null) return;

    await _uploadAvatar(File(picked.path));
  }

  Future<void> _uploadAvatar(File file) async {
    setState(() => _uploadingAvatar = true);
    final user = _client.auth.currentUser!;

    try {
      final path = '${user.id}.jpg';

      await _client.storage
          .from('avatars')
          .upload(
            path,
            file,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final baseUrl = _client.storage.from('avatars').getPublicUrl(path);
      final freshUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await _client
          .from('profiles')
          .update({'avatar_url': freshUrl})
          .eq('id', user.id);

      if (mounted) {
        setState(() {
          _profile = {...?_profile, 'avatar_url': freshUrl};
        });
      }
    } catch (e) {
      print('AVATAR UPLOAD ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final uid = _client.auth.currentUser!.id;
    setState(() => _uploadingAvatar = true);
    try {
      try {
        await _client.storage.from('avatars').remove(['$uid.jpg']);
      } catch (_) {}

      await _client.from('profiles').update({'avatar_url': null}).eq('id', uid);

      if (mounted) {
        setState(() {
          _profile = {...?_profile, 'avatar_url': null};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _openConnections(ConnectionMode mode) {
    final uid = _client.auth.currentUser!.id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(userId: uid, mode: mode),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  AppBar(
                    backgroundColor: AppColors.bg,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: const Text(
                      'Profile',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    centerTitle: true,
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                          child: Column(
                            children: [
                              // ─── Avatar ─────────────
                              GestureDetector(
                                onTap: _uploadingAvatar ? null : _changeAvatar,
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 52,
                                      backgroundColor: Colors.grey.shade300,
                                      backgroundImage:
                                          _profile?['avatar_url'] != null
                                          ? NetworkImage(
                                              _profile!['avatar_url'],
                                            )
                                          : null,
                                      child: _profile?['avatar_url'] == null
                                          ? const Icon(
                                              Icons.person,
                                              size: 50,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    if (_uploadingAvatar)
                                      Positioned.fill(
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black38,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.edit,
                                          size: 16,
                                          color: AppColors.red,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // ─── Name ───────────────
                              Text(
                                _profile?['display_name'] ?? 'Display Name',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: AppColors.red,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // ─── Year + Program ─────
                              Text(
                                _yearLabel(_profile?['year_level']),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _profile?['program'] ?? '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 20),

                              // ─── Stats (4 equal columns) ──
                              Row(
                                children: [
                                  Expanded(
                                    child: _clickableStat(
                                      '$_followersCount',
                                      'Followers',
                                      () => _openConnections(
                                        ConnectionMode.followers,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _clickableStat(
                                      '$_friendsCount',
                                      'Friends',
                                      () => _openConnections(
                                        ConnectionMode.friends,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _stat('${_posts.length}', 'Posts'),
                                  ),
                                  Expanded(child: _stat('$_likes', 'Likes')),
                                ],
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: 200,
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await _client.auth.signOut();
                                    if (mounted) {
                                      Navigator.of(context)
                                          .popUntil((r) => r.isFirst);
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    side: const BorderSide(
                                      color: AppColors.red,
                                    ),
                                    foregroundColor: AppColors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: const Text('Log out'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._posts.map(
                          (p) => PostCard(
                            key: ValueKey(p['id']),
                            post: p,
                            authorLabel: 'You',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReplyScreen(post: p),
                              ),
                            ),
                            onRemoved: () {
                              Future.microtask(() {
                                if (mounted) {
                                  setState(() {
                                    _posts.removeWhere(
                                      (x) => x['id'] == p['id'],
                                    );
                                  });
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  Stat helpers (no underline, equal width)
  // ══════════════════════════════════════════════
  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _clickableStat(String value, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.red.withOpacity(0.10),
        highlightColor: AppColors.red.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
