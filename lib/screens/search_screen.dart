import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../utils/transitions.dart';
import '../widgets/post_card.dart';
import 'reply_screen.dart';
import 'my_profile_screen.dart';
import 'user_profile_screen.dart';

enum SearchMode { posts, people }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _client = Supabase.instance.client;
  final _q = TextEditingController();

  SearchMode _mode = SearchMode.posts;
  List<Map<String, dynamic>> _postResults = [];
  List<Map<String, dynamic>> _peopleResults = [];
  String? _myAvatarUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMyAvatar();
    _search('');
  }

  @override
  void dispose() {
    _q.dispose();
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

  Future<Set<String>> _fetchBlockedIds(String uid) async {
    final rows = await _client
        .from('blocked_users')
        .select('blocker_id, blocked_id')
        .or('blocker_id.eq.$uid,blocked_id.eq.$uid');
    final ids = <String>{};
    for (final row in rows as List) {
      ids.add(
        row['blocker_id'] == uid
            ? row['blocked_id'] as String
            : row['blocker_id'] as String,
      );
    }
    return ids;
  }

  Future<void> _refresh() async {
    await _search(_q.text, silent: true);
  }

  Future<void> _search(String query, {bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    if (_mode == SearchMode.posts) {
      await _searchPosts(query);
    } else {
      await _searchPeople(query);
    }
    if (silent && mounted) setState(() => _loading = false);
  }

  Future<void> _searchPosts(String query) async {
    try {
      final uid = _client.auth.currentUser!.id;
      final blockedIds = await _fetchBlockedIds(uid);

      final hiddenRows = await _client
          .from('hidden_posts')
          .select('post_id')
          .eq('user_id', uid);
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
      if (query.trim().isNotEmpty) {
        q = q.textSearch('search_vector', query.trim(), config: 'english');
      }

      final data = await q.order('created_at', ascending: false).limit(50);

      if (mounted) {
        setState(() {
          _postResults = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      print('SEARCH POSTS ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchPeople(String query) async {
    try {
      final uid = _client.auth.currentUser!.id;
      final blockedIds = await _fetchBlockedIds(uid);
      final trimmed = query.trim();

      var q = _client
          .from('profiles')
          .select('id, display_name, avatar_url, program, year_level')
          .neq('id', uid);

      if (blockedIds.isNotEmpty) {
        q = q.not('id', 'in', '(${blockedIds.join(',')})');
      }
      if (trimmed.isNotEmpty) {
        q = q.ilike('display_name', '%$trimmed%');
      }

      final data = await q.order('display_name').limit(50);
      final seen = <String>{};
      final list = <Map<String, dynamic>>[];
      for (final row in data) {
        final id = row['id'] as String;
        if (seen.add(id)) list.add(Map<String, dynamic>.from(row));
      }
      if (mounted) {
        setState(() {
          _peopleResults = list;
          _loading = false;
        });
      }
    } catch (e) {
      print('SEARCH PEOPLE ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchMode(SearchMode m) {
    if (_mode == m) return;
    setState(() {
      _mode = m;
      _postResults = [];
      _peopleResults = [];
    });
    _search(_q.text);
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
                    'Explore',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        slideInRoute(const MyProfileScreen()),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _mode == SearchMode.posts ? 'Search Topics' : 'Search People',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                onChanged: (v) {
                  if (v.isEmpty) _search('');
                },
                decoration: InputDecoration(
                  hintText: _mode == SearchMode.posts
                      ? 'Search topics ...'
                      : 'Search people by name ...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _modeChip('Posts', SearchMode.posts),
                  const SizedBox(width: 8),
                  _modeChip('People', SearchMode.people),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _mode == SearchMode.posts
                  ? _buildPostsResults()
                  : _buildPeopleResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsResults() {
    if (_postResults.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            Center(child: Text('No results found.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _postResults.length,
        itemBuilder: (_, i) {
          final p = _postResults[i];
          return PostCard(
            key: ValueKey(p['id']),
            post: p,
            onTap: () =>
                Navigator.push(context, smoothOpenRoute(ReplyScreen(post: p))),
            onRemoved: () {
              Future.microtask(() {
                if (mounted) _search(_q.text, silent: true);
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildPeopleResults() {
    if (_peopleResults.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            Center(child: Text('No people found.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _peopleResults.length,
        itemBuilder: (_, i) {
          final p = _peopleResults[i];
          return _PersonTile(
            profile: p,
            onTap: () => Navigator.push(
              context,
              slideInRoute(UserProfileScreen(userId: p['id'])),
            ),
          );
        },
      ),
    );
  }

  Widget _modeChip(String label, SearchMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => _switchMode(mode),
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
