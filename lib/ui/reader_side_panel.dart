import 'package:flutter/material.dart';

import '../application/reader_store.dart';
import '../domain/forum_document.dart';
import 'aligned_underline.dart';

typedef LoginCallback = Future<bool> Function(String name, String trip);
typedef CacheClearCallback = Future<bool> Function();

enum _PanelForm { none, login }

class ReaderSidePanel extends StatefulWidget {
  const ReaderSidePanel({
    required this.document,
    required this.currentFloor,
    required this.openedThreads,
    required this.bookmarks,
    required this.displayScale,
    required this.busy,
    required this.onClose,
    required this.onHome,
    required this.onBookmarkCurrent,
    required this.onOpenThread,
    required this.onOpenBookmark,
    required this.onRemoveBookmark,
    required this.onRemoveThread,
    required this.onScaleChanged,
    required this.onClearCache,
    required this.onLogin,
    required this.onStartReply,
    required this.onStartNewThread,
    required this.currentPage,
    required this.pageCount,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onJumpToFloor,
    this.login,
    super.key,
  });

  final ForumDocument? document;
  final int? currentFloor;
  final List<ReadingMarker> openedThreads;
  final List<FloorBookmark> bookmarks;
  final double displayScale;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onHome;
  final VoidCallback onBookmarkCurrent;
  final ValueChanged<ReadingMarker> onOpenThread;
  final ValueChanged<FloorBookmark> onOpenBookmark;
  final ValueChanged<String> onRemoveBookmark;
  final ValueChanged<String> onRemoveThread;
  final ValueChanged<double> onScaleChanged;
  final CacheClearCallback onClearCache;
  final LoginCallback onLogin;
  final VoidCallback onStartReply;
  final VoidCallback onStartNewThread;
  final int currentPage;
  final int pageCount;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback onJumpToFloor;
  final CachedLogin? login;

  @override
  State<ReaderSidePanel> createState() => _ReaderSidePanelState();
}

class _ReaderSidePanelState extends State<ReaderSidePanel> {
  final _name = TextEditingController();
  final _trip = TextEditingController();
  _PanelForm _form = _PanelForm.none;

  @override
  void initState() {
    super.initState();
    _fillCachedLogin();
  }

