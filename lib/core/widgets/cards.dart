// Reusable card components and containers.

import 'package:flutter/material.dart';

import '../design/index.dart';

/// Base surface card — elevated dark surface with subtle border.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final List<BoxShadow>? shadows;
  final BorderRadius? borderRadius;
  final Border? border;
  final VoidCallback? onTap;
  final bool interactive;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.shadows,
    this.borderRadius,
    this.border,
    this.onTap,
    this.interactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: color ?? AppColors.bgSurface,
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppSpacing.radiusLg),
        border: border ?? Border.all(color: AppColors.divider),
        boxShadow: shadows ?? AppSpacing.shadowSm,
      ),
      child: child,
    );

    if (onTap != null && interactive) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              borderRadius ?? BorderRadius.circular(AppSpacing.radiusLg),
          child: card,
        ),
      );
    }
    return card;
  }
}

/// Card with a subtle gradient background (used sparingly for hero sections).
class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final LinearGradient? gradient;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const GradientCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.gradient,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.gradientSurface,
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
        boxShadow: AppSpacing.shadowSm,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              borderRadius ?? BorderRadius.circular(AppSpacing.radiusLg),
          child: card,
        ),
      );
    }
    return card;
  }
}

/// Team-themed card (Barcelona or Real Madrid) — used for fan war, team selection.
class TeamCard extends StatelessWidget {
  final bool isBarcelona;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool selected;
  final VoidCallback? onTap;

  const TeamCard({
    super.key,
    required this.isBarcelona,
    required this.child,
    this.padding,
    this.margin,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = isBarcelona ? AppColors.barcaBlue : AppColors.madridGold;
    final secondary = isBarcelona ? AppColors.barcaRed : AppColors.madridNavy;
    final gradient = isBarcelona
        ? AppColors.gradientBarca
        : AppColors.gradientMadrid;

    final card = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPaddingLg),
      decoration: BoxDecoration(
        gradient: selected ? gradient : null,
        color: selected ? null : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(
          color: selected ? primary : AppColors.divider,
          width: selected ? 2.5 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : AppSpacing.shadowSm,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          child: card,
        ),
      );
    }
    return card;
  }
}

/// Match card — used in home, match center, predictions.
class MatchCard extends StatelessWidget {
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final DateTime kickoff;
  final String? stadium;
  final bool isLive;
  final bool predictionsOpen;
  final int? homeScore;
  final int? awayScore;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  const MatchCard({
    super.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.kickoff,
    this.stadium,
    this.isLive = false,
    this.predictionsOpen = false,
    this.homeScore,
    this.awayScore,
    this.onTap,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isPast = now.isAfter(kickoff);
    final timeDiff = kickoff.difference(now);
    final hoursLeft = timeDiff.inHours;
    final minsLeft = timeDiff.inMinutes.remainder(60);

    return SurfaceCard(
      padding: EdgeInsets.all(
        compact ? AppSpacing.cardPaddingSm : AppSpacing.cardPadding,
      ),
      onTap: onTap,
      interactive: onTap != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Competition + status row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  competition,
                  style: AppTextStyles.labelSmall(
                    color: AppColors.accentPrimary,
                  ),
                ),
              ),
              const Spacer(),
              if (isLive)
                _LiveBadge()
              else if (!isPast && predictionsOpen)
                _CountdownBadge(hours: hoursLeft, minutes: minsLeft)
              else if (!isPast)
                _UpcomingBadge(dateTime: kickoff)
              else
                _FinishedBadge(),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Teams row
          Row(
            children: [
              // Home team
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      homeTeam,
                      style: AppTextStyles.headlineMedium(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (homeScore != null)
                      Text(
                        '$homeScore',
                        style: AppTextStyles.numberDisplay(
                          size: 48,
                          color: AppColors.accentPrimary,
                        ),
                      ),
                  ],
                ),
              ),

              // VS / Score separator
              const SizedBox(width: AppSpacing.md),
              Column(
                children: [
                  if (!compact)
                    Text(
                      isPast ? 'FT' : 'vs',
                      style: AppTextStyles.labelMedium(
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (homeScore != null && awayScore != null)
                    Text(
                      '$homeScore  –  $awayScore',
                      style: AppTextStyles.numberMedium(
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),

              // Away team
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      awayTeam,
                      style: AppTextStyles.headlineMedium(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                    if (awayScore != null)
                      Text(
                        '$awayScore',
                        style: AppTextStyles.numberDisplay(
                          size: 48,
                          color: AppColors.accentPrimary,
                        ),
                        textAlign: TextAlign.end,
                      ),
                  ],
                ),
              ),
            ],
          ),

          if (!compact && stadium != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(stadium!, style: AppTextStyles.bodySmall()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text('LIVE', style: AppTextStyles.labelSmall(color: AppColors.error)),
        ],
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  final int hours;
  final int minutes;

  const _CountdownBadge({required this.hours, required this.minutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentPrimary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 12, color: AppColors.accentPrimary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
            style: AppTextStyles.labelSmall(color: AppColors.accentPrimary),
          ),
        ],
      ),
    );
  }
}

