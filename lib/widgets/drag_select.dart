import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 按住滑动快捷切换选中的单项包裹。
///
/// [active] 为全局拖选会话（任意位置按下即激活，抬起/取消结束，
/// 由外层统一维护）；[onSelect] 为本项的选中回调。
/// 行为：按下本项瞬间立即选中；会话激活期间指针划入本项也实时选中。
/// 按住 Ctrl/Shift/Alt/Meta 等修饰键时不触发拖选（[onSelect] 不调用），
/// 由卡片自身修饰键逻辑（Ctrl 多选 / Shift 区间等）在抬起时处理。
/// [active] 或 [onSelect] 为空时不启用拖选（原样返回 [child]）。
class DragSelectItem extends StatelessWidget {
  final ValueListenable<bool>? active;
  final VoidCallback? onSelect;
  final Widget child;

  const DragSelectItem({
    super.key,
    this.active,
    this.onSelect,
    required this.child,
  });

  /// 是否按住 Ctrl/Shift/Alt/Meta 修饰键。
  static bool get _hasModifier => HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  @override
  Widget build(BuildContext context) {
    final active = this.active;
    final onSelect = this.onSelect;
    if (active == null || onSelect == null) return child;
    return Listener(
      // 仅左键按下立即选中；右键（上下文菜单）不触发。
      onPointerDown: (event) {
        if (event.buttons & kPrimaryButton != 0 && !_hasModifier) {
          onSelect();
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          if (active.value && !_hasModifier) onSelect();
        },
        child: child,
      ),
    );
  }
}
