import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'aa_picker_page.dart';
import 'aa_text.dart';

enum ComposerMode { reply, newThread }

typedef ComposerSubmitCallback =
    Future<bool> Function(String? title, String content);

class ComposerTextLayer {
  const ComposerTextLayer({
    required this.text,
    required this.row,
    required this.column,
  });

  final String text;
  final int row;
  final int column;
}

/// Flattens bottom-to-top text layers into the exact plain text sent to the
/// forum. Whitespace advances the cursor but never erases a lower layer.
String composeTextLayers(Iterable<ComposerTextLayer> layers) {
  final rows = <int, Map<int, _PlacedGlyph>>{};

  for (final layer in layers) {
    var row = math.max(0, layer.row);
    final startColumn = math.max(0, layer.column);
    var column = startColumn;

    for (final rune in layer.text.runes) {
      if (rune == 0x0d) continue;
      if (rune == 0x0a) {
        row++;
        column = startColumn;
        continue;
      }
      if (rune == 0x09) {
        column = ((column ~/ 4) + 1) * 4;
        continue;
      }

      var width = _characterWidth(rune);
      if (_isTransparentWhitespace(rune)) {
        column += math.max(1, width);
        continue;
      }

      final rowCells = rows.putIfAbsent(row, () => <int, _PlacedGlyph>{});
      final glyph = String.fromCharCode(rune);
      if (width == 0) {
        final previous = rowCells[column - 1];
        if (previous != null) {
          previous.text += glyph;
          continue;
        }
        width = 1;
      }

      final replaced = <_PlacedGlyph>{};
      for (var cell = column; cell < column + width; cell++) {
        final existing = rowCells[cell];
        if (existing != null) replaced.add(existing);
      }
      for (final existing in replaced) {
        rowCells.removeWhere((_, value) => identical(value, existing));
      }

      final placed = _PlacedGlyph(text: glyph, column: column, width: width);
      for (var cell = column; cell < column + width; cell++) {
        rowCells[cell] = placed;
      }
      column += width;
    }
  }

  final visibleRows = rows.entries.where((entry) => entry.value.isNotEmpty);
  if (visibleRows.isEmpty) return '';
  final lastRow = visibleRows.map((entry) => entry.key).reduce(math.max);
  final output = StringBuffer();
  for (var row = 0; row <= lastRow; row++) {
    if (row > 0) output.write('\n');
    final cells = rows[row];
    if (cells == null || cells.isEmpty) continue;
    final lastColumn = cells.keys.reduce(math.max);
    final line = StringBuffer();
    var column = 0;
    while (column <= lastColumn) {
      final placed = cells[column];
      if (placed == null) {
        line.write(' ');
        column++;
      } else if (placed.column == column) {
        line.write(placed.text);
        column += placed.width;
      } else {
        column++;
      }
    }
    output.write(line.toString().replaceFirst(RegExp(r' +$'), ''));
  }
  return output.toString().replaceFirst(RegExp(r'\n+$'), '');
}

class PostComposerSheet extends StatefulWidget {
  const PostComposerSheet({
    required this.mode,
    required this.onSubmit,
    this.loginName,
    super.key,
  });

  final ComposerMode mode;
  final String? loginName;
  final ComposerSubmitCallback onSubmit;

