import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'svg_icon_button.dart';

Future<bool?> showComposeSheet(
  BuildContext context, {
  String? fixedTopicSlug,
  Map<String, dynamic>? existingPost,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ComposeSheet(
      fixedTopicSlug: fixedTopicSlug,
      existingPost: existingPost,
    ),
  );
}

class _ComposeSheet extends StatefulWidget {
  final String? fixedTopicSlug;
  final Map<String, dynamic>? existingPost;
  const _ComposeSheet({this.fixedTopicSlug, this.existingPost});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _body = TextEditingController();
  final _topicController = TextEditingController();
  final _topicFocus = FocusNode();
  final _picker = ImagePicker();

  List<File> _images = [];
  List<String> _existingImageUrls = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedTopicId;
  bool _posting = false;
  bool _showSuggestions = false;

  bool get _isEdit => widget.existingPost != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPost;
    if (p != null) {
      _body.text = (p['body'] ?? '').toString();
      final topic = p['topics'] as Map<String, dynamic>?;
      if (topic != null) {
        _topicController.text = (topic['name'] as String?) ?? '';
      }
      _selectedTopicId = p['topic_id'] as String?;
      _existingImageUrls = ((p['image_urls'] as List?)?.cast<String>() ?? [])
          .toList();
    }
    _loadTopics();
  }

  @override
  void dispose() {
    _body.dispose();
    _topicController.dispose();
    _topicFocus.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    final data = await Supabase.instance.client.from('topics').select();
    if (!mounted) return;
    setState(() {
      _topics = List<Map<String, dynamic>>.from(data);
      if (widget.fixedTopicSlug != null && !_isEdit) {
        final match = _topics.firstWhere(
          (t) => t['slug'] == widget.fixedTopicSlug,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          _selectedTopicId = match['id'];
          _topicController.text = match['name'] as String;
        }
      }
    });
  }

  String _slugify(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '');
    return cleaned.isEmpty ? 'General' : cleaned;
  }

  List<Map<String, dynamic>> get _filteredTopics {
    final q = _topicController.text.trim().toLowerCase();
    if (q.isEmpty) return _topics.take(6).toList();
    return _topics
        .where((t) => (t['name'] as String).toLowerCase().contains(q))
        .toList();
  }

  bool get _needsNewTopic {
    final q = _topicController.text.trim().toLowerCase();
    if (q.isEmpty) return false;
    return !_topics.any((t) => (t['name'] as String).toLowerCase() == q);
  }

  Future<void> _pickImage() async {
    final files = await _picker.pickMultiImage(imageQuality: 75);
    if (files.isNotEmpty) {
      setState(() => _images = [..._images, ...files.map((f) => File(f.path))]);
    }
  }

  Future<String> _resolveTopicId(String name) async {
    final client = Supabase.instance.client;
    final trimmed = name.trim();
    final existing = await client
        .from('topics')
        .select()
        .ilike('name', trimmed)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final slug = _slugify(trimmed);
    final bySlug = await client
        .from('topics')
        .select()
        .eq('slug', slug)
        .maybeSingle();
    if (bySlug != null) return bySlug['id'] as String;
    final created = await client
        .from('topics')
        .insert({'name': trimmed, 'slug': slug})
        .select()
        .single();
    return created['id'] as String;
  }

  bool get _canPost =>
      _body.text.trim().isNotEmpty &&
      (_selectedTopicId != null || _topicController.text.trim().isNotEmpty) &&
      !_posting;

  Future<void> _submit() async {
    final bodyText = _body.text.trim();
    final topicName = _topicController.text.trim();
    if (bodyText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Write something first.')));
      return;
    }
    if (topicName.isEmpty && _selectedTopicId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick or type a topic.')));
      return;
    }

    setState(() => _posting = true);
    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    try {
      final topicId = _selectedTopicId ?? await _resolveTopicId(topicName);

      final newUrls = <String>[];
      for (final img in _images) {
        final path =
            'posts/${user.id}/${DateTime.now().microsecondsSinceEpoch}.jpg';
        await client.storage.from('posts').upload(path, img);
        newUrls.add(client.storage.from('posts').getPublicUrl(path));
      }

      final allUrls = [..._existingImageUrls, ...newUrls];

      if (_isEdit) {
        await client
            .from('posts')
            .update({
              'topic_id': topicId,
              'body': bodyText,
              'image_urls': allUrls,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', widget.existingPost!['id']);
      } else {
        await client.from('posts').insert({
          'topic_id': topicId,
          'author_id': user.id,
          'body': bodyText,
          'image_urls': allUrls,
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _isEdit ? 'Edit post' : 'Create post',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              TextField(
                controller: _body,
                maxLines: null,
                minLines: 3,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                  border: InputBorder.none,
                ),
              ),
              // Existing images (edit mode)
              if (_existingImageUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _existingImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _existingImageUrls[i],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _existingImageUrls.removeAt(i)),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // New images
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _images[i],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(i)),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _topicController,
                focusNode: _topicFocus,
                decoration: InputDecoration(
                  hintText: 'Topic (e.g., Tuition)',
                  prefixText: 'um/',
                  prefixStyle: const TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: AppColors.chipBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {
                  _showSuggestions = true;
                  _selectedTopicId = null;
                }),
                onTap: () => setState(() => _showSuggestions = true),
              ),
              if (_showSuggestions) _buildSuggestions(),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  const Spacer(),
                  if (_posting)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    SvgIconButton(
                      svgPath: 'assets/icons/send.svg',
                      size: 24,
                      color: _canPost ? AppColors.red : Colors.grey.shade400,
                      disabledColor: Colors.grey.shade400,
                      onPressed: _canPost ? _submit : null,
                      padding: const EdgeInsets.all(10),
                      semanticLabel: _isEdit ? 'Save' : 'Post',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    final matches = _filteredTopics;
    final showCreate = _needsNewTopic;
    if (matches.isEmpty && !showCreate) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (showCreate)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.add_circle_outline,
                size: 20,
                color: AppColors.red,
              ),
              title: Text(
                'Create "um/${_slugify(_topicController.text)}"',
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                setState(() {
                  _selectedTopicId = null;
                  _showSuggestions = false;
                });
                _topicFocus.unfocus();
              },
            ),
          ...matches.map(
            (t) => ListTile(
              dense: true,
              title: Text(
                'um/${t['slug']}',
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () {
                setState(() {
                  _topicController.text = t['name'] as String;
                  _selectedTopicId = t['id'] as String;
                  _showSuggestions = false;
                });
                _topicFocus.unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}
