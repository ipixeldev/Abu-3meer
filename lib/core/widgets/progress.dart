// Progress indicators, rings, bars, XP animations.

import 'package:flutter/material.dart';

import 'dart:math' as math;

import '../design/index.dart';

/// Circular progress ring with animated sweep.
/// Used for XP to next level, match countdown rings, streak circles.
class ProgressRing extends StatefulWidget {
  final double progress; // 0.0 – 1.0
  final double size;
  final double strokeWidth;
  final Color? progressColor;
  final Color? trackColor;
  final Widget? centerChild;
  final bool animate;
  final Duration animationDuration;
  final bool showPercentage;

  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 6,
    this.progressColor,
    this.trackColor,
    this.centerChild,
    this.animate = true,
    this.animationDuration = const Duration(milliseconds: 800),
    this.showPercentage = false,
  });

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  double _prevProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
    _prevProgress = widget.progress;
  }

  @override
  void didUpdateWidget(covariant ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _prevProgress = _animation.value;
      _animation = Tween<double>(begin: _prevProgress, end: widget.progress)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      if (widget.animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.progressColor ?? AppColors.accentPrimary;
    final tc = widget.trackColor ?? AppColors.divider;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _RingPainter(
              progress: _animation.value,
              strokeWidth: widget.strokeWidth,
              progressColor: pc,
              trackColor: tc,
            ),
            child: Center(
              child:
                  widget.centerChild ??
                  (widget.showPercentage
                      ? Text(
                          '${(widget.progress * 100).round()}%',
                          style: AppTextStyles.numberMedium(
                            size: widget.size * 0.25,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : null),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}

/// Linear progress bar with optional animated fill and label.
class ProgressBar extends StatefulWidget {
  final double progress; // 0.0 – 1.0
  final double height;
  final Color? progressColor;
  final Color? trackColor;
  final BorderRadius? borderRadius;
  final Widget? label;
  final bool animate;
  final Duration animationDuration;
  final bool showPercentage;

  const ProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
    this.progressColor,
    this.trackColor,
    this.borderRadius,
    this.label,
    this.animate = true,
    this.animationDuration = const Duration(milliseconds: 600),
    this.showPercentage = false,
  });

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  double _prevProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
    _prevProgress = widget.progress;
  }

  @override
  void didUpdateWidget(covariant ProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _prevProgress = _animation.value;
      _animation = Tween<double>(begin: _prevProgress, end: widget.progress)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      if (widget.animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.progressColor ?? AppColors.accentPrimary;
    final tc = widget.trackColor ?? AppColors.divider;
    final br = widget.borderRadius ?? BorderRadius.circular(widget.height / 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null || widget.showPercentage)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.label != null) widget.label!,
                if (widget.showPercentage)
                  Text(
                    '${(widget.progress * 100).round()}%',
                    style: AppTextStyles.labelSmall(color: pc),
                  ),
              ],
            ),
          ),
        AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(color: tc, borderRadius: br),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _animation.value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(color: pc, borderRadius: br),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// XP bar specifically for level progression — shows current/target XP.
class XpProgressBar extends StatelessWidget {
  final int currentXp;
  final int targetXp;
  final int level;
  final String levelName;
  final bool animate;
  final VoidCallback? onTap;

