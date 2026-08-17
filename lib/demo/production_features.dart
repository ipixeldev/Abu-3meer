part of 'fan_league_app.dart';

class _ProductionChallenges extends StatelessWidget {
  const _ProductionChallenges({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Watch · answer · collect points',
    title: 'Challenges',
    child: StreamBuilder<List<AbuChallenge>>(
      stream: repository.watchChallenges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 320);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: 'Challenges unavailable',
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final challenges = snapshot.data ?? const [];
        if (challenges.isEmpty) {
          return const _ProductionEmpty(
            icon: Icons.bolt_rounded,
            title: 'The next challenge is being prepared',
            body: 'Secret phrases and hidden Player Cards published by Abu 3meer will appear here.',
          );
        }
        return _ResponsiveGrid(
          children: challenges
              .map(
                (challenge) => _ProductionChallengeCard(
                  challenge: challenge,
                  repository: repository,
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class _ProductionChallengeCard extends StatelessWidget {
  const _ProductionChallengeCard({
    required this.challenge,
    required this.repository,
  });
  final AbuChallenge challenge;
  final ProductionRepository repository;

  Future<void> answer(BuildContext context) async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          challenge.kind == 'playerCard'
              ? 'Claim Player Card'
              : 'Enter the secret phrase',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Your answer'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SUBMIT'),
          ),
        ],
      ),
    );
    if (submitted != true || !context.mounted) return;
    try {
      final result = await repository.submitChallengeAnswer(
        challenge: challenge,
        answer: controller.text,
      );
      if (!context.mounted) return;
      final correct = result['correct'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            correct
                ? 'Correct! +${result['points'] ?? 0} points.'
                : 'Not this time. Watch closely and try again.',
          ),
        ),
      );
      if (correct) await _showPredictionFireworks(context);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _lime.withValues(alpha: .12),
                child: Icon(
                  challenge.kind == 'playerCard'
                      ? Icons.style_rounded
                      : Icons.subtitles_rounded,
                  color: _lime,
                ),
              ),
              const Spacer(),
              _RewardChip(text: '+${challenge.rewardPoints} PTS'),
            ],
          ),
          const SizedBox(height: 18),
          Text(challenge.title, style: _display(22)),
          const SizedBox(height: 7),
          Text(
            challenge.description,
            style: const TextStyle(color: _muted, height: 1.45),
          ),
          const Spacer(),
          const SizedBox(height: 18),
          if (challenge.videoUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(challenge.videoUrl)),
              icon: const Icon(Icons.play_circle_rounded),
              label: const Text('WATCH VIDEO'),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: challenge.isOpen ? () => answer(context) : null,
              child: Text(challenge.isOpen ? 'PLAY NOW' : 'CLOSED'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProductionCommunity extends StatelessWidget {
  const _ProductionCommunity({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Stories · updates · community',
    title: 'Abu 3meer Feed',
    child: StreamBuilder<List<AbuPost>>(
      stream: repository.watchPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 360);
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: 'Feed unavailable',
            body: productionErrorMessage(snapshot.error!),
          );
        }
        final posts = snapshot.data ?? const [];
        if (posts.isEmpty) {
          return const _ProductionEmpty(
            icon: Icons.article_rounded,
            title: 'No posts yet',
            body: 'New articles, match reactions and community updates will appear here.',
          );
        }
        return Column(
          children: posts
              .map(
                (post) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ProductionPostCard(
                    post: post,
                    repository: repository,
                    profile: profile,
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class _ProductionPostCard extends StatelessWidget {
  const _ProductionPostCard({
    required this.post,
    required this.repository,
    required this.profile,
  });
  final AbuPost post;
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 720 && post.imageUrl.isNotEmpty;
        final image = post.imageUrl.isEmpty
            ? null
            : Image.network(
                post.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: _surface2,
                  child: Center(child: Icon(Icons.image_not_supported_rounded)),
                ),
              );
        final copy = Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${post.authorName.toUpperCase()} · ${_productionDate(post.publishedAt)}',
                style: const TextStyle(
                  color: _lime,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(post.title, style: _display(27)),
              const SizedBox(height: 10),
              Text(
                post.body,
                style: const TextStyle(color: _muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => repository.reactToPost(post.id),
                    icon: const Icon(Icons.favorite_border_rounded),
                    label: const Text('SUPPORT'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _PostCommentsDialog(
                        post: post,
                        repository: repository,
                        profile: profile,
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('COMMENTS'),
                  ),
                  if (post.linkUrl.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(post.linkUrl)),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('OPEN LINK'),
                    ),
                ],
              ),
            ],
          ),
        );
        if (wide) {
          return SizedBox(
            height: 320,
            child: Row(
              children: [
                Expanded(flex: 4, child: image!),
                Expanded(flex: 6, child: copy),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (image != null) SizedBox(height: 240, child: image),
            copy,
          ],
        );
      },
    ),
  );
}

class _PostCommentsDialog extends StatefulWidget {
  const _PostCommentsDialog({
    required this.post,
    required this.repository,
    required this.profile,
  });
  final AbuPost post;
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_PostCommentsDialog> createState() => _PostCommentsDialogState();
}

class _PostCommentsDialogState extends State<_PostCommentsDialog> {
  final comment = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (comment.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.repository.addPostComment(
        postId: widget.post.id,
        userName: widget.profile.displayName,
        body: comment.text,
      );
      comment.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.post.title),
    content: SizedBox(
      width: 620,
      height: math.min(560, MediaQuery.sizeOf(context).height * .7),
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<AbuComment>>(
              stream: widget.repository.watchPostComments(widget.post.id),
              builder: (context, snapshot) {
                final comments = snapshot.data ?? const [];
                if (comments.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start the conversation.',
                      style: TextStyle(color: _muted),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final item = comments[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          item.userName.isEmpty ? '?' : item.userName[0],
                        ),
                      ),
                      title: Text(item.userName),
                      subtitle: Text(item.body),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: comment,
                  maxLength: 800,
                  decoration: const InputDecoration(
                    labelText: 'Write a comment',
                    counterText: '',
                  ),
                  onSubmitted: (_) => busy ? null : send(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: busy ? null : send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CLOSE'),
      ),
    ],
  );
}

class _ProductionGames extends StatefulWidget {
  const _ProductionGames({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionGames> createState() => _ProductionGamesState();
}

class _ProductionGamesState extends State<_ProductionGames> {
  bool showEhzerha = false;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Play inside Abu 3meer',
    title: showEhzerha ? 'Ehzerha' : 'Game Center',
    child: showEhzerha
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => showEhzerha = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('ALL GAMES'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: math.max(
                    620,
                    MediaQuery.sizeOf(context).height - 220,
                  ),
                  child: const EhzerhaEmbed(),
                ),
              ),
            ],
          )
        : _ResponsiveGrid(
            children: [
              _GameLaunchCard(
                icon: Icons.psychology_alt_rounded,
                color: _lime,
                title: 'Ehzerha',
                detail: 'The full guessing game, embedded inside the web app.',
                action: 'PLAY EHZERHA',
                onTap: () => setState(() => showEhzerha = true),
              ),
              _GameLaunchCard(
                icon: Icons.groups_rounded,
                color: _gold,
                title: 'Fan Duels',
                detail: 'Challenge another supporter in quick football trivia.',
                action: 'START A DUEL',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _FanDuelPage(
                      repository: widget.repository,
                      profile: widget.profile,
                    ),
                  ),
                ),
              ),
              _GameLaunchCard(
                icon: Icons.quiz_rounded,
                color: _blue,
                title: 'Trivia Arena',
                detail: 'Fast football questions built for mobile and desktop.',
                action: 'ENTER ARENA',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: _TriviaArenaPage()),
                  ),
                ),
              ),
            ],
          ),
  );
}

