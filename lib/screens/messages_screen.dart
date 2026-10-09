import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme.dart';
import 'chat_screen.dart';
import 'my_profile_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';

enum _Mode { direct, groups }

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _client = Supabase.instance.client;

  _Mode _mode = _Mode.direct;
  List<Map<String, dynamic>> _directRows = [];
  List<Map<String, dynamic>> _groupRows = [];

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
      await Future.wait([_loadDirect(uid), _loadGroups(uid)]);
      if (!mounted) return;
      setState(() => _loading = false);
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

  Future<void> _loadDirect(String uid) async {
    // ─── Existing conversations ───
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

    // ─── Mutual friends with no chat yet ───
    final myFollows = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', uid)
        .eq('status', 'accepted');
    final myFollowIds = (myFollows as List)
        .map((r) => r['following_id'] as String)
        .toList();

    final newFriends = <Map<String, dynamic>>[];
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
        newFriends.add({
          'kind': 'new_friend',
          'other_user': profile,
          'sort_time': null,
        });
      }
    }

    final all = [...conversations, ...newFriends];
    all.sort((a, b) {
      final aT = a['sort_time']?.toString() ?? '';
      final bT = b['sort_time']?.toString() ?? '';
      if (aT.isEmpty && bT.isEmpty) return 0;
      if (aT.isEmpty) return -1;
      if (bT.isEmpty) return 1;
      return bT.compareTo(aT);
    });

    if (mounted) setState(() => _directRows = all);
  }

  Future<void> _loadGroups(String uid) async {
    // Groups I'm a member of
    final memberRows = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final groupIds = (memberRows as List)
        .map((r) => r['group_id'] as String)
        .toList();

    if (groupIds.isEmpty) {
      if (mounted) setState(() => _groupRows = []);
      return;
    }

    final groups = await _client
        .from('group_conversations')
        .select()
        .inFilter('id', groupIds);

    final rows = <Map<String, dynamic>>[];
    for (final g in groups as List) {
      final group = Map<String, dynamic>.from(g);
      final last = await _client
          .from('group_messages')
          .select()
          .eq('group_id', group['id'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      // Member count
      final countRes = await _client
          .from('group_members')
          .select('user_id')
          .eq('group_id', group['id']);

      group['last_message'] = last;
      group['member_count'] = (countRes as List).length;
      group['sort_time'] = last?['created_at'] ?? group['created_at'];
      rows.add(group);
    }

    rows.sort((a, b) {
      final aT = a['sort_time']?.toString() ?? '';
      final bT = b['sort_time']?.toString() ?? '';
      return bT.compareTo(aT);
    });

    if (mounted) setState(() => _groupRows = rows);
  }

  Future<void> _openDirect(Map<String, dynamic> row) async {
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

  Future<void> _openGroup(Map<String, dynamic> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupId: row['id'] as String,
          groupName: row['name'] as String? ?? 'Group',
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
            // ─── Header ───
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

            // ─── Mode toggle ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  _modeChip('Direct', _Mode.direct),
                  const SizedBox(width: 8),
                  _modeChip('Groups', _Mode.groups),
                  const Spacer(),
                  if (_mode == _Mode.groups)
                    IconButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateGroupScreen(),
                          ),
                        );
                        _load();
                      },
                      icon: const Icon(
                        Icons.group_add_outlined,
                        color: AppColors.red,
                      ),
                      tooltip: 'New group',
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
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
                      child: _mode == _Mode.direct
                          ? _buildDirectList()
                          : _buildGroupList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectList() {
    if (_directRows.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No friends yet.\n\nFollow someone and wait for them to accept to start chatting.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: _directRows.length,
      itemBuilder: (_, i) {
        final r = _directRows[i];
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
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          title: Text(
            other['display_name'] ?? 'User',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            isNewFriend
                ? 'You are now connected. Say Hi!'
                : (last?['body'] ?? 'Say hi!'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isNewFriend ? AppColors.red : Colors.grey.shade600,
              fontSize: 12,
              fontStyle: isNewFriend ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          trailing: last != null
              ? Text(
                  timeago.format(
                    DateTime.parse(last['created_at']).toLocal(),
                    allowFromNow: true,
                  ),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                )
              : null,
          onTap: () => _openDirect(r),
        );
      },
    );
  }

  Widget _buildGroupList() {
    if (_groupRows.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No groups yet.\n\nTap the group icon at the top to start one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: _groupRows.length,
      itemBuilder: (_, i) {
        final g = _groupRows[i];
        final last = g['last_message'];
        final name = g['name'] as String? ?? 'Group';
        final initial = name.trim().isEmpty
            ? '?'
            : name.trim()[0].toUpperCase();
        return ListTile(
          tileColor: Colors.white,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.red,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            last?['body'] ?? '${g['member_count'] ?? 0} members',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          trailing: last != null
              ? Text(
                  timeago.format(
                    DateTime.parse(last['created_at']).toLocal(),
                    allowFromNow: true,
                  ),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                )
              : null,
          onTap: () => _openGroup(g),
        );
      },
    );
  }

  Widget _modeChip(String label, _Mode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        if (_mode == mode) return;
        setState(() => _mode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.red : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.red : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
