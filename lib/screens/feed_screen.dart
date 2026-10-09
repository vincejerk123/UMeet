import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../utils/transitions.dart';
import '../widgets/post_card.dart';
import '../widgets/compose_sheet.dart';
import 'reply_screen.dart';
import 'my_profile_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  String? _myAvatarUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _loadWithRetry();
  }

  Future<void> _loadWithRetry() async {
    try {
      await _load(timeout: const Duration(seconds: 20));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        await _load(timeout: const Duration(seconds: 20));
      } catch (_) {}
    }
  }

  Future<void> _loadMyProfile() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final data = await _client
          .from('profiles')
          .select('avatar_url')
          .eq('id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _myAvatarUrl = data?['avatar_url']);
    } catch (_) {}
  }

  Future<void> _load({Duration? timeout}) async {
    if (mounted) setState(() => _error = null);
    try {
      final uid = _client.auth.currentUser!.id;

      final blockedRows = await _client
          .from('blocked_users')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$uid,blocked_id.eq.$uid')
          .timeout(timeout ?? const Duration(seconds: 15));
      final blockedIds = <String>{};
      for (final row in blockedRows as List) {
        blockedIds.add(
          row['blocker_id'] == uid
              ? row['blocked_id'] as String
              : row['blocker_id'] as String,
        );
      }

      final hiddenRows = await _client
          .from('hidden_posts')
          .select('post_id')
          .eq('user_id', uid)
          .timeout(timeout ?? const Duration(seconds: 15));
      final hiddenIds = (hiddenRows as List)
          .map((r) => r['post_id'] as String)
          .toList();

      var q = _client
          .from('posts_with_counts')
          .select(
            '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)',
          );

      if (hiddenIds.isNotEmpty) {
        q = q.not('id', 'in', '(${hiddenIds.join(',')})');
      }
      if (blockedIds.isNotEmpty) {
        q = q.not('author_id', 'in', '(${blockedIds.join(',')})');
      }

      final data = await q
          .order('created_at', ascending: false)
          .limit(60)
          .timeout(timeout ?? const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _posts = List<Map<String, dynamic>>.from(data);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      print('FEED LOAD ERROR: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 22, color: Colors.grey.shade300),
                  const SizedBox(width: 8),
                  const Text(
                    'Community',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyProfileScreen(),
                        ),
                      );
                      _loadMyProfile();
                    },
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: _myAvatarUrl != null
                          ? NetworkImage(_myAvatarUrl!)
                          : null,
                      child: _myAvatarUrl == null
                          ? const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFEEEEEE),
                    backgroundImage: _myAvatarUrl != null
                        ? NetworkImage(_myAvatarUrl!)
                        : null,
                    child: _myAvatarUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final ok = await showComposeSheet(context);
                        if (ok == true) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Text(
                          "What's on your mind?",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      final ok = await showComposeSheet(context);
                      if (ok == true) _load();
                    },
                    icon: const Icon(Icons.send, color: AppColors.red),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading posts...',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                "Couldn't load posts",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _loadWithRetry();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  side: const BorderSide(color: AppColors.red),
                  foregroundColor: AppColors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No posts yet. Be the first!')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (_, i) {
          final p = _posts[i];
          return PostCard(
            key: ValueKey(p['id']),
            post: p,
            onTap: () =>
                Navigator.push(context, smoothOpenRoute(ReplyScreen(post: p))),
            onRemoved: () {
              Future.microtask(() {
                if (mounted) _load();
              });
            },
          );
        },
      ),
    );
  }
}
