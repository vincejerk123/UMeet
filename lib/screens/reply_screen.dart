import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme.dart';
import '../widgets/post_card.dart';
import '../widgets/svg_reaction_button.dart';
import 'image_viewer_screen.dart';

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
  final _picker = ImagePicker();

  late Map<String, dynamic> _post;
  bool _postReady = false;

  List<Map<String, dynamic>> _comments = [];
  final Map<String, Map<String, dynamic>> _voteMap = {};
  final Map<String, Map<String, dynamic>> _commentById = {};

  String? _replyToCommentId;
  String? _replyToUsername;

  File? _pendingImage;
  bool _loading = true;
  bool _sending = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _recordView();
    _refreshPost();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _recordView() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('post_views').upsert({
        'post_id': widget.post['id'],
        'user_id': uid,
      });
    } catch (_) {}
  }

  Future<void> _refreshPost() async {
    try {
      final data = await _client
          .from('posts_with_counts')
          .select(
            '*, topics(slug,name), profiles!posts_author_id_fkey(display_name,avatar_url,program,year_level)',
          )
          .eq('id', widget.post['id'])
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        if (data != null) _post = Map<String, dynamic>.from(data);
        _postReady = true;
      });
    } catch (e) {
      print('POST REFRESH ERROR: $e');
      if (mounted) setState(() => _postReady = true);
    }
  }

  Future<void> _load() async {
    try {
      final uid = _client.auth.currentUser!.id;

      final data = await _client
          .from('comments')
          .select(
            '*, profiles!comments_author_id_fkey(display_name, avatar_url)',
          )
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
          _voteMap[id] = {'like_count': 0, 'dislike_count': 0, 'my_vote': 0};
        }

        for (final v in (votes as List)) {
          final cid = v['comment_id'] as String;
          final val = (v['value'] as num).toInt();
          final bucket = _voteMap[cid];
          if (bucket == null) continue;
          if (val == 1) {
            bucket['like_count'] = (bucket['like_count'] as int) + 1;
          } else if (val == -1) {
            bucket['dislike_count'] = (bucket['dislike_count'] as int) + 1;
          }
          if (v['user_id'] == uid) bucket['my_vote'] = val;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1200,
    );
    if (picked == null) return;
    setState(() => _pendingImage = File(picked.path));
  }

  void _startReply(Map<String, dynamic> comment) {
    final author = comment['profiles'] ?? {};
    final username = author['display_name'] ?? 'user';
    setState(() {
      _replyToCommentId = comment['id'];
      _replyToUsername = username;
      if (_controller.text.isEmpty) {
        _controller.text = '@$username ';
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUsername = null;
    });
    _focusNode.unfocus();
  }

  bool get _canSend =>
      !_sending &&
      !_uploading &&
      (_controller.text.trim().isNotEmpty || _pendingImage != null);

  Future<void> _send() async {
    if (!_canSend) return;

    final text = _controller.text.trim();
    final image = _pendingImage;

    setState(() {
      _sending = true;
      _pendingImage = null;
    });

    final user = _client.auth.currentUser!;
    try {
      String? imageUrl;
      if (image != null) {
        setState(() => _uploading = true);
        final path =
            '${widget.post['id']}/${user.id}_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await _client.storage.from('comments').upload(path, image);
        imageUrl = _client.storage.from('comments').getPublicUrl(path);
        setState(() => _uploading = false);
      }

      await _client.from('comments').insert({
        'post_id': widget.post['id'],
        'author_id': user.id,
        'body': text.isEmpty ? '📷 Photo' : text,
        if (_replyToCommentId != null) 'parent_id': _replyToCommentId,
        if (imageUrl != null) 'image_url': imageUrl,
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
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
        title: const Text(
          'Replies',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_postReady)
            PostCard(post: _post, imageLayout: PostImageLayout.large)
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
                    child: Text(
                      'No replies yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _comments.length,
                      itemBuilder: (_, i) {
                        final c = _comments[i];
                        final isReply = c['parent_id'] != null;
                        final parentName = isReply
                            ? (_commentById[c['parent_id']]?['profiles']?['display_name'] ??
                                  'user')
                            : null;

                        return _CommentTile(
                          key: ValueKey(c['id']),
                          comment: c,
                          voteData: _voteMap[c['id']] ?? {},
                          isReply: isReply,
                          parentUsername: parentName,
                          myUserId: myUserId,
                          onVote: (v) => _toggleCommentVote(c['id'], v),
                          onReply: () => _startReply(c),
                          onRemoved: () {
                            Future.microtask(() {
                              if (mounted) {
                                setState(() {
                                  _comments.removeWhere(
                                    (x) => x['id'] == c['id'],
                                  );
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    child: Icon(Icons.close, size: 18, color: AppColors.red),
                  ),
                ],
              ),
            ),

          if (_pendingImage != null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _pendingImage!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: -4,
                        top: -4,
                        child: GestureDetector(
                          onTap: () => setState(() => _pendingImage = null),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Photo attached',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _sending ? null : _pickImage,
                    icon: Icon(
                      Icons.photo_outlined,
                      color: _sending
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onChanged: (_) => setState(() {}),
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _replyToUsername == null
                            ? 'Write a reply...'
                            : 'Write your reply...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: AppColors.chipBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _canSend ? _send : null,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: SvgPicture.asset(
                            'assets/icons/send.svg',
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                              _canSend ? AppColors.red : Colors.grey.shade400,
                              BlendMode.srcIn,
                            ),
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
//  Comment tile with double-tap-to-like
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
  late AnimationController _heartPop;
  late Animation<double> _likeScale;
  late Animation<double> _dislikeScale;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;

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
    _heartPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    // ─── Curves are chained INSIDE each tween (not wrapped around
    //     the TweenSequence) so easeOutBack overshoot doesn't trip
    //     the `t >= 0 && t <= 1` assertion.
    _likeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
    ]).animate(_likeBounce);

    _dislikeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.35,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.35,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
    ]).animate(_dislikeBounce);

    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.4,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    ]).animate(_heartPop);

    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_heartPop);
  }

  @override
  void dispose() {
    _likeBounce.dispose();
    _dislikeBounce.dispose();
    _heartPop.dispose();
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

  void _handleDoubleTap() {
    _heartPop.forward(from: 0);
    HapticFeedback.mediumImpact();
    final myVote = (widget.voteData['my_vote'] as num?)?.toInt() ?? 0;
    if (myVote != 1) {
      widget.onVote(1);
    }
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
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete comment',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                      content: Text('Thanks — reports coming soon.'),
                    ),
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
          'This will permanently remove your comment and any replies to it.',
        ),
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
      await _client.from('comments').delete().eq('id', widget.comment['id']);
      widget.onRemoved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  void _openImage(String url) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            ImageViewerScreen(images: [url], initialIndex: 0),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
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

    final myVote = (widget.voteData['my_vote'] as num?)?.toInt() ?? 0;
    final likeCount = (widget.voteData['like_count'] as num?)?.toInt() ?? 0;
    final dislikeCount =
        (widget.voteData['dislike_count'] as num?)?.toInt() ?? 0;

    final imageUrl = comment['image_url'] as String?;
    final body = (comment['body'] ?? '').toString();
    final showBody = body.isNotEmpty && body != '📷 Photo';

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Container(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 1),
            padding: EdgeInsets.fromLTRB(widget.isReply ? 40 : 16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isReply && widget.parentUsername != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'replying to @${widget.parentUsername}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: avatar != null
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar == null
                          ? const Icon(
                              Icons.person,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _openMenu,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),

                if (showBody)
                  Padding(
                    padding: const EdgeInsets.only(left: 42, top: 6),
                    child: Text(body, style: const TextStyle(fontSize: 13)),
                  ),

                if (imageUrl != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 42),
                    child: GestureDetector(
                      onTap: () => _openImage(imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: 200,
                                height: 150,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              width: 200,
                              height: 100,
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.only(left: 42, top: 4),
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
          ),

          // ─── Heart overlay ───
          // Center is always present; only Opacity/Transform swap in/out.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _heartPop,
                  builder: (_, __) {
                    final opacity = _heartOpacity.value.clamp(0.0, 1.0);
                    if (opacity <= 0.001) return const SizedBox.shrink();
                    return Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: _heartScale.value,
                        child: const Icon(
                          Icons.favorite,
                          color: Color(0xFFC62828),
                          size: 64,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
