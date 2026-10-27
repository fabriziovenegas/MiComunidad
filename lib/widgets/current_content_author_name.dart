import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/community_service.dart';
import '../utils/text_encoding.dart';

/// Reads only the creator's current display name through an authorized lookup.
class CurrentContentAuthorName extends StatefulWidget {
  const CurrentContentAuthorName({
    super.key,
    required this.collection,
    required this.contentId,
    required this.authorId,
    this.savedName = '',
    this.viewer,
    this.loadName,
  });
  final String collection;
  final String contentId;
  final String authorId;
  final String savedName;
  final AppUser? viewer;
  final Future<String?> Function(String collection, String contentId)? loadName;

  @override
  State<CurrentContentAuthorName> createState() =>
      _CurrentContentAuthorNameState();
}

class _CurrentContentAuthorNameState extends State<CurrentContentAuthorName>
    with WidgetsBindingObserver {
  Future<String?>? _name;
  String? _lastName;
  int _generation = 0;
  bool get _ownContent =>
      widget.authorId.isNotEmpty &&
      widget.viewer?.isApproved == true &&
      widget.authorId == widget.viewer?.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  void _reload() {
    final generation = ++_generation;
    _name = widget.viewer?.isApproved != true ||
            _ownContent ||
            widget.contentId.isEmpty ||
            widget.authorId.isEmpty
        ? null
        : _lookup(generation);
  }

  Future<String?> _lookup(int generation) async {
    try {
      final name = await (widget.loadName ??
              CommunityService.instance.currentContentAuthorName)(
          widget.collection, widget.contentId);
      if (mounted && generation == _generation) {
        final cleaned = readableText(name).trim();
        if (cleaned.isNotEmpty) _lastName = cleaned;
        return cleaned.isEmpty ? _lastName : cleaned;
      }
    } catch (_) {
      // The name is optional; keep the last readable value while unavailable.
      if (mounted && generation == _generation) return _lastName;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant CurrentContentAuthorName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection ||
        oldWidget.contentId != widget.contentId ||
        oldWidget.authorId != widget.authorId ||
        oldWidget.viewer?.userId != widget.viewer?.userId ||
        oldWidget.viewer?.role != widget.viewer?.role ||
        oldWidget.viewer?.isApproved != widget.viewer?.isApproved) {
      _lastName = null;
      _reload();
    } else if (oldWidget.savedName != widget.savedName ||
        oldWidget.loadName != widget.loadName) {
      _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(_reload);
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _display(String? value) {
    final name = readableText(value).trim();
    final saved = readableText(widget.savedName).trim();
    final shown = name.isNotEmpty ? name : saved;
    return shown.isEmpty ? 'Autor no disponible' : 'Creado por $shown';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viewer?.isApproved != true) {
      return const Text('Autor no disponible');
    }
    if (_ownContent) return Text(_display(widget.viewer?.nombre));
    return FutureBuilder<String?>(
        key: ValueKey(
            '${widget.collection}/${widget.contentId}/${widget.authorId}/${widget.viewer?.userId}'),
        future: _name,
        builder: (context, snapshot) => Text(_display(snapshot.data)));
  }
}

class ContentCreatorLine extends StatelessWidget {
  const ContentCreatorLine(
      {super.key,
      required this.collection,
      required this.contentId,
      required this.data,
      this.user});
  final String collection;
  final String contentId;
  final Map<String, dynamic> data;
  final AppUser? user;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person_outline, size: 22, color: Color(0xFF276749)),
          const SizedBox(width: 8),
          Expanded(
              child: DefaultTextStyle.merge(
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: const Color(0xFF515B55)),
                  child: CurrentContentAuthorName(
                      collection: collection,
                      contentId: contentId,
                      authorId: readableText(data['createdBy']).trim(),
                      savedName: readableText(data['createdByName']),
                      viewer: user))),
        ],
      );
}
