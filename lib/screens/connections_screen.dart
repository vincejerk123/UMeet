import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'user_profile_screen.dart';

enum ConnectionMode { followers, friends }

class ConnectionsScreen extends StatefulWidget {
  final String userId;
  final ConnectionMode mode;
  const ConnectionsScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.mode == ConnectionMode.followers) {
        // People who follow this user (accepted)
        final data = await _client
            .from('follows')
            .select(
              'follower_id, profiles!follows_follower_id_fkey(id, display_name, avatar_url, program, year_level)',
            )
            .eq('following_id', widget.userId)
            .eq('status', 'accepted');

        final list = (data as List)
            .map((r) => r['profiles'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .toList();

        if (!mounted) return;
        setState(() {
          _people = list;
          _loading = false;
        });
      } else {
        // Friends = mutual accepted follows

        // 1) Who follows X
        final followersData = await _client
            .from('follows')
            .select('follower_id')
            .eq('following_id', widget.userId)
            .eq('status', 'accepted');
        final followerIds = (followersData as List)
            .map((r) => r['follower_id'] as String)
            .toSet();

        if (followerIds.isEmpty) {
          if (!mounted) return;
          setState(() {
            _people = [];
            _loading = false;
          });
          return;
        }

        // 2) Of those, who X follows back
        final friendsData = await _client
            .from('follows')
            .select(
              'following_id, profiles!follows_following_id_fkey(id, display_name, avatar_url, program, year_level)',
            )
            .eq('follower_id', widget.userId)
            .eq('status', 'accepted')
            .inFilter('following_id', followerIds.toList());

        final list = (friendsData as List)
            .map((r) => r['profiles'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .toList();

        if (!mounted) return;
        setState(() {
          _people = list;
          _loading = false;
        });
      }
    } catch (e) {
      print('CONNECTIONS LOAD ERROR: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == ConnectionMode.followers
        ? 'Followers'
        : 'Friends';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _people.isEmpty
          ? Center(
              child: Text(
                widget.mode == ConnectionMode.followers
                    ? 'No followers yet.'
                    : 'No friends yet.',
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _people.length,
                itemBuilder: (_, i) {
                  final p = _people[i];
                  return _PersonTile(
                    profile: p,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: p['id']),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onTap;

  const _PersonTile({required this.profile, required this.onTap});

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
  Widget build(BuildContext context) {
    final name = profile['display_name'] ?? 'User';
    final program = profile['program'];
    final year = profile['year_level'];
    final avatar = profile['avatar_url'];

    final subtitleParts = <String>[];
    if (year != null) subtitleParts.add(_yearLabel(year));
    if (program != null) subtitleParts.add(program);
    final subtitle = subtitleParts.join(' | ');

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? const Icon(Icons.person, size: 22, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
