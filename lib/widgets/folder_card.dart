import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category_node.dart';
import '../services/settings_service.dart';
import '../theme/design_tokens.dart';
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
    final tokens = AppDesignTokens.of(context);
    if (widget.displayMode == GridDisplayMode.list) {
      return _buildListRow(c, cs, tokens);
    }
    final radius = BorderRadius.circular(tokens.cardRadius * c);
    final isSel = widget.isSelected;
    final isHov = _isHovered;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          widget.onRightClick(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.fast),
          curve: MotionCurves.standard,
          padding: EdgeInsets.symmetric(vertical: 8 * c, horizontal: 4 * c),
          decoration: BoxDecoration(
            color: isSel
                ? cs.primaryContainer.withValues(alpha: 0.4)
                : (isHov ? cs.primary.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: radius,
            border: Border.all(
              color: isSel
                  ? cs.primary
                  : (isHov ? cs.primary.withValues(alpha: 0.4) : Colors.transparent),
              width: isSel ? 2.0 * c : 1.0 * c,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder,
                size: 48 * c,
                color: isSel ? cs.primary : cs.tertiary.withValues(alpha: 0.85),
              ),
              SizedBox(height: 6 * c),
              Text(
                widget.node.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12 * c,
                  height: 1.2,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListRow(double c, ColorScheme cs, AppDesignTokens tokens) {
    final radius = BorderRadius.circular(tokens.buttonRadius * c);
    final isSel = widget.isSelected;
    final isHov = _isHovered;
    return GestureDetector(
      onSecondaryTapUp: (details) => widget.onRightClick(details.globalPosition),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: tokens.duration(MotionDurations.fast),
          curve: MotionCurves.standard,
          height: 46 * c,
          padding: EdgeInsets.symmetric(vertical: 5 * c, horizontal: 6 * c),
          decoration: BoxDecoration(
            color: isSel
                ? cs.primaryContainer.withValues(alpha: 0.35)
                : (isHov ? cs.primary.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: radius,
            border: Border.all(
              color: isSel
                  ? cs.primary
                  : (isHov ? cs.primary.withValues(alpha: 0.4) : Colors.transparent),
              width: isSel ? 1.5 * c : 1.0 * c,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 4 * c),
              Icon(
                Icons.folder,
                size: 30 * c,
                color: isSel ? cs.primary : cs.tertiary.withValues(alpha: 0.85),
              ),
              SizedBox(width: 10 * c),
              Expanded(
                child: Text(
                  widget.node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5 * c,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
