import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// Reusable SVG icon button with tint + ripple.
class SvgIconButton extends StatelessWidget {
  final String svgPath;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? disabledColor;
  final EdgeInsets padding;
  final String? semanticLabel;

  const SvgIconButton({
    super.key,
    required this.svgPath,
    required this.onPressed,
    this.size = 22,
    this.color,
    this.disabledColor,
    this.padding = const EdgeInsets.all(8),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final tintColor = enabled
        ? (color ?? AppColors.red)
        : (disabledColor ?? Colors.grey.shade400);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        splashColor: tintColor.withOpacity(0.12),
        highlightColor: tintColor.withOpacity(0.06),
        child: Padding(
          padding: padding,
          child: SvgPicture.asset(
            svgPath,
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(tintColor, BlendMode.srcIn),
            semanticsLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}