  const XpProgressBar({
    super.key,
    required this.currentXp,
    required this.targetXp,
    required this.level,
    required this.levelName,
    this.animate = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (currentXp / targetXp).clamp(0.0, 1.0);
    final remaining = targetXp - currentXp;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: SurfaceCard(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Level header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                    child: Text(
                      'LEVEL $level — $levelName',
                      style: AppTextStyles.xpLabel(),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatNumber(currentXp)} / ${_formatNumber(targetXp)} XP',
                    style: AppTextStyles.bodyMedium(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Progress bar
              ProgressBar(
                progress: progress,
                height: 10,
                progressColor: AppColors.xpGold,
                trackColor: AppColors.divider,
                animate: animate,
                label: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$remaining XP to next level',
                      style: AppTextStyles.labelSmall(
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (progress >= 1.0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          'LEVEL UP READY',
                          style: AppTextStyles.labelSmall(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Next level preview
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.arrow_upward,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Next: ${_nextLevelName(level)} (Level ${level + 1})',
                    style: AppTextStyles.bodySmall(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _nextLevelName(int current) {
    const names = ['Rookie', 'Fan', 'Ultra', 'Legend', 'GOAT'];
    if (current >= names.length) return 'GOAT';
    return names[current];
  }
}

/// Streak visualization — 7/30 day dots with current streak highlight.
class StreakDots extends StatelessWidget {
  final int currentStreak;
  final int maxDisplay;
  final double dotSize;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? currentColor;
  final bool animate;

  const StreakDots({
    super.key,
    required this.currentStreak,
    this.maxDisplay = 7,
    this.dotSize = 12,
    this.activeColor,
    this.inactiveColor,
    this.currentColor,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final ac = activeColor ?? AppColors.accentPrimary;
    final ic = inactiveColor ?? AppColors.divider;
    final cc = currentColor ?? AppColors.accentPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxDisplay, (index) {
        final day = index + 1;
        final isActive = day <= currentStreak;
        final isCurrent = day == currentStreak;

        return AnimatedContainer(
          duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? ac : ic,
                  border: isCurrent ? Border.all(color: cc, width: 2) : null,
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: cc.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              if (isCurrent && animate)
                _PulseRing(color: cc, size: dotSize * 2.5),
            ],
          ),
        );
      }),
    );
  }
}

class _PulseRing extends StatefulWidget {
  final Color color;
  final double size;

  const _PulseRing({required this.color, required this.size});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
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
          width: widget.size * _controller.value,
          height: widget.size * _controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: 1.0 - _controller.value),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

/// Rank movement indicator — shows position change with arrow.
class RankMovement extends StatelessWidget {
  final int previousRank;
  final int currentRank;
  final bool showPrevious;
  final double fontSize;

  const RankMovement({
    super.key,
    required this.previousRank,
    required this.currentRank,
    this.showPrevious = true,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final diff = previousRank - currentRank;
    final improved = diff > 0;
    final declined = diff < 0;
    final color = improved
        ? AppColors.success
        : (declined ? AppColors.error : AppColors.textMuted);
    final icon = improved
        ? Icons.arrow_upward
        : (declined ? Icons.arrow_downward : Icons.remove);

    if (!showPrevious && diff == 0) {
      return Text(
        '#$currentRank',
        style: AppTextStyles.numberMedium(size: fontSize),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPrevious) ...[
          Text(
            '#$previousRank',
            style: AppTextStyles.bodyMedium(
              fontSize: fontSize,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(icon, size: fontSize * 0.8, color: color),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          '#$currentRank',
          style: AppTextStyles.numberMedium(size: fontSize, color: color),
        ),
        if (diff != 0) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${improved ? '↑' : '↓'} ${diff.abs()}',
            style: AppTextStyles.labelMedium(color: color),
          ),
        ],
      ],
    );
  }
}

/// Animated counter — counts up to target value.
class AnimatedCounter extends StatefulWidget {
  final int target;
  final Duration duration;
  final TextStyle? style;
  final String? prefix;
  final String? suffix;
  final int? startFrom;

  const AnimatedCounter({
    super.key,
    required this.target,
    this.duration = const Duration(milliseconds: 1200),
    this.style,
    this.prefix,
    this.suffix,
    this.startFrom,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = IntTween(
      begin: widget.startFrom ?? 0,
      end: widget.target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _animation = IntTween(begin: _animation.value, end: widget.target)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Text(
          '${widget.prefix ?? ''}${_formatNumber(_animation.value)}${widget.suffix ?? ''}',
          style: widget.style ?? AppTextStyles.numberDisplay(),
        );
      },
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Tier badge — Gold/Silver/Bronze/Platinum for top ranks.
class TierBadge extends StatelessWidget {
  final int rank;
  final double size;
  final bool showLabel;

  const TierBadge({
    super.key,
    required this.rank,
    this.size = 28,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (rank) {
      1 => (AppColors.rankGold, '1st', Icons.emoji_events),
      2 => (AppColors.rankSilver, '2nd', Icons.emoji_events),
      3 => (AppColors.rankBronze, '3rd', Icons.emoji_events),
      <= 10 => (AppColors.accentPrimary, 'Top 10', Icons.star),
      <= 100 => (AppColors.accentSecondary, 'Top 100', Icons.star_half),
      _ => (AppColors.textMuted, null, null),
    };

    if (rank > 100 && !showLabel) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? AppSpacing.sm : 0,
        vertical: AppSpacing.xs,
      ),
      decoration: showLabel
          ? BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(color: color, width: 1.5),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: size * 0.7, color: color),
          if (showLabel && label != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTextStyles.rankBadge(color: color, size: 10)),
          ],
        ],
      ),
    );
  }
}
