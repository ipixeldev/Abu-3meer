// Splash / Launch screen with animated logo and transition.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/index.dart';
import '../../core/state/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoRotation;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.elasticOut)),
    );

    _logoRotation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8, curve: Curves.easeOut)),
    );

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic)),
    );

    _controller.forward();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (mounted) {
      final appState = context.read<AppState>();
      if (appState.isAuthenticated) {
        context.go(AppRoutes.home);
      } else {
        context.go(AppRoutes.login);
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
    return Scaffold(
      backgroundColor: AppColors.bgCanvas,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Transform.scale(
                  scale: _logoScale.value,
                  child: Transform.rotate(
                    angle: _logoRotation.value * 0.1,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientPrimary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentPrimary.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Center(
                        child: CustomPaint(
                          size: const Size(60, 60),
                          painter: _TrophyPainter(),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // App name
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Text(
                      AppConfig.appName,
                      style: AppTextStyles.displayLarge(
                        color: AppColors.textPrimary,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),

                // Tagline
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Text(
                      AppConfig.tagline,
                      style: AppTextStyles.bodyLarge(color: AppColors.textSecondary),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Loading indicator
                FadeTransition(
                  opacity: _textFade,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(AppColors.accentPrimary),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Demo badge
                FadeTransition(
                  opacity: _textFade,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      border: Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      AppConfig.demoBadge,
                      style: AppTextStyles.labelSmall(color: AppColors.accentPrimary),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrophyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Cup body
    final cupPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cupPath = Path();
    cupPath.moveTo(center.dx - w * 0.25, center.dy - h * 0.1);
    cupPath.lineTo(center.dx - w * 0.3, center.dy + h * 0.25);
    cupPath.quadraticBezierTo(
      center.dx - w * 0.3,
      center.dy + h * 0.35,
      center.dx,
      center.dy + h * 0.35,
    );
    cupPath.quadraticBezierTo(
      center.dx + w * 0.3,
      center.dy + h * 0.35,
      center.dx + w * 0.3,
      center.dy + h * 0.25,
    );
    cupPath.lineTo(center.dx + w * 0.25, center.dy - h * 0.1);
    cupPath.close();

    canvas.drawPath(cupPath, cupPaint);

    // Handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Left handle
    final leftHandle = Path();
    leftHandle.moveTo(center.dx - w * 0.25, center.dy - h * 0.05);
    leftHandle.quadraticBezierTo(
      center.dx - w * 0.45,
      center.dy,
      center.dx - w * 0.28,
      center.dy + h * 0.15,
    );
    canvas.drawPath(leftHandle, handlePaint);

    // Right handle
    final rightHandle = Path();
    rightHandle.moveTo(center.dx + w * 0.25, center.dy - h * 0.05);
    rightHandle.quadraticBezierTo(
      center.dx + w * 0.45,
      center.dy,
      center.dx + w * 0.28,
      center.dy + h * 0.15,
    );
    canvas.drawPath(rightHandle, handlePaint);

    // Base
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final baseRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        center.dx - w * 0.2,
        center.dy + h * 0.35,
        w * 0.4,
        h * 0.08,
      ),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(4),
    );
    canvas.drawRRect(baseRect, basePaint);

    // Star on cup
    final starPaint = Paint()
      ..color = AppColors.accentPrimary
      ..style = PaintingStyle.fill;

    _drawStar(canvas, center.dx, center.dy - h * 0.05, w * 0.12, starPaint);
  }

  void _drawStar(Canvas canvas, double cx, double cy, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = -3.14159 / 2 + i * 2 * 3.14159 / 5;
      final outerX = cx + radius * cos(angle);
      final outerY = cy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }

      final innerAngle = angle + 3.14159 / 5;
      final innerX = cx + radius * 0.4 * cos(innerAngle);
      final innerY = cy + radius * 0.4 * sin(innerAngle);
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  double cos(double radians) => math.cos(radians);
  double sin(double radians) => math.sin(radians);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;
