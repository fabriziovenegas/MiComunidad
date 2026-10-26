import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/community_service.dart';
import '../utils/text_encoding.dart';

/// Resolves only a report author's display name, never another user's profile.
class CurrentReportAuthorName extends StatefulWidget {
  const CurrentReportAuthorName({
    super.key,
    required this.reportId,
    required this.authorId,
    required this.savedName,
    this.viewer,
    this.loadName,
    this.prefix = '',
  });

  final String reportId;
  final String authorId;
  final String savedName;
  final AppUser? viewer;
  final Future<String?> Function(String reportId)? loadName;
  final String prefix;

  @override
  State<CurrentReportAuthorName> createState() =>
      _CurrentReportAuthorNameState();
}

class _CurrentReportAuthorNameState extends State<CurrentReportAuthorName>
    with WidgetsBindingObserver {
  Future<String?>? _name;

  bool get _ownReport =>
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
    _name = _ownReport || widget.reportId.isEmpty || widget.authorId.isEmpty
        ? null
        : (widget.loadName ??
            CommunityService.instance.currentReportAuthorName)(widget.reportId);
  }

  @override
  void didUpdateWidget(covariant CurrentReportAuthorName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.authorId != widget.authorId ||
        oldWidget.savedName != widget.savedName ||
        oldWidget.viewer?.userId != widget.viewer?.userId ||
        oldWidget.viewer?.isApproved != widget.viewer?.isApproved ||
        oldWidget.loadName != widget.loadName) {
      _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_reload);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _display(String? name) {
    final current = readableText(name).trim();
    if (current.isNotEmpty) return '${widget.prefix}$current';
    final saved = readableText(widget.savedName).trim();
    return '${widget.prefix}${saved.isEmpty ? 'Vecino' : saved}';
  }

  @override
  Widget build(BuildContext context) {
    // The existing authenticated-profile stream already updates one's own name.
    if (_ownReport) return Text(_display(widget.viewer?.nombre));
    return FutureBuilder<String?>(
      key: ValueKey(
          '${widget.viewer?.userId}/${widget.reportId}/${widget.authorId}'),
      future: _name,
      builder: (context, snapshot) =>
          Text(_display(snapshot.hasError ? null : snapshot.data)),
    );
  }
}
