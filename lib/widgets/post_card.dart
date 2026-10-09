import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../utils/transitions.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/my_profile_screen.dart';
import '../screens/reply_screen.dart';
import 'compose_sheet.dart';

enum PostImageLayout { compact, large }

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final VoidCallback? onRemoved;
  final String authorLabel;
  final PostImageLayout imageLayout;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onRemoved,
    this.authorLabel = '',
    this.imageLayout = PostImageLayout.compact,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with TickerProviderStateMixin {
  final _client = Supabase.instance.client;

  late int _likeCount;
  late int _dislikeCount;
  late int _viewCount;
  int _myVote = 0;
  bool _busy = false;

  late AnimationController _likeBounce;
  late AnimationController _dislikeBounce;
  late AnimationController _heartPop;
  late Animation<double> _likeScale;
  late Animation<double> _dislikeScale;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;

  bool get _isMine => widget.post['author_id'] == _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _syncFromPost();

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
      duration: const Duration(milliseconds: 600),
    );

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

    _loadMyVote();
  }

  void _syncFromPost() {
    _likeCount = (widget.post['like_count'] as num?)?.toInt() ?? 0;
    _dislikeCount = (widget.post['dislike_count'] as num?)?.toInt() ?? 0;
    _viewCount = (widget.post['view_count'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
    _likeBounce.dispose();
    _dislikeBounce.dispose();
    _heartPop.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['id'] != widget.post['id'] ||
        oldWidget.post['like_count'] != widget.post['like_count'] ||
        oldWidget.post['view_count'] != widget.post['view_count']) {
      _syncFromPost();
      _myVote = 0;
      _loadMyVote();
    }
  }

  Future<void> _loadMyVote() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _client
          .from('post_votes')
          .select('value')
          .eq('post_id', widget.post['id'])
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _myVote = (data['value'] as num).toInt());
      }
    } catch (_) {}
  }

  void _handleDoubleTap() {
    _heartPop.forward(from: 0);
    HapticFeedback.mediumImpact();
    if (_myVote != 1) {
      _toggleVote(1);
    }
  }

  Future<void> _toggleVote(int value) async {
    if (_busy) return;
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (value == 1) {
      _likeBounce.forward(from: 0);
    } else {
      _dislikeBounce.forward(from: 0);
    }
    HapticFeedback.lightImpact();

    setState(() => _busy = true);
    final prevVote = _myVote;
    final prevLikes = _likeCount;
    final prevDislikes = _dislikeCount;
    final newVote = (_myVote == value) ? 0 : value;
    final newLikes =
        _likeCount + (newVote == 1 ? 1 : 0) - (prevVote == 1 ? 1 : 0);
    final newDislikes =
        _dislikeCount + (newVote == -1 ? 1 : 0) - (prevVote == -1 ? 1 : 0);

    setState(() {
      _myVote = newVote;
      _likeCount = newLikes;
      _dislikeCount = newDislikes;
    });

    try {
      if (newVote == 0) {
        await _client
            .from('post_votes')
            .delete()
            .eq('post_id', widget.post['id'])
            .eq('user_id', user.id);
      } else {
        await _client.from('post_votes').upsert({
          'post_id': widget.post['id'],
          'user_id': user.id,
          'value': newVote,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myVote = prevVote;
          _likeCount = prevLikes;
          _dislikeCount = prevDislikes;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save vote: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAuthor() {
    final authorId = widget.post['author_id'] as String?;
    final myId = _client.auth.currentUser?.id;
    if (authorId == null) return;
    if (authorId == myId) {
      Navigator.push(context, slideInRoute(const MyProfileScreen()));
      return;
    }
    Navigator.push(context, slideInRoute(UserProfileScreen(userId: authorId)));
  }

  void _openReplies() {
    Navigator.push(context, smoothOpenRoute(ReplyScreen(post: widget.post)));
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
            if (_isMine) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit post'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showComposeSheet(
                    context,
                    existingPost: widget.post,
                  );
                  if (ok == true) {
                    widget.onRemoved?.call();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete post',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide this post'),
                onTap: () {
                  Navigator.pop(ctx);
                  _hidePost();
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report post'),
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
        title: const Text('Delete post?'),
        content: const Text(
          'This will permanently remove your post and all its replies.',
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
      await _client.from('posts').delete().eq('id', widget.post['id']);
      widget.onRemoved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _hidePost() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('hidden_posts').insert({
        'user_id': user.id,
        'post_id': widget.post['id'],
      });
      widget.onRemoved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not hide: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final profile = post['profiles'] as Map<String, dynamic>? ?? {};
    final topic = post['topics'] as Map<String, dynamic>? ?? {};
    final name = widget.authorLabel.isNotEmpty
        ? widget.authorLabel
        : (profile['display_name'] ?? 'user');
    final replies = (post['reply_count'] ?? 0) as int;
    final images = (post['image_urls'] as List?)?.cast<String>() ?? [];
    final created = post['created_at'];
    final time = created != null
        ? timeago.format(DateTime.parse(created.toString()).toLocal())
        : '';
    final heroPrefix = 'post-${post['id']}-${widget.imageLayout.name}';
    final isEdited =
        post['updated_at'] != null && post['updated_at'] != post['created_at'];

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _openAuthor,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: profile['avatar_url'] != null
                                  ? NetworkImage(profile['avatar_url'])
                                  : null,
                              child: profile['avatar_url'] == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 18,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '· um/${topic['slug'] ?? 'general'}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isEdited)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Text(
                      time,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
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
                if ((post['body'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(post['body'], style: const TextStyle(fontSize: 13)),
                ],
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  widget.imageLayout == PostImageLayout.compact
                      ? _buildCompactImages(context, images, heroPrefix)
                      : _buildLargeImages(context, images, heroPrefix),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _svgReaction(
                      path: _myVote == 1
                          ? 'assets/icons/like_filled.svg'
                          : 'assets/icons/like_outline.svg',
                      count: _likeCount,
                      active: _myVote == 1,
                      activeColor: AppColors.red,
                      onTap: () => _toggleVote(1),
                      scale: _likeScale,
                    ),
                    const SizedBox(width: 14),
                    _svgReaction(
                      path: _myVote == -1
                          ? 'assets/icons/dislike_filled.svg'
                          : 'assets/icons/dislike_outline.svg',
                      count: _dislikeCount,
                      active: _myVote == -1,
                      activeColor: Colors.blueGrey,
                      onTap: () => _toggleVote(-1),
                      scale: _dislikeScale,
                    ),
                    const SizedBox(width: 14),
                    _svgReaction(
                      path: 'assets/icons/reply.svg',
                      count: replies,
                      active: false,
                      activeColor: AppColors.red,
                      onTap: _openReplies,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.visibility_outlined,
                      size: 15,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_viewCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                          size: 96,
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

  Widget _svgReaction({
    required String path,
    required int count,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
    Animation<double>? scale,
  }) {
    final tint = active ? activeColor : Colors.grey.shade600;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: SvgPicture.asset(
            path,
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: tint,
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: activeColor.withOpacity(0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: scale != null
              ? ScaleTransition(scale: scale, child: content)
              : content,
        ),
      ),
    );
  }

  Widget _buildCompactImages(
    BuildContext context,
    List<String> images,
    String heroPrefix,
  ) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openViewer(context, images, i, heroPrefix),
          child: Hero(
            tag: '$heroPrefix-$i',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _networkImage(
                url: images[i],
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeImages(
    BuildContext context,
    List<String> images,
    String heroPrefix,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, images, 0, heroPrefix),
        child: Hero(
          tag: '$heroPrefix-0',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: _networkImage(
                url: images[0],
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    }
    final cardWidth = screenWidth * 0.78;
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openViewer(context, images, i, heroPrefix),
          child: Hero(
            tag: '$heroPrefix-$i',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _networkImage(
                url: images[i],
                width: cardWidth,
                height: 260,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(
    BuildContext context,
    List<String> images,
    int i,
    String heroPrefix,
  ) {
    Navigator.push(
      context,
      fadeScaleRoute(
        ImageViewerScreen(
          images: images,
          initialIndex: i,
          heroTagPrefix: heroPrefix,
        ),
      ),
    );
  }

  Widget _networkImage({
    required String url,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}