  @override
  State<PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<PostComposerSheet> {
  static const _headerHeight = 25.0;
  static const _editorTextLeft = 6.0;
  static const _editorTextTop = 5.0;
  static const _previewTextLeft = 6.0;
  static const _previewTextTop = 6.0;

  final _title = TextEditingController();
  final List<_EditorLayer> _layers = [];
  int _nextLayerId = 0;
  String? _preview;
  bool _sending = false;
  bool _layerPanelOpen = false;
  Size _canvasSize = const Size(320, 360);
  Size _viewportSize = const Size(320, 360);
  double _columnWidth = 5;
  double _rowHeight = 16;
  TextScaler _textScaler = TextScaler.noScaling;
  TextDirection _textDirection = TextDirection.ltr;

  @override
  void dispose() {
    _title.dispose();
    for (final layer in _layers) {
      layer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _updateTextMetrics(context);
    final availableHeight = math.max(
      300.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom,
    );
    final sheetHeight = math.min(availableHeight, media.size.height * 0.78);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        key: const Key('post-composer-sheet'),
        width: double.infinity,
        height: sheetHeight,
        child: Material(
          color: const Color(0xfff6f4ed),
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff777777)),
              ),
              child: Column(
                children: [
                  _buildTopBar(),
                  const Divider(height: 1, color: Colors.black),
                  Expanded(child: _buildCanvas()),
                  if (_preview == null) ...[
                    const Divider(height: 1, color: Colors.black),
                    _buildBottomBar(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '登录：${widget.loginName ?? '未登录'}',
                  key: const Key('composer-login-info'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Saitamaar',
                    fontSize: 15,
                    height: 1,
                  ),
                ),
                if (widget.mode == ComposerMode.newThread) ...[
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 31,
                    child: TextField(
                      key: const Key('composer-thread-title'),
                      controller: _title,
                      decoration: const InputDecoration(
                        hintText: '帖子标题（至少 2 字符）',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 7,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black),
                          borderRadius: BorderRadius.zero,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xff0000ee)),
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      style: const TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 14,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 7),
          if (_preview != null) ...[
            _ComposerButton(
              key: const Key('composer-cancel-preview'),
              label: '取消',
              onPressed:
                  _sending ? null : () => setState(() => _preview = null),
            ),
            const SizedBox(width: 5),
          ],
          _ComposerButton(
            key: const Key('composer-primary-action'),
            label:
                _preview == null
                    ? '确认'
                    : _sending
                    ? '发送中…'
                    : '发送',
            onPressed: _sending ? null : _handlePrimaryAction,
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    if (_preview != null) {
      return Container(
        key: const Key('composer-preview'),
        alignment: Alignment.topLeft,
        color: const Color(0xffefefef),
        padding: const EdgeInsets.fromLTRB(
          _previewTextLeft,
          _previewTextTop - 1,
          6,
          5,
        ),
        child: SingleChildScrollView(
          child: AaText(_preview!, key: const Key('composer-preview-text')),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        _canvasSize = _calculateWorkspaceSize(_viewportSize);
        return ColoredBox(
          key: const Key('composer-canvas'),
          color: const Color(0xffefefef),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  key: const Key('composer-workspace-pan'),
                  constrained: false,
                  scaleEnabled: false,
                  panEnabled: true,
                  minScale: 1,
                  maxScale: 1,
                  alignment: Alignment.topLeft,
                  boundaryMargin: EdgeInsets.all(
                    math.max(_viewportSize.width, _viewportSize.height),
                  ),
                  child: SizedBox(
                    width: _canvasSize.width,
                    height: _canvasSize.height,
                    child: ColoredBox(
                      color: const Color(0xffefefef),
                      child: Stack(
                        children: [
                          for (final layer in _layers) _buildLayerWindow(layer),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_layers.isEmpty)
                const IgnorePointer(
                  child: Center(
                    child: Text(
                      '拖动空白区域可移动画布\n点击“嵌入文字”或“嵌入AA”添加窗口',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Saitamaar',
                        fontSize: 14,
                        color: Color(0xff666666),
                      ),
                    ),
                  ),
                ),
              if (_layerPanelOpen) _buildLayerPanel(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayerWindow(_EditorLayer layer) {
    final size = _layerSize(layer);
    return Positioned(
      key: ValueKey('composer-layer-${layer.id}'),
      left: layer.position.dx,
      top: layer.position.dy,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => setState(() => _layerPanelOpen = true),
        child: Material(
          color: const Color(0x33ffffff),
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: 1.5),
          ),
          child: Column(
            children: [
              GestureDetector(
                key: ValueKey('composer-layer-drag-${layer.id}'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => layer.dragPosition = layer.position,
                onPanUpdate: (details) => _moveLayer(layer, details.delta),
                onPanEnd: (_) => _snapLayer(layer),
                child: Container(
                  height: _headerHeight,
                  padding: const EdgeInsets.only(left: 6),
                  decoration: const BoxDecoration(
                    color: Color(0x33e5e5e5),
                    border: Border(bottom: BorderSide(color: Colors.black)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '文字 ${_layers.indexOf(layer) + 1}',
                          style: const TextStyle(
                            fontFamily: 'Saitamaar',
                            fontSize: 13,
                            height: 1,
                          ),
                        ),
                      ),
                      InkWell(
                        key: ValueKey('composer-layer-delete-${layer.id}'),
                        onTap: () => _removeLayer(layer),
                        child: const SizedBox(
                          width: 28,
                          height: _headerHeight,
                          child: Icon(Icons.close, size: 17),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _editorTextLeft,
                  ),
                  child: TextField(
                    key: ValueKey('composer-layer-input-${layer.id}'),
                    controller: layer.controller,
                    focusNode: layer.focusNode,
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.only(top: _editorTextTop),
                    ),
                    style: AaText.baseStyle,
                    strutStyle: const StrutStyle(
                      fontFamily: 'Saitamaar',
                      fontSize: 16,
                      height: 1,
                      forceStrutHeight: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerPanel() {
    final width = math.min(220.0, _viewportSize.width * 0.6);
    return Positioned(
      key: const Key('composer-layer-panel'),
      top: 0,
      right: 0,
      bottom: 0,
      width: width,
      child: Material(
        color: const Color(0xfff6f4ed),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.black, width: 1.5),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        '窗口图层（上方优先）',
                        style: TextStyle(
                          fontFamily: 'Saitamaar',
                          fontSize: 13,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('close-layer-panel'),
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    onPressed: () => setState(() => _layerPanelOpen = false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.black),
            Expanded(
              child: ListView.builder(
                itemCount: _layers.length,
                itemBuilder: (context, displayIndex) {
                  final index = _layers.length - 1 - displayIndex;
                  final layer = _layers[index];
                  final preview = layer.controller.text.replaceAll('\n', ' ');
                  return Container(
                    key: ValueKey('composer-layer-row-${layer.id}'),
                    padding: const EdgeInsets.fromLTRB(7, 4, 3, 4),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xffaaaaaa)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview.isEmpty ? '文字 ${index + 1}' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Saitamaar',
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('composer-layer-up-${layer.id}'),
                          tooltip: '上移图层',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          onPressed:
                              index < _layers.length - 1
                                  ? () => _reorderLayer(index, index + 1)
                                  : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          key: ValueKey('composer-layer-down-${layer.id}'),
                          tooltip: '下移图层',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          onPressed:
                              index > 0
                                  ? () => _reorderLayer(index, index - 1)
                                  : null,
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SizedBox(
      height: 47,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _ComposerButton(
            key: const Key('embed-aa'),
            label: '嵌入AA',
            onPressed: _pickAa,
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _ComposerButton(
              key: const Key('embed-text'),
              label: '嵌入文字',
              onPressed: _addTextLayer,
            ),
          ),
        ],
      ),
    );
  }

  Size _layerSize(_EditorLayer layer) {
    final painter = TextPainter(
      text: TextSpan(
        text: layer.controller.text.isEmpty ? ' ' : layer.controller.text,
        style: AaText.baseStyle,
      ),
      textDirection: _textDirection,
      textScaler: _textScaler,
    )..layout();
    return Size(
      math.max(140, painter.width + _editorTextLeft * 2 + 4),
      math.max(82, _headerHeight + _editorTextTop + painter.height + 6),
    );
  }

  Size _calculateWorkspaceSize(Size viewport) {
    var width = math.max(640.0, viewport.width * 2);
    var height = math.max(720.0, viewport.height * 2);
    for (final layer in _layers) {
      final size = _layerSize(layer);
      width = math.max(width, layer.position.dx + size.width + viewport.width);
      height = math.max(
        height,
        layer.position.dy + size.height + viewport.height,
      );
    }
    return Size(width, height);
  }

  void _addTextLayer({String initialText = '', bool requestFocus = true}) {
    final id = _nextLayerId++;
    final stagger = _layers.length % 5;
    final layer = _EditorLayer(
      id: id,
      position: Offset(
        _columnWidth * (3 + stagger * 4),
        _rowHeight * (2 + stagger) - _verticalOriginDelta,
      ),
      text: initialText,
    );
    layer.controller.addListener(_onLayerTextChanged);
    setState(() => _layers.add(layer));
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) layer.focusNode.requestFocus();
      });
    }
  }

  void _onLayerTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickAa() async {
    FocusScope.of(context).unfocus();
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const AaPickerPage()),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    _addTextLayer(initialText: text, requestFocus: false);
  }

  void _removeLayer(_EditorLayer layer) {
    setState(() => _layers.remove(layer));
    layer
      ..controller.removeListener(_onLayerTextChanged)
      ..dispose();
    if (_layers.isEmpty) _layerPanelOpen = false;
  }

  void _moveLayer(_EditorLayer layer, Offset delta) {
    setState(() {
      final raw = (layer.dragPosition ?? layer.position) + delta;
      layer.dragPosition = _clampPosition(layer, raw);
      layer.position = _snapAndClampPosition(layer, layer.dragPosition!);
    });
  }

  void _snapLayer(_EditorLayer layer) {
    setState(() {
      layer.position = _snapAndClampPosition(
        layer,
        layer.dragPosition ?? layer.position,
      );
      layer.dragPosition = null;
    });
  }

  Offset _snapAndClampPosition(_EditorLayer layer, Offset position) {
    final size = _layerSize(layer);
    final maxX = math.max(0.0, _canvasSize.width - size.width);
    final maxY = math.max(0.0, _canvasSize.height - size.height);

    final minimumColumn =
        ((_editorTextLeft - _previewTextLeft) / _columnWidth).ceil();
    final maximumColumn =
        ((maxX + _editorTextLeft - _previewTextLeft) / _columnWidth).floor();
    final requestedColumn =
        ((position.dx + _editorTextLeft - _previewTextLeft) / _columnWidth)
            .round();

    final minimumRow = (_verticalOriginDelta / _rowHeight).ceil();
    final maximumRow = ((maxY + _verticalOriginDelta) / _rowHeight).floor();
    final requestedRow =
        ((position.dy + _verticalOriginDelta) / _rowHeight).round();

    final column =
        maximumColumn >= minimumColumn
            ? requestedColumn.clamp(minimumColumn, maximumColumn)
            : minimumColumn;
    final row =
        maximumRow >= minimumRow
            ? requestedRow.clamp(minimumRow, maximumRow)
            : minimumRow;
    return Offset(
      (column * _columnWidth - _editorTextLeft + _previewTextLeft).clamp(
        0,
        maxX,
      ),
      (row * _rowHeight - _verticalOriginDelta).clamp(0, maxY),
    );
  }

  Offset _clampPosition(_EditorLayer layer, Offset position) {
    final size = _layerSize(layer);
    return Offset(
      position.dx.clamp(0, math.max(0, _canvasSize.width - size.width)),
      position.dy.clamp(0, math.max(0, _canvasSize.height - size.height)),
    );
  }

  void _reorderLayer(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    setState(() {
      final layer = _layers.removeAt(from);
      _layers.insert(to, layer);
    });
  }

  void _handlePrimaryAction() {
    if (_preview == null) {
      _showPreview();
    } else {
      _send();
    }
  }

  void _showPreview() {
    final layers = _layers.map((layer) {
      return ComposerTextLayer(
        text: layer.controller.text,
        row: ((layer.position.dy + _verticalOriginDelta) / _rowHeight).round(),
        column:
            ((layer.position.dx + _editorTextLeft - _previewTextLeft) /
                    _columnWidth)
                .round(),
      );
    });
    final result = composeTextLayers(layers);
    if (result.trim().isEmpty) {
      _showMessage('请先嵌入文字内容');
      return;
    }
    if (widget.mode == ComposerMode.newThread &&
        _title.text.trim().length < 2) {
      _showMessage('帖子标题至少需要 2 个字符');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _preview = result;
      _layerPanelOpen = false;
    });
  }

  Future<void> _send() async {
    final content = _preview;
    if (content == null || _sending) return;
    setState(() => _sending = true);
    final success = await widget.onSubmit(
      widget.mode == ComposerMode.newThread ? _title.text.trim() : null,
      content,
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double get _verticalOriginDelta =>
      _headerHeight + _editorTextTop - _previewTextTop;

  void _updateTextMetrics(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    _textScaler = scaler;
    _textDirection = Directionality.of(context);
    final painter = TextPainter(
      text: const TextSpan(text: ' 0\n0', style: AaText.baseStyle),
      textDirection: _textDirection,
      textScaler: scaler,
    )..layout();
    final caret = Rect.fromLTWH(0, 0, 1, painter.height);
    final first = painter.getOffsetForCaret(
      const TextPosition(offset: 0),
      caret,
    );
    final second = painter.getOffsetForCaret(
      const TextPosition(offset: 1),
      caret,
    );
    final lines = painter.computeLineMetrics();
    final measuredColumn = (second.dx - first.dx).abs();
    final measuredRow =
        lines.length > 1
            ? (lines[1].baseline - lines[0].baseline).abs()
            : scaler.scale(16);
    if (measuredColumn > 0.1) _columnWidth = measuredColumn;
    if (measuredRow > 0.1) _rowHeight = measuredRow;
  }
}

class _EditorLayer {
  _EditorLayer({required this.id, required this.position, String text = ''})
    : controller = TextEditingController(text: text);

  final int id;
  final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  Offset position;
  Offset? dragPosition;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _PlacedGlyph {
  _PlacedGlyph({required this.text, required this.column, required this.width});

  String text;
  final int column;
  final int width;
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
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
        disabledForegroundColor: const Color(0xff888888),
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: const BorderSide(color: Colors.black),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontFamily: 'Saitamaar',
          fontSize: 14,
          height: 1,
        ),
      ),
      child: Text(label),
    );
  }
}

bool _isTransparentWhitespace(int rune) {
  return rune == 0x20 ||
      (rune >= 0x09 && rune <= 0x0d) ||
      rune == 0x85 ||
      rune == 0xa0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200b) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f ||
      rune == 0x2060 ||
      rune == 0x3000 ||
      rune == 0xfeff;
}

int _characterWidth(int rune) {
  if ((rune >= 0x0300 && rune <= 0x036f) ||
      (rune >= 0x1ab0 && rune <= 0x1aff) ||
      (rune >= 0x1dc0 && rune <= 0x1dff) ||
      (rune >= 0x20d0 && rune <= 0x20ff) ||
      (rune >= 0xfe00 && rune <= 0xfe0f) ||
      (rune >= 0xfe20 && rune <= 0xfe2f) ||
      (rune >= 0xe0100 && rune <= 0xe01ef) ||
      rune == 0x200c ||
      rune == 0x200d ||
      rune == 0xfeff) {
    return 0;
  }
  if (rune == 0x3000 ||
      (rune >= 0x1100 && rune <= 0x115f) ||
      (rune >= 0x2329 && rune <= 0x232a) ||
      (rune >= 0x2e80 && rune <= 0xa4cf && rune != 0x303f) ||
      (rune >= 0xac00 && rune <= 0xd7a3) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0xfe10 && rune <= 0xfe19) ||
      (rune >= 0xfe30 && rune <= 0xfe6f) ||
      (rune >= 0xff00 && rune <= 0xff60) ||
      (rune >= 0xffe0 && rune <= 0xffe6) ||
      (rune >= 0x1f300 && rune <= 0x1faff) ||
      (rune >= 0x20000 && rune <= 0x3fffd)) {
    return 2;
  }
  return 1;
}
