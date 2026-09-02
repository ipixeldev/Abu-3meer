part of 'fan_league_app.dart';

class _ProductionChallenges extends StatelessWidget {
  const _ProductionChallenges({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      'Watch · answer · collect XP',
      'شاهد · أجب · اجمع XP',
    ),
    title: abuText(context, 'Challenges', 'التحديات'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<List<AbuChallenge>>(
          stream: repository.watchChallenges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 220);
            }
            if (snapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Challenges unavailable',
                  'التحديات غير متاحة',
                ),
                body: productionErrorMessage(snapshot.error!),
              );
            }
            final challenges = snapshot.data ?? const [];
            if (challenges.isEmpty) {
              return const _ProductionChallengeEmptyState();
            }
            final uid = repository.auth.currentUser?.uid;
            if (uid == null) {
              return _ProductionChallengeGrid(
                challenges: challenges,
                repository: repository,
              );
            }
            return StreamBuilder<AbuUserProfile?>(
              stream: repository.watchProfile(uid),
              builder: (context, profileSnapshot) => _ProductionChallengeGrid(
                challenges: challenges,
                repository: repository,
                isMember: profileSnapshot.data?.isYouTubeMember ?? false,
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _ProductionChallengeGrid extends StatelessWidget {
  const _ProductionChallengeGrid({
    required this.challenges,
    required this.repository,
    this.isMember = false,
  });

  final List<AbuChallenge> challenges;
  final ProductionRepository repository;
  final bool isMember;

  @override
  Widget build(BuildContext context) => _ResponsiveGrid(
    minWidth: 340,
    children: challenges
        .map(
          (challenge) => _ProductionChallengeCard(
            challenge: challenge,
            repository: repository,
            isMember: isMember,
          ),
        )
        .toList(),
  );
}

class _ProductionChallengeEmptyState extends StatelessWidget {
  const _ProductionChallengeEmptyState();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1100) {
        return _ProductionEmpty(
          icon: Icons.bolt_rounded,
          title: abuText(
            context,
            'The next challenge is being prepared',
            'يجري تحضير التحدي القادم',
          ),
          body: abuText(
            context,
            'Video questions and player-guess challenges published by Abu 3meer will appear here.',
            'ستظهر هنا أسئلة الفيديو وتحديات تخمين اللاعبين التي ينشرها أبو عمير.',
          ),
        );
      }
      final types = [
        (
          Icons.subtitles_rounded,
          abuText(context, 'SECRET PHRASE', 'العبارة السرية'),
          abuText(
            context,
            'Listen closely to the latest video',
            'استمع جيداً إلى أحدث فيديو',
          ),
        ),
        (
          Icons.person_search_rounded,
          abuText(context, 'GUESS THE PLAYER', 'احزر اللاعب'),
          abuText(
            context,
            'Watch the clues and answer the player name',
            'شاهد التلميحات وأجب باسم اللاعب',
          ),
        ),
        (
          Icons.quiz_rounded,
          abuText(context, 'MATCH QUIZ', 'اختبار المباراة'),
          abuText(
            context,
            'Timed football knowledge rounds',
            'جولات معلومات كروية محددة الوقت',
          ),
        ),
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
                          color: _productionPrimary(context)
                              .withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _productionPrimary(context)
                                .withValues(alpha: .24),
                          ),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: _productionPrimary(context),
                          size: 46,
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LiveDot(
                              text: abuText(context, 'NEXT DROP', 'القادم'),
                            ),
                            const SizedBox(height: 13),
                            Text(
                              abuText(
                                context,
                                'The next challenge is being prepared',
                                'يجري تحضير التحدي القادم',
                              ),
                              style: _display(29),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              abuText(
                                context,
                                'New playable events appear here as soon as Abu 3meer publishes them from Admin Studio.',
                                'تظهر الفعاليات الجديدة هنا فور نشرها من استوديو الإدارة.',
                              ),
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
                      Text(
                        abuText(context, 'CHALLENGE FORMATS', 'أنواع التحديات'),
                        style: _display(19),
                      ),
                      const SizedBox(height: 12),
                      for (final type in types)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                type.$1,
                                color: _productionPrimary(context),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      type.$2,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .8,
                                      ),
                                    ),
                                    Text(
                                      type.$3,
                                      style: TextStyle(
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
    this.isMember = false,
  });
  final AbuChallenge challenge;
  final ProductionRepository repository;
  final bool isMember;

  Future<void> answer(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _ChallengePlayDialog(challenge: challenge, repository: repository),
  );

  IconData get _icon => switch (challenge.canonicalKind) {
    'playerCard' => Icons.person_search_rounded,
    'multipleChoice' => Icons.fact_check_rounded,
    'trueFalse' => Icons.rule_rounded,
    'multiQuestion' => Icons.quiz_rounded,
    _ => Icons.subtitles_rounded,
  };

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (challenge.imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: _ProductionRemoteImage(
                  url: challenge.imageUrl,
                  fit: BoxFit.cover,
                  fallback: ColoredBox(
                    color: _surface2,
                    child: Icon(_icon, color: _muted, size: 52),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _productionPrimary(context)
                    .withValues(alpha: .12),
                child: Icon(_icon, color: _productionPrimary(context)),
              ),
              const Spacer(),
              _RewardChip(text: '+${challenge.rewardPoints} XP'),
            ],
          ),
          const SizedBox(height: 18),
          Text(challenge.title, style: _display(22)),
          const SizedBox(height: 7),
          Text(
            challenge.description,
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _ChallengeMetaChip(
                icon: Icons.schedule_rounded,
                label: abuText(
                  context,
                  'Until ${_productionDate(challenge.availableUntil)}',
                  'حتى ${_productionDate(challenge.availableUntil)}',
                ),
              ),
              _ChallengeMetaChip(
                icon: challenge.solved
                    ? Icons.check_circle_rounded
                    : Icons.replay_rounded,
                label: abuText(
                  context,
                  challenge.solved
                      ? 'SOLVED'
                      : '${math.max(0, challenge.maximumAttempts - challenge.attemptsUsed)} attempts left',
                  challenge.solved
                      ? 'تم الحل'
                      : '${math.max(0, challenge.maximumAttempts - challenge.attemptsUsed)} محاولة متبقية',
                ),
                color: challenge.solved ? _productionPrimary(context) : _muted,
              ),
              if (challenge.questions.length > 1)
                _ChallengeMetaChip(
                  icon: Icons.format_list_numbered_rounded,
                  label: abuText(
                    context,
                    '${challenge.questions.length} questions',
                    '${challenge.questions.length} أسئلة',
                  ),
                ),
              if (challenge.memberOnly)
                _ChallengeMetaChip(
                  icon: Icons.workspace_premium_rounded,
                  label: abuText(context, 'MEMBERS ONLY', 'للأعضاء فقط'),
                  color: _gold,
                ),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 18),
          if (challenge.videoUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                final uri = externalHttpUri(challenge.videoUrl);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: Icon(Icons.play_circle_rounded),
              label: Text(abuText(context, 'WATCH VIDEO', 'شاهد الفيديو')),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  challenge.isOpen &&
                      !challenge.solved &&
                      challenge.attemptsUsed < challenge.maximumAttempts &&
                      (!challenge.memberOnly || isMember)
                  ? () => answer(context)
                  : null,
              child: Text(
                !challenge.isOpen
                    ? abuText(context, 'CLOSED', 'مغلق')
                    : challenge.solved
                    ? abuText(context, 'SOLVED', 'تم الحل')
                    : challenge.memberOnly && !isMember
                    ? abuText(context, 'MEMBERS ONLY', 'للأعضاء فقط')
                    : challenge.attemptsUsed >= challenge.maximumAttempts
                    ? abuText(context, 'NO ATTEMPTS LEFT', 'لا محاولات متبقية')
                    : abuText(context, 'PLAY NOW', 'العب الآن'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChallengeMetaChip extends StatelessWidget {
  const _ChallengeMetaChip({
    required this.icon,
    required this.label,
    this.color = _muted,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ChallengePlayDialog extends StatefulWidget {
  const _ChallengePlayDialog({
    required this.challenge,
    required this.repository,
  });

  final AbuChallenge challenge;
  final ProductionRepository repository;

  @override
  State<_ChallengePlayDialog> createState() => _ChallengePlayDialogState();
}

class _ChallengePlayDialogState extends State<_ChallengePlayDialog> {
  final Map<String, String> answers = <String, String>{};
  final Map<String, TextEditingController> controllers =
      <String, TextEditingController>{};
  bool submitting = false;
  String? error;

  List<AbuChallengeQuestion> get questions {
    if (widget.challenge.questions.isNotEmpty) {
      return widget.challenge.questions;
    }
    return [
      AbuChallengeQuestion(
        id: 'main',
        prompt: widget.challenge.canonicalKind == 'playerCard'
            ? 'Who is the hidden player?'
            : 'What is the secret phrase?',
        type: 'text',
        options: const [],
      ),
    ];
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.repository.auth.currentUser == null) {
      await requireAuth(context, widget.repository);
      return;
    }
    for (final question in questions) {
      if ((answers[question.id] ?? '').trim().isEmpty) {
        setState(
          () => error = abuText(
            context,
            'Answer every question before submitting.',
            'أجب عن كل الأسئلة قبل الإرسال.',
          ),
        );
        return;
      }
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final result = await widget.repository.submitChallengeAnswers(
        challenge: widget.challenge,
        answers: answers,
      );
      if (!mounted) return;
      final correct = result['correct'] == true;
      final points = result['points'] ?? 0;
      final alreadyAwarded = result['alreadyAwarded'] == true;
      final remaining = result['remainingAttempts'];
      final messenger = ScaffoldMessenger.of(context);
      final feedback = correct
          ? abuText(
              context,
              alreadyAwarded
                  ? 'Already solved. You already received $points XP.'
                  : 'Perfect! +$points XP added.',
              alreadyAwarded
                  ? 'تم حل التحدي سابقاً. حصلت على $points XP من قبل.'
                  : 'إجابة رائعة! تمت إضافة $points XP.',
            )
          : abuText(
              context,
              remaining == null
                  ? 'Not correct yet. Review the video and try again.'
                  : 'Not correct yet. $remaining attempts remaining.',
              remaining == null
                  ? 'ليست صحيحة بعد. راجع الفيديو وحاول مجدداً.'
                  : 'ليست صحيحة بعد. بقيت $remaining محاولة.',
            );
      if (correct) await _showPredictionFireworks(context);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(feedback)));
    } catch (exception) {
      if (mounted) {
        setState(() {
          submitting = false;
          error = productionErrorMessage(exception);
        });
      }
    }
  }

  Widget _question(
    BuildContext context,
    AbuChallengeQuestion question,
    int index,
  ) {
    final prompt = question.prompt.trim().isEmpty
        ? abuText(context, 'Question ${index + 1}', 'السؤال ${index + 1}')
        : question.prompt;
    if (question.type == 'multipleChoice' || question.type == 'trueFalse') {
      final options = question.type == 'trueFalse'
          ? const <String>['true', 'false']
          : question.options;
      return Card(
        color: _surface2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1}. $prompt', style: _display(18)),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: submitting,
                child: RadioGroup<String>(
                  groupValue: answers[question.id],
                  onChanged: (value) =>
                      setState(() => answers[question.id] = value ?? ''),
                  child: Column(
                    children: [
                      for (final option in options)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          title: Text(
                            question.type == 'trueFalse'
                                ? option == 'true'
                                      ? abuText(context, 'True', 'صحيح')
                                      : abuText(context, 'False', 'خطأ')
                                : option,
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
    }
    final controller = controllers.putIfAbsent(
      question.id,
      () => TextEditingController(text: answers[question.id]),
    );
    return Card(
      color: _surface2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. $prompt', style: _display(18)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              enabled: !submitting,
              onChanged: (value) => answers[question.id] = value,
              decoration: InputDecoration(
                labelText: abuText(context, 'Your answer', 'إجابتك'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text(widget.challenge.title)),
        _RewardChip(text: '+${widget.challenge.rewardPoints} XP'),
      ],
    ),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              abuText(
                context,
                '${questions.length} questions · ${math.max(0, widget.challenge.maximumAttempts - widget.challenge.attemptsUsed)} attempts left',
                '${questions.length} أسئلة · ${math.max(0, widget.challenge.maximumAttempts - widget.challenge.attemptsUsed)} محاولة متبقية',
              ),
              style: TextStyle(color: _muted),
            ),
            if (widget.challenge.videoUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  final uri = externalHttpUri(widget.challenge.videoUrl);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: Icon(Icons.play_circle_rounded),
                label: Text(
                  abuText(context, 'WATCH SOURCE VIDEO', 'شاهد الفيديو'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (var index = 0; index < questions.length; index++) ...[
              _question(context, questions[index], index),
              if (index != questions.length - 1) const SizedBox(height: 10),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: _red)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: Text(abuText(context, 'CANCEL', 'إلغاء')),
      ),
      FilledButton.icon(
        onPressed: submitting ? null : submit,
        icon: submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.lock_rounded),
        label: Text(abuText(context, 'SUBMIT ANSWERS', 'إرسال الإجابات')),
      ),
    ],
  );
}

// Kept dormant while Community/Posts are outside the current product scope.
// ignore: unused_element
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
            title: abuText(context, 'Feed unavailable', 'المنشورات غير متاحة'),
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
  Widget build(BuildContext context) => _ProductionEmpty(
    icon: Icons.forum_outlined,
    title: abuText(
      context,
      'No community posts yet',
      'لا توجد منشورات في المجتمع بعد',
    ),
    body: abuText(
      context,
      'Official announcements and community discussions from Abu 3meer will appear here.',
      'ستظهر الإعلانات الرسمية ومنشورات مجتمع أبو عمير هنا.',
    ),
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
      final postFeed = Column(
        children: posts
            .map(
              (post) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _ProductionPostCard(
                  post: post,
                  repository: repository,
                  profile: profile,
                ),
              ),
            )
            .toList(),
      );

      if (constraints.maxWidth < 1100) {
        return postFeed;
      }

      final latest = posts.first;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: postFeed),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      abuText(context, 'COMMUNITY DESK', 'قسم المجتمع'),
                      style: _display(20),
                    ),
                    const SizedBox(height: 18),
                    _CommunityDeskMetric(
                      icon: Icons.article_outlined,
                      value: '${posts.length}',
                      label: abuText(
                        context,
                        'PUBLISHED STORIES',
                        'المنشورات المنشورة',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CommunityDeskMetric(
                      icon: Icons.schedule_rounded,
                      value: _productionDate(latest.publishedAt),
                      label: abuText(context, 'LATEST UPDATE', 'آخر تحديث'),
                    ),
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
        child: Icon(icon, color: _productionPrimary(context), size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: _display(17)),
            Text(
              label,
              style: TextStyle(
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

class _ProductionPostCard extends StatefulWidget {
  const _ProductionPostCard({
    required this.post,
    required this.repository,
    required this.profile,
  });
  final AbuPost post;
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionPostCard> createState() => _ProductionPostCardState();
}

class _ProductionPostCardState extends State<_ProductionPostCard> {
  bool _showHeartAnimation = false;
  bool _showAllComments = false;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _isSendingComment = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _onDoubleTap() async {
    setState(() => _showHeartAnimation = true);
    try {
      await widget.repository.togglePostLike(widget.post.id);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showHeartAnimation = false);
    });
  }

  Future<void> _sendComment() async {
    if (widget.repository.auth.currentUser == null) {
      await requireAuth(context, widget.repository);
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSendingComment = true);
    try {
      await widget.repository.addPostComment(
        postId: widget.post.id,
        userName: widget.profile.displayName,
        body: text,
      );
      _commentCtrl.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final repository = widget.repository;
    final profile = widget.profile;

    final image = post.imageUrl.isEmpty
        ? null
        : post.imageUrl.startsWith('assets/')
        ? Image.asset(post.imageUrl, fit: BoxFit.cover, width: double.infinity)
        : _ProductionRemoteImage(
            url: post.imageUrl,
            fit: BoxFit.cover,
            fallback: const ColoredBox(
              color: _surface2,
              child: Center(child: Icon(Icons.image_not_supported_rounded)),
            ),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Header (Avatar, Name, Verified, Date, Admin Delete) ───────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _productionPrimary(context)
                      .withValues(alpha: .2),
                  child: Text(
                    post.authorName.isNotEmpty
                        ? post.authorName[0].toUpperCase()
                        : 'A',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _productionPrimary(context),
                      fontSize: 15,
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
                              post.authorName,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: _productionPrimary(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _productionDate(post.publishedAt),
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (profile.isAdmin || profile.canManageContent)
                  IconButton(
                    tooltip: abuText(context, 'Delete post', 'حذف المنشور'),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: _red,
                      size: 20,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(
                            abuText(ctx, 'Delete Post', 'حذف المنشور'),
                          ),
                          content: Text(
                            abuText(
                              ctx,
                              'Are you sure you want to permanently delete this post?',
                              'هل أنت متأكد من حذف هذا المنشور نهائياً؟',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(abuText(ctx, 'CANCEL', 'إلغاء')),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _red,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(abuText(ctx, 'DELETE', 'حذف')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await repository.deletePost(post.id);
                      }
                    },
                  ),
              ],
            ),
          ),

          // ── 2. Post Media / Image (Double-tap to like) ───────────────────
          if (image != null)
            GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 500,
                      minHeight: 200,
                    ),
                    child: image,
                  ),
                  if (_showHeartAnimation)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.2),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.elasticOut,
                      builder: (context, val, child) => Transform.scale(
                        scale: val,
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 90,
                          color: Color(0xFFFF2B54),
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 20),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── 3. Post Content: Title, Body, Link ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      post.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ),
                if (post.body.isNotEmpty)
                  Text(
                    post.body,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),
                if (post.linkUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final uri = externalHttpUri(post.linkUrl);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _productionPrimary(context)
                            .withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _productionPrimary(context)
                              .withValues(alpha: .3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.link_rounded,
                            color: _productionPrimary(context),
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              post.linkUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _productionPrimary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.open_in_new_rounded,
                            color: _productionPrimary(context),
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── 4. Action Row (Heart with Count, Comment with Count) ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                // Heart Like button + live counter
                StreamBuilder<bool>(
                  stream: repository.watchPostLiked(post.id),
                  builder: (context, likedSnap) {
                    final isLiked = likedSnap.data ?? false;
                    return StreamBuilder<int>(
                      stream: repository.watchPostLikeCount(post.id),
                      builder: (context, countSnap) {
                        final count = countSnap.data ?? post.likeCount;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            try {
                              await repository.togglePostLike(post.id);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(productionErrorMessage(e)),
                                  ),
                                );
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isLiked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 22,
                                  color: isLiked
                                      ? const Color(0xFFFF2B54)
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$count',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: isLiked
                                        ? const Color(0xFFFF2B54)
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 16),
                // Comment button + live counter
                StreamBuilder<List<AbuComment>>(
                  stream: repository.watchPostComments(post.id),
                  builder: (context, commentSnap) {
                    final count = commentSnap.data?.length ?? 0;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _showAllComments = !_showAllComments);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // ── 5. INLINE COMMENTS (Directly inside post card!) ──────────────
          StreamBuilder<List<AbuComment>>(
            stream: repository.watchPostComments(post.id),
            builder: (context, snapshot) {
              final comments = snapshot.data ?? const <AbuComment>[];
              final displayed = _showAllComments
                  ? comments
                  : comments.take(3).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (comments.length > 3 && !_showAllComments)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: InkWell(
                        onTap: () => setState(() => _showAllComments = true),
                        child: Text(
                          abuText(
                            context,
                            'View all ${comments.length} comments',
                            'عرض جميع التعليقات (${comments.length})',
                          ),
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (displayed.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      itemCount: displayed.length,
                      itemBuilder: (context, i) {
                        final item = displayed[i];
                        final canModerate =
                            profile.isAdmin ||
                            profile.canModerate ||
                            (item.userId.isNotEmpty &&
                                item.userId == profile.uid);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor: _surface2,
                                child: Text(
                                  item.userName.isNotEmpty
                                      ? item.userName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${item.userName}  ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                      TextSpan(text: item.body),
                                    ],
                                  ),
                                ),
                              ),
                              if (canModerate) ...[
                                if ((profile.isAdmin || profile.canModerate) &&
                                    item.userId.isNotEmpty &&
                                    item.userId != profile.uid)
                                  InkWell(
                                    onTap: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(
                                            abuText(
                                              ctx,
                                              'Block Member',
                                              'حظر العضو',
                                            ),
                                          ),
                                          content: Text(
                                            abuText(
                                              ctx,
                                              'Block ${item.userName} from the platform?',
                                              'حظر ${item.userName} من المنصة؟',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(
                                                abuText(ctx, 'CANCEL', 'إلغاء'),
                                              ),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: _red,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(
                                                abuText(ctx, 'BLOCK', 'حظر'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await repository.setUserSuspension(
                                          uid: item.userId,
                                          suspended: true,
                                        );
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Icon(
                                        Icons.block_rounded,
                                        size: 14,
                                        color: _red,
                                      ),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () => repository.deletePostComment(
                                    postId: post.id,
                                    commentId: item.id,
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 15,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),

          // ── 6. INLINE COMMENT INPUT (Directly at bottom of post card) ───
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _productionPrimary(context)
                      .withValues(alpha: .2),
                  child: Text(
                    profile.displayName.isNotEmpty
                        ? profile.displayName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _productionPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C121E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _commentCtrl,
                      style: TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: abuText(
                          context,
                          'Add a comment...',
                          'أضف تعليقاً...',
                        ),
                        hintStyle: TextStyle(color: _muted, fontSize: 13),
                      ),
                      onSubmitted: (_) =>
                          _isSendingComment ? null : _sendComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: _isSendingComment
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _productionPrimary(context),
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: _productionPrimary(context),
                          size: 20,
                        ),
                  onPressed: _isSendingComment ? null : _sendComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
                  icon: Icon(Icons.arrow_back_rounded),
                  label: Text(abuText(context, 'ALL GAMES', 'كل الألعاب')),
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
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Featured Game Hero Card
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E2E18),
                      Color(0xFF13221C),
                      Color(0xFF0F151C),
                    ],
                  ),
                  border: Border.all(
                    color: _productionPrimary(context).withValues(alpha: .45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _productionPrimary(context).withValues(alpha: .2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _productionPrimary(context),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, color: _ink, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  abuText(
                                    context,
                                    'FEATURED GAME',
                                    'اللعبة المميزة',
                                  ),
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _gold.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: _gold.withValues(alpha: .35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.emoji_events_rounded,
                                  color: _gold,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  abuText(
                                    context,
                                    'BEST: 820 PTS',
                                    'أفضل نتيجة: ٨٢٠',
                                  ),
                                  style: TextStyle(
                                    color: _gold,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('EHZERHA ⚽', style: _display(32)),
                                const SizedBox(height: 4),
                                Text(
                                  abuText(
                                    context,
                                    'Guess the footballer from clues, clubs & career paths!',
                                    'خمّن اللاعب من خلال الأندية ومسيرته الكروية!',
                                  ),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => setState(() => showEhzerha = true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _productionPrimary(context),
                          foregroundColor: _ink,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              abuText(
                                context,
                                'PLAY EHZERHA NOW ➔',
                                'العب احزرها الآن ➔',
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: .8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2-Column Grid for more games
              Row(
                children: [
                  Expanded(
                    child: _MiniGameCard(
                      icon: Icons.groups_rounded,
                      color: _gold,
                      title: abuText(context, 'Fan Duels', 'مواجهات الجماهير'),
                      subtitle: abuText(
                        context,
                        '1v1 trivia battle against other supporters.',
                        'مواجهة معلومات ١ ضد ١ أمام مشجع آخر.',
                      ),
                      action: abuText(context, 'START DUEL ➔', 'ابدأ مواجهة ➔'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _FanDuelPage(
                            repository: widget.repository,
                            profile: widget.profile,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _MiniGameCard(
                      icon: Icons.quiz_rounded,
                      color: _blue,
                      title: abuText(context, 'Trivia Arena', 'ساحة المعلومات'),
                      subtitle: abuText(
                        context,
                        '10 rapid questions about European football.',
                        '١٠ أسئلة كروية سريعة عن الكرة الأوروبية.',
                      ),
                      action: abuText(
                        context,
                        'ENTER ARENA ➔',
                        'ادخل الساحة ➔',
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const Scaffold(body: _TriviaArenaPage()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _ProductionPlayerCardCollection(
                repository: widget.repository,
                profile: widget.profile,
              ),
            ],
          ),
  );
}

class _ProductionPlayerCardCollection extends StatelessWidget {
  const _ProductionPlayerCardCollection({
    required this.repository,
    required this.profile,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AbuPlayerCard>>(
    stream: repository.watchPlayerCards(profile.uid),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionSkeleton(height: 310);
      }
      if (snapshot.hasError) {
        return _ProductionEmpty(
          icon: Icons.cloud_off_rounded,
          title: abuText(
            context,
            'Player Cards unavailable',
            'بطاقات اللاعبين غير متاحة',
          ),
          body: productionErrorMessage(snapshot.error!),
        );
      }
      // The server hides disabled unclaimed cards but deliberately retains a
      // disabled card for a fan who already collected it.
      final cards = snapshot.data ?? const <AbuPlayerCard>[];
      if (cards.isEmpty) {
        return const SizedBox.shrink();
      }
      final unlocked = cards.where((card) => card.unlocked).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      abuText(
                        context,
                        'PLAYER CARD COLLECTION',
                        'مجموعة بطاقات اللاعبين',
                      ),
                      style: _display(25),
                    ),
                    Text(
                      abuText(
                        context,
                        '$unlocked of ${cards.length} unlocked',
                        'تم فتح $unlocked من ${cards.length}',
                      ),
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              _RewardChip(text: '$unlocked / ${cards.length}'),
            ],
          ),
          const SizedBox(height: 14),
          _ResponsiveGrid(
            minWidth: 250,
            children: cards
                .map((card) => _PlayerCollectionCard(card: card))
                .toList(),
          ),
        ],
      );
    },
  );
}

class _PlayerCollectionCard extends StatelessWidget {
  const _PlayerCollectionCard({required this.card});
  final AbuPlayerCard card;

  Color _rarityColor(BuildContext context) =>
      switch (card.rarity.toLowerCase()) {
        'legendary' => _gold,
        'epic' => const Color(0xFF9B72FF),
        'rare' => _blue,
        _ => _productionPrimary(context),
      };

  @override
  Widget build(BuildContext context) {
    final name = abuText(
      context,
      card.playerName,
      card.playerNameAr.isEmpty ? card.playerName : card.playerNameAr,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPlayerCardDetails(context, card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: .92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: _rarityColor(context).withValues(alpha: .1),
                    child: card.imageUrl.isEmpty
                        ? Icon(
                            card.unlocked
                                ? Icons.person_rounded
                                : Icons.lock_rounded,
                            size: 72,
                            color: _rarityColor(context),
                          )
                        : _ProductionRemoteImage(
                            url: card.imageUrl,
                            fit: BoxFit.cover,
                            fallback: Icon(
                              card.unlocked
                                  ? Icons.person_rounded
                                  : Icons.lock_rounded,
                              size: 72,
                              color: _rarityColor(context),
                            ),
                          ),
                  ),
                  if (!card.unlocked)
                    ColoredBox(
                      color: _ink.withValues(alpha: .72),
                      child: const Center(
                        child: Icon(
                          Icons.lock_rounded,
                          size: 46,
                          color: _muted,
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    top: 12,
                    start: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _ink.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        card.unlocked ? '${card.rating}' : '?',
                        style: _display(18, color: _rarityColor(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.unlocked
                        ? name
                        : abuText(context, 'MYSTERY PLAYER', 'لاعب غامض'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _display(19),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    card.unlocked
                        ? '${card.teamName} · ${card.position}'
                        : card.sourceChallengeId.trim().isEmpty
                        ? abuText(
                            context,
                            'Awaiting an unlock challenge',
                            'في انتظار ربط تحدٍ لفتحها',
                          )
                        : abuText(
                            context,
                            'Complete the linked challenge to unlock',
                            'أكمل التحدي المرتبط لفتح البطاقة',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    card.rarity.toUpperCase(),
                    style: TextStyle(
                      color: _rarityColor(context),
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
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
}

Future<void> _showPlayerCardDetails(
  BuildContext context,
  AbuPlayerCard card,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final name = abuText(
      context,
      card.playerName,
      card.playerNameAr.isEmpty ? card.playerName : card.playerNameAr,
    );
    final description = abuText(
      context,
      card.description,
      card.descriptionAr.isEmpty ? card.description : card.descriptionAr,
    );
    return AlertDialog(
      title: Text(
        card.unlocked
            ? name
            : abuText(context, 'Locked Player Card', 'بطاقة مقفلة'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: card.unlocked && card.imageUrl.isNotEmpty
                      ? _ProductionRemoteImage(
                          url: card.imageUrl,
                          fit: BoxFit.cover,
                          fallback: const ColoredBox(
                            color: _surface2,
                            child: Icon(Icons.style_rounded, size: 68),
                          ),
                        )
                      : const ColoredBox(
                          color: _surface2,
                          child: Icon(
                            Icons.lock_rounded,
                            size: 68,
                            color: _muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              if (card.unlocked) ...[
                Text(
                  '${card.teamName} · ${card.position} · ${card.rating}',
                  style: TextStyle(
                    color: _productionPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                ],
                if (card.stats.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: card.stats.entries
                        .map(
                          (entry) => _ChallengeMetaChip(
                            icon: Icons.analytics_rounded,
                            label: '${entry.key.toUpperCase()} ${entry.value}',
                            color: _productionPrimary(context),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ] else
                Text(
                  abuText(
                    context,
                    'Complete its Player Card challenge to reveal the player, artwork and ratings.',
                    'أكمل تحدي بطاقة اللاعب لكشف اللاعب والصورة والتقييمات.',
                  ),
                  style: TextStyle(color: _muted, height: 1.5),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(abuText(context, 'DONE', 'تم')),
        ),
      ],
    );
  },
);

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
    if (widget.repository.auth.currentUser == null) {
      await requireAuth(context, widget.repository);
      return;
    }
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
    if (widget.repository.auth.currentUser == null) {
      await requireAuth(context, widget.repository);
      return;
    }
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
    appBar: AppBar(
      title: Text(abuText(context, 'FAN DUELS', 'مواجهات الجماهير')),
    ),
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
                        Icon(
                          Icons.sports_esports_rounded,
                          color: _productionPrimary(context),
                          size: 58,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          abuText(
                            context,
                            'One room. Two fans.',
                            'غرفة واحدة. مشجعان.',
                          ),
                          textAlign: TextAlign.center,
                          style: _display(31),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          abuText(
                            context,
                            'Create a room and share its six-character code, or join a friend. The first valid server-timed tap after the countdown wins.',
                            'أنشئ غرفة وشارك رمزها المكوّن من ستة أحرف، أو انضم إلى صديق. يفوز أول ضغط صحيح بعد انتهاء العد التنازلي.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: busy ? null : create,
                          icon: Icon(Icons.add_rounded),
                          label: Text(
                            abuText(
                              context,
                              'CREATE DUEL ROOM',
                              'إنشاء غرفة مواجهة',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Text(
                            abuText(context, 'OR', 'أو'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        TextField(
                          controller: code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 6,
                          decoration: InputDecoration(
                            labelText: abuText(
                              context,
                              'Room code',
                              'رمز الغرفة',
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : join,
                          child: Text(
                            abuText(context, 'JOIN FRIEND', 'الانضمام لصديق'),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _red),
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
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ProductionEmpty(
                  icon: Icons.cloud_off_rounded,
                  title: abuText(
                    context,
                    'Duel unavailable',
                    'المواجهة غير متاحة',
                  ),
                  body: productionErrorMessage(snapshot.error!),
                );
              }
              if (!snapshot.hasData || snapshot.data == null) {
                return _ProductionEmpty(
                  icon: Icons.sports_esports_rounded,
                  title: abuText(
                    context,
                    'Room not found',
                    'الغرفة غير موجودة',
                  ),
                  body: abuText(
                    context,
                    'Return to Game Center and create or join another room.',
                    'ارجع إلى مركز الألعاب وأنشئ غرفة أخرى أو انضم إليها.',
                  ),
                );
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
            Text(abuText(context, 'SHARE THIS ROOM CODE', 'شارك رمز الغرفة')),
            SelectableText(
              room.code,
              style: _display(
                58,
                color: _productionPrimary(context),
                spacing: 4,
              ),
            ),
            Text(
              abuText(
                context,
                'Waiting for the second fan…',
                'بانتظار المشجع الثاني…',
              ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Duel updates unavailable',
              'تحديثات المواجهة غير متاحة',
            ),
            body: productionErrorMessage(snapshot.error!),
          );
        }
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
                    abuText(
                      context,
                      'ROOM ${room.code}',
                      'الغرفة ${room.code}',
                    ),
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 36),
                  if (winnerUid.isNotEmpty) ...[
                    Icon(Icons.emoji_events_rounded, color: _gold, size: 72),
                    const SizedBox(height: 12),
                    Text(
                      abuText(
                        context,
                        '$winnerName WINS',
                        'الفائز: $winnerName',
                      ),
                      style: _display(43, color: _gold),
                    ),
                  ] else ...[
                    Text(
                      started
                          ? abuText(context, 'TAP!', 'اضغط!')
                          : '${math.max(1, remaining.inSeconds + 1)}',
                      style: _display(
                        72,
                        color: started ? _productionPrimary(context) : _gold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 280,
                      height: 120,
                      child: FilledButton(
                        onPressed: started && !mine && !tapping ? tap : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: started
                              ? _productionPrimary(context)
                              : _surface2,
                          foregroundColor: _ink,
                        ),
                        child: Text(
                          mine
                              ? abuText(
                                  context,
                                  'TAP REGISTERED',
                                  'تم تسجيل الضغط',
                                )
                              : abuText(context, 'STRIKE', 'اضغط'),
                        ),
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

class _MiniGameCard extends StatelessWidget {
  const _MiniGameCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: _muted, fontSize: 11, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Text(
                  action,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: .6,
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

class _InteractiveFanCard extends StatefulWidget {
  const _InteractiveFanCard({
    required this.profile,
    this.temporaryImage,
    this.onEdit,
    this.monthlyRank,
    this.seasonRank,
    this.accuracy,
    this.repository,
  });
  final AbuUserProfile profile;
  final Uint8List? temporaryImage;
  final VoidCallback? onEdit;
  final int? monthlyRank;
  final int? seasonRank;
  final double? accuracy;
  final ProductionRepository? repository;

  @override
  State<_InteractiveFanCard> createState() => _InteractiveFanCardState();
}

// Kept dormant for a future Fan War release.
// ignore: unused_element
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
        if (snapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Fan War unavailable',
              'حرب الجماهير غير متاحة',
            ),
            body: productionErrorMessage(snapshot.error!),
          );
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
        desktop: constraints.maxWidth >= 1100,
      );
      if (constraints.maxWidth < 1100) {
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
                  label: abuText(
                    context,
                    'ACTIVE SUPPORTERS',
                    'المشجعون النشطون',
                  ),
                  color: _productionPrimary(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.stars_rounded,
                  value: '${barcaPoints + madridPoints}',
                  label: abuText(context, 'VERIFIED POINTS', 'النقاط الموثقة'),
                  color: _gold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.flag_rounded,
                  value: leader == 'LEVEL'
                      ? abuText(context, 'LEVEL', 'تعادل')
                      : leader == 'BARCELONA'
                      ? abuText(context, 'BARCELONA', 'برشلونة')
                      : abuText(context, 'REAL MADRID', 'ريال مدريد'),
                  label: margin == 0
                      ? abuText(context, 'CURRENTLY TIED', 'تعادل حالياً')
                      : abuText(
                          context,
                          '$margin POINT LEAD',
                          'متقدم بفارق $margin نقطة',
                        ),
                  color: leader == 'BARCELONA' ? _blue : _gold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FanWarKpi(
                  icon: Icons.sports_soccer_rounded,
                  value: '$barcaFans / $madridFans',
                  label: abuText(
                    context,
                    'BARÇA / MADRID FANS',
                    'مشجعو برشلونة / مدريد',
                  ),
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
                  style: TextStyle(
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
                _LiveDot(
                  text: abuText(context, 'LIVE BATTLE', 'المواجهة المباشرة'),
                ),
                Text(
                  abuText(context, 'ALL TIME', 'كل الوقت'),
                  style: _display(13, color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const _ProductionTeamBadge(team: 'Barcelona', source: ''),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    abuText(context, 'BARCELONA', 'برشلونة'),
                    style: _display(22),
                  ),
                ),
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
                  abuText(context, '$barcaPoints PTS', '$barcaPoints نقطة'),
                  style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  abuText(context, '$madridPoints PTS', '$madridPoints نقطة'),
                  style: TextStyle(color: _gold, fontWeight: FontWeight.w900),
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
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: _ProductionEmpty(
                icon: Icons.groups_rounded,
                title: abuText(
                  context,
                  'No contributors yet',
                  'لا يوجد مساهمون بعد',
                ),
                body: abuText(
                  context,
                  'Verified fan activity will populate this table.',
                  'سيظهر نشاط المشجعين الموثق في هذا الجدول.',
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          abuText(
                            context,
                            'TOP CONTRIBUTORS',
                            'أبرز المساهمين',
                          ),
                          style: _display(20),
                        ),
                      ),
                      Text(
                        abuText(
                          context,
                          'LIVE VERIFIED TOTALS',
                          'إجماليات موثقة مباشرة',
                        ),
                        style: TextStyle(
                          color: _productionPrimary(context),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(abuText(context, 'RANK', 'الترتيب')),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(abuText(context, 'SUPPORTER', 'المشجع')),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(abuText(context, 'CLUB', 'النادي')),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            abuText(context, 'POINTS', 'النقاط'),
                            textAlign: TextAlign.end,
                          ),
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
                        style: _display(19, color: _productionPrimary(context)),
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
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.supportedTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _muted),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${entry.seasonPoints}',
                            textAlign: TextAlign.end,
                            style: _display(
                              17,
                              color: _productionPrimary(context),
                            ),
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

// Kept dormant until the achievements surface returns to navigation.
// ignore: unused_element
class _ProductionAchievements extends StatelessWidget {
  const _ProductionAchievements({
    required this.repository,
    required this.profile,
  });
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      '${profile.totalPoints} verified points',
      '${profile.totalPoints} نقطة موثقة',
    ),
    title: abuText(context, 'Achievements & Levels', 'الإنجازات والمستويات'),
    child: StreamBuilder<List<AbuLevel>>(
      stream: repository.watchLevels(),
      builder: (context, levelSnapshot) {
        if (levelSnapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 350);
        }
        if (levelSnapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Levels unavailable',
              'المستويات غير متاحة',
            ),
            body: productionErrorMessage(levelSnapshot.error!),
          );
        }
        return StreamBuilder<List<AbuAchievementProgress>>(
          stream: repository.watchAchievements(profile.uid),
          builder: (context, achievementSnapshot) {
            if (achievementSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 420);
            }
            if (achievementSnapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.cloud_off_rounded,
                title: abuText(
                  context,
                  'Achievements unavailable',
                  'الإنجازات غير متاحة',
                ),
                body: productionErrorMessage(achievementSnapshot.error!),
              );
            }
            final levels =
                (levelSnapshot.data ?? const <AbuLevel>[])
                    .where((level) => level.enabled)
                    .toList()
                  ..sort((a, b) => a.minimumPoints.compareTo(b.minimumPoints));
            final progress =
                (achievementSnapshot.data ?? const <AbuAchievementProgress>[])
                    .where((item) => item.achievement.enabled)
                    .toList()
                  ..sort(
                    (a, b) => a.achievement.sortOrder.compareTo(
                      b.achievement.sortOrder,
                    ),
                  );
            if (levels.isEmpty && progress.isEmpty) {
              return _ProductionEmpty(
                icon: Icons.emoji_events_outlined,
                title: abuText(
                  context,
                  'Achievements are being prepared',
                  'يجري تحضير الإنجازات',
                ),
                body: abuText(
                  context,
                  'New levels and achievement goals will appear when the admin publishes them.',
                  'ستظهر المستويات وأهداف الإنجازات عند نشرها من المشرف.',
                ),
              );
            }
            return _AchievementLevelContent(
              repository: repository,
              profile: profile,
              levels: levels,
              progress: progress,
            );
          },
        );
      },
    ),
  );
}

class _AchievementLevelContent extends StatelessWidget {
  const _AchievementLevelContent({
    required this.repository,
    required this.profile,
    required this.levels,
    required this.progress,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;
  final List<AbuLevel> levels;
  final List<AbuAchievementProgress> progress;

  @override
  Widget build(BuildContext context) {
    AbuLevel? current;
    AbuLevel? next;
    for (final level in levels) {
      if (profile.totalPoints >= level.minimumPoints) {
        current = level;
      } else {
        next ??= level;
      }
    }
    final currentFloor = current?.minimumPoints ?? 0;
    final nextFloor = next?.minimumPoints;
    final levelProgress = nextFloor == null
        ? 1.0
        : ((profile.totalPoints - currentFloor) /
                  math.max(1, nextFloor - currentFloor))
              .clamp(0.0, 1.0);
    final unlocked = progress.where((item) => item.unlocked).length;
    final levelAccent = _definitionColor(
      context,
      current?.color,
      _productionPrimary(context),
    );
    final levelIcon = _definitionIcon(current?.iconName ?? 'military_tech');
    final levelHero = Card(
      color: levelAccent.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: levelAccent.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(levelIcon, color: levelAccent, size: 31),
                ),
                const Spacer(),
                _LiveDot(
                  text: abuText(
                    context,
                    '$unlocked / ${progress.length} UNLOCKED',
                    '$unlocked / ${progress.length} مفتوح',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              abuText(context, 'CURRENT LEVEL', 'المستوى الحالي'),
              style: TextStyle(
                color: levelAccent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              current == null
                  ? abuText(context, 'ROOKIE', 'مبتدئ')
                  : abuText(
                      context,
                      current.name,
                      current.nameAr.isEmpty ? current.name : current.nameAr,
                    ),
              style: _display(35),
            ),
            const SizedBox(height: 8),
            Text(
              next == null
                  ? abuText(
                      context,
                      'Highest published level reached',
                      'وصلت إلى أعلى مستوى منشور',
                    )
                  : abuText(
                      context,
                      '${math.max(0, next.minimumPoints - profile.totalPoints)} points to ${next.name}',
                      '${math.max(0, next.minimumPoints - profile.totalPoints)} نقطة للوصول إلى ${next.nameAr.isEmpty ? next.name : next.nameAr}',
                    ),
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: levelProgress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(99),
              color: levelAccent,
              backgroundColor: _line,
            ),
            if (current != null && current.perks.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                abuText(context, 'LEVEL PERKS', 'مزايا المستوى'),
                style: _display(15),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < current.perks.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Icon(Icons.check_rounded, color: levelAccent, size: 17),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          abuText(
                            context,
                            current.perks[index],
                            index < current.perksAr.length
                                ? current.perksAr[index]
                                : current.perks[index],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    final roadmap = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              abuText(context, 'LEVEL ROADMAP', 'مسار المستويات'),
              style: _display(19),
            ),
            const SizedBox(height: 12),
            if (levels.isEmpty)
              Text(
                abuText(
                  context,
                  'No levels published yet.',
                  'لا توجد مستويات منشورة بعد.',
                ),
                style: TextStyle(color: _muted),
              )
            else
              for (final level in levels)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: profile.totalPoints >= level.minimumPoints
                        ? _productionPrimary(context).withValues(alpha: .15)
                        : _surface2,
                    child: Icon(
                      profile.totalPoints >= level.minimumPoints
                          ? Icons.check_rounded
                          : Icons.lock_outline_rounded,
                      color: profile.totalPoints >= level.minimumPoints
                          ? _productionPrimary(context)
                          : _muted,
                    ),
                  ),
                  title: Text(
                    abuText(
                      context,
                      level.name,
                      level.nameAr.isEmpty ? level.name : level.nameAr,
                    ),
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: Text(
                    '${level.minimumPoints} PTS',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 1100
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: levelHero),
                    const SizedBox(width: 16),
                    Expanded(flex: 5, child: roadmap),
                  ],
                )
              : Column(
                  children: [levelHero, const SizedBox(height: 14), roadmap],
                ),
        ),
        const SizedBox(height: 26),
        Text(
          abuText(context, 'ACHIEVEMENT CABINET', 'خزانة الإنجازات'),
          style: _display(24),
        ),
        const SizedBox(height: 12),
        if (progress.isEmpty)
          _ProductionEmpty(
            icon: Icons.emoji_events_outlined,
            title: abuText(
              context,
              'No achievements yet',
              'لا توجد إنجازات بعد',
            ),
            body: abuText(
              context,
              'Admin-published goals will appear here.',
              'ستظهر هنا الأهداف التي ينشرها المشرف.',
            ),
          )
        else
          _ResponsiveGrid(
            minWidth: 290,
            children: progress
                .map(
                  (item) => _AchievementProgressCard(
                    key: ValueKey(item.achievementId),
                    progress: item,
                    repository: repository,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

IconData _definitionIcon(String name) => switch (name.trim().toLowerCase()) {
  'fire' || 'local_fire_department' => Icons.local_fire_department_rounded,
  'target' || 'gps_fixed' => Icons.gps_fixed_rounded,
  'crown' || 'workspace_premium' => Icons.workspace_premium_rounded,
  'shield' => Icons.shield_rounded,
  'star' => Icons.star_rounded,
  'military_tech' => Icons.military_tech_rounded,
  'bolt' => Icons.bolt_rounded,
  'sports_soccer' => Icons.sports_soccer_rounded,
  'style' => Icons.style_rounded,
  _ => Icons.emoji_events_rounded,
};

Color _definitionColor(BuildContext context, String? raw, Color fallback) {
  final normalized = (raw ?? '').replaceAll('#', '').trim();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return fallback;
  // Existing records can still carry the original stadium-lime hex. Preserve
  // it in dark mode, while mapping it to the daylight royal-blue accent.
  if (!_isDarkTheme(context) && normalized.toUpperCase() == 'C8FF38') {
    return _lightPrimary;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

class _AchievementProgressCard extends StatefulWidget {
  const _AchievementProgressCard({
    super.key,
    required this.progress,
    required this.repository,
  });
  final AbuAchievementProgress progress;
  final ProductionRepository repository;

  @override
  State<_AchievementProgressCard> createState() =>
      _AchievementProgressCardState();
}

class _AchievementProgressCardState extends State<_AchievementProgressCard> {
  bool claiming = false;
  bool claimedThisSession = false;

  IconData get _icon => _definitionIcon(widget.progress.achievement.iconName);

  Future<void> _claim(BuildContext context) async {
    setState(() => claiming = true);
    final achievement = widget.progress.achievement;
    try {
      final result = await widget.repository.claimAchievement(achievement.id);
      if (!mounted || !context.mounted) return;
      final awarded = result['awarded'] == true;
      final awardedPoints = (result['points'] as num?)?.toInt() ?? 0;
      final successMessage = awarded && awardedPoints > 0
          ? abuText(
              context,
              'Claim confirmed. $awardedPoints points were added.',
              'تم تأكيد الاستلام وإضافة $awardedPoints نقطة.',
            )
          : abuText(
              context,
              'Achievement claim confirmed.',
              'تم تأكيد استلام الإنجاز.',
            );
      setState(() {
        claiming = false;
        claimedThisSession = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted || !context.mounted) return;
      setState(() => claiming = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final achievement = progress.achievement;
    final eligible = progress.current >= progress.target || progress.unlocked;
    final claimed = progress.unlockedAt != null || claimedThisSession;
    final secret = achievement.isSecret && !eligible;
    final title = secret
        ? abuText(context, 'SECRET ACHIEVEMENT', 'إنجاز سري')
        : abuText(
            context,
            achievement.title,
            achievement.titleAr.isEmpty
                ? achievement.title
                : achievement.titleAr,
          );
    final value = progress.target <= 0
        ? (progress.unlocked ? 1.0 : 0.0)
        : (progress.current / progress.target).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () =>
                  _showAchievementDetails(context, progress, claimed: claimed),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: value,
                              strokeWidth: 5,
                              color: claimed
                                  ? _gold
                                  : eligible
                                  ? _productionPrimary(context)
                                  : _muted,
                              backgroundColor: _line,
                            ),
                            Icon(
                              secret ? Icons.help_rounded : _icon,
                              color: claimed
                                  ? _gold
                                  : eligible
                                  ? _productionPrimary(context)
                                  : _muted,
                              size: 25,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (achievement.rewardPoints > 0)
                        _RewardChip(
                          text: claimed
                              ? abuText(context, 'CLAIMED', 'تم الاستلام')
                              : abuText(
                                  context,
                                  'REWARD ${achievement.rewardPoints} PTS',
                                  'مكافأة ${achievement.rewardPoints} نقطة',
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _display(21),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    claimed
                        ? abuText(context, 'CLAIMED', 'تم الاستلام')
                        : eligible
                        ? abuText(context, 'READY TO CLAIM', 'جاهز للاستلام')
                        : secret
                        ? abuText(
                            context,
                            'Keep playing to reveal this goal.',
                            'واصل اللعب لكشف هذا الهدف.',
                          )
                        : '${progress.current} / ${progress.target}',
                    style: TextStyle(
                      color: claimed || eligible
                          ? _productionPrimary(context)
                          : _muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (eligible && !claimed) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: claiming ? null : () => _claim(context),
                icon: claiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.redeem_rounded),
                label: Text(
                  abuText(context, 'CLAIM ACHIEVEMENT', 'استلام الإنجاز'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showAchievementDetails(
  BuildContext context,
  AbuAchievementProgress progress, {
  required bool claimed,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final achievement = progress.achievement;
    final secret = achievement.isSecret && !progress.unlocked;
    return AlertDialog(
      title: Text(
        secret
            ? abuText(context, 'Secret achievement', 'إنجاز سري')
            : abuText(
                context,
                achievement.title,
                achievement.titleAr.isEmpty
                    ? achievement.title
                    : achievement.titleAr,
              ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              secret
                  ? abuText(
                      context,
                      'The requirement stays hidden until you unlock it.',
                      'يبقى الشرط مخفياً حتى تفتح الإنجاز.',
                    )
                  : abuText(
                      context,
                      achievement.description,
                      achievement.descriptionAr.isEmpty
                          ? achievement.description
                          : achievement.descriptionAr,
                    ),
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress.target <= 0
                  ? (progress.unlocked ? 1 : 0)
                  : (progress.current / progress.target).clamp(0.0, 1.0),
              minHeight: 9,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 8),
            Text(
              claimed
                  ? abuText(context, 'Claimed', 'تم الاستلام')
                  : progress.unlocked
                  ? abuText(context, 'Ready to claim', 'جاهز للاستلام')
                  : '${progress.current} / ${progress.target}',
            ),
            if (achievement.rewardPoints > 0) ...[
              const SizedBox(height: 14),
              Text(
                abuText(
                  context,
                  'Reward: ${achievement.rewardPoints} points',
                  'المكافأة: ${achievement.rewardPoints} نقطة',
                ),
                style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(abuText(context, 'DONE', 'تم')),
        ),
      ],
    );
  },
);

class _ProductionRewards extends StatefulWidget {
  const _ProductionRewards({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<_ProductionRewards> createState() => _ProductionRewardsState();
}

class _ProductionRewardsState extends State<_ProductionRewards> {
  String category = 'all';
  bool redeeming = false;

  @override
  Widget build(BuildContext context) => _PageFrame(
    kicker: abuText(
      context,
      '${widget.profile.loyaltyPoints} loyalty points available',
      '${widget.profile.loyaltyPoints} نقطة ولاء متاحة',
    ),
    title: abuText(context, 'Loyalty Store', 'متجر الولاء'),
    child: StreamBuilder<List<AbuLoyaltyReward>>(
      stream: widget.repository.watchRewards(),
      builder: (context, rewardSnapshot) {
        if (rewardSnapshot.connectionState == ConnectionState.waiting) {
          return const _ProductionSkeleton(height: 390);
        }
        if (rewardSnapshot.hasError) {
          return _ProductionEmpty(
            icon: Icons.cloud_off_rounded,
            title: abuText(
              context,
              'Rewards unavailable',
              'المكافآت غير متاحة',
            ),
            body: productionErrorMessage(rewardSnapshot.error!),
          );
        }
        return StreamBuilder<List<AbuRewardRedemption>>(
          stream: widget.repository.watchRedemptions(widget.profile.uid),
          builder: (context, redemptionSnapshot) {
            if (redemptionSnapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionSkeleton(height: 390);
            }
            if (redemptionSnapshot.hasError) {
              return _ProductionEmpty(
                icon: Icons.history_rounded,
                title: abuText(
                  context,
                  'Redemption history unavailable',
                  'سجل الاستبدال غير متاح',
                ),
                body: productionErrorMessage(redemptionSnapshot.error!),
              );
            }
            return _buildStore(
              context,
              rewardSnapshot.data ?? const <AbuLoyaltyReward>[],
              redemptionSnapshot.data ?? const <AbuRewardRedemption>[],
            );
          },
        );
      },
    ),
  );

  Widget _buildStore(
    BuildContext context,
    List<AbuLoyaltyReward> rewards,
    List<AbuRewardRedemption> redemptions,
  ) {
    final categories = <String>{
      'all',
      ...rewards.map((reward) => reward.category),
    };
    if (!categories.contains(category)) category = 'all';
    final visible = category == 'all'
        ? rewards
        : rewards.where((reward) => reward.category == category).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: _gold.withValues(alpha: .07),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.stars_rounded, color: _gold, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          abuText(context, 'LOYALTY WALLET', 'محفظة الولاء'),
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.profile.loyaltyPoints}',
                          style: _display(32, color: _gold),
                        ),
                      ],
                    ),
                  ),
                  if (constraints.maxWidth >= 600)
                    Text(
                      abuText(
                        context,
                        'Earn through verified fan activity',
                        'اكسب من نشاط المشجع الموثق',
                      ),
                      style: TextStyle(color: _muted),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories
                .map(
                  (item) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      selected: category == item,
                      onSelected: (_) => setState(() => category = item),
                      label: Text(
                        item == 'all'
                            ? abuText(context, 'ALL', 'الكل')
                            : item.toUpperCase(),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          _ProductionEmpty(
            icon: Icons.card_giftcard_rounded,
            title: abuText(
              context,
              'No rewards in this category',
              'لا توجد مكافآت في هذه الفئة',
            ),
            body: abuText(
              context,
              'Check again after the next catalogue update.',
              'تحقق مجدداً بعد تحديث المتجر القادم.',
            ),
          )
        else
          _ResponsiveGrid(
            minWidth: 300,
            children: visible
                .map(
                  (reward) => _LoyaltyRewardCard(
                    reward: reward,
                    balance: widget.profile.loyaltyPoints,
                    isMember: widget.profile.isYouTubeMember,
                    busy: redeeming,
                    onRedeem: () => _redeem(context, reward),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 28),
        Text(
          abuText(context, 'REDEMPTION HISTORY', 'سجل الاستبدال'),
          style: _display(23),
        ),
        const SizedBox(height: 12),
        if (redemptions.isEmpty)
          _ProductionEmpty(
            icon: Icons.receipt_long_rounded,
            title: abuText(
              context,
              'No redemptions yet',
              'لا توجد عمليات استبدال بعد',
            ),
            body: abuText(
              context,
              'Rewards you redeem will appear here with fulfilment status.',
              'ستظهر المكافآت المستبدلة هنا مع حالة التنفيذ.',
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < redemptions.length; index++) ...[
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: _surface2,
                      child: Icon(Icons.redeem_rounded, color: _gold),
                    ),
                    title: Text(redemptions[index].rewardTitle),
                    subtitle: Text(
                      '${_productionDate(redemptions[index].createdAt)} · ${redemptions[index].cost} PTS',
                    ),
                    trailing: _ChallengeMetaChip(
                      icon: redemptions[index].status == 'fulfilled'
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      label: _redemptionStatus(
                        context,
                        redemptions[index].status,
                      ),
                      color: redemptions[index].status == 'fulfilled'
                          ? _productionPrimary(context)
                          : _gold,
                    ),
                  ),
                  if (index != redemptions.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _redeem(BuildContext context, AbuLoyaltyReward reward) async {
    final title = abuText(
      context,
      reward.title,
      reward.titleAr.isEmpty ? reward.title : reward.titleAr,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(abuText(context, 'Redeem $title?', 'استبدال $title؟')),
        content: Text(
          abuText(
            context,
            '${reward.cost} loyalty points will be deducted after the secure server confirms availability.',
            'سيتم خصم ${reward.cost} نقطة ولاء بعد تأكيد الخادم الآمن للتوفر.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(abuText(context, 'CONFIRM', 'تأكيد')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !context.mounted) return;
    setState(() => redeeming = true);
    try {
      await widget.repository.redeemReward(reward.id);
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abuText(
                context,
                'Redemption submitted. Track it in your history.',
                'تم إرسال طلب الاستبدال. تابعه في السجل.',
              ),
            ),
          ),
        );
      }
    } catch (exception) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(productionErrorMessage(exception))),
        );
      }
    } finally {
      if (mounted) setState(() => redeeming = false);
    }
  }
}

String _redemptionStatus(BuildContext context, String status) =>
    switch (status) {
      'fulfilled' => abuText(context, 'FULFILLED', 'تم التنفيذ'),
      'contacted' => abuText(context, 'CONTACTED', 'تم التواصل'),
      'cancelled' => abuText(context, 'CANCELLED', 'ملغي'),
      _ => abuText(context, 'PENDING', 'قيد المراجعة'),
    };

Color _redemptionStatusColor(BuildContext context, String status) =>
    switch (status) {
      'fulfilled' => _productionPrimary(context),
      'contacted' => _blue,
      'cancelled' => _red,
      _ => _muted,
    };

class _LoyaltyRewardCard extends StatelessWidget {
  const _LoyaltyRewardCard({
    required this.reward,
    required this.balance,
    required this.isMember,
    required this.busy,
    required this.onRedeem,
  });

  final AbuLoyaltyReward reward;
  final int balance;
  final bool isMember;
  final bool busy;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final title = abuText(
      context,
      reward.title,
      reward.titleAr.isEmpty ? reward.title : reward.titleAr,
    );
    final description = abuText(
      context,
      reward.description,
      reward.descriptionAr.isEmpty ? reward.description : reward.descriptionAr,
    );
    final available = reward.unlimitedStock || reward.stock > 0;
    final canRedeem =
        !busy &&
        available &&
        balance >= reward.cost &&
        (!reward.memberOnly || isMember);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 8,
            child: reward.imageUrl.isEmpty
                ? ColoredBox(
                    color: _gold.withValues(alpha: .08),
                    child: Icon(
                      Icons.card_giftcard_rounded,
                      color: _gold,
                      size: 58,
                    ),
                  )
                : _ProductionRemoteImage(
                    url: reward.imageUrl,
                    fit: BoxFit.cover,
                    fallback: ColoredBox(
                      color: _gold.withValues(alpha: .08),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        color: _gold,
                        size: 58,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: _display(20))),
                    if (reward.memberOnly)
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: _gold,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '${reward.cost} PTS',
                      style: _display(20, color: _gold),
                    ),
                    const Spacer(),
                    Text(
                      reward.unlimitedStock
                          ? abuText(context, 'AVAILABLE', 'متاح')
                          : abuText(
                              context,
                              '${reward.stock} left',
                              'متبقي ${reward.stock}',
                            ),
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canRedeem ? onRedeem : null,
                    child: Text(
                      !available
                          ? abuText(context, 'SOLD OUT', 'نفدت الكمية')
                          : reward.memberOnly && !isMember
                          ? abuText(context, 'MEMBERS ONLY', 'للأعضاء فقط')
                          : balance < reward.cost
                          ? abuText(
                              context,
                              'NOT ENOUGH POINTS',
                              'النقاط غير كافية',
                            )
                          : abuText(context, 'REDEEM', 'استبدال'),
                    ),
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

class _InteractiveFanCardState extends State<_InteractiveFanCard>
    with SingleTickerProviderStateMixin {
  static const _cardSize = Size(320, 410);
  Offset _targetTilt = Offset.zero;
  Offset _currentTilt = Offset.zero;
  late final AnimationController _controller;
  Offset _velocity = Offset.zero;
  static const double _stiffness = 110;
  static const double _damping = 18;
  bool _isHovered = false;
  UserLeaderboardRanks? _loadedRanks;
  double? _loadedAccuracy;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updatePhysics);
    _fetchStats();
  }

  @override
  void didUpdateWidget(covariant _InteractiveFanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.totalPoints != widget.profile.totalPoints) {
      _fetchStats();
    }
  }

  Future<void> _fetchStats() async {
    if (widget.repository == null) return;
    final isOwnProfile =
        widget.repository!.auth.currentUser?.uid == widget.profile.uid;
    if (widget.monthlyRank == null || widget.seasonRank == null) {
      final ranks = await widget.repository!.fetchUserRanks(widget.profile);
      if (mounted) setState(() => _loadedRanks = ranks);
    }
    if (isOwnProfile && widget.accuracy == null) {
      final a = await widget.repository!.fetchUserAccuracy(widget.profile.uid);
      if (mounted) setState(() => _loadedAccuracy = a);
    }
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

    final isMember = profile.isYouTubeMember;
    final tierTitle = isMember ? 'GOLD' : 'SILVER';
    final tierColor = isMember
        ? const Color(0xFFFFD700)
        : const Color(0xFFD6DFE8);

    final cardGradients = isMember
        ? const [Color(0xFF3E2D0E), Color(0xFF251A07), Color(0xFF140E04)]
        : const [Color(0xFF2B323D), Color(0xFF1B2028), Color(0xFF101318)];

    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => _release(),
        onHover: (event) => _updateTarget(event.localPosition),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
                  color: tierColor.withValues(alpha: isMember ? .32 : .18),
                  blurRadius: 36,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .8),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
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
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: cardGradients,
                          stops: const [0, .55, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'XP',
                                    style: TextStyle(
                                      color: tierColor,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w900,
                                      height: .85,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tierColor.withValues(alpha: .2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tierTitle,
                                      style: TextStyle(
                                        color: tierColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 32,
                                    height: 1,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    color: tierColor.withValues(alpha: .3),
                                  ),
                                  Text(
                                    teamCode,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  _CountryFlagWidget(
                                    country: profile.country,
                                    flagEmoji: profile.countryFlag,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 6),
                                  _ProductionTeamBadge(
                                    team: profile.supportedTeam,
                                    source: profile.supportedTeamLogo,
                                    size: 34,
                                  ),
                                ],
                              ),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 172,
                                    height: 196,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: tierColor.withValues(alpha: .6),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: tierColor.withValues(
                                            alpha: .22,
                                          ),
                                          blurRadius: 18,
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: portrait,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 1,
                            color: tierColor.withValues(alpha: .3),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              profile.displayName.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                                shadows: [
                                  Shadow(
                                    color: tierColor.withValues(alpha: .5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: 1,
                            color: tierColor.withValues(alpha: .3),
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final effectiveMonthlyRank =
                                  widget.monthlyRank ??
                                  _loadedRanks?.currentMonth ??
                                  0;
                              final effectiveSeasonRank =
                                  widget.seasonRank ??
                                  _loadedRanks?.season ??
                                  0;
                              final effectiveAccuracy =
                                  widget.accuracy ?? _loadedAccuracy;
                              final monthlyRankText = effectiveMonthlyRank > 0
                                  ? '#$effectiveMonthlyRank'
                                  : '—';
                              final seasonRankText = effectiveSeasonRank > 0
                                  ? '#$effectiveSeasonRank'
                                  : '—';
                              final accuracyText =
                                  profile.totalPoints > 0 &&
                                      effectiveAccuracy != null
                                  ? '${effectiveAccuracy.toStringAsFixed(0)}%'
                                  : '—';
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _FanCardStat(
                                          value: '${profile.totalPoints}',
                                          label: 'LIFETIME XP',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _FanCardStat(
                                          value: monthlyRankText,
                                          label: 'MONTH RANK',
                                          reverse: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _FanCardStat(
                                          icon: const _StreakIconWidget(
                                            size: 13,
                                          ),
                                          value: '${profile.currentStreak}',
                                          label: 'STREAK',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _FanCardStat(
                                          value: accuracyText,
                                          label: 'ACCURACY',
                                          reverse: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _FanCardStat(
                                          value: '${profile.seasonPoints}',
                                          label: 'SEASON XP',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _FanCardStat(
                                          value: seasonRankText,
                                          label: 'SEASON RANK',
                                          reverse: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
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
                    if (widget.onEdit != null)
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onEdit,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D121B)
                                    .withValues(alpha: .88),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _productionPrimary(context)
                                      .withValues(alpha: .7),
                                  width: 1.4,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.edit_rounded,
                                color: _productionPrimary(context),
                                size: 16,
                              ),
                            ),
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
    this.icon,
    this.reverse = false,
  });

  final String value;
  final String label;
  final Widget? icon;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final valueWidget = Row(
      mainAxisAlignment: reverse
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 4)],
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    final labelWidget = SizedBox(
      width: double.infinity,
      child: Text(
        label,
        textAlign: reverse ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: reverse
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [valueWidget, const SizedBox(height: 1), labelWidget],
    );
  }
}

class _FanCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const radius = 24.0;
    const cornerCut = 20.0;

    path.moveTo(cornerCut, 0);
    path.lineTo(size.width - cornerCut, 0);
    path.lineTo(size.width, cornerCut);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    );
    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, cornerCut);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _FanCardBorderPainter extends CustomPainter {
  _FanCardBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _FanCardClipper().getClip(size);
    final paint = Paint()
      ..color = const Color(0x44FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Kept dormant while all fixtures live in Predict.
// ignore: unused_element
class _ProductionCalendar extends StatelessWidget {
  const _ProductionCalendar({required this.repository, required this.profile});
  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final activeDays = profile.currentStreak;
    final now = DateTime.now();
    final monthDays = DateUtils.getDaysInMonth(now.year, now.month);
    return _PageFrame(
      kicker: abuText(
        context,
        'Upcoming fixtures & activity tracking',
        'مباريات الموسم وجدول النشاط اليومي',
      ),
      title: abuText(context, 'Calendar & Streaks', 'التقويم وسلسلة الأيام'),
      child: StreamBuilder<List<MatchEvent>>(
        stream: repository.watchMatches(),
        builder: (context, snapshot) {
          final matches = snapshot.data ?? const [];
          final upcomingMatches =
              matches
                  .where(
                    (m) => m.kickoffAt.isAfter(
                      now.subtract(const Duration(hours: 3)),
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));

          final matchScheduleCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        color: _productionPrimary(context),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        abuText(
                          context,
                          'UPCOMING MATCHES',
                          'المباريات القادمة',
                        ),
                        style: _display(20),
                      ),
                      const Spacer(),
                      if (upcomingMatches.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _productionPrimary(context)
                                .withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            abuText(
                              context,
                              '${upcomingMatches.length} FIXTURES',
                              '${upcomingMatches.length} مباريات',
                            ),
                            style: TextStyle(
                              color: _productionPrimary(context),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (upcomingMatches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          abuText(
                            context,
                            'No upcoming matches scheduled right now.',
                            'لا توجد مباريات قادمة مجدولة حالياً.',
                          ),
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: upcomingMatches.take(8).length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (context, i) {
                        final m = upcomingMatches[i];
                        final isLive =
                            m.status == 'live' || m.status == 'in_progress';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLive
                                ? _productionPrimary(context)
                                      .withValues(alpha: .08)
                                : _surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isLive
                                  ? _productionPrimary(context)
                                        .withValues(alpha: .4)
                                  : _line,
                            ),
                          ),
                          child: Row(
                            children: [
                              _ProductionTeamBadge(
                                team: m.homeTeam,
                                source: m.homeLogoUrl,
                                size: 36,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${m.homeTeam} vs ${m.awayTeam}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${m.competition.isNotEmpty ? m.competition : "Football League"} · ${_productionDate(m.kickoffAt)}',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ProductionTeamBadge(
                                team: m.awayTeam,
                                source: m.awayLogoUrl,
                                size: 36,
                              ),
                              if (isLive) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _red,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );

          final calendarGrid = Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
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
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${now.year} · ${now.month.toString().padLeft(2, '0')}',
                    style: _display(18),
                  ),
                  const SizedBox(height: 14),
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
                              ? _productionPrimary(context)
                                    .withValues(alpha: .18)
                              : Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: today ? _productionPrimary(context) : _line,
                            width: today ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: completed
                              ? Icon(
                                  Icons.check_rounded,
                                  color: _productionPrimary(context),
                                  size: 18,
                                )
                              : Text(
                                  '$day',
                                  style: TextStyle(color: _muted, fontSize: 12),
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
                    style: _display(20),
                  ),
                  const SizedBox(height: 16),
                  for (final milestone in [
                    (3, abuText(context, 'Warm up', 'بداية قوية')),
                    (7, abuText(context, 'On fire', 'متألق')),
                    (14, abuText(context, 'Unstoppable', 'لا يُوقَف')),
                    (30, abuText(context, 'Club legend', 'أسطورة النادي')),
                    (60, abuText(context, 'Master fan', 'مشجع محترف')),
                    (100, abuText(context, 'Centurion', 'مئوي')),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: activeDays >= milestone.$1
                            ? _productionPrimary(context)
                            : _line,
                        foregroundColor: _ink,
                        child: Text('${milestone.$1}'),
                      ),
                      title: Text(
                        milestone.$2,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: Icon(
                        activeDays >= milestone.$1
                            ? Icons.check_circle_rounded
                            : Icons.lock_outline_rounded,
                        color: activeDays >= milestone.$1
                            ? _productionPrimary(context)
                            : _muted,
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
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                ],
              ),
            ),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1100) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: matchScheduleCard),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          calendarGrid,
                          const SizedBox(height: 18),
                          milestones,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  matchScheduleCard,
                  const SizedBox(height: 16),
                  calendarGrid,
                  const SizedBox(height: 16),
                  milestones,
                ],
              );
            },
          );
        },
      ),
    );
  }
}

const int _maximumCampaignImageBytes = 8 * 1024 * 1024;
const Set<String> _campaignImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
};

Future<String?> _pickedCampaignImageError(
  BuildContext context,
  XFile image,
) async {
  final tooLargeMessage = abuText(
    context,
    'The image must be smaller than 8 MB.',
    'يجب أن يكون حجم الصورة أقل من 8 ميغابايت.',
  );
  final emptyMessage = abuText(
    context,
    'The selected image is empty.',
    'الصورة المحددة فارغة.',
  );
  final extension = image.name.contains('.')
      ? image.name.split('.').last.toLowerCase()
      : '';
  final mimeType = image.mimeType?.toLowerCase();
  if (!_campaignImageExtensions.contains(extension) ||
      (mimeType != null && !mimeType.startsWith('image/'))) {
    return abuText(
      context,
      'Choose a JPG, PNG, WebP or GIF image.',
      'اختر صورة بصيغة JPG أو PNG أو WebP أو GIF.',
    );
  }
  final length = await image.length();
  if (length > _maximumCampaignImageBytes) {
    return tooLargeMessage;
  }
  if (length == 0) {
    return emptyMessage;
  }
  return null;
}

Future<({XFile file, dynamic bytes})?> _selectAdminImage(
  BuildContext context,
) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 94,
  );
  if (picked == null || !context.mounted) return null;
  final validation = await _pickedCampaignImageError(context, picked);
  if (!context.mounted) return null;
  if (validation != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(validation)));
    return null;
  }
  try {
    return (file: picked, bytes: await picked.readAsBytes());
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'The selected image could not be read.',
              'تعذر قراءة الصورة المحددة.',
            ),
          ),
        ),
      );
    }
    return null;
  }
}

Widget _campaignImagePreview({
  required BuildContext context,
  required String imageUrl,
  dynamic imageBytes,
  double height = 220,
}) {
  final fallback = ColoredBox(
    color: _surface2,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, color: _muted),
            const SizedBox(height: 8),
            Text(
              abuText(
                context,
                'Image unavailable. Choose another image from your gallery.',
                'الصورة غير متاحة. اختر صورة أخرى من معرض الصور.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
  final child = imageBytes != null
      ? Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        )
      : imageUrl.trim().isEmpty
      ? ColoredBox(
          color: _surface2,
          child: Center(
            child: Text(
              abuText(context, 'No image selected', 'لم يتم اختيار صورة'),
              style: TextStyle(color: _muted),
            ),
          ),
        )
      : Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: CircularProgressIndicator()),
            _ProductionRemoteImage(
              url: externalHttpUri(imageUrl)?.toString() ?? imageUrl,
              fit: BoxFit.cover,
              fallback: fallback,
            ),
          ],
        );
  return ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(height: height, width: double.infinity, child: child),
  );
}

Future<void> _showAdminChallengePreview(
  BuildContext context, {
  required String kind,
  required String title,
  required String description,
  required int rewardPoints,
  required String status,
  required DateTime startsAt,
  required DateTime endsAt,
  required int maximumAttempts,
  required bool memberOnly,
  required List<AbuChallengeQuestion> questions,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(abuText(context, 'CHALLENGE PREVIEW', 'معاينة التحدي')),
    content: SizedBox(
      width: 500,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _productionPrimary(context)
                        .withValues(alpha: .12),
                    child: Icon(
                      _adminChallengeKindIcon(kind),
                      color: _productionPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  _RewardChip(text: '+$rewardPoints XP'),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title.trim().isEmpty
                    ? abuText(context, 'Untitled challenge', 'تحدٍ بلا عنوان')
                    : title.trim(),
                style: _display(24),
              ),
              const SizedBox(height: 8),
              Text(
                description.trim().isEmpty
                    ? abuText(
                        context,
                        'Add a description before publishing.',
                        'أضف وصفاً قبل النشر.',
                      )
                    : description.trim(),
                style: TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _LiveDot(
                    text: status == 'open'
                        ? abuText(context, 'LIVE', 'مباشر')
                        : status.toUpperCase(),
                  ),
                  _ChallengeMetaChip(
                    icon: Icons.quiz_rounded,
                    label: abuText(
                      context,
                      '${questions.length} questions',
                      '${questions.length} أسئلة',
                    ),
                  ),
                  _ChallengeMetaChip(
                    icon: Icons.replay_rounded,
                    label: abuText(
                      context,
                      '$maximumAttempts attempts',
                      '$maximumAttempts محاولات',
                    ),
                  ),
                  if (memberOnly)
                    _ChallengeMetaChip(
                      icon: Icons.workspace_premium_rounded,
                      label: abuText(context, 'Members only', 'للأعضاء فقط'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                abuText(
                  context,
                  '${_productionDate(startsAt)} → ${_productionDate(endsAt)}',
                  '${_productionDate(startsAt)} ← ${_productionDate(endsAt)}',
                ),
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              for (var index = 0; index < questions.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ',
                        style: TextStyle(color: _productionPrimary(context)),
                      ),
                      Expanded(
                        child: Text(
                          questions[index].prompt.trim().isEmpty
                              ? abuText(
                                  context,
                                  'Question preview',
                                  'معاينة السؤال',
                                )
                              : questions[index].prompt,
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'CLOSE', 'إغلاق')),
      ),
    ],
  ),
);

Future<void> _showAdminAnnouncementPreview(
  BuildContext context, {
  required String title,
  required String body,
  required String imageUrl,
  required String buttonLabel,
  dynamic imageBytes,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    clipBehavior: Clip.antiAlias,
    titlePadding: EdgeInsets.zero,
    title: imageUrl.trim().isEmpty && imageBytes == null
        ? null
        : _campaignImagePreview(
            context: context,
            imageUrl: imageUrl,
            imageBytes: imageBytes,
            height: 230,
          ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.trim().isEmpty
                ? abuText(context, 'Popup title', 'عنوان النافذة')
                : title.trim(),
            style: _display(27),
          ),
          const SizedBox(height: 10),
          Text(
            body.trim().isEmpty
                ? abuText(context, 'Popup message', 'رسالة النافذة')
                : body.trim(),
            style: TextStyle(color: _muted, height: 1.5),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'LATER', 'لاحقاً')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          buttonLabel.trim().isEmpty
              ? abuText(context, 'OPEN', 'فتح')
              : buttonLabel.trim(),
        ),
      ),
    ],
  ),
);

class _AdminQuestionDraft {
  _AdminQuestionDraft({this.type = 'text'}) {
    if (type == 'trueFalse') {
      options.text = 'True\nFalse';
      answer.text = 'true';
    }
  }

  final TextEditingController prompt = TextEditingController();
  final TextEditingController answer = TextEditingController();
  final TextEditingController acceptedAnswers = TextEditingController();
  final TextEditingController options = TextEditingController();
  String type;

  List<String> get parsedOptions => options.text
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  AbuChallengeQuestion toModel(int index, {String fallbackPrompt = ''}) =>
      AbuChallengeQuestion(
        id: 'question_${index + 1}',
        prompt: effectiveChallengePrompt(
          title: fallbackPrompt,
          prompt: prompt.text,
        ),
        type: type,
        options: type == 'trueFalse'
            ? const <String>['true', 'false']
            : parsedOptions,
        correctAnswer: type == 'trueFalse'
            ? answer.text.trim().toLowerCase()
            : answer.text.trim(),
        acceptedAnswers: acceptedAnswers.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false),
      );

  void updateType(String value) {
    type = value;
    if (value == 'trueFalse') {
      options.text = 'True\nFalse';
      if (!const ['true', 'false'].contains(answer.text.toLowerCase())) {
        answer.text = 'true';
      }
    }
  }

  void dispose() {
    prompt.dispose();
    answer.dispose();
    acceptedAnswers.dispose();
    options.dispose();
  }
}

IconData _adminChallengeKindIcon(String kind) => switch (kind) {
  'playerCard' => Icons.person_search_rounded,
  _ => Icons.subtitles_rounded,
};

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
      if (constraints.maxWidth < 1100) return _buildMobile(context);
      final actions = <Widget>[
        _AdminQuickAction(
          icon: Icons.bolt_rounded,
          label: abuText(context, 'NEW CHALLENGE', 'تحدٍ جديد'),
          detail: abuText(
            context,
            'Publish a video question or Player Guess challenge.',
            'انشر سؤال فيديو أو تحدي تخمين لاعب.',
          ),
          color: _productionPrimary(context),
          primary: true,
          onTap: () => createChallenge(context),
        ),
        _AdminQuickAction(
          icon: Icons.workspace_premium_rounded,
          label: abuText(context, 'YOUTUBE MEMBERS', 'أعضاء يوتيوب'),
          detail: abuText(
            context,
            'Review channel claims and replace the complete membership CSV.',
            'راجع طلبات القنوات واستبدل ملف CSV الكامل للعضويات.',
          ),
          color: _gold,
          onTap: () => _manageYouTubeMembers(context),
        ),
        _AdminQuickAction(
          icon: Icons.campaign_rounded,
          label: abuText(context, 'LAUNCH POPUP', 'نافذة بدء'),
          detail: abuText(
            context,
            'Schedule an in-app campaign for every platform.',
            'جدول حملة داخل التطبيق لكل المنصات.',
          ),
          color: _gold,
          onTap: () => editAnnouncement(context),
        ),
        _AdminQuickAction(
          icon: Icons.person_search_rounded,
          label: abuText(context, 'NEW PLAYER GUESS', 'تخمين لاعب جديد'),
          detail: abuText(
            context,
            'Publish a video clue and let fans answer the player name.',
            'انشر تلميح فيديو ودع الجمهور يخمن اسم اللاعب.',
          ),
          color: _blue,
          onTap: () => managePlayerCards(context),
        ),
        if (profile.isAdmin)
          _AdminQuickAction(
            icon: Icons.date_range_rounded,
            label: abuText(context, 'LEADERBOARD SEASONS', 'مواسم الترتيب'),
            detail: abuText(
              context,
              'Set the season name and exact XP leaderboard dates.',
              'حدد اسم الموسم وتواريخ ترتيب XP بدقة.',
            ),
            color: _productionPrimary(context),
            onTap: () => manageLeaderboardSeasons(context),
          ),
        if (profile.canManageRoles)
          _AdminQuickAction(
            icon: Icons.manage_accounts_rounded,
            label: abuText(context, 'ROLES & ADMINS', 'الأدوار والمشرفون'),
            detail: abuText(
              context,
              'Grant scoped access to trusted collaborators.',
              'امنح صلاحيات محددة للمتعاونين الموثوقين.',
            ),
            color: _red,
            onTap: () => manageRoles(context),
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResponsiveGrid(minWidth: 250, children: actions),
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
                          color: _productionPrimary(context)
                              .withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.dashboard_customize_rounded,
                          color: _productionPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              abuText(
                                context,
                                'ENGAGEMENT CONTROL',
                                'إدارة التفاعل',
                              ),
                              style: _display(22),
                            ),
                            Text(
                              abuText(
                                context,
                                'Live content operations · signed in as ${profile.role.toUpperCase()}',
                                'إدارة المحتوى المباشر · مسجل بصلاحية ${profile.role}',
                              ),
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      _LiveDot(text: abuText(context, 'REAL-TIME', 'فوري')),
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
          Text(
            abuText(context, 'CONTENT & ACCESS', 'المحتوى والصلاحيات'),
            style: _display(22),
          ),
          const SizedBox(height: 6),
          Text(
            abuText(
              context,
              'Publish the experiences users see without rebuilding the app. Signed in as ${profile.role}.',
              'انشر التجارب التي يراها المستخدمون دون إعادة بناء التطبيق. مسجل بصلاحية ${profile.role}.',
            ),
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                _AdminMobileAction(
                  icon: Icons.bolt_rounded,
                  label: abuText(context, 'NEW CHALLENGE', 'تحدٍ جديد'),
                  color: _productionPrimary(context),
                  emphasized: true,
                  onTap: () => createChallenge(context),
                ),
                _AdminMobileAction(
                  icon: Icons.campaign_rounded,
                  label: abuText(context, 'LAUNCH POPUP', 'نافذة بدء'),
                  color: _gold,
                  onTap: () => editAnnouncement(context),
                ),
                if (profile.canUploadMembershipSnapshot)
                  _AdminMobileAction(
                    icon: Icons.workspace_premium_rounded,
                    label: abuText(context, 'YOUTUBE MEMBERS', 'أعضاء يوتيوب'),
                    color: _gold,
                    onTap: () => _manageYouTubeMembers(context),
                  ),
                _AdminMobileAction(
                  icon: Icons.person_search_rounded,
                  label: abuText(
                    context,
                    'NEW PLAYER GUESS',
                    'تخمين لاعب جديد',
                  ),
                  color: _blue,
                  onTap: () => managePlayerCards(context),
                ),
                if (profile.isAdmin)
                  _AdminMobileAction(
                    icon: Icons.date_range_rounded,
                    label: abuText(
                      context,
                      'LEADERBOARD SEASONS',
                      'مواسم الترتيب',
                    ),
                    color: _productionPrimary(context),
                    onTap: () => manageLeaderboardSeasons(context),
                  ),
                if (profile.canManageRoles)
                  _AdminMobileAction(
                    icon: Icons.manage_accounts_rounded,
                    label: abuText(
                      context,
                      'ROLES & ADMINS',
                      'الأدوار والمشرفون',
                    ),
                    color: _red,
                    onTap: () => manageRoles(context),
                  ),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: actions.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth < 330 ? 1 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 64,
                ),
                itemBuilder: (context, index) => actions[index],
              );
            },
          ),
          const SizedBox(height: 18),
          _AdminEventManager(repository: repository),
        ],
      ),
    ),
  );

  Future<void> _manageYouTubeMembers(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _AdminMembershipDialog(repository: repository),
  );

  Future<void> createChallenge(
    BuildContext context, {
    String initialKind = 'videoPhrase',
  }) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final video = TextEditingController();
    final points = TextEditingController(text: '10');
    final questions = <_AdminQuestionDraft>[_AdminQuestionDraft()];
    var kind = initialKind == 'playerCard' ? 'playerCard' : 'videoPhrase';
    var status = 'open';
    var maximumAttempts = 3;
    var memberOnly = false;
    var notifyOnLive = true;
    var startsAt = DateTime.now();
    var endsAt = DateTime.now().add(const Duration(days: 7));
    XFile? selectedImage;
    dynamic selectedImageBytes;
    String kindLabel(BuildContext context, String value) => switch (value) {
      'playerCard' => abuText(context, 'Guess the player', 'احزر اللاعب'),
      _ => abuText(context, 'Video phrase', 'عبارة من الفيديو'),
    };

    String questionTypeForKind(String value) => switch (value) {
      _ => 'text',
    };

    void resetQuestions(String value) {
      for (final draft in questions) {
        draft.dispose();
      }
      questions
        ..clear()
        ..add(_AdminQuestionDraft(type: questionTypeForKind(value)));
      if (value == 'playerCard') {
        questions.first.prompt.text = abuText(
          context,
          'Which player is described in the video?',
          'من هو اللاعب المذكور في الفيديو؟',
        );
      }
    }

    if (kind == 'playerCard') {
      resetQuestions(kind);
    }

    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            abuText(context, 'Create playable challenge', 'إنشاء تحدٍ تفاعلي'),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Challenge format',
                        'نوع التحدي',
                      ),
                    ),
                    items: const ['videoPhrase', 'playerCard']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Row(
                              children: [
                                Icon(_adminChallengeKindIcon(value), size: 19),
                                const SizedBox(width: 10),
                                Text(kindLabel(context, value)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null || value == kind) return;
                      setDialogState(() {
                        kind = value;
                        resetQuestions(value);
                        points.text = '10';
                      });
                    },
                  ),
                  if (kind == 'playerCard') ...[
                    const SizedBox(height: 12),
                    Card(
                      color: _productionPrimary(context).withValues(alpha: .08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.smart_display_rounded,
                              color: _productionPrimary(context),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                abuText(
                                  context,
                                  'Add the YouTube video containing the clues, then enter the player name as the private correct answer below. Fans watch, type their guess in the app, and earn the configured points.',
                                  'أضف فيديو يوتيوب الذي يحتوي على التلميحات، ثم أدخل اسم اللاعب كإجابة صحيحة خاصة أدناه. يشاهد الجمهور الفيديو ويكتبون تخمينهم داخل التطبيق ويحصلون على النقاط المحددة.',
                                ),
                                style: TextStyle(color: _muted, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Status', 'الحالة'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'draft',
                        child: Text(abuText(context, 'Draft', 'مسودة')),
                      ),
                      DropdownMenuItem(
                        value: 'scheduled',
                        child: Text(abuText(context, 'Scheduled', 'مجدول')),
                      ),
                      DropdownMenuItem(
                        value: 'open',
                        child: Text(abuText(context, 'Live', 'مباشر')),
                      ),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text(abuText(context, 'Disabled', 'معطّل')),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => status = value ?? 'draft'),
                  ),
                  _AdminDateTile(
                    label: abuText(context, 'Starts', 'يبدأ'),
                    value: startsAt,
                    onChanged: (value) =>
                        setDialogState(() => startsAt = value),
                  ),
                  _AdminDateTile(
                    label: abuText(context, 'Ends', 'ينتهي'),
                    value: endsAt,
                    onChanged: (value) => setDialogState(() => endsAt = value),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Title', 'العنوان'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Description', 'الوصف'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: video,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'YouTube/video URL',
                        'رابط يوتيوب/الفيديو',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selection = await _selectAdminImage(context);
                      if (selection == null || !context.mounted) return;
                      setDialogState(() {
                        selectedImage = selection.file;
                        selectedImageBytes = selection.bytes;
                      });
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      selectedImage == null
                          ? abuText(
                              context,
                              'SELECT CHALLENGE IMAGE (OPTIONAL)',
                              'اختر صورة التحدي (اختياري)',
                            )
                          : selectedImage!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selectedImage != null) ...[
                    const SizedBox(height: 10),
                    _campaignImagePreview(
                      context: context,
                      imageUrl: '',
                      imageBytes: selectedImageBytes,
                      height: 180,
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: points,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'XP for correct answer',
                        'XP للإجابة الصحيحة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: maximumAttempts,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Maximum attempts',
                        'الحد الأقصى للمحاولات',
                      ),
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
                    title: Text(
                      abuText(
                        context,
                        'YouTube members only',
                        'لأعضاء يوتيوب فقط',
                      ),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: notifyOnLive,
                    onChanged: (value) =>
                        setDialogState(() => notifyOnLive = value),
                    title: Text(
                      abuText(
                        context,
                        'Notify users when live',
                        'إشعار المستخدمين عند النشر',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          abuText(context, 'QUESTIONS', 'الأسئلة'),
                          style: _display(18),
                        ),
                      ),
                      if (kind == 'multiQuestion')
                        TextButton.icon(
                          onPressed: () => setDialogState(
                            () => questions.add(_AdminQuestionDraft()),
                          ),
                          icon: Icon(Icons.add_rounded),
                          label: Text(
                            abuText(context, 'ADD QUESTION', 'إضافة سؤال'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var index = 0; index < questions.length; index++) ...[
                    Card(
                      color: _surface2,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    abuText(
                                      context,
                                      'Question ${index + 1}',
                                      'السؤال ${index + 1}',
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (kind == 'multiQuestion' &&
                                    questions.length > 1)
                                  IconButton(
                                    tooltip: abuText(
                                      context,
                                      'Remove question',
                                      'حذف السؤال',
                                    ),
                                    onPressed: () => setDialogState(() {
                                      final removed = questions.removeAt(index);
                                      removed.dispose();
                                    }),
                                    icon: Icon(Icons.delete_outline_rounded),
                                  ),
                              ],
                            ),
                            if (kind == 'multiQuestion') ...[
                              DropdownButtonFormField<String>(
                                initialValue: questions[index].type,
                                decoration: InputDecoration(
                                  labelText: abuText(
                                    context,
                                    'Answer format',
                                    'نوع الإجابة',
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'text',
                                    child: Text(
                                      abuText(context, 'Text answer', 'نص'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'multipleChoice',
                                    child: Text(
                                      abuText(
                                        context,
                                        'Multiple choice',
                                        'اختيار متعدد',
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'trueFalse',
                                    child: Text(
                                      abuText(
                                        context,
                                        'True or false',
                                        'صح أو خطأ',
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(
                                    () => questions[index].updateType(value),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            TextField(
                              controller: questions[index].prompt,
                              decoration: InputDecoration(
                                labelText: abuText(
                                  context,
                                  'Question prompt (optional)',
                                  'نص السؤال (اختياري)',
                                ),
                                helperText: abuText(
                                  context,
                                  'The challenge title is used when this is empty.',
                                  'يُستخدم عنوان التحدي عند تركه فارغاً.',
                                ),
                              ),
                            ),
                            if (questions[index].type == 'multipleChoice') ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: questions[index].options,
                                minLines: 3,
                                maxLines: 5,
                                decoration: InputDecoration(
                                  labelText: abuText(
                                    context,
                                    'Options · one per line',
                                    'الخيارات · خيار في كل سطر',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (questions[index].type == 'trueFalse')
                              DropdownButtonFormField<String>(
                                initialValue:
                                    questions[index].answer.text.isEmpty
                                    ? 'true'
                                    : questions[index].answer.text
                                          .toLowerCase(),
                                decoration: InputDecoration(
                                  labelText: abuText(
                                    context,
                                    'Private correct answer',
                                    'الإجابة الصحيحة الخاصة',
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'true',
                                    child: Text(
                                      abuText(context, 'True', 'صحيح'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'false',
                                    child: Text(
                                      abuText(context, 'False', 'خطأ'),
                                    ),
                                  ),
                                ],
                                onChanged: (value) =>
                                    questions[index].answer.text =
                                        value ?? 'true',
                              )
                            else
                              Column(
                                children: [
                                  TextField(
                                    controller: questions[index].answer,
                                    decoration: InputDecoration(
                                      labelText: kind == 'playerCard'
                                          ? abuText(
                                              context,
                                              'Private player name',
                                              'اسم اللاعب الخاص',
                                            )
                                          : abuText(
                                              context,
                                              'Private correct answer',
                                              'الإجابة الصحيحة الخاصة',
                                            ),
                                      helperText: kind == 'playerCard'
                                          ? abuText(
                                              context,
                                              'Fans never see this answer before submitting.',
                                              'لن يرى الجمهور هذه الإجابة قبل الإرسال.',
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller:
                                        questions[index].acceptedAnswers,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: InputDecoration(
                                      labelText: kind == 'playerCard'
                                          ? abuText(
                                              context,
                                              'Other accepted player spellings · one per line (optional)',
                                              'تهجئات أخرى مقبولة لاسم اللاعب · واحدة في كل سطر (اختياري)',
                                            )
                                          : abuText(
                                              context,
                                              'Other accepted answers · one per line (optional)',
                                              'إجابات أخرى مقبولة · واحدة في كل سطر (اختياري)',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (index != questions.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(abuText(context, 'CANCEL', 'إلغاء')),
            ),
            TextButton.icon(
              onPressed: () => _showAdminChallengePreview(
                context,
                kind: kind,
                title: title.text,
                description: description.text,
                rewardPoints: int.tryParse(points.text) ?? 0,
                status: status,
                startsAt: startsAt,
                endsAt: endsAt,
                maximumAttempts: maximumAttempts,
                memberOnly: memberOnly,
                questions: questions
                    .asMap()
                    .entries
                    .map(
                      (entry) => entry.value.toModel(
                        entry.key,
                        fallbackPrompt: title.text,
                      ),
                    )
                    .toList(),
              ),
              icon: Icon(Icons.visibility_rounded),
              label: Text(abuText(context, 'PREVIEW', 'معاينة')),
            ),
            FilledButton(
              onPressed: () {
                final reward = int.tryParse(points.text);
                String? validationError;
                if (title.text.trim().isEmpty) {
                  validationError = abuText(
                    context,
                    'Add a challenge title.',
                    'أضف عنواناً للتحدي.',
                  );
                } else if (reward == null || reward <= 0) {
                  validationError = abuText(
                    context,
                    'XP for a correct answer must be greater than zero.',
                    'يجب أن تكون نقاط XP للإجابة الصحيحة أكبر من صفر.',
                  );
                } else if (!endsAt.isAfter(startsAt)) {
                  validationError = abuText(
                    context,
                    'End time must be after the start time.',
                    'يجب أن يكون وقت الانتهاء بعد وقت البدء.',
                  );
                }
                for (final draft in questions) {
                  if (validationError != null) break;
                  if (draft.answer.text.trim().isEmpty) {
                    validationError = abuText(
                      context,
                      'Enter the private correct answer so responses can be scored.',
                      'أدخل الإجابة الصحيحة الخاصة حتى يمكن تقييم الإجابات.',
                    );
                  } else if (draft.type == 'multipleChoice' &&
                      draft.parsedOptions.length < 2) {
                    validationError = abuText(
                      context,
                      'Multiple-choice questions need at least two options.',
                      'تحتاج أسئلة الاختيار المتعدد إلى خيارين على الأقل.',
                    );
                  } else if (draft.type == 'multipleChoice' &&
                      !draft.parsedOptions.any(
                        (option) =>
                            option.toLowerCase() ==
                            draft.answer.text.trim().toLowerCase(),
                      )) {
                    validationError = abuText(
                      context,
                      'The correct answer must match one of its options.',
                      'يجب أن تطابق الإجابة الصحيحة أحد الخيارات.',
                    );
                  }
                }
                if (validationError != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(validationError)));
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(abuText(context, 'PUBLISH', 'نشر')),
            ),
          ],
        ),
      ),
    );
    final questionModels = questions
        .asMap()
        .entries
        .map(
          (entry) => entry.value.toModel(entry.key, fallbackPrompt: title.text),
        )
        .toList(growable: false);
    if (submit == true && context.mounted) {
      await _adminAction(context, () async {
        final uploadedImageUrl = selectedImage == null
            ? ''
            : await repository.uploadChallengeImage(selectedImage!);
        await repository.createAdvancedChallenge(
          kind: kind,
          title: title.text,
          description: description.text,
          videoUrl: video.text,
          imageUrl: uploadedImageUrl,
          rewardPoints: int.tryParse(points.text) ?? 0,
          availableFrom: startsAt,
          availableUntil: endsAt,
          status: status,
          maximumAttempts: maximumAttempts,
          memberOnly: memberOnly,
          notifyOnLive: notifyOnLive,
          questions: questionModels,
        );
      }, abuText(context, 'Challenge published.', 'تم نشر التحدي.'));
    }
    title.dispose();
    description.dispose();
    video.dispose();
    points.dispose();
    for (final question in questions) {
      question.dispose();
    }
  }

  Future<void> editAnnouncement(BuildContext context) async {
    LaunchAnnouncement? existing;
    try {
      existing = await repository.watchLaunchAnnouncement().first;
    } catch (_) {
      // A missing announcement is a valid first-run state.
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
    XFile? selectedImage;
    dynamic selectedImageBytes;
    String? imageValidationError;
    String? uploadError;
    var uploading = false;
    final submission = await showDialog<({String imageUrl, bool reset})?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            abuText(context, 'APP-LAUNCH POPUP', 'نافذة بدء التطبيق'),
          ),
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
                    title: Text(
                      abuText(
                        context,
                        'Show on app launch',
                        'إظهار عند بدء التطبيق',
                      ),
                    ),
                  ),
                  Material(
                    color: _surface2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: _line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            abuText(
                              context,
                              'SCHEDULE & DELIVERY',
                              'الجدولة والعرض',
                            ),
                            style: TextStyle(
                              color: _productionPrimary(context),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: frequency,
                            decoration: InputDecoration(
                              labelText: abuText(
                                context,
                                'How often should each user see it?',
                                'كم مرة يراها كل مستخدم؟',
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'once',
                                child: Text(
                                  abuText(
                                    context,
                                    'Once for this campaign',
                                    'مرة واحدة لهذه الحملة',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'daily',
                                child: Text(
                                  abuText(
                                    context,
                                    'Once per day',
                                    'مرة يومياً',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'session',
                                child: Text(
                                  abuText(
                                    context,
                                    'Once per app session',
                                    'مرة في كل جلسة',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'always',
                                child: Text(
                                  abuText(
                                    context,
                                    'Every app launch',
                                    'عند كل تشغيل',
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => frequency = value ?? 'once',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final start = _AdminDateTile(
                                label: abuText(
                                  context,
                                  'Starts (date & time)',
                                  'يبدأ (التاريخ والوقت)',
                                ),
                                value: startsAt,
                                onChanged: (value) =>
                                    setDialogState(() => startsAt = value),
                              );
                              final end = _AdminDateTile(
                                label: abuText(
                                  context,
                                  'Expires (date & time)',
                                  'ينتهي (التاريخ والوقت)',
                                ),
                                value: endsAt,
                                onChanged: (value) =>
                                    setDialogState(() => endsAt = value),
                              );
                              // AlertDialog measures its content intrinsically.
                              // LayoutBuilder cannot answer intrinsic-size
                              // requests, which left only the modal barrier on
                              // Android and made the popup editor look blank.
                              final compact =
                                  MediaQuery.sizeOf(context).width < 720;
                              if (compact) {
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
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Title', 'العنوان'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: body,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Message', 'الرسالة'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: uploading
                              ? null
                              : () async {
                                  final picked = await ImagePicker().pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 94,
                                  );
                                  if (picked == null || !context.mounted) {
                                    return;
                                  }
                                  final validation =
                                      await _pickedCampaignImageError(
                                        context,
                                        picked,
                                      );
                                  dynamic bytes;
                                  if (validation == null) {
                                    try {
                                      bytes = await picked.readAsBytes();
                                    } catch (_) {
                                      if (context.mounted) {
                                        imageValidationError = abuText(
                                          context,
                                          'The selected image could not be read.',
                                          'تعذر قراءة الصورة المحددة.',
                                        );
                                      }
                                    }
                                  }
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    selectedImage = validation == null
                                        ? picked
                                        : null;
                                    selectedImageBytes = validation == null
                                        ? bytes
                                        : null;
                                    imageValidationError = validation;
                                    uploadError = null;
                                  });
                                },
                          icon: Icon(Icons.upload_rounded),
                          label: Text(
                            selectedImage == null
                                ? abuText(context, 'SELECT IMAGE', 'اختر صورة')
                                : selectedImage!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (selectedImage != null || image.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: abuText(
                            context,
                            'Remove upload',
                            'إزالة الصورة',
                          ),
                          onPressed: uploading
                              ? null
                              : () => setDialogState(() {
                                  selectedImage = null;
                                  selectedImageBytes = null;
                                  image.clear();
                                  uploadError = null;
                                }),
                          icon: Icon(Icons.close_rounded),
                        ),
                      ],
                    ],
                  ),
                  if (selectedImage != null ||
                      image.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _campaignImagePreview(
                      context: context,
                      imageUrl: image.text,
                      imageBytes: selectedImageBytes,
                      height: 210,
                    ),
                  ],
                  if (imageValidationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      imageValidationError!,
                      style: TextStyle(color: _red, height: 1.35),
                    ),
                  ],
                  if (uploadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      uploadError!,
                      style: TextStyle(color: _red, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: link,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Clickable link (optional)',
                        'الرابط القابل للنقر (اختياري)',
                      ),
                      helperText: abuText(
                        context,
                        'iamr.dev is automatically saved as https://iamr.dev',
                        'سيُحفظ iamr.dev تلقائياً بصيغة https://iamr.dev',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: label,
                    decoration: InputDecoration(
                      labelText: abuText(context, 'Button label', 'نص الزر'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (existing != null)
              TextButton.icon(
                onPressed: uploading
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (confirmationContext) => AlertDialog(
                            title: Text(
                              abuText(
                                confirmationContext,
                                'Reset launch popup?',
                                'إعادة ضبط نافذة البدء؟',
                              ),
                            ),
                            content: Text(
                              abuText(
                                confirmationContext,
                                'This removes the popup campaign from every device. You can create a new one later.',
                                'سيؤدي هذا إلى إزالة حملة النافذة من جميع الأجهزة. يمكنك إنشاء حملة جديدة لاحقاً.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(confirmationContext, false),
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
                                onPressed: () =>
                                    Navigator.pop(confirmationContext, true),
                                icon: const Icon(Icons.delete_forever_rounded),
                                label: Text(
                                  abuText(
                                    confirmationContext,
                                    'RESET',
                                    'إعادة ضبط',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && context.mounted) {
                          Navigator.pop(context, (imageUrl: '', reset: true));
                        }
                      },
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(abuText(context, 'RESET', 'إعادة ضبط')),
              ),
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(context),
              child: Text(abuText(context, 'CANCEL', 'إلغاء')),
            ),
            TextButton.icon(
              onPressed: uploading
                  ? null
                  : () => _showAdminAnnouncementPreview(
                      context,
                      title: title.text,
                      body: body.text,
                      imageUrl: image.text,
                      imageBytes: selectedImageBytes,
                      buttonLabel: label.text,
                    ),
              icon: Icon(Icons.visibility_rounded),
              label: Text(abuText(context, 'PREVIEW', 'معاينة')),
            ),
            FilledButton(
              onPressed: uploading
                  ? null
                  : () async {
                      final linkError =
                          link.text.trim().isNotEmpty &&
                          externalHttpUri(link.text) == null;
                      if (title.text.trim().isEmpty ||
                          body.text.trim().isEmpty ||
                          !endsAt.isAfter(startsAt) ||
                          linkError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              abuText(
                                context,
                                linkError ? 'Enter a valid clickable link.' : 'Add a title, message and valid schedule.',
                                linkError ? 'أدخل رابطاً صالحاً.' : 'أضف عنواناً ورسالة وجدولاً زمنياً صالحاً.',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      var finalImageUrl = image.text.trim();
                      if (selectedImage != null) {
                        setDialogState(() {
                          uploading = true;
                          uploadError = null;
                        });
                        try {
                          finalImageUrl = await repository
                              .uploadAnnouncementImage(selectedImage!);
                          if (finalImageUrl.trim().isEmpty) {
                            throw StateError('Empty image URL returned.');
                          }
                        } catch (error) {
                          if (!context.mounted) return;
                          setDialogState(() {
                            uploading = false;
                            uploadError = abuText(
                              context,
                              'The media server could not save this image. Check the server upload volume and try again. ${productionErrorMessage(error)}',
                              'تعذّر على خادم الوسائط حفظ هذه الصورة. تحقق من مساحة رفع الملفات في الخادم ثم حاول مجدداً. ${productionErrorMessage(error)}',
                            );
                          });
                          return;
                        }
                      }
                      if (context.mounted) {
                        Navigator.pop(context, (
                          imageUrl: finalImageUrl,
                          reset: false,
                        ));
                      }
                    },
              child: uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(abuText(context, 'SAVE', 'حفظ')),
            ),
          ],
        ),
      ),
    );
    if (submission == null || !context.mounted) return;
    if (submission.reset) {
      await _adminAction(
        context,
        repository.resetAnnouncement,
        abuText(context, 'Launch popup reset.', 'تمت إعادة ضبط نافذة البدء.'),
      );
      return;
    }
    await _adminAction(
      context,
      () => repository.saveAnnouncement(
        enabled: enabled,
        title: title.text,
        body: body.text,
        imageUrl: submission.imageUrl,
        linkUrl: link.text,
        buttonLabel: label.text,
        frequency: frequency,
        startsAt: startsAt,
        endsAt: endsAt,
      ),
      abuText(context, 'Launch popup saved.', 'تم حفظ نافذة البدء.'),
    );
  }

  Future<void> manageAchievements(BuildContext context) =>
      _showAdminDefinitionManager<AbuAchievement>(
        context: context,
        title: abuText(context, 'Achievement builder', 'منشئ الإنجازات'),
        emptyTitle: abuText(
          context,
          'No achievements configured',
          'لم يتم إعداد إنجازات',
        ),
        emptyBody: abuText(
          context,
          'Create the first goal fans can unlock.',
          'أنشئ أول هدف يمكن للجماهير فتحه.',
        ),
        stream: repository.watchManagedAchievements(),
        enabled: (item) => item.enabled,
        icon: (_) => Icons.emoji_events_rounded,
        label: (item) => item.title,
        detail: (item) => abuText(
          context,
          '${item.requirementTarget} target · +${item.rewardPoints} points',
          'هدف ${item.requirementTarget} · +${item.rewardPoints} نقطة',
        ),
        onToggle: (item, value) =>
            repository.setAchievementEnabled(item.id, value),
        onEdit: (item) =>
            _editAchievementDefinition(context, repository, existing: item),
        onCreate: () => _editAchievementDefinition(context, repository),
      );

  Future<void> manageLevels(
    BuildContext context,
  ) => _showAdminDefinitionManager<AbuLevel>(
    context: context,
    title: abuText(context, 'Level builder', 'منشئ المستويات'),
    emptyTitle: abuText(
      context,
      'No levels configured',
      'لم يتم إعداد مستويات',
    ),
    emptyBody: abuText(
      context,
      'Create a progression ladder for fan points.',
      'أنشئ سلم تقدم لنقاط الجماهير.',
    ),
    stream: repository.watchManagedLevels(),
    enabled: (item) => item.enabled,
    icon: (_) => Icons.military_tech_rounded,
    label: (item) => item.name,
    detail: (item) => abuText(
      context,
      '${item.minimumPoints}–${item.maximumPoints?.toString() ?? '∞'} points · ${item.perks.length} perks',
      '${item.minimumPoints}–${item.maximumPoints?.toString() ?? '∞'} نقطة · ${item.perks.length} مزايا',
    ),
    onToggle: (item, value) => repository.setLevelEnabled(item.id, value),
    onEdit: (item) => _editLevelDefinition(context, repository, existing: item),
    onCreate: () => _editLevelDefinition(context, repository),
  );

  Future<void> manageRewards(
    BuildContext context,
  ) => _showAdminDefinitionManager<AbuLoyaltyReward>(
    context: context,
    title: abuText(context, 'Reward catalogue', 'كتالوج المكافآت'),
    emptyTitle: abuText(
      context,
      'No rewards configured',
      'لم يتم إعداد مكافآت',
    ),
    emptyBody: abuText(
      context,
      'Add merchandise, digital rewards or fan experiences.',
      'أضف منتجات أو مكافآت رقمية أو تجارب للجماهير.',
    ),
    stream: repository.watchManagedRewards(),
    enabled: (item) => item.enabled,
    icon: (_) => Icons.redeem_rounded,
    label: (item) => item.title,
    detail: (item) => abuText(
      context,
      '${item.cost} loyalty points · ${item.unlimitedStock ? 'Unlimited' : '${item.stock} in stock'}',
      '${item.cost} نقطة ولاء · ${item.unlimitedStock ? 'غير محدود' : '${item.stock} في المخزون'}',
    ),
    onToggle: (item, value) => repository.setRewardEnabled(item.id, value),
    onEdit: (item) =>
        _editRewardDefinition(context, repository, existing: item),
    onCreate: () => _editRewardDefinition(context, repository),
  );

  Future<void> manageRedemptions(BuildContext context) =>
      _showAdminRedemptionManager(context, repository);

  Future<void> managePlayerCards(BuildContext context) =>
      createChallenge(context, initialKind: 'playerCard');

  Future<void> manageLeaderboardSeasons(BuildContext context) =>
      showDialog<void>(
        context: context,
        builder: (_) => _AdminLeaderboardSeasonsDialog(repository: repository),
      );

  Future<void> manageRoles(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) =>
        _AdminRolesDialog(repository: repository, currentUserId: profile.uid),
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

class _AdminLeaderboardSeasonsDialog extends StatefulWidget {
  const _AdminLeaderboardSeasonsDialog({required this.repository});

  final ProductionRepository repository;

  @override
  State<_AdminLeaderboardSeasonsDialog> createState() =>
      _AdminLeaderboardSeasonsDialogState();
}

class _AdminLeaderboardSeasonsDialogState
    extends State<_AdminLeaderboardSeasonsDialog> {
  late Future<List<LeaderboardSeason>> _seasons;

  @override
  void initState() {
    super.initState();
    _seasons = widget.repository.fetchAdminLeaderboardSeasons();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _seasons = widget.repository.fetchAdminLeaderboardSeasons();
    });
  }

  Future<void> _openEditor([LeaderboardSeason? season]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AdminLeaderboardSeasonEditorDialog(
        repository: widget.repository,
        season: season,
      ),
    );
    if (saved == true) _refresh();
  }

  String _date(DateTime? value) {
    if (value == null) return abuText(context, 'Not set', 'غير محدد');
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
    title: Text(abuText(context, 'Leaderboard seasons', 'مواسم الترتيب')),
    content: SizedBox(
      width: 720,
      height: math.min(MediaQuery.sizeOf(context).height * .68, 610),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            abuText(
              context,
              'Dates are shown in your local time. Automatic football discovery remains the fallback; saving a season here makes its dates a protected manual override.',
              'تُعرض التواريخ حسب توقيتك المحلي. يبقى الاكتشاف التلقائي لكرة القدم احتياطياً، وحفظ الموسم هنا يجعل تواريخه يدوية ومحمية.',
            ),
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<List<LeaderboardSeason>>(
              future: _seasons,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: abuText(
                      context,
                      'Seasons could not be loaded',
                      'تعذر تحميل المواسم',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final seasons = snapshot.data ?? const <LeaderboardSeason>[];
                if (seasons.isEmpty) {
                  return _ProductionEmpty(
                    icon: Icons.date_range_rounded,
                    title: abuText(
                      context,
                      'No seasons configured',
                      'لا توجد مواسم معدة',
                    ),
                    body: abuText(
                      context,
                      'Create the first leaderboard season.',
                      'أنشئ أول موسم للترتيب.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: seasons.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final season = seasons[index];
                      final manual = season.managementMode == 'manual';
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: season.active
                                ? _productionPrimary(context)
                                      .withValues(alpha: .65)
                                : _line,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              manual
                                  ? Icons.edit_calendar_rounded
                                  : Icons.auto_awesome_rounded,
                              color: manual
                                  ? _productionPrimary(context)
                                  : _blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        season.displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      _ChallengeMetaChip(
                                        icon: manual
                                            ? Icons.lock_outline_rounded
                                            : Icons.sync_rounded,
                                        label: manual
                                            ? abuText(context, 'MANUAL', 'يدوي')
                                            : abuText(
                                                context,
                                                'AUTOMATIC',
                                                'تلقائي',
                                              ),
                                      ),
                                      if (season.active)
                                        _LiveDot(
                                          text: abuText(
                                            context,
                                            'CURRENT',
                                            'الحالي',
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${season.id} · ${_date(season.startsAt)} → ${_date(season.endsAt)}',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: abuText(
                                context,
                                'Edit season',
                                'تعديل الموسم',
                              ),
                              onPressed: () => _openEditor(season),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'CLOSE', 'إغلاق')),
      ),
      FilledButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: Text(abuText(context, 'NEW SEASON', 'موسم جديد')),
      ),
    ],
  );
}

class _AdminLeaderboardSeasonEditorDialog extends StatefulWidget {
  const _AdminLeaderboardSeasonEditorDialog({
    required this.repository,
    this.season,
  });

  final ProductionRepository repository;
  final LeaderboardSeason? season;

  @override
  State<_AdminLeaderboardSeasonEditorDialog> createState() =>
      _AdminLeaderboardSeasonEditorDialogState();
}

class _AdminLeaderboardSeasonEditorDialogState
    extends State<_AdminLeaderboardSeasonEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _reason;
  late DateTime _startsAt;
  late DateTime _endsAt;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.season == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final season = widget.season;
    _id = TextEditingController(text: season?.id ?? '');
    _name = TextEditingController(text: season?.displayName ?? '');
    _reason = TextEditingController(
      text: season == null
          ? 'Created leaderboard season from Admin Studio.'
          : 'Updated leaderboard season from Admin Studio.',
    );
    _startsAt = (season?.startsAt ?? now).toLocal();
    _endsAt = (season?.endsAt ?? _startsAt.add(const Duration(days: 365)))
        .toLocal();
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _startsAt = selected;
      } else {
        _endsAt = selected;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_startsAt.isBefore(_endsAt)) {
      setState(() {
        _error = abuText(
          context,
          'The season start must be before its end.',
          'يجب أن تكون بداية الموسم قبل نهايته.',
        );
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveAdminLeaderboardSeason(
        id: _id.text,
        displayName: _name.text,
        startsAt: _startsAt,
        endsAt: _endsAt,
        reason: _reason.text,
        create: _creating,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = productionErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      _creating
          ? abuText(context, 'Create season', 'إنشاء موسم')
          : abuText(context, 'Edit season', 'تعديل الموسم'),
    ),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _id,
                enabled: _creating && !_saving,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Season ID', 'معرف الموسم'),
                  hintText: '2026-2027',
                ),
                validator: (value) {
                  final id = value?.trim() ?? '';
                  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$')
                      .hasMatch(id)) {
                    return abuText(
                      context,
                      'Use 1–50 letters, numbers, dots, underscores or hyphens.',
                      'استخدم 1–50 حرفاً أو رقماً أو نقطة أو شرطة.',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Display name', 'اسم العرض'),
                  hintText: '2026/27 Season',
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? abuText(
                        context,
                        'Enter a display name.',
                        'أدخل اسم العرض.',
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: true),
                      icon: const Icon(Icons.event_available_rounded),
                      label: Text(
                        '${abuText(context, 'START', 'البداية')}\n${_date(_startsAt)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickDate(start: false),
                      icon: const Icon(Icons.event_busy_rounded),
                      label: Text(
                        '${abuText(context, 'END', 'النهاية')}\n${_date(_endsAt)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                enabled: !_saving,
                maxLength: 255,
                decoration: InputDecoration(
                  labelText: abuText(context, 'Audit reason', 'سبب التعديل'),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? abuText(
                        context,
                        'Enter a short reason.',
                        'أدخل سبباً مختصراً.',
                      )
                    : null,
              ),
              if (!_creating) ...[
                const SizedBox(height: 4),
                Text(
                  abuText(
                    context,
                    'Saving explicitly changes this season to manual mode. Automatic discovery will no longer change its name or dates.',
                    'الحفظ يحول هذا الموسم إلى الوضع اليدوي، ولن يغير الاكتشاف التلقائي اسمه أو تواريخه.',
                  ),
                  style: TextStyle(color: _gold, fontSize: 12, height: 1.4),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: _red, height: 1.4)),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: Text(abuText(context, 'CANCEL', 'إلغاء')),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_rounded),
        label: Text(abuText(context, 'SAVE SEASON', 'حفظ الموسم')),
      ),
    ],
  );
}

class _AdminMembershipDialog extends StatefulWidget {
  const _AdminMembershipDialog({required this.repository});

  final ProductionRepository repository;

  @override
  State<_AdminMembershipDialog> createState() => _AdminMembershipDialogState();
}

class _AdminMembershipDialogState extends State<_AdminMembershipDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  late Future<List<AbuUserProfile>> _users;

  @override
  void initState() {
    super.initState();
    _users = widget.repository.fetchAdminUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _users = widget.repository.fetchAdminUsers(search: _search.text);
    });
  }

  void _queueSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  String _verificationDetails(BuildContext context, AbuUserProfile user) {
    if (!user.youtubeChannelLinked) {
      return abuText(context, 'YouTube not linked', 'يوتيوب غير مرتبط');
    }
    final details = <String>[
      user.isYouTubeMember
          ? abuText(context, 'Active paid member', 'عضو مدفوع نشط')
          : abuText(
              context,
              'Linked · not an active member',
              'مرتبط · ليس عضواً نشطاً',
            ),
      if (user.youtubeMembershipLevelId.isNotEmpty)
        abuText(
          context,
          'Level ${user.youtubeMembershipLevelId}',
          'المستوى ${user.youtubeMembershipLevelId}',
        ),
      if (user.youtubeMemberSince != null)
        abuText(
          context,
          'Member since ${_productionDate(user.youtubeMemberSince!)}',
          'عضو منذ ${_productionDate(user.youtubeMemberSince!)}',
        ),
      if (user.youtubeMembershipVerifiedAt != null)
        abuText(
          context,
          'Checked ${_productionDate(user.youtubeMembershipVerifiedAt!)}',
          'آخر تحقق ${_productionDate(user.youtubeMembershipVerifiedAt!)}',
        ),
    ];
    return details.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableContentHeight =
        media.size.height - media.padding.vertical - 190;
    final contentHeight = availableContentHeight.clamp(300.0, 720.0);
    return AlertDialog(
      key: const Key('admin-membership-snapshot-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      clipBehavior: Clip.antiAlias,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      title: Text(
        abuText(context, 'YouTube membership snapshot', 'لقطة عضويات يوتيوب'),
      ),
      content: SizedBox(
        width: 600,
        height: contentHeight,
        child: Column(
          children: [
            AdminYouTubeMembershipSnapshotCard(
              repository: widget.repository,
              onImported: _refresh,
            ),
            const SizedBox(height: 12),
            Text(
              abuText(
                context,
                'This complete admin-uploaded UTF-8 CSV/TSV is the membership authority. A user-submitted channel URL is only a claim: staff must approve it, and the channel ID must be active in this unexpired snapshot. Always replace it with a complete current export, never a partial list.',
                'ملف CSV/TSV الكامل الذي يرفعه المسؤول بترميز UTF-8 هو مصدر العضوية. رابط القناة الذي يرسله المستخدم هو مجرد طلب: يجب أن يعتمده الموظفون وأن يكون معرّف القناة نشطاً في هذه اللقطة غير المنتهية. استبدلها دائماً بقائمة حالية كاملة، وليس قائمة جزئية.',
              ),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('review-youtube-channel-claims'),
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _PendingYouTubeClaimsDialog(
                      repository: widget.repository,
                    ),
                  );
                  _refresh();
                },
                icon: const Icon(Icons.fact_check_rounded),
                label: Text(
                  abuText(
                    context,
                    'REVIEW PENDING CHANNEL CLAIMS',
                    'مراجعة طلبات القنوات المعلقة',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: _queueSearch,
              onSubmitted: (_) => _refresh(),
              decoration: InputDecoration(
                labelText: abuText(
                  context,
                  'Search name, username or email',
                  'ابحث بالاسم أو اسم المستخدم أو البريد',
                ),
                prefixIcon: const Icon(Icons.person_search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<AbuUserProfile>>(
                future: _users,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(productionErrorMessage(snapshot.error!)),
                    );
                  }
                  final users = snapshot.data ?? const <AbuUserProfile>[];
                  if (users.isEmpty) {
                    return _ProductionEmpty(
                      icon: Icons.people_outline_rounded,
                      title: abuText(
                        context,
                        'No matching users',
                        'لا يوجد مستخدمون مطابقون',
                      ),
                      body: abuText(
                        context,
                        'Try another name, username or email.',
                        'جرّب اسماً أو اسم مستخدم أو بريداً آخر.',
                      ),
                    );
                  }
                  return Scrollbar(
                    child: ListView.builder(
                      key: const Key('admin-membership-user-list'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final label = user.displayName.isNotEmpty
                            ? user.displayName
                            : user.username.isNotEmpty
                            ? user.username
                            : user.email;
                        return ListTile(
                          leading: Icon(
                            user.isYouTubeMember
                                ? Icons.workspace_premium_rounded
                                : user.youtubeChannelLinked
                                ? Icons.link_rounded
                                : Icons.link_off_rounded,
                            color: user.isYouTubeMember
                                ? _gold
                                : user.youtubeChannelLinked
                                ? _productionPrimary(context)
                                : _muted,
                          ),
                          title: Text(label),
                          subtitle: Text(
                            <String>[
                              if (user.username.isNotEmpty) '@${user.username}',
                              if (user.email.isNotEmpty) user.email,
                              _verificationDetails(context, user),
                            ].join(' · '),
                          ),
                          trailing: Text(
                            user.isYouTubeMember
                                ? abuText(context, 'VERIFIED', 'موثّق')
                                : user.youtubeChannelLinked
                                ? abuText(context, 'LINKED', 'مرتبط')
                                : abuText(context, 'NOT LINKED', 'غير مرتبط'),
                            style: TextStyle(
                              color: user.isYouTubeMember
                                  ? _gold
                                  : user.youtubeChannelLinked
                                  ? _productionPrimary(context)
                                  : _muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(88, 46)),
          onPressed: () => Navigator.pop(context),
          child: Text(abuText(context, 'DONE', 'تم')),
        ),
      ],
    );
  }
}

class _PendingYouTubeClaimsDialog extends StatefulWidget {
  const _PendingYouTubeClaimsDialog({required this.repository});

  final ProductionRepository repository;

  @override
  State<_PendingYouTubeClaimsDialog> createState() =>
      _PendingYouTubeClaimsDialogState();
}

class _PendingYouTubeClaimsDialogState
    extends State<_PendingYouTubeClaimsDialog> {
  late Future<List<YouTubeChannelClaim>> _claims;
  String? _busyClaimId;
  String _claimFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _claims = widget.repository.fetchYouTubeChannelClaims(status: _claimFilter);
  }

  Future<void> _review(
    YouTubeChannelClaim claim,
    YouTubeChannelClaimDecision decision,
  ) async {
    final reason = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          decision == YouTubeChannelClaimDecision.approve
              ? abuText(
                  dialogContext,
                  'Approve channel claim?',
                  'اعتماد طلب القناة؟',
                )
              : decision == YouTubeChannelClaimDecision.revoke
              ? abuText(
                  dialogContext,
                  'Revoke channel claim?',
                  'إلغاء اعتماد طلب القناة؟',
                )
              : abuText(
                  dialogContext,
                  'Reject channel claim?',
                  'رفض طلب القناة؟',
                ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              claim.youtubeChannelId,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              decision == YouTubeChannelClaimDecision.approve
                  ? abuText(
                      dialogContext,
                      'Approval succeeds only if this exact ID is active in the latest unexpired complete CSV. Confirm that you independently verified the channel belongs to this app user.',
                      'ينجح الاعتماد فقط إذا كان هذا المعرّف نفسه نشطاً في أحدث ملف CSV كامل وغير منتهي. أكد أنك تحققت بشكل مستقل من أن القناة تخص مستخدم التطبيق هذا.',
                    )
                  : decision == YouTubeChannelClaimDecision.revoke
                  ? abuText(
                      dialogContext,
                      'Revoking removes membership benefits immediately. Explain why this approved claim is being revoked.',
                      'يلغي هذا مزايا العضوية فوراً. اشرح سبب إلغاء اعتماد هذا الطلب.',
                    )
                  : abuText(
                      dialogContext,
                      'Explain why this claim is being rejected.',
                      'اشرح سبب رفض هذا الطلب.',
                    ),
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: abuText(
                  dialogContext,
                  'Required audit reason',
                  'سبب التدقيق المطلوب',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(abuText(dialogContext, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length < 3) return;
              Navigator.pop(dialogContext, true);
            },
            child: Text(
              decision == YouTubeChannelClaimDecision.approve
                  ? abuText(dialogContext, 'APPROVE', 'اعتماد')
                  : decision == YouTubeChannelClaimDecision.revoke
                  ? abuText(dialogContext, 'REVOKE', 'إلغاء الاعتماد')
                  : abuText(dialogContext, 'REJECT', 'رفض'),
            ),
          ),
        ],
      ),
    );
    final auditReason = reason.text.trim();
    reason.dispose();
    if (approved != true || !mounted) return;

    setState(() => _busyClaimId = claim.id);
    try {
      await widget.repository.decideYouTubeChannelClaim(
        claimId: claim.id,
        decision: decision,
        reason: auditReason,
      );
      if (!mounted) return;
      setState(() {
        _busyClaimId = null;
        _reload();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyClaimId = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('pending-youtube-channel-claims-dialog'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    title: Text(abuText(context, 'Channel claims', 'طلبات القنوات')),
    content: SizedBox(
      width: 640,
      height: math.min(MediaQuery.sizeOf(context).height * .72, 650),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'pending',
                  icon: const Icon(Icons.pending_actions_rounded),
                  label: Text(abuText(context, 'Pending', 'معلقة')),
                ),
                ButtonSegment(
                  value: 'approved',
                  icon: const Icon(Icons.verified_rounded),
                  label: Text(abuText(context, 'Approved', 'معتمدة')),
                ),
              ],
              selected: {_claimFilter},
              onSelectionChanged: _busyClaimId != null
                  ? null
                  : (selection) {
                      final selected = selection.isEmpty
                          ? null
                          : selection.first;
                      if (selected == null || selected == _claimFilter) return;
                      setState(() {
                        _claimFilter = selected;
                        _reload();
                      });
                    },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<YouTubeChannelClaim>>(
              future: _claims,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(productionErrorMessage(snapshot.error!)),
                  );
                }
                final claims = snapshot.data ?? const <YouTubeChannelClaim>[];
                if (claims.isEmpty) {
                  final pending = _claimFilter == 'pending';
                  return _ProductionEmpty(
                    icon: Icons.verified_rounded,
                    title: abuText(
                      context,
                      pending ? 'No pending claims' : 'No approved claims',
                      pending ? 'لا توجد طلبات معلقة' : 'لا توجد طلبات معتمدة',
                    ),
                    body: abuText(
                      context,
                      pending
                          ? 'New user-submitted channel IDs will appear here.'
                          : 'Approved and lapsed claims will appear here for review or revocation.',
                      pending
                          ? 'ستظهر معرّفات القنوات الجديدة التي يرسلها المستخدمون هنا.'
                          : 'ستظهر الطلبات المعتمدة والمنتهية هنا للمراجعة أو إلغاء الاعتماد.',
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: claims.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final claim = claims[index];
                    final busy = _busyClaimId == claim.id;
                    final identity = claim.displayName.isNotEmpty
                        ? claim.displayName
                        : claim.username.isNotEmpty
                        ? claim.username
                        : claim.email.isNotEmpty
                        ? claim.email
                        : claim.youtubeChannelId;
                    final pending = _claimFilter == 'pending';
                    final channelUri = Uri.https(
                      'www.youtube.com',
                      '/channel/${claim.youtubeChannelId}',
                    );
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        Icons.smart_display_rounded,
                        color: _gold,
                      ),
                      title: Text(identity),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (claim.username.isNotEmpty)
                            Text('@${claim.username}'),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              alignment: AlignmentDirectional.centerStart,
                            ),
                            onPressed: () => launchUrl(
                              channelUri,
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                            ),
                            label: Text(
                              claim.youtubeChannelId,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!pending)
                            Text(
                              claim.status.name.toUpperCase(),
                              style: TextStyle(
                                color: claim.isActive
                                    ? _productionPrimary(context)
                                    : _gold,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: busy
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : pending
                          ? Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: abuText(context, 'Reject', 'رفض'),
                                  onPressed: () => _review(
                                    claim,
                                    YouTubeChannelClaimDecision.reject,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _red,
                                  ),
                                ),
                                IconButton(
                                  tooltip: abuText(
                                    context,
                                    'Approve',
                                    'اعتماد',
                                  ),
                                  onPressed: () => _review(
                                    claim,
                                    YouTubeChannelClaimDecision.approve,
                                  ),
                                  icon: Icon(
                                    Icons.check_rounded,
                                    color: _productionPrimary(context),
                                  ),
                                ),
                              ],
                            )
                          : IconButton(
                              tooltip: abuText(
                                context,
                                'Revoke approval',
                                'إلغاء الاعتماد',
                              ),
                              onPressed: () => _review(
                                claim,
                                YouTubeChannelClaimDecision.revoke,
                              ),
                              icon: const Icon(
                                Icons.link_off_rounded,
                                color: _red,
                              ),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'DONE', 'تم')),
      ),
    ],
  );
}

class _AdminRolesDialog extends StatefulWidget {
  const _AdminRolesDialog({
    required this.repository,
    required this.currentUserId,
  });

  final ProductionRepository repository;
  final String currentUserId;

  @override
  State<_AdminRolesDialog> createState() => _AdminRolesDialogState();
}

class _AdminRolesDialogState extends State<_AdminRolesDialog> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  late Future<List<AbuUserProfile>> _users;
  String? _busyUserId;

  static const _roles = <String>[
    'fan',
    'member',
    'moderator',
    'admin',
    'superAdmin',
  ];

  @override
  void initState() {
    super.initState();
    _users = widget.repository.fetchAdminUsers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _queueSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _users = widget.repository.fetchAdminUsers(search: _search.text);
    });
  }

  String _roleLabel(BuildContext context, String role) => switch (role) {
    'member' => abuText(context, 'Member', 'عضو'),
    'moderator' => abuText(context, 'Moderator', 'مشرف'),
    'admin' => abuText(context, 'Admin', 'مدير'),
    'superAdmin' => abuText(context, 'Super admin', 'مدير أعلى'),
    _ => abuText(context, 'Fan', 'مشجع'),
  };

  Future<void> _setRole(AbuUserProfile user, String role) async {
    setState(() => _busyUserId = user.uid);
    try {
      await widget.repository.setUserRole(uid: user.uid, role: role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abuText(context, 'User role updated.', 'تم تحديث دور المستخدم.'),
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _setSuspended(AbuUserProfile user) async {
    setState(() => _busyUserId = user.uid);
    try {
      await widget.repository.setUserSuspension(
        uid: user.uid,
        suspended: !user.suspended,
      );
      if (!mounted) return;
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      abuText(context, 'Roles & administrators', 'الأدوار والمشرفون'),
    ),
    content: SizedBox(
      width: 680,
      height: math.min(MediaQuery.sizeOf(context).height * .72, 620),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: _queueSearch,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _refresh(),
            decoration: InputDecoration(
              labelText: abuText(
                context,
                'Search name, username or email',
                'ابحث بالاسم أو اسم المستخدم أو البريد',
              ),
              prefixIcon: const Icon(Icons.person_search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? IconButton(
                      tooltip: abuText(context, 'Refresh', 'تحديث'),
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    )
                  : IconButton(
                      tooltip: abuText(context, 'Clear', 'مسح'),
                      onPressed: () {
                        _search.clear();
                        _refresh();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<AbuUserProfile>>(
              future: _users,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: abuText(
                      context,
                      'Users could not be loaded',
                      'تعذر تحميل المستخدمين',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final users = snapshot.data ?? const <AbuUserProfile>[];
                if (users.isEmpty) {
                  return _ProductionEmpty(
                    icon: Icons.people_outline_rounded,
                    title: abuText(
                      context,
                      'No matching users',
                      'لا يوجد مستخدمون مطابقون',
                    ),
                    body: abuText(
                      context,
                      'Try another name, username or email.',
                      'جرّب اسماً أو اسم مستخدم أو بريداً آخر.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildUserCard(users[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'DONE', 'تم')),
      ),
    ],
  );

  Widget _buildUserCard(AbuUserProfile user) {
    final busy = _busyUserId == user.uid;
    final isSelf = user.uid == widget.currentUserId;
    final name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.username.trim().isNotEmpty
        ? user.username.trim()
        : user.email.trim().isNotEmpty
        ? user.email.trim()
        : abuText(context, 'Unnamed account', 'حساب بلا اسم');
    final identity = <String>[
      if (user.username.trim().isNotEmpty) '@${user.username.trim()}',
      if (user.email.trim().isNotEmpty) user.email.trim(),
      if (user.supportedTeam.trim().isNotEmpty)
        '${user.countryFlag} ${user.supportedTeam.trim()}',
    ].join(' · ');
    final avatarUrl = user.avatarUrl.trim();
    final selectedRole = _roles.contains(user.role) ? user.role : 'fan';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: user.suspended ? _red.withValues(alpha: .5) : _line,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                foregroundImage: avatarUrl.isEmpty
                    ? null
                    : NetworkImage(avatarUrl),
                backgroundColor: user.suspended
                    ? _red.withValues(alpha: .18)
                    : _surface,
                child: avatarUrl.isEmpty
                    ? Text(name.characters.first.toUpperCase())
                    : null,
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
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (isSelf)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: Text(
                              abuText(context, 'YOU', 'أنت'),
                              style: TextStyle(
                                color: _productionPrimary(context),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (identity.isNotEmpty)
                      Text(
                        identity,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (user.suspended)
                Text(
                  abuText(context, 'BLOCKED', 'محظور'),
                  style: TextStyle(
                    color: _red,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: abuText(context, 'Role', 'الدور'),
                  ),
                  items: _roles
                      .map(
                        (role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(_roleLabel(context, role)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: isSelf || busy
                      ? null
                      : (role) {
                          if (role != null && role != selectedRole) {
                            _setRole(user, role);
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: user.suspended
                    ? abuText(
                        context,
                        'Reactivate account',
                        'إعادة تفعيل الحساب',
                      )
                    : abuText(context, 'Suspend account', 'إيقاف الحساب'),
                onPressed: isSelf || busy ? null : () => _setSuspended(user),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        user.suspended
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        color: user.suspended
                            ? _productionPrimary(context)
                            : _red,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showAdminRedemptionManager(
  BuildContext context,
  ProductionRepository repository,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(
      abuText(context, 'Redemption operations', 'إدارة طلبات الاستبدال'),
    ),
    content: SizedBox(
      width: 860,
      height: 580,
      child: StreamBuilder<List<AbuRewardRedemption>>(
        stream: repository.watchManagedRedemptions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ProductionEmpty(
              icon: Icons.cloud_off_rounded,
              title: abuText(
                context,
                'Redemptions unavailable',
                'طلبات الاستبدال غير متاحة',
              ),
              body: productionErrorMessage(snapshot.error!),
            );
          }
          final redemptions = snapshot.data ?? const <AbuRewardRedemption>[];
          if (redemptions.isEmpty) {
            return _ProductionEmpty(
              icon: Icons.receipt_long_rounded,
              title: abuText(
                context,
                'No redemption requests',
                'لا توجد طلبات استبدال',
              ),
              body: abuText(
                context,
                'New requests will appear here as soon as fans redeem a reward.',
                'ستظهر الطلبات الجديدة هنا فور استبدال الجماهير لمكافأة.',
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) => ListView.separated(
              itemCount: redemptions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _AdminRedemptionTile(
                redemption: redemptions[index],
                repository: repository,
                compact: constraints.maxWidth < 700,
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(abuText(context, 'DONE', 'تم')),
      ),
    ],
  ),
);

class _AdminRedemptionTile extends StatelessWidget {
  const _AdminRedemptionTile({
    required this.redemption,
    required this.repository,
    required this.compact,
  });

  final AbuRewardRedemption redemption;
  final ProductionRepository repository;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _redemptionStatusColor(context, redemption.status);
    final userLabel = redemption.userDisplayName.isEmpty
        ? abuText(context, 'Unknown user', 'مستخدم غير معروف')
        : redemption.userDisplayName;
    final status = _ChallengeMetaChip(
      icon: redemption.status == 'fulfilled'
          ? Icons.check_circle_rounded
          : Icons.schedule_rounded,
      label: _redemptionStatus(context, redemption.status),
      color: color,
    );
    final editButton = IconButton.filledTonal(
      tooltip: abuText(context, 'Update status', 'تحديث الحالة'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _RedemptionStatusDialog(
          repository: repository,
          redemption: redemption,
        ),
      ),
      icon: Icon(Icons.edit_note_rounded),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    redemption.rewardTitle,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                status,
              ],
            ),
            const SizedBox(height: 7),
            Text(userLabel, style: TextStyle(color: _muted)),
            Text(
              '${_productionDate(redemption.createdAt)} · ${redemption.cost} PTS',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            if (redemption.note.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                redemption.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            Align(alignment: AlignmentDirectional.centerEnd, child: editButton),
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(Icons.redeem_rounded, color: color),
      ),
      title: Text(
        redemption.rewardTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          userLabel,
          '${_productionDate(redemption.createdAt)} · ${redemption.cost} PTS',
          if (redemption.note.isNotEmpty) redemption.note,
        ].join('\n'),
        maxLines: redemption.note.isEmpty ? 2 : 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [status, const SizedBox(width: 8), editButton],
      ),
    );
  }
}

class _RedemptionStatusDialog extends StatefulWidget {
  const _RedemptionStatusDialog({
    required this.repository,
    required this.redemption,
  });

  final ProductionRepository repository;
  final AbuRewardRedemption redemption;

  @override
  State<_RedemptionStatusDialog> createState() =>
      _RedemptionStatusDialogState();
}

class _RedemptionStatusDialogState extends State<_RedemptionStatusDialog> {
  static const statuses = <String>[
    'pending',
    'contacted',
    'fulfilled',
    'cancelled',
  ];

  late String status;
  late final TextEditingController note;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    status = statuses.contains(widget.redemption.status)
        ? widget.redemption.status
        : 'pending';
    note = TextEditingController(text: widget.redemption.note);
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.repository.updateRedemptionStatus(
        widget.redemption.id,
        status,
        note: note.text.trim(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'Redemption status updated.',
              'تم تحديث حالة طلب الاستبدال.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(abuText(context, 'Update redemption', 'تحديث طلب الاستبدال')),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.redemption.rewardTitle,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: InputDecoration(
              labelText: abuText(context, 'Status', 'الحالة'),
            ),
            items: statuses
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_redemptionStatus(context, value)),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) => setState(() => status = value ?? status),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            enabled: !saving,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: abuText(
                context,
                'Admin note · optional',
                'ملاحظة المشرف · اختيارية',
              ),
              hintText: abuText(
                context,
                'Add fulfilment or delivery details.',
                'أضف تفاصيل التنفيذ أو التسليم.',
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(abuText(context, 'CANCEL', 'إلغاء')),
      ),
      FilledButton.icon(
        onPressed: saving ? null : _save,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.save_rounded),
        label: Text(abuText(context, 'SAVE STATUS', 'حفظ الحالة')),
      ),
    ],
  );
}

Future<void> _showAdminDefinitionManager<T>({
  required BuildContext context,
  required String title,
  required String emptyTitle,
  required String emptyBody,
  required Stream<List<T>> stream,
  required bool Function(T item) enabled,
  required IconData Function(T item) icon,
  required String Function(T item) label,
  required String Function(T item) detail,
  required Future<void> Function(T item, bool value) onToggle,
  required Future<void> Function(T item) onEdit,
  required Future<void> Function() onCreate,
  Future<void> Function(T item)? onDelete,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 760,
      height: 560,
      child: StreamBuilder<List<T>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ProductionEmpty(
              icon: Icons.cloud_off_rounded,
              title: abuText(
                context,
                'Catalogue unavailable',
                'الكتالوج غير متاح',
              ),
              body: productionErrorMessage(snapshot.error!),
            );
          }
          final items = snapshot.data ?? <T>[];
          if (items.isEmpty) {
            return _ProductionEmpty(
              icon: Icons.tune_rounded,
              title: emptyTitle,
              body: emptyBody,
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final deleteItem = onDelete;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _productionPrimary(context)
                      .withValues(alpha: .1),
                  child: Icon(icon(item), color: _productionPrimary(context)),
                ),
                title: Text(
                  label(item).trim().isEmpty
                      ? abuText(context, 'Untitled', 'بلا عنوان')
                      : label(item),
                ),
                subtitle: Text(detail(item)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch.adaptive(
                      value: enabled(item),
                      onChanged: (value) async {
                        try {
                          await onToggle(item, value);
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(productionErrorMessage(error)),
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      tooltip: abuText(context, 'Edit', 'تعديل'),
                      onPressed: () => onEdit(item),
                      icon: Icon(Icons.edit_rounded),
                    ),
                    if (deleteItem != null)
                      IconButton(
                        tooltip: abuText(context, 'Delete', 'حذف'),
                        color: _red,
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: dialogContext,
                            builder: (confirmationContext) => AlertDialog(
                              title: Text(
                                abuText(
                                  confirmationContext,
                                  'Delete ${label(item)}?',
                                  'حذف ${label(item)}؟',
                                ),
                              ),
                              content: Text(
                                abuText(
                                  confirmationContext,
                                  'This permanently removes an unclaimed Player Card. Cards already collected by fans must be disabled instead.',
                                  'يحذف هذا بطاقة اللاعب غير المُطالَب بها نهائياً. يجب تعطيل البطاقات التي جمعها المشجعون بدلاً من حذفها.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(confirmationContext, false),
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
                                  onPressed: () =>
                                      Navigator.pop(confirmationContext, true),
                                  icon: const Icon(Icons.delete_rounded),
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
                            await deleteItem(item);
                          } catch (error) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(productionErrorMessage(error)),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(abuText(dialogContext, 'CLOSE', 'إغلاق')),
      ),
      FilledButton.icon(
        onPressed: onCreate,
        icon: Icon(Icons.add_rounded),
        label: Text(abuText(dialogContext, 'CREATE NEW', 'إنشاء جديد')),
      ),
    ],
  ),
);

Future<void> _saveAdminDefinition(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(success)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(productionErrorMessage(error))));
  }
}

List<String> _adminLines(String value) => value
    .split('\n')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

Future<void> _editAchievementDefinition(
  BuildContext context,
  ProductionRepository repository, {
  AbuAchievement? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final titleAr = TextEditingController(text: existing?.titleAr ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final descriptionAr = TextEditingController(
    text: existing?.descriptionAr ?? '',
  );
  final icon = TextEditingController(
    text: existing?.iconName ?? 'emoji_events',
  );
  final target = TextEditingController(
    text: '${existing?.requirementTarget ?? 10}',
  );
  final reward = TextEditingController(
    text: '${existing?.rewardPoints ?? 100}',
  );
  final levelUnlock = TextEditingController(text: existing?.levelUnlock ?? '');
  final sortOrder = TextEditingController(text: '${existing?.sortOrder ?? 0}');
  var category = existing?.category ?? 'engagement';
  var requirementType = existing?.requirementType ?? 'totalPoints';
  var secret = existing?.isSecret ?? false;
  var enabled = existing?.enabled ?? true;
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          existing == null
              ? abuText(context, 'Create achievement', 'إنشاء إنجاز')
              : abuText(context, 'Edit achievement', 'تعديل الإنجاز'),
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AdminBilingualFields(
                  english: title,
                  arabic: titleAr,
                  englishLabel: abuText(
                    context,
                    'Title · English',
                    'العنوان · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Title · Arabic',
                    'العنوان · العربية',
                  ),
                ),
                const SizedBox(height: 10),
                _AdminBilingualFields(
                  english: description,
                  arabic: descriptionAr,
                  englishLabel: abuText(
                    context,
                    'Description · English',
                    'الوصف · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Description · Arabic',
                    'الوصف · العربية',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: icon,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Material icon name',
                      'اسم أيقونة Material',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: abuText(context, 'Category', 'الفئة'),
                        ),
                        items:
                            const [
                                  'engagement',
                                  'predictions',
                                  'challenges',
                                  'streak',
                                  'community',
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => setDialogState(
                          () => category = value ?? 'engagement',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: requirementType,
                        decoration: InputDecoration(
                          labelText: abuText(
                            context,
                            'Progress rule',
                            'قاعدة التقدم',
                          ),
                        ),
                        items:
                            const [
                                  'totalPoints',
                                  'seasonPoints',
                                  'monthlyPoints',
                                  'streak',
                                  'playerCards',
                                  'predictions',
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => setDialogState(
                          () => requirementType = value ?? 'totalPoints',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _AdminNumberRow(
                  fields: [
                    (target, abuText(context, 'Target', 'الهدف')),
                    (
                      reward,
                      abuText(context, 'Reward points', 'نقاط المكافأة'),
                    ),
                    (sortOrder, abuText(context, 'Sort order', 'الترتيب')),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: levelUnlock,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Required level ID (optional)',
                      'معرّف المستوى المطلوب (اختياري)',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: secret,
                  onChanged: (value) => setDialogState(() => secret = value),
                  title: Text(
                    abuText(context, 'Secret achievement', 'إنجاز سري'),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                  title: Text(abuText(context, 'Enabled', 'مفعّل')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty ||
                  int.tryParse(target.text) == null ||
                  int.tryParse(reward.text) == null ||
                  int.tryParse(sortOrder.text) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      abuText(
                        context,
                        'Add a title and valid numeric values.',
                        'أضف عنواناً وقيماً رقمية صالحة.',
                      ),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(abuText(context, 'SAVE', 'حفظ')),
          ),
        ],
      ),
    ),
  );
  if (submit == true && context.mounted) {
    final model = AbuAchievement(
      id: existing?.id ?? '',
      title: title.text,
      titleAr: titleAr.text,
      description: description.text,
      descriptionAr: descriptionAr.text,
      iconName: icon.text.trim().isEmpty ? 'emoji_events' : icon.text.trim(),
      category: category,
      requirementType: requirementType,
      requirementTarget: int.tryParse(target.text) ?? 0,
      rewardPoints: int.tryParse(reward.text) ?? 0,
      levelUnlock: levelUnlock.text,
      isSecret: secret,
      enabled: enabled,
      sortOrder: int.tryParse(sortOrder.text) ?? 0,
    );
    await _saveAdminDefinition(
      context,
      () => repository.saveAchievement(model),
      abuText(context, 'Achievement saved.', 'تم حفظ الإنجاز.'),
    );
  }
  for (final controller in [
    title,
    titleAr,
    description,
    descriptionAr,
    icon,
    target,
    reward,
    levelUnlock,
    sortOrder,
  ]) {
    controller.dispose();
  }
}

class _AdminBilingualFields extends StatelessWidget {
  const _AdminBilingualFields({
    required this.english,
    required this.arabic,
    required this.englishLabel,
    required this.arabicLabel,
    this.maxLines = 1,
  });

  final TextEditingController english;
  final TextEditingController arabic;
  final String englishLabel;
  final String arabicLabel;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fields = [
        TextField(
          controller: english,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: englishLabel),
        ),
        TextField(
          controller: arabic,
          maxLines: maxLines,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(labelText: arabicLabel),
        ),
      ];
      if (constraints.maxWidth < 560) {
        return Column(
          children: [fields.first, const SizedBox(height: 10), fields.last],
        );
      }
      return Row(
        children: [
          Expanded(child: fields.first),
          const SizedBox(width: 10),
          Expanded(child: fields.last),
        ],
      );
    },
  );
}

class _AdminNumberRow extends StatelessWidget {
  const _AdminNumberRow({required this.fields});
  final List<(TextEditingController, String)> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final children = fields
          .map(
            (field) => TextField(
              controller: field.$1,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: field.$2),
            ),
          )
          .toList(growable: false);
      if (constraints.maxWidth < 560) {
        return Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            Expanded(child: children[index]),
            if (index != children.length - 1) const SizedBox(width: 10),
          ],
        ],
      );
    },
  );
}

Future<void> _editLevelDefinition(
  BuildContext context,
  ProductionRepository repository, {
  AbuLevel? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final nameAr = TextEditingController(text: existing?.nameAr ?? '');
  final minimum = TextEditingController(
    text: '${existing?.minimumPoints ?? 0}',
  );
  final maximum = TextEditingController(
    text: existing?.maximumPoints?.toString() ?? '',
  );
  final perks = TextEditingController(text: existing?.perks.join('\n') ?? '');
  final perksAr = TextEditingController(
    text: existing?.perksAr.join('\n') ?? '',
  );
  final icon = TextEditingController(
    text: existing?.iconName ?? 'military_tech',
  );
  final color = TextEditingController(text: existing?.color ?? 'C8FF38');
  final sortOrder = TextEditingController(text: '${existing?.sortOrder ?? 0}');
  var enabled = existing?.enabled ?? true;
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          existing == null
              ? abuText(context, 'Create level', 'إنشاء مستوى')
              : abuText(context, 'Edit level', 'تعديل المستوى'),
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AdminBilingualFields(
                  english: name,
                  arabic: nameAr,
                  englishLabel: abuText(
                    context,
                    'Name · English',
                    'الاسم · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Name · Arabic',
                    'الاسم · العربية',
                  ),
                ),
                const SizedBox(height: 10),
                _AdminNumberRow(
                  fields: [
                    (
                      minimum,
                      abuText(context, 'Minimum points', 'الحد الأدنى للنقاط'),
                    ),
                    (
                      maximum,
                      abuText(
                        context,
                        'Maximum · blank for none',
                        'الحد الأعلى · اتركه فارغاً',
                      ),
                    ),
                    (sortOrder, abuText(context, 'Sort order', 'الترتيب')),
                  ],
                ),
                const SizedBox(height: 10),
                _AdminBilingualFields(
                  english: perks,
                  arabic: perksAr,
                  englishLabel: abuText(
                    context,
                    'Perks · one per line',
                    'المزايا · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Arabic perks · one per line',
                    'المزايا · العربية',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 10),
                _AdminBilingualFields(
                  english: icon,
                  arabic: color,
                  englishLabel: abuText(
                    context,
                    'Material icon name',
                    'اسم أيقونة Material',
                  ),
                  arabicLabel: abuText(context, 'Hex colour', 'رمز اللون'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                  title: Text(abuText(context, 'Enabled', 'مفعّل')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              final min = int.tryParse(minimum.text);
              final max = maximum.text.trim().isEmpty
                  ? null
                  : int.tryParse(maximum.text);
              if (name.text.trim().isEmpty ||
                  min == null ||
                  (maximum.text.trim().isNotEmpty && max == null) ||
                  (max != null && max < min)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      abuText(
                        context,
                        'Add a name and a valid point range.',
                        'أضف اسماً ونطاق نقاط صالحاً.',
                      ),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(abuText(context, 'SAVE', 'حفظ')),
          ),
        ],
      ),
    ),
  );
  if (submit == true && context.mounted) {
    final model = AbuLevel(
      id: existing?.id ?? '',
      name: name.text,
      nameAr: nameAr.text,
      minimumPoints: int.tryParse(minimum.text) ?? 0,
      maximumPoints: maximum.text.trim().isEmpty
          ? null
          : int.tryParse(maximum.text),
      perks: _adminLines(perks.text),
      perksAr: _adminLines(perksAr.text),
      iconName: icon.text.trim().isEmpty ? 'military_tech' : icon.text.trim(),
      color: color.text.replaceAll('#', '').trim().isEmpty
          ? 'C8FF38'
          : color.text.replaceAll('#', '').trim(),
      enabled: enabled,
      sortOrder: int.tryParse(sortOrder.text) ?? 0,
    );
    await _saveAdminDefinition(
      context,
      () => repository.saveLevel(model),
      abuText(context, 'Level saved.', 'تم حفظ المستوى.'),
    );
  }
  for (final controller in [
    name,
    nameAr,
    minimum,
    maximum,
    perks,
    perksAr,
    icon,
    color,
    sortOrder,
  ]) {
    controller.dispose();
  }
}

Future<void> _editRewardDefinition(
  BuildContext context,
  ProductionRepository repository, {
  AbuLoyaltyReward? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final titleAr = TextEditingController(text: existing?.titleAr ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final descriptionAr = TextEditingController(
    text: existing?.descriptionAr ?? '',
  );
  final image = TextEditingController(text: existing?.imageUrl ?? '');
  final cost = TextEditingController(text: '${existing?.cost ?? 500}');
  final stock = TextEditingController(text: '${existing?.stock ?? 10}');
  final perUserLimit = TextEditingController(
    text: '${existing?.perUserLimit ?? 1}',
  );
  var category = existing?.category ?? 'general';
  var fulfilmentType = existing?.fulfilmentType ?? 'manual';
  var memberOnly = existing?.memberOnly ?? false;
  var unlimitedStock = existing?.unlimitedStock ?? false;
  var enabled = existing?.enabled ?? true;
  var scheduled = existing?.startsAt != null || existing?.endsAt != null;
  var startsAt = existing?.startsAt ?? DateTime.now();
  var endsAt = existing?.endsAt ?? DateTime.now().add(const Duration(days: 30));
  XFile? selectedImage;
  dynamic selectedImageBytes;
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          existing == null
              ? abuText(context, 'Create loyalty reward', 'إنشاء مكافأة ولاء')
              : abuText(context, 'Edit loyalty reward', 'تعديل مكافأة الولاء'),
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AdminBilingualFields(
                  english: title,
                  arabic: titleAr,
                  englishLabel: abuText(
                    context,
                    'Title · English',
                    'العنوان · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Title · Arabic',
                    'العنوان · العربية',
                  ),
                ),
                const SizedBox(height: 10),
                _AdminBilingualFields(
                  english: description,
                  arabic: descriptionAr,
                  englishLabel: abuText(
                    context,
                    'Description · English',
                    'الوصف · الإنجليزية',
                  ),
                  arabicLabel: abuText(
                    context,
                    'Description · Arabic',
                    'الوصف · العربية',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selection = await _selectAdminImage(context);
                    if (selection == null || !context.mounted) return;
                    setDialogState(() {
                      selectedImage = selection.file;
                      selectedImageBytes = selection.bytes;
                    });
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    selectedImage == null
                        ? abuText(
                            context,
                            'SELECT REWARD IMAGE',
                            'اختر صورة المكافأة',
                          )
                        : selectedImage!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selectedImage != null || image.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _campaignImagePreview(
                    context: context,
                    imageUrl: image.text,
                    imageBytes: selectedImageBytes,
                    height: 180,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: abuText(context, 'Category', 'الفئة'),
                        ),
                        items:
                            const [
                                  'general',
                                  'digital',
                                  'merchandise',
                                  'experience',
                                  'members',
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) =>
                            setDialogState(() => category = value ?? 'general'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: fulfilmentType,
                        decoration: InputDecoration(
                          labelText: abuText(
                            context,
                            'Fulfilment',
                            'طريقة التسليم',
                          ),
                        ),
                        items: const ['manual', 'digital', 'code', 'shipping']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(
                          () => fulfilmentType = value ?? 'manual',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _AdminNumberRow(
                  fields: [
                    (cost, abuText(context, 'Cost', 'التكلفة')),
                    (stock, abuText(context, 'Stock', 'المخزون')),
                    (
                      perUserLimit,
                      abuText(context, 'Per-user limit', 'حد المستخدم'),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: unlimitedStock,
                  onChanged: (value) =>
                      setDialogState(() => unlimitedStock = value),
                  title: Text(
                    abuText(context, 'Unlimited stock', 'مخزون غير محدود'),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: memberOnly,
                  onChanged: (value) =>
                      setDialogState(() => memberOnly = value),
                  title: Text(
                    abuText(
                      context,
                      'YouTube members only',
                      'لأعضاء يوتيوب فقط',
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: scheduled,
                  onChanged: (value) => setDialogState(() => scheduled = value),
                  title: Text(
                    abuText(context, 'Schedule availability', 'جدولة التوفر'),
                  ),
                ),
                if (scheduled) ...[
                  _AdminDateTile(
                    label: abuText(context, 'Available from', 'متاح من'),
                    value: startsAt,
                    onChanged: (value) =>
                        setDialogState(() => startsAt = value),
                  ),
                  _AdminDateTile(
                    label: abuText(context, 'Available until', 'متاح حتى'),
                    value: endsAt,
                    onChanged: (value) => setDialogState(() => endsAt = value),
                  ),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                  title: Text(abuText(context, 'Enabled', 'مفعّل')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(abuText(context, 'CANCEL', 'إلغاء')),
          ),
          TextButton.icon(
            onPressed: () => _showRewardPreview(
              context,
              title: title.text,
              description: description.text,
              imageUrl: image.text,
              cost: int.tryParse(cost.text) ?? 0,
              stock: unlimitedStock ? null : int.tryParse(stock.text),
              memberOnly: memberOnly,
            ),
            icon: Icon(Icons.visibility_rounded),
            label: Text(abuText(context, 'PREVIEW', 'معاينة')),
          ),
          FilledButton(
            onPressed: () {
              final parsedCost = int.tryParse(cost.text);
              final parsedStock = int.tryParse(stock.text);
              final parsedLimit = int.tryParse(perUserLimit.text);
              final scheduleInvalid = scheduled && !endsAt.isAfter(startsAt);
              if (title.text.trim().isEmpty ||
                  parsedCost == null ||
                  parsedCost < 0 ||
                  parsedStock == null ||
                  parsedStock < 0 ||
                  parsedLimit == null ||
                  parsedLimit < 1 ||
                  scheduleInvalid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      abuText(
                        context,
                        'Add a title, non-negative cost and stock, and a valid schedule.',
                        'أضف عنواناً وتكلفة ومخزوناً صحيحين وجدولاً صالحاً.',
                      ),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(abuText(context, 'SAVE', 'حفظ')),
          ),
        ],
      ),
    ),
  );
  if (submit == true && context.mounted) {
    await _saveAdminDefinition(context, () async {
      final finalImageUrl = selectedImage == null
          ? image.text
          : await repository.uploadPostImage(selectedImage!);
      final model = AbuLoyaltyReward(
        id: existing?.id ?? '',
        title: title.text,
        titleAr: titleAr.text,
        description: description.text,
        descriptionAr: descriptionAr.text,
        imageUrl: finalImageUrl,
        category: category,
        cost: int.tryParse(cost.text) ?? 0,
        stock: int.tryParse(stock.text) ?? 0,
        unlimitedStock: unlimitedStock,
        perUserLimit: int.tryParse(perUserLimit.text) ?? 1,
        memberOnly: memberOnly,
        enabled: enabled,
        startsAt: scheduled ? startsAt : null,
        endsAt: scheduled ? endsAt : null,
        fulfilmentType: fulfilmentType,
      );
      await repository.saveReward(model);
    }, abuText(context, 'Reward saved.', 'تم حفظ المكافأة.'));
  }
  for (final controller in [
    title,
    titleAr,
    description,
    descriptionAr,
    image,
    cost,
    stock,
    perUserLimit,
  ]) {
    controller.dispose();
  }
}

Future<void> _showRewardPreview(
  BuildContext context, {
  required String title,
  required String description,
  required String imageUrl,
  required int cost,
  required int? stock,
  required bool memberOnly,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(abuText(context, 'REWARD PREVIEW', 'معاينة المكافأة')),
    content: SizedBox(
      width: 360,
      child: _LoyaltyRewardCard(
        reward: AbuLoyaltyReward(
          id: 'preview',
          title: title.trim().isEmpty
              ? abuText(context, 'Untitled reward', 'مكافأة بلا عنوان')
              : title,
          titleAr: '',
          description: description,
          descriptionAr: '',
          imageUrl: imageUrl,
          category: 'preview',
          cost: cost,
          stock: stock ?? 0,
          unlimitedStock: stock == null,
          memberOnly: memberOnly,
          enabled: true,
          startsAt: null,
          endsAt: null,
          fulfilmentType: 'manual',
        ),
        balance: cost,
        isMember: true,
        busy: false,
        onRedeem: () {},
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(abuText(context, 'CLOSE', 'إغلاق')),
      ),
    ],
  ),
);

class _AdminMobileAction extends StatelessWidget {
  const _AdminMobileAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Material(
    color: emphasized
        ? color.withValues(alpha: .16)
        : _surface2.withValues(alpha: .72),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: emphasized ? color.withValues(alpha: .6) : _line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasized
                      ? color
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    color: primary ? _productionPrimary(context).withValues(alpha: .09) : null,
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
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
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
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _ProductionSkeleton(height: 220);
      }
      if (snapshot.hasError) {
        return _ProductionEmpty(
          icon: Icons.cloud_off_rounded,
          title: abuText(
            context,
            'Event control unavailable',
            'إدارة الفعاليات غير متاحة',
          ),
          body: productionErrorMessage(snapshot.error!),
        );
      }
      final events = snapshot.data ?? const <AbuChallenge>[];
      if (events.isEmpty) {
        return _ProductionEmpty(
          icon: Icons.event_note_rounded,
          title: abuText(
            context,
            'No engagement events yet',
            'لا توجد فعاليات تفاعلية بعد',
          ),
          body: abuText(
            context,
            'Create a Video Question or Player Guess event above.',
            'أنشئ سؤال فيديو أو فعالية تخمين لاعب أعلاه.',
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!desktop) ...[
                Text(
                  abuText(context, 'EVENT CONTROL', 'إدارة الفعاليات'),
                  style: _display(18),
                ),
                const SizedBox(height: 8),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(abuText(context, 'TYPE', 'النوع')),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(abuText(context, 'EVENT', 'الفعالية')),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          abuText(
                            context,
                            'XP FOR CORRECT ANSWER',
                            'XP للإجابة الصحيحة',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(abuText(context, 'ENDS', 'تنتهي')),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(abuText(context, 'STATUS', 'الحالة')),
                      ),
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
                                    ? Icons.person_search_rounded
                                    : Icons.quiz_rounded,
                                color: _productionPrimary(context),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                abuText(
                                  context,
                                  '${event.rewardPoints} XP',
                                  '${event.rewardPoints} XP',
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _productionDate(event.availableUntil),
                                style: TextStyle(color: _muted),
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _statusPicker(context, event),
                                  ),
                                  _deleteButton(context, event),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          event.kind == 'playerCard'
                              ? Icons.person_search_rounded
                              : Icons.quiz_rounded,
                        ),
                        title: Text(event.title),
                        subtitle: Text(
                          abuText(
                            context,
                            '${event.rewardPoints} XP · ${_productionDate(event.availableUntil)}',
                            '${event.rewardPoints} XP · ${_productionDate(event.availableUntil)}',
                          ),
                        ),
                        trailing: SizedBox(
                          width: 180,
                          child: Row(
                            children: [
                              Expanded(child: _statusPicker(context, event)),
                              _deleteButton(context, event),
                            ],
                          ),
                        ),
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
      'closed',
      'archived',
    ];
    return DropdownButton<String>(
      isExpanded: true,
      value: statuses.contains(event.status) ? event.status : 'draft',
      items: [
        DropdownMenuItem(
          value: 'draft',
          child: Text(abuText(context, 'Draft', 'مسودة')),
        ),
        DropdownMenuItem(
          value: 'scheduled',
          child: Text(abuText(context, 'Scheduled', 'مجدول')),
        ),
        DropdownMenuItem(
          value: 'open',
          child: Text(abuText(context, 'Live', 'مباشر')),
        ),
        DropdownMenuItem(
          value: 'disabled',
          child: Text(abuText(context, 'Disabled', 'معطّل')),
        ),
        DropdownMenuItem(
          value: 'ended',
          child: Text(abuText(context, 'Ended', 'منتهٍ')),
        ),
        DropdownMenuItem(
          value: 'closed',
          child: Text(abuText(context, 'Closed', 'مغلق')),
        ),
        DropdownMenuItem(
          value: 'archived',
          child: Text(abuText(context, 'Archived', 'مؤرشف')),
        ),
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

  Widget _deleteButton(BuildContext context, AbuChallenge event) => IconButton(
    tooltip: abuText(context, 'Delete challenge', 'حذف التحدي'),
    icon: const Icon(Icons.delete_outline_rounded),
    color: _red,
    onPressed: () async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            abuText(dialogContext, 'Delete challenge?', 'حذف التحدي؟'),
          ),
          content: Text(
            abuText(
              dialogContext,
              'This permanently removes “${event.title}”, its submitted answers, and its pending notification. Points already earned by fans are kept.',
              'سيؤدي هذا إلى حذف «${event.title}» نهائياً وإجاباته المُرسلة وإشعاره المعلّق. ستبقى النقاط التي حصل عليها الجمهور.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(abuText(dialogContext, 'CANCEL', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(abuText(dialogContext, 'DELETE', 'حذف')),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await repository.deleteChallenge(event);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                abuText(context, 'Challenge deleted.', 'تم حذف التحدي.'),
              ),
            ),
          );
        }
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
                width: 560,
                child: _campaignImagePreview(
                  context: context,
                  imageUrl: announcement.imageUrl,
                  height: 230,
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
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(abuText(context, 'LATER', 'لاحقاً')),
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
