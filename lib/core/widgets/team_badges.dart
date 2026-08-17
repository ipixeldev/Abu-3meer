// Team badges, crests, and selection components.

import 'package:flutter/material.dart';
import '../design/index.dart';

/// Team crest placeholder — drawn with vectors (no asset required).
/// Can represent Barcelona or Real Madrid.
class TeamCrest extends StatelessWidget {
  final bool isBarcelona;
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  const TeamCrest({
    super.key,
    required this.isBarcelona,
    this.size = 48,
    this.showLabel = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final widget_ = _CrestShape(
      isBarcelona: isBarcelona,
      size: size,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: widget_,
        ),
      );
    }
    return widget_;
  }
}

class _CrestShape extends StatelessWidget {
  final bool isBarcelona;
  final double size;

  const _CrestShape({required this.isBarcelona, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrestPainter(isBarcelona: isBarcelona),
      ),
    );
  }
}

class _CrestPainter extends CustomPainter {
  final bool isBarcelona;

  _CrestPainter({required this.isBarcelona});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w * 0.45;

    if (isBarcelona) {
      _drawBarcelonaCrest(canvas, center, radius);
    } else {
      _drawMadridCrest(canvas, center, radius);
    }
  }

  void _drawBarcelonaCrest(Canvas canvas, Offset center, double radius) {
    // Outer shield shape
    final path = Path();
    final w = radius * 2;
    final h = radius * 2.2;

    path.moveTo(center.dx, center.dy - h * 0.48);
    path.lineTo(center.dx + w * 0.4, center.dy - h * 0.2);
    path.quadraticBezierTo(
      center.dx + w * 0.45,
      center.dy + h * 0.1,
      center.dx + w * 0.35,
      center.dy + h * 0.35,
    );
    path.lineTo(center.dx, center.dy + h * 0.48);
    path.lineTo(center.dx - w * 0.35, center.dy + h * 0.35);
    path.quadraticBezierTo(
      center.dx - w * 0.45,
      center.dy + h * 0.1,
      center.dx - w * 0.4,
      center.dy - h * 0.2,
    );
    path.close();

    // Background
    final bgPaint = Paint()
      ..color = AppColors.bgSurfaceElevated
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bgPaint);

    // Top section - Cross of St George (red cross on white)
    final topRect = Rect.fromLTWH(
      center.dx - w * 0.35,
      center.dy - h * 0.45,
      w * 0.7,
      h * 0.35,
    );

    final crossPaint = Paint()..color = AppColors.barcaRed;
    final whitePaint = Paint()..color = Colors.white;

    // White background for top
    canvas.drawRect(topRect, whitePaint);
    // Vertical bar
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - w * 0.04,
        center.dy - h * 0.45,
        w * 0.08,
        h * 0.35,
      ),
      crossPaint,
    );
    // Horizontal bar
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - w * 0.35,
        center.dy - h * 0.27,
        w * 0.7,
        h * 0.06,
      ),
      crossPaint,
    );

    // Bottom section - Blaugrana stripes
    final stripeCount = 4;
    final stripeHeight = h * 0.35 / stripeCount;
    for (int i = 0; i < stripeCount; i++) {
      final y = center.dy - h * 0.1 + i * stripeHeight;
      final color = i.isEven ? AppColors.barcaBlue : AppColors.barcaRed;
      final stripePaint = Paint()..color = color;
      canvas.drawRect(
        Rect.fromLTWH(center.dx - w * 0.35, y, w * 0.7, stripeHeight),
        stripePaint,
      );
    }

    // Outline
    final outlinePaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, outlinePaint);

    // "FCB" text placeholder
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'FCB',
        style: TextStyle(
          color: AppColors.textPrimary.withValues(alpha: 0.4),
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.18,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + h * 0.05),
    );
  }

  void _drawMadridCrest(Canvas canvas, Offset center, double radius) {
    // Shield shape with crown
    final path = Path();
    final w = radius * 2;
    final h = radius * 2.2;

    // Crown on top
    final crownHeight = h * 0.15;
    path.moveTo(center.dx, center.dy - h * 0.48 - crownHeight);
    // Crown peaks
    for (int i = 0; i < 5; i++) {
      final x = center.dx - w * 0.35 + (w * 0.7 / 4) * i;
      if (i % 2 == 0) {
        path.lineTo(x, center.dy - h * 0.48 - crownHeight * 0.5);
      } else {
        path.lineTo(x, center.dy - h * 0.48 - crownHeight);
      }
    }
    path.lineTo(center.dx + w * 0.35, center.dy - h * 0.48 - crownHeight * 0.5);
    // Shield body
    path.lineTo(center.dx + w * 0.4, center.dy - h * 0.2);
    path.quadraticBezierTo(
      center.dx + w * 0.45,
      center.dy + h * 0.1,
      center.dx + w * 0.35,
      center.dy + h * 0.35,
    );
    path.lineTo(center.dx, center.dy + h * 0.48);
    path.lineTo(center.dx - w * 0.35, center.dy + h * 0.35);
    path.quadraticBezierTo(
      center.dx - w * 0.45,
      center.dy + h * 0.1,
      center.dx - w * 0.4,
      center.dy - h * 0.2,
    );
    path.close();

    // Background
    final bgPaint = Paint()
      ..color = AppColors.bgSurfaceElevated
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bgPaint);

    // Crown - gold
    final crownPath = Path();
    crownPath.moveTo(center.dx, center.dy - h * 0.48 - crownHeight);
    for (int i = 0; i < 5; i++) {
      final x = center.dx - w * 0.35 + (w * 0.7 / 4) * i;
      if (i % 2 == 0) {
        crownPath.lineTo(x, center.dy - h * 0.48 - crownHeight * 0.5);
      } else {
        crownPath.lineTo(x, center.dy - h * 0.48 - crownHeight);
      }
    }
    crownPath.lineTo(center.dx + w * 0.35, center.dy - h * 0.48 - crownHeight * 0.5);
    crownPath.close();

    final crownPaint = Paint()..color = AppColors.madridGold;
    canvas.drawPath(crownPath, crownPaint);

    // Crown jewels
    final jewelPaint = Paint()..color = AppColors.barcaRed;
    for (int i = 0; i < 5; i++) {
      if (i % 2 == 1) {
        final x = center.dx - w * 0.35 + (w * 0.7 / 4) * i;
        canvas.drawCircle(
          Offset(x, center.dy - h * 0.48 - crownHeight * 0.7),
          radius * 0.025,
          jewelPaint,
        );
      }
    }

    // Shield - diagonal sash
    final sashPath = Path();
    sashPath.moveTo(center.dx - w * 0.35, center.dy - h * 0.2);
    sashPath.lineTo(center.dx + w * 0.05, center.dy - h * 0.2);
    sashPath.lineTo(center.dx + w * 0.35, center.dy + h * 0.2);
    sashPath.lineTo(center.dx - w * 0.05, center.dy + h * 0.2);
    sashPath.close();

    final sashPaint = Paint()..color = AppColors.madridNavy;
    canvas.drawPath(sashPath, sashPaint);

    // "MCF" text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'MCF',
        style: TextStyle(
          color: AppColors.textPrimary.withValues(alpha: 0.4),
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.18,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + h * 0.05),
    );

    // Outline
    final outlinePaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _CrestPainter oldDelegate) {
    return oldDelegate.isBarcelona != isBarcelona;
  }
}

