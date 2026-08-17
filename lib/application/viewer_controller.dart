import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/forum_repository.dart';
import '../domain/forum_document.dart';

enum ViewerPhase { idle, loading, ready, error }

class ViewerController extends ChangeNotifier {
  ViewerController(this._repository);

  final ForumRepository _repository;
  final List<Uri> _history = [];
  int _historyIndex = -1;
  int _requestSerial = 0;
  Timer? _statusTimer;

  ViewerPhase phase = ViewerPhase.idle;
  ForumDocument? document;
  Uri? pendingUri;
  String? errorMessage;
  String? statusMessage;
  bool isSubmitting = false;

  bool get canGoBack => _historyIndex > 0 && phase != ViewerPhase.loading;
  bool get canGoForward =>
      _historyIndex >= 0 &&
      _historyIndex < _history.length - 1 &&
      phase != ViewerPhase.loading;
  bool get canReload => document != null && phase != ViewerPhase.loading;

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> openAddress(String address) async {
    final input = address.trim().replaceFirst(RegExp(r'[，,]+$'), '');
    if (input.isEmpty) {
      _showError('请输入网站地址');
      return;
    }

    Uri uri;
    try {
      final parsed = Uri.parse(input);
      if (parsed.hasScheme) {
        uri = parsed;
      } else if (document != null &&
          (input.startsWith('/') || input.startsWith('?'))) {
        uri = document!.uri.resolve(input);
      } else {
        final scheme =
            input.toLowerCase().startsWith('aafanclub.com') ||
                    input.toLowerCase().startsWith('www.aafanclub.com')
                ? 'http'
                : 'https';
        uri = Uri.parse('$scheme://$input');
      }
      if ((uri.host == 'aafanclub.com' || uri.host == 'www.aafanclub.com') &&
          uri.scheme == 'https') {
        uri = uri.replace(scheme: 'http');
      }
    } on FormatException {
      _showError('网站地址格式不正确');
      return;
    }
    await _load(uri, addToHistory: true);
  }

  Future<void> openLink(Uri uri) => _load(uri, addToHistory: true);

  Future<void> reload() async {
    final current = document;
    if (current == null) return;
    final serial = ++_requestSerial;
    errorMessage = null;
    _clearStatus();
    phase = ViewerPhase.loading;
    notifyListeners();

    try {
      final refreshed = await _repository.refresh(current);
      if (serial != _requestSerial) return;
      final addedPosts = refreshed.posts.length - current.posts.length;
      document = refreshed;
      pendingUri = refreshed.uri;
      phase = ViewerPhase.ready;
      if (current.kind == ForumPageKind.thread) {
        _showStatus(addedPosts > 0 ? '已追加 $addedPosts 个新楼层' : '没有新楼层');
      } else if (current.kind == ForumPageKind.board) {
        _showStatus('帖子列表已刷新');
      } else {
        _showStatus('页面已刷新');
      }
    } catch (error) {
      if (serial != _requestSerial) return;
      errorMessage = error.toString();
      phase = ViewerPhase.error;
    }
    notifyListeners();
  }

  Future<void> goBack() async {
    if (!canGoBack) return;
    await _load(
      _history[_historyIndex - 1],
      targetHistoryIndex: _historyIndex - 1,
    );
  }

  Future<void> goForward() async {
    if (!canGoForward) return;
    await _load(
      _history[_historyIndex + 1],
      targetHistoryIndex: _historyIndex + 1,
    );
  }

  Future<bool> login({required String name, required String trip}) async {
    final current = document;
    if (current == null || isSubmitting) return false;
    return _submit(
      () => _repository.login(current, name: name, trip: trip),
      successMessage: '登录设置已保存',
    );
  }

  Future<bool> reply(String content) async {
    final current = document;
    if (current == null || isSubmitting) return false;
    return _submit(
      () => _repository.reply(current, content: content),
      successMessage: '回复已发表',
    );
  }

