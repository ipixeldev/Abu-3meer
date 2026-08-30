part of 'fan_league_app.dart';

class _RegistrationFlow extends StatefulWidget {
  const _RegistrationFlow({required this.onBack, required this.onComplete});

  final VoidCallback onBack;
  final VoidCallback onComplete;

  @override
  State<_RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends State<_RegistrationFlow> {
  int step = 0;
  bool barcelona = true;
  final username = TextEditingController(text: 'ahmed.legend');
  final email = TextEditingController(text: 'ahmed@fanleague.demo');
  final displayName = TextEditingController(text: 'Ahmed Karim');

  @override
  void dispose() {
    username.dispose();
    email.dispose();
    displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _PitchBackdrop()),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: Column(
                      key: ValueKey(step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: step == 0
                                  ? widget.onBack
                                  : () => setState(() => step--),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const Spacer(),
                            Text(
                              'STEP ${step + 1} / 3',
                              style: const TextStyle(
                                color: _lime,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: (step + 1) / 3,
                          minHeight: 6,
                          backgroundColor: _line,
                          color: _lime,
                        ),
                        const SizedBox(height: 28),
                        if (step == 0) ...[
                          Text('CREATE YOUR ACCOUNT', style: _display(34)),
                          const SizedBox(height: 8),
                          const Text(
                            'A simulated account for the client demo.',
                            style: TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: username,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: email,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const TextField(
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                        ] else if (step == 1) ...[
                          Text('BUILD YOUR PROFILE', style: _display(34)),
                          const SizedBox(height: 8),
                          const Text(
                            'This is how other supporters will know you.',
                            style: TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 22),
                          const Center(
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: _lime,
                              foregroundColor: _ink,
                              child: Text(
                                'AK',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: displayName,
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: 'Sweden',
                            items: [
                              DropdownMenuItem(
                                value: 'Sweden',
                                child: Text('🇸🇪  Sweden'),
                              ),
                              DropdownMenuItem(
                                value: 'Saudi Arabia',
                                child: Text('🇸🇦  Saudi Arabia'),
                              ),
                              DropdownMenuItem(
                                value: 'Spain',
                                child: Text('🇪🇸  Spain'),
                              ),
                            ],
                            onChanged: null,
                            decoration: InputDecoration(labelText: 'Country'),
                          ),
                        ] else ...[
                          Text('CHOOSE YOUR SIDE', style: _display(34)),
                          const SizedBox(height: 8),
                          const Text(
                            'Your choice powers Fan War and locks for the season.',
                            style: TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 22),
                          LayoutBuilder(
                            builder: (context, box) {
                              final cards = [
                                _TeamChoice(
                                  name: 'BARCELONA',
                                  code: 'BAR',
                                  colors: const [_blue, _red],
                                  selected: barcelona,
                                  onTap: () => setState(() => barcelona = true),
                                ),
                                _TeamChoice(
                                  name: 'REAL MADRID',
                                  code: 'RMA',
                                  colors: const [
                                    Colors.white,
                                    Color(0xFFB9B9C5),
                                  ],
                                  selected: !barcelona,
                                  onTap: () =>
                                      setState(() => barcelona = false),
                                ),
                              ];
                              return box.maxWidth > 520
                                  ? Row(
                                      children: [
                                        Expanded(child: cards[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: cards[1]),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        cards[0],
                                        const SizedBox(height: 12),
                                        cards[1],
                                      ],
                                    );
                            },
                          ),
                        ],
                        const SizedBox(height: 26),
                        FilledButton(
                          onPressed: step == 2
                              ? widget.onComplete
                              : () => setState(() => step++),
                          style: FilledButton.styleFrom(
                            backgroundColor: _lime,
                            foregroundColor: _ink,
                            padding: const EdgeInsets.all(17),
                          ),
                          child: Text(
                            step == 2 ? 'JOIN THE COMMUNITY' : 'CONTINUE',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
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
        ),
      ],
    ),
  );
}

class _TeamChoice extends StatelessWidget {
  const _TeamChoice({
    required this.name,
    required this.code,
    required this.colors,
    required this.selected,
    required this.onTap,
  });
  final String name, code;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: selected ? _lime.withValues(alpha: .1) : _surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? _lime : _line,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          _TeamCrest(label: code, colors: colors, size: 72),
          const SizedBox(height: 16),
          Text(name, style: _display(23)),
          const SizedBox(height: 6),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? _lime : _muted,
          ),
        ],
      ),
    ),
  );
}

class _MatchCenterPage extends StatefulWidget {
  const _MatchCenterPage({required this.onPredict});
  final VoidCallback onPredict;
  @override
  State<_MatchCenterPage> createState() => _MatchCenterPageState();
}

class _MatchCenterPageState extends State<_MatchCenterPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'La Liga · Matchday 3',
    title: 'Match Center',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF15243C), Color(0xFF11161E)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _blue.withValues(alpha: .45)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Text(
                    'EL CLÁSICO',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Spacer(),
                  _LiveDot(text: 'PICKS OPEN'),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: _Club(
                      label: 'Barcelona',
                      code: 'BAR',
                      colors: [_blue, _red],
                    ),
                  ),
                  Column(
                    children: [
                      Text('SAT 21:00', style: _display(27)),
                      const Text(
                        'CAMP NOU',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      const SizedBox(height: 8),
                      const _RewardChip(text: '02:14:36 TO LOCK'),
                    ],
                  ),
                  const Expanded(
                    child: _Club(
                      label: 'Real Madrid',
                      code: 'RMA',
                      colors: [Colors.white, Color(0xFFCBCBD4)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Pill(
                    icon: Icons.groups_rounded,
                    text: '14,820 FANS',
                    color: _blue,
                  ),
                  const SizedBox(width: 8),
                  const _Pill(
                    icon: Icons.stars_rounded,
                    text: '800 XP',
                    color: _gold,
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: widget.onPredict,
                    style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: _ink,
                    ),
                    child: const Text(
                      'MAKE PREDICTIONS',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('OVERVIEW')),
              ButtonSegment(value: 1, label: Text('STATS')),
              ButtonSegment(value: 2, label: Text('TIMELINE')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: tab == 0
              ? const _MatchOverview(key: ValueKey(0))
              : tab == 1
              ? const _MatchStats(key: ValueKey(1))
              : const _MatchTimeline(key: ValueKey(2)),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Other fixtures', action: 'THIS WEEK'),
        const SizedBox(height: 12),
        const _ResponsiveGrid(
          children: [
            _FixtureCard(
              home: 'Atlético',
              away: 'Sevilla',
              time: '18:30',
              codeA: 'ATM',
              codeB: 'SEV',
            ),
            _FixtureCard(
              home: 'Villarreal',
              away: 'Valencia',
              time: '20:00',
              codeA: 'VIL',
              codeB: 'VAL',
            ),
            _FixtureCard(
              home: 'Betis',
              away: 'Girona',
              time: '21:30',
              codeA: 'BET',
              codeB: 'GIR',
            ),
          ],
        ),
      ],
    ),
  );
}

class _MatchOverview extends StatelessWidget {
  const _MatchOverview({super.key});
  @override
  Widget build(BuildContext context) => const _ResponsiveGrid(
    children: [
      _SummaryCard(
        label: 'STADIUM',
        value: 'Camp Nou',
        detail: 'Barcelona, Spain',
        color: _lime,
      ),
      _SummaryCard(
        label: 'PARTICIPATING',
        value: '14.8K',
        detail: '+2,102 today',
        color: _blue,
      ),
      _SummaryCard(
        label: 'XP POOL',
        value: '8.4M',
        detail: 'Potential community XP',
        color: _gold,
      ),
    ],
  );
}

class _MatchStats extends StatelessWidget {
  const _MatchStats({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: const [
          _StatCompare(
            label: 'Win probability',
            left: 48,
            right: 36,
            leftText: '48%',
            rightText: '36%',
          ),
          _StatCompare(
            label: 'Recent form',
            left: 80,
            right: 65,
            leftText: 'W W D W W',
            rightText: 'W L W W D',
          ),
          _StatCompare(
            label: 'Fan predictions',
            left: 55,
            right: 31,
            leftText: '55%',
            rightText: '31%',
          ),
        ],
      ),
    ),
  );
}

