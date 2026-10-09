import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _client = Supabase.instance.client;
  final _nameController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final uid = _client.auth.currentUser!.id;

      final following = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted');
      final followingIds = (following as List)
          .map((r) => r['following_id'] as String)
          .toList();

      if (followingIds.isEmpty) {
        if (mounted) {
          setState(() {
            _friends = [];
            _loading = false;
          });
        }
        return;
      }

      final friends = await _client
          .from('follows')
          .select(
            'profiles!follows_follower_id_fkey(id, display_name, avatar_url, program, year_level)',
          )
          .eq('following_id', uid)
          .eq('status', 'accepted')
          .inFilter('follower_id', followingIds);

      final list = (friends as List)
          .map((r) => r['profiles'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .toList();

      if (!mounted) return;
      setState(() {
        _friends = list;
        _loading = false;
      });
    } catch (e) {
      print('LOAD FRIENDS ERROR: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give the group a name.')));
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one friend.')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final groupId = await _client.rpc(
        'create_group',
        params: {'group_name': name, 'member_ids': _selectedIds.toList()},
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GroupChatScreen(groupId: groupId as String, groupName: name),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create group: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Group',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_creating)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _create,
              child: const Text(
                'Create',
                style: TextStyle(
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Group name field
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups_outlined, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Group name...',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Add members',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                if (_selectedIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                : _friends.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'You need mutual friends to create a group.\n\n'
                        'Follow someone and wait for them to accept first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _friends.length,
                    itemBuilder: (_, i) {
                      final f = _friends[i];
                      final id = f['id'] as String;
                      final selected = _selectedIds.contains(id);
                      final avatar = f['avatar_url'] as String?;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedIds.remove(id);
                            } else {
                              _selectedIds.add(id);
                            }
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: avatar != null
                                    ? NetworkImage(avatar)
                                    : null,
                                child: avatar == null
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  f['display_name'] ?? 'User',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.red
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.red
                                        : Colors.grey.shade400,
                                    width: 1.5,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
