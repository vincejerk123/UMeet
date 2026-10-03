import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../theme.dart';
import '../widgets/post_card.dart';
import '../widgets/svg_reaction_button.dart';

class ReplyScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  const ReplyScreen({super.key, required this.post});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Fresh copy of the post (refreshed on mount)
  late Map<String, dynamic> _post;
  bool _postReady = false;

  List<Map<String, dynamic>> _comments = [];
  final Map<String, Map<String, dynamic>> _voteMap = {};
  final Map<String, Map<String, dynamic>> _commentById = {};

  String? _replyToCommentId;
  String? _replyToUsername;

  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _refreshPost();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════
  //  Fetch fresh post data so counts aren't stale
  // ══════════════════════════════════════════════
  Future<void> _refreshPost() async {
    try {
      final data = await _client
          .from('posts_with_counts')
          .select(
              '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)')
          .eq('id', widget.post['id'])
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        if (data != null) {
          _post = Map<String, dynamic>.from(data);
        }
        _postReady = true;
      });
    } catch (e) {
      print('POST REFRESH ERROR: $e');
      if (mounted) setState(() => _postReady = true);
    }
  }

  // ══════════════════════════════════════════════
  //  Load comments + reactions
  // ══════════════════════════════════════════════
  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;

      final data = await _client
          .from('comments')
          .select(
              '*, profiles!comments_author_id_fkey(display_name, avatar_url)')
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(data);

      _commentById.clear();
      for (final c in list) {
        _commentById[c['id'] as String] = c;
      }

      _voteMap.clear();
      if (list.isNotEmpty) {
        final ids = list.map((c) => c['id'] as String).toList();
        final votes = await _client
            .from('comment_votes')
            .select()
            .inFilter('comment_id', ids);

        for (final id in ids) {
          _voteMap[id] = {
            'like_count': 0,
            'dislike_count': 0,
            'my_vote': 0,
          };
        }

        for (final v in (votes as List)) {
          final cid = v['comment_id'] as String;
          final val = (v['value'] as num).toInt();
          final bucket = _voteMap[cid];
          if (bucket == null) continue;
          if (val == 1) {
            bucket['like_count'] = (bucket['like_count'] as int) + 1;
          } else if (val == -1) {
            bucket['dislike_count'] =
                (bucket['dislike_count'] as int) + 1;
          }
          if (v['user_id'] == uid) {
            bucket['my_vote'] = val;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _comments = list;
        _loading = false;
      });
    } catch (e) {
      print('REPLIES LOAD ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ══════════════════════════════════════════════
  //  Comment reactions
  // ══════════════════════════════════════════════
  Future<void> _toggleCommentVote(String commentId, int value) async {
    final user = _client.auth.currentUser!;
    final bucket = _voteMap[commentId];
    if (bucket == null) return;

    final prevVote = (bucket['my_vote'] as num).toInt();
    final prevLikes = (bucket['like_count'] as num).toInt();
    final prevDislikes = (bucket['dislike_count'] as num).toInt();

    final newVote = (prevVote == value) ? 0 : value;
    final newLikes =
        prevLikes + (newVote == 1 ? 1 : 0) - (prevVote == 1 ? 1 : 0);
    final newDislikes =
        prevDislikes + (newVote == -1 ? 1 : 0) - (prevVote == -1 ? 1 : 0);

    setState(() {
      bucket['my_vote'] = newVote;
      bucket['like_count'] = newLikes;
      bucket['dislike_count'] = newDislikes;
    });

    try {
      if (newVote == 0) {
        await _client
            .from('comment_votes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', user.id);
      } else {
        await _client.from('comment_votes').upsert({
          'comment_id': commentId,
          'user_id': user.id,
          'value': newVote,
        });
      }
    } catch (e) {
      setState(() {
        bucket['my_vote'] = prevVote;
        bucket['like_count'] = prevLikes;
        bucket['dislike_count'] = prevDislikes;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  // ══════════════════════════════════════════════
  //  Reply composer helpers
  // ══════════════════════════════════════════════
  void _startReply(Map<String, dynamic> comment) {
    final author = comment['profiles'] ?? {};
    final username = author['display_name'] ?? 'user';
    setState(() {
      _replyToCommentId = comment['id'];
      _replyToUsername = username;
      _controller.text = '@$username ';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUsername = null;
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final user = _client.auth.currentUser!;

    try {
      await _client.from('comments').insert({
        'post_id': widget.post['id'],
        'author_id': user.id,
        'body': text,
        if (_replyToCommentId != null) 'parent_id': _replyToCommentId,
      });

      _controller.clear();
      _focusNode.unfocus();
      setState(() {
        _replyToCommentId = null;
        _replyToUsername = null;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ══════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final myUserId = _client.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Replies',
            style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ─── Show placeholder until post is refreshed ───
          if (_postReady)
            PostCard(
              post: _post,
              imageLayout: PostImageLayout.large,
            )
          else
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(
                        child: Text('No replies yet.',
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) {
                            final c = _comments[i];
                            final isReply = c['parent_id'] != null;
                            final parentName = isReply
                                ? (_commentById[c['parent_id']]
                                            ?['profiles']
                                        ?['display_name'] ??
                                    'user')
                                : null;

                            return _CommentTile(
                              key: ValueKey(c['id']),
                              comment: c,
                              voteData: _voteMap[c['id']] ?? {},
                              isReply: isReply,
                              parentUsername: parentName,
                              myUserId: myUserId,
                              onVote: (v) =>
                                  _toggleCommentVote(c['id'], v),
                              onReply: () => _startReply(c),
                              onRemoved: () {
                                Future.microtask(() {
                                  if (mounted) {
                                    setState(() {
                                      _comments.removeWhere((x) =>
                                          x['id'] == c['id']);
                                      _voteMap.remove(c['id']);
                                    });
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
          ),

          if (_replyToUsername != null)
            Container(
              color: AppColors.lightRed.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: AppColors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to @$_replyToUsername',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Icon(Icons.close,
                        size: 18, color: AppColors.red),
                  ),
                ],
              ),
            ),

          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: _replyToUsername == null
                            ? 'Write a reply...'
                            : 'Write your reply...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: AppColors.chipBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2),
                      ),
                    )
                  else
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _send,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SvgPicture.asset(
                            'assets/icons/send.svg',
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                                AppColors.red, BlendMode.srcIn),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════
//  Comment tile
// ════════════════════════════════════════════════════
class _CommentTile extends StatefulWidget {
  final Map<String, dynamic> comment;
  final Map<String, dynamic> voteData;
  final bool isReply;
  final String? parentUsername;
  final String myUserId;
  final ValueChanged<int> onVote;
  final VoidCallback onReply;
  final VoidCallback onRemoved;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.voteData,
    required this.isReply,
    required this.parentUsername,
    required this.myUserId,
    required this.onVote,
    required this.onReply,
    required this.onRemoved,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile>
    with TickerProviderStateMixin {
  final _client = Supabase.instance.client;

  late AnimationController _likeBounce;
  late AnimationController _dislikeBounce;
  late Animation<double> _likeScale;
  late Animation<double> _dislikeScale;

  bool get _isMine => widget.comment['author_id'] == widget.myUserId;

  @override
  void initState() {
    super.initState();
    _likeBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _dislikeBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _likeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
        parent: _likeBounce, curve: Curves.easeOutBack));
    _dislikeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
        parent: _dislikeBounce, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _likeBounce.dispose();
    _dislikeBounce.dispose();
    super.dispose();
  }

  void _onLikeTap() {
    _likeBounce.forward(from: 0);
    HapticFeedback.lightImpact();
    widget.onVote(1);
  }

  void _onDislikeTap() {
    _dislikeBounce.forward(from: 0);
    HapticFeedback.lightImpact();
    widget.onVote(-1);
  }

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (_isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.red),
                title: const Text('Delete comment',
                    style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide this comment'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onRemoved();
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report comment'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Thanks — reports coming soon.')),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text(
            'This will permanently remove your comment and any replies to it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client
          .from('comments')
          .delete()
          .eq('id', widget.comment['id']);
      widget.onRemoved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final profile = comment['profiles'] ?? {};
    final name = profile['display_name'] ?? 'user';
    final avatar = profile['avatar_url'];
    final createdAt = comment['created_at'];
    final time = createdAt != null
        ? timeago.format(DateTime.parse(createdAt).toLocal())
        : '';

    final myVote =
        (widget.voteData['my_vote'] as num?)?.toInt() ?? 0;
    final likeCount =
        (widget.voteData['like_count'] as num?)?.toInt() ?? 0;
    final dislikeCount =
        (widget.voteData['dislike_count'] as num?)?.toInt() ?? 0;

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 1),
      padding: EdgeInsets.fromLTRB(
          widget.isReply ? 40 : 16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isReply && widget.parentUsername != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('replying to @${widget.parentUsername}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500)),
                ],
              ),
            ),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade300,
                backgroundImage:
                    avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null
                    ? const Icon(Icons.person,
                        size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(time,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _openMenu,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.more_horiz,
                      size: 18, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 6),
            child: Text(comment['body'] ?? '',
                style: const TextStyle(fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 2),
            child: Row(
              children: [
                SvgReactionButton(
                  svgPath: myVote == 1
                      ? 'assets/icons/like_filled.svg'
                      : 'assets/icons/like_outline.svg',
                  count: likeCount,
                  active: myVote == 1,
                  activeColor: AppColors.red,
                  onTap: _onLikeTap,
                  scale: _likeScale,
                  iconSize: 18,
                  countFontSize: 12,
                ),
                const SizedBox(width: 4),
                SvgReactionButton(
                  svgPath: myVote == -1
                      ? 'assets/icons/dislike_filled.svg'
                      : 'assets/icons/dislike_outline.svg',
                  count: dislikeCount,
                  active: myVote == -1,
                  activeColor: Colors.blueGrey,
                  onTap: _onDislikeTap,
                  scale: _dislikeScale,
                  iconSize: 18,
                  countFontSize: 12,
                ),
                const SizedBox(width: 4),
                SvgReactionButton(
                  svgPath: 'assets/icons/reply.svg',
                  count: 0,
                  active: false,
                  activeColor: AppColors.red,
                  onTap: widget.onReply,
                  iconSize: 18,
                  showCount: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}