import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category_node.dart';
import '../services/settings_service.dart';
import 'compact_level.dart';

/// 文件夹卡片，模仿 Windows 资源管理器大图标风格。
/// 单击：选中文件夹（右侧显示其 info）；双击：进入文件夹。
///
/// 用手动双击检测替代 InkWell.onDoubleTap，避免 Flutter 为区分单击/双击
/// 等待 ~300ms 超时导致的"点击卡顿"。单击立即响应，300ms 内第二次点击触发双击。
class FolderCard extends StatefulWidget {
  final CategoryNode node;
  final double displayWidth;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onShiftTap;
  final void Function(Offset globalPosition) onRightClick;
  final GridDisplayMode displayMode;

  const FolderCard({
    super.key,
    required this.node,
    required this.displayWidth,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onCtrlTap,
    required this.onShiftTap,
    required this.onRightClick,
    this.displayMode = GridDisplayMode.loose,
  });

  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  DateTime? _lastTapTime;
  bool _isHovered = false;

  void _handleTap() {
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (isCtrl) {
      widget.onCtrlTap();
      return;
    }
    if (isShift) {
      widget.onShiftTap();
      return;
    }

    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _lastTapTime = null;
      widget.onDoubleTap();
    } else {
      _lastTapTime = now;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CompactLevel.of(context);
    final cs = Theme.of(context).colorScheme;
    if (widget.displayMode == GridDisplayMode.list) {
      return _buildListRow(c, cs);
    }
    final selectedColor = cs.brightness == Brightness.light
        ? const Color(0xFF7B49E0)
        : cs.primary;
    final hoverColor = cs.brightness == Brightness.light
        ? const Color(0xFFB89AFF)
        : const Color(0xFF7E8FA3);
    final borderColor = widget.isSelected
        ? selectedColor
        : (_isHovered ? hoverColor : Colors.transparent);
    final borderWidth = widget.isSelected ? 1.5 : (_isHovered ? 1.0 : 1.5);
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          widget.onRightClick(details.globalPosition),
      child: InkWell(
        onTap: _handleTap,
        onHover: (v) => setState(() => _isHovered = v),
        borderRadius: BorderRadius.circular(4 * c),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6 * c, horizontal: 4 * c),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? cs.primaryContainer.withValues(alpha: 0.4)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4 * c),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder, size: 48 * c, color: Colors.amber.shade400),
              SizedBox(height: 4 * c),
              Text(
                widget.node.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11 * c,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListRow(double c, ColorScheme cs) {
    final selectedColor = cs.brightness == Brightness.light
        ? const Color(0xFF7B49E0)
        : cs.primary;
    final hoverColor = cs.brightness == Brightness.light
        ? const Color(0xFFB89AFF)
        : const Color(0xFF7E8FA3);
    final borderColor = widget.isSelected
        ? selectedColor
        : (_isHovered ? hoverColor : cs.outlineVariant);
    return GestureDetector(
      onSecondaryTapUp: (details) => widget.onRightClick(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(4 * c),
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Container(
            height: 44 * c,
            padding: EdgeInsets.symmetric(vertical: 4 * c, horizontal: 4 * c),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? cs.primaryContainer.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4 * c),
              border: Border.all(
                color: borderColor,
                width: widget.isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 4 * c),
                Icon(Icons.folder, size: 32 * c, color: Colors.amber.shade400),
                SizedBox(width: 8 * c),
                Expanded(
                  child: Text(
                    widget.node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12 * c,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
