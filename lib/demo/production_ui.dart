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
              message:
                  'This account is suspended. Contact ${AbuBrand.supportEmail}.',
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
      setState(() => error = 'Enter your email first.');
      return;
    }
    await run(() => widget.repository.sendPasswordReset(email.text));
    if (mounted && error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
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
              createAccount ? 'CREATE ACCOUNT' : 'WELCOME BACK',
              style: _display(28),
            ),
            const SizedBox(height: 6),
            Text(
              createAccount
                  ? 'Join the Abu 3meer community.'
                  : 'Sign in to predict, answer and find.',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
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
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Show password' : 'Hide password',
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
                      createAccount ? 'CREATE ACCOUNT' : 'SIGN IN',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
            if (!createAccount)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : resetPassword,
                  child: const Text('FORGOT PASSWORD?'),
                ),
              ),
            const Row(
              children: [
                Expanded(child: Divider(color: _line)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: TextStyle(color: _muted)),
                ),
                Expanded(child: Divider(color: _line)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(widget.repository.signInWithGoogle),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('CONTINUE WITH GOOGLE'),
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
                    ? 'I ALREADY HAVE AN ACCOUNT'
                    : 'CREATE AN ABU 3MEER ACCOUNT',
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
        const Text(
          'Your prediction. Your knowledge. Your place on the leaderboard.',
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
    title: 'VERIFY YOUR EMAIL',
    body: 'We sent a verification link to ${widget.user.email}.',
    message: message,
    actions: [
      FilledButton(
        onPressed: busy
            ? null
            : () => act(
                widget.repository.refreshUser,
                'Account status refreshed.',
              ),
        child: const Text('I HAVE VERIFIED'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => act(
                widget.repository.resendVerification,
                'Verification email sent again.',
              ),
        child: const Text('RESEND EMAIL'),
      ),
      TextButton(
        onPressed: busy ? null : widget.repository.signOut,
        child: const Text('USE ANOTHER ACCOUNT'),
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
    title: 'BUILD YOUR PROFILE',
    body: 'Choose the identity you will use on Abu 3meer leaderboards.',
    message: error,
    content: Column(
      children: [
        TextField(
          controller: username,
          decoration: const InputDecoration(
            labelText: 'Unique username',
            prefixText: '@',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: displayName,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: country,
          decoration: const InputDecoration(labelText: 'Country'),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Barcelona', label: Text('Barcelona')),
            ButtonSegment(value: 'Real Madrid', label: Text('Real Madrid')),
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
        child: Text(busy ? 'SAVING…' : 'ENTER ABU 3MEER'),
      ),
      TextButton(
        onPressed: busy ? null : widget.repository.signOut,
        child: const Text('SIGN OUT'),
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
    title: 'WE COULD NOT LOAD YOUR ACCOUNT',
    body: message,
    actions: [
      FilledButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
      TextButton(onPressed: onSignOut, child: const Text('SIGN OUT')),
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

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _ProductionHome(repository: widget.repository, profile: widget.profile),
      _ProductionMatches(repository: widget.repository),
      _ProductionLeaderboard(
        repository: widget.repository,
        profile: widget.profile,
      ),
      _ProductionPoints(repository: widget.repository, profile: widget.profile),
      _ProductionProfile(
        repository: widget.repository,
        profile: widget.profile,
      ),
      _ProductionSettings(profile: widget.profile),
      if (widget.profile.isAdmin)
        _ProductionAdmin(repository: widget.repository),
    ];
    if (index >= pages.length) index = 0;
    final items = <(IconData, String)>[
      (Icons.grid_view_rounded, abuText(context, 'Home', 'الرئيسية')),
      (Icons.sports_soccer_rounded, abuText(context, 'Predict', 'توقع')),
      (Icons.leaderboard_rounded, abuText(context, 'Leaders', 'الترتيب')),
      (Icons.receipt_long_rounded, abuText(context, 'Points', 'النقاط')),
      (Icons.person_rounded, abuText(context, 'Profile', 'حسابي')),
    ];
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const _LogoMark(size: 30),
            const SizedBox(width: 10),
            Text(
              abuText(context, 'ABU 3MEER', 'أبو عمير'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ],
        ),
        actions: [
          _Pill(
            icon: Icons.stars_rounded,
            text: '${widget.profile.totalPoints}',
            color: _gold,
            compact: true,
          ),
          IconButton(
            tooltip: abuText(context, 'Settings', 'الإعدادات'),
            onPressed: () => setState(() => index = 5),
            icon: const Icon(Icons.settings_rounded),
          ),
          if (widget.profile.isAdmin)
            IconButton(
              tooltip: 'Admin Dashboard',
              onPressed: () => setState(() => index = 6),
              icon: const Icon(Icons.admin_panel_settings_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: desktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: index < 5 ? index : 0,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: items
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.$1),
                          label: Text(item.$2),
                        ),
                      )
                      .toList(),
                ),
                const VerticalDivider(width: 1, color: _line),
                Expanded(child: pages[index]),
              ],
            )
          : pages[index],
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              height: 66,
              selectedIndex: index < 5 ? index : 0,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: items
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

class _ProductionHome extends StatelessWidget {
  const _ProductionHome({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: profile.isYouTubeMember
        ? 'YouTube Member · 2× points'
        : 'Abu 3meer Community',
    title: 'Welcome, ${profile.displayName}',
    child: Column(
      children: [
        _ProductionPointsHero(profile: profile),
        const SizedBox(height: 16),
        StreamBuilder<List<MatchEvent>>(
          stream: repository.watchMatches(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 190);
            }
            if (snapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: 'Matches unavailable',
                body: productionErrorMessage(snapshot.error!),
              );
            }
            final matches = snapshot.data ?? const [];
            if (matches.isEmpty) {
              return const _ProductionEmpty(
                icon: Icons.event_busy_rounded,
                title: 'No prediction is open',
                body: 'The next Abu 3meer match event will appear here.',
              );
            }
            return _ProductionMatchCard(
              event: matches.first,
              repository: repository,
            );
          },
        ),
        const SizedBox(height: 16),
        _ProductionLatestVideoCard(repository: repository),
      ],
    ),
  );
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
                child: video.thumbnailUrl.startsWith('assets/')
                    ? Image.asset(video.thumbnailUrl, fit: BoxFit.cover)
                    : Image.network(
                        video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Image.asset(
                          'assets/images/latest_abu3meer.jpg',
                          fit: BoxFit.cover,
                        ),
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
            const Text(
              'CURRENT POINTS',
              style: TextStyle(
                color: _lime,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
            const Spacer(),
            if (profile.isYouTubeMember) const _LiveDot(text: '2× MEMBER'),
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
                label: 'THIS MONTH',
                color: _lime,
              ),
            ),
            Expanded(
              child: _Metric(
                value: '${profile.seasonPoints}',
                label: 'THIS SEASON',
                color: _gold,
              ),
            ),
            Expanded(
              child: _Metric(
                value: profile.supportedTeam == 'Barcelona' ? 'FCB' : 'RMA',
                label: 'YOUR TEAM',
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
    kicker: '100 base points · exact score',
    title: 'Predictions',
    child: StreamBuilder<List<MatchEvent>>(
      stream: repository.watchMatches(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 260);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load matches',
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final events = snapshot.data ?? const [];
        if (events.isEmpty) {
          return const _ProductionEmpty(
            icon: Icons.sports_soccer_rounded,
            title: 'No matches yet',
            body: 'An administrator has not published a match event.',
          );
        }
        return Column(
          children: events
              .map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ProductionMatchCard(
                    event: event,
                    repository: repository,
                  ),
                ),
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
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exact score prediction'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreInput(
                label: event.homeTeam,
                value: home,
                onChanged: (value) => setDialogState(() => home = value),
              ),
              Text('–', style: _display(34)),
              _ScoreInput(
                label: event.awayTeam,
                value: away,
                onChanged: (value) => setDialogState(() => away = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (home, away)),
              child: const Text('SAVE PREDICTION'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await repository.submitPrediction(
        matchId: event.id,
        homeScore: result.$1,
        awayScore: result.$2,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prediction saved securely.')),
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
                _LiveDot(text: event.status.toUpperCase()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 48,
                  child: Stack(
                    children: [
                      _ProductionTeamBadge(
                        team: event.homeTeam,
                        source: event.homeLogoUrl,
                      ),
                      Positioned(
                        left: 27,
                        child: _ProductionTeamBadge(
                          team: event.awayTeam,
                          source: event.awayLogoUrl,
                        ),
                      ),
                    ],
                  ),
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
                    ? 'PREDICT EXACT SCORE'
                    : event.status == 'completed'
                    ? 'RESULT PUBLISHED'
                    : event.id.startsWith('external_')
                    ? 'NEXT MATCH · EVENT OPENS SOON'
                    : 'PREDICTIONS CLOSED',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductionTeamBadge extends StatelessWidget {
  const _ProductionTeamBadge({required this.team, required this.source});
  final String team;
  final String source;

  @override
  Widget build(BuildContext context) {
    final fallback = team.toLowerCase().contains('barcelona')
        ? 'assets/images/fcb.png'
        : team.toLowerCase().contains('real madrid')
        ? 'assets/images/rma.png'
        : '';
    Widget image;
    if (source.startsWith('http')) {
      image = Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback.isEmpty
            ? const Icon(Icons.shield_rounded)
            : Image.asset(fallback, fit: BoxFit.contain),
      );
    } else if (source.startsWith('assets/')) {
      image = Image.asset(source, fit: BoxFit.contain);
    } else if (fallback.isNotEmpty) {
      image = Image.asset(fallback, fit: BoxFit.contain);
    } else {
      image = const Icon(Icons.shield_rounded);
    }
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
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
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Top 5 qualify for prizes',
    title: 'Leaderboard',
    child: Column(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('MONTHLY')),
            ButtonSegment(value: false, label: Text('SEASON')),
          ],
          selected: {monthly},
          onSelectionChanged: (value) => setState(() => monthly = value.first),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<LeaderboardEntry>>(
          stream: widget.repository.watchLeaderboard(monthly: monthly),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 300);
            }
            if (snapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: 'Leaderboard unavailable',
                body: productionErrorMessage(snapshot.error!),
              );
            }
            final entries = snapshot.data ?? const [];
            if (entries.isEmpty) {
              return const _ProductionEmpty(
                icon: Icons.leaderboard_rounded,
                title: 'The race starts here',
                body:
                    'Rankings appear when users earn their first real points.',
              );
            }
            return Card(
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
                      '${monthly ? entry.monthlyPoints : entry.seasonPoints}',
                      style: _display(
                        20,
                        color: index < 5 ? _gold : Colors.white,
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _ProductionPoints extends StatelessWidget {
  const _ProductionPoints({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: '${profile.totalPoints} verified points',
    title: 'Point history',
    child: StreamBuilder<List<PointLedgerEntry>>(
      stream: repository.watchPointHistory(profile.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 260);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: 'History unavailable',
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const _ProductionEmpty(
            icon: Icons.receipt_long_rounded,
            title: 'No point transactions yet',
            body:
                'Every point will appear here with its source and multiplier.',
          );
        }
        return Card(
          child: Column(
            children: entries
                .map(
                  (entry) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _lime.withValues(alpha: .12),
                      child: const Icon(Icons.add_rounded, color: _lime),
                    ),
                    title: Text(entry.reason),
                    subtitle: Text(
                      '${entry.basePoints} × ${entry.multiplier.toStringAsFixed(entry.multiplier % 1 == 0 ? 0 : 1)} · ${_productionDate(entry.createdAt)}',
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
      },
    ),
  );
}

class _ProductionProfile extends StatelessWidget {
  const _ProductionProfile({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: profile.role.toUpperCase(),
    title: '@${profile.username}',
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: _lime,
              foregroundImage: profile.avatarUrl.isEmpty
                  ? null
                  : NetworkImage(profile.avatarUrl),
              child: profile.avatarUrl.isEmpty
                  ? Text(
                      profile.displayName.isEmpty
                          ? '?'
                          : profile.displayName[0].toUpperCase(),
                      style: _display(30, color: _ink),
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Text(profile.displayName, style: _display(25)),
            Text(
              '${profile.country} · ${profile.supportedTeam}',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 20),
            if (profile.isYouTubeMember)
              const _LiveDot(text: 'YOUTUBE MEMBER · 2×'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: repository.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('SIGN OUT'),
              ),
            ),
          ],
        ),
      ),
    ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Column(
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
                        'The layout changes direction immediately.',
                        'يتغير اتجاه واجهة التطبيق مباشرة.',
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AbuLanguage>(
                        segments: const [
                          ButtonSegment(
                            value: AbuLanguage.english,
                            label: Text('English'),
                          ),
                          ButtonSegment(
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
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          color: _red,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            abuText(
                              context,
                              'YOUTUBE MEMBERSHIP',
                              'عضوية يوتيوب',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        _LiveDot(
                          text: profile.isYouTubeMember
                              ? abuText(context, 'VERIFIED · 2×', 'موثق · 2×')
                              : abuText(context, 'NOT VERIFIED', 'غير موثق'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      abuText(
                        context,
                        'Member points will only be activated after secure verification with the creator\'s YouTube account. They are never granted from a user-entered claim.',
                        'يتم تفعيل نقاط الأعضاء فقط بعد التحقق الآمن باستخدام حساب منشئ القناة، ولا تُمنح بناءً على اختيار يدوي.',
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
            ),
            const SizedBox(height: 14),
            Card(
              color: _gold.withValues(alpha: .09),
              child: SwitchListTile.adaptive(
                value: mockData.enabled,
                onChanged: mockData.setEnabled,
                secondary: const Icon(Icons.science_rounded, color: _gold),
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
                    'Testing only. Replaces the live match and video with predictable sample content. This isolated option can be removed before launch.',
                    'للاختبار فقط. يستبدل المباراة والفيديو المباشرين ببيانات ثابتة، ويمكن حذف هذا الخيار قبل الإطلاق.',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductionAdmin extends StatelessWidget {
  const _ProductionAdmin({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Role-protected operations',
    title: 'Admin Dashboard',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => _showCreateMatch(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('CREATE MATCH EVENT'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showPointRules(context),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('POINT RULES'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        StreamBuilder<List<MatchEvent>>(
          stream: repository.watchManagedMatches(),
          builder: (context, snapshot) {
            final matches = snapshot.data ?? const [];
            if (matches.isEmpty) {
              return const _ProductionEmpty(
                icon: Icons.event_note_rounded,
                title: 'No events published',
                body: 'Create the first real prediction event.',
              );
            }
            return Card(
              child: Column(
                children: matches
                    .map(
                      (match) => ListTile(
                        title: Text('${match.homeTeam} vs ${match.awayTeam}'),
                        subtitle: Text(
                          '${match.competition} · ${match.status}',
                        ),
                        trailing: match.status == 'completed'
                            ? null
                            : IconButton(
                                tooltip: 'Publish result',
                                onPressed: () => _showResult(context, match),
                                icon: const Icon(Icons.flag_rounded),
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
    var kickoff = DateTime.now().add(const Duration(days: 2));
    var opens = DateTime.now();
    var closes = kickoff.subtract(const Duration(minutes: 5));
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create match event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: home,
                  decoration: const InputDecoration(labelText: 'Home team'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: away,
                  decoration: const InputDecoration(labelText: 'Away team'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: competition,
                  decoration: const InputDecoration(labelText: 'Competition'),
                ),
                const SizedBox(height: 12),
                _AdminDateTile(
                  label: 'Predictions open',
                  value: opens,
                  onChanged: (value) => setDialogState(() => opens = value),
                ),
                _AdminDateTile(
                  label: 'Predictions close',
                  value: closes,
                  onChanged: (value) => setDialogState(() => closes = value),
                ),
                _AdminDateTile(
                  label: 'Kickoff',
                  value: kickoff,
                  onChanged: (value) => setDialogState(() => kickoff = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CREATE'),
            ),
          ],
        ),
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
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Match event published.')));
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
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish official result'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: home,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: match.homeTeam),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: away,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: match.awayTeam),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('PROCESS REWARDS'),
          ),
        ],
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      await repository.publishMatchResult(
        matchId: match.id,
        homeScore: int.parse(home.text),
        awayScore: int.parse(away.text),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result published and rewards processed.'),
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
    final question = TextEditingController(text: '40');
    final card = TextEditingController(text: '20');
    final multiplier = TextEditingController(text: '2');
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Point rules'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: prediction,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Exact prediction',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: question,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Video question'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: card,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Player Card'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: multiplier,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Member multiplier',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (submit != true || !context.mounted) return;
    try {
      await repository.updatePointRules(
        exactPrediction: int.parse(prediction.text),
        videoQuestion: int.parse(question.text),
        playerCard: int.parse(card.text),
        memberMultiplier: double.parse(multiplier.text),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Point rules updated.')));
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
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: const Center(child: _ProductionLottieLoader()),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 38),
          const SizedBox(height: 12),
          Text(title, style: _display(22)),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
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
