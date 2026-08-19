import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _postsPerPage = 50;
  static final _threadPath = RegExp(r'^/view/(\d+)(?:-\d+)?(?:-icchi)?/?$');
  static final _boardPath = RegExp(r'^/form-(\d+)-(\d+)/?$');

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
  bool _edgeHintVisible = false;
  DateTime? _lastBackPress;
  Timer? _middleTapTimer;
  int _linkTapSerial = 0;

  /// Windows and other desktop targets get a visible toolbar plus keyboard
  /// shortcuts; touch targets keep the original chrome-free reading surface.
  bool get _isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };

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
    _middleTapTimer?.cancel();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Scaffold(body: SafeArea(child: _buildShortcutScope(_buildShell()))),
    );
  }

  /// Desktop key bindings mirror the toolbar. Text fields keep their own keys,
  /// so every binding except Escape stands down while the caret is active.
  Widget _buildShortcutScope(Widget child) {
    if (!_isDesktop) return child;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () => _onShortcut(_reload),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            () => _onShortcut(_reload),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            () => _onShortcut(_goBack),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            () => _onShortcut(_goForward),
        const SingleActivator(LogicalKeyboardKey.home, alt: true):
            () => _onShortcut(_goHome),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true):
            () => _onShortcut(() => _goToRelativePage(-1)),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
            () => _onShortcut(() => _goToRelativePage(1)),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true):
            () => _onShortcut(_promptJumpToFloor),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            () => _onShortcut(_bookmarkCurrentFloor),
        const SingleActivator(LogicalKeyboardKey.escape): _closePanel,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  Widget _buildShell() {
    return Column(
      children: [
        if (_isDesktop)
          _DesktopToolbar(
            canGoBack: _controller.canGoBack,
            canGoForward: _controller.canGoForward,
            canReload: _controller.canReload,
            currentPage: _currentPage,
            pageCount: _pageCount,
            isThread: _controller.document?.kind == ForumPageKind.thread,
            onBack: _goBack,
            onForward: _goForward,
            onReload: _reload,
            onHome: _goHome,
            onBoardList: _goBoardList,
            onPreviousPage: () => _goToRelativePage(-1),
            onNextPage: () => _goToRelativePage(1),
            onJumpToFloor: _promptJumpToFloor,
            onOpenPanel: () => setState(() => _drawerOpen = !_drawerOpen),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
            final panelWidth = (constraints.maxWidth * 0.68).clamp(
              250.0,
              390.0,
            );
            final leftZone = _resolveZone(true, constraints.biggest);
            final rightZone = _resolveZone(false, constraints.biggest);
            return Stack(
              children: [
                Positioned.fill(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(_readerStore.displayScale),
                    ),
                    child: _EdgeTapSurface(
                      size: constraints.biggest,
                      leftZone: leftZone,
                      rightZone: rightZone,
                      // The desktop toolbar replaces the invisible zones so a
                      // stray click never reloads the page.
                      enabled: !_drawerOpen && !_isDesktop,
                      onEdgeTap: _handleEdgeTap,
                      hintVisible: _edgeHintVisible,
                      onMiddleTap: _handleMiddleTap,
                      onHideHint: _hideEdgeHint,
                      onZoneMoved:
                          (left, dy) =>
                              _moveZone(left, dy, constraints.biggest),
                      onZoneResized:
                          (left, dx, dy) =>
                              _resizeZone(left, dx, dy, constraints.biggest),
                      onZoneReset: _readerStore.resetEdgeZone,
                      child: _PullToRefresh(
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
                    onClose: () => setState(() => _drawerOpen = false),
                    onHome: _goHome,
                    onBookmarkCurrent: _bookmarkCurrentFloor,
                    onOpenThread: _openSavedPosition,
                    onOpenBookmark: _openBookmark,
                    onRemoveBookmark: _readerStore.removeBookmark,
                    onRemoveThread: _readerStore.removeThread,
                    onScaleChanged: _readerStore.setDisplayScale,
                    onClearCache: _controller.clearCache,
                    login: _readerStore.login,
                    onLogin: _loginAndRemember,
                    onStartReply: () => _openComposer(ComposerMode.reply),
                    onStartNewThread:
                        () => _openComposer(ComposerMode.newThread),
                    currentPage: _currentPage,
                    pageCount: _pageCount,
                    onPreviousPage: () => _goToRelativePage(-1),
                    onNextPage: () => _goToRelativePage(1),
                    onJumpToFloor: _promptJumpToFloor,
                  ),
                ),
              ],
            );
            },
          ),
        ),
      ],
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
        onReply: () => _openComposer(ComposerMode.reply),
      );
    }
    return _GenericDocumentView(document: document);
  }

  void _navigate(Uri uri) {
    _linkTapSerial++;
    _hideEdgeHint();
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
    _linkTapSerial++;
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

    final targetPage = ((floor - 1) ~/ _postsPerPage) + 1;
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
    final targetPage = ((marker.floor - 1) ~/ _postsPerPage) + 1;
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

  void _goForward() {
    setState(() => _drawerOpen = false);
    unawaited(_controller.goForward());
  }

  void _goBoardList() {
    setState(() => _drawerOpen = false);
    unawaited(_controller.openLink(Uri.parse(_home).resolve('/form-1-1/')));
  }

  void _reload() => unawaited(_controller.reload());

  void _closePanel() {
    if (_drawerOpen) setState(() => _drawerOpen = false);
  }

  /// Two taps on the reading area reveal the invisible edge zones. Anything
  /// else — a further tap, a scroll, a navigation — puts them away again.
  void _handleMiddleTap() {
    if (_edgeHintVisible) {
      _hideEdgeHint();
      return;
    }
    if (_middleTapTimer?.isActive ?? false) {
      _middleTapTimer?.cancel();
      _middleTapTimer = null;
      // The second tap also lands on the text's SelectionArea, which selects a
      // word. Dropping focus clears that so the zones are what you get.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _edgeHintVisible = true);
      return;
    }
    _middleTapTimer = Timer(kDoubleTapTimeout, () => _middleTapTimer = null);
  }

  /// Turns a stored zone layout into pixels. A null field falls back to the
  /// screen-derived default, which is what keeps "default" meaningful when the
  /// window is resized or the device is rotated.
  _EdgeZoneGeometry _resolveZone(bool left, Size size) {
    final layout = _readerStore.edgeZone(left);
    final width = (layout.width ?? (size.width * 0.18).clamp(56.0, 96.0)).clamp(
      48.0,
      size.width * 0.5,
    );
    final height =
        (layout.height ?? (size.height * 0.26).clamp(150.0, 220.0)).clamp(
          80.0,
          size.height,
        );
    final center = (layout.centerFactor ?? 0.5) * size.height;
    final maxTop = (size.height - height).clamp(0.0, size.height);
    return _EdgeZoneGeometry(
      width: width,
      height: height,
      top: (center - height / 2).clamp(0.0, maxTop),
      isDefault: layout.isDefault,
    );
  }

  void _moveZone(bool left, double dy, Size size) {
    if (size.height <= 0) return;
    final zone = _resolveZone(left, size);
    final maxTop = (size.height - zone.height).clamp(0.0, size.height);
    final top = (zone.top + dy).clamp(0.0, maxTop);
    _readerStore.setEdgeZone(
      left,
      _readerStore
          .edgeZone(left)
          .copyWith(centerFactor: (top + zone.height / 2) / size.height),
    );
  }

  void _resizeZone(bool left, double dx, double dy, Size size) {
    final zone = _resolveZone(left, size);
    _readerStore.setEdgeZone(
      left,
      _readerStore.edgeZone(left).copyWith(
        width: (zone.width + dx).clamp(48.0, size.width * 0.5),
        height: (zone.height + dy).clamp(80.0, size.height),
      ),
    );
  }

  /// A link tapped inside a zone must win over the zone. Raw pointer events
  /// reach the surface before the gesture arena hands the tap to the link, so
  /// the zone's action waits one microtask and stands down if a link claimed
  /// the same tap in the meantime.
  void _handleEdgeTap(bool left) {
    final serial = _linkTapSerial;
    scheduleMicrotask(() {
      if (!mounted || _linkTapSerial != serial) return;
      _hideEdgeHint();
      if (left) {
        if (_controller.canReload) unawaited(_controller.reload());
      } else {
        setState(() => _drawerOpen = true);
      }
    });
  }

  void _hideEdgeHint() {
    _middleTapTimer?.cancel();
    _middleTapTimer = null;
    if (_edgeHintVisible) setState(() => _edgeHintVisible = false);
  }

  /// Keyboard bindings stay out of the way while a text field owns the caret.
  void _onShortcut(VoidCallback action) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorStateOfType<EditableTextState>() != null) return;
    action();
  }

  /// The Android system back key walks the reader's own history before it is
  /// allowed to close the app.
  Future<void> _handleSystemBack() async {
    if (_drawerOpen) {
      setState(() => _drawerOpen = false);
      return;
    }
    if (_controller.canGoBack) {
      _goBack();
      return;
    }
    final now = DateTime.now();
    final previous = _lastBackPress;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    _showMessage('再按一次返回键退出');
  }

  int get _currentPage => _controller.document?.currentPage ?? 1;

  int get _pageCount {
    final document = _controller.document;
    if (document == null) return 1;
    return document.pageCount ?? document.currentPage ?? 1;
  }

  void _goToRelativePage(int delta) {
    final uri = _uriForPage(_currentPage + delta);
    if (uri == null) return;
    setState(() => _drawerOpen = false);
    unawaited(_controller.openLink(uri));
  }

  /// Prefers a page link the site itself published, and falls back to the
  /// canonical `/view/<id>-<page>` and `/form-<board>-<page>/` shapes.
  Uri? _uriForPage(int page) {
    final document = _controller.document;
    if (document == null || page < 1 || page > _pageCount) return null;
    if (page == _currentPage) return null;
    for (final link in document.pagination) {
      if (link.pageNumber == page) return link.uri;
    }
    final threadId = document.threadId;
    if (threadId != null) {
      final suffix = document.uri.path.endsWith('-icchi') ? '-icchi' : '';
      return document.uri.replace(
        path: '/view/$threadId-$page$suffix',
        query: null,
        fragment: null,
      );
    }
    final board = _boardPath.firstMatch(document.uri.path);
    if (board != null) {
      return document.uri.replace(
        path: '/form-${board.group(1)}-$page/',
        query: null,
        fragment: null,
      );
    }
    return null;
  }

  Future<void> _promptJumpToFloor() async {
    final document = _controller.document;
    if (document == null || document.kind != ForumPageKind.thread) {
      _showMessage('只有帖子页可以跳转楼层');
      return;
    }
    setState(() => _drawerOpen = false);
    final floor = await showDialog<int>(
      context: context,
      builder: (context) => _JumpToFloorDialog(currentFloor: _currentFloor),
    );
    if (floor != null && mounted) _jumpToFloorNumber(floor);
  }

  void _jumpToFloorNumber(int floor) {
    final document = _controller.document;
    final threadId = document?.threadId;
    if (document == null || threadId == null || floor < 1) return;

    final targetPage = ((floor - 1) ~/ _postsPerPage) + 1;
    if (targetPage > _pageCount) {
      _showMessage('这个帖子还没有第 $floor 楼');
      return;
    }
    if (targetPage == _currentPage) {
      if (!document.posts.any((post) => post.numericNumber == floor)) {
        _showMessage('这一页没有第 $floor 楼');
        return;
      }
      setState(() {
        _currentFloor = floor;
        _jumpFloor = floor;
        _jumpNonce++;
      });
      return;
    }

    _pendingJumpThread = threadId;
    _pendingProgressFloor = floor;
    final suffix = document.uri.path.endsWith('-icchi') ? '-icchi' : '';
    unawaited(
      _controller.openLink(
        document.uri.resolve('/view/$threadId-$targetPage$suffix'),
      ),
    );
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

/// Where one edge zone currently sits, after the reader's own adjustments.
class _EdgeZoneGeometry {
  const _EdgeZoneGeometry({
    required this.width,
    required this.height,
    required this.top,
    required this.isDefault,
  });

  final double width;
  final double height;
  final double top;
  final bool isDefault;

  double get bottom => top + height;
}

class _EdgeTapSurface extends StatefulWidget {
  const _EdgeTapSurface({
    required this.size,
    required this.leftZone,
    required this.rightZone,
    required this.enabled,
    required this.onEdgeTap,
    required this.hintVisible,
    required this.onMiddleTap,
    required this.onHideHint,
    required this.onZoneMoved,
    required this.onZoneResized,
    required this.onZoneReset,
    required this.child,
  });

  final Size size;
  final _EdgeZoneGeometry leftZone;
  final _EdgeZoneGeometry rightZone;
  final bool enabled;

  /// Reports that a zone was tapped. The page decides whether the tap really
  /// belongs to the zone or to a link sitting on top of it.
  final void Function(bool left) onEdgeTap;

  /// Whether the otherwise invisible zones are being shown as a reminder.
  final bool hintVisible;
  final VoidCallback onMiddleTap;
  final VoidCallback onHideHint;

  /// Adjustments are reported as deltas; the page owns the stored layout.
  final void Function(bool left, double dy) onZoneMoved;
  final void Function(bool left, double dx, double dy) onZoneResized;
  final void Function(bool left) onZoneReset;
  final Widget child;

  @override
  State<_EdgeTapSurface> createState() => _EdgeTapSurfaceState();
}

class _EdgeTapSurfaceState extends State<_EdgeTapSurface> {
  static const _tapSlop = 12.0;

  Offset? _downPosition;
  Duration? _downTime;

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('edge-tap-surface'),
      // Every zone gesture is read from raw pointers. A GestureDetector here
      // loses the arena to the SelectionArea wrapping each post, so an edge
      // tap that happened to land on text was silently swallowed.
      onPointerDown: (event) {
        _downPosition = event.localPosition;
        _downTime = event.timeStamp;
      },
      onPointerUp: _handlePointerUp,
      onPointerCancel: (_) {
        _downPosition = null;
        _downTime = null;
      },
      child: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                // Scrolling counts as an action, so the reminder gets out of
                // the way as soon as reading resumes.
                onNotification: (notification) {
                  if (widget.hintVisible &&
                      notification is ScrollUpdateNotification) {
                    widget.onHideHint();
                  }
                  return false;
                },
                child: widget.child,
              ),
            ),
            if (widget.hintVisible) ...[
              ..._buildZone(left: true),
              ..._buildZone(left: false),
            ],
          ],
      ),
    );
  }

  /// The reset button lives in the full-screen stack rather than inside the
  /// zone: a child hanging past its parent's bounds paints but cannot be hit.
  Rect? _resetButtonRect(bool left) {
    final zone = left ? widget.leftZone : widget.rightZone;
    if (zone.isDefault) return null;
    const gap = 6.0;
    const side = 32.0;
    final x =
        left ? zone.width + gap : widget.size.width - zone.width - gap - side;
    return Rect.fromLTWH(x, zone.top, side, side);
  }

  List<Widget> _buildZone({required bool left}) {
    final zone = left ? widget.leftZone : widget.rightZone;
    final reset = _resetButtonRect(left);
    return [
      Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: zone.top,
        width: zone.width,
        height: zone.height,
        child: _EdgeHint(
          // On the hint itself, not the Positioned, so tests can measure it.
          key: Key(left ? 'edge-hint-left' : 'edge-hint-right'),
          label: left ? '刷新' : '阅读工具',
          left: left,
          onTap: () => widget.onEdgeTap(left),
          onMove: (delta) => widget.onZoneMoved(left, delta.dy),
          onResize: (delta) => widget.onZoneResized(left, delta.dx, delta.dy),
        ),
      ),
      if (reset != null)
        Positioned.fromRect(
          rect: reset,
          child: Material(
            color: const Color(0xccf6f4ed),
            shape: const RoundedRectangleBorder(
              side: BorderSide(color: Colors.black),
            ),
            child: IconButton(
              key: Key(left ? 'edge-reset-left' : 'edge-reset-right'),
              tooltip: '恢复默认大小和位置',
              padding: EdgeInsets.zero,
              iconSize: 18,
              onPressed: () => widget.onZoneReset(left),
              icon: const Icon(Icons.settings_backup_restore),
            ),
          ),
        ),
    ];
  }

  bool _inEdgeZone(Offset position) {
    final left = widget.leftZone;
    if (position.dx <= left.width &&
        position.dy >= left.top &&
        position.dy <= left.bottom) {
      return true;
    }
    final right = widget.rightZone;
    return position.dx >= widget.size.width - right.width &&
        position.dy >= right.top &&
        position.dy <= right.bottom;
  }

  void _handlePointerUp(PointerUpEvent event) {
    final down = _downPosition;
    final downTime = _downTime;
    _downPosition = null;
    _downTime = null;
    if (!widget.enabled || down == null) return;
    // A drag is a scroll, not a tap.
    if ((event.localPosition - down).distance > _tapSlop) return;

    if (_inEdgeZone(down)) {
      // While shown, each zone handles its own tap so it can also drag,
      // resize and put itself away.
      if (widget.hintVisible) return;
      // A held press belongs to the text underneath, so selecting and copying
      // inside a zone still works.
      final held = downTime == null ? Duration.zero : event.timeStamp - downTime;
      if (held >= kLongPressTimeout) return;

      widget.onEdgeTap(down.dx <= widget.leftZone.width);
      return;
    }

    // Working the reset button is an adjustment, not a tap somewhere else.
    if (widget.hintVisible &&
        ((_resetButtonRect(true)?.contains(down) ?? false) ||
            (_resetButtonRect(false)?.contains(down) ?? false))) {
      return;
    }
    widget.onMiddleTap();
  }
}

