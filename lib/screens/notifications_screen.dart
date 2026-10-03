import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme.dart';
import 'my_profile_screen.dart';
import 'reply_screen.dart';
import 'user_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  String? _myAvatarUrl;
  bool _loading = true;
  final Set<String> _processing = {}; // actor ids being accepted/rejected
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMyAvatar();
    _load();
    final uid = _client.auth.currentUser!.id;
    _channel = _client
        .channel('notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMyAvatar() async {
    final uid = _client.auth.currentUser!.id;
    final data = await _client
        .from('profiles')
        .select('avatar_url')
        .eq('id', uid)
        .maybeSingle();
    if (mounted) setState(() => _myAvatarUrl = data?['avatar_url']);
  }

  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;
      final data = await _client
          .from('notifications')
          .select(
            '*, actor:profiles!notifications_actor_id_fkey(display_name, avatar_url, program, year_level)',
          )
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      print('NOTIFICATIONS LOAD ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ══════════════════════════════════════════════
  //  Accept / Reject follow requests
  // ══════════════════════════════════════════════
  Future<void> _accept(String actorId) async {
    if (_processing.contains(actorId)) return;
    setState(() => _processing.add(actorId));
    final uid = _client.auth.currentUser!.id;

    try {
      // Mark their request as accepted
      await _client
          .from('follows')
          .update({'status': 'accepted'})
          .eq('follower_id', actorId)
          .eq('following_id', uid);

      // Create my follow-back (also accepted)
      // Wrap in try/catch in case my side already exists
      try {
        await _client.from('follows').insert({
          'follower_id': uid,
          'following_id': actorId,
          'status': 'accepted',
        });
      } catch (_) {
        // already follows — ignore
      }

      // Notify them: "you are now friends"
      try {
        await _client.from('notifications').insert({
          'user_id': actorId,
          'actor_id': uid,
          'type': 'friend_accepted',
        });
      } catch (_) {}

      // Remove the follow_request notification from my list
      await _client
          .from('notifications')
          .delete()
          .eq('user_id', uid)
          .eq('actor_id', actorId)
          .eq('type', 'follow_request');

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Accept failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing.remove(actorId));
    }
  }

  Future<void> _reject(String actorId) async {
    if (_processing.contains(actorId)) return;
    setState(() => _processing.add(actorId));
    final uid = _client.auth.currentUser!.id;

    try {
      // Delete their follow request
      await _client
          .from('follows')
          .delete()
          .eq('follower_id', actorId)
          .eq('following_id', uid)
          .eq('status', 'pending');

      // Remove the notification
      await _client
          .from('notifications')
          .delete()
          .eq('user_id', uid)
          .eq('actor_id', actorId)
          .eq('type', 'follow_request');

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reject failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing.remove(actorId));
    }
  }

  // ══════════════════════════════════════════════
  //  Tap handler (non-request types)
  // ══════════════════════════════════════════════
  Future<void> _handleTap(Map<String, dynamic> n) async {
    final type = n['type'] as String?;

    if (type == 'follow_request') return; // uses Accept/Reject buttons
    if (type == 'friend_accepted' || type == 'follow') {
      final actorId = n['actor_id'] as String?;
      if (actorId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UserProfileScreen(userId: actorId)),
        );
      }
      return;
    }

    final postId = n['post_id'] as String?;
    if (postId == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final postData = await _client
          .from('posts_with_counts')
          .select(
            '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)',
          )
          .eq('id', postId)
          .maybeSingle();

      if (mounted) Navigator.pop(context);

      if (postData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This post was deleted.')),
          );
        }
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ReplyScreen(post: Map<String, dynamic>.from(postData)),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open post: $e')));
      }
    }
  }

  String _text(Map<String, dynamic> n) {
    switch (n['type']) {
      case 'like':
        return ' liked your post';
      case 'reply':
        return ' replied to your post';
      case 'follow_request':
        return ' wants to follow you';
      case 'friend_accepted':
        return ' — you are now friends';
      case 'follow':
        return ' followed you';
      default:
        return ' sent a notification';
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'reply':
        return Icons.chat_bubble;
      case 'follow_request':
        return Icons.person_add;
      case 'friend_accepted':
        return Icons.people;
      case 'follow':
        return Icons.person_add;
      default:
        return Icons.notifications;
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
                    'Notifications',
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
                      _loadMyAvatar();
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(child: Text('No notifications yet.')),
                              ],
                            )
                          : ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final n = _items[i];
                                return _buildRow(n);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> n) {
    final actor = n['actor'] ?? {};
    final type = n['type'] as String?;
    final isRequest = type == 'follow_request';
    final actorId = n['actor_id'] as String?;
    final processing = actorId != null && _processing.contains(actorId);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: isRequest ? null : () => _handleTap(n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: actor['avatar_url'] != null
                            ? NetworkImage(actor['avatar_url'])
                            : null,
                        child: actor['avatar_url'] == null
                            ? const Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconFor(type),
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: actor['display_name'] ?? 'Someone',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: _text(n)),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    n['created_at'] != null
                        ? timeago.format(
                            DateTime.parse(n['created_at']).toLocal(),
                            allowFromNow: true,
                          )
                        : '',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (!isRequest) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ],
              ),
              if (isRequest) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 52), // align under text
                    Expanded(
                      child: OutlinedButton(
                        onPressed: processing
                            ? null
                            : () => _reject(actorId ?? ''),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: BorderSide(color: Colors.grey.shade400),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: processing
                            ? null
                            : () => _accept(actorId ?? ''),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: processing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
