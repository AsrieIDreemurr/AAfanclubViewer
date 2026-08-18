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

/// Measures the rendered width of a run of text in the forum's own font.
typedef ComposerGlyphWidth = double Function(String text);

/// Flattens bottom-to-top text layers into the exact plain text sent to the
/// forum. Whitespace advances the cursor but never erases a lower layer.
///
/// [measureWidth] and [spaceWidth] make padding follow the real font: the
/// board renders in a proportional face, so a run of glyphs is not as wide as
/// the same number of spaces. Without them the function falls back to treating
/// every half-width cell as one space, which is only exact for a monospace
/// target. Glyphs placed before the origin are dropped, never shifted, so what
/// stays inside the frame keeps the columns the author gave it.
String composeTextLayers(
  Iterable<ComposerTextLayer> layers, {
  ComposerGlyphWidth? measureWidth,
  double spaceWidth = 1,
}) {
  final rows = <int, List<_PlacedGlyph>>{};
  final widthCache = <String, double>{};

  /// How far the caret moves past [glyph]. Saitamaar is proportional, so this
  /// is nothing like the East Asian cell count: `A` is two space-widths, `i`
  /// is a little over half of one, and the ideographic space is 2.2.
  double advanceOf(String glyph, int rune) {
    final measure = measureWidth;
    if (measure == null) {
      return math.max(1, _characterWidth(rune)) * spaceWidth;
    }
    return widthCache.putIfAbsent(glyph, () => measure(glyph));
  }

  for (final layer in layers) {
    var row = layer.row;
    final startX = layer.column * spaceWidth;
    var x = startX;
    _PlacedGlyph? previous;

    for (final rune in layer.text.runes) {
      if (rune == 0x0d) continue;
      if (rune == 0x0a) {
        row++;
        x = startX;
        previous = null;
        continue;
      }
      if (rune == 0x09) {
        final stop = spaceWidth * 4;
        x = ((x / stop).floor() + 1) * stop;
        previous = null;
        continue;
      }

      final glyph = String.fromCharCode(rune);
      if (_isTransparentWhitespace(rune)) {
        x += advanceOf(glyph, rune);
        previous = null;
        continue;
      }

      final cells = _characterWidth(rune);
      if (cells == 0 && previous != null) {
        previous.text += glyph;
        continue;
      }
      // A combining mark with nothing to attach to still needs to occupy a
      // cell of its own, the way the old cell engine promoted it to width 1.
      final advance = math.max(
        advanceOf(glyph, rune),
        cells == 0 ? spaceWidth : 0.0,
      );

      // Anything before the origin is dropped rather than shifted, so what
      // stays in frame keeps the position the author gave it.
      if (row < 0 || x < -0.01) {
        x += advance;
        previous = null;
        continue;
      }

      final placed = _PlacedGlyph(text: glyph, x: x, advance: advance);
      _placeGlyph(rows.putIfAbsent(row, () => <_PlacedGlyph>[]), placed);
      previous = placed;
      x += advance;
    }
  }

  final visibleRows = rows.entries.where((entry) => entry.value.isNotEmpty);
  if (visibleRows.isEmpty) return '';
  final lastRow = visibleRows.map((entry) => entry.key).reduce(math.max);

  final output = StringBuffer();
  for (var row = 0; row <= lastRow; row++) {
    if (row > 0) output.write('\n');
    final glyphs = rows[row];
    if (glyphs == null || glyphs.isEmpty) continue;
    final line = StringBuffer();
    var lineWidth = 0.0;
    for (final glyph in glyphs) {
      // Pad until the glyph lands on its own pixel column, rounding to the
      // nearest whole space since that is the only ruler plain text has.
      while (glyph.x - lineWidth >= spaceWidth / 2) {
        line.write(' ');
        lineWidth += spaceWidth;
      }
      line.write(glyph.text);
      lineWidth += glyph.advance;
    }
    output.write(line.toString().replaceFirst(RegExp(r' +$'), ''));
  }
  return output.toString().replaceFirst(RegExp(r'\n+$'), '');
}