/// Team tag/pill — small coloured label with team initials.
class TeamTag extends StatelessWidget {
  final bool isBarcelona;
  final String? customText;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const TeamTag({
    super.key,
    required this.isBarcelona,
    this.customText,
    this.fontSize = 10,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final text = customText ?? (isBarcelona ? 'BAR' : 'RMA');
    final bgColor = isBarcelona ? AppColors.barcaBlue : AppColors.madridGold;
    final textColor = isBarcelona ? Colors.white : AppColors.bgCanvas;

    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.space3,
            vertical: AppSpacing.xs,
          ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Barlow Condensed',
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: 1.0,
          color: textColor,
        ),
      ),
    );
  }
}

/// Large team selection card used in onboarding.
class TeamSelectionCard extends StatelessWidget {
  final bool isBarcelona;
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String subtitle;

  const TeamSelectionCard({
    super.key,
    required this.isBarcelona,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return TeamCard(
      isBarcelona: isBarcelona,
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          // Crest
          TeamCrest(isBarcelona: isBarcelona, size: 100),
          const SizedBox(height: AppSpacing.lg),

          // Team name
          Text(
            title,
            style: AppTextStyles.displaySmall(
              color: isBarcelona ? AppColors.barcaBlue : AppColors.madridGold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium(),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Selection indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: selected ? 48 : 0,
            height: 4,
            decoration: BoxDecoration(
              color: isBarcelona ? AppColors.barcaBlue : AppColors.madridGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (selected) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: isBarcelona ? AppColors.barcaBlue : AppColors.madridGold,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'SELECTED',
                  style: AppTextStyles.labelSmall(
                    color: isBarcelona ? AppColors.barcaBlue : AppColors.madridGold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Fan War progress bar — animated split between two teams.
class FanWarProgress extends StatefulWidget {
  final int barcaXp;
  final int madridXp;
  final double height;
  final bool animate;
  final bool showLabels;

  const FanWarProgress({
    super.key,
    required this.barcaXp,
    required this.madridXp,
    this.height = 12,
    this.animate = true,
    this.showLabels = true,
  });

  @override
  State<FanWarProgress> createState() => _FanWarProgressState();
}

class _FanWarProgressState extends State<FanWarProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    final progress = _calculateProgress();
    _animation = Tween<double>(begin: 0, end: progress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant FanWarProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barcaXp != widget.barcaXp || oldWidget.madridXp != widget.madridXp) {
      final progress = _calculateProgress();
      _animation = Tween<double>(begin: _animation.value, end: progress).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      if (widget.animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  double _calculateProgress() {
    final total = widget.barcaXp + widget.madridXp;
    if (total == 0) return 0.5;
    return widget.barcaXp / total;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _calculateProgress();
    final barcaPct = (progress * 100).round();
    final madridPct = 100 - barcaPct;
    final diff = widget.barcaXp - widget.madridXp;
    final leader = diff > 0 ? 'Barcelona' : 'Real Madrid';
    final diffAbs = diff.abs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLabels)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  TeamTag(isBarcelona: true, fontSize: 10),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$barcaPct%',
                    style: AppTextStyles.labelMedium(
                      color: AppColors.barcaBlue,
                    ),
                  ),
                ],
              ),
              Text(
                leader == 'Barcelona'
                    ? 'Barcelona leads by ${_formatNumber(diffAbs)} XP'
                    : 'Real Madrid leads by ${_formatNumber(diffAbs)} XP',
                style: AppTextStyles.bodySmall(),
              ),
              Row(
                children: [
                  Text(
                    '$madridPct%',
                    style: AppTextStyles.labelMedium(
                      color: AppColors.madridGold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TeamTag(isBarcelona: false, fontSize: 10),
                ],
              ),
            ],
          ),
        if (widget.showLabels) const SizedBox(height: AppSpacing.sm),
        AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height / 2),
                color: AppColors.divider,
              ),
              child: Stack(
                children: [
                  // Barcelona portion (left)
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _animation.value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(widget.height / 2),
                          right: _animation.value >= 1.0
                              ? Radius.circular(widget.height / 2)
                              : Radius.zero,
                        ),
                        gradient: AppColors.gradientBarca,
                      ),
                    ),
                  ),
                  // Real Madrid portion (right)
                  FractionallySizedBox(
                    alignment: Alignment.centerRight,
                    widthFactor: (1 - _animation.value).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(widget.height / 2),
                          left: _animation.value <= 0
                              ? Radius.circular(widget.height / 2)
                              : Radius.zero,
                        ),
                        gradient: AppColors.gradientMadrid,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Countdown timer widget — days, hours, minutes, seconds.
class CountdownTimer extends StatefulWidget {
  final DateTime target;
  final TextStyle? style;
  final bool compact;
  final VoidCallback? onComplete;

  const CountdownTimer({
    super.key,
    required this.target,
    this.style,
    this.compact = false,
    this.onComplete,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final diff = widget.target.difference(now);
    if (diff.isNegative) {
      if (!_completed) {
        _completed = true;
        _timer.cancel();
        widget.onComplete?.call();
      }
      setState(() => _remaining = Duration.zero);
    } else {
      setState(() => _remaining = diff);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _remaining.inDays;
    final h = _remaining.inHours.remainder(24);
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);

    if (widget.compact) {
      String text;
      if (d > 0) {
        text = '${d}d ${h}h';
      } else if (h > 0) {
        text = '${h}h ${m}m';
      } else {
        text = '${m}m ${s}s';
      }
      return Text(text, style: widget.style ?? AppTextStyles.labelMedium(color: AppColors.accentPrimary));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (d > 0) ...[
          _TimeUnit(value: d, label: 'd'),
          const SizedBox(width: AppSpacing.sm),
        ],
        _TimeUnit(value: h, label: 'h'),
        const SizedBox(width: AppSpacing.sm),
        _TimeUnit(value: m, label: 'm'),
        const SizedBox(width: AppSpacing.sm),
        _TimeUnit(value: s, label: 's'),
      ],
    );
  }
}

class _TimeUnit extends StatelessWidget {
  final int value;
  final String label;

  const _TimeUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value.toString().padLeft(2, '0'),
          style: AppTextStyles.numberMedium(
            color: AppColors.accentPrimary,
            size: 18,
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: AppTextStyles.labelSmall(color: AppColors.textMuted)),
      ],
    );
  }
}

import 'dart:async';