class _MatchTimeline extends StatelessWidget {
  const _MatchTimeline({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: const [
          _TimelineItem(
            time: 'NOW',
            title: 'Predictions open',
            detail: '14,820 supporters have entered',
            color: _lime,
          ),
          _TimelineItem(
            time: '19:00',
            title: 'Predictions lock',
            detail: 'One hour before kickoff',
            color: _gold,
          ),
          _TimelineItem(
            time: '20:00',
            title: 'Match starts',
            detail: 'Live Fan War contribution begins',
            color: _blue,
          ),
          _TimelineItem(
            time: 'FT',
            title: 'Rewards calculated',
            detail: 'XP, ranks and achievements update',
            color: _muted,
          ),
        ],
      ),
    ),
  );
}

class _ChallengeLabPage extends StatefulWidget {
  const _ChallengeLabPage();
  @override
  State<_ChallengeLabPage> createState() => _ChallengeLabPageState();
}

class _ChallengeLabPageState extends State<_ChallengeLabPage> {
  int challenge = 0;
  int? answer;
  bool? correct;
  final phrase = TextEditingController();
  int xp = 8420;
  int loyalty = 2480;
  @override
  void dispose() {
    phrase.dispose();
    super.dispose();
  }

  void submit() {
    final valid = challenge == 0
        ? phrase.text.trim().toLowerCase() == 'visca barca'
        : answer == 1;
    setState(() {
      correct = valid;
      if (valid) {
        xp += 50;
        loyalty += 100;
      }
    });
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Interactive challenge detail',
    title: challenge == 0 ? 'Find the secret phrase' : 'Football knowledge',
    child: LayoutBuilder(
      builder: (context, box) {
        final selector = Column(
          children: [
            _LabChoice(
              title: 'Secret Phrase',
              detail: 'Latest reaction video',
              icon: Icons.play_circle_fill_rounded,
              active: challenge == 0,
              onTap: () => setState(() {
                challenge = 0;
                correct = null;
              }),
            ),
            const SizedBox(height: 10),
            _LabChoice(
              title: 'Football Knowledge',
              detail: 'One multiple-choice question',
              icon: Icons.psychology_alt_rounded,
              active: challenge == 1,
              onTap: () => setState(() {
                challenge = 1;
                correct = null;
              }),
            ),
          ],
        );
        final task = Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const _RewardChip(text: '+50 XP'),
                    const SizedBox(width: 8),
                    const _RewardChip(text: '+100 LOYALTY'),
                    const Spacer(),
                    Text(
                      '$xp XP · $loyalty LP',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (challenge == 0) ...[
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      image: const DecorationImage(
                        image: AssetImage('assets/images/latest_abu3meer.jpg'),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Color(0x8831151C),
                          BlendMode.multiply,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: InkWell(
                            onTap: () => launchUrl(
                              Uri.parse(_latestVideoUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: SizedBox(
                              width: 170,
                              height: 56,
                              child: Lottie.asset(
                                'assets/animations/youtube.json',
                                repeat: true,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          bottom: 16,
                          child: Text(
                            'LATEST ABU 3MEER VIDEO',
                            style: _display(18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'What secret phrase did the creator say after the second goal?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phrase,
                    decoration: const InputDecoration(
                      hintText: 'Enter the secret phrase…',
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Who did the creator name as the key player today?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(
                    4,
                    (i) => ListTile(
                      onTap: () => setState(() => answer = i),
                      leading: Icon(
                        answer == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: answer == i ? _lime : _muted,
                      ),
                      title: Text(
                        [
                          'Pedri',
                          'Lamine Yamal',
                          'Kylian Mbappé',
                          'Vinícius Jr.',
                        ][i],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (correct != null)
                  if (correct!)
                    SizedBox(
                      height: 140,
                      child: IgnorePointer(
                        child: Lottie.asset(
                          'assets/animations/fireworks.json',
                          repeat: false,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                if (correct != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (correct! ? _lime : _red).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: correct! ? _lime : _red),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          correct!
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: correct! ? _lime : _red,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            correct!
                                ? 'Correct! Rewards added to your demo balance.'
                                : 'Not quite. Try again—the demo accepts “Visca Barca”.',
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: _ink,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text(
                    'SUBMIT ANSWER',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        );
        return box.maxWidth > 760
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 270, child: selector),
                  const SizedBox(width: 18),
                  Expanded(child: task),
                ],
              )
            : Column(children: [selector, const SizedBox(height: 18), task]);
      },
    ),
  );
}

class _ProfileStudioPage extends StatefulWidget {
  const _ProfileStudioPage();
  @override
  State<_ProfileStudioPage> createState() => _ProfileStudioPageState();
}

class _ProfileStudioPageState extends State<_ProfileStudioPage> {
  bool edit = false;
  final name = TextEditingController(text: 'Ahmed Karim');
  final handle = TextEditingController(text: 'ahmed.legend');

  @override
  void dispose() {
    name.dispose();
    handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: edit ? 'Private editing view' : 'Public fan preview',
    title: edit ? 'Edit profile' : 'Ahmed Karim',
    child: LayoutBuilder(
      builder: (context, box) {
        final hero = Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 48,
                backgroundColor: _lime,
                foregroundColor: _ink,
                child: Text(
                  'AK',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 14),
              if (edit) ...[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: handle,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              ] else ...[
                Text(name.text, style: _display(29)),
                Text(
                  '@${handle.text} · 🇸🇪 Sweden',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 8),
                const _Pill(
                  icon: Icons.verified_rounded,
                  text: 'ULTRA MEMBER',
                  color: _gold,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => setState(() => edit = !edit),
                  icon: Icon(edit ? Icons.save_rounded : Icons.edit_rounded),
                  label: Text(edit ? 'SAVE PROFILE' : 'EDIT PROFILE'),
                ),
              ),
            ],
          ),
        );
        final public = Column(
          children: [
            const _ResponsiveGrid(
              children: [
                _SummaryCard(
                  label: 'SEASON RANK',
                  value: '#342',
                  detail: '↑18 this week',
                  color: _lime,
                ),
                _SummaryCard(
                  label: 'PREDICTION RATE',
                  value: '68%',
                  detail: '34 correct picks',
                  color: _gold,
                ),
                _SummaryCard(
                  label: 'MATCH STREAK',
                  value: '12',
                  detail: 'Best: 18',
                  color: _red,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _SectionTitle(
                      title: 'Public achievements',
                      action: '4 PINNED',
                    ),
                    SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('🎯', style: TextStyle(fontSize: 34)),
                        Text('🔥', style: TextStyle(fontSize: 34)),
                        Text('👑', style: TextStyle(fontSize: 34)),
                        Text('⚔️', style: TextStyle(fontSize: 34)),
                      ],
                    ),
                    SizedBox(height: 20),
                    Divider(color: _line),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.youtube_searched_for_rounded,
                        color: _red,
                      ),
                      title: Text('YouTube Membership'),
                      subtitle: Text('Verified Ultra Member · 2× Loyalty only'),
                      trailing: Icon(Icons.verified_rounded, color: _lime),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        return box.maxWidth > 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 350, child: hero),
                  const SizedBox(width: 18),
                  Expanded(child: public),
                ],
              )
            : Column(children: [hero, const SizedBox(height: 18), public]);
      },
    ),
  );
}

class _ObsOverlayPage extends StatefulWidget {
  const _ObsOverlayPage({required this.onExit});
  final VoidCallback onExit;
  @override
  State<_ObsOverlayPage> createState() => _ObsOverlayPageState();
}

class _ObsOverlayPageState extends State<_ObsOverlayPage> {
  Timer? timer;
  bool swapped = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => swapped = !swapped);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaders = swapped
        ? const [
            ('1', 'Mohammed', '14,950', '↑'),
            ('2', 'NoraGOAT', '14,940', '↓'),
            ('3', 'Ahmed', '14,810', '↑'),
            ('4', 'CuleKing', '14,720', '—'),
          ]
        : const [
            ('1', 'NoraGOAT', '14,940', '↑'),
            ('2', 'Mohammed', '14,910', '↓'),
            ('3', 'CuleKing', '14,720', '—'),
            ('4', 'Ahmed', '14,680', '↑'),
          ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF2080B10), Color(0xEB111B16)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Row(
                  children: [
                    const _LogoMark(size: 42),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LIVE COMMUNITY', style: _display(28)),
                        const Text(
                          'EL CLÁSICO SPECIAL',
                          style: TextStyle(
                            color: _lime,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const _LiveDot(text: 'LIVE'),
                    IconButton(
                      onPressed: widget.onExit,
                      tooltip: 'Exit overlay',
                      icon: const Icon(Icons.close_rounded, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final board = _OverlayBoard(
                        leaders: leaders,
                        swapped: swapped,
                      );
                      const war = _OverlayFanWar();
                      return box.maxWidth > 850
                          ? Row(
                              children: [
                                Expanded(flex: 5, child: board),
                                const SizedBox(width: 18),
                                const Expanded(flex: 4, child: war),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(child: board),
                                const SizedBox(height: 14),
                                war,
                              ],
                            );
                    },
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

class _OverlayBoard extends StatelessWidget {
  const _OverlayBoard({required this.leaders, required this.swapped});
  final List<(String, String, String, String)> leaders;
  final bool swapped;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Top supporters', action: 'LIVE RANKING'),
        const SizedBox(height: 14),
        ...leaders.map(
          (e) => AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: e.$2 == 'Ahmed' ? _lime.withValues(alpha: .1) : _surface2,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: e.$2 == 'Ahmed' ? _lime : _line),
            ),
            child: Row(
              children: [
                Text(
                  '#${e.$1}',
                  style: _display(
                    25,
                    color: e.$1 == '1' ? _gold : Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                CircleAvatar(
                  backgroundColor: e.$2 == 'Ahmed' ? _lime : _blue,
                  foregroundColor: _ink,
                  child: Text(
                    e.$2[0],
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.$2,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${e.$3} XP',
                  style: const TextStyle(
                    color: _lime,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  e.$4,
                  style: TextStyle(
                    color: e.$4 == '↑'
                        ? _lime
                        : e.$4 == '↓'
                        ? _red
                        : _muted,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _OverlayFanWar extends StatelessWidget {
  const _OverlayFanWar();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _line),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('FAN WAR', style: _display(25, color: _muted, spacing: 2)),
        const SizedBox(height: 20),
        Row(
          children: [
            const _TeamCrest(label: 'BAR', colors: [_blue, _red], size: 62),
            const Spacer(),
            Text('51.8', style: _display(48, color: _blue)),
            Text(' — ', style: _display(24, color: _muted)),
            Text('48.2', style: _display(48)),
            const Spacer(),
            const _TeamCrest(
              label: 'RMA',
              colors: [Colors.white, Color(0xFFCBCBD4)],
              size: 62,
            ),
          ],
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Expanded(flex: 518, child: Container(height: 14, color: _blue)),
              Expanded(
                flex: 482,
                child: Container(height: 14, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'BARCELONA LEADS BY 411,610 XP',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _lime,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 28),
        Text('+28,420 XP', style: _display(35, color: _gold)),
        const Text(
          'COMMUNITY GAIN · LAST 5 MIN',
          style: TextStyle(color: _muted, fontSize: 10),
        ),
      ],
    ),
  );
}

class _StatCompare extends StatelessWidget {
  const _StatCompare({
    required this.label,
    required this.left,
    required this.right,
    required this.leftText,
    required this.rightText,
  });
  final String label, leftText, rightText;
  final int left, right;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                leftText,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                rightText,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: left,
              child: Container(height: 6, color: _blue),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: right,
              child: Container(height: 6, color: Colors.white),
            ),
            Expanded(
              flex: 100 - left - right,
              child: Container(height: 6, color: _line),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.time,
    required this.title,
    required this.detail,
    required this.color,
  });
  final String time, title, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            time,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
        CircleAvatar(radius: 7, backgroundColor: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({
    required this.home,
    required this.away,
    required this.time,
    required this.codeA,
    required this.codeB,
  });
  final String home, away, time, codeA, codeB;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          _TeamCrest(label: codeA, colors: const [_blue, _red]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              home,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Column(
            children: [
              Text(
                time,
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text('SAT', style: TextStyle(color: _muted, fontSize: 9)),
            ],
          ),
          Expanded(
            child: Text(
              away,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          _TeamCrest(label: codeB, colors: const [Colors.white, _muted]),
        ],
      ),
    ),
  );
}

class _LabChoice extends StatelessWidget {
  const _LabChoice({
    required this.title,
    required this.detail,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String title, detail;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: active ? _lime.withValues(alpha: .1) : _surface,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(icon, color: active ? _lime : _muted),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (active) const Icon(Icons.chevron_right_rounded, color: _lime),
          ],
        ),
      ),
    ),
  );
}

class _AdminEditorDialog extends StatefulWidget {
  const _AdminEditorDialog({required this.section});
  final String section;
  @override
  State<_AdminEditorDialog> createState() => _AdminEditorDialogState();
}

class _AdminEditorDialogState extends State<_AdminEditorDialog> {
  bool active = true;
  double reward = 250;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Create ${widget.section}', style: _display(26)),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: '${widget.section} name',
                prefixIcon: const Icon(Icons.edit_rounded),
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description / internal notes',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Start date',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'End date',
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Reward value',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: Slider(
                    value: reward,
                    min: 0,
                    max: 1000,
                    divisions: 20,
                    label: '${reward.round()} XP',
                    onChanged: (v) => setState(() => reward = v),
                  ),
                ),
                Text(
                  '${reward.round()} XP',
                  style: const TextStyle(
                    color: _lime,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            _PremiumToggleTile(
              title: const Text('Active immediately'),
              subtitle: const Text('All changes remain local to this demo'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ],
        ),
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
  );
}

class _PublicFanDialog extends StatelessWidget {
  const _PublicFanDialog({required this.fan});
  final (String, String, String, String) fan;

  @override
  Widget build(BuildContext context) => AlertDialog(
    contentPadding: EdgeInsets.zero,
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF192612), _surface]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _TeamCrest(
                  label: fan.$3,
                  colors: fan.$3 == 'BAR'
                      ? const [_blue, _red]
                      : const [Colors.white, Color(0xFFCBCBD4)],
                  size: 76,
                ),
                const SizedBox(height: 12),
                Text(fan.$1, style: _display(29)),
                Text(
                  '${fan.$2} · ${fan.$3} SUPPORTER',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Metric(value: fan.$4, label: 'XP', color: _lime),
                    ),
                    const Expanded(
                      child: _Metric(
                        value: '71%',
                        label: 'ACCURACY',
                        color: _gold,
                      ),
                    ),
                    const Expanded(
                      child: _Metric(value: '16', label: 'STREAK', color: _red),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: _line),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('🎯', style: TextStyle(fontSize: 30)),
                    Text('🔥', style: TextStyle(fontSize: 30)),
                    Text('👑', style: TextStyle(fontSize: 30)),
                    Text('⚔️', style: TextStyle(fontSize: 30)),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CLOSE PROFILE'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