/// The translucent stand-in for an edge zone, shown only after a double tap.
/// While it is up the zone can be dragged and resized; the reset button only
/// appears once the zone has actually been moved from its default.
class _EdgeHint extends StatelessWidget {
  const _EdgeHint({
    required this.label,
    required this.left,
    required this.onTap,
    required this.onMove,
    required this.onResize,
    super.key,
  });

  static const _handleSize = 26.0;

  final String label;
  final bool left;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onPanUpdate: (details) => onMove(details.delta),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x59808080),
                border: Border.all(color: const Color(0x73000000)),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Saitamaar',
                  fontSize: 15,
                  height: 1.2,
                  color: Color(0xdd000000),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        // Resize grip on the inner corner, away from the screen edge.
        Positioned(
          left: left ? null : 0,
          right: left ? 0 : null,
          bottom: 0,
          width: _handleSize,
          height: _handleSize,
          child: GestureDetector(
            key: Key(left ? 'edge-resize-left' : 'edge-resize-right'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate:
                (details) => onResize(
                  // Dragging away from the screen edge grows the zone.
                  Offset(left ? details.delta.dx : -details.delta.dx,
                      details.delta.dy),
                ),
            child: Container(
              color: const Color(0x66000000),
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: left ? 0 : 1.5708,
                child: const Icon(
                  Icons.open_in_full,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which end of the list the reader is pulling from.
enum _PullEdge { top, bottom }

/// Overscrolling either end far enough triggers a refresh. Both ends work, so
/// the gesture is available whether the reader is at the newest post or the
/// oldest one.
class _PullToRefresh extends StatefulWidget {
  const _PullToRefresh({
    required this.enabled,
    required this.onRefresh,
    required this.child,
  });

  final bool enabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<_PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<_PullToRefresh> {
  static const _triggerDistance = 64.0;

  double _pullDistance = 0;
  double _maxPullDistance = 0;
  _PullEdge _edge = _PullEdge.bottom;
  bool _refreshing = false;

  bool get _armed => _maxPullDistance >= _triggerDistance;

  String get _label {
    if (_refreshing) return '正在刷新';
    return _armed ? '松开刷新' : '继续拉动刷新';
  }

  @override
  Widget build(BuildContext context) {
    final showing = _refreshing || _pullDistance > 0;
    return NotificationListener<ScrollNotification>(
      key: const Key('pull-refresh'),
      onNotification: _handleScroll,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (showing)
            Positioned(
              left: 0,
              right: 0,
              top: _edge == _PullEdge.top ? 8 : null,
              bottom: _edge == _PullEdge.top ? null : 8,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const Key('pull-refresh-indicator'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfff7f5ed),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Text(
                      _label,
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
    // While a refresh runs the indicator stays put and says so; new pulls are
    // ignored until it finishes.
    if (!widget.enabled || _refreshing) return false;

    final metrics = notification.metrics;
    if (notification is OverscrollNotification) {
      if (notification.overscroll > 0 && metrics.extentAfter <= 0.01) {
        _setPull(_PullEdge.bottom, _pullDistance + notification.overscroll);
      } else if (notification.overscroll < 0 && metrics.extentBefore <= 0.01) {
        _setPull(_PullEdge.top, _pullDistance - notification.overscroll);
      }
    } else if (notification is ScrollUpdateNotification) {
      final beyondBottom = metrics.pixels - metrics.maxScrollExtent;
      final beyondTop = metrics.minScrollExtent - metrics.pixels;
      if (beyondBottom > 0 && metrics.extentAfter <= 0.01) {
        _setPull(_PullEdge.bottom, beyondBottom);
      } else if (beyondTop > 0 && metrics.extentBefore <= 0.01) {
        _setPull(_PullEdge.top, beyondTop);
      }
    } else if (notification is ScrollEndNotification && _maxPullDistance > 0) {
      if (_armed) {
        unawaited(_refresh());
      } else {
        _resetPull();
      }
    }
    return false;
  }

  void _setPull(_PullEdge edge, double value) {
    final next = value.clamp(0, _triggerDistance * 1.5).toDouble();
    setState(() {
      _edge = edge;
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
    // Swap straight from "release" to "refreshing" in one frame so the
    // indicator never blinks out between the two.
    setState(() {
      _refreshing = true;
      _pullDistance = 0;
      _maxPullDistance = 0;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      } else {
        _refreshing = false;
      }
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
    // Purely informational, so it never takes a pointer away from the page
    // underneath and stays see-through enough to read the AA behind it.
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: isError ? const Color(0xccffcccc) : const Color(0xccccffcc),
        child: Text(
          message,
          style: TextStyle(
            fontFamily: 'Saitamaar',
            fontSize: 14,
            color: isError ? const Color(0xff880000) : Colors.black,
          ),
        ),
      ),
    );
  }
}

/// Classic-styled toolbar shown on desktop only. Every entry has a keyboard
/// equivalent, listed in its tooltip.
class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.canGoBack,
    required this.canGoForward,
    required this.canReload,
    required this.currentPage,
    required this.pageCount,
    required this.isThread,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onBoardList,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onJumpToFloor,
    required this.onOpenPanel,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool canReload;
  final int currentPage;
  final int pageCount;
  final bool isThread;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  final VoidCallback onBoardList;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback onJumpToFloor;
  final VoidCallback onOpenPanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('desktop-toolbar'),
      color: const Color(0xffefefef),
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
      child: Row(
        children: [
          // A narrow window scrolls the controls instead of clipping them.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildControls()),
            ),
          ),
          _ToolbarCell(
            key: const Key('toolbar-panel'),
            label: '■阅读工具■',
            tooltip: '书签、登录、发帖、显示大小',
            onTap: onOpenPanel,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildControls() {
    return [
          _ToolbarCell(
            key: const Key('toolbar-back'),
            label: '■后退■',
            tooltip: '后退（Alt+←）',
            enabled: canGoBack,
            onTap: onBack,
          ),
          _ToolbarCell(
            key: const Key('toolbar-forward'),
            label: '■前进■',
            tooltip: '前进（Alt+→）',
            enabled: canGoForward,
            onTap: onForward,
          ),
          _ToolbarCell(
            key: const Key('toolbar-reload'),
            label: '■刷新■',
            tooltip: '刷新（F5）',
            enabled: canReload,
            onTap: onReload,
          ),
          const SizedBox(width: 8),
          _ToolbarCell(
            key: const Key('toolbar-home'),
            label: '■首页■',
            tooltip: '回到首页（Alt+Home）',
            onTap: onHome,
          ),
          _ToolbarCell(
            key: const Key('toolbar-board'),
            label: '■帖子一览■',
            tooltip: '打开帖子一览',
            onTap: onBoardList,
          ),
          const SizedBox(width: 8),
          _ToolbarCell(
            key: const Key('toolbar-previous-page'),
            label: '◀',
            tooltip: '上一页（Ctrl+PageUp）',
            enabled: currentPage > 1,
            onTap: onPreviousPage,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '$currentPage / $pageCount',
              key: const Key('toolbar-page-indicator'),
              style: const TextStyle(
                fontFamily: 'Saitamaar',
                fontSize: 16,
                height: 1,
                color: Colors.black,
              ),
            ),
          ),
          _ToolbarCell(
            key: const Key('toolbar-next-page'),
            label: '▶',
            tooltip: '下一页（Ctrl+PageDown）',
            enabled: currentPage < pageCount,
            onTap: onNextPage,
          ),
          const SizedBox(width: 8),
          _ToolbarCell(
            key: const Key('toolbar-jump-floor'),
            label: '■跳楼层■',
            tooltip: '跳到指定楼层（Ctrl+G）',
            enabled: isThread,
            onTap: onJumpToFloor,
          ),
        ];
  }
}

class _ToolbarCell extends StatelessWidget {
  const _ToolbarCell({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  static const _padding = EdgeInsets.symmetric(horizontal: 7, vertical: 5);

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? Colors.black : const Color(0xffaaaaaa),
          ),
        ),
        child:
            enabled
                ? ClassicLink(label, padding: _padding, onTap: onTap)
                : Padding(
                  padding: _padding,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Saitamaar',
                      fontSize: 16,
                      height: 1,
                      color: Color(0xffaaaaaa),
                    ),
                  ),
                ),
      ),
    );
  }
}

/// Asks for a floor number. Returns the parsed floor, or null when cancelled.
class _JumpToFloorDialog extends StatefulWidget {
  const _JumpToFloorDialog({this.currentFloor});

  final int? currentFloor;

  @override
  State<_JumpToFloorDialog> createState() => _JumpToFloorDialogState();
}

class _JumpToFloorDialogState extends State<_JumpToFloorDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('jump-to-floor-dialog'),
      backgroundColor: const Color(0xfff6f4ed),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Colors.black),
      ),
      title: const Text(
        '跳转楼层',
        style: TextStyle(fontFamily: 'Saitamaar', fontSize: 18, height: 1),
      ),
      content: TextField(
        key: const Key('jump-to-floor-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        style: const TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 16,
          height: 1,
        ),
        decoration: InputDecoration(
          hintText:
              widget.currentFloor == null
                  ? '楼层号'
                  : '楼层号（当前 #${widget.currentFloor}）',
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.all(9),
          border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Colors.black),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('jump-to-floor-confirm'),
          onPressed: _submit,
          child: const Text('跳转'),
        ),
      ],
    );
  }

  void _submit() {
    final floor = int.tryParse(_controller.text.trim());
    Navigator.pop(context, floor != null && floor > 0 ? floor : null);
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
    required this.onReply,
  });

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;
  final int? currentFloor;
  final int? jumpFloor;
  final int jumpNonce;
  final ValueChanged<int> onCurrentFloorChanged;
  final ValueChanged<Uri> onFloorLinkTap;
  final VoidCallback onReply;

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
        onReply: onReply,
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

  /// Matches the site table's `cellspacing="7"` and `cellpadding="3"`, with
  /// the gap sandwiched between the outer rule and the cells halved.
  static const _cellSpacing = 7.0;
  static const _frameGap = 3.5;
  static const _cellPadding = EdgeInsets.all(3);

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
    // Mirrors the site's `<table border=1 cellspacing=7 cellpadding=3>`: one
    // outer rule, then a single thin rule per cell.
    return Container(
      key: const Key('home-notice-table'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(5, 5, 5, 8),
      padding: const EdgeInsets.all(_frameGap),
      decoration: BoxDecoration(
        color: const Color(0xffccffcc),
        border: Border.fromBorderSide(classicRule(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _NoticeCell(
            padding: _cellPadding,
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
          const SizedBox(height: _cellSpacing),
          _NoticeCell(
            padding: _cellPadding,
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
          const SizedBox(height: _cellSpacing),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _NoticeCell(
                    // The link owns the cell so the whole box stays tappable
                    // even at the site's tight three-pixel padding.
                    padding: EdgeInsets.zero,
                    child: ClassicLink(
                      '■帖子一览■',
                      bold: true,
                      fontSize: 13,
                      padding: _cellPadding,
                      expand: true,
                      onTap:
                          () => onNavigate(document.uri.resolve('/form-1-1/')),
                    ),
                  ),
                ),
                const SizedBox(width: _cellSpacing),
                Expanded(
                  flex: 3,
                  child: _NoticeCell(
                    padding: _cellPadding,
                    child: Center(
                      child: Text(
                        session,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Saitamaar',
                          fontSize: 16,
                          height: 1,
                        ),
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

/// A one-physical-pixel rule, the width a browser draws for `border="1"`.
/// A whole logical pixel reads as a heavy stroke on a high-density screen.
BorderSide classicRule(BuildContext context) => BorderSide(
  color: Colors.black,
  width: 1 / MediaQuery.devicePixelRatioOf(context),
);

/// One cell of the homepage notice table: a single thin rule, nothing else.
class _NoticeCell extends StatelessWidget {
  const _NoticeCell({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border.fromBorderSide(classicRule(context)),
      ),
      child: child,
    );
  }
}

/// Thread titles are the most-tapped links in the reader, so they carry real
/// slack above and below the glyphs instead of a bare text-sized target.
const _threadTitleHitPadding = EdgeInsets.fromLTRB(2, 6, 12, 8);

class _HomeThreadPreview extends StatelessWidget {
  const _HomeThreadPreview({required this.thread, required this.onNavigate});

  final ForumThreadSummary thread;
  final ValueChanged<Uri> onNavigate;

  @override
  Widget build(BuildContext context) {
    // `<table border=1 cellspacing=7 cellpadding=3>` with a single cell: the
    // two rules belong there, but they need the site's 7px gap between them.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 8),
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: const Color(0xffefefef),
        border: Border.fromBorderSide(classicRule(context)),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.fromBorderSide(classicRule(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClassicLink(
              thread.title,
              bold: true,
              fontSize: 24,
              padding: _threadTitleHitPadding,
              onTap: () => onNavigate(thread.uri),
            ),
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
                    padding: _threadTitleHitPadding,
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
    required this.onReply,
    super.key,
  });

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;
  final int? jumpFloor;
  final int jumpNonce;
  final ValueChanged<int> onCurrentFloorChanged;
  final ValueChanged<Uri> onFloorLinkTap;
  final VoidCallback onReply;

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
      onReply: widget.onReply,
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
  const _ClassicNavigation({
    required this.document,
    required this.onNavigate,
    this.onReply,
  });

  final ForumDocument document;
  final ValueChanged<Uri> onNavigate;

  /// Set only on the row under the last post, where a reader who has just
  /// finished reading is most likely to want the composer.
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    const cellPadding = _NavCell.contentPadding;
    final entries = <Widget>[
      _NavCell(
        key: const Key('nav-home'),
        child: ClassicLink(
          '■回到首页■',
          padding: cellPadding,
          onTap: () => onNavigate(document.uri.resolve('/')),
        ),
      ),
      if (document.ownerFilter != null)
        _NavCell(
          key: const Key('nav-owner-only'),
          child: ClassicLink(
            document.ownerFilter!.title,
            padding: cellPadding,
            onTap: () => onNavigate(document.ownerFilter!.uri),
          ),
        ),
    ];
    int? previousPage;
    for (final link in document.pagination) {
      final page = link.pageNumber;
      if (page == null) continue;
      if (previousPage != null && page - previousPage > 1) {
        entries.add(
          _NavCell(
            key: ValueKey('nav-gap-$page'),
            child: const Padding(padding: cellPadding, child: Text('....')),
          ),
        );
      }
      entries.add(
        _NavCell(
          key: ValueKey('nav-page-$page'),
          child:
              page == document.currentPage
                  ? Padding(
                    padding: cellPadding,
                    child: Text(
                      '$page',
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 16,
                        height: 1,
                      ),
                    ),
                  )
                  : ClassicLink(
                    '$page',
                    padding: cellPadding,
                    onTap: () => onNavigate(link.uri),
                  ),
        ),
      );
      previousPage = page;
    }
    if (onReply != null) {
      entries.add(
        _NavCell(
          key: const Key('nav-reply'),
          child: ClassicLink(
            '■回复■',
            padding: cellPadding,
            onTap: onReply!,
          ),
        ),
      );
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

  /// Owned by the cell's child rather than the cell, so tapping anywhere
  /// inside the border counts — the cell keeps its original size either way.
  static const contentPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 2,
  );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.fromBorderSide(classicRule(context)),
      ),
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
