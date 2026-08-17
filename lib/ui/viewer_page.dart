import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../application/reader_store.dart';
import '../application/viewer_controller.dart';
import '../data/forum_repository.dart';
import '../domain/forum_document.dart';
import 'aa_text.dart';
import 'classic_link.dart';
import 'post_card.dart';
import 'post_composer_sheet.dart';
import 'reader_side_panel.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({required this.repository, super.key});

  final ForumRepository repository;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static const _home = 'http://aafanclub.com/';
  static final _threadPath = RegExp(r'^/view/(\d+)(?:-\d+)?(?:-icchi)?/?$');

  late final ViewerController _controller;
  late final ReaderStore _readerStore;
  Timer? _progressTimer;
  ForumDocument? _observedDocument;
  String? _pageIdentity;
  String? _pendingJumpThread;
  int? _pendingProgressFloor;
  int? _currentFloor;
  int? _jumpFloor;
  int _jumpNonce = 0;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = ViewerController(widget.repository)..addListener(_onChange);
    _readerStore = ReaderStore()..addListener(_onStoreChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openInitialPage());
    });
  }

  Future<void> _openInitialPage() async {
    await _readerStore.load();
    if (!mounted) return;
    await _controller.openAddress(_home);
    final login = _readerStore.login;
    if (mounted && login != null) {
      await _controller.login(name: login.name, trip: login.trip);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    _readerStore
      ..removeListener(_onStoreChange)
      ..dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _onChange() {
    final document = _controller.document;
    if (_controller.phase == ViewerPhase.ready &&
        document != null &&
        !identical(document, _observedDocument)) {
      _observedDocument = document;
      if (document.kind == ForumPageKind.thread) {
        final identity = '${document.threadId}:${document.currentPage ?? 1}';
        final requestedFloor =
            _pendingJumpThread == document.threadId
                ? _pendingProgressFloor
                : null;
        if (identity != _pageIdentity || requestedFloor != null) {
          _pageIdentity = identity;
          if (requestedFloor != null) {
            _pendingJumpThread = null;
            _pendingProgressFloor = null;
          }
          _currentFloor =
              requestedFloor ?? document.posts.firstOrNull?.numericNumber;
          _jumpFloor = requestedFloor;
          _jumpNonce++;
          final initialFloor = _currentFloor;
          if (initialFloor != null) {
            _readerStore.markThreadOpened(document, initialFloor);
          }
        }
      } else {
        _pageIdentity = null;
        _currentFloor = null;
        _jumpFloor = null;
      }
    }
    if (mounted) setState(() {});
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = (constraints.maxWidth * 0.68).clamp(
              250.0,
              390.0,
            );
            final edgeWidth = (constraints.maxWidth * 0.18).clamp(56.0, 96.0);
            final edgeHeight = (constraints.maxHeight * 0.26).clamp(
              150.0,
              220.0,
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(_readerStore.displayScale),
                    ),
                    child: _EdgeTapSurface(
                      size: constraints.biggest,
                      edgeWidth: edgeWidth,
                      edgeHeight: edgeHeight,
                      enabled: !_drawerOpen,
                      canRefresh: _controller.canReload,
                      onRefresh: _controller.reload,
                      onOpenPanel: () => setState(() => _drawerOpen = true),
                      child: _BottomPullToRefresh(
                        enabled: !_drawerOpen && _controller.canReload,
                        onRefresh: _controller.reload,
                        child: ScrollConfiguration(
                          behavior: const _ReaderScrollBehavior(),
                          child: _buildContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_controller.phase == ViewerPhase.loading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xff0000ff),
                      backgroundColor: Color(0xffd4d0c8),
                    ),
                  ),
                if (_controller.errorMessage != null)
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 3,
                    child: _MessageBar(
                      message: _controller.errorMessage!,
                      isError: true,
                    ),
                  )
                else if (_controller.statusMessage != null)
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 3,
                    child: _MessageBar(message: _controller.statusMessage!),
                  ),
                if (_drawerOpen)
                  Positioned.fill(
                    right: panelWidth,
                    child: GestureDetector(
                      key: const Key('panel-dismiss-area'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _drawerOpen = false),
                    ),
                  ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 230),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  right: _drawerOpen ? 0 : -panelWidth - 4,
                  width: panelWidth,
                  child: ReaderSidePanel(
                    document: _controller.document,
                    currentFloor: _currentFloor,
                    openedThreads: _readerStore.openedThreads,
                    bookmarks: _readerStore.bookmarks,
                    displayScale: _readerStore.displayScale,
                    busy: _controller.isSubmitting,
                    canGoBack: _controller.canGoBack,
                    onClose: () => setState(() => _drawerOpen = false),
                    onHome: _goHome,
                    onBack: _goBack,
                    onBookmarkCurrent: _bookmarkCurrentFloor,
                    onOpenThread: _openSavedPosition,
                    onOpenBookmark: _openBookmark,
                    onRemoveBookmark: _readerStore.removeBookmark,
                    onScaleChanged: _readerStore.setDisplayScale,
                    onClearCache: _controller.clearCache,
                    login: _readerStore.login,
                    onLogin: _loginAndRemember,
                    onStartReply: () => _openComposer(ComposerMode.reply),
                    onStartNewThread:
                        () => _openComposer(ComposerMode.newThread),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    final document = _controller.document;
    if (document == null) {
      return Center(
        child: Text(
          _controller.phase == ViewerPhase.error
              ? '页面读取失败，请检查地址后重试。'
              : '正在读取 AA同好会揭示板……',
          style: const TextStyle(fontFamily: 'Saitamaar', fontSize: 16),
        ),
      );
    }
    if (document.site == ForumSite.aaFanclub) {
      return _AaFanclubDocumentView(
        document: document,
        onNavigate: _navigate,
        currentFloor: _currentFloor,
        jumpFloor: _jumpFloor,
        jumpNonce: _jumpNonce,
        onCurrentFloorChanged: _recordCurrentFloor,
        onFloorLinkTap: _openFloorLink,
      );
    }
    return _GenericDocumentView(document: document);
  }

  void _navigate(Uri uri) {
    final match = _threadPath.firstMatch(uri.path);
    final targetThread = match?.group(1);
    final currentThread = _controller.document?.threadId;
    if (targetThread != null && targetThread != currentThread) {
      final progress = _readerStore.progressFor(targetThread);
      if (progress != null) {
        _pendingJumpThread = targetThread;
        _pendingProgressFloor = progress.floor;
        uri = progress.uri;
      }
    }
    unawaited(_controller.openLink(uri));
  }

  void _openFloorLink(Uri uri) {
    final floorMatch = RegExp(r'^f(\d+)$').firstMatch(uri.fragment);
    final document = _controller.document;
    if (floorMatch == null || document == null) {
      _navigate(uri);
      return;
    }

    final floor = int.parse(floorMatch.group(1)!);
    final targetThread =
        _threadPath.firstMatch(uri.path)?.group(1) ?? document.threadId;
    if (targetThread == null) {
      _navigate(uri);
      return;
    }

    final targetPage = ((floor - 1) ~/ 50) + 1;
    if (targetThread == document.threadId &&
        targetPage == (document.currentPage ?? 1)) {
      setState(() {
        _currentFloor = floor;
        _jumpFloor = floor;
        _jumpNonce++;
      });
      return;
    }

    _pendingJumpThread = targetThread;
    _pendingProgressFloor = floor;
    final targetUri = uri.resolve('/view/$targetThread-$targetPage');
    unawaited(_controller.openLink(targetUri));
  }

  void _recordCurrentFloor(int floor) {
    if (_currentFloor != floor) setState(() => _currentFloor = floor);
    final document = _controller.document;
    if (document == null || document.kind != ForumPageKind.thread) return;
    _progressTimer?.cancel();
    _progressTimer = Timer(
      const Duration(milliseconds: 250),
      () => _readerStore.recordProgress(document, floor),
    );
  }

  void _bookmarkCurrentFloor() {
    final document = _controller.document;
    final floor = _currentFloor;
    if (document == null || floor == null) return;
    final added = _readerStore.addBookmark(document, floor);
    _showMessage(added ? '已加入第 $floor 楼书签' : '这个楼层已经有书签');
  }

  void _openBookmark(FloorBookmark bookmark) {
    _openSavedPosition(bookmark);
  }

  void _openSavedPosition(ReadingMarker marker) {
    final document = _controller.document;
    final targetPage = ((marker.floor - 1) ~/ 50) + 1;
    if (document?.threadId == marker.threadId &&
        (document?.currentPage ?? 1) == targetPage) {
      setState(() {
        _drawerOpen = false;
        _currentFloor = marker.floor;
        _jumpFloor = marker.floor;
        _jumpNonce++;
      });
      return;
    }
    _pendingJumpThread = marker.threadId;
    _pendingProgressFloor = marker.floor;
    setState(() => _drawerOpen = false);
    unawaited(_controller.openLink(marker.uri));
  }

  void _goHome() {
    setState(() => _drawerOpen = false);
    unawaited(_controller.openLink(Uri.parse(_home)));
  }

  void _goBack() {
    setState(() => _drawerOpen = false);
    unawaited(_controller.goBack());
  }

  Future<bool> _createThread(String title, String content) async {
    final success = await _controller.createThread(
      title: title,
      content: content,
    );
    if (success && mounted) setState(() => _drawerOpen = false);
    return success;
  }

  Future<bool> _loginAndRemember(String name, String trip) async {
    final success = await _controller.login(name: name, trip: trip);
    if (success) _readerStore.saveLogin(name, trip);
    return success;
  }

  void _openComposer(ComposerMode mode) {
    setState(() => _drawerOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          isDismissible: true,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          barrierColor: const Color(0x55000000),
          builder:
              (context) => PostComposerSheet(
                mode: mode,
                loginName: _readerStore.login?.name,
                onSubmit: (title, content) {
                  if (mode == ComposerMode.reply) {
                    return _controller.reply(content);
                  }
                  return _createThread(title!, content);
                },
              ),
        ),
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EdgeTapSurface extends StatelessWidget {
  const _EdgeTapSurface({
    required this.size,
    required this.edgeWidth,
    required this.edgeHeight,
    required this.enabled,
    required this.canRefresh,
    required this.onRefresh,
    required this.onOpenPanel,
    required this.child,
  });

  final Size size;
  final double edgeWidth;
  final double edgeHeight;
  final bool enabled;
  final bool canRefresh;
  final VoidCallback onRefresh;
  final VoidCallback onOpenPanel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('edge-tap-surface'),
      behavior: HitTestBehavior.translucent,
      onTapUp: enabled ? _handleTap : null,
      child: child,
    );
  }

  void _handleTap(TapUpDetails details) {
    final position = details.localPosition;
    final edgeTop = (size.height - edgeHeight) / 2;
    if (position.dy < edgeTop || position.dy > edgeTop + edgeHeight) return;
    if (position.dx <= edgeWidth) {
      if (canRefresh) onRefresh();
    } else if (position.dx >= size.width - edgeWidth) {
      onOpenPanel();
    }
  }
}