class _FanDuelPage extends StatefulWidget {
  const _FanDuelPage({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_FanDuelPage> createState() => _FanDuelPageState();
}

class _FanDuelPageState extends State<_FanDuelPage> {
  final code = TextEditingController();
  String activeCode = '';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final created = await widget.repository.createFanDuel(
        hostName: widget.profile.displayName,
      );
      if (mounted) setState(() => activeCode = created);
    } catch (exception) {
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> join() async {
    if (code.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.joinFanDuel(
        code: code.text,
        guestName: widget.profile.displayName,
      );
      if (mounted) setState(() => activeCode = code.text.trim().toUpperCase());
    } catch (exception) {
      if (mounted) setState(() => error = productionErrorMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FAN DUELS')),
    body: activeCode.isEmpty
        ? Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.sports_esports_rounded,
                          color: _lime,
                          size: 58,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'One room. Two fans.',
                          textAlign: TextAlign.center,
                          style: _display(31),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create a room and share its six-character code, or join a friend. The first valid server-timed tap after the countdown wins.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: busy ? null : create,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('CREATE DUEL ROOM'),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 15),
                          child: Text('OR', textAlign: TextAlign.center),
                        ),
                        TextField(
                          controller: code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Room code',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : join,
                          child: const Text('JOIN FRIEND'),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        : StreamBuilder<FanDuel?>(
            stream: widget.repository.watchFanDuel(activeCode),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final room = snapshot.data!;
              return _FanDuelArena(
                repository: widget.repository,
                profile: widget.profile,
                room: room,
              );
            },
          ),
  );
}

class _FanDuelArena extends StatefulWidget {
  const _FanDuelArena({
    required this.repository,
    required this.profile,
    required this.room,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final FanDuel room;

  @override
  State<_FanDuelArena> createState() => _FanDuelArenaState();
}

class _FanDuelArenaState extends State<_FanDuelArena> {
  Timer? ticker;
  bool tapping = false;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> tap() async {
    setState(() => tapping = true);
    try {
      await widget.repository.tapFanDuel(widget.room.code);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => tapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    if (room.status == 'waiting') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ProductionLottieLoader(),
            const SizedBox(height: 20),
            const Text('SHARE THIS ROOM CODE'),
            SelectableText(
              room.code,
              style: _display(58, color: _lime, spacing: 4),
            ),
            const Text(
              'Waiting for the second fan…',
              style: TextStyle(color: _muted),
            ),
          ],
        ),
      );
    }
    final startAt = room.startAt!;
    final remaining = startAt.difference(DateTime.now());
    final started = remaining <= Duration.zero;
    return StreamBuilder<Map<String, DateTime>>(
      stream: widget.repository.watchDuelTaps(room.code),
      builder: (context, snapshot) {
        final taps = snapshot.data ?? const {};
        final ordered = taps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final winnerUid = ordered.isEmpty ? '' : ordered.first.key;
        final mine = taps.containsKey(widget.profile.uid);
        final winnerName = winnerUid == room.hostUid
            ? room.hostName
            : room.guestName;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${room.hostName}  VS  ${room.guestName}',
                    style: _display(28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ROOM ${room.code}',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 36),
                  if (winnerUid.isNotEmpty) ...[
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: _gold,
                      size: 72,
                    ),
                    const SizedBox(height: 12),
                    Text('$winnerName WINS', style: _display(43, color: _gold)),
                  ] else ...[
                    Text(
                      started
                          ? 'TAP!'
                          : '${math.max(1, remaining.inSeconds + 1)}',
                      style: _display(72, color: started ? _lime : _gold),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 280,
                      height: 120,
                      child: FilledButton(
                        onPressed: started && !mine && !tapping ? tap : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: started ? _lime : _surface2,
                          foregroundColor: _ink,
                        ),
                        child: Text(mine ? 'TAP REGISTERED' : 'STRIKE'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GameLaunchCard extends StatelessWidget {
  const _GameLaunchCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 42),
          const SizedBox(height: 26),
          Text(title, style: _display(27)),
          const SizedBox(height: 8),
          Text(detail, style: const TextStyle(color: _muted, height: 1.5)),
          const Spacer(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onTap, child: Text(action)),
          ),
        ],
      ),
    ),
  );
}

class _InteractiveFanCard extends StatefulWidget {
  const _InteractiveFanCard({required this.profile, this.temporaryImage});
  final AbuUserProfile profile;
  final Uint8List? temporaryImage;

  @override
  State<_InteractiveFanCard> createState() => _InteractiveFanCardState();
}

class _ProductionFanWar extends StatelessWidget {
  const _ProductionFanWar({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: 'Barcelona vs Real Madrid · live community totals',
    title: 'Fan War',
    child: StreamBuilder<List<LeaderboardEntry>>(
      stream: repository.watchLeaderboard(monthly: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 360);
        }
        final entries = snapshot.data ?? const [];
        final barca = entries
            .where((entry) => entry.supportedTeam == 'Barcelona')
            .fold<int>(0, (sum, entry) => sum + entry.seasonPoints);
        final madrid = entries
            .where((entry) => entry.supportedTeam == 'Real Madrid')
            .fold<int>(0, (sum, entry) => sum + entry.seasonPoints);
        final total = math.max(1, barca + madrid);
        final barcaShare = barca / total;
        return Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const _ProductionTeamBadge(
                          team: 'Barcelona',
                          source: '',
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text('BARCELONA', style: _display(24))),
                        Text(
                          '${(barcaShare * 100).toStringAsFixed(1)}%',
                          style: _display(30, color: _blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Row(
                        children: [
                          Expanded(
                            flex: math.max(1, (barcaShare * 1000).round()),
                            child: const ColoredBox(
                              color: _blue,
                              child: SizedBox(height: 18),
                            ),
                          ),
                          Expanded(
                            flex: math.max(
                              1,
                              ((1 - barcaShare) * 1000).round(),
                            ),
                            child: const ColoredBox(
                              color: _gold,
                              child: SizedBox(height: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          '$barca PTS',
                          style: const TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$madrid PTS',
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const _ProductionTeamBadge(
                          team: 'Real Madrid',
                          source: '',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: entries.take(12).toList().asMap().entries.map((row) {
                  final entry = row.value;
                  return ListTile(
                    leading: Text('${row.key + 1}', style: _display(18)),
                    title: Text('@${entry.username}'),
                    subtitle: Text(entry.supportedTeam),
                    trailing: Text(
                      '${entry.seasonPoints}',
                      style: _display(19, color: _lime),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ProductionAchievements extends StatelessWidget {
  const _ProductionAchievements({required this.profile});
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    const milestones = <(int, String, IconData)>[
      (100, 'First Century', Icons.looks_one_rounded),
      (500, 'Rising Fan', Icons.trending_up_rounded),
      (1000, 'One Thousand Club', Icons.workspace_premium_rounded),
      (5000, 'Ultra Supporter', Icons.local_fire_department_rounded),
      (10000, 'Abu 3meer Legend', Icons.emoji_events_rounded),
    ];
    return _PageFrame(
      kicker: '${profile.totalPoints} verified points',
      title: 'Achievements',
      child: _ResponsiveGrid(
        children: milestones.map((milestone) {
          final unlocked = profile.totalPoints >= milestone.$1;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    milestone.$3,
                    color: unlocked ? _gold : _muted,
                    size: 38,
                  ),
                  const SizedBox(height: 20),
                  Text(milestone.$2, style: _display(22)),
                  const SizedBox(height: 8),
                  Text(
                    unlocked
                        ? 'UNLOCKED'
                        : '${profile.totalPoints} / ${milestone.$1} PTS',
                    style: TextStyle(
                      color: unlocked ? _lime : _muted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (profile.totalPoints / milestone.$1).clamp(0, 1),
                    color: unlocked ? _gold : _lime,
                    backgroundColor: _line,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProductionRewards extends StatelessWidget {
  const _ProductionRewards({required this.profile});
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: '${profile.seasonPoints} loyalty points available',
    title: 'Rewards',
    child: const _ProductionEmpty(
      icon: Icons.card_giftcard_rounded,
      title: 'Reward catalogue coming soon',
      body: 'The owner will publish real rewards here. No redemption is simulated and no points are removed until the catalogue is connected.',
    ),
  );
}

class _InteractiveFanCardState extends State<_InteractiveFanCard> {
  Offset tilt = Offset.zero;

  void update(Offset local, Size size) {
    setState(() {
      tilt = Offset(
        ((local.dx / size.width) - .5).clamp(-.5, .5),
        ((local.dy / size.height) - .5).clamp(-.5, .5),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final rating = (45 + profile.totalPoints ~/ 500).clamp(45, 99);
    final teamCode = profile.supportedTeam == 'Barcelona' ? 'FCB' : 'RMA';
    final initials = profile.displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateX(-tilt.dy * .24)
      ..rotateY(tilt.dx * .3);
    return LayoutBuilder(
      builder: (context, box) => MouseRegion(
        onHover: (event) => update(event.localPosition, box.biggest),
        onExit: (_) => setState(() => tilt = Offset.zero),
        child: GestureDetector(
          onPanUpdate: (event) => update(event.localPosition, box.biggest),
          onPanEnd: (_) => setState(() => tilt = Offset.zero),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            transform: transform,
            transformAlignment: Alignment.center,
            child: ClipPath(
              clipper: _FanCardClipper(),
              child: Container(
                width: 360,
                height: 500,
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: profile.supportedTeam == 'Barcelona'
                        ? const [Color(0xFF172E63), Color(0xFF671D3D), _surface]
                        : const [
                            Color(0xFFF0F0F4),
                            Color(0xFF8B82C4),
                            _surface,
                          ],
                  ),
                  border: Border.all(color: _gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: .16),
                      blurRadius: 34,
                      offset: Offset(tilt.dx * -18, 20 + tilt.dy * 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Text(
                              '$rating',
                              style: _display(47, color: Colors.white),
                            ),
                            const Text(
                              'RKE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              teamCode,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: SizedBox(
                            height: 235,
                            child: widget.temporaryImage != null
                                ? Image.memory(
                                    widget.temporaryImage!,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                  )
                                : profile.avatarUrl.isNotEmpty
                                ? Image.network(
                                    profile.avatarUrl,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    errorBuilder: (_, _, _) =>
                                        _CardMonogram(initials: initials),
                                  )
                                : _CardMonogram(initials: initials),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Divider(color: Colors.white38, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        profile.displayName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _display(20, color: Colors.white, spacing: .8),
                      ),
                    ),
                    const Divider(color: Colors.white38, height: 1),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _FanCardStat(
                          value: '${profile.totalPoints}',
                          label: 'XP',
                        ),
                        const _FanCardStat(value: '—', label: 'RNK'),
                        const _FanCardStat(value: '0', label: 'STK'),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        const _FanCardStat(value: '0', label: 'ACC'),
                        _FanCardStat(
                          value: '${profile.seasonPoints}',
                          label: 'LTY',
                        ),
                        _FanCardStat(
                          value: profile.role.toUpperCase(),
                          label: 'ROLE',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardMonogram extends StatelessWidget {
  const _CardMonogram({required this.initials});
  final String initials;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      initials.isEmpty ? '?' : initials,
      style: _display(78, color: Colors.white.withValues(alpha: .88)),
    ),
  );
}

class _FanCardStat extends StatelessWidget {
  const _FanCardStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white60,
          fontWeight: FontWeight.w900,
          fontSize: 8,
          letterSpacing: .8,
        ),
      ),
    ],
  );
}

class _FanCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(18, 0)
    ..lineTo(size.width - 18, 0)
    ..lineTo(size.width, 28)
    ..lineTo(size.width, size.height - 56)
    ..lineTo(size.width - 42, size.height)
    ..lineTo(42, size.height)
    ..lineTo(0, size.height - 56)
    ..lineTo(0, 28)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ProductionObsOverlay extends StatelessWidget {
  const _ProductionObsOverlay({
    required this.repository,
    required this.profile,
    required this.onExit,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06101C),
    body: Stack(
      children: [
        const Positioned.fill(child: _PitchBackdrop()),
        Positioned(
          left: 28,
          top: 28,
          bottom: 28,
          width: 420,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xEE0C1422),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const _LiveDot(text: 'LIVE'),
                    const Spacer(),
                    Text('ABU 3MEER LEADERBOARD', style: _display(17)),
                    const SizedBox(width: 10),
                    const _LogoMark(size: 30),
                  ],
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<LeaderboardEntry>>(
                  stream: repository.watchLeaderboard(monthly: false),
                  builder: (context, snapshot) {
                    final entries = snapshot.data ?? const [];
                    return Expanded(
                      child: ListView.separated(
                        itemCount: math.min(10, entries.length),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Text(
                              '${index + 1}',
                              style: _display(
                                18,
                                color: index < 3 ? _gold : Colors.white,
                              ),
                            ),
                            title: Text('@${entry.username}'),
                            subtitle: Text(entry.supportedTeam),
                            trailing: Text(
                              '${entry.seasonPoints}',
                              style: const TextStyle(
                                color: _lime,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const Text(
                  'Browser Source · transparent-safe · updates live',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 30,
          top: 30,
          child: Row(
            children: [
              _Pill(
                icon: Icons.stars_rounded,
                text: '${profile.totalPoints}',
                color: _gold,
              ),
              const SizedBox(width: 10),
              const _LiveDot(text: 'LIVE'),
            ],
          ),
        ),
        Positioned(
          right: 30,
          bottom: 30,
          child: FilledButton.icon(
            onPressed: onExit,
            icon: const Icon(Icons.close_fullscreen_rounded),
            label: const Text('EXIT OVERLAY'),
          ),
        ),
      ],
    ),
  );
}

class _ProductionAdminTools extends StatelessWidget {
  const _ProductionAdminTools({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CONTENT & ACCESS', style: _display(22)),
          const SizedBox(height: 6),
          Text(
            'Publish the experiences users see without rebuilding the app. Signed in as ${profile.role}.',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => createChallenge(context),
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('NEW CHALLENGE'),
              ),
              OutlinedButton.icon(
                onPressed: () => createPost(context),
                icon: const Icon(Icons.post_add_rounded),
                label: const Text('NEW POST'),
              ),
              OutlinedButton.icon(
                onPressed: () => editAnnouncement(context),
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('LAUNCH POPUP'),
              ),
              if (profile.canManageRoles)
                OutlinedButton.icon(
                  onPressed: () => manageRoles(context),
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: const Text('ROLES & ADMINS'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> createChallenge(BuildContext context) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final video = TextEditingController();
    final answer = TextEditingController();
    final points = TextEditingController(text: '40');
    var kind = 'videoQuestion';
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create challenge'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'videoQuestion',
                        label: Text('SECRET PHRASE'),
                      ),
                      ButtonSegment(
                        value: 'playerCard',
                        label: Text('PLAYER CARD'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (value) =>
                        setDialogState(() => kind = value.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: video,
                    decoration: const InputDecoration(
                      labelText: 'YouTube/video URL',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: answer,
                    decoration: const InputDecoration(
                      labelText: 'Private correct answer',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: points,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Reward points',
                    ),
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
              child: const Text('PUBLISH'),
            ),
          ],
        ),
      ),
    );
    if (submit != true || !context.mounted) return;
    await _adminAction(context, () {
      return repository.createChallenge(
        kind: kind,
        title: title.text,
        description: description.text,
        videoUrl: video.text,
        answer: answer.text,
        rewardPoints: int.parse(points.text),
        availableFrom: DateTime.now(),
        availableUntil: DateTime.now().add(const Duration(days: 7)),
      );
    }, 'Challenge published.');
  }

  Future<void> createPost(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final image = TextEditingController();
    final link = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish a post'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Headline'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: 'Post'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: image,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(
                    labelText: 'Clickable link (optional)',
                  ),
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
            child: const Text('PUBLISH'),
          ),
        ],
      ),
    );
    if (submit != true || !context.mounted) return;
    await _adminAction(
      context,
      () => repository.createPost(
        title: title.text,
        body: body.text,
        imageUrl: image.text,
        linkUrl: link.text,
        authorName: profile.displayName,
      ),
      'Post published.',
    );
  }

  Future<void> editAnnouncement(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final image = TextEditingController();
    final link = TextEditingController();
    final label = TextEditingController(text: 'OPEN NOW');
    var enabled = true;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('App-launch popup'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                    title: const Text('Show on app launch'),
                  ),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: body,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: image,
                    decoration: const InputDecoration(labelText: 'Image URL'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: link,
                    decoration: const InputDecoration(
                      labelText: 'Clickable link',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                    ),
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
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
    if (submit != true || !context.mounted) return;
    await _adminAction(
      context,
      () => repository.saveAnnouncement(
        enabled: enabled,
        title: title.text,
        body: body.text,
        imageUrl: image.text,
        linkUrl: link.text,
        buttonLabel: label.text,
      ),
      'Launch popup saved.',
    );
  }

  Future<void> manageRoles(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Roles & administrators'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: StreamBuilder<List<AbuUserProfile>>(
          stream: repository.watchUsers(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(productionErrorMessage(snapshot.error!)),
              );
            }
            final users = snapshot.data ?? const [];
            if (users.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      user.displayName.isEmpty ? '?' : user.displayName[0],
                    ),
                  ),
                  title: Text(user.displayName),
                  subtitle: Text('@${user.username} · ${user.email}'),
                  trailing: DropdownButton<String>(
                    value:
                        const [
                          'user',
                          'moderator',
                          'editor',
                          'admin',
                        ].contains(user.role)
                        ? user.role
                        : 'user',
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(
                        value: 'moderator',
                        child: Text('Moderator'),
                      ),
                      DropdownMenuItem(value: 'editor', child: Text('Editor')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: user.uid == profile.uid
                        ? null
                        : (role) async {
                            if (role == null) return;
                            try {
                              await repository.setUserRole(
                                uid: user.uid,
                                role: role,
                              );
                            } catch (error) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
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
                );
              },
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('DONE'),
        ),
      ],
    ),
  );

  Future<void> _adminAction(
    BuildContext context,
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
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

final Set<int> _shownAnnouncementRevisions = <int>{};

Future<void> showLaunchAnnouncement(
  BuildContext context,
  LaunchAnnouncement announcement,
) async {
  if (!announcement.enabled ||
      announcement.title.isEmpty ||
      _shownAnnouncementRevisions.contains(announcement.revision)) {
    return;
  }
  _shownAnnouncementRevisions.add(announcement.revision);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      title: announcement.imageUrl.isEmpty
          ? null
          : SizedBox(
              height: 230,
              width: 520,
              child: Image.network(announcement.imageUrl, fit: BoxFit.cover),
            ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(announcement.title, style: _display(27)),
            const SizedBox(height: 10),
            Text(
              announcement.body,
              style: const TextStyle(color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('LATER'),
        ),
        if (announcement.linkUrl.isNotEmpty)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse(announcement.linkUrl));
            },
            child: Text(announcement.buttonLabel),
          ),
      ],
    ),
  );
}