  Future<bool> createThread({
    required String title,
    required String content,
  }) async {
    final current = document;
    if (current == null || isSubmitting) return false;
    return _submit(
      () => _repository.createThread(current, title: title, content: content),
      successMessage: '新帖子已发布',
      addResultToHistory: true,
    );
  }

  Future<bool> clearCache() async {
    if (isSubmitting) return false;
    isSubmitting = true;
    errorMessage = null;
    _clearStatus();
    notifyListeners();
    try {
      await _repository.clearCache();
      _showStatus('帖子缓存已清除');
      return true;
    } catch (error) {
      errorMessage = '清除缓存失败：$error';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  void showDemo() {
    _requestSerial++;
    document = ForumDocument(
      uri: Uri(scheme: 'local', host: 'aa-demo'),
      title: 'AA爱好者交流串（本地示例）',
      kind: ForumPageKind.thread,
      encoding: 'UTF-8',
      posts: const [
        ForumPost(
          number: '1',
          name: '名無しさん',
          date: '2026/08/17 12:00:00',
          id: 'DEMO001',
          body:
              '这里会保留原帖中的空格和换行。\n\n　 ∧＿∧\n　( ´･ω･)　AA 阅读器へようこそ\n　( つ旦O\n　と＿)＿)',
        ),
        ForumPost(
          number: '2',
          name: 'AA好き',
          date: '2026/08/17 12:03:14',
          body: '右上角的按钮可以切换“保持原始宽度”和“自动折行”。',
        ),
      ],
    );
    pendingUri = document!.uri;
    errorMessage = null;
    _clearStatus();
    phase = ViewerPhase.ready;
    notifyListeners();
  }

  Future<void> _load(
    Uri uri, {
    bool addToHistory = false,
    int? targetHistoryIndex,
  }) async {
    final serial = ++_requestSerial;
    var refreshThreadAfterLoad = false;
    pendingUri = uri;
    errorMessage = null;
    _clearStatus();
    phase = ViewerPhase.loading;
    notifyListeners();

    try {
      final loaded = await _repository.load(uri);
      if (serial != _requestSerial) return;
      document = loaded;
      pendingUri = loaded.uri;
      if (addToHistory) {
        if (_historyIndex < _history.length - 1) {
          _history.removeRange(_historyIndex + 1, _history.length);
        }
        _history.add(loaded.uri);
        _historyIndex = _history.length - 1;
      } else if (targetHistoryIndex != null) {
        _historyIndex = targetHistoryIndex;
        _history[_historyIndex] = loaded.uri;
      }
      phase = ViewerPhase.ready;
      refreshThreadAfterLoad = loaded.kind == ForumPageKind.thread;
    } catch (error) {
      if (serial != _requestSerial) return;
      errorMessage = error.toString();
      phase = ViewerPhase.error;
    }
    notifyListeners();
    if (refreshThreadAfterLoad && serial == _requestSerial) {
      await reload();
    }
  }

  Future<bool> _submit(
    Future<ForumDocument> Function() operation, {
    required String successMessage,
    bool addResultToHistory = false,
  }) async {
    isSubmitting = true;
    errorMessage = null;
    _clearStatus();
    notifyListeners();
    try {
      final result = await operation();
      document = result;
      pendingUri = result.uri;
      if (addResultToHistory) {
        if (_historyIndex < _history.length - 1) {
          _history.removeRange(_historyIndex + 1, _history.length);
        }
        _history.add(result.uri);
        _historyIndex = _history.length - 1;
      }
      phase = ViewerPhase.ready;
      _showStatus(successMessage);
      return true;
    } catch (error) {
      errorMessage = error.toString();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  void _showError(String message) {
    errorMessage = message;
    _clearStatus();
    phase = ViewerPhase.error;
    notifyListeners();
  }

  void _showStatus(String message) {
    _statusTimer?.cancel();
    statusMessage = message;
    _statusTimer = Timer(const Duration(seconds: 1), () {
      if (statusMessage != message) return;
      statusMessage = null;
      notifyListeners();
    });
  }

  void _clearStatus() {
    _statusTimer?.cancel();
    _statusTimer = null;
    statusMessage = null;
  }
}
