part of 'fan_league_app.dart';

class _ProductionChallenges extends StatelessWidget {
  const _ProductionChallenges({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'Watch · answer · collect points',
      'شاهد · أجب · اجمع النقاط',
    ),
    title: abuText(context, 'Challenges', 'التحديات'),
    child: StreamBuilder<List<AbuChallenge>>(
      stream: repository.watchChallenges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 220);
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
          return const _ProductionChallengeEmptyState();
        }
        return _ResponsiveGrid(
          minWidth: 330,
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

class _ProductionChallengeEmptyState extends StatelessWidget {
  const _ProductionChallengeEmptyState();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return const _ProductionEmpty(
          icon: Icons.bolt_rounded,
          title: 'The next challenge is being prepared',
          body: 'Secret phrases and hidden Player Cards published by Abu 3meer will appear here.',
        );
      }
      final types = const [
        (
          Icons.subtitles_rounded,
          'SECRET PHRASE',
          'Listen closely to the latest video',
        ),
        (
          Icons.style_rounded,
          'PLAYER CARD',
          'Find the hidden player and claim it',
        ),
        (Icons.quiz_rounded, 'MATCH QUIZ', 'Timed football knowledge rounds'),
      ];
      return SizedBox(
        height: 280,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 7,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(34),
                  child: Row(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: _lime.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _lime.withValues(alpha: .24),
                          ),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: _lime,
                          size: 46,
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _LiveDot(text: 'NEXT DROP'),
                            const SizedBox(height: 13),
                            Text(
                              'The next challenge is being prepared',
                              style: _display(29),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'New playable events appear here as soon as Abu 3meer publishes them from Admin Studio.',
                              style: TextStyle(color: _muted, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CHALLENGE FORMATS', style: _display(19)),
                      const SizedBox(height: 12),
                      for (final type in types)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(type.$1, color: _lime, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      type.$2,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .8,
                                      ),
                                    ),
                                    Text(
                                      type.$3,
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
                    ],
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

class _ProductionHomeActivityFeed extends StatelessWidget {
  const _ProductionHomeActivityFeed({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AbuChallenge>>(
    stream: repository.watchChallenges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionSkeleton(height: 210);
      }
      final active = (snapshot.data ?? const <AbuChallenge>[])
          .where((event) => event.isOpen)
          .take(3)
          .toList();
      if (active.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('YOUR NEXT MOVES', style: _display(22)),
              const Spacer(),
              Text(
                '${active.length} LIVE',
                style: const TextStyle(
                  color: _lime,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResponsiveGrid(
            children: active
                .map(
                  (event) => _ProductionChallengeCard(
                    challenge: event,
                    repository: repository,
                  ),
                )
                .toList(),
          ),
        ],
      );
    },
  );
}

class _ProductionCommunity extends StatelessWidget {
  const _ProductionCommunity({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'Stories · updates · community',
      'قصص · أخبار · مجتمع',
    ),
    title: abuText(context, 'Abu 3meer Feed', 'منشورات أبو عمير'),
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
          return const _ProductionCommunityEmptyState();
        }
        return _ProductionCommunityContent(
          posts: posts,
          repository: repository,
          profile: profile,
        );
      },
    ),
  );
}

class _ProductionCommunityEmptyState extends StatelessWidget {
  const _ProductionCommunityEmptyState();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 980) {
        return const _ProductionEmpty(
          icon: Icons.article_rounded,
          title: 'No posts yet',
          body: 'New articles, match reactions and community updates will appear here.',
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 7,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(34),
                child: Row(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: _lime.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.newspaper_rounded,
                        color: _lime,
                        size: 42,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _LiveDot(text: 'EDITORIAL DESK'),
                          const SizedBox(height: 12),
                          Text(
                            'The first story is being prepared',
                            style: _display(29),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Match reactions, creator updates and community stories will be published here from Admin Studio.',
                            style: TextStyle(color: _muted, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('COMMUNITY DESK', style: _display(20)),
                    const Spacer(),
                    const _CommunityDeskMetric(
                      icon: Icons.article_outlined,
                      value: '0',
                      label: 'PUBLISHED STORIES',
                    ),
                    const SizedBox(height: 18),
                    const _CommunityDeskMetric(
                      icon: Icons.forum_outlined,
                      value: 'LIVE',
                      label: 'COMMENTS & REACTIONS',
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ProductionCommunityContent extends StatelessWidget {
  const _ProductionCommunityContent({
    required this.posts,
    required this.repository,
    required this.profile,
  });

  final List<AbuPost> posts;
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 980) {
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
      }

      final latest = posts.first;
      final recent = posts.skip(1).take(4).toList();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 7,
            child: _ProductionPostCard(
              post: latest,
              repository: repository,
              profile: profile,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COMMUNITY DESK', style: _display(20)),
                        const SizedBox(height: 18),
                        _CommunityDeskMetric(
                          icon: Icons.article_outlined,
                          value: '${posts.length}',
                          label: 'PUBLISHED STORIES',
                        ),
                        const SizedBox(height: 16),
                        _CommunityDeskMetric(
                          icon: Icons.schedule_rounded,
                          value: _productionDate(latest.publishedAt),
                          label: 'LATEST UPDATE',
                        ),
                      ],
                    ),
                  ),
                ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MORE STORIES', style: _display(18)),
                          const SizedBox(height: 8),
                          for (final post in recent)
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => _PostCommentsDialog(
                                  post: post,
                                  repository: repository,
                                  profile: profile,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            post.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _productionDate(post.publishedAt),
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: _lime,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _CommunityDeskMetric extends StatelessWidget {
  const _CommunityDeskMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: _lime, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: _display(17)),
            Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ],
        ),
      ),
    ],
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
            : post.imageUrl.startsWith('assets/')
            ? Image.asset(post.imageUrl, fit: BoxFit.cover)
            : _ProductionRemoteImage(
                url: post.imageUrl,
                fit: BoxFit.cover,
                fallback: const ColoredBox(
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
                      onPressed: () async {
                        final uri = externalHttpUri(post.linkUrl);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
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
    kicker: abuText(context, 'Play inside Abu 3meer', 'العب داخل أبو عمير'),
    title: showEhzerha
        ? 'Ehzerha'
        : abuText(context, 'Game Center', 'مركز الألعاب'),
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
    kicker: abuText(
      context,
      'Barcelona vs Real Madrid · live community totals',
      'برشلونة ضد ريال مدريد · مجموع المجتمع المباشر',
    ),
    title: abuText(context, 'Fan War', 'حرب الجماهير'),
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
        final total = barca + madrid;
        final barcaShare = total == 0 ? .5 : barca / total;
        return _ProductionFanWarContent(
          entries: entries,
          barcaPoints: barca,
          madridPoints: madrid,
          barcaShare: barcaShare,
        );
      },
    ),
  );
}

class _ProductionFanWarContent extends StatelessWidget {
  const _ProductionFanWarContent({
    required this.entries,
    required this.barcaPoints,
    required this.madridPoints,
    required this.barcaShare,
  });

  final List<LeaderboardEntry> entries;
  final int barcaPoints;
  final int madridPoints;
  final double barcaShare;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final battle = _FanWarBattleCard(
        barcaPoints: barcaPoints,
        madridPoints: madridPoints,
        barcaShare: barcaShare,
      );
      final contributors = _FanWarContributorCard(
        entries: entries.take(12).toList(),
        desktop: constraints.maxWidth >= 1040,
      );
      if (constraints.maxWidth < 1040) {
        return Column(
          children: [battle, const SizedBox(height: 16), contributors],
        );
      }

      final barcaFans = entries
          .where((entry) => entry.supportedTeam == 'Barcelona')
          .length;
      final madridFans = entries
          .where((entry) => entry.supportedTeam == 'Real Madrid')
          .length;
      final leader = barcaPoints == madridPoints
          ? 'LEVEL'
          : barcaPoints > madridPoints
          ? 'BARCELONA'
          : 'REAL MADRID';
      final margin = (barcaPoints - madridPoints).abs();
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.groups_rounded,
                  value: '${entries.length}',
                  label: 'ACTIVE SUPPORTERS',
                  color: _lime,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.stars_rounded,
                  value: '${barcaPoints + madridPoints}',
                  label: 'VERIFIED POINTS',
                  color: _gold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.flag_rounded,
                  value: leader,
                  label: margin == 0 ? 'CURRENTLY TIED' : '$margin POINT LEAD',
                  color: leader == 'BARCELONA' ? _blue : _gold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.sports_soccer_rounded,
                  value: '$barcaFans / $madridFans',
                  label: 'BARÇA / MADRID FANS',
                  color: _red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: battle),
              const SizedBox(width: 18),
              Expanded(flex: 7, child: contributors),
            ],
          ),
        ],
      );
    },
  );
}