  @override
  void didUpdateWidget(covariant ReaderSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.login != widget.login && _form == _PanelForm.none) {
      _fillCachedLogin();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _trip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isThread = widget.document?.kind == ForumPageKind.thread;
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('reader-side-panel'),
        decoration: BoxDecoration(
          color: const Color(0xfff6f4ed),
          border: Border.all(color: Colors.black, width: 2),
        ),
        padding: const EdgeInsets.all(7),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xff777777)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(onClose: widget.onClose),
              const Divider(height: 1, color: Colors.black),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PanelSectionTitle(
                      label: '帖子标签（${widget.openedThreads.length}）',
                    ),
                    Expanded(child: _buildThreadTabs()),
                    const Divider(height: 1, color: Colors.black),
                    _PanelSectionTitle(
                      label: '楼层书签（${widget.bookmarks.length}）',
                    ),
                    Expanded(child: _buildBookmarks()),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _form == _PanelForm.none ? 190 : 285,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.pageCount > 1) ...[
                        Text(
                          '第 ${widget.currentPage} / ${widget.pageCount} 页',
                          key: const Key('panel-page-indicator'),
                          style: const TextStyle(
                            fontFamily: 'Saitamaar',
                            fontSize: 13,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      // Fixed rows rather than a wrap, so a button never moves
                      // to a different place as the page state changes.
                      _ButtonRow(
                        children: [
                          _ClassicButton(
                            key: const Key('panel-reply'),
                            label: '回复',
                            onPressed: isThread ? widget.onStartReply : null,
                          ),
                          _ClassicButton(
                            key: const Key('bookmark-current'),
                            label:
                                isThread && widget.currentFloor != null
                                    ? '书签 #${widget.currentFloor}'
                                    : '加入书签',
                            onPressed:
                                isThread && widget.currentFloor != null
                                    ? widget.onBookmarkCurrent
                                    : null,
                          ),
                          _ClassicButton(
                            key: const Key('panel-jump-floor'),
                            label: '跳楼层',
                            onPressed: isThread ? widget.onJumpToFloor : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _ButtonRow(
                        children: [
                          _ClassicButton(label: '首页', onPressed: widget.onHome),
                          _ClassicButton(
                            key: const Key('panel-previous-page'),
                            label: '◀ 上一页',
                            onPressed:
                                widget.currentPage > 1
                                    ? widget.onPreviousPage
                                    : null,
                          ),
                          _ClassicButton(
                            key: const Key('panel-next-page'),
                            label: '下一页 ▶',
                            onPressed:
                                widget.currentPage < widget.pageCount
                                    ? widget.onNextPage
                                    : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _ButtonRow(
                        children: [
                          _ClassicButton(
                            label: '登录',
                            onPressed: () => _toggle(_PanelForm.login),
                          ),
                          _ClassicButton(
                            label: '新建帖子',
                            onPressed: widget.onStartNewThread,
                          ),
                          _ClassicButton(
                            key: const Key('clear-thread-cache'),
                            label: '清除缓存',
                            onPressed: widget.busy ? null : _confirmClearCache,
                          ),
                        ],
                      ),
                      if (_form != _PanelForm.none) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xff777777)),
                        const SizedBox(height: 7),
                        _buildForm(),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.black),
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '显示大小 ${(widget.displayScale * 100).round()}%',
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 13,
                        height: 1,
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        activeTrackColor: Colors.black,
                        inactiveTrackColor: const Color(0xff999999),
                        thumbColor: const Color(0xfff6f4ed),
                        overlayColor: const Color(0x22000000),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        key: const Key('display-scale-slider'),
                        min: 0.3,
                        max: 1.6,
                        value: widget.displayScale,
                        onChanged: widget.onScaleChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadTabs() {
    if (widget.openedThreads.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            '还没有打开过帖子',
            style: TextStyle(fontFamily: 'Saitamaar', fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('thread-tab-list'),
      padding: const EdgeInsets.fromLTRB(7, 3, 7, 6),
      itemCount: widget.openedThreads.length,
      itemBuilder: (context, index) {
        final marker = widget.openedThreads[index];
        final active = widget.document?.threadId == marker.threadId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            decoration: BoxDecoration(
              color: active ? const Color(0xffddffdd) : const Color(0xffefefef),
              border: Border.all(
                color: active ? const Color(0xff006600) : Colors.black,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: ValueKey('thread-tab-${marker.threadId}'),
                      onTap: () => widget.onOpenThread(marker),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 6, 4, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: _PanelLink(
                                label: marker.threadTitle,
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '#${marker.floor}',
                              style: const TextStyle(
                                fontFamily: 'Saitamaar',
                                fontSize: 13,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('thread-tab-close-${marker.threadId}'),
                    tooltip: '关闭标签页',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    iconSize: 16,
                    onPressed: () => widget.onRemoveThread(marker.threadId),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookmarks() {
    if (widget.bookmarks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '还没有书签',
            style: TextStyle(fontFamily: 'Saitamaar', fontSize: 14),
          ),
        ),
      );
    }
    return ListView.separated(
      key: const Key('bookmark-list'),
      padding: const EdgeInsets.fromLTRB(7, 3, 7, 7),
      itemCount: widget.bookmarks.length,
      separatorBuilder:
          (context, index) =>
              const Divider(height: 1, color: Color(0xffaaaaaa)),
      itemBuilder: (context, index) {
        final bookmark = widget.bookmarks[index];
        return Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => widget.onOpenBookmark(bookmark),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: _PanelLink(
                    label: '${bookmark.threadTitle}\n#${bookmark.floor}',
                    maxLines: 3,
                    lineHeight: 1.15,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '删除书签',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => widget.onRemoveBookmark(bookmark.id),
              icon: const Icon(Icons.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildForm() {
    switch (_form) {
      case _PanelForm.login:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('登录设置（昵称 / 密钥）'),
            const SizedBox(height: 5),
            _ClassicField(
              key: const Key('login-name'),
              controller: _name,
              hint: '昵称',
            ),
            const SizedBox(height: 5),
            _ClassicField(
              key: const Key('login-trip'),
              controller: _trip,
              hint: '密钥（8～30 字符）',
              obscureText: true,
            ),
            const SizedBox(height: 6),
            _ClassicButton(
              label: widget.busy ? '提交中…' : '保存登录设置',
              onPressed: widget.busy ? null : _submitLogin,
            ),
          ],
        );
      case _PanelForm.none:
        return const SizedBox.shrink();
    }
  }

  void _toggle(_PanelForm form) {
    setState(() => _form = _form == form ? _PanelForm.none : form);
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xfff6f4ed),
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Colors.black),
            ),
            title: const Text('清除帖子缓存'),
            content: const Text('删除已访问帖子的本地页面缓存？书签和阅读进度会保留。'),
            actions: [
              _ClassicButton(
                label: '取消',
                onPressed: () => Navigator.pop(context, false),
              ),
              _ClassicButton(
                label: '清除',
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
    );
    if (confirmed == true) await widget.onClearCache();
  }

  Future<void> _submitLogin() async {
    final name = _name.text.trim();
    final trip = _trip.text;
    if (name.isEmpty || trip.length < 8 || trip.length > 30) {
      _showLocalMessage('请输入昵称，并填写 8～30 字符的密钥');
      return;
    }
    if (await widget.onLogin(name, trip) && mounted) {
      setState(() => _form = _PanelForm.none);
    }
  }

  void _fillCachedLogin() {
    _name.text = widget.login?.name ?? '';
    _trip.text = widget.login?.trip ?? '';
  }

  void _showLocalMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A panel link drawn with the same straight underline the board pages use, so
/// the rule stays put when Saitamaar falls back for an unsupported glyph.
class _PanelLink extends StatelessWidget {
  const _PanelLink({
    required this.label,
    required this.maxLines,
    this.lineHeight = 1.1,
  });

  static const _fontSize = 14.0;

  final String label;
  final int maxLines;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Saitamaar',
      fontSize: _fontSize,
      height: lineHeight,
      color: const Color(0xff0000ee),
      decoration: TextDecoration.none,
    );
    final span = TextSpan(text: label, style: style);
    return CustomPaint(
      foregroundPainter: AlignedUnderlinePainter(
        text: span,
        ranges: [
          AlignedUnderlineRange(
            start: 0,
            end: label.length,
            color: const Color(0xff0000ee),
          ),
        ],
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: maxLines,
        ellipsis: '…',
      ),
      child: Text(
        label,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          Expanded(child: children[index]),
        ],
      ],
    );
  }
}

class _PanelSectionTitle extends StatelessWidget {
  const _PanelSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 16,
          height: 1,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                '阅读工具',
                style: TextStyle(
                  fontFamily: 'Saitamaar',
                  fontSize: 17,
                  height: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('close-reader-panel'),
            tooltip: '收起',
            padding: EdgeInsets.zero,
            iconSize: 18,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ClassicButton extends StatelessWidget {
  const _ClassicButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        backgroundColor: const Color(0xffefefef),
        disabledForegroundColor: const Color(0xff999999),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        minimumSize: const Size(0, 30),
        side: const BorderSide(color: Colors.black),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 14,
          height: 1,
        ),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
    );
  }
}

class _ClassicField extends StatelessWidget {
  const _ClassicField({
    required this.controller,
    required this.hint,
    this.obscureText = false,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontFamily: 'Saitamaar', fontSize: 14, height: 1),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.all(7),
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.black),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xff000080), width: 2),
        ),
      ),
    );
  }
}
