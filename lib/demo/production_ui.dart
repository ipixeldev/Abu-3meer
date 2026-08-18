part of 'fan_league_app.dart';

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
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: repository.authChanges,
    builder: (context, authSnapshot) {
      if (authSnapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionLoading();
      }
      final user = authSnapshot.data;
      if (user == null) return _ProductionAuth(repository: repository);
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
            return _ProductionFailure(
              message: productionErrorMessage(profileSnapshot.error!),
              onRetry: () => setState(() {}),
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
              onRetry: () => setState(() {}),
              onSignOut: repository.signOut,
            );
          }
          return _ProductionShell(repository: repository, profile: profile);
        },
      );
    },
  );
}

class _ProductionLoading extends StatelessWidget {
  const _ProductionLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: _ink,
    body: Stack(
      children: [
        Positioned.fill(child: _PitchBackdrop()),
        Center(
          child: SizedBox(
            width: 110,
            height: 110,
            child: _ProductionLottieLoader(),
          ),
        ),
      ],
    ),
  );
}

class _ProductionLottieLoader extends StatelessWidget {
  const _ProductionLottieLoader();
  @override
  Widget build(BuildContext context) => Lottie.asset(
    'assets/animations/ball-loading.json',
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const CircularProgressIndicator(color: _lime),
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
    // Arbitrary team and campaign CDNs frequently omit CORS headers. On web,
    // an HTML image element can display those assets without fetching bytes.
    webHtmlElementStrategy: kIsWeb
        ? WebHtmlElementStrategy.prefer
        : WebHtmlElementStrategy.never,
    errorBuilder: (_, _, _) => fallback,
  );
}

