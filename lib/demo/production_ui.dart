part of 'fan_league_app.dart';

void _runProductionBackgroundTask(Future<void> operation, String label) {
  unawaited(() async {
    try {
      await operation;
    } catch (error, stackTrace) {
      debugPrint('[$label] Background refresh failed: $error\n$stackTrace');
    }
  }());
}

class _ProductionGate extends StatefulWidget {
  const _ProductionGate();

  @override
  State<_ProductionGate> createState() => _ProductionGateState();
}

class _ProductionGateState extends State<_ProductionGate> {
  late final ProductionRepository repository;

  @override
  void initState() {
    super.initState();
    repository = ProductionRepository();
    unawaited(
      NotificationService.instance.initialize(apiRepo: repository.apiRepo),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: repository.authChanges,
    builder: (context, authSnapshot) {
      if (authSnapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionLoading();
      }
      final user = authSnapshot.data;
      if (user == null) {
        return _ProductionShell(
          repository: repository,
          profile: AbuUserProfile.guest(),
        );
      }
      final passwordUser = user.providerData.any(
        (provider) => provider.providerId == 'password',
      );
      if (passwordUser && !user.emailVerified) {
        return _VerifyEmail(repository: repository, user: user);
      }
      return StreamBuilder<AbuUserProfile?>(
        stream: repository.watchProfile(user.uid),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const _ProductionLoading();
          }
          if (profileSnapshot.hasError) {
            final error = profileSnapshot.error!;
            final expiredSession =
                error is AbuApiException && error.statusCode == 401;
            return _ProductionFailure(
              title: expiredSession
                  ? abuText(
                      context,
                      'YOUR SESSION EXPIRED',
                      'انتهت صلاحية جلستك',
                    )
                  : abuText(
                      context,
                      'TEMPORARY CONNECTION ISSUE',
                      'مشكلة اتصال مؤقتة',
                    ),
              message: productionErrorMessage(error),
              onRetry: () => _runProductionBackgroundTask(
                repository.refreshProfile(user.uid, force: true),
                'Profile',
              ),
              onSignOut: repository.signOut,
            );
          }
          final profile = profileSnapshot.data;
          if (profile == null || !profile.onboardingComplete) {
            return _ProductionOnboarding(repository: repository, user: user);
          }
          if (profile.suspended) {
            return _ProductionFailure(
              message: abuText(
                context,
                'This account is suspended. Contact ${AbuBrand.supportEmail}.',
                'هذا الحساب موقوف. تواصل عبر ${AbuBrand.supportEmail}.',
              ),
              onRetry: () => _runProductionBackgroundTask(
                repository.refreshProfile(user.uid, force: true),
                'Profile',
              ),
              onSignOut: repository.signOut,
            );
          }
          return _ProductionShell(repository: repository, profile: profile);
        },
      );
    },
  );
}

