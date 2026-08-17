part of 'fan_league_app.dart';

enum _TriviaPhase { lobby, playing, finished }

class _TriviaQuestion {
  const _TriviaQuestion({
    required this.category,
    required this.prompt,
    required this.answers,
    required this.correctIndex,
    required this.fact,
  });

  final String category;
  final String prompt;
  final List<String> answers;
  final int correctIndex;
  final String fact;
}

const _triviaQuestions = <_TriviaQuestion>[
  _TriviaQuestion(
    category: 'EL CLÁSICO',
    prompt: 'Which stadium is Real Madrid’s home ground?',
    answers: ['Camp Nou', 'Santiago Bernabéu', 'Mestalla', 'San Mamés'],
    correctIndex: 1,
    fact: 'The Santiago Bernabéu opened in 1947 and sits in central Madrid.',
  ),
  _TriviaQuestion(
    category: 'WORLD CUP',
    prompt: 'Which nation won the 2022 FIFA World Cup?',
    answers: ['France', 'Brazil', 'Argentina', 'Croatia'],
    correctIndex: 2,
    fact: 'Argentina defeated France on penalties after a 3–3 final.',
  ),
  _TriviaQuestion(
    category: 'CHAMPIONS LEAGUE',
    prompt: 'Which club is known as “The Citizens”?',
    answers: ['Manchester City', 'Inter Milan', 'Arsenal', 'PSG'],
    correctIndex: 0,
    fact: 'Manchester City’s long-standing nickname is The Citizens.',
  ),
  _TriviaQuestion(
    category: 'PREMIER LEAGUE',
    prompt: 'How many players does one team start with on the pitch?',
    answers: ['9', '10', '11', '12'],
    correctIndex: 2,
    fact: 'A match starts with 11 players per team, including one goalkeeper.',
  ),
  _TriviaQuestion(
    category: 'LEGENDS',
    prompt: 'Which player is nicknamed “The Egyptian King”?',
    answers: [
      'Riyad Mahrez',
      'Mohamed Salah',
      'Omar Marmoush',
      'Achraf Hakimi',
    ],
    correctIndex: 1,
    fact: 'Liverpool supporters popularised the nickname for Mohamed Salah.',
  ),
];

class _TriviaArenaPage extends StatefulWidget {
  const _TriviaArenaPage();

  @override
  State<_TriviaArenaPage> createState() => _TriviaArenaPageState();
}

class _TriviaArenaPageState extends State<_TriviaArenaPage> {
  _TriviaPhase _phase = _TriviaPhase.lobby;
  int _questionIndex = 0;
  int _activeTeam = 0;
  int _seconds = 20;
  int? _selected;
  List<int> _scores = [0, 0];
  List<bool> _doubleAvailable = [true, true];
  bool _doubleActive = false;
  Timer? _timer;

