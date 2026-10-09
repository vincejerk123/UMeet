import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../theme.dart';
import 'image_viewer_screen.dart';
import 'user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> otherUser;
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  File? _pendingImage;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribe() {
    _channel = _client
        .channel('dm:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            final mine =
                payload.newRecord['sender_id'] == _client.auth.currentUser?.id;
            if (mine &&
                _messages.any((m) => m['id'] == payload.newRecord['id'])) {
              return;
            }
            setState(() {
              _messages.add(Map<String, dynamic>.from(payload.newRecord));
            });
            _scrollDown();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            setState(() {
              _messages.removeWhere((m) => m['id'] == payload.oldRecord['id']);
            });
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Block check
      final uid = _client.auth.currentUser!.id;
      final otherId = widget.otherUser['id'] as String;

      final blocked = await _client
          .from('blocked_users')
          .select('blocker_id')
          .or(
            'and(blocker_id.eq.$uid,blocked_id.eq.$otherId),and(blocker_id.eq.$otherId,blocked_id.eq.$uid)',
          )
          .maybeSingle();

      if (blocked != null) {
        if (mounted) {
          setState(() {
            _error = 'Messaging is not available with this user.';
            _loading = false;
          });
        }
        return;
      }

      final data = await _client
          .from('messages')
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
      _scrollDown();
    } catch (e) {
      print('CHAT LOAD ERROR: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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

  bool get _canSend =>
      !_sending &&
      !_uploadingImage &&
      (_controller.text.trim().isNotEmpty || _pendingImage != null);

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _controller.text.trim();
    final image = _pendingImage;
    final uid = _client.auth.currentUser!.id;

    _controller.clear();
    setState(() {
      _pendingImage = null;
      _sending = true;
    });

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = {
      'id': tempId,
      'conversation_id': widget.conversationId,
      'sender_id': uid,
      'body': text,
      'image_url': image?.path,
      'created_at': DateTime.now().toIso8601String(),
      '_localImage': image,
    };
    setState(() => _messages.add(optimistic));
    _scrollDown();

    try {
      String? imageUrl;
      if (image != null) {
        setState(() => _uploadingImage = true);
        final path =
            '${widget.conversationId}/${uid}_${DateTime.now().microsecondsSinceEpoch}.jpg';
        await _client.storage.from('chat').upload(path, image);
        imageUrl = _client.storage.from('chat').getPublicUrl(path);
        setState(() => _uploadingImage = false);
      }

      final inserted = await _client
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': uid,
            'body': text.isEmpty ? '📷 Photo' : text,
            if (imageUrl != null) 'image_url': imageUrl,
          })
          .select()
          .single();

      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) _messages[idx] = Map<String, dynamic>.from(inserted);
      });
    } catch (e) {
      print('SEND MESSAGE ERROR: $e');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          _uploadingImage = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _unsend(Map<String, dynamic> message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsend message?'),
        content: const Text(
          'This message will be permanently removed for both you and the recipient.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unsend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messageId = message['id'] as String;
    final prev = _messages.where((m) => m['id'] == messageId).toList();
    setState(() => _messages.removeWhere((m) => m['id'] == messageId));

    try {
      await _client.from('messages').delete().eq('id', messageId);
    } catch (e) {
      if (mounted && prev.isNotEmpty) {
        setState(() => _messages.add(prev.first));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not unsend: $e')));
      }
    }
  }

  void _showMessageMenu(Map<String, dynamic> message) {
    final mine = message['sender_id'] == _client.auth.currentUser?.id;
    final body = (message['body'] ?? '').toString();

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
            if (body.isNotEmpty && body != '📷 Photo')
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: body));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Unsend message',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _unsend(message);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report message'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thanks — reports coming soon.'),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _client.auth.currentUser!.id;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            final otherId = widget.otherUser['id'] as String?;
            if (otherId == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: otherId),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: widget.otherUser['avatar_url'] != null
                      ? NetworkImage(widget.otherUser['avatar_url'])
                      : null,
                  child: widget.otherUser['avatar_url'] == null
                      ? const Icon(Icons.person, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.otherUser['display_name'] ?? 'User',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
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
                            Icons.lock_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
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
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet.\nSay hi to ${widget.otherUser['display_name'] ?? 'them'}!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final mine = m['sender_id'] == uid;
                      final createdAt = m['created_at'];
                      final time = createdAt != null
                          ? timeago.format(
                              DateTime.parse(createdAt).toLocal(),
                              allowFromNow: true,
                            )
                          : '';
                      return _MessageBubble(
                        message: m,
                        mine: mine,
                        time: time,
                        onMore: () => _showMessageMenu(m),
                      );
                    },
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
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onChanged: (_) => setState(() {}),
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Write a message...',
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

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool mine;
  final String time;
  final VoidCallback onMore;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.time,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = message['image_url'] as String?;
    final localFile = message['_localImage'] as File?;
    final body = (message['body'] ?? '').toString();
    final showBody = body.isNotEmpty && body != '📷 Photo';

    Widget? imageWidget;
    if (localFile != null) {
      imageWidget = Image.file(localFile, width: 200, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl.startsWith('http')) {
      imageWidget = Image.network(
        imageUrl,
        width: 200,
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
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          width: 200,
          height: 100,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (mine) _threeDots(),
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: imageUrl != null && imageUrl.startsWith('http')
                      ? () => _openImageViewer(context, [imageUrl])
                      : null,
                  child: Container(
                    padding: imageWidget != null && !showBody
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.lightRed : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageWidget != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: imageWidget,
                          ),
                        if (imageWidget != null && showBody)
                          const SizedBox(height: 8),
                        if (showBody)
                          Text(body, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    time,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
          if (!mine) _threeDots(),
        ],
      ),
    );
  }

  Widget _threeDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: onMore,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.more_horiz, size: 18, color: Colors.grey),
        ),
      ),
    );
  }

  void _openImageViewer(BuildContext context, List<String> images) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            ImageViewerScreen(images: images, initialIndex: 0),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}
