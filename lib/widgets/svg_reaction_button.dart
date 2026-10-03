import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Reusable SVG icon + count button with ripple + tint.
///
/// Used for post reactions, comment reactions, and reply buttons.
class SvgReactionButton extends StatelessWidget {
  final String svgPath;
  final int count;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final Animation<double>? scale;
  final double iconSize;
  final double countFontSize;
  final bool showCount;
  final EdgeInsets padding;

  const SvgReactionButton({
    super.key,
    required this.svgPath,
    required this.count,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.scale,
    this.iconSize = 18,
    this.countFontSize = 12,
    this.showCount = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final tint = active ? activeColor : Colors.grey.shade600;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: SvgPicture.asset(
            svgPath,
            key: ValueKey('$svgPath-$active'),
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: countFontSize,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: tint,
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: activeColor.withOpacity(0.12),
        highlightColor: activeColor.withOpacity(0.06),
        child: Padding(
          padding: padding,
          child: scale != null
              ? ScaleTransition(scale: scale!, child: content)
              : content,
        ),
      ),
    );
  }
}