class _UpcomingBadge extends StatelessWidget {
  final DateTime dateTime;

  const _UpcomingBadge({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, size: 12, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(_formatDate(dateTime), style: AppTextStyles.labelSmall()),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _FinishedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text('FINISHED', style: AppTextStyles.labelSmall()),
    );
  }
}

/// Stat card — icon + large number + label (used in hub, profile, admin).
class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? valueColor;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.valueColor,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.all(
        compact ? AppSpacing.cardPaddingSm : AppSpacing.cardPadding,
      ),
      onTap: onTap,
      interactive: onTap != null,
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: compact ? 40 : 48,
              height: compact ? 40 : 48,
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.accentPrimary).withValues(
                  alpha: 0.15,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                icon,
                size: compact ? 20 : 24,
                color: iconColor ?? AppColors.accentPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: icon != null
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: compact
                      ? AppTextStyles.numberMedium(
                          color: valueColor ?? AppColors.textPrimary,
                          size: 24,
                        )
                      : AppTextStyles.numberLarge(
                          color: valueColor ?? AppColors.textPrimary,
                        ),
                  textAlign: icon != null ? TextAlign.start : TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: compact
                      ? AppTextStyles.labelSmall()
                      : AppTextStyles.bodySmall(),
                  textAlign: icon != null ? TextAlign.start : TextAlign.center,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Info card — title, subtitle, optional action (used in lists, settings).
class InfoCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool divider;

  const InfoCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.divider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: AppColors.divider))
                : null,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium(color: titleColor),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.bodySmall()),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state illustration + message + optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(
                icon,
                size: iconSize * 0.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTextStyles.headlineSmall(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTextStyles.bodyMedium(),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading shimmer placeholder (skeleton).
class ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius:
                widget.borderRadius ??
                BorderRadius.circular(AppSpacing.radiusMd),
            gradient: LinearGradient(
              colors: [
                AppColors.bgSurfaceElevated,
                AppColors.bgSurfaceElevated.withValues(alpha: 0.6),
                AppColors.bgSurfaceElevated,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_controller.value * 2 * 3.14159),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton loader for a card-like structure.
class CardSkeleton extends StatelessWidget {
  final bool compact;

  const CardSkeleton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.all(
        compact ? AppSpacing.cardPaddingSm : AppSpacing.cardPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerPlaceholder(
                width: 100,
                height: 16,
                borderRadius: BorderRadius.circular(4),
              ),
              const Spacer(),
              ShimmerPlaceholder(
                width: 60,
                height: 20,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ShimmerPlaceholder(
            width: 80,
            height: 32,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              ShimmerPlaceholder(
                width: 60,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: AppSpacing.md),
              ShimmerPlaceholder(
                width: 60,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
