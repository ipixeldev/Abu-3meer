// Reusable button components with premium micro-interactions.

import 'package:flutter/material.dart';

import '../design/index.dart';

/// Primary CTA button — accentPrimary background, bold label.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final double? width;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.leadingIcon,
    this.trailingIcon,
    this.width,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 18, color: AppColors.textOnAccent),
          const SizedBox(width: AppSpacing.inlineGap),
        ],
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
            color: enabled
                ? AppColors.textOnAccent
                : AppColors.textOnAccent.withValues(alpha: 0.5),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.inlineGap),
          Icon(trailingIcon, size: 18, color: AppColors.textOnAccent),
        ],
        if (loading) ...[
          const SizedBox(width: AppSpacing.inlineGap),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.textOnAccent),
            ),
          ),
        ],
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : width,
      height: height,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: AppColors.textOnAccent,
          disabledBackgroundColor: AppColors.accentPrimary.withValues(
            alpha: 0.35,
          ),
          disabledForegroundColor: AppColors.textOnAccent.withValues(
            alpha: 0.5,
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Secondary button — outlined, transparent background.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final IconData? leadingIcon;
  final Color? borderColor;
  final Color? textColor;
  final double height;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.leadingIcon,
    this.borderColor,
    this.textColor,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final bc = borderColor ?? AppColors.divider;
    final tc = textColor ?? AppColors.textPrimary;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? tc : tc.withValues(alpha: 0.4),
          side: BorderSide(
            color: enabled ? bc : bc.withValues(alpha: 0.4),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.buttonHorizontal,
            vertical: AppSpacing.buttonVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: enabled ? tc : tc.withValues(alpha: 0.4),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    enabled ? tc : tc.withValues(alpha: 0.4),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leadingIcon != null) ...[
                    Icon(
                      leadingIcon,
                      size: 18,
                      color: enabled ? tc : tc.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: AppSpacing.inlineGap),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Ghost button — no border, text only, accentPrimary color.
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final IconData? leadingIcon;
  final Color? color;
  final double height;

  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fullWidth = false,
    this.leadingIcon,
    this.color,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = color ?? AppColors.accentPrimary;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: enabled ? c : c.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.buttonHorizontal,
            vertical: AppSpacing.buttonVertical,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: enabled ? c : c.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: 16,
                color: enabled ? c : c.withValues(alpha: 0.4),
              ),
              const SizedBox(width: AppSpacing.inlineGap),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Icon-only button (square, for toolbars, headers, etc.).
class IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final String? tooltip;
  final bool selected;

  const IconActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 40,
    this.tooltip,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final bg = selected
        ? (backgroundColor ?? AppColors.accentPrimary).withValues(alpha: 0.2)
        : (backgroundColor ?? AppColors.bgSurfaceElevated);
    final ic = selected
        ? (iconColor ?? AppColors.accentPrimary)
        : (iconColor ?? AppColors.textSecondary);

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected
                  ? (iconColor ?? AppColors.accentPrimary)
                  : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.5,
            color: enabled ? ic : ic.withValues(alpha: 0.4),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Toggle chip for filter tabs, team selection, etc.
class ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? selectedColor;
  final Color? unselectedColor;

  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final sc = selectedColor ?? AppColors.accentPrimary;
    final uc = unselectedColor ?? AppColors.textMuted;
    final bg = selected
        ? sc.withValues(alpha: 0.15)
        : AppColors.bgSurfaceElevated;
    final border = selected ? sc : AppColors.divider;
    final textColor = selected ? sc : uc;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: textColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented control (horizontal pill group).
class SegmentedControl<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<SegmentedOption<T>> options;
  final Color? activeColor;
  final Color? inactiveColor;

  const SegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.options,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final ac = activeColor ?? AppColors.accentPrimary;
    final ic = inactiveColor ?? AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isActive = opt.value == value;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(opt.value),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                  vertical: AppSpacing.space2,
                ),
                decoration: BoxDecoration(
                  color: isActive ? ac : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (opt.icon != null) ...[
                      Icon(
                        opt.icon,
                        size: 14,
                        color: isActive ? AppColors.textOnAccent : ic,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(
                      opt.label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: isActive ? AppColors.textOnAccent : ic,
                      ),
                    ),
                    if (opt.badge != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.textOnAccent.withValues(alpha: 0.2)
                              : AppColors.bgSurfaceElevated,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          opt.badge!,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: isActive ? AppColors.textOnAccent : ic,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentedOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? badge;

  const SegmentedOption({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
  });
}
