// Premium Login Screen with validation and demo credentials.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/index.dart';
import '../../core/state/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/navigation/routes.dart';
import '../../core/widgets/buttons.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Demo credentials hint
  static const List<Map<String, String>> _demoAccounts = [
    {'email': 'ahmed.demo@fanleague.app', 'name': 'Ahmed (Ultra Member)'},
    {'email': 'mohammed.ak@demo.fanleague.app', 'name': 'Mohammed (GOAT #1)'},
    {'email': 'alex.martinez@demo.fanleague.app', 'name': 'Alex (Barcelona)'},
    {'email': 'omar.garcia@demo.fanleague.app', 'name': 'Omar (Madrid)'},
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await context.appStateRead.login(
      _emailController.text.trim(),
      _passwordController.text,
      rememberMe: _rememberMe,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        context.go(AppRoutes.home);
      } else {
        setState(() => _errorMessage = context.appStateRead.authError);
      }
    }
  }

  Future<void> _handleSocialLogin(bool isGoogle) async {
    setState(() => _isLoading = true);
    final success = isGoogle
        ? await context.appStateRead.loginWithGoogle()
        : await context.appStateRead.loginWithApple();
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        context.go(AppRoutes.home);
      }
    }
  }

  void _fillDemoCredentials(int index) {
    final account = _demoAccounts[index];
    _emailController.text = account['email']!;
    _passwordController.text = 'demo1234';
    setState(() {}); // Refresh to show filled fields
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenPaddingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientPrimary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      ),
                      child: Center(
                        child: CustomPaint(
                          size: const Size(40, 40),
                          painter: _TrophyPainter(),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // Title
                  Text(
                    'Welcome Back',
                    style: AppTextStyles.displayMedium(),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  Text(
                    'Sign in to continue your Fan League journey',
                    style: AppTextStyles.bodyMedium(),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // Error message
                  if (_errorMessage != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 20, color: AppColors.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTextStyles.bodySmall(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_errorMessage != null) const SizedBox(height: AppSpacing.md),

                  // Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!value.contains('@') || !value.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            if (value.length < 4) {
                              return 'Password too short';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: AppSpacing.sm),

                        // Remember me + Forgot password
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (v) => setState(() => _rememberMe = v ?? false),
                              activeColor: AppColors.accentPrimary,
                              checkColor: AppColors.textOnAccent,
                              side: BorderSide(color: AppColors.divider),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                            ),
                            Text('Remember me', style: AppTextStyles.bodySmall()),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                // Demo: show snackbar
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Demo: Password reset not implemented')),
                                );
                              },
                              child: Text('Forgot password?', style: AppTextStyles.labelMedium(color: AppColors.accentPrimary)),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // Sign In button
                        PrimaryButton(
                          label: 'Sign In',
                          onPressed: _handleLogin,
                          loading: _isLoading,
                          fullWidth: true,
                          height: 56,
                        ),

                        const SizedBox(height: AppSpacing.lg),

                        // Divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: AppColors.divider)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                              child: Text('Or continue with', style: AppTextStyles.labelSmall()),
                            ),
                            const Expanded(child: Divider(color: AppColors.divider)),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Social buttons
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                label: 'Google',
                                onPressed: () => _handleSocialLogin(true),
                                loading: _isLoading,
                                fullWidth: true,
                                leadingIcon: Icons.g_mobiledata,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: SecondaryButton(
                                label: 'Apple',
                                onPressed: () => _handleSocialLogin(false),
                                loading: _isLoading,
                                fullWidth: true,
                                leadingIcon: Icons.apple,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        // Demo accounts helper
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurfaceElevated,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: AppColors.accentPrimary),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text('Demo Accounts', style: AppTextStyles.labelMedium(color: AppColors.accentPrimary)),
                                  const Spacer(),
                                  Text('Password: demo1234', style: AppTextStyles.labelSmall(color: AppColors.textMuted)),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: List.generate(_demoAccounts.length, (i) {
                                  final acc = _demoAccounts[i];
                                  return ActionChip(
                                    label: Text(acc['name']!, style: AppTextStyles.labelSmall()),
                                    onPressed: () => _fillDemoCredentials(i),
                                    backgroundColor: AppColors.bgSurface,
                                    side: BorderSide(color: AppColors.divider),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusFull)),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        // Sign up link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Don't have an account? ", style: AppTextStyles.bodyMedium()),
                            GestureDetector(
                              onTap: () => context.go(AppRoutes.register),
                              child: Text(
                                'Create Account',
                                style: AppTextStyles.labelMedium(color: AppColors.accentPrimary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Cup body
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
    canvas.drawPath(cupPath, paint);

    // Handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final leftHandle = Path();
    leftHandle.moveTo(center.dx - w * 0.25, center.dy - h * 0.05);
    leftHandle.quadraticBezierTo(
      center.dx - w * 0.45,
      center.dy,
      center.dx - w * 0.28,
      center.dy + h * 0.15,
    );
    canvas.drawPath(leftHandle, handlePaint);

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
      Rect.fromLTWH(center.dx - w * 0.2, center.dy + h * 0.35, w * 0.4, h * 0.08),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(4),
    );
    canvas.drawRRect(baseRect, basePaint);

    // Star
    final starPaint = Paint()..color = AppColors.accentPrimary..style = PaintingStyle.fill;
    _drawStar(canvas, center.dx, center.dy - h * 0.05, w * 0.1, starPaint);
  }

  void _drawStar(Canvas canvas, double cx, double cy, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = -3.14159 / 2 + i * 2 * 3.14159 / 5;
      final outerX = cx + radius * math.cos(angle);
      final outerY = cy + radius * math.sin(angle);
      if (i == 0) path.moveTo(outerX, outerY);
      else path.lineTo(outerX, outerY);
      final innerAngle = angle + 3.14159 / 5;
      final innerX = cx + radius * 0.4 * math.cos(innerAngle);
      final innerY = cy + radius * 0.4 * math.sin(innerAngle);
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;
