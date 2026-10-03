import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme.dart';
import 'chat_screen.dart';
import 'my_profile_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  String? _myAvatarUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMyAvatar();
    _load();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _client.auth.currentUser!.id;

      // ─── Existing conversations ──────────────
      final convData = await _client
          .from('conversations')
          .select('*')
          .or('user_a.eq.$uid,user_b.eq.$uid');

      final conversations = <Map<String, dynamic>>[];
      final friendIdsInChats = <String>{};

      for (final row in convData as List) {
        final conv = Map<String, dynamic>.from(row);
        final otherId = conv['user_a'] == uid ? conv['user_b'] : conv['user_a'];
        friendIdsInChats.add(otherId as String);

        final other = await _client
            .from('profiles')
            .select('id, display_name, avatar_url')
            .eq('id', otherId)
            .maybeSingle();

        final last = await _client
            .from('messages')
            .select()
            .eq('conversation_id', conv['id'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        conversations.add({
          'kind': 'conversation',
          'conversation_id': conv['id'],
          'other_user': other,
          'last_message': last,
          'sort_time': last?['created_at'] ?? conv['created_at'],
        });
      }

      // ─── Mutual friends (no chat yet) ────────
      final myFollows = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted');
      final myFollowIds = (myFollows as List)
          .map((r) => r['following_id'] as String)
          .toList();

      final friendsWithNoChat = <Map<String, dynamic>>[];

      if (myFollowIds.isNotEmpty) {
        final theirFollows = await _client
            .from('follows')
            .select(
              'follower_id, profiles!follows_follower_id_fkey(id, display_name, avatar_url)',
            )
            .eq('following_id', uid)
            .eq('status', 'accepted')
            .inFilter('follower_id', myFollowIds);

        for (final row in theirFollows as List) {
          final friendId = row['follower_id'] as String;
          if (friendIdsInChats.contains(friendId)) continue;
          final profile = row['profiles'];
          friendsWithNoChat.add({
            'kind': 'new_friend',
            'other_user': profile,
            'sort_time': null,
          });
        }
      }

      final all = [...conversations, ...friendsWithNoChat];
      all.sort((a, b) {
        final aT = a['sort_time']?.toString() ?? '';
        final bT = b['sort_time']?.toString() ?? '';
        if (aT.isEmpty && bT.isEmpty) return 0;
        if (aT.isEmpty) return -1;
        if (bT.isEmpty) return 1;
        return bT.compareTo(aT);
      });

      if (!mounted) return;
      setState(() {
        _rows = all;
        _loading = false;
      });
    } catch (e) {
      print('MESSAGES LOAD ERROR: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    final uid = _client.auth.currentUser!.id;
    final other = row['other_user'] ?? {};
    final otherId = other['id'] as String?;
    if (otherId == null) return;

    String convoId = row['conversation_id'] ?? '';

    if (convoId.isEmpty) {
      final a = uid.compareTo(otherId) < 0 ? uid : otherId;
      final b = uid.compareTo(otherId) < 0 ? otherId : uid;
      try {
        final existing = await _client
            .from('conversations')
            .select('id')
            .eq('user_a', a)
            .eq('user_b', b)
            .maybeSingle();
        if (existing != null) {
          convoId = existing['id'];
        } else {
          final created = await _client
              .from('conversations')
              .insert({'user_a': a, 'user_b': b})
              .select()
              .single();
          convoId = created['id'];
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
        }
        return;
      }
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: convoId,
          otherUser: Map<String, dynamic>.from(other),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header (matched to other tabs) ────
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
                    'Chat',
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
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
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
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _rows.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 32,
                                    ),
                                    child: Text(
                                      'No friends yet.\n\nFollow someone and wait for them to accept to start chatting.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              itemCount: _rows.length,
                              itemBuilder: (_, i) {
                                final r = _rows[i];
                                final other = r['other_user'] ?? {};
                                final last = r['last_message'];
                                final isNewFriend = r['kind'] == 'new_friend';

                                return ListTile(
                                  tileColor: Colors.white,
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.grey.shade300,
                                    backgroundImage: other['avatar_url'] != null
                                        ? NetworkImage(other['avatar_url'])
                                        : null,
                                    child: other['avatar_url'] == null
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    other['display_name'] ?? 'User',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isNewFriend
                                        ? 'You are now connected. Say Hi!'
                                        : (last?['body'] ?? 'Say hi!'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isNewFriend
                                          ? AppColors.red
                                          : Colors.grey.shade600,
                                      fontSize: 12,
                                      fontStyle: isNewFriend
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                  trailing: last != null
                                      ? Text(
                                          timeago.format(
                                            DateTime.parse(last['created_at'])
                                                .toLocal(),
                                            allowFromNow: true,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        )
                                      : null,
                                  onTap: () => _openRow(r),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
