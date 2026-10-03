import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/post_card.dart';
import 'reply_screen.dart';
import 'chat_screen.dart';
import 'connections_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  int _followersCount = 0;
  int _friendsCount = 0;
  int _likes = 0;

  String? _myFollowStatus;
  String? _theirFollowStatus;
  bool _hasConversation = false;
  bool _loading = true;
  bool _busy = false;

  bool get _mutual =>
      _myFollowStatus == 'accepted' && _theirFollowStatus == 'accepted';

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
          .eq('id', widget.userId)
          .maybeSingle();

      final posts = await _client
          .from('posts_with_counts')
          .select(
            '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)',
          )
          .eq('author_id', widget.userId)
          .order('created_at', ascending: false);

      final followersData = await _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', widget.userId)
          .eq('status', 'accepted');
      final followerIds = (followersData as List)
          .map((r) => r['follower_id'] as String)
          .toSet();

      final followingData = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', widget.userId)
          .eq('status', 'accepted');
      final followingIds = (followingData as List)
          .map((r) => r['following_id'] as String)
          .toSet();

      final friendsCount = followerIds.intersection(followingIds).length;

      final mine = await _client
          .from('follows')
          .select('status')
          .eq('follower_id', uid)
          .eq('following_id', widget.userId)
          .maybeSingle();

      final theirs = await _client
          .from('follows')
          .select('status')
          .eq('follower_id', widget.userId)
          .eq('following_id', uid)
          .maybeSingle();

      final a = uid.compareTo(widget.userId) < 0 ? uid : widget.userId;
      final b = uid.compareTo(widget.userId) < 0 ? widget.userId : uid;
      final convo = await _client
          .from('conversations')
          .select('id')
          .eq('user_a', a)
          .eq('user_b', b)
          .maybeSingle();

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
        _myFollowStatus = mine?['status'] as String?;
        _theirFollowStatus = theirs?['status'] as String?;
        _hasConversation = convo != null;
        _loading = false;
      });
    } catch (e) {
      print('USER PROFILE LOAD ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ══════════════════════════════════════════════
  //  Follow / accept / unfollow
  // ══════════════════════════════════════════════
  Future<void> _handleFollowTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final uid = _client.auth.currentUser!.id;

    try {
      if (_myFollowStatus == 'pending') {
        await _client
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', widget.userId);
      } else if (_myFollowStatus == 'accepted') {
        await _client
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', widget.userId);
      } else {
        if (_theirFollowStatus == 'pending') {
          await _acceptTheirRequest(uid);
        } else {
          await _client.from('follows').insert({
            'follower_id': uid,
            'following_id': widget.userId,
            'status': 'pending',
          });
        }
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptTheirRequest(String uid) async {
    await _client
        .from('follows')
        .update({'status': 'accepted'})
        .eq('follower_id', widget.userId)
        .eq('following_id', uid);

    await _client.from('follows').insert({
      'follower_id': uid,
      'following_id': widget.userId,
      'status': 'accepted',
    });

    await _client.from('notifications').insert({
      'user_id': widget.userId,
      'actor_id': uid,
      'type': 'friend_accepted',
    });

    await _client
        .from('notifications')
        .delete()
        .eq('user_id', uid)
        .eq('actor_id', widget.userId)
        .eq('type', 'follow_request');
  }

  // ══════════════════════════════════════════════
  //  Message flow (mutual required)
  // ══════════════════════════════════════════════
  Future<void> _openChat() async {
    final uid = _client.auth.currentUser!.id;

    if (_hasConversation) {
      await _pushChat(uid);
      return;
    }
    if (!_mutual) {
      await _showGateDialog();
      return;
    }

    final a = uid.compareTo(widget.userId) < 0 ? uid : widget.userId;
    final b = uid.compareTo(widget.userId) < 0 ? widget.userId : uid;

    try {
      final created = await _client
          .from('conversations')
          .insert({'user_a': a, 'user_b': b})
          .select()
          .single();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: created['id'],
            otherUser: _profile ?? {},
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
      }
    }
  }

  Future<void> _pushChat(String uid) async {
    final a = uid.compareTo(widget.userId) < 0 ? uid : widget.userId;
    final b = uid.compareTo(widget.userId) < 0 ? widget.userId : uid;
    final convo = await _client
        .from('conversations')
        .select('id')
        .eq('user_a', a)
        .eq('user_b', b)
        .maybeSingle();
    if (convo == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(conversationId: convo['id'], otherUser: _profile ?? {}),
      ),
    );
  }

  Future<void> _showGateDialog() async {
    final name = _profile?['display_name'] ?? 'this user';

    String title;
    String body;
    bool showFollowButton = false;

    if (_theirFollowStatus == 'pending' && _myFollowStatus == null) {
      title = 'Accept $name\'s request?';
      body =
          '$name wants to follow you. Accept to become friends and start chatting.';
      showFollowButton = true;
    } else if (_myFollowStatus == 'pending') {
      title = 'Waiting for $name';
      body =
          'Your follow request is pending. You\'ll be able to chat once $name accepts.';
    } else if (_myFollowStatus == 'accepted' && !_mutual) {
      title = 'Not friends yet';
      body = 'You\'re following $name, but you\'re not mutual friends yet.';
    } else {
      title = 'Become friends to chat';
      body =
          'You and $name need to be mutual friends before you can message each other.';
      showFollowButton = true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          if (showFollowButton)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                _theirFollowStatus == 'pending' ? 'Accept' : 'Follow',
              ),
            ),
        ],
      ),
    );

    if (result == true) await _handleFollowTap();
  }

  String _followButtonLabel() {
    if (_myFollowStatus == 'pending') return 'Requested';
    if (_myFollowStatus == 'accepted') {
      return _mutual ? 'Friends' : 'Following';
    }
    if (_theirFollowStatus == 'pending') return 'Accept request';
    return 'Follow';
  }

  Color _followButtonBg() {
    if (_myFollowStatus == 'accepted' && _mutual) {
      return AppColors.lightRed;
    }
    if (_myFollowStatus == 'pending') return Colors.grey.shade200;
    return Colors.white;
  }

  void _openConnections(ConnectionMode mode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(userId: widget.userId, mode: mode),
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
                              CircleAvatar(
                                radius: 52,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: _profile?['avatar_url'] != null
                                    ? NetworkImage(_profile!['avatar_url'])
                                    : null,
                                child: _profile?['avatar_url'] == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 12),

                              // ─── Name ───────────────
                              Text(
                                _profile?['display_name'] ?? 'User',
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

                              // ─── Stats ──────────────
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

                              // ─── Actions ────────────
                              Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : _handleFollowTap,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          side: const BorderSide(
                                            color: AppColors.red,
                                          ),
                                          foregroundColor: AppColors.red,
                                          backgroundColor: _followButtonBg(),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                        ),
                                        child: Text(_followButtonLabel()),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: _buildMessageButton(),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._posts.map(
                          (p) => PostCard(
                            key: ValueKey(p['id']),
                            post: p,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReplyScreen(post: p),
                              ),
                            ),
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

  Widget _buildMessageButton() {
    final canMessage = _mutual || _hasConversation;
    return OutlinedButton(
      onPressed: _openChat,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        side: BorderSide(
          color: canMessage ? AppColors.red : Colors.grey.shade400,
        ),
        foregroundColor: canMessage ? AppColors.red : Colors.grey.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!canMessage) ...[
            Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
          ],
          const Text('Message'),
        ],
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