class _StreakIconWidget extends StatelessWidget {
  const _StreakIconWidget({this.size = 18.0});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/streak_fire.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    isAntiAlias: true,
    errorBuilder: (_, _, _) =>
        Icon(Icons.local_fire_department_rounded, color: _red, size: size),
  );
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({
    required this.streak,
    required this.onTap,
    this.compact = false,
  });
  final int streak;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1416),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _red.withValues(alpha: .4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StreakIconWidget(size: compact ? 14 : 16),
            SizedBox(width: compact ? 4 : 5),
            Text(
              '$streak',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showStreakGoals(
  BuildContext context,
  AbuUserProfile profile,
) async {
  const milestones = <int>[3, 7, 14, 30, 60, 100];
  final current = profile.currentStreak;
  final next = milestones.firstWhere(
    (value) => value > current,
    orElse: () => ((current ~/ 30) + 1) * 30,
  );
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const _StreakIconWidget(size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abuText(sheetContext, 'STREAK GOALS', 'أهداف السلسلة'),
                        style: _display(24),
                      ),
                      Text(
                        abuText(
                          sheetContext,
                          '$current days active · Best ${profile.longestStreak}',
                          '$current يوم نشط · الأفضل ${profile.longestStreak}',
                        ),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final milestone in milestones) ...[
              _StreakGoalRow(
                days: milestone,
                completed: current >= milestone,
                current: current,
              ),
              if (milestone != milestones.last) const SizedBox(height: 10),
            ],
            const SizedBox(height: 18),
            Text(
              abuText(
                sheetContext,
                'Next goal: $next days. Complete an eligible activity each day to keep the streak alive.',
                'الهدف التالي: $next يوم. أكمل نشاطاً مؤهلاً كل يوم للحفاظ على السلسلة.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StreakGoalRow extends StatelessWidget {
  const _StreakGoalRow({
    required this.days,
    required this.completed,
    required this.current,
  });

  final int days;
  final bool completed;
  final int current;

  @override
  Widget build(BuildContext context) {
    final progress = (current / days).clamp(0.0, 1.0);
    final color = completed ? _productionPrimary(context) : _red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.flag_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  abuText(context, '$days DAY GOAL', 'هدف $days يوم'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: _line,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            completed ? '✓' : '${current.clamp(0, days)}/$days',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// A local, dependency-free rendition of Google's four-colour G mark.
///
/// Keeping this as vector paint means the sign-in control remains crisp and
/// recognizable when the app is offline, and avoids the former monochrome
/// Material "g" glyph which is not Google's sign-in mark.
class _GoogleGMark extends StatelessWidget {
  const _GoogleGMark({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: const _GoogleGMarkPainter()),
  );
}

class _GoogleGMarkPainter extends CustomPainter {
  const _GoogleGMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    canvas.save();
    canvas.scale(scale, scale);
    final paint = Paint()..style = PaintingStyle.fill;

    final yellow = Path()
      ..moveTo(43.611, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(33.654, 32.657, 29.223, 36, 24, 36)
      ..cubicTo(17.373, 36, 12, 30.627, 12, 24)
      ..cubicTo(12, 17.373, 17.373, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(12.955, 4, 4, 12.955, 4, 24)
      ..cubicTo(4, 35.045, 12.955, 44, 24, 44)
      ..cubicTo(35.045, 44, 44, 35.045, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20)
      ..close();
    canvas.drawPath(yellow, paint..color = const Color(0xFFFBBC05));

    final red = Path()
      ..moveTo(6.306, 14.691)
      ..lineTo(12.877, 19.51)
      ..cubicTo(14.655, 15.108, 18.961, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(16.318, 4, 9.656, 8.337, 6.306, 14.691)
      ..close();
    canvas.drawPath(red, paint..color = const Color(0xFFEA4335));

    final green = Path()
      ..moveTo(24, 44)
      ..cubicTo(29.166, 44, 33.86, 42.023, 37.409, 38.808)
      ..lineTo(31.219, 33.57)
      ..cubicTo(29.211, 35.091, 26.715, 36, 24, 36)
      ..cubicTo(18.798, 36, 14.381, 32.683, 12.717, 28.054)
      ..lineTo(6.195, 33.079)
      ..cubicTo(9.505, 39.556, 16.227, 44, 24, 44)
      ..close();
    canvas.drawPath(green, paint..color = const Color(0xFF34A853));

    final blue = Path()
      ..moveTo(43.611, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(34.511, 30.237, 33.072, 32.166, 31.216, 33.571)
      ..lineTo(37.406, 38.809)
      ..cubicTo(36.971, 39.205, 44, 34, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20)
      ..close();
    canvas.drawPath(blue, paint..color = const Color(0xFF4285F4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleGMarkPainter oldDelegate) => false;
}

class _ProductionLoading extends StatelessWidget {
  const _ProductionLoading();

  @override
  Widget build(BuildContext context) => const _PremiumSplash();
}

class _ProductionLottieLoader extends StatelessWidget {
  const _ProductionLottieLoader();
  @override
  Widget build(BuildContext context) => Lottie.asset(
    'assets/animations/ball-loading.json',
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) =>
        CircularProgressIndicator(color: _productionPrimary(context)),
  );
}

class _ProductionRemoteImage extends StatelessWidget {
  const _ProductionRemoteImage({
    required this.url,
    required this.fit,
    required this.fallback,
    this.alignment = Alignment.center,
  });

  final String url;
  final BoxFit fit;
  final Widget fallback;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: fit,
    alignment: alignment,
    // Keep the previous decoded frame while a rebuilt widget resolves the same
    // URL. This prevents avatars and team artwork from briefly flashing blank
    // during profile updates and fast scrolling.
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    // Arbitrary team and campaign CDNs frequently omit CORS headers. On web,
    // an HTML image element can display those assets without fetching bytes.
    webHtmlElementStrategy: kIsWeb
        ? WebHtmlElementStrategy.prefer
        : WebHtmlElementStrategy.never,
    errorBuilder: (_, _, _) => fallback,
  );
}

class _ProductionAuth extends StatefulWidget {
  const _ProductionAuth({required this.repository, this.isModal = false});
  final ProductionRepository repository;
  final bool isModal;

  @override
  State<_ProductionAuth> createState() => _ProductionAuthState();
}

class _ProductionAuthState extends State<_ProductionAuth> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool createAccount = false;
  bool hidden = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted && widget.isModal) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (exception, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Auth] $exception');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      setState(
        () => error = abuText(
          context,
          'Enter your email first.',
          'أدخل بريدك الإلكتروني أولاً.',
        ),
      );
      return;
    }
    await run(() => widget.repository.sendPasswordReset(email.text));
    if (mounted && error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'Password reset email sent.',
              'تم إرسال رسالة إعادة تعيين كلمة المرور.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final intro = const _AbuBrandIntro();
    final form = Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isModal)
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: IconButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).maybePop(),
                  icon: Icon(Icons.close_rounded),
                ),
              ),
            Text(
              createAccount
                  ? abuText(context, 'CREATE ACCOUNT', 'إنشاء حساب')
                  : abuText(context, 'WELCOME BACK', 'مرحباً بعودتك'),
              style: _display(28),
            ),
            const SizedBox(height: 6),
            Text(
              createAccount
                  ? abuText(
                      context,
                      'Join the Abu 3meer community.',
                      'انضم إلى مجتمع أبو عمير.',
                    )
                  : abuText(
                      context,
                      'Sign in to predict, answer and find.',
                      'سجل الدخول لتتوقع وتجيب وتكتشف.',
                    ),
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: abuText(context, 'Email', 'البريد الإلكتروني'),
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
            const SizedBox(height: 13),
            TextField(
              controller: password,
              obscureText: hidden,
              autofillHints: [
                createAccount
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: abuText(context, 'Password', 'كلمة المرور'),
                prefixIcon: Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: hidden
                      ? abuText(context, 'Show password', 'إظهار كلمة المرور')
                      : abuText(context, 'Hide password', 'إخفاء كلمة المرور'),
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: _red, fontSize: 12)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run(
                      () => createAccount
                          ? widget.repository.createEmailAccount(
                              email: email.text,
                              password: password.text,
                            )
                          : widget.repository.signInWithEmail(
                              email: email.text,
                              password: password.text,
                            ),
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: _productionPrimary(context),
                foregroundColor: _ink,
                padding: const EdgeInsets.all(17),
              ),
              child: Text(
                busy
                    ? abuText(context, 'PLEASE WAIT…', 'يرجى الانتظار…')
                    : createAccount
                    ? abuText(context, 'CREATE ACCOUNT', 'إنشاء حساب')
                    : abuText(context, 'SIGN IN', 'تسجيل الدخول'),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(widget.repository.signInWithGoogle),
              icon: const _GoogleGMark(size: 22),
              label: Text(
                abuText(
                  context,
                  'CONTINUE WITH GOOGLE',
                  'المتابعة باستخدام Google',
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(14),
              ),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
              const SizedBox(height: 10),
              SignInWithAppleButton(
                onPressed: busy
                    ? null
                    : () => run(widget.repository.signInWithApple),
                text: abuText(
                  context,
                  'Continue with Apple',
                  'المتابعة باستخدام Apple',
                ),
                height: 52,
                style: SignInWithAppleButtonStyle.white,
                borderRadius: const BorderRadius.all(Radius.circular(26)),
              ),
            ],
            const SizedBox(height: 10),
            if (!createAccount)
              TextButton(
                onPressed: busy ? null : resetPassword,
                child: Text(
                  abuText(context, 'FORGOT PASSWORD?', 'هل نسيت كلمة المرور؟'),
                ),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      createAccount = !createAccount;
                      error = null;
                    }),
              child: Text(
                createAccount
                    ? abuText(
                        context,
                        'I ALREADY HAVE AN ACCOUNT',
                        'لدي حساب بالفعل',
                      )
                    : abuText(
                        context,
                        'CREATE AN ABU 3MEER ACCOUNT',
                        'إنشاء حساب أبو عمير',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.isModal) return form;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _PitchBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: compact
                    ? Column(
                        children: [intro, const SizedBox(height: 22), form],
                      )
                    : Row(
                        children: [
                          const Expanded(child: _AbuBrandIntro()),
                          const SizedBox(width: 70),
                          Expanded(child: form),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAuthModal(
  BuildContext context,
  ProductionRepository repository,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .75),
  builder: (dialogContext) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: _ProductionAuth(repository: repository, isModal: true),
    ),
  ),
);

Future<bool> requireAuth(
  BuildContext context,
  ProductionRepository repository,
) async {
  if (repository.auth.currentUser != null) return true;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_person_rounded,
                size: 48,
                color: _productionPrimary(context),
              ),
              const SizedBox(height: 16),
              Text(
                abuText(context, 'SIGN IN REQUIRED', 'تسجيل الدخول مطلوب'),
                style: _display(24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                abuText(
                  context,
                  'You need an Abu 3meer account to make predictions, join challenges, and compete on the leaderboard.',
                  'يلزم تسجيل الدخول أو إنشاء حساب للمشاركة في التوقعات والتحديات والمنافسة على صدارة الترتيب.',
                ),
                style: TextStyle(color: _muted, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    showAuthModal(context, repository);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _productionPrimary(context),
                    foregroundColor: _ink,
                    padding: const EdgeInsets.all(14),
                  ),
                  child: Text(
                    abuText(
                      context,
                      'SIGN IN / CREATE ACCOUNT',
                      'تسجيل الدخول / إنشاء حساب',
                    ),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  abuText(context, 'MAYBE LATER', 'لاحقاً'),
                  style: TextStyle(color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return false;
}

class _AbuBrandIntro extends StatelessWidget {
  const _AbuBrandIntro();
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LogoMark(size: compact ? 54 : 64),
        SizedBox(height: compact ? 18 : 24),
        Text(
          AbuBrand.appName.toUpperCase(),
          style: _display(compact ? 52 : 64, height: .9),
        ),
        const SizedBox(height: 14),
        Text(
          AbuBrand.tagline,
          style: _display(14, color: _productionPrimary(context), spacing: 1.8),
        ),
        const SizedBox(height: 8),
        Text(
          abuText(
            context,
            'Your prediction. Your knowledge. Your place on the leaderboard.',
            'توقعك. معرفتك. مكانك في لوحة المتصدرين.',
          ),
          style: TextStyle(color: _muted, height: 1.55, fontSize: 14),
        ),
      ],
    );
  }
}

class _VerifyEmail extends StatefulWidget {
  const _VerifyEmail({required this.repository, required this.user});
  final ProductionRepository repository;
  final User user;
  @override
  State<_VerifyEmail> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends State<_VerifyEmail> {
  bool busy = false;
  String? message;

  Future<void> act(Future<void> Function() action, String success) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => message = success);
    } catch (error) {
      if (mounted) setState(() => message = productionErrorMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _CenteredProductionCard(
    icon: Icons.mark_email_read_outlined,
    title: abuText(context, 'VERIFY YOUR EMAIL', 'تحقق من بريدك الإلكتروني'),
    body: abuText(
      context,
      'We sent a verification link to ${widget.user.email}.',
      'أرسلنا رابط تحقق إلى ${widget.user.email}.',
    ),
    message: message,
    actions: [
      FilledButton(
        onPressed: busy
            ? null
            : () => act(
                widget.repository.refreshUser,
                abuText(
                  context,
                  'Account status refreshed.',
                  'تم تحديث حالة الحساب.',
                ),
              ),
        child: Text(abuText(context, 'I HAVE VERIFIED', 'تم التحقق')),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => act(
                widget.repository.resendVerification,
                abuText(
                  context,
                  'Verification email sent again.',
                  'تم إرسال رسالة التحقق مرة أخرى.',
                ),
              ),
        child: Text(abuText(context, 'RESEND EMAIL', 'إعادة إرسال الرسالة')),
      ),
      TextButton(
        onPressed: busy ? null : widget.repository.signOut,
        child: Text(
          abuText(context, 'USE ANOTHER ACCOUNT', 'استخدام حساب آخر'),
        ),
      ),
    ],
  );
}

class _CountryItem {
  final String code;
  final String nameEn;
  final String nameAr;
  final String flag;
  const _CountryItem(this.code, this.nameEn, this.nameAr, this.flag);
}

class _SyrianFlagWidget extends StatelessWidget {
  const _SyrianFlagWidget({this.width = 28, this.height = 19});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final starSize = height * 0.28;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Container(color: const Color(0xFF007A3D)), // Green
          ),
          Expanded(
            child: Container(
              color: Colors.white, // White with 3 red stars
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    '★',
                    style: TextStyle(
                      color: const Color(0xFFD52B1E),
                      fontSize: starSize,
                      height: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '★',
                    style: TextStyle(
                      color: const Color(0xFFD52B1E),
                      fontSize: starSize,
                      height: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '★',
                    style: TextStyle(
                      color: const Color(0xFFD52B1E),
                      fontSize: starSize,
                      height: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(color: Colors.black), // Black
          ),
        ],
      ),
    );
  }
}

class _CountryFlagWidget extends StatelessWidget {
  const _CountryFlagWidget({
    required this.country,
    this.flagEmoji = '',
    this.size = 22,
  });

  final String country;
  final String flagEmoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = country.trim().toLowerCase();
    if (c.contains('syria') ||
        c.contains('سوريا') ||
        c == 'sy' ||
        flagEmoji == '🇸🇾') {
      return _SyrianFlagWidget(width: size * 1.35, height: size * 0.9);
    }
    var effectiveFlag = flagEmoji;
    if (effectiveFlag == '🌍') effectiveFlag = '';
    if (effectiveFlag.isEmpty) {
      for (final item in _kPopularCountries) {
        if (item.code.toLowerCase() == c ||
            item.nameEn.toLowerCase() == c ||
            item.nameAr.toLowerCase() == c ||
            c.contains(item.nameEn.toLowerCase()) ||
            c.contains(item.nameAr.toLowerCase()) ||
            item.nameEn.toLowerCase().contains(c)) {
          effectiveFlag = item.flag;
          break;
        }
      }
    }
    if (effectiveFlag.isEmpty) {
      effectiveFlag = (c.isEmpty || c.contains('saudi') || c == 'sa')
          ? '🇸🇦'
          : '🌍';
    }
    return Text(effectiveFlag, style: TextStyle(fontSize: size));
  }
}

const _kPopularCountries = [
  _CountryItem('SA', 'Saudi Arabia', 'المملكة العربية السعودية', '🇸🇦'),
  _CountryItem('EG', 'Egypt', 'مصر', '🇪🇬'),
  _CountryItem(
    'AE',
    'United Arab Emirates',
    'الإمارات العربية المتحدة',
    '🇦🇪',
  ),
  _CountryItem('KW', 'Kuwait', 'الكويت', '🇰🇼'),
  _CountryItem('QA', 'Qatar', 'قطر', '🇶🇦'),
  _CountryItem('JO', 'Jordan', 'الأردن', '🇯🇴'),
  _CountryItem('IQ', 'Iraq', 'العراق', '🇮🇶'),
  _CountryItem('MA', 'Morocco', 'المغرب', '🇲🇦'),
  _CountryItem('DZ', 'Algeria', 'الجزائر', '🇩🇿'),
  _CountryItem('TN', 'Tunisia', 'تونس', '🇹🇳'),
  _CountryItem('OM', 'Oman', 'عُمان', '🇴🇲'),
  _CountryItem('BH', 'Bahrain', 'البحرين', '🇧🇭'),
  _CountryItem('LB', 'Lebanon', 'لبنان', '🇱🇧'),
  _CountryItem('PS', 'Palestine', 'فلسطين', '🇵🇸'),
  _CountryItem('SD', 'Sudan', 'السودان', '🇸🇩'),
  _CountryItem('LY', 'Libya', 'ليبيا', '🇱🇾'),
  _CountryItem('YE', 'Yemen', 'اليمن', '🇾🇪'),
  _CountryItem('SY', 'Syria', 'سوريا', '🇸🇾'),
  _CountryItem('ES', 'Spain', 'إسبانيا', '🇪🇸'),
  _CountryItem('SE', 'Sweden', 'السويد', '🇸🇪'),
  _CountryItem('GB', 'United Kingdom', 'المملكة المتحدة', '🇬🇧'),
  _CountryItem('US', 'United States', 'الولايات المتحدة', '🇺🇸'),
  _CountryItem('DE', 'Germany', 'ألمانيا', '🇩🇪'),
  _CountryItem('FR', 'France', 'فرنسا', '🇫🇷'),
  _CountryItem('IT', 'Italy', 'إيطاليا', '🇮🇹'),
  _CountryItem('BR', 'Brazil', 'البرازيل', '🇧🇷'),
  _CountryItem('AR', 'Argentina', 'الأرجنتين', '🇦🇷'),
  _CountryItem('TR', 'Turkey', 'تركيا', '🇹🇷'),
];

String _countryCodeForName(String country) {
  final normalized = country.trim().toLowerCase();
  for (final item in _kPopularCountries) {
    if (item.code.toLowerCase() == normalized ||
        item.nameEn.toLowerCase() == normalized ||
        item.nameAr == country.trim()) {
      return item.code;
    }
  }
  return 'SA';
}

Future<_CountryItem?> _showCountryPickerSheet(
  BuildContext context, {
  String currentCountry = '',
}) {
  return showModalBottomSheet<_CountryItem?>(
    context: context,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = _kPopularCountries.where((c) {
            final q = query.trim().toLowerCase();
            if (q.isEmpty) return true;
            return c.nameEn.toLowerCase().contains(q) ||
                c.nameAr.contains(q) ||
                c.code.toLowerCase().contains(q);
          }).toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.public_rounded,
                      color: _productionPrimary(context),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      abuText(context, 'Select Country', 'اختر الدولة'),
                      style: _display(20),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: abuText(
                      context,
                      'Search country…',
                      'ابحث عن الدولة…',
                    ),
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (val) => setSheetState(() => query = val),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        final label = abuText(
                          context,
                          item.nameEn,
                          item.nameAr,
                        );
                        final isSelected =
                            currentCountry == item.nameEn ||
                            currentCountry == item.code;
                        return ListTile(
                          leading: _CountryFlagWidget(
                            country: item.nameEn,
                            flagEmoji: item.flag,
                            size: 22,
                          ),
                          title: Text(
                            label,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: _productionPrimary(context),
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(sheetContext).pop(item);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ProductionOnboarding extends StatefulWidget {
  const _ProductionOnboarding({required this.repository, required this.user});
  final ProductionRepository repository;
  final User user;
  @override
  State<_ProductionOnboarding> createState() => _ProductionOnboardingState();
}

class _ProductionOnboardingState extends State<_ProductionOnboarding> {
  final username = TextEditingController();
  final displayName = TextEditingController();
  final ImagePicker imagePicker = ImagePicker();
  String selectedCountry = 'Saudi Arabia';
  String selectedCountryCode = 'SA';
  String selectedCountryFlag = '🇸🇦';
  String team = 'Barcelona';
  String teamLogo = '';
  String avatarUrl = '';
  bool uploadingAvatar = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    displayName.text = widget.user.displayName ?? '';
    avatarUrl = (widget.user.photoURL ?? '').trim();
    final email = widget.user.email ?? '';
    if (email.contains('@')) {
      final handle = email
          .split('@')
          .first
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
      if (handle.length >= 3) {
        username.text = handle.toLowerCase();
      }
    }
    _autoDetectLocationAndCountry();
    NotificationService.instance.initialize(apiRepo: widget.repository.apiRepo);
  }

  Future<void> _autoDetectLocationAndCountry() async {
    try {
      final detected = await LocationService.detectUserCountry();
      if (mounted) {
        setState(() {
          selectedCountry = detected.nameEn;
          selectedCountryCode = detected.code;
          selectedCountryFlag = detected.flag;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    username.dispose();
    displayName.dispose();
    super.dispose();
  }

  Future<void> _openCountryPicker() async {
    final picked = await _showCountryPickerSheet(
      context,
      currentCountry: selectedCountry,
    );
    if (picked != null && mounted) {
      setState(() {
        selectedCountry = picked.nameEn;
        selectedCountryCode = picked.code;
        selectedCountryFlag = picked.flag;
      });
    }
  }

  Future<void> _openTeamSearchModal() async {
    final searchController = TextEditingController();
    List<FootballTeamAsset> searchResults = const [];
    bool searching = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                MediaQuery.viewInsetsOf(context).bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sports_soccer_rounded,
                        color: _productionPrimary(context),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        abuText(
                          context,
                          'Search Any Football Club',
                          'ابحث عن أي نادٍ كروي',
                        ),
                        style: _display(18),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: abuText(
                        context,
                        'Type club name (e.g. Arsenal, Al Ahly, PSG)…',
                        'اكتب اسم النادي (مثال: أرسنال، الأهلي، باريس)…',
                      ),
                      prefixIcon: Icon(Icons.search_rounded),
                      suffixIcon: searching
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _productionPrimary(context),
                                ),
                              ),
                            )
                          : null,
                    ),
                    onSubmitted: (query) async {
                      if (query.trim().isEmpty) return;
                      setSheetState(() => searching = true);
                      final results = await widget.repository.searchTeams(
                        query.trim(),
                      );
                      if (mounted) {
                        setSheetState(() {
                          searchResults = results;
                          searching = false;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: searchResults.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  searching
                                      ? abuText(
                                          context,
                                          'Searching clubs…',
                                          'جارٍ البحث عن الأندية…',
                                        )
                                      : abuText(
                                          context,
                                          'Type club name and press enter to search',
                                          'اكتب اسم النادي واضغط بحث لعرض النتائج من قاعدة البيانات',
                                        ),
                                  style: TextStyle(color: _muted),
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: searchResults.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = searchResults[i];
                                return ListTile(
                                  leading: _ProductionTeamBadge(
                                    team: item.name,
                                    source: item.badgeUrl,
                                    size: 36,
                                  ),
                                  title: Text(
                                    item.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.league} ${item.country.isNotEmpty ? "· ${item.country}" : ""}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _muted,
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: _productionPrimary(context),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      team = item.name;
                                      teamLogo = item.badgeUrl;
                                    });
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickAvatar() async {
    if (busy || uploadingAvatar) return;
    setState(() {
      uploadingAvatar = true;
      error = null;
    });
    try {
      final image = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image == null) return;
      final uploaded = await widget.repository.uploadAvatar(image);
      if (mounted) setState(() => avatarUrl = uploaded.trim());
    } catch (exception) {
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => uploadingAvatar = false);
    }
  }

  Future<void> submit() async {
    final normalizedUsername = username.text.trim();
    final normalizedDisplayName = displayName.text.trim();
    if (normalizedUsername.length < 3 ||
        normalizedDisplayName.length < 2 ||
        team.trim().isEmpty ||
        selectedCountry.trim().isEmpty ||
        avatarUrl.trim().isEmpty) {
      setState(() {
        error = abuText(
          context,
          'Complete your name, username, club, country and profile photo before continuing.',
          'أكمل الاسم واسم المستخدم والنادي والدولة وصورة الملف الشخصي قبل المتابعة.',
        );
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.completeOnboarding(
        username: normalizedUsername,
        displayName: normalizedDisplayName,
        country: selectedCountry,
        countryCode: selectedCountryCode,
        supportedTeam: team,
        supportedTeamLogo: teamLogo,
        avatarUrl: avatarUrl,
      );
    } catch (exception) {
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _CenteredProductionCard(
    icon: Icons.sports_soccer_rounded,
    title: abuText(context, 'COMPLETE YOUR PROFILE', 'أكمل ملفك الشخصي'),
    body: abuText(
      context,
      'Select your club and identity to start competing in the Community.',
      'اختر ناديك وهويتك لتبدأ المنافسة على لوحة صدارة المشجعين.',
    ),
    message: error,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Semantics(
            button: true,
            label: abuText(
              context,
              'Choose a profile photo',
              'اختر صورة للملف الشخصي',
            ),
            child: InkWell(
              onTap: uploadingAvatar || busy ? null : _pickAvatar,
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _surface2,
                      border: Border.all(
                        color: _productionPrimary(context),
                        width: 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarUrl.isNotEmpty
                        ? _ProductionRemoteImage(
                            url: avatarUrl,
                            fit: BoxFit.cover,
                            fallback: Icon(
                              Icons.person_rounded,
                              size: 42,
                              color: _productionPrimary(context),
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: 42,
                            color: _productionPrimary(context),
                          ),
                  ),
                  PositionedDirectional(
                    end: -2,
                    bottom: -2,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _productionPrimary(context),
                        border: Border.all(color: _surface, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: uploadingAvatar
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _ink,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: _ink,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          abuText(
            context,
            avatarUrl.isEmpty
                ? 'Add a profile photo'
                : 'Tap to change profile photo',
            avatarUrl.isEmpty
                ? 'أضف صورة للملف الشخصي'
                : 'اضغط لتغيير صورة الملف الشخصي',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _ClubSelectionCard(
                teamName: 'Barcelona',
                label: abuText(context, 'FC Barcelona', 'برشلونة'),
                selected: team == 'Barcelona',
                primaryColor: const Color(0xFF1877F2),
                secondaryColor: const Color(0xFFA50044),
                onTap: busy
                    ? null
                    : () => setState(() {
                        team = 'Barcelona';
                        teamLogo = '';
                      }),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ClubSelectionCard(
                teamName: 'Real Madrid',
                label: abuText(context, 'Real Madrid', 'ريال مدريد'),
                selected: team == 'Real Madrid',
                primaryColor: const Color(0xFFFFD700),
                secondaryColor: const Color(0xFF5E6AD2),
                onTap: busy
                    ? null
                    : () => setState(() {
                        team = 'Real Madrid';
                        teamLogo = '';
                      }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (team != 'Barcelona' && team != 'Real Madrid') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _productionPrimary(context).withValues(alpha: .6),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                _ProductionTeamBadge(team: team, source: teamLogo, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abuText(context, 'Selected Club', 'النادي المختار'),
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        team,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.check_circle_rounded,
                  color: _productionPrimary(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: busy ? null : _openTeamSearchModal,
          icon: Icon(Icons.search_rounded, size: 18),
          label: Text(
            abuText(context, 'SEARCH ANOTHER CLUB ➔', 'ابحث عن نادٍ آخر ➔'),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _productionPrimary(context),
            side: BorderSide(
              color: _productionPrimary(context).withValues(alpha: .5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: username,
          decoration: InputDecoration(
            labelText: abuText(context, 'Unique username', 'اسم مستخدم فريد'),
            prefixText: '@',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: displayName,
          decoration: InputDecoration(
            labelText: abuText(context, 'Display name', 'الاسم الظاهر'),
            prefixIcon: Icon(Icons.badge_rounded),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: busy ? null : _openCountryPicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                _CountryFlagWidget(
                  country: selectedCountry,
                  flagEmoji: selectedCountryFlag,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abuText(context, 'Country', 'الدولة'),
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedCountry,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _productionPrimary(context),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: busy ? null : submit,
        style: FilledButton.styleFrom(
          backgroundColor: _productionPrimary(context),
          foregroundColor: _ink,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          busy
              ? abuText(context, 'SAVING…', 'جارٍ الحفظ…')
              : abuText(context, 'ENTER ABU 3MEER ➔', 'دخول دوري أبو عمير ➔'),
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8),
        ),
      ),
      TextButton(
        onPressed: busy ? null : widget.repository.signOut,
        child: Text(abuText(context, 'SIGN OUT', 'تسجيل الخروج')),
      ),
    ],
  );
}

class _ClubSelectionCard extends StatelessWidget {
  const _ClubSelectionCard({
    required this.teamName,
    required this.label,
    required this.selected,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onTap,
  });

  final String teamName;
  final String label;
  final bool selected;
  final Color primaryColor;
  final Color secondaryColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? [
                  primaryColor.withValues(alpha: .28),
                  secondaryColor.withValues(alpha: .18),
                  const Color(0xFF131722),
                ]
              : [const Color(0xFF181C26), const Color(0xFF10131B)],
        ),
        border: Border.all(
          color: selected ? primaryColor : Colors.white.withValues(alpha: .12),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: .32),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            child: Column(
              children: [
                _ProductionTeamBadge(team: teamName, size: 58),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: selected ? Colors.white : _muted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? primaryColor.withValues(alpha: .22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    selected
                        ? abuText(context, 'SELECTED', 'محدد')
                        : abuText(context, 'SELECT', 'اختيار'),
                    style: TextStyle(
                      color: selected ? primaryColor : _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredProductionCard extends StatelessWidget {
  const _CenteredProductionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.content,
    this.message,
  });
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  final Widget? content;
  final String? message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _PitchBackdrop()),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(icon, color: _productionPrimary(context), size: 42),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: _display(30),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, height: 1.5),
                      ),
                      if (content != null) ...[
                        const SizedBox(height: 22),
                        content!,
                      ],
                      if (message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _gold, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ...actions.map(
                        (action) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: action,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProductionFailure extends StatelessWidget {
  const _ProductionFailure({
    this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final String? title;
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => _CenteredProductionCard(
    icon: Icons.cloud_off_rounded,
    title:
        title ??
        abuText(context, 'WE COULD NOT LOAD YOUR ACCOUNT', 'تعذر تحميل حسابك'),
    body: message,
    actions: [
      FilledButton(
        onPressed: onRetry,
        child: Text(abuText(context, 'TRY AGAIN', 'حاول مجدداً')),
      ),
      TextButton(
        onPressed: onSignOut,
        child: Text(abuText(context, 'SIGN OUT', 'تسجيل الخروج')),
      ),
    ],
  );
}

const int _homeShellPageIndex = 0;
const int _predictShellPageIndex = 1;
const int _challengesShellPageIndex = 2;
const int _exclusiveShellPageIndex = 3;
const int _leaderboardShellPageIndex = 4;
const int _profileShellPageIndex = 5;
const int _settingsShellPageIndex = 6;
const List<int> _mobileShellPageIndexes = <int>[
  _homeShellPageIndex,
  _predictShellPageIndex,
  _challengesShellPageIndex,
  _exclusiveShellPageIndex,
  _profileShellPageIndex,
];

class _ProductionShell extends StatefulWidget {
  const _ProductionShell({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionShell> createState() => _ProductionShellState();
}

class _ProductionShellState extends State<_ProductionShell>
    with WidgetsBindingObserver {
  int index = _homeShellPageIndex;
  final Set<int> _visitedPageIndexes = <int>{_homeShellPageIndex};
  StreamSubscription<LaunchAnnouncement?>? announcementSubscription;
  StreamSubscription<Map<String, dynamic>>? notificationTapSubscription;
  StreamSubscription<Map<String, dynamic>>? foregroundNotificationSubscription;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listenForLaunchAnnouncements());
    notificationTapSubscription = NotificationService.instance.notificationTaps
        .listen(_handleNotificationTap);
    foregroundNotificationSubscription = NotificationService
        .instance
        .foregroundNotifications
        .listen(_handleForegroundNotification);
    final pendingTap = NotificationService.instance
        .takePendingNotificationTap();
    if (pendingTap != null) _handleNotificationTap(pendingTap);
    if (!widget.profile.isGuest) {
      widget.repository
          .checkInDailyStreak(widget.profile.uid)
          .then((pointsAwarded) {
            if (pointsAwarded > 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1B2A1E),
                  content: Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          abuText(
                            context,
                            'Daily login streak updated! +$pointsAwarded XP',
                            'تم تحديث سلسلة الدخول اليومي! +$pointsAwarded XP',
                          ),
                          style: TextStyle(
                            color: _productionPrimary(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          })
          .catchError((Object error) {
            debugPrint(
              '[Streak] Startup check-in could not be completed: $error',
            );
          });

      widget.repository
          .checkUnseenCompletedPredictions(
            widget.profile.uid,
            isYouTubeMember: widget.profile.isYouTubeMember,
          )
          .then((outcomes) {
            if (outcomes.isNotEmpty && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  for (final outcome in outcomes) {
                    _showMatchPredictionResultAnnouncementDialog(
                      context,
                      outcome,
                      repository: widget.repository,
                    );
                  }
                }
              });
            }
          });
    }
  }

  Future<void> _listenForLaunchAnnouncements() async {
    // Refresh before subscribing so a reset performed on another device can
    // never replay an old cached popup during shell construction.
    try {
      await widget.repository.refreshLaunchAnnouncement(force: true);
    } catch (error, stackTrace) {
      // Always subscribe. A temporary startup outage must not permanently
      // disable launch announcements for the lifetime of this shell.
      debugPrint('[Announcement] Startup refresh failed: $error\n$stackTrace');
    }
    if (!mounted) return;
    announcementSubscription = widget.repository
        .watchLaunchAnnouncement()
        .listen(
          (announcement) {
            if (announcement == null || !mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) showLaunchAnnouncement(context, announcement);
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('[Announcement] Refresh failed: $error');
          },
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    announcementSubscription?.cancel();
    notificationTapSubscription?.cancel();
    foregroundNotificationSubscription?.cancel();
    super.dispose();
  }

  void _handleForegroundNotification(Map<String, dynamic> data) {
    final route = (data['route'] ?? '').toString().trim().toLowerCase();
    final destination = switch (route) {
      '/exclusive' => _exclusiveShellPageIndex,
      '/challenges' => _challengesShellPageIndex,
      '/predict' => _predictShellPageIndex,
      _ => null,
    };
    if (destination != null) _refreshShellPage(destination);
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final route = (data['route'] ?? '').toString().trim().toLowerCase();
    final destination = switch (route) {
      '/exclusive' => _exclusiveShellPageIndex,
      '/challenges' => _challengesShellPageIndex,
      '/predict' => _predictShellPageIndex,
      _ => _homeShellPageIndex,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectShellPage(destination);
    });
  }

  void _selectShellPage(int value) {
    if (!mounted) return;
    setState(() => index = value);
    _refreshShellPage(value);
  }

  void _refreshShellPage(int value) {
    if (value == _challengesShellPageIndex) {
      _runProductionBackgroundTask(
        widget.repository.refreshChallenges(force: true),
        'Challenges',
      );
      _runProductionBackgroundTask(
        widget.repository.refreshPlayerCards(widget.profile.uid, force: true),
        'PlayerCards',
      );
    } else if (value == _exclusiveShellPageIndex) {
      _runProductionBackgroundTask(
        widget.repository.refreshExclusiveVideos(force: true),
        'ExclusiveVideos',
      );
    } else if (value == _predictShellPageIndex) {
      // A result push can arrive while the prediction replay resource still
      // contains its pre-settlement `pending` snapshot. Refresh PostgreSQL-
      // backed matches and prediction history before the fan opens the card.
      _runProductionBackgroundTask(
        widget.repository.refreshActiveResources(
          uid: widget.profile.uid,
          force: true,
        ),
        'Predictions',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null ||
        DateTime.now().difference(backgroundedAt) <
            const Duration(seconds: 30)) {
      return;
    }
    if (!widget.profile.isGuest) {
      _runProductionBackgroundTask(
        widget.repository.checkInDailyStreak(widget.profile.uid).then((_) {}),
        'StreakResume',
      );
    }
    _runProductionBackgroundTask(
      widget.repository.refreshActiveResources(
        uid: widget.profile.isGuest ? null : widget.profile.uid,
        force: true,
      ),
      'AppResume',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep already visited tabs mounted to preserve scroll position and avoid
    // a blank rebuild flash, without starting every tab's streams on launch.
    _visitedPageIndexes.add(index);
    final profile = widget.profile;
    final pages = <Widget>[
      _ProductionHome(
        repository: widget.repository,
        profile: profile,
        onOpenStreak: () => _showStreakGoals(context, profile),
        onOpenLeaderboard: () => _selectShellPage(_leaderboardShellPageIndex),
      ),
      _ProductionMatches(repository: widget.repository, profile: profile),
      _ProductionChallenges(repository: widget.repository, profile: profile),
      ExclusiveVideosView(repository: widget.repository, profile: profile),
      _ProductionLeaderboard(repository: widget.repository, profile: profile),
      _ProductionProfile(repository: widget.repository, profile: profile),
      _ProductionSettings(repository: widget.repository, profile: profile),
      if (profile.canManageContent)
        _ProductionAdmin(repository: widget.repository, profile: profile),
    ];
    if (index >= pages.length) index = _homeShellPageIndex;
    final items = <(IconData, String)>[
      (Icons.grid_view_rounded, abuText(context, 'Home', 'الرئيسية')),
      (Icons.sports_soccer_rounded, abuText(context, 'Predict', 'توقع')),
      (Icons.bolt_rounded, abuText(context, 'Challenges', 'التحديات')),
      (
        Icons.play_circle_fill_rounded,
        abuText(context, 'Exclusive', 'فيديوهات حصرية'),
      ),
      (Icons.leaderboard_rounded, abuText(context, 'Leaders', 'الترتيب')),
      (Icons.person_rounded, abuText(context, 'Profile', 'حسابي')),
      (Icons.settings_rounded, abuText(context, 'Settings', 'الإعدادات')),
      if (profile.canManageContent)
        (
          Icons.admin_panel_settings_rounded,
          abuText(context, 'Admin Studio', 'استوديو المشرف'),
        ),
    ];
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final desktop = viewportWidth >= 1100;
    final narrowHeader = !desktop && viewportWidth < 400;
    final avatarMenuIndexes = List<int>.generate(items.length, (value) => value)
        .where((value) => !_mobileShellPageIndexes.contains(value))
        .toList(growable: false);
    final mobileSelected = _mobileShellPageIndexes.indexOf(index);
    final initials = profile.displayName.isNotEmpty
        ? profile.displayName.trim()[0].toUpperCase()
        : 'A';
    return AdaptiveLiquidGlassLayer(
      // A full-screen fragment-filter layer causes transient black/blank frames
      // on some Impeller and Android GPU combinations while scrolling. The
      // individual glass controls already render their own clipped blur, so a
      // lightweight pass-through root is both faster and visually identical.
      quality: GlassQuality.minimal,
      settings: const LiquidGlassSettings(
        thickness: 24,
        blur: 8,
        refractiveIndex: 1.54,
      ),
      child: Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: narrowHeader ? 58 : 62,
                titleSpacing: narrowHeader ? 10 : 16,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF090D14)
                    : _lightSurface,
                title: Row(
                  children: [_BrandHeaderLogo(height: narrowHeader ? 34 : 40)],
                ),
                actions: [
                  if (profile.isGuest)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: _Pill(
                        icon: Icons.login_rounded,
                        text: abuText(context, 'SIGN IN', 'تسجيل الدخول'),
                        color: Theme.of(context).brightness == Brightness.dark
                            ? _productionPrimary(context)
                            : _lightPrimary,
                        compact: true,
                        onTap: () => showAuthModal(context, widget.repository),
                      ),
                    )
                  else ...[
                    _StreakPill(
                      streak: profile.currentStreak,
                      onTap: () => _showStreakGoals(context, profile),
                      compact: narrowHeader,
                    ),
                    SizedBox(width: narrowHeader ? 4 : 6),
                    _Pill(
                      icon: Icons.stars_rounded,
                      text: '${profile.totalPoints} XP',
                      color: Theme.of(context).brightness == Brightness.dark
                          ? _productionPrimary(context)
                          : _lightPrimary,
                      compact: true,
                      onTap: () => _selectShellPage(_leaderboardShellPageIndex),
                    ),
                    SizedBox(width: narrowHeader ? 5 : 8),
                    PopupMenuButton<int>(
                      key: const ValueKey<String>('header-avatar-menu'),
                      tooltip: abuText(
                        context,
                        'More account features',
                        'المزيد من ميزات الحساب',
                      ),
                      position: PopupMenuPosition.under,
                      onSelected: _selectShellPage,
                      itemBuilder: (context) => <PopupMenuEntry<int>>[
                        for (final itemIndex in avatarMenuIndexes)
                          PopupMenuItem<int>(
                            key: ValueKey<String>(
                              'header-avatar-menu-item-$itemIndex',
                            ),
                            value: itemIndex,
                            child: Row(
                              children: [
                                Icon(items[itemIndex].$1, size: 19),
                                const SizedBox(width: 10),
                                Text(items[itemIndex].$2),
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        width: narrowHeader ? 32 : 36,
                        height: narrowHeader ? 32 : 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _productionPrimary(context)
                                .withValues(alpha: .6),
                            width: 1.5,
                          ),
                          color: _surface2,
                        ),
                        child: ClipOval(
                          child: profile.avatarUrl.isNotEmpty
                              ? _ProductionRemoteImage(
                                  url: profile.avatarUrl,
                                  fit: BoxFit.cover,
                                  fallback: Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: _productionPrimary(context),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initials,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: _productionPrimary(context),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: narrowHeader ? 8 : 12),
                ],
              ),
        extendBody: false,
        body: desktop
            ? _ProductionDesktopScaffold(
                items: items,
                selectedIndex: index,
                page: pages[index],
                profile: profile,
                onSelect: _selectShellPage,
                onSignIn: () => showAuthModal(context, widget.repository),
              )
            : IndexedStack(
                index: index,
                sizing: StackFit.expand,
                children: List<Widget>.generate(
                  pages.length,
                  (pageIndex) => !_visitedPageIndexes.contains(pageIndex)
                      ? const SizedBox.shrink()
                      : TickerMode(
                          enabled: pageIndex == index,
                          child: RepaintBoundary(
                            key: PageStorageKey<String>(
                              'production-page-$pageIndex',
                            ),
                            child: pages[pageIndex],
                          ),
                        ),
                ),
              ),
        bottomNavigationBar: desktop
            ? null
            : _LiquidGlassNavBar(
                selectedIndex: mobileSelected < 0
                    ? _homeShellPageIndex
                    : mobileSelected,
                onSelect: (value) =>
                    _selectShellPage(_mobileShellPageIndexes[value]),
                items: _mobileShellPageIndexes
                    .map((itemIndex) => items[itemIndex])
                    .toList(),
              ),
      ),
    );
  }
}

class _LiquidGlassNavBar extends StatelessWidget {
  const _LiquidGlassNavBar({
    required this.selectedIndex,
    required this.onSelect,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final primary = _productionPrimary(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // glass_liquid_navbar lays out and animates its indicator in physical LTR
    // coordinates. A surrounding RTL Directionality reverses the Row without
    // reversing the indicator calculation, which made the glow appear under a
    // different tab. Feed it an explicitly visual list/index instead.
    final visualItems = rtl ? items.reversed.toList() : items;
    final safeSelectedIndex = selectedIndex.clamp(0, items.length - 1);
    final visualSelectedIndex = rtl
        ? items.length - 1 - safeSelectedIndex
        : safeSelectedIndex;
    final theme = dark
        ? glass_nav.LiquidGlassTheme.dark(
            glassColor: const Color(0xB8141A22),
            glassBorderColor: Colors.white.withValues(alpha: .22),
            selectedColor: primary,
            unselectedColor: const Color(0xFF9AA5B4),
            indicatorColor: primary.withValues(alpha: .16),
            indicatorBlur: 10,
            glassBlur: 24,
            borderRadius: 25,
            pillHeight: 54,
            horizontalPadding: 12,
            bottomSafeAreaPadding: 0,
            iconSize: 21,
            shadowBlurRadius: 24,
            shadowOffset: const Offset(0, 5),
            labelStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .1,
            ),
          )
        : glass_nav.LiquidGlassTheme.light(
            glassColor: Colors.white.withValues(alpha: .82),
            glassBorderColor: _lightPrimary.withValues(alpha: .22),
            selectedColor: _lightPrimary,
            unselectedColor: _lightMuted,
            indicatorColor: _lightPrimary.withValues(alpha: .13),
            indicatorBlur: 10,
            glassBlur: 28,
            borderRadius: 25,
            pillHeight: 54,
            horizontalPadding: 12,
            bottomSafeAreaPadding: 0,
            iconSize: 21,
            shadowColor: _lightInk.withValues(alpha: .18),
            shadowBlurRadius: 22,
            shadowOffset: const Offset(0, 5),
            labelStyle: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .1,
            ),
          );

    return Transform.translate(
      offset: const Offset(0, 4),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: glass_nav.LiquidGlassNavbar(
          key: ValueKey('primary-liquid-navbar-$rtl-$dark-${items.length}'),
          currentIndex: visualSelectedIndex,
          onTap: (visualIndex) =>
              onSelect(rtl ? items.length - 1 - visualIndex : visualIndex),
          theme: theme,
          // The package adds this value to the rendered pill height. Keeping it
          // at zero anchors the 54px glass surface directly above the system
          // inset.
          floatingOffset: 0,
          animationDuration: const Duration(milliseconds: 280),
          enableHaptics: true,
          showLabels: true,
          items: [
            for (final item in visualItems)
              glass_nav.LiquidNavItem(
                icon: item.$1,
                activeIcon: item.$1,
                label: item.$2,
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeaderLogo extends StatelessWidget {
  const _BrandHeaderLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: AbuBrand.appName,
    child: Image.asset(
      'assets/branding/logo.png',
      height: height,
      width: height * 2.5,
      fit: BoxFit.contain,
      alignment: AlignmentDirectional.centerStart,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => Text(
        AbuBrand.appName.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: height * .4,
          letterSpacing: .6,
        ),
      ),
    ),
  );
}

class _ProductionDesktopScaffold extends StatelessWidget {
  const _ProductionDesktopScaffold({
    required this.items,
    required this.selectedIndex,
    required this.page,
    required this.profile,
    required this.onSelect,
    required this.onSignIn,
  });

  final List<(IconData, String)> items;
  final int selectedIndex;
  final Widget page;
  final AbuUserProfile profile;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 268,
        color: const Color(0xFF0D1118),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: _BrandHeaderLogo(height: 48),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 10, bottom: 9),
              child: Text(
                abuText(context, 'WORKSPACES', 'مساحات العمل'),
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < items.length;
                    itemIndex++
                  ) ...[
                    if (itemIndex == _leaderboardShellPageIndex ||
                        itemIndex == _settingsShellPageIndex)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                        child: Text(
                          itemIndex == _leaderboardShellPageIndex
                              ? abuText(context, 'ENGAGE', 'التفاعل')
                              : abuText(context, 'TOOLS', 'الأدوات'),
                          style: TextStyle(
                            color: _muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SideItem(
                        icon: items[itemIndex].$1,
                        label: items[itemIndex].$2,
                        selected: itemIndex == selectedIndex,
                        onTap: () => onSelect(itemIndex),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 24),
            if (profile.isGuest)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: _productionPrimary(context).withValues(alpha: .12),
                leading: Icon(
                  Icons.login_rounded,
                  color: _productionPrimary(context),
                ),
                title: Text(
                  abuText(context, 'SIGN IN', 'تسجيل الدخول'),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _productionPrimary(context),
                    fontSize: 13,
                  ),
                ),
                onTap: onSignIn,
              )
            else
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: _surface2,
                leading: CircleAvatar(
                  backgroundColor: _productionPrimary(context),
                  foregroundColor: _ink,
                  child: Text(
                    profile.displayName.isEmpty
                        ? '?'
                        : profile.displayName[0].toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                title: Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '@${profile.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => onSelect(_profileShellPageIndex),
              ),
          ],
        ),
      ),
      const VerticalDivider(width: 1, color: _line),
      Expanded(
        child: Column(
          children: [
            Container(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 34),
              decoration: BoxDecoration(color: Color(0xFF0A0E14)),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[selectedIndex].$2.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        abuText(
                          context,
                          'Live production workspace',
                          'مساحة إنتاج مباشرة',
                        ),
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (profile.isGuest) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _productionPrimary(context),
                        foregroundColor: _ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: onSignIn,
                      icon: Icon(Icons.login_rounded, size: 17),
                      label: Text(
                        abuText(context, 'SIGN IN', 'تسجيل الدخول'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ] else ...[
                    _LiveDot(
                      text: abuText(context, 'LIVE DATA', 'بيانات مباشرة'),
                    ),
                    const SizedBox(width: 10),
                    _Pill(
                      icon: Icons.local_fire_department_rounded,
                      text: abuText(
                        context,
                        '${profile.currentStreak} DAY',
                        '${profile.currentStreak} يوم',
                      ),
                      color: _red,
                      compact: true,
                      onTap: () => _showStreakGoals(context, profile),
                    ),
                    const SizedBox(width: 10),
                    _Pill(
                      icon: Icons.stars_rounded,
                      text: '${profile.totalPoints} XP',
                      color: _gold,
                      compact: true,
                      onTap: () => onSelect(_leaderboardShellPageIndex),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: abuText(context, 'Settings', 'الإعدادات'),
                      onPressed: () => onSelect(_settingsShellPageIndex),
                      icon: Icon(Icons.settings_rounded),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: _line),
            Expanded(child: page),
          ],
        ),
      ),
    ],
  );
}

class _ProductionHome extends StatelessWidget {
  const _ProductionHome({
    required this.repository,
    required this.profile,
    required this.onOpenStreak,
    required this.onOpenLeaderboard,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final VoidCallback onOpenStreak;
  final VoidCallback onOpenLeaderboard;

  @override
  Widget build(BuildContext context) {
    final match = StreamBuilder<List<SavedPrediction>>(
      stream: profile.isGuest
          ? Stream.value(const <SavedPrediction>[])
          : repository.watchPredictionHistory(profile.uid),
      builder: (context, predSnapshot) {
        final predictions = predSnapshot.data ?? const <SavedPrediction>[];
        SavedPrediction? findPrediction(MatchEvent ev) {
          for (final p in predictions) {
            if (p.matchId == ev.id) return p;
            if (p.homeTeam.isNotEmpty &&
                p.awayTeam.isNotEmpty &&
                p.homeTeam.trim().toLowerCase() ==
                    ev.homeTeam.trim().toLowerCase() &&
                p.awayTeam.trim().toLowerCase() ==
                    ev.awayTeam.trim().toLowerCase()) {
              return p;
            }
          }
          return null;
        }

        return StreamBuilder<List<MatchEvent>>(
          stream: repository.watchMatches(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 190);
            }
            if (snapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Matches unavailable',
                  'المباريات غير متاحة',
                ),
                body: productionErrorMessage(snapshot.error!),
              );
            }
            final matches = snapshot.data ?? const <MatchEvent>[];
            final nextMatch = nextHomePredictionMatch(matches);
            if (nextMatch == null) {
              return _ProductionEmpty(
                icon: Icons.event_busy_rounded,
                title: abuText(
                  context,
                  'No prediction is open',
                  'لا توجد توقعات مفتوحة',
                ),
                body: abuText(
                  context,
                  'The next Abu 3meer match event will appear here.',
                  'ستظهر فعالية مباراة أبو عمير القادمة هنا.',
                ),
              );
            }
            // Home keeps the nearest future fixture; the Predict tab owns the
            // complete fixture list and prediction history.
            return _ProductionMatchCard(
              event: nextMatch,
              repository: repository,
              profile: profile,
              prediction: findPrediction(nextMatch),
            );
          },
        );
      },
    );
    return _PageFrame(
      kicker: profile.isYouTubeMember
          ? abuText(
              context,
              'YouTube Member · 2× predictions & video challenges',
              'عضو يوتيوب · ×٢ للتوقعات وتحديات الفيديو',
            )
          : abuText(context, AbuBrand.appName, 'أبو عمير'),
      title: profile.isGuest
          ? abuText(context, AbuBrand.appName, 'أبو عمير')
          : abuText(
              context,
              'Welcome, ${profile.displayName}',
              'مرحباً، ${profile.displayName}',
            ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 850) {
            return Column(
              children: [
                if (profile.isGuest) ...[
                  _GuestWelcomeCard(repository: repository),
                  const SizedBox(height: 16),
                ],
                _ProductionLatestVideoCard(
                  repository: repository,
                  profile: profile,
                ),
                const SizedBox(height: 16),
                _ProductionPointsHero(profile: profile),
                const SizedBox(height: 16),
                _ProductionHomeRankingCard(
                  repository: repository,
                  profile: profile,
                  onOpenLeaderboard: onOpenLeaderboard,
                ),
                const SizedBox(height: 16),
                _ProductionHomeStreakCard(
                  profile: profile,
                  onTap: onOpenStreak,
                ),
                const SizedBox(height: 16),
                match,
              ],
            );
          }
          return Column(
            children: [
              if (profile.isGuest) ...[
                _GuestWelcomeCard(repository: repository),
                const SizedBox(height: 18),
              ],
              _ProductionLatestVideoCard(
                repository: repository,
                profile: profile,
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _ProductionPointsHero(profile: profile),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    flex: 5,
                    child: _ProductionHomeStreakCard(
                      profile: profile,
                      onTap: onOpenStreak,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ProductionHomeRankingCard(
                repository: repository,
                profile: profile,
                onOpenLeaderboard: onOpenLeaderboard,
              ),
              const SizedBox(height: 22),
              match,
            ],
          );
        },
      ),
    );
  }
}

// Kept for potential campaign deep links; challenges themselves belong only
// to the dedicated Challenges tab.
// ignore: unused_element
class _HomeDirectChallengeActionSection extends StatelessWidget {
  const _HomeDirectChallengeActionSection({
    required this.repository,
    required this.profile,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AbuChallenge>>(
      stream: repository.watchChallenges(),
      builder: (context, snapshot) {
        final challenges = snapshot.data ?? const [];
        final openChallenges = challenges.where((c) => c.isOpen).toList();
        if (openChallenges.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flash_on_rounded,
                  color: _productionPrimary(context),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  abuText(
                    context,
                    'ACTIVE CHALLENGES · PLAY DIRECTLY',
                    'تحديات نشطة · تفاعل مباشر',
                  ),
                  style: TextStyle(
                    color: _productionPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _productionPrimary(context).withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    abuText(context, '10 XP EACH', '١٠ نقاط لكل تحدٍ'),
                    style: TextStyle(
                      color: _productionPrimary(context),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final challenge in openChallenges.take(2)) ...[
              _DirectChallengeInlineCard(
                challenge: challenge,
                repository: repository,
                profile: profile,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _DirectChallengeInlineCard extends StatefulWidget {
  const _DirectChallengeInlineCard({
    required this.challenge,
    required this.repository,
    required this.profile,
  });

  final AbuChallenge challenge;
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_DirectChallengeInlineCard> createState() =>
      _DirectChallengeInlineCardState();
}

class _DirectChallengeInlineCardState
    extends State<_DirectChallengeInlineCard> {
  final _controller = TextEditingController();
  bool _submitting = false;
  late bool _solved;

  @override
  void initState() {
    super.initState();
    _solved = widget.challenge.solved;
  }

  @override
  void didUpdateWidget(covariant _DirectChallengeInlineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.challenge.solved) _solved = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.profile.isGuest) {
      await showAuthModal(context, widget.repository);
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await widget.repository.submitChallengeAnswers(
        challenge: widget.challenge,
        answers: {'main': text},
      );
      if (!mounted) return;
      final correct = result['correct'] == true;
      final basePoints = widget.challenge.rewardPoints > 0
          ? widget.challenge.rewardPoints
          : 10;
      final memberEligible = widget.profile.isYouTubeMember;
      final points = result['points'] ?? basePoints * (memberEligible ? 2 : 1);
      final alreadyAwarded = result['alreadyAwarded'] == true;
      if (correct) {
        setState(() => _solved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B2A1E),
            content: Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    abuText(
                      context,
                      alreadyAwarded
                          ? 'Already solved. Your $points XP was awarded earlier.'
                          : 'Correct answer! +$points XP added to your account.',
                      alreadyAwarded
                          ? 'تم حل التحدي سابقاً. تمت إضافة $points نقطة من قبل.'
                          : 'إجابة صحيحة! تمت إضافة +$points نقطة إلى حسابك.',
                    ),
                    style: TextStyle(
                      color: _productionPrimary(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A1B1B),
            content: Row(
              children: [
                const Text('❌', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    abuText(
                      context,
                      'Not correct yet. Check the video carefully and try again!',
                      'إجابة غير صحيحة. راجع الفيديو وحاول مرة أخرى!',
                    ),
                    style: TextStyle(color: _red, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(productionErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final isPlayerCard = challenge.canonicalKind == 'playerCard';
    final isMember = widget.profile.isYouTubeMember;
    final basePoints = challenge.rewardPoints > 0 ? challenge.rewardPoints : 10;
    final memberEligible = isMember;
    final pointsText = memberEligible
        ? '+${basePoints * 2} XP (2×)'
        : '+$basePoints XP';
    final cardTitle = isPlayerCard
        ? abuText(context, 'GUESS THE PLAYER', 'احزر اللاعب')
        : abuText(context, 'SECRET VIDEO PHRASE', 'العبارة السرية في الفيديو');
    final hintText = isPlayerCard
        ? abuText(context, 'Type the player name…', 'اكتب اسم اللاعب…')
        : abuText(context, 'Type the secret phrase…', 'اكتب العبارة السرية…');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _solved
              ? _productionPrimary(context)
              : (isPlayerCard
                    ? const Color(0xFF9B72FF).withValues(alpha: .5)
                    : _productionPrimary(context).withValues(alpha: .4)),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isPlayerCard
                ? const Color(0xFF9B72FF).withValues(alpha: .12)
                : _productionPrimary(context).withValues(alpha: .10),
            _surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (isPlayerCard
                              ? const Color(0xFF9B72FF)
                              : _productionPrimary(context))
                          .withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPlayerCard
                      ? Icons.person_search_rounded
                      : Icons.subtitles_rounded,
                  color: isPlayerCard
                      ? const Color(0xFF9B72FF)
                      : _productionPrimary(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: TextStyle(
                        color: isPlayerCard
                            ? const Color(0xFF9B72FF)
                            : _productionPrimary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      challenge.title.isEmpty
                          ? (isPlayerCard ? 'Guess the Player' : 'Video Riddle')
                          : challenge.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _gold.withValues(alpha: .4)),
                ),
                child: Text(
                  pointsText,
                  style: TextStyle(
                    color: _gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (challenge.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              challenge.description,
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          if (_solved)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _productionPrimary(context).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _productionPrimary(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: _productionPrimary(context),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    abuText(
                      context,
                      'Challenge completed! Points added.',
                      'تم حل التحدي بنجاح! أضيفت النقاط.',
                    ),
                    style: TextStyle(
                      color: _productionPrimary(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: hintText,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: isPlayerCard
                        ? const Color(0xFF9B72FF)
                        : _productionPrimary(context),
                    foregroundColor: _ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _ink,
                          ),
                        )
                      : Text(
                          abuText(context, 'SUBMIT', 'إرسال'),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                ),
              ],
            ),
          if (challenge.videoUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  final uri = externalHttpUri(challenge.videoUrl);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded, color: _red, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      abuText(
                        context,
                        'Watch YouTube video clue',
                        'شاهد تلميح الفيديو على يوتيوب',
                      ),
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Retained for the optional multi-activity home layout.
// ignore: unused_element
class _HomeActivitiesBanner extends StatelessWidget {
  const _HomeActivitiesBanner({
    required this.repository,
    required this.onOpenStreak,
  });

  final ProductionRepository repository;
  final VoidCallback onOpenStreak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _productionPrimary(context).withValues(alpha: .35),
        ),
        gradient: LinearGradient(
          colors: [
            _productionPrimary(context).withValues(alpha: .12),
            _surface,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _productionPrimary(context).withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bolt_rounded,
              color: _productionPrimary(context),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      abuText(
                        context,
                        'EARN UP TO +140 XP TODAY',
                        'اكسب حتى +١٤٠ نقطة اليوم',
                      ),
                      style: TextStyle(
                        color: _productionPrimary(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: .9,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  abuText(
                    context,
                    'Match Prediction · Video Challenge · Daily Streak',
                    'توقع المباراة · تحدي الفيديو · السلسلة اليومية',
                  ),
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestWelcomeCard extends StatelessWidget {
  const _GuestWelcomeCard({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF142417), Color(0xFF111722)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: _productionPrimary(context).withValues(alpha: .45),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 430;
        final titleAndCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              abuText(context, 'JOIN THE COMMUNITY', 'انضم إلى المجتمع'),
              style: TextStyle(
                color: _productionPrimary(context),
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              abuText(
                context,
                'Sign up or log in to predict matches, enter challenges, and compete on the leaderboard!',
                'أنشئ حسابك أو سجّل الدخول لتتوقع نتائج المباريات وتشارك في التحديات وتتصدر الترتيب!',
              ),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        );
        final signInButton = FilledButton(
          onPressed: () => showAuthModal(context, repository),
          style: FilledButton.styleFrom(
            backgroundColor: _productionPrimary(context),
            foregroundColor: _ink,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          child: Text(
            abuText(context, 'SIGN IN / JOIN', 'تسجيل الدخول / انضم'),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LogoMark(size: 42),
                  const SizedBox(width: 13),
                  Expanded(child: titleAndCopy),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: signInButton),
            ],
          );
        }

        return Row(
          children: [
            const _LogoMark(size: 44),
            const SizedBox(width: 16),
            Expanded(child: titleAndCopy),
            const SizedBox(width: 14),
            signInButton,
          ],
        );
      },
    ),
  );
}

class _ProductionHomeStreakCard extends StatelessWidget {
  const _ProductionHomeStreakCard({required this.profile, required this.onTap});

  final AbuUserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = profile.currentStreak;
    final lastActivity = profile.lastActivityAt;
    final isToday =
        lastActivity != null &&
        DateUtils.isSameDay(lastActivity.toLocal(), DateTime.now());
    const streakMilestones = [3, 7, 14, 30, 60, 100];
    final nextMilestone = streakMilestones.firstWhere(
      (m) => m > active,
      orElse: () => ((active ~/ 30) + 1) * 30,
    );
    int prevMilestone = 0;
    for (final m in streakMilestones) {
      if (m <= active) prevMilestone = m;
    }
    final range = nextMilestone - prevMilestone;
    final milestoneProgress = range > 0
        ? ((active - prevMilestone) / range).clamp(0.0, 1.0)
        : 1.0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: _red,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          abuText(context, 'ACTIVITY STREAK', 'سلسلة النشاط'),
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$active ${abuText(context, active == 1 ? 'day' : 'days', 'يوم')}',
                          style: _display(29, color: _red),
                        ),
                        Text(
                          isToday
                              ? abuText(
                                  context,
                                  'Today is secured · Best ${profile.longestStreak}',
                                  'تم تسجيل نشاط اليوم · الأفضل ${profile.longestStreak}',
                                )
                              : abuText(
                                  context,
                                  'Complete an eligible activity today',
                                  'أكمل نشاطاً مؤهلاً اليوم',
                                ),
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: _productionPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: active == 0 ? 0 : milestoneProgress,
                  minHeight: 7,
                  backgroundColor: _line,
                  color: isToday ? _productionPrimary(context) : _red,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text(
                    abuText(
                      context,
                      isToday ? 'DAILY CHECK-IN COMPLETE' : 'TODAY IS AT RISK',
                      isToday ? 'اكتمل نشاط اليوم' : 'سلسلتك معرضة للخطر',
                    ),
                    style: TextStyle(
                      color: isToday ? _productionPrimary(context) : _red,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    abuText(
                      context,
                      'Next milestone: $nextMilestone days',
                      'المحطة التالية: $nextMilestone يوم',
                    ),
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductionLatestVideoCard extends StatefulWidget {
  const _ProductionLatestVideoCard({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionLatestVideoCard> createState() =>
      _ProductionLatestVideoCardState();
}

class _ProductionLatestVideoCardState
    extends State<_ProductionLatestVideoCard> {
  late Future<LatestVideo> request;

  @override
  void initState() {
    super.initState();
    request = widget.repository.latestVideo();
  }

  void retry() =>
      setState(() => request = widget.repository.latestVideo(refresh: true));

  AbuChallenge? _matchingChallenge(
    LatestVideo video,
    Iterable<AbuChallenge> challenges,
  ) {
    final videoId =
        extractYoutubeVideoId(video.id) ?? extractYoutubeVideoId(video.url);
    if (videoId == null) return null;
    for (final challenge in challenges) {
      if (!challenge.isOpen) continue;
      if (extractYoutubeVideoId(challenge.videoUrl) == videoId) {
        return challenge;
      }
    }
    return null;
  }

  Future<void> _openChallenge(AbuChallenge challenge) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChallengePlayDialog(
      challenge: challenge,
      repository: widget.repository,
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<LatestVideo>(
    future: request,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionSkeleton(height: 230);
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return _ProductionEmpty(
          icon: Icons.youtube_searched_for_rounded,
          title: abuText(
            context,
            'Latest video unavailable',
            'تعذر تحميل أحدث فيديو',
          ),
          body: abuText(
            context,
            'Check the connection and try the channel feed again.',
            'تحقق من الاتصال وحاول تحديث قناة يوتيوب.',
          ),
          actionLabel: abuText(context, 'RETRY', 'إعادة المحاولة'),
          onAction: retry,
        );
      }
      final video = snapshot.data!;
      return StreamBuilder<List<AbuChallenge>>(
        stream: widget.repository.watchChallenges(),
        builder: (context, challengeSnapshot) {
          final challenge = _matchingChallenge(
            video,
            challengeSnapshot.data ?? const <AbuChallenge>[],
          );
          final canPlayChallenge =
              challenge != null &&
              !challenge.solved &&
              challenge.attemptsRemaining > 0 &&
              (!challenge.memberOnly || widget.profile.isYouTubeMember);
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse(video.url),
                mode: LaunchMode.externalApplication,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 680;
                  final image = AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        video.thumbnailUrl.startsWith('assets/')
                            ? Image.asset(video.thumbnailUrl, fit: BoxFit.cover)
                            : _ProductionRemoteImage(
                                url: video.thumbnailUrl,
                                fit: BoxFit.cover,
                                fallback: Image.asset(
                                  'assets/images/latest_abu3meer.jpg',
                                  fit: BoxFit.cover,
                                ),
                              ),
                        if (challenge != null)
                          PositionedDirectional(
                            top: 12,
                            end: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _ink.withValues(alpha: .84),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: _productionPrimary(context)
                                      .withValues(alpha: .7),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: _productionPrimary(context),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    abuText(
                                      context,
                                      'VIDEO CHALLENGE',
                                      'تحدي الفيديو',
                                    ),
                                    style: TextStyle(
                                      color: _productionPrimary(context),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                  final details = Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          abuText(
                            context,
                            'LATEST ABU 3MEER VIDEO',
                            'أحدث فيديو لأبو عمير',
                          ),
                          style: TextStyle(
                            color: _productionPrimary(context),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          video.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: _display(24, height: 1.05),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => launchUrl(
                                  Uri.parse(video.url),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: SizedBox(
                                  width: 155,
                                  height: 42,
                                  child: Lottie.asset(
                                    'assets/animations/youtube.json',
                                    repeat: true,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            if (challenge != null)
                              FilledButton.icon(
                                onPressed: widget.profile.isGuest
                                    ? () => showAuthModal(
                                        context,
                                        widget.repository,
                                      )
                                    : canPlayChallenge
                                    ? () => _openChallenge(challenge)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _productionPrimary(context),
                                  foregroundColor: _ink,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                                icon: Icon(
                                  challenge.solved
                                      ? Icons.check_circle_rounded
                                      : Icons.bolt_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  widget.profile.isGuest
                                      ? abuText(
                                          context,
                                          'SIGN IN TO ANSWER',
                                          'سجّل الدخول للإجابة',
                                        )
                                      : challenge.solved
                                      ? abuText(context, 'COMPLETED', 'مكتمل')
                                      : challenge.memberOnly &&
                                            !widget.profile.isYouTubeMember
                                      ? abuText(
                                          context,
                                          'MEMBERS ONLY',
                                          'للأعضاء فقط',
                                        )
                                      : abuText(
                                          context,
                                          'ANSWER CHALLENGE',
                                          'أجب عن التحدي',
                                        ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (challenge != null) ...[
                          const SizedBox(height: 9),
                          Text(
                            challenge.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                  return compact
                      ? Column(children: [image, details])
                      : Row(
                          children: [
                            Expanded(flex: 5, child: image),
                            Expanded(flex: 4, child: details),
                          ],
                        );
                },
              ),
            ),
          );
        },
      );
    },
  );
}

class _ProductionPointsHero extends StatelessWidget {
  const _ProductionPointsHero({required this.profile});
  final AbuUserProfile profile;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(colors: [Color(0xFF182313), _surface]),
      border: Border.all(
        color: _productionPrimary(context).withValues(alpha: .35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              abuText(context, 'CURRENT POINTS', 'النقاط الحالية'),
              style: TextStyle(
                color: _productionPrimary(context),
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
            const Spacer(),
            if (profile.isYouTubeMember)
              _LiveDot(text: abuText(context, '2× MEMBER', 'عضو ×٢')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${profile.totalPoints}',
          style: _display(50, color: Colors.white),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Metric(
                value: '${profile.monthlyPoints}',
                label: abuText(context, 'THIS MONTH', 'هذا الشهر'),
                color: _productionPrimary(context),
              ),
            ),
            Expanded(
              child: _Metric(
                value: '${profile.seasonPoints}',
                label: abuText(context, 'THIS SEASON', 'هذا الموسم'),
                color: _gold,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProductionHomeRankingCard extends StatefulWidget {
  const _ProductionHomeRankingCard({
    required this.repository,
    required this.profile,
    required this.onOpenLeaderboard,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;
  final VoidCallback onOpenLeaderboard;

  @override
  State<_ProductionHomeRankingCard> createState() =>
      _ProductionHomeRankingCardState();
}

bool _leaderboardEntryBelongsToProfile(
  LeaderboardEntry entry, {
  required String uid,
  required String username,
}) {
  if (uid.isNotEmpty && entry.uid == uid) return true;
  final publicUsername = entry.username.trim().toLowerCase();
  return publicUsername.isNotEmpty &&
      publicUsername == username.trim().toLowerCase();
}

class _ProductionHomeRankingCardState
    extends State<_ProductionHomeRankingCard> {
  LeaderboardPeriod period = LeaderboardPeriod.currentMonth;

  List<RankedLeaderboardEntry> _nearbyEntries(LeaderboardSnapshot snapshot) {
    final entries = snapshot.entries;
    if (entries.isEmpty) return const <RankedLeaderboardEntry>[];
    final currentUser = snapshot.currentUser;
    if (currentUser == null) {
      return entries.take(5).toList(growable: false);
    }
    final index = entries.indexWhere(
      (ranked) => ranked.entry.uid == currentUser.entry.uid,
    );
    if (index < 0) {
      return <RankedLeaderboardEntry>[...entries.take(4), currentUser];
    }
    final count = math.min(5, entries.length);
    final start = math.max(0, math.min(entries.length - count, index - 2));
    return entries.sublist(start, start + count);
  }

  Widget _periodDropdown(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<LeaderboardPeriod>(
        value: period,
        borderRadius: BorderRadius.circular(16),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
        items: [
          DropdownMenuItem(
            value: LeaderboardPeriod.currentMonth,
            child: Text(abuText(context, 'This month', 'هذا الشهر')),
          ),
          DropdownMenuItem(
            value: LeaderboardPeriod.season,
            child: Text(abuText(context, 'This season', 'هذا الموسم')),
          ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => period = value);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<LeaderboardSnapshot>(
    stream: widget.repository.watchLeaderboardView(period: period),
    builder: (context, snapshot) {
      final leaderboard = snapshot.data;
      final currentUser = leaderboard?.currentUser;
      final nearby = leaderboard == null
          ? const <RankedLeaderboardEntry>[]
          : _nearbyEntries(leaderboard);
      final primary = _productionPrimary(context);
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF132012), Color(0xFF101722)],
          ),
          border: Border.all(color: primary.withValues(alpha: .38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    period == LeaderboardPeriod.season
                        ? abuText(context, 'SEASON RANKING', 'ترتيب الموسم')
                        : abuText(context, 'MONTHLY RANKING', 'الترتيب الشهري'),
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                _periodDropdown(context),
              ],
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting &&
                leaderboard == null)
              const _ProductionSkeleton(height: 150)
            else if (snapshot.hasError && leaderboard == null)
              _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Ranking unavailable',
                  'الترتيب غير متاح',
                ),
                body: productionErrorMessage(snapshot.error!),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: primary.withValues(alpha: .28)),
                ),
                child: currentUser == null
                    ? Row(
                        children: [
                          Icon(
                            widget.profile.isGuest
                                ? Icons.login_rounded
                                : Icons.hourglass_empty_rounded,
                            color: primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.profile.isGuest
                                  ? abuText(
                                      context,
                                      'Sign in to see your place in the ranking.',
                                      'سجّل الدخول لمعرفة مركزك في الترتيب.',
                                    )
                                  : abuText(
                                      context,
                                      'Earn XP to receive your first ranking.',
                                      'اجمع XP لتحصل على أول ترتيب لك.',
                                    ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                abuText(context, 'YOU ARE', 'ترتيبك'),
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                '#${currentUser.rank}',
                                style: _display(42, color: primary),
                              ),
                            ],
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentUser.entry.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${currentUser.points} XP · ${leaderboard?.totalPlayers ?? 0} ${abuText(context, 'ranked fans', 'مشجعاً مصنفاً')}',
                                  maxLines: 2,
                                  style: TextStyle(color: _muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              if (nearby.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _surface.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < nearby.length; index++) ...[
                        _HomeRankingEntryRow(
                          ranked: nearby[index],
                          currentUid: widget.profile.uid,
                          currentUsername: widget.profile.username,
                        ),
                        if (index != nearby.length - 1)
                          const Divider(height: 1, color: _line),
                      ],
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: widget.onOpenLeaderboard,
                icon: const Icon(Icons.leaderboard_rounded, size: 17),
                label: Text(
                  abuText(
                    context,
                    'VIEW FULL LEADERBOARD',
                    'عرض الترتيب الكامل',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _HomeRankingEntryRow extends StatelessWidget {
  const _HomeRankingEntryRow({
    required this.ranked,
    required this.currentUid,
    required this.currentUsername,
  });

  final RankedLeaderboardEntry ranked;
  final String currentUid;
  final String currentUsername;

  @override
  Widget build(BuildContext context) {
    final entry = ranked.entry;
    final mine = _leaderboardEntryBelongsToProfile(
      entry,
      uid: currentUid,
      username: currentUsername,
    );
    final initials = entry.displayName.trim().isEmpty
        ? '?'
        : entry.displayName.trim()[0].toUpperCase();
    return ColoredBox(
      color: mine
          ? _productionPrimary(context).withValues(alpha: .12)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 37,
              child: Text(
                '#${ranked.rank}',
                style: TextStyle(
                  color: mine ? _productionPrimary(context) : _muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: mine ? _productionPrimary(context) : _line,
                ),
                color: _surface2,
              ),
              clipBehavior: Clip.antiAlias,
              child: entry.avatarUrl.isEmpty
                  ? Center(
                      child: Text(
                        initials,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    )
                  : _ProductionRemoteImage(
                      url: entry.avatarUrl,
                      fit: BoxFit.cover,
                      fallback: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mine
                    ? abuText(
                        context,
                        '${entry.displayName} (YOU)',
                        '${entry.displayName} (أنت)',
                      )
                    : entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine ? _productionPrimary(context) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${ranked.points} XP',
              style: TextStyle(
                color: mine ? _productionPrimary(context) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PredictionHistoryFilter { all, pending, resolved }

@visibleForTesting
MatchEvent? nextHomePredictionMatch(List<MatchEvent> events, {DateTime? now}) {
  final current = now ?? DateTime.now();
  const terminalStatuses = <String>{
    'completed',
    'finished',
    'archived',
    'cancelled',
    'postponed',
    'disabled',
  };
  final future =
      events
          .where(
            (event) =>
                event.kickoffAt.isAfter(current) &&
                !terminalStatuses.contains(event.status.toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
  return future.firstOrNull;
}

@visibleForTesting
DateTime initialMatchCalendarDay(List<MatchEvent> events, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateUtils.dateOnly(current);
  const terminalStatuses = <String>{
    'completed',
    'archived',
    'cancelled',
    'postponed',
    'disabled',
  };
  final actionable =
      events
          .where(
            (event) =>
                !terminalStatuses.contains(event.status.toLowerCase()) &&
                event.kickoffAt.toLocal().isAfter(current) &&
                event.predictionClosesAt.toLocal().isAfter(current),
          )
          .toList()
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
  if (actionable.isNotEmpty) {
    return DateUtils.dateOnly(actionable.first.kickoffAt.toLocal());
  }
  final upcoming =
      events
          .where(
            (event) =>
                !DateUtils.dateOnly(event.kickoffAt.toLocal()).isBefore(today),
          )
          .toList()
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
  return upcoming.isEmpty
      ? today
      : DateUtils.dateOnly(upcoming.first.kickoffAt.toLocal());
}

@visibleForTesting
List<MatchEvent> matchEventsOnDay(List<MatchEvent> events, DateTime day) {
  final matches =
      events
          .where((event) => DateUtils.isSameDay(event.kickoffAt.toLocal(), day))
          .toList()
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
  return matches;
}

@visibleForTesting
List<DateTime> buildMatchCalendarDays(
  List<MatchEvent> events, {
  DateTime? now,
}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  var start = today.subtract(const Duration(days: 3));
  var end = today.add(const Duration(days: 30));
  final relevantDates = events
      .map((event) => DateUtils.dateOnly(event.kickoffAt.toLocal()))
      .where(
        (day) =>
            !day.isBefore(today.subtract(const Duration(days: 30))) &&
            !day.isAfter(today.add(const Duration(days: 90))),
      );
  for (final day in relevantDates) {
    if (day.isBefore(start)) start = day;
    if (day.isAfter(end)) end = day;
  }
  return List<DateTime>.generate(
    end.difference(start).inDays + 1,
    (index) => start.add(Duration(days: index)),
  );
}

class _MatchDayStrip extends StatefulWidget {
  const _MatchDayStrip({
    required this.events,
    required this.selectedDay,
    required this.onSelected,
  });

  final List<MatchEvent> events;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;

  @override
  State<_MatchDayStrip> createState() => _MatchDayStripState();
}

class _MatchDayStripState extends State<_MatchDayStrip> {
  final ScrollController controller = ScrollController();
  DateTime? lastCenteredDay;
  DateTime? pendingCenteredDay;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void centerSelectedDay(List<DateTime> days) {
    if (DateUtils.isSameDay(lastCenteredDay, widget.selectedDay) ||
        DateUtils.isSameDay(pendingCenteredDay, widget.selectedDay)) {
      return;
    }
    final index = days.indexWhere(
      (day) => DateUtils.isSameDay(day, widget.selectedDay),
    );
    if (index < 0) return;
    final selectedDay = widget.selectedDay;
    final initialCenter = lastCenteredDay == null;
    pendingCenteredDay = selectedDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pendingCenteredDay = null;
      if (!mounted || !controller.hasClients) return;
      final viewport = controller.position.viewportDimension;
      const dayExtent = 58.0;
      final target = (index * dayExtent) - (viewport / 2) + 26;
      final offset = target
          .clamp(0.0, controller.position.maxScrollExtent)
          .toDouble();
      lastCenteredDay = selectedDay;
      if (initialCenter) {
        controller.jumpTo(offset);
      } else {
        controller.animateTo(
          offset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = buildMatchCalendarDays(widget.events);
    centerSelectedDay(days);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = dark ? _productionPrimary(context) : _lightPrimary;
    final textColor = dark ? Colors.white : _lightInk;
    final muted = dark ? _muted : _lightMuted;
    final line = dark ? _line : _lightLine;
    final surface = dark ? _surface : _lightSurface;
    return Semantics(
      container: true,
      label: abuText(context, 'Match calendar', 'تقويم المباريات'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.swipe_rounded, color: primary, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  abuText(
                    context,
                    'SWIPE TO CHOOSE A MATCH DAY',
                    'مرّر لاختيار يوم المباراة',
                  ),
                  style: TextStyle(
                    color: primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 76,
            child: ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(end: 12),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final day = days[index];
                final selected = DateUtils.isSameDay(day, widget.selectedDay);
                final matches = matchEventsOnDay(widget.events, day);
                final weekday = abuText(
                  context,
                  const [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ][day.weekday - 1],
                  const [
                    'الاثنين',
                    'الثلاثاء',
                    'الأربعاء',
                    'الخميس',
                    'الجمعة',
                    'السبت',
                    'الأحد',
                  ][day.weekday - 1],
                );
                return Semantics(
                  selected: selected,
                  button: true,
                  label: '$weekday ${day.day}',
                  child: InkWell(
                    key: ValueKey('match-day-${day.toIso8601String()}'),
                    onTap: () => widget.onSelected(day),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 52,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? primary : surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? primary : line,
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: !dark && selected
                            ? [
                                BoxShadow(
                                  color: primary.withValues(alpha: .2),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            weekday,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? (dark ? _ink : Colors.white)
                                  : muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: selected
                                  ? (dark ? _ink : Colors.white)
                                  : textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          if (matches.isEmpty)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? (dark ? _ink : Colors.white54)
                                    : line,
                              ),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _ProductionTeamBadge(
                                  team: matches.first.homeTeam,
                                  source: matches.first.homeLogoUrl,
                                  size: 15,
                                ),
                                const SizedBox(width: 1),
                                _ProductionTeamBadge(
                                  team: matches.first.awayTeam,
                                  source: matches.first.awayLogoUrl,
                                  size: 15,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionMatches extends StatefulWidget {
  const _ProductionMatches({required this.repository, required this.profile});

  final ProductionRepository repository;

  final AbuUserProfile profile;

  @override
  State<_ProductionMatches> createState() => _ProductionMatchesState();
}

class _ProductionMatchesState extends State<_ProductionMatches> {
  _PredictionHistoryFilter historyFilter = _PredictionHistoryFilter.all;
  DateTime? selectedMatchDay;
  late final Stream<List<SavedPrediction>> _predictionStream;
  late final Stream<List<MatchEvent>> _matchesStream;

  @override
  void initState() {
    super.initState();
    _predictionStream = widget.repository.watchPredictionHistory(
      widget.profile.uid,
    );
    _matchesStream = widget.repository.watchMatches();
  }

  List<SavedPrediction> _filteredPredictions(
    List<SavedPrediction> predictions,
  ) => switch (historyFilter) {
    _PredictionHistoryFilter.all => predictions,
    _PredictionHistoryFilter.pending =>
      predictions
          .where((prediction) => !_predictionIsResolved(prediction))
          .toList(),
    _PredictionHistoryFilter.resolved =>
      predictions.where(_predictionIsResolved).toList(),
  };

  Widget _historyFilter(BuildContext context) =>
      SegmentedButton<_PredictionHistoryFilter>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: _PredictionHistoryFilter.all,
            label: Text(abuText(context, 'ALL', 'الكل')),
          ),
          ButtonSegment(
            value: _PredictionHistoryFilter.pending,
            label: Text(abuText(context, 'PENDING', 'قيد الانتظار')),
          ),
          ButtonSegment(
            value: _PredictionHistoryFilter.resolved,
            label: Text(abuText(context, 'RESOLVED', 'محسومة')),
          ),
        ],
        selected: {historyFilter},
        onSelectionChanged: (selection) =>
            setState(() => historyFilter = selection.first),
      );

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'Pick · lock · track every result',
      'توقع · ثبّت · تابع كل نتيجة',
    ),
    title: abuText(context, 'Predictions', 'التوقعات'),
    child: StreamBuilder<List<SavedPrediction>>(
      stream: _predictionStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Column(
            children: [
              _ProductionSkeleton(height: 260),
              SizedBox(height: 18),
              _ProductionSkeleton(height: 220),
            ],
          );
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Could not load predictions',
              'تعذر تحميل التوقعات',
            ),
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final predictions = snapshot.data ?? const <SavedPrediction>[];
        SavedPrediction? findPrediction(MatchEvent ev) {
          for (final p in predictions) {
            if (p.matchId == ev.id) return p;
            if (p.homeTeam.isNotEmpty &&
                p.awayTeam.isNotEmpty &&
                p.homeTeam.trim().toLowerCase() ==
                    ev.homeTeam.trim().toLowerCase() &&
                p.awayTeam.trim().toLowerCase() ==
                    ev.awayTeam.trim().toLowerCase()) {
              return p;
            }
          }
          return null;
        }

        return StreamBuilder<List<MatchEvent>>(
          stream: _matchesStream,
          builder: (context, matchesSnapshot) {
            final waiting =
                matchesSnapshot.connectionState == ConnectionState.waiting &&
                !matchesSnapshot.hasData;
            if (waiting) {
              return const Column(
                children: [
                  _ProductionSkeleton(height: 96),
                  SizedBox(height: 22),
                  _ProductionSkeleton(height: 260),
                  SizedBox(height: 30),
                  _ProductionSkeleton(height: 220),
                ],
              );
            }
            if (matchesSnapshot.hasError && !matchesSnapshot.hasData) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Could not load matches',
                  'تعذر تحميل المباريات',
                ),
                body: productionErrorMessage(matchesSnapshot.error!),
              );
            }
            final events = matchesSnapshot.data ?? const <MatchEvent>[];
            final joinedPredictions = predictions.map((pred) {
              if (pred.match != null) return pred;
              MatchEvent? found;
              for (final ev in events) {
                if (ev.id == pred.matchId ||
                    (pred.homeTeam.isNotEmpty &&
                        pred.awayTeam.isNotEmpty &&
                        pred.homeTeam.trim().toLowerCase() ==
                            ev.homeTeam.trim().toLowerCase() &&
                        pred.awayTeam.trim().toLowerCase() ==
                            ev.awayTeam.trim().toLowerCase())) {
                  found = ev;
                  break;
                }
              }
              return pred.copyWith(match: found);
            }).toList();
            final filteredHistory = _filteredPredictions(joinedPredictions);
            final selectedDay =
                selectedMatchDay ??
                initialMatchCalendarDay(events, now: DateTime.now());
            final visibleEvents = matchEventsOnDay(events, selectedDay);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MatchDayStrip(
                  events: events,
                  selectedDay: selectedDay,
                  onSelected: (day) => setState(() => selectedMatchDay = day),
                ),
                const SizedBox(height: 22),
                _ProductionSectionHeading(
                  title: abuText(
                    context,
                    'OPEN & UPCOMING',
                    'المتاحة والقادمة',
                  ),
                  detail: abuText(
                    context,
                    'Your latest saved picks stay visible after locking.',
                    'تبقى آخر توقعاتك المحفوظة ظاهرة بعد الإغلاق.',
                  ),
                ),
                const SizedBox(height: 12),
                if (events.isEmpty)
                  _ProductionEmpty(
                    icon: Icons.sports_soccer_rounded,
                    title: abuText(
                      context,
                      'No matches yet',
                      'لا توجد مباريات بعد',
                    ),
                    body: abuText(
                      context,
                      'An administrator has not published a match event.',
                      'لم ينشر المشرف فعالية مباراة بعد.',
                    ),
                  )
                else if (visibleEvents.isEmpty)
                  _ProductionEmpty(
                    icon: Icons.event_busy_rounded,
                    title: abuText(
                      context,
                      'No matches on this day',
                      'لا توجد مباريات في هذا اليوم',
                    ),
                    body: abuText(
                      context,
                      'Swipe the dates to choose a day marked with a club badge.',
                      'مرّر الأيام واختر يوماً يحمل شعار أحد الأندية.',
                    ),
                  )
                else
                  _ResponsiveGrid(
                    minWidth: 420,
                    children: visibleEvents
                        .map(
                          (event) => _ProductionMatchCard(
                            event: event,
                            repository: widget.repository,
                            profile: widget.profile,
                            prediction: findPrediction(event),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 30),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop = constraints.maxWidth >= 900;
                    final heading = _ProductionSectionHeading(
                      title: abuText(
                        context,
                        'PREDICTION HISTORY',
                        'سجل التوقعات',
                      ),
                      detail: abuText(
                        context,
                        '${joinedPredictions.length} saved predictions',
                        '${joinedPredictions.length} توقعاً محفوظاً',
                      ),
                    );
                    if (desktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: 20),
                          SizedBox(width: 420, child: _historyFilter(context)),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading,
                        const SizedBox(height: 12),
                        _historyFilter(context),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (filteredHistory.isEmpty)
                  _ProductionEmpty(
                    icon: Icons.fact_check_outlined,
                    title: abuText(
                      context,
                      predictions.isEmpty
                          ? 'No saved predictions yet'
                          : 'No predictions in this filter',
                      predictions.isEmpty
                          ? 'لا توجد توقعات محفوظة بعد'
                          : 'لا توجد توقعات في هذا التصنيف',
                    ),
                    body: abuText(
                      context,
                      predictions.isEmpty
                          ? 'Lock your first match picks to start your history.'
                          : 'Choose another filter to see your saved picks.',
                      predictions.isEmpty
                          ? 'ثبّت أول توقعاتك لبدء سجلك.'
                          : 'اختر تصنيفاً آخر لرؤية توقعاتك المحفوظة.',
                    ),
                  )
                else
                  _ProductionPredictionHistory(predictions: filteredHistory),
              ],
            );
          },
        );
      },
    ),
  );
}

class _ProductionSectionHeading extends StatelessWidget {
  const _ProductionSectionHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? _productionPrimary(context)
              : _lightPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.25,
        ),
      ),
      const SizedBox(height: 5),
      Text(detail, style: TextStyle(color: _muted, height: 1.4)),
    ],
  );
}

bool _predictionIsResolved(SavedPrediction prediction) {
  // A provider score is not a settlement receipt. Keep the prediction pending
  // until the server has atomically evaluated every pick and persisted the
  // reward flag (including settled losses worth zero points).
  return prediction.rewarded;
}

String _normalizedPredictionLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool? _predictionExactCorrect(SavedPrediction prediction, MatchEvent? match) {
  if (match == null || !_predictionIsResolved(prediction)) return null;
  return prediction.exactScoreCorrect;
}

bool? _predictionScorerCorrect(SavedPrediction prediction, MatchEvent? match) {
  if (match == null || !_predictionIsResolved(prediction)) return null;
  if (prediction.firstScorerMatchResult case final persisted?) return persisted;
  final cleanMatchScorer = match.firstScorer
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .trim()
      .toLowerCase();
  final cleanPredScorer = prediction.firstScorer
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .trim()
      .toLowerCase();
  if (cleanMatchScorer.isEmpty && cleanPredScorer.isEmpty) return true;
  if (cleanMatchScorer.isEmpty || cleanPredScorer.isEmpty) return false;
  return cleanMatchScorer == cleanPredScorer;
}

String _predictionScorerLabel(BuildContext context, String scorer) {
  final normalized = _normalizedPredictionLabel(scorer);
  if (normalized.isEmpty) return '—';
  return normalized == 'no scorer'
      ? abuText(context, 'No scorer', 'لا يوجد مسجل')
      : scorer;
}

class _ProductionPredictionHistory extends StatelessWidget {
  const _ProductionPredictionHistory({required this.predictions});

  final List<SavedPrediction> predictions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 900
        ? _desktop(context)
        : Column(
            children: [
              for (var index = 0; index < predictions.length; index++) ...[
                _mobileCard(context, predictions[index]),
                if (index != predictions.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
  );

  Widget _mobileCard(BuildContext context, SavedPrediction prediction) {
    final match = prediction.match;
    final resolved = _predictionIsResolved(prediction);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: resolved && match != null
            ? () {
                final exact = prediction.exactScoreCorrect;
                final firstScorerCorrect = prediction.firstScorerCorrect;
                final winnerCorrect = prediction.winnerCorrect;
                final wonAny = exact || firstScorerCorrect || winnerCorrect;
                _showMatchPredictionResultAnnouncementDialog(
                  context,
                  PredictionOutcomeResult(
                    prediction: prediction,
                    event: match,
                    exactMatch: exact,
                    firstScorerMatch: firstScorerCorrect,
                    winnerMatch: winnerCorrect,
                    pointsEarned: prediction.pointsAwarded,
                    isPerfect: exact && firstScorerCorrect && winnerCorrect,
                    hasSomeCorrect: wonAny,
                  ),
                  repository: ProductionRepository(),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (match != null) ...[
                    _ProductionTeamBadge(
                      team: match.homeTeam,
                      source: match.homeLogoUrl,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match != null
                              ? '${match.homeTeam} vs ${match.awayTeam}'
                              : (prediction.homeTeam.isNotEmpty &&
                                        prediction.awayTeam.isNotEmpty
                                    ? '${prediction.homeTeam} vs ${prediction.awayTeam}'
                                    : abuText(
                                        context,
                                        'Saved match',
                                        'مباراة محفوظة',
                                      )),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          match == null
                              ? _productionDate(prediction.submittedAt)
                              : '${match.competition} · ${_productionDate(match.kickoffAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PredictionStateBadge(
                    resolved: resolved,
                    points: prediction.pointsAwarded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SavedPredictionSummary(prediction: prediction, match: match),
              const SizedBox(height: 10),
              Text(
                abuText(
                  context,
                  'Saved ${_productionDate(prediction.updatedAt)}',
                  'حُفظ في ${_productionDate(prediction.updatedAt)}',
                ),
                textAlign: TextAlign.end,
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktop(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 15, 20, 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  abuText(context, 'MATCH', 'المباراة'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  abuText(context, 'YOUR PICKS', 'توقعاتك'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  abuText(context, 'STATE', 'الحالة'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  abuText(context, 'POINTS', 'النقاط'),
                  textAlign: TextAlign.end,
                  style: _desktopTableHeaderStyle,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final prediction in predictions)
          _ProductionPredictionHistoryRow(prediction: prediction),
      ],
    ),
  );
}

class _ProductionPredictionHistoryRow extends StatelessWidget {
  const _ProductionPredictionHistoryRow({required this.prediction});

  final SavedPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final match = prediction.match;
    final resolved = _predictionIsResolved(prediction);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (match != null) ...[
                  _ProductionTeamBadge(
                    team: match.homeTeam,
                    source: match.homeLogoUrl,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match != null
                            ? '${match.homeTeam} vs ${match.awayTeam}'
                            : (prediction.homeTeam.isNotEmpty &&
                                      prediction.awayTeam.isNotEmpty
                                  ? '${prediction.homeTeam} vs ${prediction.awayTeam}'
                                  : abuText(
                                      context,
                                      'Saved match',
                                      'مباراة محفوظة',
                                    )),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        match == null
                            ? _productionDate(prediction.submittedAt)
                            : '${match.competition} · ${_productionDate(match.kickoffAt)}\n'
                                  '${abuText(context, 'Saved', 'حُفظ')} ${_productionDate(prediction.updatedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: _SavedPredictionSummary(
              prediction: prediction,
              match: match,
              inline: true,
            ),
          ),
          SizedBox(
            width: 120,
            child: _PredictionStateBadge(
              resolved: resolved,
              points: prediction.pointsAwarded,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              resolved ? '+${prediction.pointsAwarded}' : '—',
              textAlign: TextAlign.end,
              style: _display(
                18,
                color: resolved ? _productionPrimary(context) : _muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictionStateBadge extends StatelessWidget {
  const _PredictionStateBadge({required this.resolved, required this.points});

  final bool resolved;
  final int points;

  @override
  Widget build(BuildContext context) {
    final color = resolved
        ? (points > 0 ? _productionPrimary(context) : _muted)
        : _gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        resolved
            ? points > 0
                  ? abuText(context, 'WON', 'فائز')
                  : abuText(context, 'RESOLVED', 'محسومة')
            : abuText(context, 'PENDING', 'قيد الانتظار'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _SavedPredictionSummary extends StatelessWidget {
  const _SavedPredictionSummary({
    required this.prediction,
    required this.match,
    this.compact = false,
    this.inline = false,
  });

  final SavedPrediction prediction;
  final MatchEvent? match;
  final bool compact;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final exactCorrect = _predictionExactCorrect(prediction, match);
    final scorerCorrect = _predictionScorerCorrect(prediction, match);
    final predWinner = prediction.homeScore > prediction.awayScore
        ? (prediction.homeTeam.isNotEmpty ? prediction.homeTeam : 'Home')
        : (prediction.awayScore > prediction.homeScore
              ? (prediction.awayTeam.isNotEmpty ? prediction.awayTeam : 'Away')
              : abuText(context, 'Draw', 'تعادل'));
    final winnerCorrect = match != null && _predictionIsResolved(prediction)
        ? prediction.winnerCorrect
        : null;

    final picks = <Widget>[
      _PredictionPickPill(
        icon: Icons.scoreboard_rounded,
        label: abuText(context, 'SCORE', 'النتيجة'),
        value: '${prediction.homeScore}–${prediction.awayScore}',
        correct: exactCorrect,
      ),
      _PredictionPickPill(
        icon: Icons.person_pin_circle_rounded,
        label: abuText(context, 'FIRST', 'الأول'),
        value: _predictionScorerLabel(context, prediction.firstScorer),
        correct: scorerCorrect,
      ),
      _PredictionPickPill(
        icon: Icons.emoji_events_rounded,
        label: abuText(context, 'WINNER', 'الفائز'),
        value: predWinner,
        correct: winnerCorrect,
      ),
    ];
    final content = inline
        ? Wrap(spacing: 7, runSpacing: 7, children: picks)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (match != null && _predictionIsResolved(prediction)) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        abuText(context, 'Official result', 'النتيجة الرسمية'),
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${match!.homeScore}–${match!.awayScore}',
                      style: _display(19, color: _productionPrimary(context)),
                    ),
                    if (prediction.pointsAwarded > 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        '+${prediction.pointsAwarded}',
                        style: _display(17, color: _gold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${abuText(context, 'First scorer', 'أول مسجل')}: '
                  '${_predictionScorerLabel(context, match!.firstScorer)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 9),
                ),
                const SizedBox(height: 9),
              ],
              Wrap(spacing: 7, runSpacing: 7, children: picks),
            ],
          );
    if (inline) return content;
    return Container(
      padding: EdgeInsets.all(compact ? 11 : 13),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? _line
              : _lightLine,
        ),
      ),
      child: content,
    );
  }
}

class _PredictionPickPill extends StatelessWidget {
  const _PredictionPickPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.correct,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool? correct;

  @override
  Widget build(BuildContext context) {
    final color = correct == null
        ? _muted
        : (correct! ? _productionPrimary(context) : _red);
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: correct == null ? .06 : .1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            correct == null
                ? icon
                : correct!
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label  $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionMatchCard extends StatelessWidget {
  const _ProductionMatchCard({
    required this.event,
    required this.repository,
    this.prediction,
    this.profile,
  });

  final MatchEvent event;
  final ProductionRepository repository;
  final SavedPrediction? prediction;
  final AbuUserProfile? profile;

  Future<void> predict(BuildContext context) async {
    if (repository.auth.currentUser == null) {
      await requireAuth(context, repository);
      return;
    }
    if (prediction != null) return;
    final pointRules = await repository.loadPointRules();
    if (!context.mounted) return;
    final exactPoints = (pointRules['exactPrediction'] ?? 30).toInt();
    final scorerPoints = (pointRules['firstScorer'] ?? 20).toInt();
    final winnerPoints = (pointRules['winnerOutcome'] ?? 10).toInt();
    final maximumPoints = exactPoints + scorerPoints + winnerPoints;
    var home = prediction?.homeScore ?? 0;
    var away = prediction?.awayScore ?? 0;
    final lookedUpScorers = await repository.lookupMatchScorers(
      event.homeTeam,
      event.awayTeam,
      homeTeamId: event.homeTeamId,
      awayTeamId: event.awayTeamId,
    );
    if (!context.mounted) return;
    final combinedScorers = <String>{
      ...event.firstScorerOptions.where(
        (s) => s.trim().isNotEmpty && s != 'No scorer',
      ),
      ...lookedUpScorers.where((s) => s.trim().isNotEmpty && s != 'No scorer'),
    };
    if (combinedScorers.isEmpty) {
      combinedScorers.addAll(const [
        'Robert Lewandowski',
        'Lamine Yamal',
        'Raphinha',
        'Dani Olmo',
        'Vinícius Júnior',
        'Kylian Mbappé',
        'Jude Bellingham',
        'Rodrygo',
        'Pedri',
        'Ferran Torres',
        'Gavi',
        'Fermín López',
        'Pau Víctor',
        'Luka Modrić',
        'Brahim Díaz',
        'Endrick',
        'Arda Güler',
      ]);
    }
    final scorerOptions =
        <String>[
              'No scorer',
              if (prediction != null && prediction!.firstScorer.isNotEmpty)
                prediction!.firstScorer,
              ...combinedScorers,
            ]
            .map((option) => option.trim())
            .where((option) => option.isNotEmpty)
            .toSet()
            .toList();
    var firstScorer =
        (prediction?.firstScorer.trim().isNotEmpty == true &&
            scorerOptions.contains(prediction!.firstScorer.trim()))
        ? prediction!.firstScorer.trim()
        : scorerOptions.first;
    final result = await showDialog<(int, int, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final predictedWinner = home > away
              ? event.homeTeam
              : (away > home
                    ? event.awayTeam
                    : abuText(context, 'Draw', 'تعادل'));
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                abuText(
                                  context,
                                  'Build your prediction',
                                  'كوّن توقعك',
                                ),
                                style: _display(27),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                abuText(
                                  context,
                                  'Exact score · First scorer · Winner',
                                  'النتيجة الدقيقة · أول مسجل · الفائز',
                                ),
                                style: TextStyle(color: _muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: abuText(context, 'Close', 'إغلاق'),
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _PredictionSection(
                      title: abuText(context, 'EXACT SCORE', 'النتيجة الدقيقة'),
                      points: exactPoints,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ScoreInput(
                            label: event.homeTeam,
                            value: home,
                            onChanged: (value) =>
                                setDialogState(() => home = value),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('–', style: _display(34)),
                          ),
                          _ScoreInput(
                            label: event.awayTeam,
                            value: away,
                            onChanged: (value) =>
                                setDialogState(() => away = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PredictionSection(
                      title: abuText(context, 'MATCH WINNER', 'الفريق الفائز'),
                      points: winnerPoints,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _line),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              color: _gold,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              abuText(
                                context,
                                'Predicted Winner: ',
                                'الفائز المتوقع: ',
                              ),
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                predictedWinner,
                                style: TextStyle(
                                  color: _productionPrimary(context),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PredictionSection(
                      title: abuText(
                        context,
                        'WHO SCORED / FIRST SCORER',
                        'صاحب الهدف / أول مسجل',
                      ),
                      points: scorerPoints,
                      child: InkWell(
                        onTap: () async {
                          final selected = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: _surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            builder: (sheetContext) {
                              var search = '';
                              return StatefulBuilder(
                                builder: (context, setSheetState) {
                                  final filtered = scorerOptions.where((s) {
                                    if (search.trim().isEmpty) return true;
                                    return s.toLowerCase().contains(
                                      search.trim().toLowerCase(),
                                    );
                                  }).toList();
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      18,
                                      18,
                                      18,
                                      MediaQuery.viewInsetsOf(context).bottom +
                                          18,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.sports_soccer_rounded,
                                              color: _productionPrimary(
                                                context,
                                              ),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              abuText(
                                                context,
                                                'Select Player',
                                                'اختر اللاعب المسجل',
                                              ),
                                              style: _display(20),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              onPressed: () =>
                                                  Navigator.pop(sheetContext),
                                              icon: Icon(Icons.close_rounded),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            hintText: abuText(
                                              context,
                                              'Search player name…',
                                              'ابحث عن اسم اللاعب…',
                                            ),
                                            prefixIcon: Icon(
                                              Icons.search_rounded,
                                            ),
                                          ),
                                          onChanged: (val) =>
                                              setSheetState(() => search = val),
                                        ),
                                        const SizedBox(height: 12),
                                        Flexible(
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 360,
                                            ),
                                            child: ListView.separated(
                                              itemCount: filtered.length,
                                              separatorBuilder: (_, _) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, i) {
                                                final p = filtered[i];
                                                final isSelected =
                                                    p == firstScorer;
                                                return ListTile(
                                                  leading: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: isSelected
                                                          ? _productionPrimary(
                                                              context,
                                                            ).withValues(
                                                              alpha: .2,
                                                            )
                                                          : _surface2,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      p == 'No scorer'
                                                          ? Icons.block_rounded
                                                          : Icons
                                                                .person_rounded,
                                                      color: isSelected
                                                          ? _productionPrimary(
                                                              context,
                                                            )
                                                          : _muted,
                                                      size: 18,
                                                    ),
                                                  ),
                                                  title: Text(
                                                    p == 'No scorer'
                                                        ? abuText(
                                                            context,
                                                            'No scorer (0–0)',
                                                            'لا يوجد مسجل (٠–٠)',
                                                          )
                                                        : p,
                                                    style: TextStyle(
                                                      fontWeight: isSelected
                                                          ? FontWeight.w900
                                                          : FontWeight.w600,
                                                      color: isSelected
                                                          ? _productionPrimary(
                                                              context,
                                                            )
                                                          : Colors.white,
                                                    ),
                                                  ),
                                                  trailing: isSelected
                                                      ? Icon(
                                                          Icons
                                                              .check_circle_rounded,
                                                          color:
                                                              _productionPrimary(
                                                                context,
                                                              ),
                                                          size: 20,
                                                        )
                                                      : null,
                                                  onTap: () => Navigator.pop(
                                                    sheetContext,
                                                    p,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                          if (selected != null) {
                            setDialogState(() => firstScorer = selected);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _line),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sports_soccer_rounded,
                                color: _productionPrimary(context),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  firstScorer == 'No scorer'
                                      ? abuText(
                                          context,
                                          'No scorer (0–0)',
                                          'لا يوجد مسجل (٠–٠)',
                                        )
                                      : firstScorer,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _line),
                                ),
                                child: Text(
                                  abuText(context, 'SELECT', 'تغيير'),
                                  style: TextStyle(
                                    color: _productionPrimary(context),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            abuText(
                              context,
                              'Up to $maximumPoints points on the line.',
                              'حتى $maximumPoints نقطة متاحة.',
                            ),
                            style: TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(abuText(context, 'CANCEL', 'إلغاء')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(context, (home, away, firstScorer)),
                          child: Text(
                            abuText(context, 'LOCK PICKS', 'تثبيت التوقعات'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result == null) return;
    try {
      // The live match stream may rebuild this card while the dialog is open,
      // especially on Android. Saving does not depend on the old card's
      // BuildContext, so always commit a confirmed result and only guard the
      // follow-up snackbar below.
      await repository.submitPrediction(
        matchId: event.id,
        homeScore: result.$1,
        awayScore: result.$2,
        firstScorer: result.$3,
        homeTeam: event.homeTeam,
        awayTeam: event.awayTeam,
        competition: event.competition,
        kickoffAt: event.kickoffAt,
        homeLogoUrl: event.homeLogoUrl,
        awayLogoUrl: event.awayLogoUrl,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B2A1E),
            content: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    abuText(
                      context,
                      'Prediction saved to your account.',
                      'تم حفظ توقعك في حسابك.',
                    ),
                    style: TextStyle(
                      color: _productionPrimary(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await _showPredictionFireworks(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isMatchLockedOrDone = const {
      'locked',
      'completed',
      'archived',
      'disabled',
    }.contains(event.status);

    final bool open;
    if (event.status == 'open') {
      open = true;
    } else if (isMatchLockedOrDone) {
      open = false;
    } else {
      final isKickoffPassed = !now.isBefore(event.kickoffAt);
      final isClosingPassed = !now.isBefore(event.predictionClosesAt);
      final isBeforeOpen = now.isBefore(event.predictionOpensAt);
      open = !isBeforeOpen && !isClosingPassed && !isKickoffPassed;
    }

    final hasPrediction = prediction != null;
    final canPredict = open && !hasPrediction;

    final resolved =
        const {'completed', 'archived'}.contains(event.status) &&
        event.homeScore != null &&
        event.awayScore != null;

    final String buttonLabel;
    if (resolved) {
      buttonLabel = abuText(context, 'MATCH COMPLETED', 'اكتملت المباراة');
    } else if (hasPrediction) {
      buttonLabel = abuText(context, 'PICKS LOCKED 🔒', 'تم تثبيت التوقع 🔒');
    } else if (open) {
      buttonLabel = abuText(context, 'MAKE PREDICTION ➔', 'سجّل توقعك ➔');
    } else if (now.isBefore(event.predictionOpensAt)) {
      buttonLabel = abuText(
        context,
        'OPENS 24H BEFORE MATCH',
        'يفتح التوقع قبل المباراة بـ ٢٤ ساعة',
      );
    } else {
      buttonLabel = abuText(context, 'PREDICTIONS CLOSED', 'أغلقت التوقعات');
    }

    final isBarcaMatch =
        event.homeTeam.toLowerCase().contains('barcelona') ||
        event.awayTeam.toLowerCase().contains('barcelona');
    final isMadridMatch =
        event.homeTeam.toLowerCase().contains('madrid') ||
        event.awayTeam.toLowerCase().contains('madrid');
    final isElClasico = isBarcaMatch && isMadridMatch;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = !isDark
        ? [const Color(0xFFFFFFFF), const Color(0xFFF8FAFC)]
        : (isElClasico
              ? [
                  const Color(0xFF1E1736),
                  const Color(0xFF2E1A18),
                  const Color(0xFF10131B),
                ]
              : (isBarcaMatch
                    ? [
                        const Color(0xFF151833),
                        const Color(0xFF220E1C),
                        const Color(0xFF10131B),
                      ]
                    : (isMadridMatch
                          ? [
                              const Color(0xFF1E1F2A),
                              const Color(0xFF282312),
                              const Color(0xFF10131B),
                            ]
                          : [
                              const Color(0xFF151924),
                              const Color(0xFF10131B),
                            ])));
    final cardBorder = !isDark
        ? const Color(0xFFE2E8F0)
        : (isElClasico
              ? _gold.withValues(alpha: .45)
              : (isBarcaMatch
                    ? const Color(0xFF1877F2).withValues(alpha: .35)
                    : (isMadridMatch
                          ? _gold.withValues(alpha: .35)
                          : Colors.white.withValues(alpha: .1))));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardBg,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
        border: Border.all(color: cardBorder, width: isElClasico ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    event.competition.toUpperCase(),
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (isElClasico) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _red.withValues(alpha: .4)),
                    ),
                    child: Text(
                      abuText(
                        context,
                        'EL CLÁSICO · 2× XP',
                        'الكلاسيكو · نقاط مضاعفة',
                      ),
                      style: TextStyle(
                        color: _red,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (hasPrediction)
                  _LiveDot(
                    text: abuText(
                      context,
                      resolved ? 'RESOLVED' : 'PICKS LOCKED',
                      resolved ? 'محسومة' : 'تم التثبيت',
                    ),
                  )
                else
                  _LiveDot(
                    text: _localizedMatchStatus(
                      context,
                      event.status,
                    ).toUpperCase(),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MatchFactsScreen(event: event, repository: repository),
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          _ProductionTeamBadge(
                            team: event.homeTeam,
                            source: event.homeLogoUrl,
                            size: 38,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              event.homeTeam,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? _surface2 : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? _line : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        event.homeScore == null
                            ? 'VS'
                            : '${event.homeScore} – ${event.awayScore}',
                        style: TextStyle(
                          color: event.homeScore == null
                              ? (isDark ? _muted : const Color(0xFF64748B))
                              : (isDark
                                    ? _productionPrimary(context)
                                    : const Color(0xFF16A34A)),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              event.awayTeam,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ProductionTeamBadge(
                            team: event.awayTeam,
                            source: event.awayLogoUrl,
                            size: 38,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MatchFactsScreen(event: event, repository: repository),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _productionDate(event.kickoffAt),
                      style: TextStyle(
                        color: isDark ? _muted : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: isDark
                          ? _productionPrimary(context)
                          : const Color(0xFF16A34A),
                      size: 10,
                    ),
                  ],
                ),
              ),
            ),
            if (prediction != null) ...[
              const SizedBox(height: 12),
              _SavedPredictionSummary(
                prediction: prediction!,
                match: event,
                compact: true,
              ),
            ],
            if (resolved) ...[
              _MatchGoalTimelineCard(event: event, repository: repository),
              if (prediction != null)
                _PredictionVictoryCard(
                  event: event,
                  prediction: prediction!,
                  repository: repository,
                ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canPredict ? () => predict(context) : null,
              style: FilledButton.styleFrom(
                backgroundColor: canPredict
                    ? (isDark
                          ? _productionPrimary(context)
                          : const Color(0xFF16A34A))
                    : (isDark ? _surface2 : const Color(0xFFE2E8F0)),
                foregroundColor: canPredict
                    ? (isDark ? _ink : Colors.white)
                    : (isDark ? _muted : const Color(0xFF94A3B8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                buttonLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchGoalTimelineCard extends StatelessWidget {
  const _MatchGoalTimelineCard({required this.event, required this.repository});

  final MatchEvent event;
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) {
    if (event.timeline.isNotEmpty) {
      return _buildTimeline(context, event.timeline);
    }
    return FutureBuilder<List<MatchTimelineEvent>>(
      future: repository.fetchMatchTimeline(event.id),
      builder: (context, snapshot) {
        final timeline = snapshot.data ?? const <MatchTimelineEvent>[];
        if (timeline.isEmpty) {
          if (event.firstScorer.isNotEmpty) {
            return Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_soccer_rounded,
                    size: 16,
                    color: _productionPrimary(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${abuText(context, 'First scorer', 'أول مسجل')}: ${event.firstScorer}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }
        return _buildTimeline(context, timeline);
      },
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    List<MatchTimelineEvent> timeline,
  ) {
    final goals = timeline
        .where((e) => e.type.toLowerCase().contains('goal'))
        .toList();
    if (goals.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sports_soccer_rounded,
                size: 16,
                color: _productionPrimary(context),
              ),
              const SizedBox(width: 8),
              Text(
                abuText(
                  context,
                  'GOALS & MATCH TIMELINE',
                  'أهداف ومجريات المباراة',
                ),
                style: TextStyle(
                  color: _gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final goal in goals) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _productionPrimary(context).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${goal.minute}\'',
                      style: TextStyle(
                        color: _productionPrimary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '⚽ ${goal.player}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  if (goal.team.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${goal.team})',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                  if (goal.assist.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '· ${abuText(context, 'Assist', 'صناعة')}: ${goal.assist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PredictionVictoryCard extends StatelessWidget {
  const _PredictionVictoryCard({
    required this.event,
    required this.prediction,
    required this.repository,
  });

  final MatchEvent event;
  final SavedPrediction prediction;
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) {
    final exactMatch =
        event.homeScore != null &&
        prediction.homeScore == event.homeScore &&
        prediction.awayScore == event.awayScore;
    final firstScorerMatch =
        event.firstScorer.isNotEmpty &&
        prediction.firstScorer.trim().toLowerCase() ==
            event.firstScorer.trim().toLowerCase();
    final winnerMatch =
        event.homeScore != null &&
        ((prediction.homeScore > prediction.awayScore &&
                event.homeScore! > event.awayScore!) ||
            (prediction.homeScore < prediction.awayScore &&
                event.homeScore! < event.awayScore!) ||
            (prediction.homeScore == prediction.awayScore &&
                event.homeScore! == event.awayScore!));
    final wonAny = exactMatch || firstScorerMatch || winnerMatch;

    if (!wonAny) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            const Text('⚽', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    abuText(
                      context,
                      'HARD LUCK THIS TIME',
                      'حظ أوفر هذه المرة',
                    ),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    abuText(
                      context,
                      'None of your picks matched the final outcome. Better luck next match!',
                      'لم تصب توقعاتك هذه المرة. حظ أوفر في المباراة القادمة يا بطل!',
                    ),
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _productionPrimary(context).withValues(alpha: .14),
            _gold.withValues(alpha: .10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _productionPrimary(context).withValues(alpha: .55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.stars_rounded,
                color: _productionPrimary(context),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  abuText(
                    context,
                    'YOU PREDICTED CORRECTLY!',
                    'مبروك! توقعك كان صحيحاً!',
                  ),
                  style: TextStyle(
                    color: _productionPrimary(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (exactMatch)
                _correctPill(
                  context,
                  '${abuText(context, 'Exact score (30 XP)', 'النتيجة الدقيقة (٣٠ نقطة)')}: ${prediction.homeScore}–${prediction.awayScore}',
                ),
              if (firstScorerMatch)
                _correctPill(
                  context,
                  '${abuText(context, 'Who scored (20 XP)', 'صاحب الهدف (٢٠ نقطة)')}: ${prediction.firstScorer}',
                ),
              if (winnerMatch)
                _correctPill(
                  context,
                  '${abuText(context, 'Winner team (10 XP)', 'الفريق الفائز (١٠ نقاط)')}: ${prediction.homeScore > prediction.awayScore ? event.homeTeam : (prediction.awayScore > prediction.homeScore ? event.awayTeam : abuText(context, 'Draw', 'تعادل'))}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _correctPill(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _productionPrimary(context).withValues(alpha: .2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: _productionPrimary(context).withValues(alpha: .4),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 12,
          color: _productionPrimary(context),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: _productionPrimary(context),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

Future<void> _showMatchPredictionResultAnnouncementDialog(
  BuildContext context,
  PredictionOutcomeResult outcome, {
  required ProductionRepository repository,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: .75),
  builder: (dialogContext) {
    final event = outcome.event;
    final prediction = outcome.prediction;
    final hasAnyPoints = outcome.hasSomeCorrect;
    final isPerfect = outcome.isPerfect;

    if (hasAnyPoints) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showPredictionFireworks(context);
        }
      });
    }

    final Widget iconWidget;
    final String titleText;
    final String subText;
    final Color themeColor;

    if (isPerfect) {
      iconWidget = Icon(
        Icons.workspace_premium_rounded,
        size: 52,
        color: _gold,
      );
      titleText = abuText(
        dialogContext,
        'PERFECT PREDICTION!',
        'توقع مثالي خارق!',
      );
      subText = abuText(
        dialogContext,
        'You predicted every detail accurately! Full points awarded.',
        'ألف مبروك! أصبت في جميع التوقعات وحصلت على النقاط الكاملة!',
      );
      themeColor = _gold;
    } else if (hasAnyPoints) {
      iconWidget = Icon(
        Icons.stars_rounded,
        size: 52,
        color: _productionPrimary(context),
      );
      titleText = abuText(
        dialogContext,
        'GREAT PREDICTIONS!',
        'عمل رائع وتوقع مميز!',
      );
      subText = abuText(
        dialogContext,
        'You got some picks right and earned bonus points!',
        'أحسنت! أصبت في بعض التوقعات وحصلت على نقاط إضافية!',
      );
      themeColor = _productionPrimary(context);
    } else {
      iconWidget = Icon(Icons.sports_soccer_rounded, size: 52, color: _muted);
      titleText = abuText(
        dialogContext,
        'HARD LUCK!',
        'حظ أوفر في المرة القادمة!',
      );
      subText = abuText(
        dialogContext,
        'None of your picks landed this time. Keep going for the next match!',
        'لم تصب توقعاتك هذه المرة. حظ أوفر في المباراة القادمة يا بطل!',
      );
      themeColor = _muted;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (hasAnyPoints)
              Positioned.fill(
                child: IgnorePointer(
                  child: Lottie.asset(
                    'assets/animations/fireworks.json',
                    repeat: true,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141C),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hasAnyPoints ? themeColor : _line,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: hasAnyPoints
                        ? themeColor.withValues(alpha: .25)
                        : Colors.black54,
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(height: 10),
                    Text(
                      titleText,
                      style: _display(24, color: themeColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subText,
                      style: TextStyle(color: _muted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                event.homeTeam,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _surface2,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${event.homeScore ?? 0} – ${event.awayScore ?? 0}',
                                  style: TextStyle(
                                    color: _gold,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                event.awayTeam,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          if (event.timeline.isNotEmpty) ...[
                            const Divider(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: event.timeline
                                  .where(
                                    (t) =>
                                        t.type.toLowerCase().contains('goal') ||
                                        t.type.toLowerCase().contains(
                                          'penalty',
                                        ),
                                  )
                                  .map(
                                    (t) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _surface2,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            '⚽',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${t.player} (${t.minute}\')',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                      ),
                      child: Column(
                        children: [
                          _predictionResultComparisonRow(
                            dialogContext,
                            title: abuText(
                              dialogContext,
                              'Exact Score',
                              'النتيجة الدقيقة',
                            ),
                            picked:
                                '${prediction.homeScore} – ${prediction.awayScore}',
                            actual: '${event.homeScore} – ${event.awayScore}',
                            isCorrect: outcome.exactMatch,
                          ),
                          const Divider(height: 14),
                          _predictionResultComparisonRow(
                            dialogContext,
                            title: abuText(
                              dialogContext,
                              'Who Scored / First Scorer',
                              'صاحب الهدف / أول مسجل',
                            ),
                            picked: prediction.firstScorer.isNotEmpty
                                ? prediction.firstScorer
                                : 'No scorer',
                            actual: event.firstScorer.isNotEmpty
                                ? event.firstScorer
                                : (event.homeScore == 0 && event.awayScore == 0
                                      ? 'No scorer'
                                      : '–'),
                            isCorrect: outcome.firstScorerMatch,
                          ),
                          const Divider(height: 14),
                          _predictionResultComparisonRow(
                            dialogContext,
                            title: abuText(
                              dialogContext,
                              'Winner Team',
                              'الفريق الفائز',
                            ),
                            picked: prediction.homeScore > prediction.awayScore
                                ? event.homeTeam
                                : (prediction.awayScore > prediction.homeScore
                                      ? event.awayTeam
                                      : abuText(
                                          dialogContext,
                                          'Draw',
                                          'تعادل',
                                        )),
                            actual:
                                (event.homeScore ?? 0) > (event.awayScore ?? 0)
                                ? event.homeTeam
                                : ((event.awayScore ?? 0) >
                                          (event.homeScore ?? 0)
                                      ? event.awayTeam
                                      : abuText(
                                          dialogContext,
                                          'Draw',
                                          'تعادل',
                                        )),
                            isCorrect: outcome.winnerMatch,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (outcome.pointsEarned > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _productionPrimary(context)
                              .withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _productionPrimary(context)
                                .withValues(alpha: .3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _StreakIconWidget(size: 16),
                            const SizedBox(width: 6),
                            Text(
                              abuText(
                                dialogContext,
                                '+${outcome.pointsEarned} Points Added To Your Total!',
                                '+${outcome.pointsEarned} نقطة أضيفت إلى رصيدك!',
                              ),
                              style: TextStyle(
                                color: _productionPrimary(context),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          repository.markPredictionResultSeen(prediction.id);
                          Navigator.pop(dialogContext);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: hasAnyPoints
                              ? _productionPrimary(context)
                              : _surface2,
                          foregroundColor: hasAnyPoints ? _ink : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          abuText(dialogContext, 'CONTINUE', 'متابعة'),
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

Widget _predictionResultComparisonRow(
  BuildContext context, {
  required String title,
  required String picked,
  required String actual,
  required bool isCorrect,
}) => Row(
  children: [
    Icon(
      isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: isCorrect ? _productionPrimary(context) : _red,
      size: 18,
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            '${abuText(context, 'You:', 'توقعك:')} $picked  ·  ${abuText(context, 'Actual:', 'الفعلي:')} $actual',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    ),
    Text(
      isCorrect
          ? abuText(context, 'Correct', 'صحيح')
          : abuText(context, 'Incorrect', 'غير صحيح'),
      style: TextStyle(
        color: isCorrect ? _productionPrimary(context) : _muted,
        fontWeight: FontWeight.w900,
        fontSize: 12,
      ),
    ),
  ],
);

class _PredictionSection extends StatelessWidget {
  const _PredictionSection({
    required this.title,
    required this.points,
    required this.child,
  });

  final String title;
  final int points;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '+$points XP',
                style: TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _ProductionTeamBadge extends StatelessWidget {
  const _ProductionTeamBadge({
    required this.team,
    this.source = '',
    this.size = 44.0,
  });
  final String team;
  final String source;
  final double size;

  static const _knownLogos = <String, String>{
    'barcelona': 'https://crests.football-data.org/81.png',
    'fc barcelona': 'https://crests.football-data.org/81.png',
    'real madrid': 'https://crests.football-data.org/86.png',
    'real madrid cf': 'https://crests.football-data.org/86.png',
    'atletico madrid': 'https://crests.football-data.org/78.png',
    'manchester city': 'https://crests.football-data.org/65.png',
    'liverpool': 'https://crests.football-data.org/64.png',
    'arsenal': 'https://crests.football-data.org/57.png',
    'bayern': 'https://crests.football-data.org/5.png',
    'bayern munich': 'https://crests.football-data.org/5.png',
    'paris saint-germain': 'https://crests.football-data.org/524.png',
    'psg': 'https://crests.football-data.org/524.png',
    'chelsea': 'https://crests.football-data.org/61.png',
    'juventus': 'https://crests.football-data.org/109.png',
    'inter': 'https://crests.football-data.org/108.png',
    'milan': 'https://crests.football-data.org/98.png',
  };

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size;
    final stableFallback = _ProductionTeamBadgeFallback(team: team);
    final key = team.toLowerCase().trim();
    final effectiveUrl = source.startsWith('http')
        ? source
        : (_knownLogos[key] ?? '');

    Widget image;
    if (effectiveUrl.isNotEmpty) {
      image = _ProductionRemoteImage(
        url: effectiveUrl,
        fit: BoxFit.contain,
        fallback: stableFallback,
      );
    } else {
      image = stableFallback;
    }
    return Container(
      width: effectiveSize,
      height: effectiveSize,
      padding: EdgeInsets.all(effectiveSize * .1),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(effectiveSize * .25),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

class _ProductionTeamBadgeFallback extends StatelessWidget {
  const _ProductionTeamBadgeFallback({required this.team});

  final String team;

  @override
  Widget build(BuildContext context) {
    final words = team
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? 'FC'
        : words.take(3).map((word) => word[0].toUpperCase()).join();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _productionPrimary(context).withValues(alpha: .24),
            _blue.withValues(alpha: .18),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          initials,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ),
    );
  }
}

Future<void> _showPredictionFireworks(BuildContext context) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .2),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 2200), () {
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }),
        );
        return Material(
          color: Colors.transparent,
          child: IgnorePointer(
            child: Center(
              child: SizedBox(
                width: math.min(MediaQuery.sizeOf(context).width, 620),
                height: math.min(MediaQuery.sizeOf(context).height, 620),
                child: Lottie.asset(
                  'assets/animations/fireworks.json',
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      },
    );

class _ScoreInput extends StatelessWidget {
  const _ScoreInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
      IconButton(
        onPressed: () => onChanged(math.min(20, value + 1)),
        icon: Icon(Icons.keyboard_arrow_up_rounded),
      ),
      Text('$value', style: _display(40)),
      IconButton(
        onPressed: value == 0 ? null : () => onChanged(value - 1),
        icon: Icon(Icons.keyboard_arrow_down_rounded),
      ),
    ],
  );
}

class _ProductionLeaderboard extends StatefulWidget {
  const _ProductionLeaderboard({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  @override
  State<_ProductionLeaderboard> createState() => _ProductionLeaderboardState();
}

class _ProductionLeaderboardState extends State<_ProductionLeaderboard> {
  LeaderboardPeriod period = LeaderboardPeriod.currentMonth;
  String? selectedSeasonId;
  bool _previousMonthAvailable = false;

  Widget _periodControl(
    BuildContext context, {
    required bool previousMonthAvailable,
  }) {
    final selectedPeriod =
        !previousMonthAvailable && period == LeaderboardPeriod.previousMonth
        ? LeaderboardPeriod.currentMonth
        : period;
    return SegmentedButton<LeaderboardPeriod>(
      segments: [
        ButtonSegment(
          value: LeaderboardPeriod.currentMonth,
          label: Text(abuText(context, 'THIS MONTH', 'هذا الشهر')),
        ),
        if (previousMonthAvailable)
          ButtonSegment(
            value: LeaderboardPeriod.previousMonth,
            label: Text(abuText(context, 'LAST MONTH', 'الشهر الماضي')),
          ),
        ButtonSegment(
          value: LeaderboardPeriod.season,
          label: Text(abuText(context, 'SEASON', 'الموسم')),
        ),
      ],
      showSelectedIcon: false,
      selected: {selectedPeriod},
      onSelectionChanged: (value) => setState(() => period = value.first),
    );
  }

  void _synchronizePreviousMonthAvailability(bool available) {
    if (_previousMonthAvailable == available &&
        (available || period != LeaderboardPeriod.previousMonth)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _previousMonthAvailable = available;
        if (!available && period == LeaderboardPeriod.previousMonth) {
          period = LeaderboardPeriod.currentMonth;
        }
      });
    });
  }

  Widget _seasonControl(BuildContext context, LeaderboardSnapshot snapshot) {
    if (period != LeaderboardPeriod.season || snapshot.seasons.isEmpty) {
      return const SizedBox.shrink();
    }
    final ids = snapshot.seasons.map((season) => season.id).toSet();
    final effectiveId = ids.contains(selectedSeasonId)
        ? selectedSeasonId
        : ids.contains(snapshot.activeSeasonId)
        ? snapshot.activeSeasonId
        : snapshot.seasons.first.id;
    return DropdownButtonFormField<String>(
      key: ValueKey(effectiveId),
      initialValue: effectiveId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: abuText(context, 'Season', 'الموسم'),
        prefixIcon: Icon(Icons.calendar_month_rounded),
      ),
      items: [
        for (final season in snapshot.seasons)
          DropdownMenuItem(value: season.id, child: Text(season.displayName)),
      ],
      onChanged: (value) => setState(() => selectedSeasonId = value),
    );
  }

  Widget _mobileLeaderboard(
    BuildContext context,
    LeaderboardSnapshot snapshot,
    bool previousMonthAvailable,
  ) {
    final entries = snapshot.entries;
    final top3 = entries.take(3).toList(growable: false);
    final remaining = entries.skip(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodControl(context, previousMonthAvailable: previousMonthAvailable),
        if (period == LeaderboardPeriod.season &&
            snapshot.seasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          _seasonControl(context, snapshot),
        ],
        const SizedBox(height: 16),
        if (snapshot.currentUser != null) ...[
          _StickyUserLeaderboardPill(
            currentUser: snapshot.currentUser!,
            profile: widget.profile,
          ),
          const SizedBox(height: 16),
        ],
        if (top3.isNotEmpty) ...[
          _LeaderboardPodium(
            top3: top3,
            currentUid: widget.profile.uid,
            currentUsername: widget.profile.username,
            onTapUser: (ranked) => _showOtherUserProfileDialog(
              context,
              ranked.entry.uid,
              widget.repository,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (entries.isEmpty)
          _ProductionEmpty(
            icon: Icons.leaderboard_rounded,
            title: abuText(
              context,
              'Leaderboard is resetting',
              'لوحة المتصدرين قيد التحديث',
            ),
            body: abuText(
              context,
              'Eligible activity XP will appear here after signup, daily login, correct predictions, or video answers.',
              'ستظهر هنا XP من التسجيل والدخول اليومي والتوقعات أو إجابات الفيديو الصحيحة.',
            ),
          )
        else if (remaining.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: remaining.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final ranked = remaining[i];
              final entry = ranked.entry;
              final mine = _leaderboardEntryBelongsToProfile(
                entry,
                uid: widget.profile.uid,
                username: widget.profile.username,
              );
              return _LeaderboardRowCard(
                rank: ranked.rank,
                username: entry.username,
                displayName: entry.displayName,
                supportedTeam: entry.supportedTeam,
                isMember: entry.isMember,
                points: ranked.points,
                isMine: mine,
                avatarUrl: entry.avatarUrl,
                onTap: () => _showOtherUserProfileDialog(
                  context,
                  entry.uid,
                  widget.repository,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _desktopLeaderboard(
    BuildContext context,
    LeaderboardSnapshot snapshot,
    bool previousMonthAvailable,
  ) {
    final entries = snapshot.entries;
    final top3 = entries.take(3).toList(growable: false);
    final remaining = entries.skip(3).toList(growable: false);
    final currentUser = snapshot.currentUser;
    final leaderPoints = entries.isEmpty ? 0 : entries.first.points;
    final myPoints = currentUser?.points ?? 0;
    final gapToLeader = math.max(0, leaderPoints - myPoints);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 390,
                child: _periodControl(
                  context,
                  previousMonthAvailable: previousMonthAvailable,
                ),
              ),
              if (period == LeaderboardPeriod.season &&
                  snapshot.seasons.isNotEmpty) ...[
                const SizedBox(width: 12),
                SizedBox(width: 230, child: _seasonControl(context, snapshot)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.groups_rounded,
                  label: abuText(context, 'Ranked fans', 'المشجعون المصنفون'),
                  value: '${snapshot.totalPlayers}',
                  detail: abuText(context, 'Fans with XP', 'مشجعون لديهم XP'),
                  color: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.stars_rounded,
                  label: abuText(context, 'Leader XP', 'XP المتصدر'),
                  value: '$leaderPoints',
                  detail: abuText(context, 'Recognition only', 'للترتيب فقط'),
                  color: _gold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.military_tech_rounded,
                  label: abuText(context, 'Your standing', 'ترتيبك'),
                  value: currentUser == null ? '—' : '#${currentUser.rank}',
                  detail: currentUser == null
                      ? abuText(
                          context,
                          'Earn XP to be ranked',
                          'اكسب XP للظهور في الترتيب',
                        )
                      : abuText(context, '$myPoints XP', '$myPoints XP'),
                  color: _productionPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (top3.isNotEmpty) ...[
                      _LeaderboardPodium(
                        top3: top3,
                        currentUid: widget.profile.uid,
                        currentUsername: widget.profile.username,
                        onTapUser: (ranked) => _showOtherUserProfileDialog(
                          context,
                          ranked.entry.uid,
                          widget.repository,
                        ),
                      ),
                      if (remaining.isNotEmpty) const SizedBox(height: 14),
                    ],
                    if (remaining.isNotEmpty || entries.isEmpty)
                      _ProductionLeaderboardTable(
                        entries: remaining,
                        profileUid: widget.profile.uid,
                        profileUsername: widget.profile.username,
                        repository: widget.repository,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 292,
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.sports_score_rounded,
                              color: _productionPrimary(context),
                              size: 28,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              abuText(context, 'YOUR POSITION', 'مركزك'),
                              style: TextStyle(
                                color: _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              currentUser == null
                                  ? '—'
                                  : '#${currentUser.rank}',
                              style: _display(
                                46,
                                color: _productionPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentUser == null
                                  ? abuText(
                                      context,
                                      'Earn XP from correct answers to enter this ranking.',
                                      'اكسب XP من الإجابات الصحيحة للدخول في هذا الترتيب.',
                                    )
                                  : gapToLeader == 0 && currentUser.rank == 1
                                  ? abuText(
                                      context,
                                      'You lead this table.',
                                      'أنت في صدارة الترتيب.',
                                    )
                                  : abuText(
                                      context,
                                      '$gapToLeader XP behind the leader',
                                      'تبتعد $gapToLeader XP عن المتصدر',
                                    ),
                              style: TextStyle(color: _muted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              abuText(
                                context,
                                'HOW RANKING WORKS',
                                'كيف يعمل الترتيب',
                              ),
                              style: TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              abuText(
                                context,
                                'XP shows fan activity only. It cannot be bought, transferred, redeemed, or used to unlock anything. There are no prizes or rewards.',
                                'تعرض نقاط XP نشاط المشجع فقط. لا يمكن شراؤها أو نقلها أو استبدالها ولا تفتح أي مزايا. لا توجد جوائز أو مكافآت.',
                              ),
                              style: TextStyle(color: _muted, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'XP ranking · no prizes or rewards',
      'ترتيب XP · بلا جوائز أو مكافآت',
    ),
    title: abuText(context, 'Leaderboard', 'لوحة المتصدرين'),
    child: StreamBuilder<LeaderboardSnapshot>(
      stream: widget.repository.watchLeaderboardView(
        period: period,
        seasonId: period == LeaderboardPeriod.season ? selectedSeasonId : null,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: _periodControl(
                  context,
                  previousMonthAvailable: _previousMonthAvailable,
                ),
              ),
              const SizedBox(height: 16),
              const _ProductionSkeleton(height: 300),
            ],
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: _periodControl(
                    context,
                    previousMonthAvailable: _previousMonthAvailable,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Leaderboard unavailable',
                  'لوحة المتصدرين غير متاحة',
                ),
                body: productionErrorMessage(snapshot.error!),
              ),
            ],
          );
        }
        final leaderboard = snapshot.data;
        if (leaderboard == null) {
          return const _ProductionSkeleton(height: 300);
        }
        final previousMonthAvailable = leaderboardPreviousMonthAvailable(
          seasons: leaderboard.seasons,
          activeSeasonId: leaderboard.activeSeasonId,
          now: DateTime.now(),
        );
        _synchronizePreviousMonthAvailability(previousMonthAvailable);
        final desktop = MediaQuery.sizeOf(context).width >= 1100;
        if (desktop) {
          return _desktopLeaderboard(
            context,
            leaderboard,
            previousMonthAvailable,
          );
        }
        return _mobileLeaderboard(context, leaderboard, previousMonthAvailable);
      },
    ),
  );
}

class _LeaderboardPodium extends StatelessWidget {
  const _LeaderboardPodium({
    required this.top3,
    required this.currentUid,
    required this.currentUsername,
    this.onTapUser,
  });

  final List<RankedLeaderboardEntry> top3;
  final String currentUid;
  final String currentUsername;
  final ValueChanged<RankedLeaderboardEntry>? onTapUser;

  @override
  Widget build(BuildContext context) {
    if (top3.isEmpty) return const SizedBox.shrink();
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _gold.withValues(alpha: .12),
            _surface2.withValues(alpha: .6),
            const Color(0xFF10131B),
          ],
        ),
        border: Border.all(color: _gold.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd Place (Silver)
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    ranked: second,
                    rank: 2,
                    medalColor: const Color(0xFFC0C0C0),
                    medalIcon: '🥈',
                    height: 100,
                    isMine: _leaderboardEntryBelongsToProfile(
                      second.entry,
                      uid: currentUid,
                      username: currentUsername,
                    ),
                    onTap: () => onTapUser?.call(second),
                  ),
          ),
          const SizedBox(width: 8),
          // 1st Place (Gold)
          Expanded(
            child: first == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    ranked: first,
                    rank: 1,
                    medalColor: _gold,
                    medalIcon: '🥇',
                    height: 128,
                    isMine: _leaderboardEntryBelongsToProfile(
                      first.entry,
                      uid: currentUid,
                      username: currentUsername,
                    ),
                    onTap: () => onTapUser?.call(first),
                  ),
          ),
          const SizedBox(width: 8),
          // 3rd Place (Bronze)
          Expanded(
            child: third == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    ranked: third,
                    rank: 3,
                    medalColor: const Color(0xFFCD7F32),
                    medalIcon: '🥉',
                    height: 88,
                    isMine: _leaderboardEntryBelongsToProfile(
                      third.entry,
                      uid: currentUid,
                      username: currentUsername,
                    ),
                    onTap: () => onTapUser?.call(third),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.ranked,
    required this.rank,
    required this.medalColor,
    required this.medalIcon,
    required this.height,
    required this.isMine,
    this.onTap,
  });

  final RankedLeaderboardEntry ranked;
  final int rank;
  final Color medalColor;
  final String medalIcon;
  final double height;
  final bool isMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final entry = ranked.entry;
    final initials = entry.displayName.isNotEmpty
        ? entry.displayName.trim()[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medalIcon, style: TextStyle(fontSize: rank == 1 ? 26 : 20)),
          const SizedBox(height: 4),
          Container(
            width: rank == 1 ? 52 : 44,
            height: rank == 1 ? 52 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: medalColor,
                width: rank == 1 ? 2.5 : 1.8,
              ),
              color: _surface2,
              boxShadow: rank == 1
                  ? [
                      BoxShadow(
                        color: _gold.withValues(alpha: .35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: entry.avatarUrl.isNotEmpty
                  ? _ProductionRemoteImage(
                      url: entry.avatarUrl,
                      fit: BoxFit.cover,
                      fallback: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: medalColor,
                            fontWeight: FontWeight.w900,
                            fontSize: rank == 1 ? 18 : 14,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: medalColor,
                          fontWeight: FontWeight.w900,
                          fontSize: rank == 1 ? 18 : 14,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: rank == 1 ? 12 : 11,
              color: isMine ? _productionPrimary(context) : Colors.white,
            ),
          ),
          Text(
            '@${entry.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 9),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  medalColor.withValues(alpha: rank == 1 ? .35 : .22),
                  _surface2,
                ],
              ),
              border: Border.all(color: medalColor.withValues(alpha: .4)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${ranked.points}',
                  style: _display(rank == 1 ? 22 : 17, color: medalColor),
                ),
                const Text(
                  'XP',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRowCard extends StatelessWidget {
  const _LeaderboardRowCard({
    required this.rank,
    required this.username,
    required this.displayName,
    required this.supportedTeam,
    required this.isMember,
    required this.points,
    required this.isMine,
    required this.avatarUrl,
    this.onTap,
  });

  final int rank;
  final String username;
  final String displayName;
  final String supportedTeam;
  final bool isMember;
  final int points;
  final bool isMine;
  final String avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = displayName.isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMine
                ? _productionPrimary(context).withValues(alpha: .1)
                : _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMine
                  ? _productionPrimary(context).withValues(alpha: .5)
                  : _line,
              width: isMine ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: isMine ? _productionPrimary(context) : _muted,
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surface2,
                  border: Border.all(
                    color: isMine
                        ? _productionPrimary(context)
                        : Colors.white.withValues(alpha: .15),
                  ),
                ),
                child: ClipOval(
                  child: avatarUrl.isNotEmpty
                      ? _ProductionRemoteImage(
                          url: avatarUrl,
                          fit: BoxFit.cover,
                          fallback: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: isMine
                                    ? _productionPrimary(context)
                                    : Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: isMine
                                  ? _productionPrimary(context)
                                  : Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName.isNotEmpty ? displayName : username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isMine
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              fontSize: 13,
                              color: isMine
                                  ? _productionPrimary(context)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        if (isMember) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '2×',
                              style: TextStyle(
                                color: _gold,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@$username · $supportedTeam',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$points',
                    style: _display(
                      18,
                      color: isMine
                          ? _productionPrimary(context)
                          : Colors.white,
                    ),
                  ),
                  const Text(
                    'XP',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyUserLeaderboardPill extends StatelessWidget {
  const _StickyUserLeaderboardPill({
    required this.currentUser,
    required this.profile,
  });

  final RankedLeaderboardEntry currentUser;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final initials = profile.displayName.isNotEmpty
        ? profile.displayName.trim()[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF162E2A), Color(0xFF13202E)],
        ),
        border: Border.all(color: _productionPrimary(context), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: _productionPrimary(context).withValues(alpha: .28),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                abuText(context, 'YOUR RANK', 'ترتيبك'),
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '#${currentUser.rank}',
                style: _display(36, color: _productionPrimary(context)),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _productionPrimary(context)),
              color: _surface2,
            ),
            child: ClipOval(
              child: profile.avatarUrl.isNotEmpty
                  ? _ProductionRemoteImage(
                      url: profile.avatarUrl,
                      fit: BoxFit.cover,
                      fallback: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: _productionPrimary(context),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: _productionPrimary(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      abuText(context, 'YOU', 'أنت'),
                      style: TextStyle(
                        color: _productionPrimary(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '@${profile.username}',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '${currentUser.points} XP',
            style: _display(20, color: _productionPrimary(context)),
          ),
        ],
      ),
    );
  }
}

void _showOtherUserProfileDialog(
  BuildContext context,
  String uid,
  ProductionRepository repository,
) {
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: FutureBuilder<AbuUserProfile?>(
        future: repository.fetchProfileByUid(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: _productionPrimary(context),
              ),
            );
          }
          final userProfile = snapshot.data;
          if (userProfile == null) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off_rounded, color: _muted, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    abuText(
                      context,
                      'Fan profile not found',
                      'تعذر العثور على ملف المشجع',
                    ),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(abuText(context, 'CLOSE', 'إغلاق')),
                  ),
                ],
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F151E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _line),
                  boxShadow: const [
                    BoxShadow(color: Colors.black87, blurRadius: 30),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            abuText(
                              context,
                              'FAN PROFILE',
                              'الملف الشخصي للمشجع',
                            ),
                            style: TextStyle(
                              color: _productionPrimary(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 320,
                        height: 410,
                        child: _InteractiveFanCard(
                          profile: userProfile,
                          repository: repository,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ProfileStatSection(
                        title: abuText(
                          context,
                          'ACTIVITY & XP',
                          'النشاط ونقاط الخبرة',
                        ),
                        icon: Icons.local_fire_department_rounded,
                        items: [
                          _StatItem(
                            icon: const _StreakIconWidget(size: 16),
                            value: '${userProfile.currentStreak} Days',
                            label: abuText(
                              context,
                              'CURRENT STREAK',
                              'السلسلة الحالية',
                            ),
                            color: _red,
                          ),
                          _StatItem(
                            icon: const _StreakIconWidget(size: 16),
                            value: '${userProfile.longestStreak} Days',
                            label: abuText(
                              context,
                              'BEST STREAK',
                              'أفضل سلسلة',
                            ),
                            color: _gold,
                          ),
                          _StatItem(
                            value: '${userProfile.totalPoints} XP',
                            label: abuText(
                              context,
                              'TOTAL XP',
                              'إجمالي النقاط',
                            ),
                            color: _productionPrimary(context),
                          ),
                          _StatItem(
                            value: userProfile.supportedTeam,
                            label: abuText(context, 'CLUB', 'النادي'),
                            color: const Color(0xFF9B72FF),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ProductionLeaderboardTable extends StatelessWidget {
  const _ProductionLeaderboardTable({
    required this.entries,
    required this.profileUid,
    required this.profileUsername,
    this.repository,
  });

  final List<RankedLeaderboardEntry> entries;
  final String profileUid;
  final String profileUsername;
  final ProductionRepository? repository;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 17, 20, 13),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  abuText(context, 'RANK', 'الترتيب'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  abuText(context, 'SUPPORTER', 'المشجع'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  abuText(context, 'CLUB', 'النادي'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  abuText(context, 'STATUS', 'الحالة'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 105,
                child: Text(
                  'XP',
                  textAlign: TextAlign.end,
                  style: _desktopTableHeaderStyle,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.leaderboard_rounded, color: _muted),
                const SizedBox(width: 10),
                Text(
                  abuText(
                    context,
                    'The first verified points will start the table.',
                    'أول نقاط موثقة ستبدأ الترتيب.',
                  ),
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        for (var index = 0; index < entries.length; index++)
          _ProductionLeaderboardDesktopRow(
            ranked: entries[index],
            mine: _leaderboardEntryBelongsToProfile(
              entries[index].entry,
              uid: profileUid,
              username: profileUsername,
            ),
            onTap: repository != null
                ? () => _showOtherUserProfileDialog(
                    context,
                    entries[index].entry.uid,
                    repository!,
                  )
                : null,
          ),
      ],
    ),
  );
}

const _desktopTableHeaderStyle = TextStyle(
  color: _muted,
  fontSize: 9,
  fontWeight: FontWeight.w900,
  letterSpacing: 1.15,
);

class _ProductionLeaderboardDesktopRow extends StatelessWidget {
  const _ProductionLeaderboardDesktopRow({
    required this.ranked,
    required this.mine,
    this.onTap,
  });

  final RankedLeaderboardEntry ranked;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final entry = ranked.entry;
    return Material(
      color: mine
          ? _productionPrimary(context).withValues(alpha: .075)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${ranked.rank}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _surface2,
                      foregroundColor: mine
                          ? _productionPrimary(context)
                          : Colors.white,
                      child: Text(
                        entry.username.isEmpty
                            ? '?'
                            : entry.username[0].toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Text(
                        '@${entry.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: mine ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 7),
                      _LiveDot(text: abuText(context, 'YOU', 'أنت')),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _ProductionTeamBadge(team: entry.supportedTeam, source: ''),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        entry.supportedTeam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 92,
                child: entry.isMember
                    ? _LiveDot(text: abuText(context, '2× MEMBER', 'عضو ×٢'))
                    : const Text('—', style: TextStyle(color: _muted)),
              ),
              SizedBox(
                width: 105,
                child: Text(
                  '${ranked.points}',
                  textAlign: TextAlign.end,
                  style: _display(21, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePointsCard extends StatelessWidget {
  const _ProfilePointsCard({required this.repository, required this.profile});

  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? _productionPrimary(context)
        : const Color(0xFF16A34A);
    final cardBg = isDark ? _surface : Colors.white;
    final borderColor = isDark ? _line : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? _muted : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.stars_rounded, color: primaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      abuText(
                        context,
                        'POINTS & XP LEDGER',
                        'سجل النقاط والعمليات',
                      ),
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.totalPoints} XP',
                      style: _display(28, color: textColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: .3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.leaderboard_rounded, color: _gold, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      abuText(context, 'RANKING ONLY', 'للترتيب فقط'),
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: borderColor),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                abuText(
                  context,
                  'Verified prediction and video-answer XP',
                  'نقاط XP الموثقة للتوقعات وإجابات الفيديو',
                ),
                style: TextStyle(color: subtextColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () =>
                _showFullPointsHistoryModal(context, repository, profile),
            icon: Icon(Icons.receipt_long_rounded, size: 18),
            label: Text(
              abuText(
                context,
                'VIEW FULL POINTS HISTORY',
                'عرض سجل النقاط والعمليات بالكامل',
              ),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? _surface2 : const Color(0xFFF1F5F9),
              foregroundColor: isDark ? primaryColor : const Color(0xFF15803D),
              side: BorderSide(color: isDark ? _line : const Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showFullPointsHistoryModal(
  BuildContext context,
  ProductionRepository repository,
  AbuUserProfile profile,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF10141D)
        : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
      final primaryColor = isDark
          ? _productionPrimary(context)
          : const Color(0xFF16A34A);
      return DraggableScrollableSheet(
        initialChildSize: .75,
        minChildSize: .4,
        maxChildSize: .92,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF28313E)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.history_rounded, color: primaryColor, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      abuText(context, 'XP History', 'سجل XP'),
                      style: _display(
                        22,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<List<PointLedgerEntry>>(
                  stream: repository.watchPointHistory(profile.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: _productionPrimary(context),
                        ),
                      );
                    }
                    final entries = snapshot.data ?? [];
                    if (entries.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.stars_rounded, size: 48, color: _gold),
                            const SizedBox(height: 10),
                            Text(
                              abuText(
                                context,
                                'No XP activity yet. Correct predictions and video answers earn XP.',
                                'لا يوجد نشاط XP بعد. التوقعات وإجابات الفيديو الصحيحة تمنح XP.',
                              ),
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark ? _line : const Color(0xFFE2E8F0),
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: primaryColor.withValues(
                              alpha: .15,
                            ),
                            child: Icon(
                              _pointSourceIcon(entry.sourceType),
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            _pointTransactionReason(context, entry),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            '${_pointSourceLabel(context, entry.sourceType)} · ${_productionDate(entry.createdAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? _muted : const Color(0xFF64748B),
                            ),
                          ),
                          trailing: Text(
                            '+${entry.finalPoints} XP',
                            style: _display(20, color: primaryColor),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Retained for a possible standalone points route; Profile owns it today.
// ignore: unused_element
class _ProductionPoints extends StatelessWidget {
  const _ProductionPoints({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  Widget _mobileHistory(
    BuildContext context,
    List<PointLedgerEntry> entries,
  ) => Card(
    child: Column(
      children: entries
          .map(
            (entry) => ListTile(
              leading: CircleAvatar(
                backgroundColor: _productionPrimary(context)
                    .withValues(alpha: .12),
                child: Icon(
                  _pointSourceIcon(entry.sourceType),
                  color: _productionPrimary(context),
                ),
              ),
              title: Text(_pointTransactionReason(context, entry)),
              subtitle: Text(
                '${_pointSourceLabel(context, entry.sourceType)} · '
                '${entry.basePoints} × ${entry.multiplier.toStringAsFixed(entry.multiplier % 1 == 0 ? 0 : 1)} · '
                '${_productionDate(entry.createdAt)}',
              ),
              trailing: Text(
                '+${entry.finalPoints}',
                style: _display(20, color: _productionPrimary(context)),
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _desktopHistory(BuildContext context, List<PointLedgerEntry> entries) {
    final visibleTotal = entries.fold<int>(
      0,
      (total, entry) => total + entry.finalPoints,
    );
    final boosted = entries.where((entry) => entry.multiplier > 1).length;
    final averageMultiplier = entries.isEmpty
        ? 1.0
        : entries.fold<double>(0, (total, entry) => total + entry.multiplier) /
              entries.length;
    final totalsBySource = <String, int>{};
    for (final entry in entries) {
      totalsBySource.update(
        entry.sourceType,
        (total) => total + entry.finalPoints,
        ifAbsent: () => entry.finalPoints,
      );
    }
    final sources = totalsBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _ProductionPointsHero(profile: profile),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Expanded(
                        child: _ProductionDesktopKpi(
                          icon: Icons.verified_rounded,
                          label: abuText(
                            context,
                            'Ledger total',
                            'إجمالي السجل',
                          ),
                          value: '+$visibleTotal',
                          detail: abuText(
                            context,
                            '${entries.length} verified entries',
                            '${entries.length} عملية موثقة',
                          ),
                          color: _productionPrimary(context),
                          fillHeight: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProductionDesktopKpi(
                          icon: Icons.workspace_premium_rounded,
                          label: abuText(
                            context,
                            'Boosted awards',
                            'مكافآت مضاعفة',
                          ),
                          value: '$boosted',
                          detail: abuText(
                            context,
                            '${averageMultiplier.toStringAsFixed(1)}× average multiplier',
                            'متوسط ${averageMultiplier.toStringAsFixed(1)}×',
                          ),
                          color: _gold,
                          fillHeight: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _ProductionPointsTable(entries: entries),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 310,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          abuText(context, 'EARNING MIX', 'مصادر النقاط'),
                          style: TextStyle(
                            color: _productionPrimary(context),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          abuText(
                            context,
                            'Every total below comes from the verified server ledger.',
                            'كل إجمالي أدناه مصدره سجل الخادم الموثق.',
                          ),
                          style: TextStyle(color: _muted, height: 1.45),
                        ),
                        const SizedBox(height: 20),
                        for (final source in sources) ...[
                          _ProductionPointSourceBreakdown(
                            source: source.key,
                            points: source.value,
                            total: math.max(visibleTotal, 1),
                          ),
                          const SizedBox(height: 17),
                        ],
                        if (sources.isEmpty)
                          Text(
                            abuText(
                              context,
                              'No verified earning sources yet.',
                              'لا توجد مصادر نقاط موثقة بعد.',
                            ),
                            style: TextStyle(color: _muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      '${profile.totalPoints} verified points',
      '${profile.totalPoints} نقطة موثقة',
    ),
    title: abuText(context, 'Point history', 'سجل النقاط'),
    child: StreamBuilder<List<PointLedgerEntry>>(
      stream: repository.watchPointHistory(profile.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 260);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(context, 'History unavailable', 'السجل غير متاح'),
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final entries = snapshot.data ?? const [];
        final desktop = MediaQuery.sizeOf(context).width >= 1100;
        if (entries.isEmpty) {
          if (desktop) return _desktopHistory(context, entries);
          return _ProductionEmpty(
            icon: Icons.receipt_long_rounded,
            title: abuText(
              context,
              'No point transactions yet',
              'لا توجد عمليات نقاط بعد',
            ),
            body: abuText(
              context,
              'Every point will appear here with its source and multiplier.',
              'ستظهر كل نقطة هنا مع مصدرها ومضاعفها.',
            ),
          );
        }
        return desktop
            ? _desktopHistory(context, entries)
            : _mobileHistory(context, entries);
      },
    ),
  );
}

class _ProductionDesktopKpi extends StatelessWidget {
  const _ProductionDesktopKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    this.fillHeight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          if (fillHeight) const Spacer() else const SizedBox(height: 16),
          Text(value, style: _display(31, color: color)),
          const SizedBox(height: 3),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    ),
  );
}

class _ProductionPointsTable extends StatelessWidget {
  const _ProductionPointsTable({required this.entries});
  final List<PointLedgerEntry> entries;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 13),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  abuText(context, 'TRANSACTION', 'العملية'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  abuText(context, 'SOURCE', 'المصدر'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 86,
                child: Text(
                  abuText(context, 'BASE', 'الأساس'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 86,
                child: Text(
                  abuText(context, 'BOOST', 'المضاعف'),
                  style: _desktopTableHeaderStyle,
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  abuText(context, 'AWARD', 'المكافأة'),
                  textAlign: TextAlign.end,
                  style: _desktopTableHeaderStyle,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_rounded, color: _muted),
                const SizedBox(width: 10),
                Text(
                  abuText(
                    context,
                    'Verified transactions will appear here.',
                    'ستظهر العمليات الموثقة هنا.',
                  ),
                  style: TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _productionPrimary(context)
                              .withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          _pointSourceIcon(entry.sourceType),
                          color: _productionPrimary(context),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pointTransactionReason(context, entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _productionDate(entry.createdAt),
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _pointSourceLabel(context, entry.sourceType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted),
                  ),
                ),
                SizedBox(width: 86, child: Text('${entry.basePoints}')),
                SizedBox(
                  width: 86,
                  child: Text(
                    '${entry.multiplier.toStringAsFixed(entry.multiplier % 1 == 0 ? 0 : 1)}×',
                    style: TextStyle(
                      color: entry.multiplier > 1 ? _gold : _muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    '+${entry.finalPoints}',
                    textAlign: TextAlign.end,
                    style: _display(20, color: _productionPrimary(context)),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ProductionPointSourceBreakdown extends StatelessWidget {
  const _ProductionPointSourceBreakdown({
    required this.source,
    required this.points,
    required this.total,
  });

  final String source;
  final int points;
  final int total;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(
            _pointSourceIcon(source),
            color: _productionPrimary(context),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pointSourceLabel(context, source),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$points',
            style: _display(17, color: _productionPrimary(context)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          minHeight: 7,
          value: (points / total).clamp(0, 1).toDouble(),
          backgroundColor: _surface2,
          valueColor: AlwaysStoppedAnimation(_productionPrimary(context)),
        ),
      ),
    ],
  );
}

AbuLanguage _pointLanguage(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar'
    ? AbuLanguage.arabic
    : AbuLanguage.english;

String _pointSourceLabel(BuildContext context, String source) =>
    localizedPointSourceLabel(
      sourceType: source,
      language: _pointLanguage(context),
    );

String _pointTransactionReason(BuildContext context, PointLedgerEntry entry) =>
    localizedPointTransactionReason(
      sourceType: entry.sourceType,
      storedReason: entry.reason,
      language: _pointLanguage(context),
    );

IconData _pointSourceIcon(String source) => switch (source) {
  'exactPrediction' => Icons.sports_soccer_rounded,
  'firstScorer' => Icons.person_pin_circle_rounded,
  'videoQuestion' => Icons.play_circle_fill_rounded,
  'playerCard' || 'player_card' => Icons.person_search_rounded,
  _ => Icons.add_circle_rounded,
};

class _ProductionProfile extends StatefulWidget {
  const _ProductionProfile({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionProfile> createState() => _ProductionProfileState();
}

class _ProductionProfileState extends State<_ProductionProfile> {
  Uint8List? temporaryImage;
  bool pickingImage = false;
  final ImagePicker imagePicker = ImagePicker();
  UserLeaderboardRanks? userRanks;
  double? userAccuracy;

  Future<void> pickTemporaryImage() async {
    if (pickingImage) return;
    final emptyImageMessage = abuText(
      context,
      'The selected image was empty.',
      'الصورة المختارة فارغة.',
    );
    setState(() => pickingImage = true);
    try {
      final image = await imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError(emptyImageMessage);
      }
      // Decode before placing the bytes in the widget tree so HEIC and other
      // unsupported browser formats produce a friendly error, not an uncaught
      // renderer exception.
      await decodeImageFromList(bytes);
      if (mounted) setState(() => temporaryImage = bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Could not preview that photo: ${productionErrorMessage(error)}',
                'تعذرت معاينة الصورة: ${productionErrorMessage(error)}',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => pickingImage = false);
    }
  }

  Future<void> editProfile() async {
    final profile = widget.profile;
    final user = widget.repository.auth.currentUser;
    final usernameController = TextEditingController(text: profile.username);
    final nameController = TextEditingController(text: profile.displayName);
    final emailController = TextEditingController(
      text: user?.email ?? profile.email,
    );
    final passwordController = TextEditingController();
    var selectedCountryName = profile.country.isNotEmpty
        ? profile.country
        : 'Saudi Arabia';
    var selectedCountryCode = profile.countryCode.isNotEmpty
        ? profile.countryCode
        : _countryCodeForName(selectedCountryName);
    var selectedCountryEmoji = profile.countryFlag.isNotEmpty
        ? profile.countryFlag
        : '🇸🇦';
    var team = profile.supportedTeam.isNotEmpty
        ? profile.supportedTeam
        : 'Barcelona';
    String? uploadedAvatarUrl = profile.avatarUrl;
    bool uploadingPhoto = false;
    final editMedia = MediaQuery.of(context);
    final compactDialog = editMedia.size.width < 430;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF10141D),
          insetPadding: EdgeInsets.symmetric(
            horizontal: compactDialog ? 12 : 40,
            vertical: compactDialog ? 14 : 24,
          ),
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: math.max(360.0, editMedia.size.height - 32),
          ),
          scrollable: true,
          titlePadding: EdgeInsets.fromLTRB(
            compactDialog ? 18 : 24,
            compactDialog ? 18 : 24,
            compactDialog ? 18 : 24,
            8,
          ),
          contentPadding: EdgeInsets.fromLTRB(
            compactDialog ? 16 : 24,
            10,
            compactDialog ? 16 : 24,
            12,
          ),
          actionsPadding: EdgeInsets.fromLTRB(
            compactDialog ? 12 : 20,
            4,
            compactDialog ? 12 : 20,
            compactDialog ? 12 : 18,
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: _line),
          ),
          title: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                color: _productionPrimary(context),
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  abuText(
                    context,
                    'Edit Profile & Account',
                    'تعديل الملف والحساب',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compactDialog ? 16 : 18,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Avatar Photo Picker
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _productionPrimary(context),
                            width: 2,
                          ),
                          color: _surface2,
                        ),
                        child: ClipOval(
                          child: temporaryImage != null
                              ? Image.memory(temporaryImage!, fit: BoxFit.cover)
                              : (uploadedAvatarUrl?.isNotEmpty == true)
                              ? _ProductionRemoteImage(
                                  url: uploadedAvatarUrl!,
                                  fit: BoxFit.cover,
                                  fallback: Center(
                                    child: Text(
                                      profile.displayName.isNotEmpty
                                          ? profile.displayName[0].toUpperCase()
                                          : 'A',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 28,
                                        color: _productionPrimary(context),
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    profile.displayName.isNotEmpty
                                        ? profile.displayName[0].toUpperCase()
                                        : 'A',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                      color: _productionPrimary(context),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: uploadingPhoto
                              ? null
                              : () async {
                                  setDialogState(() => uploadingPhoto = true);
                                  try {
                                    final picked = await imagePicker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 85,
                                    );
                                    if (picked != null) {
                                      final bytes = await picked.readAsBytes();
                                      if (mounted) {
                                        setState(() => temporaryImage = bytes);
                                      }
                                      final url = await widget.repository
                                          .uploadAvatar(picked);
                                      uploadedAvatarUrl = url;
                                      setDialogState(() {});
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                productionErrorMessage(e),
                                              ),
                                            ),
                                          );
                                    }
                                  } finally {
                                    setDialogState(
                                      () => uploadingPhoto = false,
                                    );
                                  }
                                },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _productionPrimary(context),
                              shape: BoxShape.circle,
                            ),
                            child: uploadingPhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _ink,
                                    ),
                                  )
                                : Icon(
                                    Icons.camera_alt_rounded,
                                    color: _ink,
                                    size: 16,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Name & Username
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Display Name',
                      'الاسم المعروض',
                    ),
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: abuText(context, 'Username', 'اسم المستخدم'),
                    prefixText: '@',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Country Selection with Location Auto-detect
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _CountryFlagWidget(
                            country: selectedCountryName,
                            flagEmoji: selectedCountryEmoji,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedCountryName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final item = await _showCountryPickerSheet(
                                context,
                                currentCountry: selectedCountryName,
                              );
                              if (item != null) {
                                setDialogState(() {
                                  selectedCountryName = item.nameEn;
                                  selectedCountryCode = item.code;
                                  selectedCountryEmoji = item.flag;
                                });
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.symmetric(
                                horizontal: compactDialog ? 8 : 10,
                              ),
                            ),
                            child: compactDialog
                                ? const Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 20,
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(abuText(context, 'CHANGE', 'تغيير')),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final detected =
                              await LocationService.detectUserCountry();
                          setDialogState(() {
                            selectedCountryName = detected.nameEn;
                            selectedCountryCode = detected.code;
                            selectedCountryEmoji = detected.flag;
                          });
                        },
                        icon: Icon(
                          Icons.my_location_rounded,
                          size: 16,
                          color: _productionPrimary(context),
                        ),
                        label: Text(
                          abuText(
                            context,
                            'Detect via GPS Location 📍',
                            'تحديد الدولة عبر الموقع 📍',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: _productionPrimary(context),
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Supported Team
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'Barcelona',
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(abuText(context, 'Barcelona', 'برشلونة')),
                      ),
                    ),
                    ButtonSegment(
                      value: 'Real Madrid',
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          abuText(context, 'Real Madrid', 'ريال مدريد'),
                        ),
                      ),
                    ),
                  ],
                  expandedInsets: EdgeInsets.zero,
                  selected: {team},
                  onSelectionChanged: (value) =>
                      setDialogState(() => team = value.first),
                ),
                const SizedBox(height: 18),

                // 5. Account Security (Email & Password)
                Text(
                  abuText(
                    context,
                    'ACCOUNT CREDENTIALS',
                    'بيانات الحساب وكلمة المرور',
                  ),
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Account Email',
                      'البريد الإلكتروني',
                    ),
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'New Password (optional)',
                      'كلمة مرور جديدة (اختياري)',
                    ),
                    hintText: abuText(
                      context,
                      'Leave blank to keep current',
                      'اترك فارغاً للاحتفاظ بالحالية',
                    ),
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(abuText(context, 'CANCEL', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(abuText(context, 'SAVE CHANGES', 'حفظ التعديلات')),
            ),
          ],
        ),
      ),
    );

    if (save != true || !mounted) return;

    try {
      // 1. Update Password if provided
      if (passwordController.text.trim().isNotEmpty && user != null) {
        if (passwordController.text.trim().length < 6) {
          throw ArgumentError('Password must be at least 6 characters.');
        }
        await user.updatePassword(passwordController.text.trim());
      }

      // 2. Update Email if changed
      if (emailController.text.trim().isNotEmpty &&
          user != null &&
          emailController.text.trim().toLowerCase() !=
              (user.email ?? '').toLowerCase()) {
        await user.verifyBeforeUpdateEmail(emailController.text.trim());
      }

      // 3. Update Profile & Sync
      final key = team.toLowerCase().trim();
      final teamLogo = _ProductionTeamBadge._knownLogos[key] ?? '';
      await widget.repository.updateProfile(
        username: usernameController.text.trim(),
        displayName: nameController.text.trim(),
        country: selectedCountryName,
        countryCode: selectedCountryCode,
        supportedTeam: team,
        supportedTeamLogo: teamLogo,
        avatarUrl: uploadedAvatarUrl,
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B2A1E),
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: _productionPrimary(context),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  abuText(
                    context,
                    'Profile updated successfully!',
                    'تم حفظ وتحديث بياناتك بنجاح!',
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A1B1B),
            content: Text(
              productionErrorMessage(error),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant _ProductionProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.totalPoints != widget.profile.totalPoints) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final ranks = await widget.repository.fetchUserRanks(widget.profile);
    final a = await widget.repository.fetchUserAccuracy(widget.profile.uid);
    if (mounted) {
      setState(() {
        userRanks = ranks;
        userAccuracy = a;
      });
    }
  }

  bool verifyingMember = false;

  Future<void> _verifyMember() async {
    setState(() => verifyingMember = true);
    try {
      if (widget.repository.canLinkGoogleAccount) {
        await widget.repository.linkGoogleAccount();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Google is linked. Tap again to prove which YouTube channel belongs to you. Membership comes only from the current admin-uploaded snapshot.',
                'تم ربط Google. اضغط مجدداً لإثبات قناة يوتيوب التابعة لك. تأتي حالة العضوية فقط من اللقطة الحالية التي رفعها المسؤول.',
              ),
            ),
          ),
        );
        return;
      }
      final verified = await _openYouTubeMembershipConnection(
        context,
        repository: widget.repository,
        uid: widget.profile.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verified == true
                  ? abuText(
                      context,
                      'Verified! Welcome Gold Channel Member ⭐',
                      'تم التحقق بنجاح! أهلاً بك في فئة الأعضاء الذهبيين ⭐',
                    )
                  : abuText(
                      context,
                      'Your channel was linked but did not match the current membership snapshot. You can reconnect and choose another channel.',
                      'تم ربط قناتك لكنها لم تطابق لقطة العضويات الحالية. يمكنك إعادة الربط واختيار قناة أخرى.',
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(productionErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => verifyingMember = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return _PageFrame(
      kicker: abuText(
        context,
        '${profile.role.toUpperCase()} · INTERACTIVE FAN CARD',
        '${profile.role.toUpperCase()} · بطاقة مشجع تفاعلية',
      ),
      title: '@${profile.username}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 320,
              height: 410,
              child: _InteractiveFanCard(
                profile: profile,
                temporaryImage: temporaryImage,
                onEdit: editProfile,
                monthlyRank: userRanks?.currentMonth,
                seasonRank: userRanks?.season,
                accuracy: userAccuracy,
                repository: widget.repository,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: profile.isYouTubeMember
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: .5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFFFFD700),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          abuText(
                            context,
                            'GOLD CHANNEL MEMBER',
                            'عضو ذهبي موثق في القناة',
                          ),
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: .6,
                          ),
                        ),
                      ],
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: verifyingMember ? null : _verifyMember,
                    icon: verifyingMember
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _gold,
                            ),
                          )
                        : Icon(Icons.workspace_premium_rounded, size: 18),
                    label: Text(
                      verifyingMember
                          ? abuText(context, 'CONNECTING…', 'جارٍ الربط…')
                          : widget.repository.canLinkGoogleAccount
                          ? abuText(
                              context,
                              'LINK GOOGLE FIRST',
                              'اربط GOOGLE أولاً',
                            )
                          : abuText(
                              context,
                              'LINK & CHECK YOUTUBE',
                              'ربط ومطابقة يوتيوب',
                            ),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gold,
                      side: BorderSide(color: _gold.withValues(alpha: .5)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          _ProductionProfileSummary(
            profile: profile,
            monthlyRank: userRanks?.currentMonth,
            seasonRank: userRanks?.season,
            accuracy: userAccuracy,
          ),
          if (profile.canUploadMembershipSnapshot) ...[
            const SizedBox(height: 24),
            MembershipSnapshotProfilePanel(repository: widget.repository),
          ],
          const SizedBox(height: 24),
          _ProfilePointsCard(repository: widget.repository, profile: profile),
          const SizedBox(height: 24),
          _ProductionRecentActivity(
            repository: widget.repository,
            profile: profile,
          ),
          if (!profile.isGuest) ...[
            const SizedBox(height: 28),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withValues(alpha: .5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(abuText(ctx, 'Sign Out', 'تسجيل الخروج')),
                      content: Text(
                        abuText(
                          ctx,
                          'Are you sure you want to sign out of your account?',
                          'هل أنت متأكد من تسجيل الخروج من حسابك؟',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(abuText(ctx, 'CANCEL', 'إلغاء')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(abuText(ctx, 'SIGN OUT', 'تسجيل الخروج')),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    widget.repository.signOut();
                  }
                },
                icon: Icon(Icons.logout_rounded),
                label: Text(
                  abuText(
                    context,
                    'SIGN OUT OF ACCOUNT',
                    'تسجيل الخروج من الحساب',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _ProductionProfileSummary extends StatelessWidget {
  const _ProductionProfileSummary({
    required this.profile,
    this.monthlyRank,
    this.seasonRank,
    this.accuracy,
  });
  final AbuUserProfile profile;
  final int? monthlyRank;
  final int? seasonRank;
  final double? accuracy;

  @override
  Widget build(BuildContext context) {
    final effectiveAccuracy = accuracy ?? 100.0;
    final monthlyRankText = (monthlyRank ?? 0) > 0 ? '#$monthlyRank' : '—';
    final seasonRankText = (seasonRank ?? 0) > 0 ? '#$seasonRank' : '—';
    final accuracyText = profile.totalPoints > 0
        ? '${effectiveAccuracy.toStringAsFixed(0)}%'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category 1: Season Performance
        _ProfileStatSection(
          title: abuText(context, 'SEASON PERFORMANCE', 'أداء الموسم'),
          icon: Icons.analytics_rounded,
          items: [
            _StatItem(
              value: '${profile.totalPoints} XP',
              label: abuText(context, 'TOTAL XP', 'إجمالي XP'),
              color: _productionPrimary(context),
            ),
            _StatItem(
              value: seasonRankText,
              label: abuText(context, 'SEASON RANK', 'ترتيب الموسم'),
              color: _gold,
            ),
            _StatItem(
              value: accuracyText,
              label: abuText(context, 'PREDICTION ACCURACY', 'دقة التوقعات'),
              color: _blue,
            ),
            _StatItem(
              value: '${profile.monthlyPoints}',
              label: abuText(context, 'THIS MONTH', 'هذا الشهر'),
              color: Colors.white,
            ),
            _StatItem(
              value: monthlyRankText,
              label: abuText(context, 'MONTH RANK', 'ترتيب الشهر'),
              color: _productionPrimary(context),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Streaks remain an activity counter and never award XP.
        _ProfileStatSection(
          title: abuText(context, 'STREAKS & CHALLENGES', 'السلاسل والتحديات'),
          icon: Icons.local_fire_department_rounded,
          items: [
            _StatItem(
              value: '${profile.currentStreak}',
              label: abuText(context, 'ACTIVE STREAK', 'السلسلة الحالية'),
              color: _gold,
              icon: const Text('🔥', style: TextStyle(fontSize: 14)),
            ),
            _StatItem(
              value: '${profile.longestStreak}',
              label: abuText(context, 'LONGEST STREAK', 'أطول سلسلة'),
              color: _gold,
            ),
            _StatItem(
              value: '${profile.exactPredictions}',
              label: abuText(context, 'EXACT PREDICTIONS', 'توقعات دقيقة'),
              color: _blue,
            ),
            _StatItem(
              value: '${profile.challengesCompleted}',
              label: abuText(context, 'VIDEO ANSWERS', 'إجابات الفيديو'),
              color: _productionPrimary(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileStatSection extends StatelessWidget {
  const _ProfileStatSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _surface : Colors.white;
    final borderColor = isDark ? _line : const Color(0xFFE2E8F0);
    final itemBg = isDark ? _surface2 : const Color(0xFFF1F5F9);
    final primaryColor = isDark
        ? _productionPrimary(context)
        : const Color(0xFF16A34A);
    final labelColor = isDark ? _muted : const Color(0xFF64748B);
    final defaultTextColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 500;
              final crossAxisCount = isMobile ? 2 : 4;
              const spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                  crossAxisCount;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items.map((item) {
                  final effectiveItemColor = item.color == Colors.white
                      ? defaultTextColor
                      : (item.color == _productionPrimary(context) && !isDark
                            ? const Color(0xFF15803D)
                            : item.color);

                  return Container(
                    width: itemWidth,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: itemBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.icon != null) ...[
                              item.icon!,
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _display(
                                  isMobile ? 18 : 20,
                                  color: effectiveItemColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: labelColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final String value;
  final String label;
  final Color color;
  final Widget? icon;
  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
    this.icon,
  });
}

class _ProductionRecentActivity extends StatelessWidget {
  const _ProductionRecentActivity({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PointLedgerEntry>>(
    stream: repository.watchPointHistory(profile.uid),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionSkeleton(height: 176);
      }
      if (snapshot.hasError) {
        return _ProductionEmpty(
          icon: Icons.cloud_off_rounded,
          title: abuText(context, 'Activity unavailable', 'النشاط غير متاح'),
          body: productionErrorMessage(snapshot.error!),
        );
      }
      final entries = (snapshot.data ?? const <PointLedgerEntry>[])
          .take(4)
          .toList();
      if (entries.isEmpty) {
        return _ProductionEmpty(
          icon: Icons.history_rounded,
          title: abuText(context, 'No recent activity', 'لا يوجد نشاط حديث'),
          body: abuText(
            context,
            'Your verified point awards will appear here.',
            'ستظهر مكافآت النقاط الموثقة هنا.',
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                abuText(context, 'RECENT ACTIVITY', 'النشاط الحديث'),
                style: _display(21),
              ),
              const SizedBox(height: 8),
              ...entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _productionPrimary(context)
                        .withValues(alpha: .12),
                    child: Icon(
                      Icons.add_rounded,
                      color: _productionPrimary(context),
                    ),
                  ),
                  title: Text(_pointTransactionReason(context, entry)),
                  subtitle: Text(_productionDate(entry.createdAt)),
                  trailing: Text(
                    '+${entry.finalPoints}',
                    style: _display(18, color: _productionPrimary(context)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool?> _openYouTubeMembershipConnection(
  BuildContext context, {
  required ProductionRepository repository,
  required String uid,
}) async {
  final attempt = await repository.startYouTubeMembershipConnection(uid);
  final opened = await launchUrl(
    attempt.authorizationUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!opened) {
    throw StateError('Google authorization could not be opened.');
  }
  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _YouTubeOAuthStatusDialog(
      checkStatus: () => repository.checkYouTubeMembershipConnection(
        uid,
        flowId: attempt.flowId,
      ),
    ),
  );
}

String _localizedYouTubeOAuthError(
  BuildContext context,
  YouTubeOAuthErrorCode code,
) => switch (code) {
  YouTubeOAuthErrorCode.creatorMembersApiUnavailable => abuText(
    context,
    'The current membership snapshot is unavailable. Ask an administrator to import a complete current UTF-8 CSV/TSV export.',
    'لقطة العضويات الحالية غير متاحة. اطلب من المسؤول استيراد ملف CSV/TSV حالي وكامل بترميز UTF-8.',
  ),
  YouTubeOAuthErrorCode.creatorMembershipsDisabled => abuText(
    context,
    'No active membership snapshot is available. Contact support.',
    'لا توجد لقطة عضويات نشطة. تواصل مع الدعم.',
  ),
  YouTubeOAuthErrorCode.creatorChannelMismatch => abuText(
    context,
    'The selected Google account does not prove ownership of the expected YouTube channel. Reconnect and choose the correct account.',
    'حساب Google المحدد لا يثبت ملكية قناة يوتيوب المتوقعة. أعد الربط واختر الحساب الصحيح.',
  ),
  YouTubeOAuthErrorCode.googleAccountMismatch => abuText(
    context,
    'You authorized a different Google account from the one linked to this ABU 3MEER account. Reconnect and choose the same Google account.',
    'تم تفويض حساب Google مختلف عن الحساب المرتبط بحساب ABU 3MEER هذا. أعد الربط واختر حساب Google نفسه.',
  ),
  YouTubeOAuthErrorCode.youtubeChannelAlreadyLinked => abuText(
    context,
    'This YouTube channel is already linked to another ABU 3MEER account. Sign in to that account or contact support.',
    'قناة يوتيوب هذه مرتبطة بالفعل بحساب ABU 3MEER آخر. سجّل الدخول إلى ذلك الحساب أو تواصل مع الدعم.',
  ),
  YouTubeOAuthErrorCode.authorizationDenied => abuText(
    context,
    'Google authorization was cancelled or denied. Nothing was linked. Try again and approve the requested read-only access.',
    'تم إلغاء تفويض Google أو رفضه. لم يتم ربط أي شيء. حاول مجدداً ووافق على صلاحية القراءة المطلوبة.',
  ),
  YouTubeOAuthErrorCode.youtubeChannelMissing => abuText(
    context,
    'The selected Google account does not have a YouTube channel. Choose the Google account that owns the intended channel.',
    'حساب Google المحدد لا يملك قناة يوتيوب. اختر حساب Google الذي يملك القناة المطلوبة.',
  ),
  YouTubeOAuthErrorCode.youtubeChannelAmbiguous => abuText(
    context,
    'This Google account owns multiple YouTube channels and no active membership was found. Select the intended YouTube or Brand Account and try again.',
    'يملك حساب Google هذا عدة قنوات يوتيوب ولم يتم العثور على عضوية نشطة. اختر قناة يوتيوب أو حساب العلامة التجارية المطلوب وحاول مجدداً.',
  ),
  YouTubeOAuthErrorCode.googleAccountLinkRequired => abuText(
    context,
    'Link Google to this ABU 3MEER account first, then start YouTube verification again.',
    'اربط Google بحساب ABU 3MEER هذا أولاً، ثم ابدأ توثيق يوتيوب مجدداً.',
  ),
  YouTubeOAuthErrorCode.creatorNotConnected => abuText(
    context,
    'No active complete membership snapshot is available. Ask an administrator to import the current CSV/TSV export.',
    'لا توجد لقطة عضويات كاملة ونشطة. اطلب من المسؤول استيراد ملف CSV/TSV الحالي.',
  ),
  YouTubeOAuthErrorCode.creatorReauthorizationRequired => abuText(
    context,
    'The membership snapshot must be refreshed by an administrator.',
    'يجب على أحد المسؤولين تحديث لقطة العضويات.',
  ),
  YouTubeOAuthErrorCode.creatorReusableAuthorizationMissing => abuText(
    context,
    'The membership snapshot is not ready. Contact support.',
    'لقطة العضويات غير جاهزة. تواصل مع الدعم.',
  ),
  YouTubeOAuthErrorCode.youtubeScopeMissing => abuText(
    context,
    'The required YouTube permission was not granted. Reconnect and approve all requested read-only permissions.',
    'لم يتم منح صلاحية يوتيوب المطلوبة. أعد الربط ووافق على جميع صلاحيات القراءة المطلوبة.',
  ),
  YouTubeOAuthErrorCode.oauthFlowExpired => abuText(
    context,
    'This connection attempt expired. Close this message and start a new connection.',
    'انتهت صلاحية محاولة الربط هذه. أغلق الرسالة وابدأ محاولة ربط جديدة.',
  ),
  YouTubeOAuthErrorCode.youtubeApiUnavailable => abuText(
    context,
    'YouTube verification is temporarily unavailable. No membership was granted; try again later.',
    'التحقق عبر يوتيوب غير متاح مؤقتاً. لم يتم منح العضوية؛ حاول لاحقاً.',
  ),
  YouTubeOAuthErrorCode.youtubeNotConfigured => abuText(
    context,
    'YouTube verification is not configured correctly on the ABU 3MEER server. Contact support.',
    'لم يتم إعداد التحقق عبر يوتيوب بشكل صحيح على خادم ABU 3MEER. تواصل مع الدعم.',
  ),
  YouTubeOAuthErrorCode.youtubeSnapshotNotImported => abuText(
    context,
    'Membership checking is not ready because no complete member snapshot has been imported. Contact support.',
    'التحقق من العضوية غير جاهز لأنه لم يتم استيراد لقطة كاملة للأعضاء. تواصل مع الدعم.',
  ),
  YouTubeOAuthErrorCode.youtubeSnapshotExpired => abuText(
    context,
    'The membership snapshot is stale but remains the current authority. Ask staff to import a fresh complete CSV/TSV export.',
    'لقطة العضويات قديمة لكنها ما زالت المصدر الحالي. اطلب من أحد الموظفين استيراد ملف CSV/TSV جديد وكامل.',
  ),
  YouTubeOAuthErrorCode.youtubeSnapshotUnavailable => abuText(
    context,
    'The membership snapshot is temporarily unavailable. Your channel was not marked as a member; try again later.',
    'لقطة العضويات غير متاحة مؤقتاً. لم يتم اعتبار قناتك عضواً؛ حاول لاحقاً.',
  ),
  YouTubeOAuthErrorCode.none || YouTubeOAuthErrorCode.unknown => abuText(
    context,
    'YouTube authorization could not be completed. Nothing was linked. Close this message and try again.',
    'تعذر إكمال تفويض يوتيوب. لم يتم ربط أي شيء. أغلق الرسالة وحاول مجدداً.',
  ),
};

class _YouTubeOAuthStatusDialog extends StatefulWidget {
  const _YouTubeOAuthStatusDialog({required this.checkStatus});

  final Future<YouTubeOAuthStatus?> Function() checkStatus;

  @override
  State<_YouTubeOAuthStatusDialog> createState() =>
      _YouTubeOAuthStatusDialogState();
}

class _YouTubeOAuthStatusDialogState extends State<_YouTubeOAuthStatusDialog>
    with WidgetsBindingObserver {
  YouTubeOAuthStatus? status;
  bool checking = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (checking) return;
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final next = await widget.checkStatus();
      if (!mounted) return;
      setState(() {
        status = next;
        checking = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        checking = false;
        error = productionErrorMessage(exception);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    final currentChannelTitle = current?.channelTitle ?? '';
    final successful = current?.isSuccessful == true;
    final notMember = current?.state == YouTubeOAuthFlowState.notMember;
    final failed =
        current?.state == YouTubeOAuthFlowState.error ||
        current?.state == YouTubeOAuthFlowState.expired;
    final icon = successful
        ? Icons.verified_rounded
        : notMember
        ? Icons.person_search_rounded
        : failed
        ? Icons.error_outline_rounded
        : Icons.youtube_searched_for_rounded;
    final iconColor = successful
        ? _productionPrimary(context)
        : notMember
        ? _gold
        : failed
        ? _red
        : _gold;

    final title = abuText(context, 'Link YouTube channel', 'ربط قناة يوتيوب');
    final body = successful
        ? abuText(
            context,
            'Channel ownership confirmed${currentChannelTitle.isEmpty ? '' : ' for $currentChannelTitle'}. Its channel ID matched the current admin-uploaded membership snapshot.',
            'تم تأكيد ملكية القناة${currentChannelTitle.isEmpty ? '' : ' $currentChannelTitle'}. تطابق معرّفها مع لقطة العضويات الحالية التي رفعها المسؤول.',
          )
        : notMember
        ? abuText(
            context,
            'Channel ownership was confirmed, but its channel ID is not in the current complete membership snapshot. If you chose the wrong channel, close this message and connect again.',
            'تم تأكيد ملكية القناة، لكن معرّفها غير موجود في لقطة العضويات الكاملة الحالية. إذا اخترت قناة غير صحيحة، أغلق الرسالة وأعد الربط.',
          )
        : failed
        ? _localizedYouTubeOAuthError(context, current!.errorCode)
        : abuText(
            context,
            'Finish Google authorization in the browser, then return here. This only proves which YouTube channel ID belongs to you; the app does not store a Google access token.',
            'أكمل تفويض Google في المتصفح ثم عد إلى هنا. هذه العملية تثبت فقط معرّف قناة يوتيوب التابع لك؛ لا يخزن التطبيق رمز وصول Google.',
          );

    return AlertDialog(
      icon: Icon(icon, color: iconColor, size: 42),
      title: Text(title, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.45),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _red, height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: checking ? null : () => Navigator.pop(context, successful),
          child: Text(
            successful
                ? abuText(context, 'DONE', 'تم')
                : abuText(context, 'CLOSE', 'إغلاق'),
          ),
        ),
        if (!successful && !notMember && !failed)
          FilledButton.icon(
            onPressed: checking ? null : _check,
            icon: checking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              checking
                  ? abuText(context, 'CHECKING…', 'جارٍ التحقق…')
                  : abuText(context, 'CHECK STATUS', 'تحقق من الحالة'),
            ),
          ),
      ],
    );
  }
}

class _ProductionSettings extends StatelessWidget {
  const _ProductionSettings({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final preferences = AbuAppPreferences.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? _productionPrimary(context) : _lightPrimary;
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => _PageFrame(
        kicker: abuText(context, 'Personalize Abu 3meer', 'خصص تطبيق أبو عمير'),
        title: abuText(context, 'Settings', 'الإعدادات'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 920;
            final account = _SettingsPanel(
              icon: Icons.person_rounded,
              title: abuText(context, 'ACCOUNT', 'الحساب'),
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: primary.withValues(alpha: .14),
                    child: Text(
                      profile.displayName.isNotEmpty
                          ? profile.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                  ),
                  title: Text(
                    profile.displayName,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    profile.isGuest
                        ? abuText(context, 'Guest Mode', 'وضع الزائر')
                        : '@${profile.username} · ${profile.email}',
                  ),
                  trailing: profile.isGuest
                      ? FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: isDark ? _ink : Colors.white,
                          ),
                          onPressed: () => showAuthModal(context, repository),
                          child: Text(
                            abuText(context, 'SIGN IN', 'تسجيل الدخول'),
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        )
                      : null,
                ),
                if (!profile.isGuest) ...[
                  if (repository.canLinkGoogleAccount) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const _GoogleGMark(size: 22),
                      title: Text(
                        abuText(
                          context,
                          'Link Google account',
                          'ربط حساب Google',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        abuText(
                          context,
                          'Keep this account, add Google sign-in, then complete the separate YouTube verification step below.',
                          'احتفظ بهذا الحساب وأضف تسجيل Google، ثم أكمل خطوة توثيق يوتيوب المنفصلة أدناه.',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        try {
                          await repository.linkGoogleAccount();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  abuText(
                                    context,
                                    'Google account linked. Your existing account was kept.',
                                    'تم ربط حساب Google. تم الاحتفاظ بحسابك الحالي.',
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(productionErrorMessage(error)),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: _red,
                    ),
                    title: Text(
                      abuText(context, 'Delete account', 'حذف الحساب'),
                      style: const TextStyle(
                        color: _red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      abuText(
                        context,
                        'Permanently delete your profile and all account data.',
                        'حذف ملفك وجميع بيانات حسابك نهائياً.',
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: _red,
                    ),
                    onTap: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          _AccountDeletionDialog(repository: repository),
                    ),
                  ),
                ],
              ],
            );
            final experience = _SettingsPanel(
              icon: Icons.tune_rounded,
              title: abuText(context, 'EXPERIENCE', 'تجربة الاستخدام'),
              children: [
                ListTile(
                  leading: Icon(Icons.language_rounded, color: primary),
                  title: Text(abuText(context, 'Language', 'اللغة')),
                  subtitle: Text(
                    abuText(
                      context,
                      'The layout and content language update immediately.',
                      'يتغير اتجاه الواجهة ولغتها مباشرة.',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AbuLanguage>(
                      segments: [
                        ButtonSegment(
                          value: AbuLanguage.english,
                          label: Text(
                            abuText(context, 'English', 'الإنجليزية'),
                          ),
                        ),
                        const ButtonSegment(
                          value: AbuLanguage.arabic,
                          label: Text('العربية'),
                        ),
                      ],
                      selected: {preferences.language},
                      onSelectionChanged: (selection) =>
                          preferences.setLanguage(selection.first),
                    ),
                  ),
                ),
              ],
            );
            final notifications = _SettingsPanel(
              icon: Icons.notifications_active_rounded,
              title: abuText(
                context,
                'NOTIFICATION PREFERENCES',
                'تفضيلات الإشعارات',
              ),
              children: [
                _SettingsNotificationTile(
                  icon: Icons.sports_soccer_rounded,
                  title: abuText(
                    context,
                    'Match reminders',
                    'تذكيرات المباريات',
                  ),
                  subtitle: abuText(
                    context,
                    'Notify 15 minutes before kick-off.',
                    'تنبيه قبل 15 دقيقة من بداية المباراة.',
                  ),
                  value: preferences.matchNotifications,
                  onChanged: preferences.setMatchNotifications,
                  repository: repository,
                ),
                const Divider(height: 1),
                _SettingsNotificationTile(
                  icon: Icons.bolt_rounded,
                  title: abuText(context, 'New challenges', 'التحديات الجديدة'),
                  subtitle: abuText(
                    context,
                    'Video questions, player guesses, and Exclusive videos.',
                    'أسئلة الفيديو وتخمين اللاعبين والفيديوهات الحصرية.',
                  ),
                  value: preferences.challengeNotifications,
                  onChanged: preferences.setChallengeNotifications,
                  repository: repository,
                ),
              ],
            );
            final membership = _SettingsPanel(
              icon: Icons.workspace_premium_rounded,
              title: abuText(context, 'YOUTUBE MEMBERSHIP', 'عضوية يوتيوب'),
              trailing: _LiveDot(
                text: profile.isYouTubeMember
                    ? abuText(context, 'VERIFIED · 2×', 'موثق · 2×')
                    : abuText(context, 'NOT VERIFIED', 'غير موثق'),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        abuText(
                          context,
                          'Link Google, then authorize YouTube only to prove which channel ID belongs to you. Membership status comes exclusively from the latest complete UTF-8 CSV/TSV uploaded by admins; linking Google or YouTube does not itself prove membership. Matched members receive 2× XP on correct predictions and video questions. XP cannot be bought, transferred, redeemed, or used to unlock anything.',
                          'اربط Google، ثم فوّض YouTube فقط لإثبات معرّف القناة التابعة لك. تأتي حالة العضوية حصرياً من أحدث ملف CSV/TSV كامل بترميز UTF-8 رفعه المسؤولون؛ ربط Google أو YouTube لا يثبت العضوية بمفرده. يحصل الأعضاء المطابقون على XP مضاعف للتوقعات وأسئلة الفيديو الصحيحة. لا يمكن شراء XP أو نقلها أو استبدالها ولا تفتح أي مزايا.',
                        ),
                        style: TextStyle(color: _muted, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: profile.isGuest
                            ? null
                            : () async {
                                try {
                                  if (repository.canLinkGoogleAccount) {
                                    await repository.linkGoogleAccount();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          abuText(
                                            context,
                                            'Google is linked to this account. Now link YouTube to prove your channel ID.',
                                            'تم ربط Google بهذا الحساب. اربط YouTube الآن لإثبات معرّف قناتك.',
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final verified =
                                      await _openYouTubeMembershipConnection(
                                        context,
                                        repository: repository,
                                        uid: profile.uid,
                                      );
                                  if (verified == true && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          abuText(
                                            context,
                                            'YouTube channel linked and membership snapshot matched.',
                                            'تم ربط قناة يوتيوب ومطابقتها مع لقطة العضويات.',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        productionErrorMessage(error),
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: repository.canLinkGoogleAccount
                            ? const _GoogleGMark(size: 18)
                            : const Icon(Icons.youtube_searched_for_rounded),
                        label: Text(
                          repository.canLinkGoogleAccount
                              ? abuText(
                                  context,
                                  'LINK GOOGLE FIRST',
                                  'اربط GOOGLE أولاً',
                                )
                              : abuText(
                                  context,
                                  profile.isYouTubeMember
                                      ? 'RECONNECT / REFRESH YOUTUBE'
                                      : 'LINK & CHECK YOUTUBE',
                                  profile.isYouTubeMember
                                      ? 'إعادة ربط / تحديث يوتيوب'
                                      : 'ربط ومطابقة يوتيوب',
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://www.youtube.com/channel/${AbuExternalContentService.youtubeChannelId}/join',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: Icon(Icons.open_in_new_rounded),
                        label: Text(
                          abuText(
                            context,
                            'OPEN CHANNEL MEMBERSHIP',
                            'فتح عضوية القناة',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final legal = _SettingsPanel(
              icon: Icons.verified_user_rounded,
              title: abuText(context, 'LEGAL & PRIVACY', 'القانونية والخصوصية'),
              children: [
                _SettingsActionTile(
                  icon: Icons.privacy_tip_rounded,
                  title: abuText(context, 'Privacy Policy', 'سياسة الخصوصية'),
                  subtitle: abuText(
                    context,
                    'What Abu 3meer collects, why it is used, and how to delete it.',
                    'ما يجمعه أبو عمير، ولماذا يستخدم، وكيف يمكن حذفه.',
                  ),
                  onTap: () => _showLegalDocument(
                    context,
                    document: _privacyLegalDocument(context),
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionTile(
                  icon: Icons.leaderboard_rounded,
                  title: abuText(
                    context,
                    'XP & Ranking Rules',
                    'قواعد XP والترتيب',
                  ),
                  subtitle: abuText(
                    context,
                    'Free XP scoring and recognition-only rankings.',
                    'احتساب XP المجاني وترتيب للتقدير فقط.',
                  ),
                  onTap: () => _showLegalDocument(
                    context,
                    document: _competitionLegalDocument(context),
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionTile(
                  icon: Icons.description_rounded,
                  title: abuText(context, 'Terms of Use', 'شروط الاستخدام'),
                  subtitle: abuText(
                    context,
                    'Fair play, account rules, content rules, and XP.',
                    'اللعب النظيف وقواعد الحساب والمحتوى وXP.',
                  ),
                  onTap: () => _showLegalDocument(
                    context,
                    document: _termsLegalDocument(context),
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionTile(
                  icon: Icons.family_restroom_rounded,
                  title: abuText(
                    context,
                    'Age Suitability (13+)',
                    'ملاءمة العمر (+13)',
                  ),
                  subtitle: abuText(
                    context,
                    'Information for users, parents, and App Store review.',
                    'معلومات للمستخدمين والأهل ومراجعة متجر التطبيقات.',
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(AbuBrand.ageSuitabilityUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionTile(
                  icon: Icons.support_agent_rounded,
                  title: abuText(context, 'Support', 'الدعم'),
                  subtitle: AbuBrand.supportEmail,
                  onTap: () => launchUrl(
                    Uri.parse(AbuBrand.supportUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            );

            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: desktop
                  ? Column(
                      children: [
                        account,
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: experience),
                            const SizedBox(width: 18),
                            Expanded(child: notifications),
                          ],
                        ),
                        const SizedBox(height: 18),
                        membership,
                        const SizedBox(height: 18),
                        legal,
                      ],
                    )
                  : Column(
                      children: [
                        account,
                        const SizedBox(height: 14),
                        experience,
                        const SizedBox(height: 14),
                        notifications,
                        const SizedBox(height: 14),
                        membership,
                        const SizedBox(height: 14),
                        legal,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _AccountDeletionDialog extends StatefulWidget {
  const _AccountDeletionDialog({required this.repository});

  final ProductionRepository repository;

  @override
  State<_AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<_AccountDeletionDialog> {
  final confirmation = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscurePassword = true;
  String? error;

  bool get confirmed =>
      confirmation.text.trim().toUpperCase() == 'DELETE' &&
      (!widget.repository.accountDeletionNeedsPassword ||
          password.text.isNotEmpty);

  @override
  void dispose() {
    confirmation.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> deleteAccount() async {
    if (!confirmed || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.deleteAccount(currentPassword: password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AccountDeletion] $exception');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        setState(() {
          busy = false;
          error = productionErrorMessage(exception);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: _red, size: 42),
        title: Text(
          abuText(
            context,
            'Delete account permanently?',
            'حذف الحساب نهائياً؟',
          ),
          textAlign: TextAlign.center,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  abuText(
                    context,
                    'This cannot be undone. Your profile, XP, predictions, challenge answers, device registrations, and sign-in account will be permanently deleted.',
                    'لا يمكن التراجع عن هذا الإجراء. سيُحذف ملفك وXP وتوقعاتك وإجابات التحديات وأجهزة الإشعارات وحساب تسجيل الدخول نهائياً.',
                  ),
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 14),
                Text(
                  abuText(
                    context,
                    'You may be asked to verify your sign-in again. Type DELETE to continue.',
                    'قد يُطلب منك تأكيد تسجيل الدخول مرة أخرى. اكتب DELETE للمتابعة.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: abuText(context, 'Type DELETE', 'اكتب DELETE'),
                  ),
                ),
                if (widget.repository.accountDeletionNeedsPassword) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Current password',
                        'كلمة المرور الحالية',
                      ),
                      suffixIcon: IconButton(
                        onPressed: busy
                            ? null
                            : () => setState(
                                () => obscurePassword = !obscurePassword,
                              ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: _red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton.icon(
            onPressed: confirmed && !busy ? deleteAccount : null,
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label: Text(
              busy
                  ? abuText(context, 'DELETING…', 'جارٍ الحذف…')
                  : abuText(context, 'DELETE ACCOUNT', 'حذف الحساب'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = _productionPrimary(context);
    return ListTile(
      leading: Icon(icon, color: primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _LegalDocument {
  const _LegalDocument({
    required this.title,
    required this.updated,
    required this.webUrl,
    required this.sections,
  });

  final String title;
  final String updated;
  final String webUrl;
  final List<(String, String)> sections;
}

_LegalDocument _privacyLegalDocument(BuildContext context) => _LegalDocument(
  title: abuText(context, 'Privacy Policy', 'سياسة الخصوصية'),
  updated: abuText(
    context,
    'Updated 1 September 2026',
    'آخر تحديث 1 سبتمبر 2026',
  ),
  webUrl: AbuBrand.privacyUrl,
  sections: [
    (
      abuText(context, 'Data We Collect', 'البيانات التي نجمعها'),
      abuText(
        context,
        'Abu 3meer collects account details such as name, email address, sign-in provider, selected team and country, profile image, prediction entries, challenge answers, points, streaks, notification tokens, and basic device or diagnostics data needed to run the service. If you deliberately connect YouTube, we also store the connected channel ID, derived membership status, membership level identifier, member-since date, and verification timestamps.',
        'يجمع أبو عمير بيانات الحساب مثل الاسم والبريد الإلكتروني وطريقة تسجيل الدخول والفريق والدولة وصورة الحساب والتوقعات وإجابات التحديات والنقاط والسلاسل ورموز الإشعارات وبيانات الجهاز أو التشخيص اللازمة لتشغيل الخدمة. وإذا ربطت يوتيوب بإرادتك، نخزن أيضاً معرّف القناة المرتبطة وحالة العضوية المستنتجة ومعرّف مستوى العضوية وتاريخ بدء العضوية وتوقيتات التحقق.',
      ),
    ),
    (
      abuText(context, 'How We Use It', 'كيف نستخدمها'),
      abuText(
        context,
        'We use this data to sign you in, save predictions, award points, verify YouTube membership benefits, show leaderboards, send requested notifications, protect the app from abuse, and respond to support requests.',
        'نستخدم هذه البيانات لتسجيل الدخول وحفظ التوقعات ومنح النقاط والتحقق من مزايا عضوية يوتيوب وعرض الترتيب وإرسال الإشعارات المطلوبة وحماية التطبيق من إساءة الاستخدام والرد على طلبات الدعم.',
      ),
    ),
    (
      abuText(context, 'Sharing', 'المشاركة'),
      abuText(
        context,
        'We use service providers such as Firebase, Google sign-in, Apple sign-in, YouTube Data API, push-notification delivery, hosting, and football data providers. A temporary user Google authorization is used only to prove ownership of a YouTube channel ID and is not retained. Membership is determined by matching that ID against a complete CSV/TSV snapshot uploaded by administrators. We do not sell personal data.',
        'نستخدم مزودي خدمات مثل Firebase وتسجيل الدخول عبر Google وApple وواجهة YouTube Data API وتسليم الإشعارات والاستضافة ومزودي بيانات كرة القدم. يُستخدم تفويض Google المؤقت للمستخدم فقط لإثبات ملكية معرّف قناة يوتيوب ولا نحتفظ به. تُحدد العضوية بمطابقة هذا المعرّف مع لقطة CSV/TSV كاملة يرفعها المسؤولون. لا نبيع البيانات الشخصية.',
      ),
    ),
    (
      abuText(context, 'Location', 'الموقع'),
      abuText(
        context,
        'With permission, location may be used briefly to suggest your country. If permission is declined, the app may use an IP-derived country or device locale. Abu 3meer stores the selected country, not a continuous location history.',
        'بعد موافقتك قد يستخدم الموقع مؤقتاً لاقتراح دولتك. إذا رفضت الإذن فقد يستخدم التطبيق الدولة المستنتجة من عنوان IP أو إعدادات الجهاز. يخزن أبو عمير الدولة المختارة ولا يحتفظ بسجل مستمر للموقع.',
      ),
    ),
    (
      abuText(context, 'Your Controls', 'خياراتك'),
      abuText(
        context,
        'You can change notification preferences in Settings, link Google to prove your YouTube channel identity, and delete your account from Settings. Account deletion removes the profile and personal account data handled by Abu 3meer, subject to fraud prevention and legal retention requirements.',
        'يمكنك تغيير تفضيلات الإشعارات في الإعدادات وربط Google لإثبات هوية قناتك على يوتيوب وحذف حسابك من الإعدادات. حذف الحساب يزيل الملف والبيانات الشخصية التي يديرها أبو عمير مع مراعاة متطلبات منع الاحتيال والاحتفاظ القانوني.',
      ),
    ),
    (
      abuText(context, 'Age and Contact', 'العمر والتواصل'),
      abuText(
        context,
        'Abu 3meer is intended for users aged 13 or older. For privacy rights or questions, contact ${AbuBrand.supportEmail}.',
        'أبو عمير مخصص للمستخدمين بعمر 13 سنة فأكثر. لطلبات حقوق الخصوصية أو الأسئلة تواصل عبر ${AbuBrand.supportEmail}.',
      ),
    ),
  ],
);

_LegalDocument _competitionLegalDocument(BuildContext context) =>
    _LegalDocument(
      title: abuText(context, 'XP & Ranking Rules', 'قواعد XP والترتيب'),
      updated: abuText(
        context,
        'Updated 31 August 2026',
        'آخر تحديث 31 أغسطس 2026',
      ),
      webUrl: AbuBrand.competitionRulesUrl,
      sections: [
        (
          abuText(context, 'Completely Free', 'مجاني بالكامل'),
          abuText(
            context,
            'Abu 3meer has no paid entry, XP purchase, stake, wager, or payment required to make a prediction or answer a video question. A wrong answer never causes a user to lose money or XP.',
            'أبو عمير لا يفرض رسوماً للدخول ولا يبيع XP ولا يتطلب رهاناً أو دفعاً للتوقع أو الإجابة عن سؤال فيديو. الإجابة الخاطئة لا تسبب خسارة مال أو XP.',
          ),
        ),
        (
          abuText(context, 'How XP Is Earned', 'كيف تُكتسب XP'),
          abuText(
            context,
            'XP is awarded for account signup (50 XP once), the first app login each UTC day (5 XP), correct football predictions, and correct video-question answers including player guesses.',
            'تُمنح XP عند التسجيل (50 XP مرة واحدة)، وأول دخول للتطبيق كل يوم UTC (5 XP)، والتوقعات الكروية الصحيحة، وإجابات أسئلة الفيديو الصحيحة بما فيها تخمين اللاعب.',
          ),
        ),
        (
          abuText(context, 'YouTube Member Multiplier', 'مضاعف أعضاء يوتيوب'),
          abuText(
            context,
            'Verified members of the Abu 3meer YouTube channel receive 2× XP only on eligible correct predictions and video-question answers. Signup and daily-login XP always stay at their base amounts. The multiplier changes only a recognition score and never produces money, goods, access, prizes, or any redeemable benefit.',
            'يحصل أعضاء قناة أبو عمير الموثقون على XP مضاعف فقط للتوقعات وإجابات الفيديو الصحيحة المؤهلة. تبقى XP التسجيل والدخول اليومي بقيمتها الأساسية دائماً. يغيّر المضاعف درجة ترتيب تقديرية فقط ولا ينتج مالاً أو سلعاً أو وصولاً أو جوائز أو أي منفعة قابلة للاستبدال.',
          ),
        ),
        (
          abuText(context, 'No Value or Rewards', 'لا قيمة ولا مكافآت'),
          abuText(
            context,
            'XP has no cash or real-world value. It cannot be bought, sold, transferred, exchanged, redeemed for codes or items, or used to unlock app features. Rankings do not name winners and provide no prize, reward, giveaway, payment, or claim.',
            'لا تملك XP أي قيمة نقدية أو واقعية. لا يمكن شراؤها أو بيعها أو نقلها أو استبدالها بأكواد أو أغراض ولا تُستخدم لفتح ميزات التطبيق. الترتيب لا يحدد فائزين ولا يمنح جائزة أو مكافأة أو هدية أو دفعة أو مطالبة.',
          ),
        ),
        (
          abuText(
            context,
            'Ranking Periods and Fair Scoring',
            'فترات الترتيب وعدالة الاحتساب',
          ),
          abuText(
            context,
            'The leaderboard shows current-month XP, previous-month XP, and season XP for recognition only. Monthly ranking starts again each calendar month. Each season uses its administrator-configured start and end dates, and completed seasons remain available as archived rankings. Abu 3meer may correct provider data and remove fraudulent activity so XP remains accurate.',
            'تعرض لوحة الترتيب XP للشهر الحالي والشهر السابق والموسم للتقدير فقط. يبدأ ترتيب شهري جديد مع كل شهر ميلادي. يعتمد كل موسم على تاريخي البداية والنهاية اللذين يحددهما المشرف، وتبقى المواسم المكتملة متاحة كترتيبات مؤرشفة. يجوز لأبو عمير تصحيح بيانات المزود وإزالة النشاط الاحتيالي للحفاظ على دقة XP.',
          ),
        ),
      ],
    );

_LegalDocument _termsLegalDocument(BuildContext context) => _LegalDocument(
  title: abuText(context, 'Terms of Use', 'شروط الاستخدام'),
  updated: abuText(
    context,
    'Updated 31 August 2026',
    'آخر تحديث 31 أغسطس 2026',
  ),
  webUrl: AbuBrand.termsUrl,
  sections: [
    (
      abuText(context, 'Accounts', 'الحسابات'),
      abuText(
        context,
        'Use accurate account information and keep your sign-in secure. You may sign in with email, Google, or Apple where available. Email or Apple users can link Google to the same account to prove ownership of their YouTube channel ID so it can be matched against the admin-uploaded membership snapshot.',
        'استخدم معلومات حساب صحيحة وحافظ على أمان تسجيل الدخول. يمكنك تسجيل الدخول بالبريد الإلكتروني أو Google أو Apple حيثما توفر ذلك. يمكن لمستخدمي البريد أو Apple ربط Google بالحساب نفسه لإثبات ملكية معرّف قناتهم على يوتيوب حتى تتم مطابقته مع لقطة العضويات التي رفعها المسؤول.',
      ),
    ),
    (
      abuText(context, 'Content and Conduct', 'المحتوى والسلوك'),
      abuText(
        context,
        'Do not abuse the app, automate entries, exploit bugs, impersonate others, or interfere with fair scoring. Abu 3meer may suspend accounts that break these rules.',
        'لا تسئ استخدام التطبيق أو تؤتمت المشاركات أو تستغل الأخطاء أو تنتحل شخصية الآخرين أو تتدخل في عدالة احتساب النقاط. قد يوقف أبو عمير الحسابات المخالفة لهذه القواعد.',
      ),
    ),
    (
      abuText(context, 'Service Changes', 'تغييرات الخدمة'),
      abuText(
        context,
        'Football data, videos, challenges, and XP records may change, be corrected, or be removed when needed for accuracy, safety, legal compliance, or operations. XP never unlocks features and has no monetary or redeemable value.',
        'قد تتغير بيانات كرة القدم والفيديوهات والتحديات وسجلات XP أو تصحح أو تزال عند الحاجة للدقة أو السلامة أو الامتثال القانوني أو التشغيل. لا تفتح XP أي ميزات ولا تملك قيمة نقدية أو قابلة للاستبدال.',
      ),
    ),
    (
      abuText(context, 'Contact', 'التواصل'),
      abuText(
        context,
        'For support, privacy, account deletion, or ranking questions, contact ${AbuBrand.supportEmail}.',
        'للدعم أو الخصوصية أو حذف الحساب أو أسئلة الترتيب، تواصل عبر ${AbuBrand.supportEmail}.',
      ),
    ),
  ],
);

Future<void> _showLegalDocument(
  BuildContext context, {
  required _LegalDocument document,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: _surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      minChildSize: .45,
      maxChildSize: .94,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: _line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(document.title, style: _display(28)),
          const SizedBox(height: 6),
          Text(document.updated, style: const TextStyle(color: _muted)),
          const SizedBox(height: 18),
          for (final section in document.sections) ...[
            Text(
              section.$1,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SelectableText(
              section.$2,
              style: const TextStyle(color: _muted, height: 1.45),
            ),
            const SizedBox(height: 18),
          ],
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(document.webUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(abuText(context, 'OPEN WEB VERSION', 'فتح نسخة الويب')),
          ),
        ],
      ),
    ),
  );
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).brightness == Brightness.dark
        ? _productionPrimary(context)
        : _lightPrimary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
            child: Row(
              children: [
                Icon(icon, color: primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .9,
                    ),
                  ),
                ),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsNotificationTile extends StatelessWidget {
  const _SettingsNotificationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.repository,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ProductionRepository? repository;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? _productionPrimary(context) : _lightPrimary;
    final muted = isDark ? _muted : _lightMuted;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: (val) async {
        if (val) {
          final granted = await NotificationService.instance.requestPermission(
            apiRepo: repository?.apiRepo,
          );
          if (!granted && context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    abuText(
                      context,
                      'Notification access is disabled for Abu 3meer in device settings.',
                      'إذن الإشعارات معطل لتطبيق أبو عمير في إعدادات الجهاز.',
                    ),
                  ),
                ),
              );
            return;
          }
        }
        onChanged(val);
        unawaited(NotificationService.instance.syncPreferencesFromLocal());
      },
      activeTrackColor: primary,
      secondary: Icon(icon, color: value ? primary : muted),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}

class _ProductionAdmin extends StatelessWidget {
  const _ProductionAdmin({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'Role-protected operations',
      'عمليات محمية حسب الصلاحيات',
    ),
    title: abuText(context, 'Admin Dashboard', 'لوحة تحكم المشرف'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDashboardStatsPanel(repository: repository),
        const SizedBox(height: 18),
        _ProductionAdminTools(repository: repository, profile: profile),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (profile.isAdmin) ...[
              FilledButton.icon(
                onPressed: () => _showCreateMatch(context),
                icon: Icon(Icons.add_rounded),
                label: Text(
                  abuText(context, 'CREATE MATCH EVENT', 'إنشاء فعالية مباراة'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showPointRules(context),
                icon: Icon(Icons.tune_rounded),
                label: Text(abuText(context, 'POINT RULES', 'قواعد النقاط')),
              ),
              OutlinedButton.icon(
                onPressed: () => _showExclusiveVideosManager(context),
                icon: Icon(Icons.video_library_rounded),
                label: Text(
                  abuText(context, 'EXCLUSIVE VIDEOS', 'الفيديوهات الحصرية'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showNotificationComposer(context),
                icon: Icon(Icons.notifications_active_rounded),
                label: Text(
                  abuText(context, 'SEND NOTIFICATION', 'إرسال إشعار'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        StreamBuilder<List<MatchEvent>>(
          stream: repository.watchManagedMatches(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 260);
            }
            if (snapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Could not load managed matches',
                  'تعذر تحميل المباريات المُدارة',
                ),
                body: productionErrorMessage(snapshot.error!),
              );
            }
            final matches = snapshot.data ?? const [];
            if (matches.isEmpty) {
              return _ProductionEmpty(
                icon: Icons.event_note_rounded,
                title: abuText(
                  context,
                  'No events published',
                  'لا توجد فعاليات منشورة',
                ),
                body: abuText(
                  context,
                  'Create the first real prediction event.',
                  'أنشئ أول فعالية توقعات حقيقية.',
                ),
              );
            }
            return Card(
              child: Column(
                children: matches
                    .map(
                      (match) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _line),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 520;
                            final dropdown = DropdownButton<String>(
                              isExpanded: true,
                              value:
                                  const [
                                    'draft',
                                    'open',
                                    'locked',
                                    'disabled',
                                    'completed',
                                  ].contains(match.status)
                                  ? match.status
                                  : 'draft',
                              items: [
                                DropdownMenuItem(
                                  value: 'draft',
                                  child: Text(
                                    abuText(context, 'Draft', 'مسودة'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'open',
                                  child: Text(
                                    abuText(context, 'Open', 'مفتوحة'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'locked',
                                  child: Text(
                                    abuText(context, 'Locked', 'مقفلة'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'disabled',
                                  child: Text(
                                    abuText(context, 'Disabled', 'معطلة'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'completed',
                                  enabled: false,
                                  child: Text(
                                    abuText(context, 'Completed', 'مكتملة'),
                                  ),
                                ),
                              ],
                              onChanged: match.status == 'completed'
                                  ? null
                                  : (status) async {
                                      if (status == null) return;
                                      try {
                                        await repository.setMatchStatus(
                                          matchId: match.id,
                                          status: status,
                                        );
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                productionErrorMessage(error),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    _ProductionTeamBadge(
                                      team: match.homeTeam,
                                      source: match.homeLogoUrl,
                                    ),
                                    const SizedBox(width: 6),
                                    _ProductionTeamBadge(
                                      team: match.awayTeam,
                                      source: match.awayLogoUrl,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${match.homeTeam} vs ${match.awayTeam}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${match.competition} · ${_productionDate(match.kickoffAt)}',
                                            style: TextStyle(
                                              color: _muted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isNarrow)
                                      SizedBox(width: 110, child: dropdown),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    if (match.status == 'completed')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _productionPrimary(context)
                                              .withValues(alpha: .12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: _productionPrimary(context)
                                                .withValues(alpha: .45),
                                          ),
                                        ),
                                        child: Text(
                                          abuText(
                                            context,
                                            'FINAL ${match.homeScore ?? '-'} - ${match.awayScore ?? '-'}',
                                            'النتيجة النهائية ${match.homeScore ?? '-'} - ${match.awayScore ?? '-'}',
                                          ),
                                          style: TextStyle(
                                            color: _productionPrimary(context),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (match.status != 'completed' &&
                                        match.status != 'open')
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _productionPrimary(
                                            context,
                                          ),
                                          foregroundColor: _ink,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () async {
                                          try {
                                            await repository.setMatchStatus(
                                              matchId: match.id,
                                              status: 'open',
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    abuText(
                                                      context,
                                                      'Predictions opened!',
                                                      'تم فتح باب التوقعات!',
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    productionErrorMessage(e),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: Icon(
                                          Icons.lock_open_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          abuText(
                                            context,
                                            'OPEN PREDICTIONS',
                                            'فتح التوقعات',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      )
                                    else if (match.status == 'open')
                                      FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _gold.withValues(
                                            alpha: .2,
                                          ),
                                          foregroundColor: _gold,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () async {
                                          try {
                                            await repository.setMatchStatus(
                                              matchId: match.id,
                                              status: 'locked',
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        abuText(
                                                          context,
                                                          'Predictions locked!',
                                                          'تم قفل التوقعات!',
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    productionErrorMessage(e),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: Icon(
                                          Icons.lock_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          abuText(
                                            context,
                                            'LOCK PREDICTIONS',
                                            'قفل التوقعات',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (match.status != 'completed' &&
                                        match.status != 'disabled')
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _blue,
                                          side: BorderSide(
                                            color: _blue.withValues(alpha: .5),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () async {
                                          try {
                                            final res = await repository
                                                .autoFetchAndSettleMatch(
                                                  match.id,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    abuText(
                                                      context,
                                                      'Settled: ${res['homeScore']} - ${res['awayScore']} (First Scorer: ${res['firstScorer']})',
                                                      'تم الحسم: ${res['homeScore']} - ${res['awayScore']} (أول مسجل: ${res['firstScorer']})',
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    productionErrorMessage(e),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: Icon(
                                          Icons.sync_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          abuText(
                                            context,
                                            'AUTO-FETCH API RESULT',
                                            'جلب وحسم النتيجة من API',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (match.status != 'completed' &&
                                        match.status != 'disabled')
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _showResult(context, match),
                                        icon: Icon(
                                          Icons.flag_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          abuText(
                                            context,
                                            'MANUAL RESULT',
                                            'حسم يدوي',
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    if (isNarrow)
                                      SizedBox(
                                        width: double.infinity,
                                        child: dropdown,
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      ],
    ),
  );

  Future<void> _showCreateMatch(BuildContext context) async {
    final home = TextEditingController(text: 'Barcelona');
    final away = TextEditingController(text: 'Real Madrid');
    final competition = TextEditingController();
    final homeLogo = TextEditingController();
    final awayLogo = TextEditingController();
    XFile? selectedHomeLogo;
    dynamic selectedHomeLogoBytes;
    XFile? selectedAwayLogo;
    dynamic selectedAwayLogoBytes;
    final firstScorers = TextEditingController(
      text: 'No scorer, Lamine Yamal, Raphinha, Kylian Mbappé, Vinícius Júnior',
    );
    var kickoff = DateTime.now().add(const Duration(days: 2));
    var opens = kickoff.subtract(const Duration(hours: 24));
    var closes = kickoff.subtract(const Duration(minutes: 5));
    var fetchingLogos = false;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canCreate =
              home.text.trim().isNotEmpty &&
              away.text.trim().isNotEmpty &&
              competition.text.trim().isNotEmpty &&
              opens.isBefore(closes) &&
              closes.isBefore(kickoff);
          void refresh(String _) => setDialogState(() {});
          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 680),
            title: Text(
              abuText(context, 'Create match event', 'إنشاء فعالية مباراة'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AdminMatchPreview(
                    homeTeam: home.text,
                    awayTeam: away.text,
                    competition: competition.text,
                    homeLogoUrl: selectedHomeLogo == null ? homeLogo.text : '',
                    awayLogoUrl: selectedAwayLogo == null ? awayLogo.text : '',
                    kickoffAt: kickoff,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: home,
                          onChanged: refresh,
                          decoration: InputDecoration(
                            labelText: abuText(
                              context,
                              'Home team',
                              'الفريق المضيف',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: away,
                          onChanged: refresh,
                          decoration: InputDecoration(
                            labelText: abuText(
                              context,
                              'Away team',
                              'الفريق الضيف',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: competition,
                    onChanged: refresh,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Competition', 'البطولة'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final selection = await _selectAdminImage(
                                  context,
                                );
                                if (selection == null || !context.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  selectedHomeLogo = selection.file;
                                  selectedHomeLogoBytes = selection.bytes;
                                });
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                selectedHomeLogo == null
                                    ? abuText(
                                        context,
                                        'SELECT HOME LOGO',
                                        'اختر شعار المضيف',
                                      )
                                    : selectedHomeLogo!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selectedHomeLogo != null ||
                                homeLogo.text.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _campaignImagePreview(
                                context: context,
                                imageUrl: selectedHomeLogo == null
                                    ? homeLogo.text
                                    : '',
                                imageBytes: selectedHomeLogoBytes,
                                height: 110,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final selection = await _selectAdminImage(
                                  context,
                                );
                                if (selection == null || !context.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  selectedAwayLogo = selection.file;
                                  selectedAwayLogoBytes = selection.bytes;
                                });
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                selectedAwayLogo == null
                                    ? abuText(
                                        context,
                                        'SELECT AWAY LOGO',
                                        'اختر شعار الضيف',
                                      )
                                    : selectedAwayLogo!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selectedAwayLogo != null ||
                                awayLogo.text.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _campaignImagePreview(
                                context: context,
                                imageUrl: selectedAwayLogo == null
                                    ? awayLogo.text
                                    : '',
                                imageBytes: selectedAwayLogoBytes,
                                height: 110,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: fetchingLogos
                          ? null
                          : () async {
                              setDialogState(() => fetchingLogos = true);
                              try {
                                final teams = await Future.wait([
                                  repository.lookupTeam(home.text),
                                  repository.lookupTeam(away.text),
                                ]);
                                if (teams[0] != null) {
                                  home.text = teams[0]!.name;
                                  homeLogo.text = teams[0]!.badgeUrl;
                                  selectedHomeLogo = null;
                                  selectedHomeLogoBytes = null;
                                  if (competition.text.trim().isEmpty) {
                                    competition.text = teams[0]!.league;
                                  }
                                }
                                if (teams[1] != null) {
                                  away.text = teams[1]!.name;
                                  awayLogo.text = teams[1]!.badgeUrl;
                                  selectedAwayLogo = null;
                                  selectedAwayLogoBytes = null;
                                }
                                setDialogState(() {});
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        productionErrorMessage(error),
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (context.mounted) {
                                  setDialogState(() => fetchingLogos = false);
                                }
                              }
                            },
                      icon: fetchingLogos
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.travel_explore_rounded),
                      label: Text(
                        fetchingLogos
                            ? abuText(
                                context,
                                'LOOKING UP TEAMS…',
                                'جارٍ البحث عن الفرق…',
                              )
                            : abuText(
                                context,
                                'FIND TEAM NAMES & LOGOS',
                                'البحث عن أسماء وشعارات الفرق',
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: firstScorers,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'First-scorer options (comma separated)',
                        'خيارات أول مسجل (مفصولة بفواصل)',
                      ),
                      helperText: abuText(
                        context,
                        'These players appear in the fan prediction picker.',
                        'يظهر هؤلاء اللاعبون في قائمة توقعات الجماهير.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AdminDateTile(
                    label: abuText(context, 'Predictions open', 'فتح التوقعات'),
                    value: opens,
                    onChanged: (value) => setDialogState(() => opens = value),
                  ),
                  _AdminDateTile(
                    label: abuText(
                      context,
                      'Predictions close',
                      'إغلاق التوقعات',
                    ),
                    value: closes,
                    onChanged: (value) => setDialogState(() => closes = value),
                  ),
                  _AdminDateTile(
                    label: abuText(context, 'Kickoff', 'بدء المباراة'),
                    value: kickoff,
                    onChanged: (value) => setDialogState(() {
                      kickoff = value;
                      opens = kickoff.subtract(const Duration(hours: 24));
                      closes = kickoff.subtract(const Duration(minutes: 5));
                    }),
                  ),
                  if (!canCreate) ...[
                    const SizedBox(height: 8),
                    Text(
                      abuText(
                        context,
                        'Add both teams and a competition. Opening must be before closing, and closing before kickoff.',
                        'أضف الفريقين والبطولة. يجب أن يكون الفتح قبل الإغلاق، والإغلاق قبل بدء المباراة.',
                      ),
                      style: TextStyle(color: _gold, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(abuText(context, 'CANCEL', 'إلغاء')),
              ),
              FilledButton.icon(
                onPressed: canCreate
                    ? () => Navigator.pop(context, true)
                    : null,
                icon: Icon(Icons.publish_rounded),
                label: Text(abuText(context, 'CREATE', 'إنشاء')),
              ),
            ],
          );
        },
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      final homeLogoUrl = selectedHomeLogo == null
          ? homeLogo.text.trim()
          : await repository.uploadPostImage(selectedHomeLogo!);
      final awayLogoUrl = selectedAwayLogo == null
          ? awayLogo.text.trim()
          : await repository.uploadPostImage(selectedAwayLogo!);
      await repository.createMatch(
        homeTeam: home.text,
        awayTeam: away.text,
        competition: competition.text,
        kickoffAt: kickoff,
        predictionOpensAt: opens,
        predictionClosesAt: closes,
        homeLogoUrl: homeLogoUrl,
        awayLogoUrl: awayLogoUrl,
        firstScorerOptions: firstScorers.text
            .split(',')
            .map((player) => player.trim())
            .where((player) => player.isNotEmpty)
            .toSet()
            .toList(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Match event published.',
                'تم نشر فعالية المباراة.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    }
  }

  Future<void> _showResult(BuildContext context, MatchEvent match) async {
    final home = TextEditingController();
    final away = TextEditingController();
    final customScorerController = TextEditingController();
    final defaultPlayers = <String>[
      'No scorer',
      'Lamine Yamal',
      'Robert Lewandowski',
      'Raphinha',
      'Dani Olmo',
      'Pedri',
      'Ferran Torres',
      'Gavi',
      'Frenkie de Jong',
      'Fermín López',
      'Kylian Mbappé',
      'Vinícius Júnior',
      'Jude Bellingham',
      'Rodrygo',
      'Arda Güler',
      'Brahim Díaz',
      'Endrick',
      'Federico Valverde',
      'Luka Modrić',
      'Other Player',
    ];
    final scorerOptions = <String>{
      'No scorer',
      ...match.firstScorerOptions
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty),
      ...defaultPlayers,
    }.toList();

    var firstScorer = 'No scorer';
    var isOtherScorer = false;

    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final homeScore = int.tryParse(home.text);
          final awayScore = int.tryParse(away.text);
          final noGoals = (homeScore ?? -1) + (awayScore ?? -1) == 0;
          final effectiveFirstScorer = isOtherScorer
              ? customScorerController.text.trim()
              : firstScorer;
          final scorerIsValid = noGoals
              ? effectiveFirstScorer == 'No scorer'
              : effectiveFirstScorer.isNotEmpty &&
                    effectiveFirstScorer != 'No scorer';
          final valid =
              homeScore != null &&
              awayScore != null &&
              homeScore >= 0 &&
              awayScore >= 0 &&
              scorerIsValid;

          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 620),
            title: Text(
              abuText(
                context,
                'Review and publish result',
                'مراجعة النتيجة ونشرها',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AdminResultPreview(
                    match: match,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    firstScorer: effectiveFirstScorer,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: home,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {
                            final nextHome = int.tryParse(home.text) ?? 0;
                            final nextAway = int.tryParse(away.text) ?? 0;
                            if (nextHome == 0 && nextAway == 0) {
                              firstScorer = 'No scorer';
                              isOtherScorer = false;
                            } else if (firstScorer == 'No scorer') {
                              firstScorer = scorerOptions.length > 1
                                  ? scorerOptions[1]
                                  : '';
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: match.homeTeam,
                            helperText: abuText(
                              context,
                              'Official goals',
                              'الأهداف الرسمية',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: away,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {
                            final nextHome = int.tryParse(home.text) ?? 0;
                            final nextAway = int.tryParse(away.text) ?? 0;
                            if (nextHome == 0 && nextAway == 0) {
                              firstScorer = 'No scorer';
                              isOtherScorer = false;
                            } else if (firstScorer == 'No scorer') {
                              firstScorer = scorerOptions.length > 1
                                  ? scorerOptions[1]
                                  : '';
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: match.awayTeam,
                            helperText: abuText(
                              context,
                              'Official goals',
                              'الأهداف الرسمية',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: isOtherScorer
                        ? 'Other Player'
                        : (scorerOptions.contains(firstScorer)
                              ? firstScorer
                              : scorerOptions.first),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Official first scorer',
                        'أول مسجل رسمي للهدف الأول',
                      ),
                    ),
                    items: [
                      for (final player in scorerOptions)
                        DropdownMenuItem(
                          value: player,
                          child: Text(
                            player == 'No scorer'
                                ? abuText(
                                    context,
                                    'No scorer (0–0 clean sheet)',
                                    'لا يوجد مسجل (شباك نظيفة ٠-٠)',
                                  )
                                : player,
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      if (value == 'Other Player') {
                        isOtherScorer = true;
                      } else {
                        isOtherScorer = false;
                        firstScorer = value ?? 'No scorer';
                      }
                    }),
                  ),
                  if (isOtherScorer) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customScorerController,
                      decoration: InputDecoration(
                        labelText: abuText(
                          context,
                          'Enter player name',
                          'أدخل اسم اللاعب',
                        ),
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    abuText(
                      context,
                      'Publishing is final and securely calculates XP for each correct prediction component.',
                      'النشر نهائي ويبدأ احتساب XP بأمان لكل عنصر توقع صحيح.',
                    ),
                    style: TextStyle(color: _gold, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(abuText(context, 'CANCEL', 'إلغاء')),
              ),
              FilledButton.icon(
                onPressed: valid ? () => Navigator.pop(context, true) : null,
                icon: Icon(Icons.verified_rounded),
                label: Text(abuText(context, 'CALCULATE XP', 'احتساب XP')),
              ),
            ],
          );
        },
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      final effectiveFirstScorer = isOtherScorer
          ? customScorerController.text.trim()
          : firstScorer;
      await repository.publishMatchResult(
        matchId: match.id,
        homeScore: int.parse(home.text),
        awayScore: int.parse(away.text),
        firstScorer: effectiveFirstScorer,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Result published and correct-prediction XP calculated.',
                'تم نشر النتيجة واحتساب XP للتوقعات الصحيحة.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    }
  }

  Future<void> _showNotificationComposer(BuildContext context) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    XFile? selectedImage;
    dynamic selectedImageBytes;
    var scheduleEnabled = false;
    var scheduledFor = DateTime.now().add(const Duration(hours: 1));
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final canSubmit =
              titleController.text.trim().length >= 2 &&
              bodyController.text.trim().length >= 2 &&
              !saving;
          void refresh(String _) => setModalState(() {});

          return AlertDialog(
            backgroundColor: const Color(0xFF111622),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              abuText(modalContext, 'Send Notification', 'إرسال إشعار'),
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      abuText(
                        modalContext,
                        'Send to every active device whose notification access is enabled.',
                        'يُرسل إلى كل جهاز نشط فعّل إذن الإشعارات.',
                      ),
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      onChanged: refresh,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: abuText(
                          modalContext,
                          'Notification title',
                          'عنوان الإشعار',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bodyController,
                      onChanged: refresh,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: abuText(
                          modalContext,
                          'Message',
                          'نص الإشعار',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final selection = await _selectAdminImage(
                                      modalContext,
                                    );
                                    if (selection == null ||
                                        !modalContext.mounted) {
                                      return;
                                    }
                                    setModalState(() {
                                      selectedImage = selection.file;
                                      selectedImageBytes = selection.bytes;
                                    });
                                  },
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              selectedImage == null
                                  ? abuText(
                                      modalContext,
                                      'SELECT IMAGE (OPTIONAL)',
                                      'اختر صورة (اختياري)',
                                    )
                                  : selectedImage!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (selectedImage != null)
                          IconButton(
                            tooltip: abuText(
                              modalContext,
                              'Remove image',
                              'إزالة الصورة',
                            ),
                            onPressed: saving
                                ? null
                                : () => setModalState(() {
                                    selectedImage = null;
                                    selectedImageBytes = null;
                                  }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                    if (selectedImage != null) ...[
                      const SizedBox(height: 10),
                      _campaignImagePreview(
                        context: modalContext,
                        imageUrl: '',
                        imageBytes: selectedImageBytes,
                        height: 170,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        abuText(
                          modalContext,
                          'The image appears in supported Android notifications. iPhone receives the text notification; rich images require an iOS media extension that is not enabled yet.',
                          'تظهر الصورة في إشعارات أندرويد المدعومة. يستقبل الآيفون الإشعار النصي؛ صور الإشعارات الغنية تحتاج إضافة iOS غير مفعلة حالياً.',
                        ),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        abuText(
                          modalContext,
                          'Schedule for later',
                          'جدولة الإرسال لوقت لاحق',
                        ),
                      ),
                      subtitle: Text(
                        abuText(
                          modalContext,
                          'Turn off to send immediately.',
                          'أوقف الخيار للإرسال فوراً.',
                        ),
                      ),
                      value: scheduleEnabled,
                      onChanged: saving
                          ? null
                          : (value) => setModalState(() {
                              scheduleEnabled = value;
                              if (value &&
                                  !scheduledFor.isAfter(DateTime.now())) {
                                scheduledFor = DateTime.now().add(
                                  const Duration(hours: 1),
                                );
                              }
                            }),
                    ),
                    if (scheduleEnabled)
                      _AdminDateTile(
                        label: abuText(
                          modalContext,
                          'Send date and time',
                          'تاريخ ووقت الإرسال',
                        ),
                        value: scheduledFor,
                        onChanged: (value) =>
                            setModalState(() => scheduledFor = value),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(abuText(modalContext, 'CANCEL', 'إلغاء')),
              ),
              FilledButton.icon(
                onPressed: canSubmit
                    ? () async {
                        setModalState(() => saving = true);
                        try {
                          final title = titleController.text.trim();
                          final body = bodyController.text.trim();
                          final imageUrl = selectedImage == null
                              ? null
                              : await repository.uploadAnnouncementImage(
                                  selectedImage!,
                                );
                          final result = await repository
                              .createNotificationBroadcast(
                                title: title,
                                body: body,
                                imageUrl: imageUrl,
                                scheduledAt: scheduleEnabled
                                    ? scheduledFor
                                    : null,
                              );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!context.mounted) return;
                          final isScheduled = result['status'] == 'scheduled';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isScheduled
                                    ? abuText(
                                        context,
                                        'Notification scheduled successfully.',
                                        'تمت جدولة الإشعار بنجاح.',
                                      )
                                    : abuText(
                                        context,
                                        'Notification queued for delivery.',
                                        'تم وضع الإشعار في قائمة الإرسال.',
                                      ),
                              ),
                            ),
                          );
                        } catch (error) {
                          if (modalContext.mounted) {
                            setModalState(() => saving = false);
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              SnackBar(
                                content: Text(productionErrorMessage(error)),
                              ),
                            );
                          }
                        }
                      }
                    : null,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        scheduleEnabled
                            ? Icons.schedule_send_rounded
                            : Icons.send_rounded,
                      ),
                label: Text(
                  scheduleEnabled
                      ? abuText(modalContext, 'SCHEDULE', 'جدولة')
                      : abuText(modalContext, 'SEND NOW', 'إرسال الآن'),
                ),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    bodyController.dispose();
  }

  void _showExclusiveVideosManager(BuildContext context) {
    final youtubeIdCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    XFile? selectedThumbnail;
    dynamic selectedThumbnailBytes;
    bool memberOnly = false;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF111622),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            abuText(
              context,
              'Manage Exclusive Videos',
              'إدارة الفيديوهات الحصرية',
            ),
          ),
          content: SizedBox(
            width: 580,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Video Title',
                        'عنوان الفيديو',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: youtubeIdCtrl,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'YouTube Video Link or ID',
                        'رابط أو معرّف فيديو يوتيوب (غير مدرج)',
                      ),
                      hintText: 'https://youtu.be/... or dQw4w9WgXcQ',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Description (Optional)',
                        'الوصف (اختياري)',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final selection = await _selectAdminImage(context);
                            if (selection == null || !context.mounted) return;
                            setModalState(() {
                              selectedThumbnail = selection.file;
                              selectedThumbnailBytes = selection.bytes;
                            });
                          },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      selectedThumbnail == null
                          ? abuText(
                              context,
                              'SELECT THUMBNAIL (OPTIONAL)',
                              'اختر صورة الغلاف (اختياري)',
                            )
                          : selectedThumbnail!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selectedThumbnail != null) ...[
                    const SizedBox(height: 10),
                    _campaignImagePreview(
                      context: context,
                      imageUrl: '',
                      imageBytes: selectedThumbnailBytes,
                      height: 170,
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(
                      abuText(
                        context,
                        'Gold Members Only ⭐',
                        'مخصص للأعضاء الذهبيين فقط ⭐',
                      ),
                    ),
                    value: memberOnly,
                    onChanged: (val) => setModalState(() => memberOnly = val),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final rawLink = youtubeIdCtrl.text.trim();
                            if (titleCtrl.text.trim().isEmpty ||
                                rawLink.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    abuText(
                                      context,
                                      'Add a title and YouTube link.',
                                      'أضف عنواناً ورابط يوتيوب.',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }

                            final ytId = extractYoutubeVideoId(rawLink);
                            if (ytId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    abuText(
                                      context,
                                      'Enter a valid YouTube link or 11-character video ID.',
                                      'أدخل رابط يوتيوب صالحاً أو معرّف فيديو من 11 حرفاً.',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }
                            setModalState(() => saving = true);

                            try {
                              final thumbnailUrl = selectedThumbnail == null
                                  ? 'https://img.youtube.com/vi/$ytId/hqdefault.jpg'
                                  : await repository.uploadPostImage(
                                      selectedThumbnail!,
                                    );
                              await repository.createExclusiveVideo(
                                youtubeId: ytId,
                                title: titleCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                thumbnailUrl: thumbnailUrl,
                                memberOnly: memberOnly,
                              );
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      abuText(
                                        context,
                                        'Video published successfully!',
                                        'تم نشر الفيديو بنجاح!',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() => saving = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(productionErrorMessage(e)),
                                  ),
                                );
                              }
                            }
                          },
                    icon: Icon(Icons.add_rounded),
                    label: Text(
                      saving
                          ? abuText(context, 'Publishing...', 'جارٍ النشر...')
                          : abuText(context, 'Publish Video', 'نشر الفيديو'),
                    ),
                  ),
                  const Divider(height: 32),
                  Text(
                    abuText(context, 'Current Videos', 'الفيديوهات الحالية'),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<ExclusiveVideo>>(
                    stream: repository.watchManagedExclusiveVideos(),
                    builder: (context, snapshot) {
                      final vids = snapshot.data ?? const [];
                      if (vids.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            abuText(
                              context,
                              'No exclusive videos yet.',
                              'لا توجد فيديوهات منشورة حالياً.',
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: vids
                            .map(
                              (v) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    v.thumbnailUrl,
                                    width: 60,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        Icon(Icons.video_library),
                                  ),
                                ),
                                title: Text(
                                  v.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  v.memberOnly ? '⭐ Members Only' : 'Public',
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (confirmationContext) =>
                                          AlertDialog(
                                            title: Text(
                                              abuText(
                                                confirmationContext,
                                                'Delete this video?',
                                                'حذف هذا الفيديو؟',
                                              ),
                                            ),
                                            content: Text(v.title),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                  confirmationContext,
                                                  false,
                                                ),
                                                child: Text(
                                                  abuText(
                                                    confirmationContext,
                                                    'CANCEL',
                                                    'إلغاء',
                                                  ),
                                                ),
                                              ),
                                              FilledButton.icon(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: _red,
                                                ),
                                                onPressed: () => Navigator.pop(
                                                  confirmationContext,
                                                  true,
                                                ),
                                                icon: const Icon(
                                                  Icons.delete_rounded,
                                                ),
                                                label: Text(
                                                  abuText(
                                                    confirmationContext,
                                                    'DELETE',
                                                    'حذف',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                    );
                                    if (confirmed != true) return;
                                    try {
                                      await repository.deleteExclusiveVideo(
                                        v.id,
                                      );
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                productionErrorMessage(error),
                                              ),
                                            ),
                                          );
                                    }
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(abuText(context, 'Close', 'إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPointRules(BuildContext context) async {
    final current = await repository.loadPointRules();
    if (!context.mounted) return;
    final prediction = TextEditingController(
      text: (current['exactPrediction'] ?? 30).toInt().toString(),
    );
    final firstScorer = TextEditingController(
      text: (current['firstScorer'] ?? 20).toInt().toString(),
    );
    final winnerOutcome = TextEditingController(
      text: (current['winnerOutcome'] ?? 10).toInt().toString(),
    );
    final question = TextEditingController(
      text: (current['videoQuestion'] ?? 10).toInt().toString(),
    );
    final card = TextEditingController(
      text: (current['playerCard'] ?? 10).toInt().toString(),
    );
    final multiplier = TextEditingController(
      text: (current['memberMultiplier'] ?? 2.0).toString(),
    );
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(abuText(context, 'Point rules', 'قواعد النقاط')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: prediction,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Exact-score prediction (30 XP)',
                    'توقع النتيجة الدقيقة (٣٠ نقطة)',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: firstScorer,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'First-scorer prediction (20 XP)',
                    'توقع أول مسجل (٢٠ نقطة)',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: winnerOutcome,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Winner outcome (10 XP)',
                    'الفريق الفائز (١٠ نقاط)',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: question,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Video phrase question (10 XP)',
                    'سؤال العبارة السرية (١٠ نقاط)',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: card,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Player Guess (10 XP)',
                    'تخمين اللاعب (١٠ نقاط)',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: multiplier,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Member multiplier (2x)',
                    'مضاعف نقاط الأعضاء (٢×)',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(abuText(context, 'SAVE', 'حفظ')),
          ),
        ],
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      await repository.updatePointRules(
        exactPrediction: int.parse(prediction.text),
        firstScorer: int.parse(firstScorer.text),
        winnerOutcome: int.parse(winnerOutcome.text),
        videoQuestion: int.parse(question.text),
        playerCard: int.parse(card.text),
        memberMultiplier: double.parse(multiplier.text),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Point rules updated.',
                'تم تحديث قواعد النقاط.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    }
  }
}

String _localizedMatchStatus(BuildContext context, String status) =>
    switch (status) {
      'draft' => abuText(context, 'Draft', 'مسودة'),
      'open' => abuText(context, 'Open', 'مفتوحة'),
      'locked' => abuText(context, 'Locked', 'مقفلة'),
      'disabled' => abuText(context, 'Disabled', 'معطلة'),
      'completed' => abuText(context, 'Completed', 'مكتملة'),
      'archived' => abuText(context, 'Archived', 'مؤرشفة'),
      _ => status,
    };

class _AdminMatchPreview extends StatelessWidget {
  const _AdminMatchPreview({
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.homeLogoUrl,
    required this.awayLogoUrl,
    required this.kickoffAt,
  });

  final String homeTeam;
  final String awayTeam;
  final String competition;
  final String homeLogoUrl;
  final String awayLogoUrl;
  final DateTime kickoffAt;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _productionPrimary(context).withValues(alpha: .24),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              abuText(context, 'LIVE PREVIEW', 'معاينة مباشرة'),
              style: TextStyle(
                color: _productionPrimary(context),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            Text(
              competition.trim().isEmpty
                  ? abuText(context, 'Competition', 'البطولة')
                  : competition.trim(),
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _ProductionTeamBadge(team: homeTeam, source: homeLogoUrl.trim()),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                homeTeam.trim().isEmpty
                    ? abuText(context, 'Home team', 'الفريق المضيف')
                    : homeTeam.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('VS', style: _display(18, color: _muted)),
            ),
            Expanded(
              child: Text(
                awayTeam.trim().isEmpty
                    ? abuText(context, 'Away team', 'الفريق الضيف')
                    : awayTeam.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            _ProductionTeamBadge(team: awayTeam, source: awayLogoUrl.trim()),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${abuText(context, 'Kickoff', 'بدء المباراة')}: ${_productionDate(kickoffAt)}',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _AdminResultPreview extends StatelessWidget {
  const _AdminResultPreview({
    required this.match,
    required this.homeScore,
    required this.awayScore,
    required this.firstScorer,
  });

  final MatchEvent match;
  final int? homeScore;
  final int? awayScore;
  final String firstScorer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
    ),
    child: Column(
      children: [
        Text(
          match.competition.toUpperCase(),
          style: TextStyle(
            color: _gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ProductionTeamBadge(
              team: match.homeTeam,
              source: match.homeLogoUrl,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                match.homeTeam,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${homeScore ?? '–'}  :  ${awayScore ?? '–'}',
              style: _display(30, color: _productionPrimary(context)),
            ),
            Expanded(
              child: Text(
                match.awayTeam,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 9),
            _ProductionTeamBadge(
              team: match.awayTeam,
              source: match.awayLogoUrl,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          firstScorer.isEmpty
              ? abuText(
                  context,
                  'Select the official first scorer',
                  'اختر أول مسجل رسمي',
                )
              : '${abuText(context, 'First scorer', 'أول مسجل')}: $firstScorer',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _AdminDateTile extends StatelessWidget {
  const _AdminDateTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(_productionDate(value)),
    trailing: Icon(Icons.edit_calendar_rounded),
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 730)),
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(value),
      );
      if (time == null) return;
      onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    },
  );
}

class _ProductionSkeleton extends StatelessWidget {
  const _ProductionSkeleton({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: .35, end: .85),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOut,
      builder: (context, opacity, _) => Opacity(
        opacity: opacity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 124,
              height: 12,
              decoration: BoxDecoration(
                color: _line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 260,
              height: 26,
              decoration: BoxDecoration(
                color: _line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Spacer(),
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(
                  color: _productionPrimary(context).withValues(alpha: .85),
                  strokeWidth: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProductionEmpty extends StatelessWidget {
  const _ProductionEmpty({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 1100;
    final copy = Column(
      crossAxisAlignment: desktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: _display(desktop ? 25 : 22)),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: desktop ? TextAlign.start : TextAlign.center,
          style: TextStyle(color: _muted, height: 1.5),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: EdgeInsets.all(desktop ? 34 : 18),
        child: desktop
            ? Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _productionPrimary(context).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      icon,
                      color: _productionPrimary(context),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(child: copy),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 22),
                    OutlinedButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              )
            : Column(
                children: [
                  Icon(icon, color: _muted, size: 28),
                  const SizedBox(height: 8),
                  copy,
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

String _productionDate(DateTime date) {
  final local = date.toLocal();
  const months = [
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
  return '${local.day} ${months[local.month - 1]} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