class _FanWarKpi extends StatelessWidget {
  const _FanWarKpi({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _display(21),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .6,
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

class _FanWarBattleCard extends StatelessWidget {
  const _FanWarBattleCard({
    required this.barcaPoints,
    required this.madridPoints,
    required this.barcaShare,
  });

  final int barcaPoints;
  final int madridPoints;
  final double barcaShare;

  @override
  Widget build(BuildContext context) {
    final madridShare = 1 - barcaShare;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _LiveDot(text: 'LIVE BATTLE'),
                Text('ALL TIME', style: _display(13, color: _muted)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const _ProductionTeamBadge(team: 'Barcelona', source: ''),
                const SizedBox(width: 12),
                Expanded(child: Text('BARCELONA', style: _display(22))),
                Text(
                  '${(barcaShare * 100).toStringAsFixed(1)}%',
                  style: _display(30, color: _blue),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                    flex: math.max(1, (madridShare * 1000).round()),
                    child: const ColoredBox(
                      color: _gold,
                      child: SizedBox(height: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '$barcaPoints PTS',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '$madridPoints PTS',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                const _ProductionTeamBadge(team: 'Real Madrid', source: ''),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FanWarContributorCard extends StatelessWidget {
  const _FanWarContributorCard({required this.entries, required this.desktop});

  final List<LeaderboardEntry> entries;
  final bool desktop;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: EdgeInsets.all(desktop ? 22 : 0),
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(28),
              child: _ProductionEmpty(
                icon: Icons.groups_rounded,
                title: 'No contributors yet',
                body: 'Verified fan activity will populate this table.',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('TOP CONTRIBUTORS', style: _display(20)),
                      ),
                      const Text(
                        'LIVE VERIFIED TOTALS',
                        style: TextStyle(
                          color: _lime,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 48, child: Text('RANK')),
                        Expanded(flex: 3, child: Text('SUPPORTER')),
                        Expanded(flex: 2, child: Text('CLUB')),
                        SizedBox(
                          width: 90,
                          child: Text('POINTS', textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 22),
                ],
                ...entries.asMap().entries.map((row) {
                  final entry = row.value;
                  if (!desktop) {
                    return ListTile(
                      leading: Text('${row.key + 1}', style: _display(18)),
                      title: Text('@${entry.username}'),
                      subtitle: Text(entry.supportedTeam),
                      trailing: Text(
                        '${entry.seasonPoints}',
                        style: _display(19, color: _lime),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '#${row.key + 1}',
                            style: _display(
                              16,
                              color: row.key < 3 ? _gold : null,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '@${entry.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.supportedTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${entry.seasonPoints}',
                            textAlign: TextAlign.end,
                            style: _display(17, color: _lime),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
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
      kicker: abuText(
        context,
        '${profile.totalPoints} verified points',
        '${profile.totalPoints} نقطة موثقة',
      ),
      title: abuText(context, 'Achievements', 'الإنجازات'),
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
  Widget build(BuildContext context) {
    final mock = TemporaryMockData.instance.enabled;
    return _PageFrame(
      kicker: abuText(
        context,
        '${profile.seasonPoints} loyalty points available',
        '${profile.seasonPoints} نقطة ولاء متاحة',
      ),
      title: abuText(context, 'Rewards', 'المكافآت'),
      child: !mock
          ? const _ProductionEmpty(
              icon: Icons.card_giftcard_rounded,
              title: 'Reward catalogue coming soon',
              body: 'The owner will publish real rewards here. No redemption is simulated and no points are removed until the catalogue is connected.',
            )
          : _ResponsiveGrid(
              children:
                  const [
                        (
                          'SIGNED HOME SHIRT',
                          '5,000 PTS',
                          Icons.checkroom_rounded,
                        ),
                        (
                          'ABU 3MEER VIDEO SHOUTOUT',
                          '2,500 PTS',
                          Icons.record_voice_over_rounded,
                        ),
                        (
                          '€25 STORE CREDIT',
                          '1,800 PTS',
                          Icons.wallet_giftcard_rounded,
                        ),
                        (
                          'MONTHLY GIVEAWAY ENTRY',
                          '500 PTS',
                          Icons.confirmation_number_rounded,
                        ),
                      ]
                      .map(
                        (reward) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(reward.$3, color: _gold, size: 36),
                                const Spacer(),
                                Text(reward.$1, style: _display(20)),
                                const SizedBox(height: 7),
                                Text(
                                  reward.$2,
                                  style: const TextStyle(
                                    color: _lime,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: null,
                                    child: Text('PREVIEW REWARD'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
    );
  }
}

class _InteractiveFanCardState extends State<_InteractiveFanCard>
    with SingleTickerProviderStateMixin {
  static const _cardSize = Size(320, 448);
  Offset _targetTilt = Offset.zero;
  Offset _currentTilt = Offset.zero;
  late final AnimationController _controller;
  Offset _velocity = Offset.zero;
  static const double _stiffness = 110;
  static const double _damping = 18;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updatePhysics);
  }

  void _updatePhysics() {
    const dt = .016;
    final forceX =
        (_targetTilt.dx - _currentTilt.dx) * _stiffness -
        _velocity.dx * _damping;
    final forceY =
        (_targetTilt.dy - _currentTilt.dy) * _stiffness -
        _velocity.dy * _damping;
    _velocity = Offset(_velocity.dx + forceX * dt, _velocity.dy + forceY * dt);
    _currentTilt = Offset(
      _currentTilt.dx + _velocity.dx * dt,
      _currentTilt.dy + _velocity.dy * dt,
    );
    if (mounted) setState(() {});
    if (_velocity.distance < .001 &&
        (_targetTilt - _currentTilt).distance < .001) {
      _controller.stop();
    }
  }

  void _setTargetTilt(Offset target) {
    _targetTilt = Offset(
      target.dx.clamp(-1.0, 1.0),
      target.dy.clamp(-1.0, 1.0),
    );
    if (!_controller.isAnimating) _controller.repeat();
  }

  void _updateTarget(Offset local) => _setTargetTilt(
    Offset(
      ((local.dx / _cardSize.width) - .5) * 2,
      ((local.dy / _cardSize.height) - .5) * 2,
    ),
  );

  void _release() {
    if (mounted) setState(() => _isHovered = false);
    _setTargetTilt(Offset.zero);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final teamCode = profile.supportedTeam == 'Barcelona' ? 'FCB' : 'RMA';
    final initials = profile.displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final rotateX = -_currentTilt.dy * 14 * (math.pi / 180);
    final rotateY = _currentTilt.dx * 14 * (math.pi / 180);
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .001)
      ..rotateX(rotateX)
      ..rotateY(rotateY);
    final glowAlignment = Alignment(
      -_currentTilt.dx * 1.5,
      -_currentTilt.dy * 1.5,
    );
    final portrait = widget.temporaryImage != null
        ? Image.memory(
            widget.temporaryImage!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => _CardMonogram(initials: initials),
          )
        : profile.avatarUrl.isNotEmpty
        ? _ProductionRemoteImage(
            url: profile.avatarUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            fallback: _CardMonogram(initials: initials),
          )
        : _CardMonogram(initials: initials);
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => _release(),
        onHover: (event) => _updateTarget(event.localPosition),
        child: GestureDetector(
          onPanStart: (event) {
            setState(() => _isHovered = true);
            _updateTarget(event.localPosition);
          },
          onPanUpdate: (event) {
            if (!_isHovered) setState(() => _isHovered = true);
            _updateTarget(event.localPosition);
          },
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: Container(
            width: _cardSize.width,
            height: _cardSize.height,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .75),
                  blurRadius: 34,
                  offset: const Offset(0, 26),
                ),
              ],
            ),
            child: Transform(
              transform: transform,
              alignment: Alignment.center,
              child: ClipPath(
                clipper: _FanCardClipper(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2B3038),
                            Color(0xFF1A1E25),
                            Color(0xFF14171C),
                          ],
                          stops: [0, .55, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  const Text(
                                    '45',
                                    style: TextStyle(
                                      color: Color(0xFFE8E8E8),
                                      fontSize: 42,
                                      fontWeight: FontWeight.w900,
                                      height: .85,
                                    ),
                                  ),
                                  const Text(
                                    'RKE',
                                    style: TextStyle(
                                      color: Color(0xFFE8E8E8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Container(
                                    width: 28,
                                    height: 1,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    color: Colors.white24,
                                  ),
                                  Text(
                                    teamCode,
                                    style: const TextStyle(
                                      color: Color(0xFFE8E8E8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: Center(
                                  child:
                                      widget.temporaryImage != null ||
                                          profile.avatarUrl.isNotEmpty
                                      ? SizedBox(
                                          width: 118,
                                          height: 168,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: portrait,
                                          ),
                                        )
                                      : Text(
                                          initials.isEmpty ? '?' : initials,
                                          style: const TextStyle(
                                            color: Color(0xFFE8E8E8),
                                            fontSize: 54,
                                            fontWeight: FontWeight.w900,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black54,
                                                blurRadius: 24,
                                                offset: Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(height: 1, color: Colors.white24),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              profile.displayName.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          Container(height: 1, color: Colors.white24),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _FanCardStat(
                                value: '${profile.totalPoints}',
                                label: 'XP',
                              ),
                              _FanCardStat(
                                value: profile.monthlyPoints == 0
                                    ? '—'
                                    : '#342',
                                label: 'RNK',
                                reverse: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _FanCardStat(
                                value: '${profile.currentStreak}',
                                label: 'STK',
                              ),
                              const _FanCardStat(value: '0', label: 'ACC'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _FanCardStat(
                                value: '${profile.seasonPoints}',
                                label: 'LTY',
                              ),
                              const _FanCardStat(
                                value: '—',
                                label: 'BST',
                                reverse: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _isHovered ? 1 : .5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: glowAlignment,
                              radius: .8,
                              colors: [
                                Colors.white.withValues(alpha: .26),
                                Colors.white.withValues(alpha: .05),
                                Colors.transparent,
                              ],
                              stops: const [0, .45, .7],
                            ),
                          ),
                        ),
                      ),
                    ),
                    CustomPaint(painter: _FanCardBorderPainter()),
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
  const _FanCardStat({
    required this.value,
    required this.label,
    this.reverse = false,
  });
  final String value;
  final String label;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
    final labelText = Text(
      label,
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: .8,
      ),
    );
    return SizedBox(
      width: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: reverse
            ? [labelText, const SizedBox(width: 4), valueText]
            : [valueText, const SizedBox(width: 4), labelText],
      ),
    );
  }
}

class _FanCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .03, 0)
    ..lineTo(size.width * .97, 0)
    ..lineTo(size.width, size.height * .035)
    ..lineTo(size.width, size.height * .88)
    ..lineTo(size.width * .88, size.height)
    ..lineTo(size.width * .12, size.height)
    ..lineTo(0, size.height * .88)
    ..lineTo(0, size.height * .035)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _FanCardBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _FanCardClipper().getClip(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF6B7280),
          Color(0xFF9CA3AF),
          Color(0xFF4B5563),
          Color(0xFF9CA3AF),
          Color(0xFF6B7280),
        ],
        stops: [0, .22, .48, .78, 1],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProductionStreak extends StatelessWidget {
  const _ProductionStreak({required this.profile});
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final activeDays = profile.currentStreak;
    final now = DateTime.now();
    final monthDays = DateUtils.getDaysInMonth(now.year, now.month);
    return _PageFrame(
      kicker: abuText(
        context,
        'Build momentum every day',
        'حافظ على نشاطك كل يوم',
      ),
      title: abuText(context, 'Activity Streak', 'سلسلة النشاط'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final calendar = Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: _red,
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Text('$activeDays', style: _display(44, color: _red)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          abuText(context, 'DAY STREAK', 'يوم متواصل'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${now.year} · ${now.month.toString().padLeft(2, '0')}',
                    style: _display(20),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: monthDays,
                    itemBuilder: (context, i) {
                      final day = i + 1;
                      final completed =
                          activeDays > 0 &&
                          day <= now.day &&
                          day > now.day - activeDays;
                      final today = day == now.day;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: completed
                              ? _lime.withValues(alpha: .18)
                              : Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: today ? _lime : _line,
                            width: today ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: completed
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: _lime,
                                  size: 18,
                                )
                              : Text(
                                  '$day',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
          final milestones = Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    abuText(context, 'STREAK MILESTONES', 'مراحل السلسلة'),
                    style: _display(22),
                  ),
                  const SizedBox(height: 16),
                  for (final milestone in const [
                    (3, 'Warm up'),
                    (7, 'On fire'),
                    (14, 'Unstoppable'),
                    (30, 'Club legend'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: activeDays >= milestone.$1
                            ? _lime
                            : _line,
                        foregroundColor: _ink,
                        child: Text('${milestone.$1}'),
                      ),
                      title: Text(
                        milestone.$2,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: Icon(
                        activeDays >= milestone.$1
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        color: activeDays >= milestone.$1 ? _lime : _muted,
                      ),
                    ),
                  const Divider(),
                  Text(
                    activeDays == 0
                        ? abuText(
                            context,
                            'Complete an eligible activity today to start your streak.',
                            'أكمل نشاطاً مؤهلاً اليوم لبدء سلسلتك.',
                          )
                        : abuText(
                            context,
                            'Come back tomorrow so your streak stays alive.',
                            'عد غداً للحفاظ على سلسلتك.',
                          ),
                    style: const TextStyle(color: _muted, height: 1.5),
                  ),
                ],
              ),
            ),
          );
          if (constraints.maxWidth >= 820) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: calendar),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: milestones),
              ],
            );
          }
          return Column(
            children: [calendar, const SizedBox(height: 16), milestones],
          );
        },
      ),
    );
  }
}

class _ProductionObsOverlay extends StatefulWidget {
  const _ProductionObsOverlay({
    required this.repository,
    required this.profile,
    required this.onExit,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;
  final VoidCallback onExit;

  @override
  State<_ProductionObsOverlay> createState() => _ProductionObsOverlayState();
}

class _ProductionObsOverlayState extends State<_ProductionObsOverlay> {
  @override
  void initState() {
    super.initState();
    setObsOverlayActive(true);
  }

  @override
  void dispose() {
    setObsOverlayActive(false);
    super.dispose();
  }

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
                  stream: widget.repository.watchLeaderboard(monthly: false),
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
                text: '${widget.profile.totalPoints}',
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
            onPressed: widget.onExit,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 980) return _buildMobile(context);
      final actions = <Widget>[
        _AdminQuickAction(
          icon: Icons.bolt_rounded,
          label: 'NEW CHALLENGE',
          detail: 'Publish a phrase, quiz or Player Card challenge.',
          color: _lime,
          primary: true,
          onTap: () => createChallenge(context),
        ),
        _AdminQuickAction(
          icon: Icons.post_add_rounded,
          label: 'NEW POST',
          detail: 'Add an article, image, reaction or external link.',
          color: _blue,
          onTap: () => createPost(context),
        ),
        _AdminQuickAction(
          icon: Icons.campaign_rounded,
          label: 'LAUNCH POPUP',
          detail: 'Schedule an in-app campaign for every platform.',
          color: _gold,
          onTap: () => editAnnouncement(context),
        ),
        if (profile.canManageRoles)
          _AdminQuickAction(
            icon: Icons.manage_accounts_rounded,
            label: 'ROLES & ADMINS',
            detail: 'Grant scoped access to trusted collaborators.',
            color: _red,
            onTap: () => manageRoles(context),
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                Expanded(child: actions[index]),
                if (index != actions.length - 1) const SizedBox(width: 14),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _lime.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_rounded,
                          color: _lime,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ENGAGEMENT CONTROL', style: _display(22)),
                            Text(
                              'Live content operations · signed in as ${profile.role.toUpperCase()}',
                              style: const TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const _LiveDot(text: 'REAL-TIME'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _AdminEventManager(repository: repository),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildMobile(BuildContext context) => Card(
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
          const SizedBox(height: 18),
          _AdminEventManager(repository: repository),
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
    var status = 'open';
    var maximumAttempts = 3;
    var memberOnly = false;
    var notifyOnLive = true;
    var startsAt = DateTime.now();
    var endsAt = DateTime.now().add(const Duration(days: 7));
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
                    onSelectionChanged: (value) => setDialogState(() {
                      kind = value.first;
                      points.text = kind == 'playerCard' ? '20' : '40';
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'draft', child: Text('Draft')),
                      DropdownMenuItem(
                        value: 'scheduled',
                        child: Text('Scheduled'),
                      ),
                      DropdownMenuItem(value: 'open', child: Text('Live')),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text('Disabled'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => status = value ?? 'draft'),
                  ),
                  _AdminDateTile(
                    label: 'Starts',
                    value: startsAt,
                    onChanged: (value) =>
                        setDialogState(() => startsAt = value),
                  ),
                  _AdminDateTile(
                    label: 'Ends',
                    value: endsAt,
                    onChanged: (value) => setDialogState(() => endsAt = value),
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
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: maximumAttempts,
                    decoration: const InputDecoration(
                      labelText: 'Maximum attempts',
                    ),
                    items: const [1, 2, 3, 5, 10]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => maximumAttempts = value ?? 3),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: memberOnly,
                    onChanged: (value) =>
                        setDialogState(() => memberOnly = value),
                    title: const Text('YouTube members only'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: notifyOnLive,
                    onChanged: (value) =>
                        setDialogState(() => notifyOnLive = value),
                    title: const Text('Notify users when live'),
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
        availableFrom: startsAt,
        availableUntil: endsAt,
        status: status,
        maximumAttempts: maximumAttempts,
        memberOnly: memberOnly,
        notifyOnLive: notifyOnLive,
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
    LaunchAnnouncement? existing;
    try {
      existing = await repository.watchLaunchAnnouncement().first;
    } catch (_) {
      // A missing announcement is a valid first-run state. The save action
      // below will still surface any real Firestore permission/network error.
    }
    if (!context.mounted) return;
    final title = TextEditingController(text: existing?.title ?? '');
    final body = TextEditingController(text: existing?.body ?? '');
    final image = TextEditingController(text: existing?.imageUrl ?? '');
    final link = TextEditingController(text: existing?.linkUrl ?? '');
    final label = TextEditingController(
      text: existing?.buttonLabel ?? 'OPEN NOW',
    );
    var enabled = existing?.enabled ?? true;
    var frequency = existing?.frequency ?? 'once';
    var startsAt = existing?.startsAt ?? DateTime.now();
    var endsAt =
        existing?.endsAt ?? DateTime.now().add(const Duration(days: 7));
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('APP-LAUNCH POPUP'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                    title: const Text('Show on app launch'),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'SCHEDULE & DELIVERY',
                          style: TextStyle(
                            color: _lime,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: frequency,
                          decoration: const InputDecoration(
                            labelText: 'How often should each user see it?',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'once',
                              child: Text('Once for this campaign'),
                            ),
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('Once per day'),
                            ),
                            DropdownMenuItem(
                              value: 'session',
                              child: Text('Once per app session'),
                            ),
                            DropdownMenuItem(
                              value: 'always',
                              child: Text('Every app launch'),
                            ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => frequency = value ?? 'once'),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final start = _AdminDateTile(
                              label: 'Starts (date & time)',
                              value: startsAt,
                              onChanged: (value) =>
                                  setDialogState(() => startsAt = value),
                            );
                            final end = _AdminDateTile(
                              label: 'Expires (date & time)',
                              value: endsAt,
                              onChanged: (value) =>
                                  setDialogState(() => endsAt = value),
                            );
                            if (constraints.maxWidth < 560) {
                              return Column(children: [start, end]);
                            }
                            return Row(
                              children: [
                                Expanded(child: start),
                                const SizedBox(width: 10),
                                Expanded(child: end),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Direct image URL (optional)',
                      helperText: 'Use an http(s) image URL. Firebase Storage is recommended.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Clickable link (optional)',
                      helperText:
                          'iamr.dev is automatically saved as https://iamr.dev',
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
        frequency: frequency,
        startsAt: startsAt,
        endsAt: endsAt,
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

class _AdminQuickAction extends StatelessWidget {
  const _AdminQuickAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Card(
    color: primary ? _lime.withValues(alpha: .09) : null,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const Spacer(),
                Icon(Icons.north_east_rounded, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 24),
            Text(label, style: _display(18)),
            const SizedBox(height: 6),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AdminEventManager extends StatelessWidget {
  const _AdminEventManager({required this.repository});
  final ProductionRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AbuChallenge>>(
    stream: repository.watchManagedChallenges(),
    builder: (context, snapshot) {
      final events = snapshot.data ?? const <AbuChallenge>[];
      if (events.isEmpty) {
        return const _ProductionEmpty(
          icon: Icons.event_note_rounded,
          title: 'No engagement events yet',
          body: 'Create a Video Question or Player Card event above.',
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!desktop) ...[
                Text('EVENT CONTROL', style: _display(18)),
                const SizedBox(height: 8),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 52, child: Text('TYPE')),
                      Expanded(flex: 4, child: Text('EVENT')),
                      Expanded(flex: 2, child: Text('REWARD')),
                      Expanded(flex: 2, child: Text('ENDS')),
                      SizedBox(width: 130, child: Text('STATUS')),
                    ],
                  ),
                ),
              if (desktop) const Divider(height: 1),
              ...events.map(
                (event) => desktop
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Icon(
                                event.kind == 'playerCard'
                                    ? Icons.style_rounded
                                    : Icons.quiz_rounded,
                                color: _lime,
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('${event.rewardPoints} points'),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _productionDate(event.availableUntil),
                                style: const TextStyle(color: _muted),
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: _statusPicker(context, event),
                            ),
                          ],
                        ),
                      )
                    : ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          event.kind == 'playerCard'
                              ? Icons.style_rounded
                              : Icons.quiz_rounded,
                        ),
                        title: Text(event.title),
                        subtitle: Text(
                          '${event.rewardPoints} points · ${_productionDate(event.availableUntil)}',
                        ),
                        trailing: _statusPicker(context, event),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _statusPicker(BuildContext context, AbuChallenge event) {
    const statuses = [
      'draft',
      'scheduled',
      'open',
      'disabled',
      'ended',
      'archived',
    ];
    return DropdownButton<String>(
      isExpanded: true,
      value: statuses.contains(event.status) ? event.status : 'draft',
      items: const [
        DropdownMenuItem(value: 'draft', child: Text('Draft')),
        DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
        DropdownMenuItem(value: 'open', child: Text('Live')),
        DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
        DropdownMenuItem(value: 'ended', child: Text('Ended')),
        DropdownMenuItem(value: 'archived', child: Text('Archived')),
      ],
      onChanged: (status) async {
        if (status == null) return;
        try {
          await repository.setChallengeStatus(challenge: event, status: status);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(productionErrorMessage(error))),
            );
          }
        }
      },
    );
  }
}

final Set<int> _shownAnnouncementRevisions = <int>{};

Future<void> showLaunchAnnouncement(
  BuildContext context,
  LaunchAnnouncement announcement,
) async {
  if (!announcement.isActive ||
      announcement.title.isEmpty ||
      _shownAnnouncementRevisions.contains(announcement.revision)) {
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  final key = 'launch_popup_${announcement.revision}';
  final previous = preferences.getString(key);
  final today = DateTime.now();
  final todayKey = '${today.year}-${today.month}-${today.day}';
  if (announcement.frequency == 'once' && previous != null) return;
  if (announcement.frequency == 'daily' && previous == todayKey) return;
  _shownAnnouncementRevisions.add(announcement.revision);
  if (!context.mounted) {
    _shownAnnouncementRevisions.remove(announcement.revision);
    return;
  }
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        title: announcement.imageUrl.isEmpty
            ? null
            : SizedBox(
                height: 230,
                width: 560,
                child: _ProductionRemoteImage(
                  url: announcement.imageUrl,
                  fit: BoxFit.cover,
                  fallback: const ColoredBox(
                    color: _surface2,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_rounded, color: _muted),
                            SizedBox(height: 8),
                            Text(
                              'Image unavailable — use a direct HTTPS image URL.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
              onPressed: () async {
                final uri = externalHttpUri(announcement.linkUrl);
                Navigator.pop(context);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(announcement.buttonLabel),
            ),
        ],
      ),
    );
    // A once/daily campaign is only consumed after its dialog was actually
    // presented, so a rendering/context failure cannot silently hide it.
    if (announcement.frequency == 'once') {
      await preferences.setString(key, DateTime.now().toIso8601String());
    } else if (announcement.frequency == 'daily') {
      await preferences.setString(key, todayKey);
    }
  } catch (_) {
    _shownAnnouncementRevisions.remove(announcement.revision);
    rethrow;
  }
}