class _BottomPullToRefresh extends StatefulWidget {
  const _BottomPullToRefresh({
    required this.enabled,
    required this.onRefresh,
    required this.child,
  });

  final bool enabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<_BottomPullToRefresh> createState() => _BottomPullToRefreshState();
}

class _BottomPullToRefreshState extends State<_BottomPullToRefresh> {
  static const _triggerDistance = 64.0;
  double _pullDistance = 0;
  double _maxPullDistance = 0;
  bool _refreshing = false;

  bool get _armed => _maxPullDistance >= _triggerDistance;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      key: const Key('bottom-pull-refresh'),
      onNotification: _handleScroll,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_pullDistance > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const Key('bottom-pull-refresh-indicator'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfff7f5ed),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Text(
                      _armed ? '松开刷新' : '继续拉动刷新',
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 13,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (!widget.enabled || _refreshing) {
      _resetPull();
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter <= 0.01) {
      final beyondBottom =
          notification.metrics.pixels - notification.metrics.maxScrollExtent;
      if (beyondBottom > 0) {
        _setPullDistance(beyondBottom);
      }
    } else if (notification is OverscrollNotification &&
        notification.metrics.extentAfter <= 0.01 &&
        notification.overscroll > 0) {
      _setPullDistance(_pullDistance + notification.overscroll);
    } else if (notification is ScrollEndNotification && _maxPullDistance > 0) {
      final shouldRefresh = _armed;
      _resetPull();
      if (shouldRefresh) unawaited(_refresh());
    }
    return false;
  }