  _TriviaQuestion get _question => _triviaQuestions[_questionIndex];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startGame() {
    _timer?.cancel();
    setState(() {
      _phase = _TriviaPhase.playing;
      _questionIndex = 0;
      _activeTeam = 0;
      _seconds = 20;
      _selected = null;
      _scores = [0, 0];
      _doubleAvailable = [true, true];
      _doubleActive = false;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _phase != _TriviaPhase.playing || _selected != null) {
        timer.cancel();
        return;
      }
      if (_seconds <= 1) {
        timer.cancel();
        setState(() {
          _seconds = 0;
          _selected = -1;
        });
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _answer(int index) {
    if (_selected != null) return;
    _timer?.cancel();
    final correct = index == _question.correctIndex;
    setState(() {
      _selected = index;
      if (correct) {
        _scores[_activeTeam] += _doubleActive ? 200 : 100;
      }
    });
  }

  void _useDouble() {
    if (!_doubleAvailable[_activeTeam] || _selected != null) return;
    setState(() {
      _doubleAvailable[_activeTeam] = false;
      _doubleActive = true;
    });
  }

  void _next() {
    if (_questionIndex == _triviaQuestions.length - 1) {
      _timer?.cancel();
      setState(() => _phase = _TriviaPhase.finished);
      return;
    }
    setState(() {
      _questionIndex++;
      _activeTeam = 1 - _activeTeam;
      _seconds = 20;
      _selected = null;
      _doubleActive = false;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      kicker: 'Live fan game · 2 teams',
      title: 'Trivia Arena',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: switch (_phase) {
          _TriviaPhase.lobby => _buildLobby(),
          _TriviaPhase.playing => _buildGame(),
          _TriviaPhase.finished => _buildResult(),
        },
      ),
    );
  }

  Widget _buildLobby() => LayoutBuilder(
    key: const ValueKey('trivia-lobby'),
    builder: (context, constraints) {
      final wide = constraints.maxWidth > 760;
      final intro = Container(
        constraints: const BoxConstraints(minHeight: 390),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2648D9), Color(0xFF101A54), _surface],
          ),
          image: const DecorationImage(
            image: AssetImage('assets/images/wembley_stadium_night.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Color(0xAA101A54),
              BlendMode.multiply,
            ),
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _blue.withValues(alpha: .55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _ArenaBadge(
              icon: Icons.stadium_rounded,
              text: 'MATCHDAY MODE',
            ),
            const SizedBox(height: 54),
            Text('WHO KNOWS\nFOOTBALL BEST?', style: _display(44, height: .92)),
            const SizedBox(height: 14),
            const Text(
              'Pass the screen between two fan teams. Five questions, twenty seconds each, one winner.',
              style: TextStyle(color: Color(0xFFC4CEE8), height: 1.55),
            ),
          ],
        ),
      );
      final setup = Card(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('GAME SETUP', style: _display(24)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundImage: AssetImage(
                        'assets/images/lamine_yamal_2025.jpg',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FEATURED PACK',
                            style: TextStyle(
                              color: _lime,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'European football stars',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: _muted),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _TeamSetupTile(
                color: _blue,
                name: 'Team Ultras',
                initials: 'TU',
              ),
              const SizedBox(height: 10),
              const _TeamSetupTile(
                color: _red,
                name: 'Team Legends',
                initials: 'TL',
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(
                    child: _GameRule(
                      icon: Icons.quiz_rounded,
                      value: '5',
                      label: 'questions',
                    ),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: _GameRule(
                      icon: Icons.timer_rounded,
                      value: '20s',
                      label: 'per round',
                    ),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: _GameRule(
                      icon: Icons.bolt_rounded,
                      value: '2×',
                      label: 'power-up',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('start-trivia'),
                onPressed: _startGame,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('START MATCH'),
                style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: _ink,
                  padding: const EdgeInsets.all(18),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: intro),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: setup),
              ],
            )
          : Column(children: [intro, const SizedBox(height: 16), setup]);
    },
  );

  Widget _buildGame() {
    final answered = _selected != null;
    final correct = _selected == _question.correctIndex;
    return Column(
      key: ValueKey('trivia-question-$_questionIndex'),
      children: [
        Row(
          children: [
            Expanded(
              child: _ScoreCard(
                name: 'TEAM ULTRAS',
                score: _scores[0],
                active: _activeTeam == 0,
                color: _blue,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Text(
                    '${_questionIndex + 1}/${_triviaQuestions.length}',
                    style: _display(20),
                  ),
                  const Text(
                    'ROUND',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ScoreCard(
                name: 'TEAM LEGENDS',
                score: _scores[1],
                active: _activeTeam == 1,
                color: _red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              children: [
                Row(
                  children: [
                    _ArenaBadge(
                      icon: Icons.sports_soccer_rounded,
                      text: _question.category,
                    ),
                    const Spacer(),
                    _TimerDial(seconds: _seconds),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  _question.prompt,
                  textAlign: TextAlign.center,
                  style: _display(30, height: 1.08),
                ),
                const SizedBox(height: 26),
                LayoutBuilder(
                  builder: (context, box) {
                    final tiles = List.generate(
                      _question.answers.length,
                      (index) => _AnswerTile(
                        label: String.fromCharCode(65 + index),
                        answer: _question.answers[index],
                        state: !answered
                            ? 0
                            : index == _question.correctIndex
                            ? 1
                            : index == _selected
                            ? -1
                            : 0,
                        onTap: () => _answer(index),
                      ),
                    );
                    if (box.maxWidth < 680) {
                      return Column(
                        children: [
                          for (final tile in tiles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: tile,
                            ),
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final tile in tiles)
                          SizedBox(width: (box.maxWidth - 12) / 2, child: tile),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (!answered)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Playing: ${_activeTeam == 0 ? 'Team Ultras' : 'Team Legends'}',
                          style: const TextStyle(color: _muted),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _doubleAvailable[_activeTeam]
                            ? _useDouble
                            : null,
                        icon: const Icon(Icons.bolt_rounded),
                        label: Text(
                          _doubleActive ? '2× ACTIVE' : 'DOUBLE POINTS',
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (correct ? _lime : _red).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: correct ? _lime : _red),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          correct
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: correct ? _lime : _red,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selected == -1
                                ? 'Time is up. ${_question.fact}'
                                : '${correct ? 'Correct!' : 'Not quite.'} ${_question.fact}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _next,
                          child: Text(
                            _questionIndex == _triviaQuestions.length - 1
                                ? 'RESULT'
                                : 'NEXT',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final draw = _scores[0] == _scores[1];
    final winner = _scores[0] > _scores[1] ? 'TEAM ULTRAS' : 'TEAM LEGENDS';
    return Center(
      key: const ValueKey('trivia-result'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(34),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: _lime,
                  foregroundColor: _ink,
                  child: Icon(Icons.emoji_events_rounded, size: 42),
                ),
                const SizedBox(height: 20),
                Text(
                  draw ? 'MATCH DRAWN' : '$winner WIN',
                  textAlign: TextAlign.center,
                  style: _display(38),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Trivia complete · matchday XP awarded',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${_scores[0]}', style: _display(54, color: _blue)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: Text('—', style: _display(30, color: _muted)),
                    ),
                    Text('${_scores[1]}', style: _display(54, color: _red)),
                  ],
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('PLAY AGAIN'),
                ),
                TextButton(
                  onPressed: () => setState(() => _phase = _TriviaPhase.lobby),
                  child: const Text('BACK TO GAME SETUP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArenaBadge extends StatelessWidget {
  const _ArenaBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: .13)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _lime),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _TeamSetupTile extends StatelessWidget {
  const _TeamSetupTile({
    required this.color,
    required this.name,
    required this.initials,
  });
  final Color color;
  final String name;
  final String initials;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Text(
            initials,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Icon(Icons.edit_rounded, color: _muted, size: 18),
      ],
    ),
  );
}

class _GameRule extends StatelessWidget {
  const _GameRule({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(
      color: _surface2,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Icon(icon, color: _lime, size: 19),
        const SizedBox(height: 7),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
      ],
    ),
  );
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.name,
    required this.score,
    required this.active,
    required this.color,
  });
  final String name;
  final int score;
  final bool active;
  final Color color;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: active ? color.withValues(alpha: .15) : _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: active ? color : _line),
    ),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ),
        Text('$score', style: _display(24, color: color)),
      ],
    ),
  );
}

class _TimerDial extends StatelessWidget {
  const _TimerDial({required this.seconds});
  final int seconds;
  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 5;
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: seconds / 20,
            strokeWidth: 5,
            backgroundColor: _line,
            color: urgent ? _red : _lime,
          ),
          Center(
            child: Text(
              '$seconds',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: urgent ? _red : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.answer,
    required this.state,
    required this.onTap,
  });
  final String label;
  final String answer;
  final int state;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = state == 1
        ? _lime
        : state == -1
        ? _red
        : _line;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: state == 0 ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: state == 0 ? .2 : .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: state == 0 ? _surface : color,
              foregroundColor: state == 1 ? _ink : Colors.white,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                answer,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (state != 0)
              Icon(
                state == 1 ? Icons.check_rounded : Icons.close_rounded,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}