/// Inserts [glyph] in x order, erasing whatever it lands on top of.
void _placeGlyph(List<_PlacedGlyph> row, _PlacedGlyph glyph) {
  const epsilon = 0.01;
  row.removeWhere(
    (existing) =>
        existing.x < glyph.end - epsilon && glyph.x < existing.end - epsilon,
  );
  final index = row.indexWhere((existing) => existing.x > glyph.x);
  if (index < 0) {
    row.add(glyph);
  } else {
    row.insert(index, glyph);
  }
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

  /// Cells of hatched gutter kept before the origin, so a window can be
  /// dragged past the start of the post while staying inside the canvas.
  static const _gutterColumns = 24;
  static const _gutterRows = 5;

  final _title = TextEditingController();
  final _previewController = TextEditingController();
  final List<_EditorLayer> _layers = [];
  int _nextLayerId = 0;
  String? _preview;
  bool _sending = false;
  bool _layerPanelOpen = false;
  bool _canvasParked = false;
  final TransformationController _canvasTransform = TransformationController();
  Size _canvasSize = const Size(320, 360);
  Size _viewportSize = const Size(320, 360);
  double _columnWidth = 5;
  double _rowHeight = 16;
  TextScaler _textScaler = TextScaler.noScaling;
  TextDirection _textDirection = TextDirection.ltr;

  @override
  void dispose() {
    _title.dispose();
    _previewController.dispose();
    for (final layer in _layers) {
      layer.dispose();
    }
    _canvasTransform.dispose();
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
                  _sending ? null : _cancelPreview,
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
    if (_preview != null) return _buildPreviewEditor();

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = constraints.biggest;
        _canvasSize = _calculateWorkspaceSize(_viewportSize);
        _parkCanvasOnOrigin();
        return ColoredBox(
          key: const Key('composer-canvas'),
          color: const Color(0xffefefef),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  key: const Key('composer-workspace-pan'),
                  transformationController: _canvasTransform,
                  constrained: false,
                  scaleEnabled: true,
                  panEnabled: true,
                  minScale: 0.35,
                  maxScale: 4,
                  alignment: Alignment.topLeft,
                  boundaryMargin: EdgeInsets.all(
                    math.max(_viewportSize.width, _viewportSize.height),
                  ),
                  child: SizedBox(
                    width: _canvasSize.width,
                    height: _canvasSize.height,
                    child: CustomPaint(
                      painter: _OutOfFramePainter(
                        originX: _originX,
                        originY: _originY,
                      ),
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
                      '拖动空白区域可移动画布，双指缩放\n'
                      '点击“嵌入文字”或“嵌入AA”添加窗口\n'
                      '灰色斜线区域在正文之外，那里的文字不会发出去',
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

  /// The confirmed post, editable as plain text. Edits made here are thrown
  /// away by 取消 — they never turn back into windows.
  Widget _buildPreviewEditor() {
    return Container(
      key: const Key('composer-preview'),
      alignment: Alignment.topLeft,
      color: const Color(0xffefefef),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // AA must not wrap, so the field is laid out at its widest line and
          // the surplus is reached by scrolling sideways.
          final longest = _preview!
              .split('\n')
              .map(_measureRun)
              .fold(0.0, math.max);
          final width = math.max(
            constraints.maxWidth,
            longest + _previewTextLeft + 24,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _previewTextLeft,
                  _previewTextTop - 1,
                  6,
                  5,
                ),
                child: TextField(
                  key: const Key('composer-preview-text'),
                  controller: _previewController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: AaText.baseStyle,
                  strutStyle: const StrutStyle(
                    fontFamily: 'Saitamaar',
                    fontSize: 16,
                    height: 1,
                    forceStrutHeight: false,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
          );
        },
      ),
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

  /// Opens the canvas looking at the first character of the post, so the
  /// hatched gutter sits off-screen until it is deliberately scrolled to.
  void _parkCanvasOnOrigin() {
    if (_canvasParked) return;
    _canvasParked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _canvasTransform.value =
          Matrix4.identity()..translate(-_originX, -_originY);
    });
  }

  Size _calculateWorkspaceSize(Size viewport) {
    var width = math.max(640.0, viewport.width * 2) + _originX;
    var height = math.max(720.0, viewport.height * 2) + _originY;
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
        _canvasXForColumn(1 + stagger * 4),
        _canvasYForRow(1 + stagger),
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

    // Columns and rows may go negative: that is the out-of-frame gutter, and
    // the canvas bounds are the only real limit.
    final minimumColumn =
        ((_editorTextLeft - _previewTextLeft - _originX) / _columnWidth).ceil();
    final maximumColumn =
        ((maxX + _editorTextLeft - _previewTextLeft - _originX) / _columnWidth)
            .floor();
    final requestedColumn = _columnForCanvasX(position.dx);

    final minimumRow = ((_verticalOriginDelta - _originY) / _rowHeight).ceil();
    final maximumRow =
        ((maxY + _verticalOriginDelta - _originY) / _rowHeight).floor();
    final requestedRow = _rowForCanvasY(position.dy);

    final column =
        maximumColumn >= minimumColumn
            ? requestedColumn.clamp(minimumColumn, maximumColumn)
            : minimumColumn;
    final row =
        maximumRow >= minimumRow
            ? requestedRow.clamp(minimumRow, maximumRow)
            : minimumRow;
    return Offset(
      _canvasXForColumn(column).clamp(0, maxX),
      _canvasYForRow(row).clamp(0, maxY),
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

  void _cancelPreview() {
    // Text typed straight into the preview is discarded rather than folded
    // back into a window, so the canvas is exactly as it was left.
    setState(() {
      _preview = null;
      _previewController.clear();
    });
  }

  void _showPreview() {
    final layers = _layers.map((layer) {
      return ComposerTextLayer(
        text: layer.controller.text,
        row: _rowForCanvasY(layer.position.dy),
        column: _columnForCanvasX(layer.position.dx),
      );
    });
    final result = composeTextLayers(
      layers,
      measureWidth: _measureRun,
      spaceWidth: _columnWidth,
    );
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
      _previewController.text = result;
      _layerPanelOpen = false;
    });
  }

  Future<void> _send() async {
    if (_preview == null || _sending) return;
    final content = _previewController.text;
    if (content.trim().isEmpty) {
      _showMessage('内容为空，无法发送');
      return;
    }
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

  /// Canvas offset of the post's first character. Everything left of or above
  /// it is out of frame and gets dropped when the layers are flattened.
  double get _originX => _columnWidth * _gutterColumns;
  double get _originY => _rowHeight * _gutterRows;

  double _canvasXForColumn(int column) =>
      _originX + column * _columnWidth - _editorTextLeft + _previewTextLeft;
  double _canvasYForRow(int row) =>
      _originY + row * _rowHeight - _verticalOriginDelta;
  int _columnForCanvasX(double x) =>
      ((x - _originX + _editorTextLeft - _previewTextLeft) / _columnWidth)
          .round();
  int _rowForCanvasY(double y) =>
      ((y - _originY + _verticalOriginDelta) / _rowHeight).round();

  /// Width of a run of text in the board's font, used so padding lands on the
  /// right pixel column instead of the right cell count.
  double _measureRun(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AaText.baseStyle),
      textDirection: _textDirection,
      textScaler: _textScaler,
    )..layout();
    return painter.width;
  }

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

/// Shades everything before the origin. Text dragged into the hatching is
/// outside the post: it is dropped when the layers are flattened, and the
/// glyphs still inside keep the columns they were given.
class _OutOfFramePainter extends CustomPainter {
  const _OutOfFramePainter({required this.originX, required this.originY});

  final double originX;
  final double originY;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffefefef),
    );
    if (originX <= 0 && originY <= 0) return;

    final outside =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, originX, size.height))
          ..addRect(Rect.fromLTWH(originX, 0, size.width - originX, originY));

    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x0f000000),
    );
    final stroke =
        Paint()
          ..color = const Color(0x38000000)
          ..strokeWidth = 1;
    const spacing = 9.0;
    for (var x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        stroke,
      );
    }
    canvas.restore();

    final rule =
        Paint()
          ..color = const Color(0x8c000000)
          ..strokeWidth = 1;
    canvas.drawLine(Offset(originX, 0), Offset(originX, size.height), rule);
    canvas.drawLine(Offset(0, originY), Offset(size.width, originY), rule);
  }

  @override
  bool shouldRepaint(covariant _OutOfFramePainter oldDelegate) =>
      oldDelegate.originX != originX || oldDelegate.originY != originY;
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
  _PlacedGlyph({required this.text, required this.x, required this.advance});

  String text;
  final double x;
  final double advance;

  double get end => x + advance;
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