  void _setPullDistance(double value) {
    final next = value.clamp(0, _triggerDistance * 1.5).toDouble();
    setState(() {
      _pullDistance = next;
      if (next > _maxPullDistance) _maxPullDistance = next;
    });
  }

  void _resetPull() {
    if ((_pullDistance == 0 && _maxPullDistance == 0) || !mounted) return;
    setState(() {
      _pullDistance = 0;
      _maxPullDistance = 0;
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await widget.onRefresh();
    } finally {
      _refreshing = false;
    }
  }
}

class _ReaderScrollBehavior extends MaterialScrollBehavior {
  const _ReaderScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: isError ? const Color(0xffffcccc) : const Color(0xffccffcc),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 14,
          color: isError ? const Color(0xff880000) : Colors.black,
        ),
      ),
    );
  }
}

class _AaFanclubDocumentView extends StatelessWidget {
  const _AaFanclubDocumentView({
    required this.document,
    required this.onNavigate,
    required this.currentFloor,
    required this.jumpFloor,
    required this.jumpNonce,
    required this.onCurrentFloorChanged,
    required this.onFloorLinkTap,
  });

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;
  final int? currentFloor;
  final int? jumpFloor;
  final int jumpNonce;
  final ValueChanged<int> onCurrentFloorChanged;
  final ValueChanged<Uri> onFloorLinkTap;

