import 'package:flutter/material.dart';

import 'app_theme.dart';

class SmoothActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool isLoading;
  final double height;

  const SmoothActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.isLoading = false,
    this.height = 58,
  });

  @override
  State<SmoothActionButton> createState() => _SmoothActionButtonState();
}

class _SmoothActionButtonState extends State<SmoothActionButton> {
  bool isPressed = false;

  bool get isEnabled {
    return widget.onPressed != null && !widget.isLoading;
  }

  void setPressed(bool value) {
    if (!isEnabled) {
      return;
    }

    setState(() {
      isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = widget.outlined
        ? Colors.white
        : AppTheme.primaryColor;

    final Color textColor = widget.outlined
        ? AppTheme.primaryColor
        : Colors.white;

    final Color borderColor = widget.outlined
        ? AppTheme.primaryColor
        : AppTheme.primaryColor;

    final Color shadowColor = widget.outlined
        ? Colors.black12
        : AppTheme.primaryColor;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isEnabled ? 1 : 0.65,
      child: GestureDetector(
        onTapDown: (_) {
          setPressed(true);
        },
        onTapUp: (_) {
          setPressed(false);
        },
        onTapCancel: () {
          setPressed(false);
        },
        onTap: isEnabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            constraints: BoxConstraints(minHeight: widget.height),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.outlined ? borderColor : Colors.transparent,
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor.withValues(
                    alpha: widget.outlined ? 0.08 : 0.22,
                  ),
                  blurRadius: widget.outlined ? 12 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: widget.isLoading
                    ? SizedBox(
                        key: const ValueKey("loading"),
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: textColor,
                        ),
                      )
                    : Row(
                        key: const ValueKey("content"),
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, color: textColor, size: 23),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                height: 1.15,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