class _ProductionAuth extends StatefulWidget {
  const _ProductionAuth({required this.repository});
  final ProductionRepository repository;

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
    } catch (exception) {
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
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: abuText(context, 'Email', 'البريد الإلكتروني'),
                prefixIcon: const Icon(Icons.mail_outline_rounded),
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
                prefixIcon: const Icon(Icons.lock_outline_rounded),
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
              Text(error!, style: const TextStyle(color: _red, fontSize: 12)),
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
                backgroundColor: _lime,
                foregroundColor: _ink,
                padding: const EdgeInsets.all(17),
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      createAccount
                          ? abuText(context, 'CREATE ACCOUNT', 'إنشاء حساب')
                          : abuText(context, 'SIGN IN', 'تسجيل الدخول'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
            if (!createAccount)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : resetPassword,
                  child: Text(
                    abuText(context, 'FORGOT PASSWORD?', 'نسيت كلمة المرور؟'),
                  ),
                ),
              ),
            Row(
              children: [
                const Expanded(child: Divider(color: _line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    abuText(context, 'OR', 'أو'),
                    style: const TextStyle(color: _muted),
                  ),
                ),
                const Expanded(child: Divider(color: _line)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(widget.repository.signInWithGoogle),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: Text(
                abuText(
                  context,
                  'CONTINUE WITH GOOGLE',
                  'المتابعة باستخدام Google',
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(15),
                side: const BorderSide(color: _line),
              ),
            ),
            const SizedBox(height: 10),
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
        Text(AbuBrand.tagline, style: _display(14, color: _lime, spacing: 1.8)),
        const SizedBox(height: 8),
        Text(
          abuText(
            context,
            'Your prediction. Your knowledge. Your place on the leaderboard.',
            'توقعك. معرفتك. مكانك في لوحة المتصدرين.',
          ),
          style: const TextStyle(color: _muted, height: 1.55, fontSize: 14),
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
  final country = TextEditingController();
  String team = 'Barcelona';
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    displayName.text = widget.user.displayName ?? '';
  }

  @override
  void dispose() {
    username.dispose();
    displayName.dispose();
    country.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.completeOnboarding(
        username: username.text,
        displayName: displayName.text,
        country: country.text,
        supportedTeam: team,
        avatarUrl: widget.user.photoURL ?? '',
      );
    } catch (exception) {
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _CenteredProductionCard(
    icon: Icons.person_add_alt_1_rounded,
    title: abuText(context, 'BUILD YOUR PROFILE', 'أنشئ ملفك الشخصي'),
    body: abuText(
      context,
      'Choose the identity you will use on Abu 3meer leaderboards.',
      'اختر الهوية التي ستظهر بها في لوحات متصدري أبو عمير.',
    ),
    message: error,
    content: Column(
      children: [
        TextField(
          controller: username,
          decoration: InputDecoration(
            labelText: abuText(context, 'Unique username', 'اسم مستخدم فريد'),
            prefixText: '@',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: displayName,
          decoration: InputDecoration(
            labelText: abuText(context, 'Display name', 'الاسم الظاهر'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: country,
          decoration: InputDecoration(
            labelText: abuText(context, 'Country', 'الدولة'),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'Barcelona',
              label: Text(abuText(context, 'Barcelona', 'برشلونة')),
            ),
            ButtonSegment(
              value: 'Real Madrid',
              label: Text(abuText(context, 'Real Madrid', 'ريال مدريد')),
            ),
          ],
          selected: {team},
          onSelectionChanged: busy
              ? null
              : (selection) => setState(() => team = selection.first),
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(
          busy
              ? abuText(context, 'SAVING…', 'جارٍ الحفظ…')
              : abuText(context, 'ENTER ABU 3MEER', 'دخول أبو عمير'),
        ),
      ),
      TextButton(
        onPressed: busy ? null : widget.repository.signOut,
        child: Text(abuText(context, 'SIGN OUT', 'تسجيل الخروج')),
      ),
    ],
  );
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
                      Icon(icon, color: _lime, size: 42),
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
                        style: const TextStyle(color: _muted, height: 1.5),
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
                          style: const TextStyle(color: _gold, fontSize: 12),
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
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => _CenteredProductionCard(
    icon: Icons.cloud_off_rounded,
    title: abuText(
      context,
      'WE COULD NOT LOAD YOUR ACCOUNT',
      'تعذر تحميل حسابك',
    ),
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

class _ProductionShell extends StatefulWidget {
  const _ProductionShell({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionShell> createState() => _ProductionShellState();
}

class _ProductionShellState extends State<_ProductionShell> {
  int index = 0;
  StreamSubscription<LaunchAnnouncement?>? announcementSubscription;

  @override
  void initState() {
    super.initState();
    announcementSubscription = widget.repository
        .watchLaunchAnnouncement()
        .listen((announcement) {
          if (announcement == null || !mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showLaunchAnnouncement(context, announcement);
          });
        });
  }

  @override
  void dispose() {
    announcementSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = TemporaryMockData.instance.enabled
        ? TemporaryMockData.instance.profile(widget.profile)
        : widget.profile;
    final pages = <Widget>[
      _ProductionHome(
        repository: widget.repository,
        profile: profile,
        onOpenStreak: () => setState(() => index = 12),
      ),
      _ProductionMatches(repository: widget.repository),
      _ProductionLeaderboard(repository: widget.repository, profile: profile),
      _ProductionPoints(repository: widget.repository, profile: profile),
      _ProductionProfile(repository: widget.repository, profile: profile),
      _ProductionChallenges(repository: widget.repository),
      _ProductionGames(repository: widget.repository, profile: profile),
      _ProductionCommunity(repository: widget.repository, profile: profile),
      _ProductionFanWar(repository: widget.repository),
      _ProductionAchievements(profile: profile),
      _ProductionRewards(profile: profile),
      _ProductionSettings(profile: profile),
      _ProductionStreak(profile: profile),
      _ProductionObsOverlay(
        repository: widget.repository,
        profile: profile,
        onExit: () => setState(() => index = 0),
      ),
      if (profile.canManageContent)
        _ProductionAdmin(repository: widget.repository, profile: profile),
    ];
    if (index >= pages.length) index = 0;
    final items = <(IconData, String)>[
      (Icons.grid_view_rounded, abuText(context, 'Home', 'الرئيسية')),
      (Icons.sports_soccer_rounded, abuText(context, 'Predict', 'توقع')),
      (Icons.leaderboard_rounded, abuText(context, 'Leaders', 'الترتيب')),
      (Icons.receipt_long_rounded, abuText(context, 'Points', 'النقاط')),
      (Icons.person_rounded, abuText(context, 'Profile', 'حسابي')),
      (Icons.bolt_rounded, abuText(context, 'Challenges', 'التحديات')),
      (Icons.sports_esports_rounded, abuText(context, 'Games', 'الألعاب')),
      (Icons.forum_rounded, abuText(context, 'Community', 'المجتمع')),
      (Icons.shield_rounded, abuText(context, 'Fan War', 'حرب الجماهير')),
      (
        Icons.emoji_events_rounded,
        abuText(context, 'Achievements', 'الإنجازات'),
      ),
      (Icons.card_giftcard_rounded, abuText(context, 'Rewards', 'المكافآت')),
      (Icons.settings_rounded, abuText(context, 'Settings', 'الإعدادات')),
      (
        Icons.local_fire_department_rounded,
        abuText(context, 'Streak', 'سلسلة الأيام'),
      ),
      (Icons.live_tv_rounded, abuText(context, 'OBS Overlay', 'واجهة البث')),
      if (profile.canManageContent)
        (
          Icons.admin_panel_settings_rounded,
          abuText(context, 'Admin Studio', 'استوديو المشرف'),
        ),
    ];
    final desktop = MediaQuery.sizeOf(context).width >= 1100;
    const mobileIndexes = [0, 1, 6, 7, 4];
    final mobileSelected = mobileIndexes.indexOf(index);
    if (index == 13) return pages[index];
    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  const _LogoMark(size: 30),
                  const SizedBox(width: 10),
                  Text(
                    abuText(context, 'ABU 3MEER', 'أبو عمير'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              actions: [
                _Pill(
                  icon: Icons.stars_rounded,
                  text: '${profile.totalPoints}',
                  color: _gold,
                  compact: true,
                ),
                IconButton(
                  tooltip: abuText(context, 'Settings', 'الإعدادات'),
                  onPressed: () => setState(() => index = 11),
                  icon: const Icon(Icons.settings_rounded),
                ),
                if (!desktop)
                  PopupMenuButton<int>(
                    tooltip: abuText(context, 'More features', 'ميزات إضافية'),
                    onSelected: (value) => setState(() => index = value),
                    itemBuilder: (context) =>
                        List.generate(items.length, (itemIndex) {
                          if (mobileIndexes.contains(itemIndex) ||
                              itemIndex == 11) {
                            return null;
                          }
                          final item = items[itemIndex];
                          return PopupMenuItem<int>(
                            value: itemIndex,
                            child: Row(
                              children: [
                                Icon(item.$1, size: 19),
                                const SizedBox(width: 10),
                                Text(item.$2),
                              ],
                            ),
                          );
                        }).whereType<PopupMenuEntry<int>>().toList(),
                    icon: const Icon(Icons.apps_rounded),
                  ),
                if (profile.canManageContent)
                  IconButton(
                    tooltip: abuText(
                      context,
                      'Admin Dashboard',
                      'لوحة تحكم المشرف',
                    ),
                    onPressed: () => setState(() => index = 14),
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                  ),
                const SizedBox(width: 8),
              ],
            ),
      body: desktop
          ? _ProductionDesktopScaffold(
              items: items,
              selectedIndex: index,
              page: pages[index],
              profile: profile,
              onSelect: (value) => setState(() => index = value),
            )
          : pages[index],
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              height: 66,
              selectedIndex: mobileSelected < 0 ? 0 : mobileSelected,
              onDestinationSelected: (value) =>
                  setState(() => index = mobileIndexes[value]),
              destinations: mobileIndexes
                  .map((itemIndex) => items[itemIndex])
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.$1),
                      label: item.$2,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ProductionDesktopScaffold extends StatelessWidget {
  const _ProductionDesktopScaffold({
    required this.items,
    required this.selectedIndex,
    required this.page,
    required this.profile,
    required this.onSelect,
  });

  final List<(IconData, String)> items;
  final int selectedIndex;
  final Widget page;
  final AbuUserProfile profile;
  final ValueChanged<int> onSelect;

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
            Row(
              children: [
                const _LogoMark(size: 42),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abuText(context, 'ABU 3MEER', 'أبو عمير'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: .9,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        abuText(context, 'FAN PLATFORM', 'منصة الجماهير'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 10, bottom: 9),
              child: Text(
                abuText(context, 'WORKSPACES', 'مساحات العمل'),
                style: const TextStyle(
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
                    if (itemIndex == 5 || itemIndex == 11)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                        child: Text(
                          itemIndex == 5
                              ? abuText(context, 'ENGAGE', 'التفاعل')
                              : abuText(context, 'TOOLS', 'الأدوات'),
                          style: const TextStyle(
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: _surface2,
              leading: CircleAvatar(
                backgroundColor: _lime,
                foregroundColor: _ink,
                child: Text(
                  profile.displayName.isEmpty
                      ? '?'
                      : profile.displayName[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              title: Text(
                profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '@${profile.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 18),
              onTap: () => onSelect(4),
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
              decoration: const BoxDecoration(color: Color(0xFF0A0E14)),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[selectedIndex].$2.toUpperCase(),
                        style: const TextStyle(
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
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
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
                  ),
                  const SizedBox(width: 10),
                  _Pill(
                    icon: Icons.stars_rounded,
                    text: '${profile.totalPoints}',
                    color: _gold,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: abuText(context, 'Settings', 'الإعدادات'),
                    onPressed: () => onSelect(11),
                    icon: const Icon(Icons.settings_rounded),
                  ),
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
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final VoidCallback onOpenStreak;

  @override
  Widget build(BuildContext context) {
    final match = StreamBuilder<List<MatchEvent>>(
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
        final matches = snapshot.data ?? const [];
        if (matches.isEmpty) {
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
        return _ProductionMatchCard(
          event: matches.first,
          repository: repository,
        );
      },
    );
    return _PageFrame(
      kicker: profile.isYouTubeMember
          ? abuText(
              context,
              'YouTube Member · 2× points',
              'عضو يوتيوب · نقاط مضاعفة',
            )
          : abuText(context, 'Abu 3meer Community', 'مجتمع أبو عمير'),
      title: abuText(
        context,
        'Welcome, ${profile.displayName}',
        'مرحباً، ${profile.displayName}',
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 850) {
            return Column(
              children: [
                _ProductionPointsHero(profile: profile),
                const SizedBox(height: 16),
                _ProductionHomeStreakCard(
                  profile: profile,
                  onTap: onOpenStreak,
                ),
                const SizedBox(height: 16),
                match,
                const SizedBox(height: 16),
                _ProductionLatestVideoCard(repository: repository),
                const SizedBox(height: 16),
                _ProductionHomeActivityFeed(repository: repository),
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _ProductionPointsHero(profile: profile),
                        const SizedBox(height: 18),
                        match,
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _ProductionLatestVideoCard(repository: repository),
                        const SizedBox(height: 18),
                        _ProductionHomeStreakCard(
                          profile: profile,
                          onTap: onOpenStreak,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ProductionHomeActivityFeed(repository: repository),
            ],
          );
        },
      ),
    );
  }
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
    final weekProgress = (active % 7) / 7;
    final nextMilestone = active == 0 ? 1 : ((active ~/ 7) + 1) * 7;
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
                    child: const Icon(
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
                          style: const TextStyle(
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
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: _lime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: active > 0 && active % 7 == 0 ? 1 : weekProgress,
                  minHeight: 7,
                  backgroundColor: _line,
                  color: isToday ? _lime : _red,
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
                      color: isToday ? _lime : _red,
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
                    style: const TextStyle(color: _muted, fontSize: 10),
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
  const _ProductionLatestVideoCard({required this.repository});
  final ProductionRepository repository;

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
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: Container(
                        width: 52,
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: _ink.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Lottie.asset(
                          'assets/animations/youtube.json',
                          repeat: true,
                          fit: BoxFit.contain,
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
                      style: const TextStyle(
                        color: _lime,
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.play_circle_fill_rounded, color: _red),
                        const SizedBox(width: 8),
                        Text(
                          abuText(
                            context,
                            'WATCH ON YOUTUBE',
                            'شاهد على يوتيوب',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
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
      border: Border.all(color: _lime.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              abuText(context, 'CURRENT POINTS', 'النقاط الحالية'),
              style: const TextStyle(
                color: _lime,
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
                color: _lime,
              ),
            ),
            Expanded(
              child: _Metric(
                value: '${profile.seasonPoints}',
                label: abuText(context, 'THIS SEASON', 'هذا الموسم'),
                color: _gold,
              ),
            ),
            Expanded(
              child: _Metric(
                value: profile.supportedTeam == 'Barcelona' ? 'FCB' : 'RMA',
                label: abuText(context, 'YOUR TEAM', 'فريقك'),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProductionMatches extends StatelessWidget {
  const _ProductionMatches({required this.repository});
  final ProductionRepository repository;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      '100 base points · exact score',
      '١٠٠ نقطة أساسية · النتيجة الدقيقة',
    ),
    title: abuText(context, 'Predictions', 'التوقعات'),
    child: StreamBuilder<List<MatchEvent>>(
      stream: repository.watchMatches(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 260);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Could not load matches',
              'تعذر تحميل المباريات',
            ),
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final events = snapshot.data ?? const [];
        if (events.isEmpty) {
          return _ProductionEmpty(
            icon: Icons.sports_soccer_rounded,
            title: abuText(context, 'No matches yet', 'لا توجد مباريات بعد'),
            body: abuText(
              context,
              'An administrator has not published a match event.',
              'لم ينشر المشرف فعالية مباراة بعد.',
            ),
          );
        }
        return _ResponsiveGrid(
          minWidth: 420,
          children: events
              .map(
                (event) =>
                    _ProductionMatchCard(event: event, repository: repository),
              )
              .toList(),
        );
      },
    ),
  );
}

class _ProductionMatchCard extends StatelessWidget {
  const _ProductionMatchCard({required this.event, required this.repository});
  final MatchEvent event;
  final ProductionRepository repository;

  Future<void> predict(BuildContext context) async {
    var home = 0;
    var away = 0;
    var bothTeamsScore = false;
    final scorerOptions = <String>['No scorer', ...event.firstScorerOptions]
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toSet()
        .toList();
    var firstScorer = scorerOptions.first;
    final result = await showDialog<(int, int, String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
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
                                'Each correct pick earns its own points.',
                                'كل اختيار صحيح يمنح نقاطه الخاصة.',
                              ),
                              style: const TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: abuText(context, 'Close', 'إغلاق'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _PredictionSection(
                    title: abuText(context, 'EXACT SCORE', 'النتيجة الدقيقة'),
                    points: 100,
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
                    title: abuText(context, 'FIRST SCORER', 'أول مسجل'),
                    points: 250,
                    child: DropdownButtonFormField<String>(
                      initialValue: firstScorer,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: abuText(
                          context,
                          'Choose the first scorer',
                          'اختر أول مسجل',
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
                                      'No scorer (0–0)',
                                      'لا يوجد مسجل (٠–٠)',
                                    )
                                  : player,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setDialogState(
                        () => firstScorer = value ?? 'No scorer',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PredictionSection(
                    title: abuText(
                      context,
                      'BOTH TEAMS TO SCORE',
                      'هل يسجل الفريقان؟',
                    ),
                    points: 150,
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(abuText(context, 'YES', 'نعم')),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.close_rounded),
                            label: Text(abuText(context, 'NO', 'لا')),
                          ),
                        ],
                        selected: {bothTeamsScore},
                        onSelectionChanged: (selection) => setDialogState(
                          () => bothTeamsScore = selection.first,
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
                            'Potential reward: up to 500 points',
                            'المكافأة المحتملة: حتى ٥٠٠ نقطة',
                          ),
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(abuText(context, 'CANCEL', 'إلغاء')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, (
                          home,
                          away,
                          firstScorer,
                          bothTeamsScore,
                        )),
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
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await repository.submitPrediction(
        matchId: event.id,
        homeScore: result.$1,
        awayScore: result.$2,
        firstScorer: result.$3,
        bothTeamsScore: result.$4,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Prediction saved securely.',
                'تم حفظ توقعك بأمان.',
              ),
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
    final open =
        event.status == 'open' &&
        DateTime.now().isBefore(event.predictionClosesAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      event.competition.toUpperCase(),
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    _LiveDot(
                      text: _localizedMatchStatus(
                        context,
                        event.status,
                      ).toUpperCase(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ProductionTeamBadge(
                          team: event.homeTeam,
                          source: event.homeLogoUrl,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _ProductionTeamBadge(
                          team: event.awayTeam,
                          source: event.awayLogoUrl,
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${event.homeTeam}\nvs ${event.awayTeam}',
                        style: _display(21, height: 1.05),
                      ),
                    ),
                    Text(
                      event.homeScore == null
                          ? _productionDate(event.kickoffAt)
                          : '${event.homeScore} – ${event.awayScore}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: event.homeScore == null ? _muted : _lime,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed: open ? () => predict(context) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: _ink,
                  ),
                  child: Text(
                    open
                        ? abuText(context, 'MAKE YOUR PICKS', 'سجّل توقعاتك')
                        : event.status == 'completed'
                        ? abuText(context, 'RESULT PUBLISHED', 'تم نشر النتيجة')
                        : event.id.startsWith('external_')
                        ? abuText(
                            context,
                            'NEXT MATCH · EVENT OPENS SOON',
                            'المباراة القادمة · تفتح التوقعات قريباً',
                          )
                        : abuText(
                            context,
                            'PREDICTIONS CLOSED',
                            'أغلقت التوقعات',
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
                style: const TextStyle(
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
                '+$points ${abuText(context, 'PTS', 'نقطة')}',
                style: const TextStyle(
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
  const _ProductionTeamBadge({required this.team, required this.source});
  final String team;
  final String source;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final fallback = team.toLowerCase().contains('barcelona')
        ? 'assets/images/fcb.png'
        : team.toLowerCase().contains('real madrid')
        ? 'assets/images/rma.png'
        : '';
    final stableFallback = _ProductionTeamBadgeFallback(team: team);
    Widget image;
    // Our featured clubs use transparent bundled art. Other API-provided team
    // badges use an HTML image fallback on web to avoid CDN CORS failures.
    if (fallback.isNotEmpty) {
      image = Image.asset(fallback, fit: BoxFit.contain);
    } else if (source.startsWith('http')) {
      image = _ProductionRemoteImage(
        url: source,
        fit: BoxFit.contain,
        fallback: fallback.isEmpty
            ? stableFallback
            : Image.asset(fallback, fit: BoxFit.contain),
      );
    } else if (source.startsWith('assets/')) {
      image = Image.asset(source, fit: BoxFit.contain);
    } else {
      image = stableFallback;
    }
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .1),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(size * .25),
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
          colors: [_lime.withValues(alpha: .24), _blue.withValues(alpha: .18)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          initials,
          maxLines: 1,
          style: const TextStyle(
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
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
      ),
      Text('$value', style: _display(40)),
      IconButton(
        onPressed: value == 0 ? null : () => onChanged(value - 1),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
  bool monthly = true;

  int _pointsFor(LeaderboardEntry entry) =>
      monthly ? entry.monthlyPoints : entry.seasonPoints;

  Widget _periodControl(BuildContext context) => SegmentedButton<bool>(
    segments: [
      ButtonSegment(
        value: true,
        label: Text(abuText(context, 'MONTHLY', 'شهري')),
      ),
      ButtonSegment(
        value: false,
        label: Text(abuText(context, 'SEASON', 'الموسم')),
      ),
    ],
    selected: {monthly},
    onSelectionChanged: (value) => setState(() => monthly = value.first),
  );

  Widget _mobileLeaderboard(
    BuildContext context,
    List<LeaderboardEntry> entries,
  ) => Column(
    children: [
      _periodControl(context),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: List.generate(entries.length, (index) {
            final entry = entries[index];
            final mine = entry.uid == widget.profile.uid;
            return ListTile(
              tileColor: mine ? _lime.withValues(alpha: .08) : null,
              leading: CircleAvatar(
                backgroundColor: index < 5 ? _gold : _surface2,
                foregroundColor: _ink,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              title: Text(
                '@${entry.username}',
                style: TextStyle(
                  fontWeight: mine ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${entry.supportedTeam}${entry.isMember ? ' · 2× MEMBER' : ''}',
              ),
              trailing: Text(
                '${_pointsFor(entry)}',
                style: _display(20, color: index < 5 ? _gold : Colors.white),
              ),
            );
          }),
        ),
      ),
    ],
  );

  Widget _desktopLeaderboard(
    BuildContext context,
    List<LeaderboardEntry> entries,
  ) {
    final myIndex = entries.indexWhere(
      (entry) => entry.uid == widget.profile.uid,
    );
    final leaderPoints = entries.isEmpty ? 0 : _pointsFor(entries.first);
    final myPoints = myIndex < 0 ? 0 : _pointsFor(entries[myIndex]);
    final prizeCutoff = entries.isEmpty
        ? 0
        : _pointsFor(entries[math.min(4, entries.length - 1)]);
    final gapToLeader = math.max(0, leaderPoints - myPoints);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 300, child: _periodControl(context)),
              const SizedBox(width: 18),
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.groups_rounded,
                  label: abuText(context, 'Ranked fans', 'المشجعون المصنفون'),
                  value: '${entries.length}',
                  detail: abuText(
                    context,
                    'Verified competitors',
                    'متنافسون موثقون',
                  ),
                  color: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.emoji_events_rounded,
                  label: abuText(context, 'Prize cutoff', 'حد التأهل'),
                  value: '$prizeCutoff',
                  detail: abuText(
                    context,
                    'Top five points',
                    'نقاط الخمسة الأوائل',
                  ),
                  color: _gold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProductionDesktopKpi(
                  icon: Icons.military_tech_rounded,
                  label: abuText(context, 'Your standing', 'ترتيبك'),
                  value: myIndex < 0 ? '—' : '#${myIndex + 1}',
                  detail: myIndex < 0
                      ? abuText(
                          context,
                          'Earn points to enter',
                          'اكسب نقاطاً للدخول',
                        )
                      : abuText(context, '$myPoints points', '$myPoints نقطة'),
                  color: _lime,
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
                child: _ProductionLeaderboardTable(
                  entries: entries,
                  profileUid: widget.profile.uid,
                  pointsFor: _pointsFor,
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
                            const Icon(
                              Icons.sports_score_rounded,
                              color: _lime,
                              size: 28,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              abuText(
                                context,
                                'YOUR RACE TO #1',
                                'سباقك نحو المركز الأول',
                              ),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              myIndex < 0 ? '—' : '#${myIndex + 1}',
                              style: _display(46, color: _lime),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              gapToLeader == 0 && myIndex == 0
                                  ? abuText(
                                      context,
                                      'You lead this table.',
                                      'أنت في صدارة الترتيب.',
                                    )
                                  : abuText(
                                      context,
                                      '$gapToLeader points behind the leader',
                                      'تبتعد $gapToLeader نقطة عن المتصدر',
                                    ),
                              style: const TextStyle(
                                color: _muted,
                                height: 1.4,
                              ),
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
                              abuText(context, 'PRIZE ZONE', 'منطقة الجوائز'),
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              abuText(
                                context,
                                'Positions 1–5 qualify. The cutoff updates live whenever verified points are awarded.',
                                'المراكز من 1 إلى 5 تتأهل. يتحدث الحد فور احتساب النقاط.',
                              ),
                              style: const TextStyle(
                                color: _muted,
                                height: 1.5,
                              ),
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
      'Top 5 qualify for prizes',
      'أفضل ٥ يتأهلون للجوائز',
    ),
    title: abuText(context, 'Leaderboard', 'لوحة المتصدرين'),
    child: StreamBuilder<List<LeaderboardEntry>>(
      stream: widget.repository.watchLeaderboard(monthly: monthly),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: _periodControl(context)),
              const SizedBox(height: 16),
              const _ProductionSkeleton(height: 300),
            ],
          );
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Leaderboard unavailable',
              'لوحة المتصدرين غير متاحة',
            ),
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final entries = snapshot.data ?? const [];
        final desktop = MediaQuery.sizeOf(context).width >= 1100;
        if (entries.isEmpty) {
          if (desktop) return _desktopLeaderboard(context, entries);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: _periodControl(context)),
              const SizedBox(height: 16),
              _ProductionEmpty(
                icon: Icons.leaderboard_rounded,
                title: abuText(
                  context,
                  'The race starts here',
                  'يبدأ السباق هنا',
                ),
                body: abuText(
                  context,
                  'Rankings appear when users earn their first real points.',
                  'يظهر الترتيب عندما يكسب المستخدمون أول نقاط حقيقية.',
                ),
              ),
            ],
          );
        }
        return desktop
            ? _desktopLeaderboard(context, entries)
            : _mobileLeaderboard(context, entries);
      },
    ),
  );
}

class _ProductionLeaderboardTable extends StatelessWidget {
  const _ProductionLeaderboardTable({
    required this.entries,
    required this.profileUid,
    required this.pointsFor,
  });

  final List<LeaderboardEntry> entries;
  final String profileUid;
  final int Function(LeaderboardEntry entry) pointsFor;

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
                  abuText(context, 'POINTS', 'النقاط'),
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
                const Icon(Icons.leaderboard_rounded, color: _muted),
                const SizedBox(width: 10),
                Text(
                  abuText(
                    context,
                    'The first verified points will start the table.',
                    'أول نقاط موثقة ستبدأ الترتيب.',
                  ),
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        for (var index = 0; index < entries.length; index++)
          _ProductionLeaderboardDesktopRow(
            entry: entries[index],
            index: index,
            mine: entries[index].uid == profileUid,
            points: pointsFor(entries[index]),
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
    required this.entry,
    required this.index,
    required this.mine,
    required this.points,
  });

  final LeaderboardEntry entry;
  final int index;
  final bool mine;
  final int points;

  @override
  Widget build(BuildContext context) => Container(
    color: mine ? _lime.withValues(alpha: .075) : Colors.transparent,
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
                color: index < 5 ? _gold.withValues(alpha: .16) : _surface2,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: index < 5 ? _gold : Colors.white,
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
                foregroundColor: mine ? _lime : Colors.white,
                child: Text(
                  entry.username.isEmpty
                      ? '?'
                      : entry.username[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
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
                  style: const TextStyle(color: _muted),
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
            '$points',
            textAlign: TextAlign.end,
            style: _display(21, color: index < 5 ? _gold : Colors.white),
          ),
        ),
      ],
    ),
  );
}

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
                backgroundColor: _lime.withValues(alpha: .12),
                child: Icon(_pointSourceIcon(entry.sourceType), color: _lime),
              ),
              title: Text(entry.reason),
              subtitle: Text(
                '${_pointSourceLabel(context, entry.sourceType)} · '
                '${entry.basePoints} × ${entry.multiplier.toStringAsFixed(entry.multiplier % 1 == 0 ? 0 : 1)} · '
                '${_productionDate(entry.createdAt)}',
              ),
              trailing: Text(
                '+${entry.finalPoints}',
                style: _display(20, color: _lime),
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
                          color: _lime,
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
                          style: const TextStyle(
                            color: _lime,
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
                          style: const TextStyle(color: _muted, height: 1.45),
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
                            style: const TextStyle(color: _muted),
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
                  style: const TextStyle(
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
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
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
                const Icon(Icons.receipt_long_rounded, color: _muted),
                const SizedBox(width: 10),
                Text(
                  abuText(
                    context,
                    'Verified transactions will appear here.',
                    'ستظهر العمليات الموثقة هنا.',
                  ),
                  style: const TextStyle(color: _muted),
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
                          color: _lime.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          _pointSourceIcon(entry.sourceType),
                          color: _lime,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _productionDate(entry.createdAt),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
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
                    style: const TextStyle(color: _muted),
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
                    style: _display(20, color: _lime),
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
          Icon(_pointSourceIcon(source), color: _lime, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pointSourceLabel(context, source),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text('$points', style: _display(17, color: _lime)),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          minHeight: 7,
          value: (points / total).clamp(0, 1).toDouble(),
          backgroundColor: _surface2,
          valueColor: const AlwaysStoppedAnimation(_lime),
        ),
      ),
    ],
  );
}

String _pointSourceLabel(BuildContext context, String source) =>
    switch (source) {
      'exactPrediction' => abuText(context, 'Prediction', 'توقع'),
      'firstScorer' => abuText(context, 'First scorer', 'أول مسجل'),
      'bothTeamsScore' => abuText(
        context,
        'Both teams to score',
        'تسجيل الفريقين',
      ),
      'videoQuestion' => abuText(context, 'Video challenge', 'تحدي الفيديو'),
      'playerCard' => abuText(context, 'Player Card', 'بطاقة اللاعب'),
      _ => source.isEmpty ? abuText(context, 'Other', 'أخرى') : source,
    };

IconData _pointSourceIcon(String source) => switch (source) {
  'exactPrediction' => Icons.sports_soccer_rounded,
  'firstScorer' => Icons.person_pin_circle_rounded,
  'bothTeamsScore' => Icons.compare_arrows_rounded,
  'videoQuestion' => Icons.play_circle_fill_rounded,
  'playerCard' => Icons.style_rounded,
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
    final username = TextEditingController(text: profile.username);
    final name = TextEditingController(text: profile.displayName);
    final country = TextEditingController(text: profile.country);
    var team = profile.supportedTeam;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(abuText(context, 'Edit profile', 'تعديل الملف الشخصي')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: username,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Username', 'اسم المستخدم'),
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Name', 'الاسم'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: country,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Country', 'الدولة'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'Barcelona',
                        label: Text(abuText(context, 'Barcelona', 'برشلونة')),
                      ),
                      ButtonSegment(
                        value: 'Real Madrid',
                        label: Text(
                          abuText(context, 'Real Madrid', 'ريال مدريد'),
                        ),
                      ),
                    ],
                    selected: {team},
                    onSelectionChanged: (value) =>
                        setDialogState(() => team = value.first),
                  ),
                ],
              ),
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
      ),
    );
    if (save != true || !mounted) return;
    try {
      await widget.repository.updateProfile(
        username: username.text,
        displayName: name.text,
        country: country.text,
        supportedTeam: team,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(context, 'Profile saved.', 'تم حفظ الملف الشخصي.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
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
      child: LayoutBuilder(
        builder: (context, box) {
          final card = Center(
            child: SizedBox(
              width: 320,
              height: 448,
              child: _InteractiveFanCard(
                profile: profile,
                temporaryImage: temporaryImage,
              ),
            ),
          );
          final controls = Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(profile.displayName, style: _display(29)),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.country} · ${profile.supportedTeam}',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 18),
                  if (profile.isYouTubeMember)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _LiveDot(
                        text: abuText(
                          context,
                          'YOUTUBE MEMBER · 2×',
                          'عضو يوتيوب · 2×',
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: editProfile,
                    icon: const Icon(Icons.edit_rounded),
                    label: Text(
                      abuText(
                        context,
                        'EDIT NAME & USERNAME',
                        'تعديل الاسم واسم المستخدم',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: pickingImage ? null : pickTemporaryImage,
                    icon: pickingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_rounded),
                    label: Text(
                      pickingImage
                          ? abuText(
                              context,
                              'OPENING PHOTO LIBRARY…',
                              'جارٍ فتح مكتبة الصور…',
                            )
                          : abuText(
                              context,
                              'TRY A PHOTO ON THE CARD',
                              'جرّب صورة على البطاقة',
                            ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    abuText(
                      context,
                      'Preview only: this image stays in memory and is not uploaded or saved.',
                      'للمعاينة فقط: تبقى الصورة في الذاكرة ولا يتم رفعها أو حفظها.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _gold, fontSize: 10),
                  ),
                  if (temporaryImage != null)
                    TextButton(
                      onPressed: () => setState(() => temporaryImage = null),
                      child: Text(
                        abuText(
                          context,
                          'REMOVE PREVIEW PHOTO',
                          'إزالة صورة المعاينة',
                        ),
                      ),
                    ),
                  const Divider(height: 30),
                  OutlinedButton.icon(
                    onPressed: widget.repository.signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(abuText(context, 'SIGN OUT', 'تسجيل الخروج')),
                  ),
                ],
              ),
            ),
          );
          final primary = box.maxWidth >= 820
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: card),
                    const SizedBox(width: 28),
                    Expanded(flex: 6, child: controls),
                  ],
                )
              : Column(children: [card, const SizedBox(height: 20), controls]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: 20),
              _ProductionProfileSummary(profile: profile),
              const SizedBox(height: 20),
              _ProductionRecentActivity(
                repository: widget.repository,
                profile: profile,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductionProfileSummary extends StatelessWidget {
  const _ProductionProfileSummary({required this.profile});
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final demo = TemporaryMockData.instance.enabled;
    final stats = <(String, String)>[
      (
        '${profile.totalPoints}',
        abuText(context, 'TOTAL POINTS', 'إجمالي النقاط'),
      ),
      ('${profile.monthlyPoints}', abuText(context, 'MONTHLY', 'شهري')),
      ('${profile.seasonPoints}', abuText(context, 'SEASON', 'الموسم')),
      (demo ? '#342' : '—', abuText(context, 'MONTHLY RANK', 'الترتيب الشهري')),
      (
        demo ? '68%' : '—',
        abuText(context, 'PREDICTION ACCURACY', 'دقة التوقعات'),
      ),
      (
        abuText(
          context,
          '${profile.currentStreak} DAYS',
          '${profile.currentStreak} يوماً',
        ),
        abuText(context, 'CURRENT STREAK', 'السلسلة الحالية'),
      ),
      (demo ? '12 / 20' : '0', abuText(context, 'ACHIEVEMENTS', 'الإنجازات')),
      (demo ? '4' : '0', abuText(context, 'PLAYER CARDS', 'بطاقات اللاعبين')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              abuText(context, 'PROFILE OVERVIEW', 'ملخص الملف الشخصي'),
              style: _display(21),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: stats
                  .map(
                    (stat) => Container(
                      width: 180,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stat.$1, style: _display(22, color: _lime)),
                          const SizedBox(height: 3),
                          Text(
                            stat.$2,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
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
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1FC8FF38),
                    child: Icon(Icons.add_rounded, color: _lime),
                  ),
                  title: Text(entry.reason),
                  subtitle: Text(_productionDate(entry.createdAt)),
                  trailing: Text(
                    '+${entry.finalPoints}',
                    style: _display(18, color: _lime),
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

class _ProductionSettings extends StatelessWidget {
  const _ProductionSettings({required this.profile});
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final preferences = AbuAppPreferences.instance;
    final mockData = TemporaryMockData.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([preferences, mockData]),
      builder: (context, _) => _PageFrame(
        kicker: abuText(context, 'Personalize Abu 3meer', 'خصص تطبيق أبو عمير'),
        title: abuText(context, 'Settings', 'الإعدادات'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 920;
            final experience = _SettingsPanel(
              icon: Icons.tune_rounded,
              title: abuText(context, 'EXPERIENCE', 'تجربة الاستخدام'),
              children: [
                ListTile(
                  leading: const Icon(Icons.contrast_rounded, color: _lime),
                  title: Text(abuText(context, 'Appearance', 'المظهر')),
                  subtitle: Text(
                    abuText(
                      context,
                      'Choose the theme used across the app.',
                      'اختر المظهر المستخدم في التطبيق.',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode_rounded),
                          label: Text(abuText(context, 'Dark', 'داكن')),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode_rounded),
                          label: Text(abuText(context, 'Light', 'فاتح')),
                        ),
                      ],
                      selected: {preferences.themeMode},
                      onSelectionChanged: (selection) =>
                          preferences.setThemeMode(selection.first),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: _lime),
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
                    'Opening, closing and kickoff alerts.',
                    'تنبيهات فتح وإغلاق التوقعات وبدء المباراة.',
                  ),
                  value: preferences.matchNotifications,
                  onChanged: preferences.setMatchNotifications,
                ),
                const Divider(height: 1),
                _SettingsNotificationTile(
                  icon: Icons.bolt_rounded,
                  title: abuText(context, 'New challenges', 'التحديات الجديدة'),
                  subtitle: abuText(
                    context,
                    'Video phrases, quizzes and Player Cards.',
                    'عبارات الفيديو والاختبارات وبطاقات اللاعبين.',
                  ),
                  value: preferences.challengeNotifications,
                  onChanged: preferences.setChallengeNotifications,
                ),
                const Divider(height: 1),
                _SettingsNotificationTile(
                  icon: Icons.stars_rounded,
                  title: abuText(
                    context,
                    'Points and rewards',
                    'النقاط والمكافآت',
                  ),
                  subtitle: abuText(
                    context,
                    'Point awards, achievements and redemptions.',
                    'النقاط والإنجازات وعمليات الاستبدال.',
                  ),
                  value: preferences.rewardNotifications,
                  onChanged: preferences.setRewardNotifications,
                ),
                const Divider(height: 1),
                _SettingsNotificationTile(
                  icon: Icons.campaign_rounded,
                  title: abuText(
                    context,
                    'News and posts',
                    'الأخبار والمنشورات',
                  ),
                  subtitle: abuText(
                    context,
                    'Updates published by Abu 3meer.',
                    'التحديثات التي ينشرها أبو عمير.',
                  ),
                  value: preferences.newsNotifications,
                  onChanged: preferences.setNewsNotifications,
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
                          'Member points activate only after secure verification with the creator\'s YouTube account.',
                          'تتفعل نقاط الأعضاء فقط بعد التحقق الآمن عبر حساب منشئ قناة يوتيوب.',
                        ),
                        style: const TextStyle(color: _muted, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://www.youtube.com/channel/${AbuExternalContentService.youtubeChannelId}/join',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded),
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
            final testing = _SettingsPanel(
              color: _gold.withValues(alpha: .07),
              icon: Icons.science_rounded,
              title: abuText(context, 'DEVELOPER PREVIEW', 'معاينة المطور'),
              children: [
                SwitchListTile.adaptive(
                  value: mockData.enabled,
                  onChanged: mockData.setEnabled,
                  secondary: Icon(
                    mockData.enabled
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: _gold,
                  ),
                  title: Text(
                    abuText(
                      context,
                      'Temporary mock data',
                      'بيانات تجريبية مؤقتة',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    abuText(
                      context,
                      'Testing only. Sample content is isolated from production data and can be removed before launch.',
                      'للاختبار فقط. المحتوى التجريبي معزول عن بيانات الإنتاج ويمكن حذفه قبل الإطلاق.',
                    ),
                  ),
                ),
              ],
            );

            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: desktop
                  ? Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: experience),
                            const SizedBox(width: 18),
                            Expanded(child: notifications),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: membership),
                            const SizedBox(width: 18),
                            Expanded(child: testing),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        experience,
                        const SizedBox(height: 14),
                        notifications,
                        const SizedBox(height: 14),
                        membership,
                        const SizedBox(height: 14),
                        testing,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
          child: Row(
            children: [
              Icon(icon, color: _lime),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
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

class _SettingsNotificationTile extends StatelessWidget {
  const _SettingsNotificationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    value: value,
    onChanged: onChanged,
    secondary: Icon(icon, color: value ? _lime : _muted),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
  );
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
        _ProductionAdminTools(repository: repository, profile: profile),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (profile.isAdmin) ...[
              FilledButton.icon(
                onPressed: () => _showCreateMatch(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  abuText(context, 'CREATE MATCH EVENT', 'إنشاء فعالية مباراة'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showPointRules(context),
                icon: const Icon(Icons.tune_rounded),
                label: Text(abuText(context, 'POINT RULES', 'قواعد النقاط')),
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
                      (match) => ListTile(
                        leading: SizedBox(
                          width: 96,
                          child: Row(
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
                            ],
                          ),
                        ),
                        title: Text('${match.homeTeam} vs ${match.awayTeam}'),
                        subtitle: Text(
                          '${match.competition} · ${_localizedMatchStatus(context, match.status)} · ${_productionDate(match.kickoffAt)}',
                        ),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<String>(
                              value:
                                  const [
                                    'draft',
                                    'open',
                                    'locked',
                                    'disabled',
                                    'completed',
                                    'archived',
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
                                  child: Text(
                                    abuText(context, 'Completed', 'مكتملة'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'archived',
                                  child: Text(
                                    abuText(context, 'Archived', 'مؤرشفة'),
                                  ),
                                ),
                              ],
                              onChanged: (status) async {
                                if (status == null) return;
                                try {
                                  await repository.setMatchStatus(
                                    matchId: match.id,
                                    status: status,
                                  );
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
                                }
                              },
                            ),
                            if (match.status != 'completed')
                              IconButton(
                                tooltip: abuText(
                                  context,
                                  'Publish result',
                                  'نشر النتيجة',
                                ),
                                onPressed: () => _showResult(context, match),
                                icon: const Icon(Icons.flag_rounded),
                              ),
                          ],
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
    final firstScorers = TextEditingController(
      text: 'No scorer, Lamine Yamal, Raphinha, Kylian Mbappé, Vinícius Júnior',
    );
    var kickoff = DateTime.now().add(const Duration(days: 2));
    var opens = DateTime.now();
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
                    homeLogoUrl: homeLogo.text,
                    awayLogoUrl: awayLogo.text,
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
                  TextField(
                    controller: homeLogo,
                    onChanged: refresh,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Home team logo URL (optional)',
                        'رابط شعار المضيف (اختياري)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: awayLogo,
                    onChanged: refresh,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Away team logo URL (optional)',
                        'رابط شعار الضيف (اختياري)',
                      ),
                    ),
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
                                  if (competition.text.trim().isEmpty) {
                                    competition.text = teams[0]!.league;
                                  }
                                }
                                if (teams[1] != null) {
                                  away.text = teams[1]!.name;
                                  awayLogo.text = teams[1]!.badgeUrl;
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
                          : const Icon(Icons.travel_explore_rounded),
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
                    onChanged: (value) => setDialogState(() => kickoff = value),
                  ),
                  if (!canCreate) ...[
                    const SizedBox(height: 8),
                    Text(
                      abuText(
                        context,
                        'Add both teams and a competition. Opening must be before closing, and closing before kickoff.',
                        'أضف الفريقين والبطولة. يجب أن يكون الفتح قبل الإغلاق، والإغلاق قبل بدء المباراة.',
                      ),
                      style: const TextStyle(color: _gold, fontSize: 11),
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
                icon: const Icon(Icons.publish_rounded),
                label: Text(abuText(context, 'CREATE', 'إنشاء')),
              ),
            ],
          );
        },
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      await repository.createMatch(
        homeTeam: home.text,
        awayTeam: away.text,
        competition: competition.text,
        kickoffAt: kickoff,
        predictionOpensAt: opens,
        predictionClosesAt: closes,
        homeLogoUrl: homeLogo.text,
        awayLogoUrl: awayLogo.text,
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
    final scorerOptions =
        <String>[
              if (match.firstScorerOptions.isNotEmpty) 'No scorer',
              ...match.firstScorerOptions,
            ]
            .map((player) => player.trim())
            .where((player) => player.isNotEmpty)
            .toSet()
            .toList();
    var firstScorer = scorerOptions.isEmpty ? '' : scorerOptions.first;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final homeScore = int.tryParse(home.text);
          final awayScore = int.tryParse(away.text);
          final noGoals = (homeScore ?? -1) + (awayScore ?? -1) == 0;
          final scorerIsValid = noGoals
              ? firstScorer == 'No scorer'
              : firstScorer.isNotEmpty && firstScorer != 'No scorer';
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
                    firstScorer: firstScorer,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: home,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {
                            final nextHome = int.tryParse(home.text);
                            final nextAway = int.tryParse(away.text);
                            if (nextHome == 0 && nextAway == 0) {
                              firstScorer = 'No scorer';
                            } else if (scorerOptions.isEmpty &&
                                firstScorer == 'No scorer') {
                              firstScorer = '';
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
                            final nextHome = int.tryParse(home.text);
                            final nextAway = int.tryParse(away.text);
                            if (nextHome == 0 && nextAway == 0) {
                              firstScorer = 'No scorer';
                            } else if (scorerOptions.isEmpty &&
                                firstScorer == 'No scorer') {
                              firstScorer = '';
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
                  const SizedBox(height: 12),
                  if (scorerOptions.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: firstScorer,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: abuText(
                          context,
                          'Official first scorer',
                          'أول مسجل رسمي',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(
                            abuText(
                              context,
                              'No scorer (0–0 only)',
                              'لا يوجد مسجل (٠–٠ فقط)',
                            ),
                          ),
                        ),
                        for (final player in scorerOptions)
                          DropdownMenuItem(
                            value: player,
                            child: Text(
                              player == 'No scorer'
                                  ? abuText(
                                      context,
                                      'No scorer (0–0)',
                                      'لا يوجد مسجل (٠–٠)',
                                    )
                                  : player,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => firstScorer = value ?? ''),
                    )
                  else
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: abuText(
                          context,
                          'Official first scorer',
                          'أول مسجل رسمي',
                        ),
                        helperText: abuText(
                          context,
                          'Required when at least one goal was scored.',
                          'مطلوب عند تسجيل هدف واحد على الأقل.',
                        ),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => firstScorer = value.trim()),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    abuText(
                      context,
                      'Publishing is final and starts secure reward processing for exact score, first scorer and both teams to score.',
                      'النشر نهائي ويبدأ احتساب مكافآت النتيجة الدقيقة وأول مسجل وتسجيل الفريقين بأمان.',
                    ),
                    style: const TextStyle(color: _gold, fontSize: 11),
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
                icon: const Icon(Icons.verified_rounded),
                label: Text(
                  abuText(context, 'PROCESS REWARDS', 'احتساب المكافآت'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      await repository.publishMatchResult(
        matchId: match.id,
        homeScore: int.parse(home.text),
        awayScore: int.parse(away.text),
        firstScorer: firstScorer,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Result published and rewards processed.',
                'تم نشر النتيجة واحتساب المكافآت.',
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

  Future<void> _showPointRules(BuildContext context) async {
    final prediction = TextEditingController(text: '100');
    final firstScorer = TextEditingController(text: '250');
    final bothTeamsScore = TextEditingController(text: '150');
    final question = TextEditingController(text: '40');
    final card = TextEditingController(text: '20');
    final multiplier = TextEditingController(text: '2');
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
                    'Exact-score prediction',
                    'توقع النتيجة الدقيقة',
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
                    'First-scorer prediction',
                    'توقع أول مسجل',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bothTeamsScore,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(
                    context,
                    'Both teams to score',
                    'تسجيل الفريقين',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: question,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Video question', 'سؤال الفيديو'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: card,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Player Card', 'بطاقة اللاعب'),
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
                    'Member multiplier',
                    'مضاعف نقاط الأعضاء',
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
        bothTeamsScore: int.parse(bothTeamsScore.text),
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
      border: Border.all(color: _lime.withValues(alpha: .24)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              abuText(context, 'LIVE PREVIEW', 'معاينة مباشرة'),
              style: const TextStyle(
                color: _lime,
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
              style: const TextStyle(color: _muted, fontSize: 11),
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
                style: const TextStyle(fontWeight: FontWeight.w800),
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
                style: const TextStyle(fontWeight: FontWeight.w800),
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
          style: const TextStyle(color: _muted, fontSize: 11),
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
          style: const TextStyle(
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
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${homeScore ?? '–'}  :  ${awayScore ?? '–'}',
              style: _display(30, color: _lime),
            ),
            Expanded(
              child: Text(
                match.awayTeam,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w800),
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
          style: const TextStyle(color: _muted, fontSize: 11),
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
    trailing: const Icon(Icons.edit_calendar_rounded),
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
                  color: _lime.withValues(alpha: .85),
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
          style: const TextStyle(color: _muted, height: 1.5),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: EdgeInsets.all(desktop ? 34 : 28),
        child: desktop
            ? Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _lime.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: _lime, size: 32),
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
                  Icon(icon, color: _muted, size: 38),
                  const SizedBox(height: 12),
                  copy,
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 14),
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