  @override
  Widget build(BuildContext context) {
    if (document.kind == ForumPageKind.thread) {
      return _ThreadView(
        key: ValueKey('${document.threadId}:${document.currentPage ?? 1}'),
        document: document,
        onNavigate: onNavigate,
        jumpFloor: jumpFloor,
        jumpNonce: jumpNonce,
        onCurrentFloorChanged: onCurrentFloorChanged,
        onFloorLinkTap: onFloorLinkTap,
      );
    }
    if (document.kind == ForumPageKind.board) {
      return document.uri.path == '/'
          ? _HomeView(document: document, onNavigate: onNavigate)
          : _BoardView(document: document, onNavigate: onNavigate);
    }
    return _GenericDocumentView(document: document);
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({required this.document, required this.onNavigate});

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HomeHeader(document: document, onNavigate: onNavigate),
          for (final thread in document.threads)
            _HomeThreadPreview(thread: thread, onNavigate: onNavigate),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.document, required this.onNavigate});

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    final notice = (document.textBlocks.firstOrNull ?? '').replaceAll(
      RegExp(r'\n[ \t　]*\n+'),
      '\n',
    );
    final noticeLines = notice
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[ \t　]+'), ''))
        .toList(growable: false);
    final session =
        (document.textBlocks.length > 1
                ? document.textBlocks[1]
                : '当前昵称：互联网的无名者')
            .replaceAll(RegExp(r'\s*■?修改■?\s*'), '')
            .trim();
    return _DoubleClassicFrame(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(5, 5, 5, 8),
      color: const Color(0xffccffcc),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DoubleClassicFrame(
            color: Color(0xffccffcc),
            innerPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              'AA同好会揭示板',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Saitamaar',
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          _DoubleClassicFrame(
            color: const Color(0xffccffcc),
            innerPadding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (noticeLines.isNotEmpty)
                  Text(
                    noticeLines.first,
                    style: const TextStyle(
                      fontFamily: 'Saitamaar',
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (noticeLines.length > 1)
                  AaText(
                    noticeLines.skip(1).join('\n'),
                    wrap: true,
                    lineHeight: 1.25,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _DoubleClassicFrame(
                    color: const Color(0xffccffcc),
                    innerPadding: const EdgeInsets.all(6),
                    child: Center(
                      child: ClassicLink(
                        '■帖子一览■',
                        bold: true,
                        fontSize: 13,
                        onTap:
                            () =>
                                onNavigate(document.uri.resolve('/form-1-1/')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: 3,
                  child: _DoubleClassicFrame(
                    color: const Color(0xffccffcc),
                    innerPadding: const EdgeInsets.all(6),
                    child: Text(
                      session,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 14,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoubleClassicFrame extends StatelessWidget {
  const _DoubleClassicFrame({
    required this.child,
    required this.color,
    this.width,
    this.margin = EdgeInsets.zero,
    this.innerPadding = EdgeInsets.zero,
  });

  final Widget child;
  final Color color;
  final double? width;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry innerPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black, width: 0.5),
      ),
      child: Container(
        padding: innerPadding,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.black, width: 0.5),
        ),
        child: child,
      ),
    );
  }
}

class _HomeThreadPreview extends StatelessWidget {
  const _HomeThreadPreview({required this.thread, required this.onNavigate});

  final ForumThreadSummary thread;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xffefefef),
        border: Border.all(color: Colors.black, width: 0.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClassicLink(
              thread.title,
              bold: true,
              fontSize: 24,
              onTap: () => onNavigate(thread.uri),
            ),
            const SizedBox(height: 4),
            for (final post in thread.previewPosts) PostCard(post: post),
          ],
        ),
      ),
    );
  }
}

class _BoardView extends StatelessWidget {
  const _BoardView({required this.document, required this.onNavigate});

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xffefefef),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        children: [
          _ClassicNavigation(document: document, onNavigate: onNavigate),
          const SizedBox(height: 12),
          for (final thread in document.threads)
            _ThreadSummaryRow(thread: thread, onNavigate: onNavigate),
          const Divider(height: 2, thickness: 1, color: Color(0xff888888)),
          _ClassicNavigation(document: document, onNavigate: onNavigate),
        ],
      ),
    );
  }
}

class _ThreadSummaryRow extends StatelessWidget {
  const _ThreadSummaryRow({required this.thread, required this.onNavigate});

  final ForumThreadSummary thread;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    final details =
        <String>[
          if (thread.replyCount != null) '【楼层数 ： ${thread.replyCount}】',
          if (thread.latestReplyAt != null) '【最新回复 ： ${thread.latestReplyAt}】',
        ].join();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 2, thickness: 1, color: Color(0xff888888)),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 8, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  ClassicLink(
                    thread.title,
                    bold: true,
                    fontSize: 24,
                    onTap: () => onNavigate(thread.uri),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 16,
                        height: 1,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: 'Saitamaar',
                    fontSize: 16,
                    height: 1,
                    color: Colors.black,
                  ),
                  children: [
                    TextSpan(text: '${thread.threadNumber ?? ''} ：'),
                    if (thread.author != null)
                      TextSpan(
                        text: thread.author,
                        style: const TextStyle(
                          color: Color(0xff008000),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (thread.createdAt != null)
                      TextSpan(text: '：${thread.createdAt}'),
                    if (thread.id != null) TextSpan(text: ' ID:${thread.id}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadView extends StatefulWidget {
  const _ThreadView({
    required this.document,
    required this.onNavigate,
    required this.jumpFloor,
    required this.jumpNonce,
    required this.onCurrentFloorChanged,
    required this.onFloorLinkTap,
    super.key,
  });

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;
  final int? jumpFloor;
  final int jumpNonce;
  final ValueChanged<int> onCurrentFloorChanged;
  final ValueChanged<Uri> onFloorLinkTap;

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  static const _postStartIndex = 4;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  int? _lastReportedFloor;

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_reportVisibleFloor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToFloor(widget.jumpFloor);
      _reportVisibleFloor();
    });
  }

  @override
  void didUpdateWidget(covariant _ThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jumpNonce != widget.jumpNonce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToFloor(widget.jumpFloor);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisibleFloor());
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_reportVisibleFloor);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xffefefef),
      child: ScrollablePositionedList.builder(
        key: const Key('thread-scroll'),
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        itemCount: widget.document.posts.length + 6,
        itemBuilder: _buildItem,
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    if (index == 0) {
      return _ClassicNavigation(
        document: widget.document,
        onNavigate: widget.onNavigate,
      );
    }
    if (index == 1) return const SizedBox(height: 18);
    if (index == 2) {
      return const Divider(height: 1, thickness: 1, color: Color(0xff888888));
    }
    if (index == 3) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          widget.document.title,
          style: const TextStyle(
            fontFamily: 'Saitamaar',
            fontSize: 32,
            height: 1,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    final postIndex = index - _postStartIndex;
    if (postIndex >= 0 && postIndex < widget.document.posts.length) {
      return PostCard(
        key: ValueKey('post-${widget.document.posts[postIndex].number}'),
        post: widget.document.posts[postIndex],
        onLinkTap: widget.onFloorLinkTap,
      );
    }
    if (postIndex == widget.document.posts.length) {
      return const SizedBox(height: 12);
    }
    return _ClassicNavigation(
      document: widget.document,
      onNavigate: widget.onNavigate,
    );
  }

  void _reportVisibleFloor() {
    if (!mounted || widget.document.posts.isEmpty) return;
    final positions =
        _itemPositionsListener.itemPositions.value
            .where(
              (item) =>
                  item.index >= _postStartIndex &&
                  item.index < _postStartIndex + widget.document.posts.length &&
                  item.itemTrailingEdge > 0 &&
                  item.itemLeadingEdge < 1,
            )
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (positions.isEmpty) return;
    final crossed = positions.where((item) => item.itemLeadingEdge <= 0.1);
    final selected = crossed.isEmpty ? positions.first : crossed.last;
    final current =
        widget.document.posts[selected.index - _postStartIndex].numericNumber;
    if (current == null || current == _lastReportedFloor) return;
    _lastReportedFloor = current;
    widget.onCurrentFloorChanged(current);
  }

  void _jumpToFloor(int? floor) {
    if (!mounted || floor == null || widget.document.posts.isEmpty) return;
    final postIndex = widget.document.posts.indexWhere(
      (post) => post.numericNumber == floor,
    );
    if (postIndex < 0 || !_itemScrollController.isAttached) return;
    _itemScrollController
        .scrollTo(
          index: _postStartIndex + postIndex,
          alignment: 0.05,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .then((_) => _reportVisibleFloor());
  }
}

class _ClassicNavigation extends StatelessWidget {
  const _ClassicNavigation({required this.document, required this.onNavigate});

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      _NavCell(
        key: const Key('nav-home'),
        child: ClassicLink(
          '■回到首页■',
          onTap: () => onNavigate(document.uri.resolve('/')),
        ),
      ),
      if (document.ownerOnlyUri != null)
        _NavCell(
          key: const Key('nav-owner-only'),
          child: ClassicLink(
            '■只看贴主■',
            onTap: () => onNavigate(document.ownerOnlyUri!),
          ),
        ),
    ];
    int? previousPage;
    for (final link in document.pagination) {
      final page = link.pageNumber;
      if (page == null) continue;
      if (previousPage != null && page - previousPage > 1) {
        entries.add(
          _NavCell(key: ValueKey('nav-gap-$page'), child: const Text('....')),
        );
      }
      entries.add(
        _NavCell(
          key: ValueKey('nav-page-$page'),
          child:
              page == document.currentPage
                  ? Text(
                    '$page',
                    style: const TextStyle(
                      fontFamily: 'Saitamaar',
                      fontSize: 16,
                      height: 1,
                    ),
                  )
                  : ClassicLink('$page', onTap: () => onNavigate(link.uri)),
        ),
      );
      previousPage = page;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(children: entries),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 16,
          height: 1,
          color: Colors.black,
        ),
        child: child,
      ),
    );
  }
}

class _GenericDocumentView extends StatelessWidget {
  const _GenericDocumentView({required this.document});

  final ForumDocument document;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xffefefef),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            document.title,
            style: const TextStyle(
              fontFamily: 'Saitamaar',
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          for (final block in document.textBlocks) ...[
            AaText(block, wrap: true),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
