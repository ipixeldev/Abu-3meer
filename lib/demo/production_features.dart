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
            'Secret phrases and hidden Player Cards published by Abu 3meer will appear here.',
            'ستظهر هنا العبارات السرية وبطاقات اللاعبين التي ينشرها أبو عمير.',
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
          Icons.style_rounded,
          abuText(context, 'PLAYER CARD', 'بطاقة اللاعب'),
          abuText(
            context,
            'Find the hidden player and claim it',
            'اعثر على اللاعب المخفي واحصل على بطاقته',
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
                              style: const TextStyle(
                                color: _muted,
                                height: 1.5,
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
              ? abuText(context, 'Claim Player Card', 'احصل على بطاقة اللاعب')
              : abuText(
                  context,
                  'Enter the secret phrase',
                  'أدخل العبارة السرية',
                ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: abuText(context, 'Your answer', 'إجابتك'),
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
            child: Text(abuText(context, 'SUBMIT', 'إرسال')),
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
                ? abuText(
                    context,
                    'Correct! +${result['points'] ?? 0} points.',
                    'إجابة صحيحة! +${result['points'] ?? 0} نقطة.',
                  )
                : abuText(
                    context,
                    'Not this time. Watch closely and try again.',
                    'ليست صحيحة هذه المرة. شاهد جيداً وحاول مجدداً.',
                  ),
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
              label: Text(abuText(context, 'WATCH VIDEO', 'شاهد الفيديو')),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: challenge.isOpen ? () => answer(context) : null,
              child: Text(
                challenge.isOpen
                    ? abuText(context, 'PLAY NOW', 'العب الآن')
                    : abuText(context, 'CLOSED', 'مغلق'),
              ),
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
      if (snapshot.hasError) {
        return _ProductionEmpty(
          icon: Icons.cloud_off_rounded,
          title: abuText(context, 'Activity unavailable', 'النشاط غير متاح'),
          body: productionErrorMessage(snapshot.error!),
        );
      }
      final active = (snapshot.data ?? const <AbuChallenge>[])
          .where((event) => event.isOpen)
          .take(3)
          .toList();
      if (active.isEmpty) {
        return _ProductionEmpty(
          icon: Icons.event_available_rounded,
          title: abuText(context, 'You are all caught up', 'أكملت كل شيء'),
          body: abuText(
            context,
            'New challenges and activities will appear here.',
            'ستظهر التحديات والأنشطة الجديدة هنا.',
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                abuText(context, 'YOUR NEXT MOVES', 'خطواتك القادمة'),
                style: _display(22),
              ),
              const Spacer(),
              Text(
                abuText(
                  context,
                  '${active.length} LIVE',
                  '${active.length} متاح',
                ),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1100) {
        return _ProductionEmpty(
          icon: Icons.article_rounded,
          title: abuText(context, 'No posts yet', 'لا توجد منشورات بعد'),
          body: abuText(
            context,
            'New articles, match reactions and community updates will appear here.',
            'ستظهر هنا المقالات الجديدة وردود أفعال المباريات وأخبار المجتمع.',
          ),
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
                          _LiveDot(
                            text: abuText(
                              context,
                              'EDITORIAL DESK',
                              'قسم التحرير',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            abuText(
                              context,
                              'The first story is being prepared',
                              'يجري تحضير أول منشور',
                            ),
                            style: _display(29),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            abuText(
                              context,
                              'Match reactions, creator updates and community stories will be published here from Admin Studio.',
                              'ستنشر هنا ردود أفعال المباريات وأخبار صانع المحتوى وقصص المجتمع من استوديو الإدارة.',
                            ),
                            style: const TextStyle(color: _muted, height: 1.5),
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
                    Text(
                      abuText(context, 'COMMUNITY DESK', 'قسم المجتمع'),
                      style: _display(20),
                    ),
                    const Spacer(),
                    _CommunityDeskMetric(
                      icon: Icons.article_outlined,
                      value: '0',
                      label: abuText(
                        context,
                        'PUBLISHED STORIES',
                        'المنشورات المنشورة',
                      ),
                    ),
                    const SizedBox(height: 18),
                    _CommunityDeskMetric(
                      icon: Icons.forum_outlined,
                      value: abuText(context, 'LIVE', 'مباشر'),
                      label: abuText(
                        context,
                        'COMMENTS & REACTIONS',
                        'التعليقات والتفاعلات',
                      ),
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
      if (constraints.maxWidth < 1100) {
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
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            abuText(context, 'MORE STORIES', 'منشورات أخرى'),
                            style: _display(18),
                          ),
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
                    label: Text(abuText(context, 'SUPPORT', 'دعم')),
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
                    label: Text(abuText(context, 'COMMENTS', 'التعليقات')),
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
                      label: Text(abuText(context, 'OPEN LINK', 'فتح الرابط')),
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ProductionEmpty(
                    icon: Icons.cloud_off_rounded,
                    title: abuText(
                      context,
                      'Comments unavailable',
                      'التعليقات غير متاحة',
                    ),
                    body: productionErrorMessage(snapshot.error!),
                  );
                }
                final comments = snapshot.data ?? const [];
                if (comments.isEmpty) {
                  return Center(
                    child: Text(
                      abuText(
                        context,
                        'Start the conversation.',
                        'ابدأ المحادثة.',
                      ),
                      style: const TextStyle(color: _muted),
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
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Write a comment',
                      'اكتب تعليقاً',
                    ),
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
        child: Text(abuText(context, 'CLOSE', 'إغلاق')),
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
        : _ResponsiveGrid(
            children: [
              _GameLaunchCard(
                icon: Icons.psychology_alt_rounded,
                color: _lime,
                title: 'Ehzerha',
                detail: abuText(
                  context,
                  'The full guessing game, embedded inside the web app.',
                  'لعبة التخمين الكاملة داخل تطبيق الويب.',
                ),
                action: abuText(context, 'PLAY EHZERHA', 'العب احزرها'),
                onTap: () => setState(() => showEhzerha = true),
              ),
              _GameLaunchCard(
                icon: Icons.groups_rounded,
                color: _gold,
                title: abuText(context, 'Fan Duels', 'مواجهات الجماهير'),
                detail: abuText(
                  context,
                  'Challenge another supporter in quick football trivia.',
                  'تحدَّ مشجعاً آخر في أسئلة كروية سريعة.',
                ),
                action: abuText(context, 'START A DUEL', 'ابدأ مواجهة'),
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
                title: abuText(context, 'Trivia Arena', 'ساحة المعلومات'),
                detail: abuText(
                  context,
                  'Fast football questions built for mobile and desktop.',
                  'أسئلة كروية سريعة للجوال وسطح المكتب.',
                ),
                action: abuText(context, 'ENTER ARENA', 'ادخل الساحة'),
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
                        const Icon(
                          Icons.sports_esports_rounded,
                          color: _lime,
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
                          style: const TextStyle(color: _muted, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: busy ? null : create,
                          icon: const Icon(Icons.add_rounded),
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
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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
              style: _display(58, color: _lime, spacing: 4),
            ),
            Text(
              abuText(
                context,
                'Waiting for the second fan…',
                'بانتظار المشجع الثاني…',
              ),
              style: const TextStyle(color: _muted),
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
          return const Center(child: CircularProgressIndicator());
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
                  color: _lime,
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
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  abuText(context, '$madridPoints PTS', '$madridPoints نقطة'),
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
                        style: const TextStyle(
                          color: _lime,
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
    final milestones = <(int, String, IconData)>[
      (
        100,
        abuText(context, 'First Century', 'المئة الأولى'),
        Icons.looks_one_rounded,
      ),
      (
        500,
        abuText(context, 'Rising Fan', 'مشجع صاعد'),
        Icons.trending_up_rounded,
      ),
      (
        1000,
        abuText(context, 'One Thousand Club', 'نادي الألف'),
        Icons.workspace_premium_rounded,
      ),
      (
        5000,
        abuText(context, 'Ultra Supporter', 'مشجع ألترا'),
        Icons.local_fire_department_rounded,
      ),
      (
        10000,
        abuText(context, 'Abu 3meer Legend', 'أسطورة أبو عمير'),
        Icons.emoji_events_rounded,
      ),
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
                        ? abuText(context, 'UNLOCKED', 'تم الفتح')
                        : abuText(
                            context,
                            '${profile.totalPoints} / ${milestone.$1} PTS',
                            '${profile.totalPoints} / ${milestone.$1} نقطة',
                          ),
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
          ? _ProductionEmpty(
              icon: Icons.card_giftcard_rounded,
              title: abuText(
                context,
                'Reward catalogue coming soon',
                'متجر المكافآت قريباً',
              ),
              body: abuText(
                context,
                'The owner will publish real rewards here. No redemption is simulated and no points are removed until the catalogue is connected.',
                'سينشر المالك المكافآت الحقيقية هنا. لن تتم محاكاة الاستبدال أو خصم النقاط حتى يتم ربط المتجر.',
              ),
            )
          : _ResponsiveGrid(
              children:
                  [
                        (
                          abuText(
                            context,
                            'SIGNED HOME SHIRT',
                            'قميص منزلي موقّع',
                          ),
                          abuText(context, '5,000 PTS', '5,000 نقطة'),
                          Icons.checkroom_rounded,
                        ),
                        (
                          abuText(
                            context,
                            'ABU 3MEER VIDEO SHOUTOUT',
                            'تحية فيديو من أبو عمير',
                          ),
                          abuText(context, '2,500 PTS', '2,500 نقطة'),
                          Icons.record_voice_over_rounded,
                        ),
                        (
                          abuText(
                            context,
                            '€25 STORE CREDIT',
                            'رصيد متجر بقيمة €25',
                          ),
                          abuText(context, '1,800 PTS', '1,800 نقطة'),
                          Icons.wallet_giftcard_rounded,
                        ),
                        (
                          abuText(
                            context,
                            'MONTHLY GIVEAWAY ENTRY',
                            'دخول السحب الشهري',
                          ),
                          abuText(context, '500 PTS', '500 نقطة'),
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
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: null,
                                    child: Text(
                                      abuText(
                                        context,
                                        'PREVIEW REWARD',
                                        'معاينة المكافأة',
                                      ),
                                    ),
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
                  for (final milestone in [
                    (3, abuText(context, 'Warm up', 'بداية قوية')),
                    (7, abuText(context, 'On fire', 'متألق')),
                    (14, abuText(context, 'Unstoppable', 'لا يُوقَف')),
                    (30, abuText(context, 'Club legend', 'أسطورة النادي')),
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
          if (constraints.maxWidth >= 1100) {
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
                    _LiveDot(text: abuText(context, 'LIVE', 'مباشر')),
                    const Spacer(),
                    Text(
                      abuText(
                        context,
                        'ABU 3MEER LEADERBOARD',
                        'ترتيب أبو عمير',
                      ),
                      style: _display(17),
                    ),
                    const SizedBox(width: 10),
                    const _LogoMark(size: 30),
                  ],
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<LeaderboardEntry>>(
                  stream: widget.repository.watchLeaderboard(monthly: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Expanded(
                        child: _ProductionEmpty(
                          icon: Icons.cloud_off_rounded,
                          title: abuText(
                            context,
                            'Leaderboard unavailable',
                            'الترتيب غير متاح',
                          ),
                          body: productionErrorMessage(snapshot.error!),
                        ),
                      );
                    }
                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return Expanded(
                        child: _ProductionEmpty(
                          icon: Icons.leaderboard_rounded,
                          title: abuText(
                            context,
                            'No rankings yet',
                            'لا يوجد ترتيب بعد',
                          ),
                          body: abuText(
                            context,
                            'Rankings will appear after fans earn points.',
                            'سيظهر الترتيب بعد أن يجمع المشجعون النقاط.',
                          ),
                        ),
                      );
                    }
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
                Text(
                  abuText(
                    context,
                    'Browser Source · transparent-safe · updates live',
                    'مصدر متصفح · يدعم الشفافية · تحديث مباشر',
                  ),
                  style: const TextStyle(color: _muted, fontSize: 10),
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
              _LiveDot(text: abuText(context, 'LIVE', 'مباشر')),
            ],
          ),
        ),
        Positioned(
          right: 30,
          bottom: 30,
          child: FilledButton.icon(
            onPressed: widget.onExit,
            icon: const Icon(Icons.close_fullscreen_rounded),
            label: Text(abuText(context, 'EXIT OVERLAY', 'إغلاق العرض')),
          ),
        ),
      ],
    ),
  );
}

const int _maximumCampaignImageBytes = 8 * 1024 * 1024;
const Set<String> _campaignImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
};

String? _campaignImageUrlError(BuildContext context, String raw) {
  if (raw.trim().isEmpty) return null;
  if (externalHttpUri(raw) == null) {
    return abuText(
      context,
      'Enter a valid HTTPS image URL.',
      'أدخل رابط صورة HTTPS صالحاً.',
    );
  }
  return null;
}

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
            const Icon(Icons.broken_image_rounded, color: _muted),
            const SizedBox(height: 8),
            Text(
              abuText(
                context,
                'Image unavailable. Check the URL or upload another image.',
                'الصورة غير متاحة. تحقق من الرابط أو ارفع صورة أخرى.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
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
              style: const TextStyle(color: _muted),
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
                    backgroundColor: _lime.withValues(alpha: .12),
                    child: Icon(
                      kind == 'playerCard'
                          ? Icons.style_rounded
                          : Icons.subtitles_rounded,
                      color: _lime,
                    ),
                  ),
                  const Spacer(),
                  _RewardChip(text: '+$rewardPoints PTS'),
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
                style: const TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              _LiveDot(
                text: status == 'open'
                    ? abuText(context, 'LIVE', 'مباشر')
                    : status.toUpperCase(),
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

Future<void> _showAdminPostPreview(
  BuildContext context, {
  required String title,
  required String body,
  required String imageUrl,
  required String authorName,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(abuText(context, 'POST PREVIEW', 'معاينة المنشور')),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (imageUrl.trim().isNotEmpty)
                _campaignImagePreview(
                  context: context,
                  imageUrl: imageUrl,
                  height: 240,
                ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName.toUpperCase(),
                      style: const TextStyle(
                        color: _lime,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title.trim().isEmpty
                          ? abuText(context, 'Untitled post', 'منشور بلا عنوان')
                          : title.trim(),
                      style: _display(27),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body.trim().isEmpty
                          ? abuText(
                              context,
                              'Add post content before publishing.',
                              'أضف محتوى المنشور قبل النشر.',
                            )
                          : body.trim(),
                      style: const TextStyle(color: _muted, height: 1.6),
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
            style: const TextStyle(color: _muted, height: 1.5),
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
            'Publish a phrase, quiz or Player Card challenge.',
            'انشر عبارة أو اختباراً أو تحدي بطاقة لاعب.',
          ),
          color: _lime,
          primary: true,
          onTap: () => createChallenge(context),
        ),
        _AdminQuickAction(
          icon: Icons.post_add_rounded,
          label: abuText(context, 'NEW POST', 'منشور جديد'),
          detail: abuText(
            context,
            'Add an article, image, reaction or external link.',
            'أضف مقالاً أو صورة أو تفاعلاً أو رابطاً خارجياً.',
          ),
          color: _blue,
          onTap: () => createPost(context),
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
                              style: const TextStyle(color: _muted),
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
                label: Text(abuText(context, 'NEW CHALLENGE', 'تحدٍ جديد')),
              ),
              OutlinedButton.icon(
                onPressed: () => createPost(context),
                icon: const Icon(Icons.post_add_rounded),
                label: Text(abuText(context, 'NEW POST', 'منشور جديد')),
              ),
              OutlinedButton.icon(
                onPressed: () => editAnnouncement(context),
                icon: const Icon(Icons.campaign_rounded),
                label: Text(abuText(context, 'LAUNCH POPUP', 'نافذة بدء')),
              ),
              if (profile.canManageRoles)
                OutlinedButton.icon(
                  onPressed: () => manageRoles(context),
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: Text(
                    abuText(context, 'ROLES & ADMINS', 'الأدوار والمشرفون'),
                  ),
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
          title: Text(abuText(context, 'Create challenge', 'إنشاء تحدٍ')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'videoQuestion',
                        label: Text(
                          abuText(context, 'SECRET PHRASE', 'العبارة السرية'),
                        ),
                      ),
                      ButtonSegment(
                        value: 'playerCard',
                        label: Text(
                          abuText(context, 'PLAYER CARD', 'بطاقة اللاعب'),
                        ),
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
                  TextField(
                    controller: answer,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Private correct answer',
                        'الإجابة الصحيحة الخاصة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: points,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Reward points',
                        'نقاط المكافأة',
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
              ),
              icon: const Icon(Icons.visibility_rounded),
              label: Text(abuText(context, 'PREVIEW', 'معاينة')),
            ),
            FilledButton(
              onPressed: () {
                final reward = int.tryParse(points.text);
                final invalid =
                    title.text.trim().isEmpty ||
                    answer.text.trim().isEmpty ||
                    reward == null ||
                    reward <= 0 ||
                    !endsAt.isAfter(startsAt);
                if (invalid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        abuText(
                          context,
                          'Add a title, correct answer, positive reward and valid schedule.',
                          'أضف عنواناً وإجابة صحيحة ومكافأة موجبة وجدولاً زمنياً صالحاً.',
                        ),
                      ),
                    ),
                  );
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
    if (submit != true || !context.mounted) return;
    await _adminAction(context, () {
      return repository.createChallenge(
        kind: kind,
        title: title.text,
        description: description.text,
        videoUrl: video.text,
        answer: answer.text,
        rewardPoints: int.tryParse(points.text) ?? 0,
        availableFrom: startsAt,
        availableUntil: endsAt,
        status: status,
        maximumAttempts: maximumAttempts,
        memberOnly: memberOnly,
        notifyOnLive: notifyOnLive,
      );
    }, abuText(context, 'Challenge published.', 'تم نشر التحدي.'));
  }

  Future<void> createPost(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final image = TextEditingController();
    final link = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(abuText(context, 'Publish a post', 'نشر منشور')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: abuText(context, 'Headline', 'العنوان'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: abuText(context, 'Post', 'المنشور'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: image,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Image URL (optional)',
                      'رابط الصورة (اختياري)',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: link,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Clickable link (optional)',
                      'الرابط القابل للنقر (اختياري)',
                    ),
                  ),
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
          TextButton.icon(
            onPressed: () => _showAdminPostPreview(
              context,
              title: title.text,
              body: body.text,
              imageUrl: image.text,
              authorName: profile.displayName,
            ),
            icon: const Icon(Icons.visibility_rounded),
            label: Text(abuText(context, 'PREVIEW', 'معاينة')),
          ),
          FilledButton(
            onPressed: () {
              final imageError = _campaignImageUrlError(context, image.text);
              final linkError =
                  link.text.trim().isNotEmpty &&
                  externalHttpUri(link.text) == null;
              if (title.text.trim().isEmpty ||
                  body.text.trim().isEmpty ||
                  imageError != null ||
                  linkError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      imageError ??
                          abuText(
                            context,
                            linkError
                                ? 'Enter a valid clickable link.'
                                : 'Add a headline and post content.',
                            linkError
                                ? 'أدخل رابطاً صالحاً.'
                                : 'أضف عنواناً ومحتوى للمنشور.',
                          ),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(abuText(context, 'PUBLISH', 'نشر')),
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
      abuText(context, 'Post published.', 'تم نشر المنشور.'),
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
    XFile? selectedImage;
    dynamic selectedImageBytes;
    String? imageValidationError;
    String? uploadError;
    var uploading = false;
    final submission = await showDialog<({String imageUrl})?>(
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
                        Text(
                          abuText(
                            context,
                            'SCHEDULE & DELIVERY',
                            'الجدولة والعرض',
                          ),
                          style: const TextStyle(
                            color: _lime,
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
                                abuText(context, 'Once per day', 'مرة يومياً'),
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
                          onChanged: (value) =>
                              setDialogState(() => frequency = value ?? 'once'),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
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
                  TextField(
                    controller: image,
                    keyboardType: TextInputType.url,
                    onChanged: (value) => setDialogState(() {
                      imageValidationError = _campaignImageUrlError(
                        context,
                        value,
                      );
                      uploadError = null;
                    }),
                    decoration: InputDecoration(
                      labelText: abuText(
                        context,
                        'Direct image URL (optional)',
                        'رابط صورة مباشر (اختياري)',
                      ),
                      helperText: abuText(
                        context,
                        'Use an HTTPS image URL, or upload an image below.',
                        'استخدم رابط HTTPS أو ارفع صورة أدناه.',
                      ),
                      errorText: imageValidationError,
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
                          icon: const Icon(Icons.upload_rounded),
                          label: Text(
                            selectedImage == null
                                ? abuText(context, 'UPLOAD IMAGE', 'رفع صورة')
                                : selectedImage!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (selectedImage != null) ...[
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
                                  uploadError = null;
                                }),
                          icon: const Icon(Icons.close_rounded),
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
                  if (uploadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      uploadError!,
                      style: const TextStyle(color: _red, height: 1.35),
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
              icon: const Icon(Icons.visibility_rounded),
              label: Text(abuText(context, 'PREVIEW', 'معاينة')),
            ),
            FilledButton(
              onPressed: uploading
                  ? null
                  : () async {
                      final urlError = selectedImage == null
                          ? _campaignImageUrlError(context, image.text)
                          : null;
                      final linkError =
                          link.text.trim().isNotEmpty &&
                          externalHttpUri(link.text) == null;
                      if (title.text.trim().isEmpty ||
                          body.text.trim().isEmpty ||
                          !endsAt.isAfter(startsAt) ||
                          urlError != null ||
                          linkError) {
                        setDialogState(() => imageValidationError = urlError);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              urlError ??
                                  abuText(
                                    context,
                                    linkError
                                        ? 'Enter a valid clickable link.'
                                        : 'Add a title, message and valid schedule.',
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
                              'Image upload is not available. Enable Firebase Storage for this project and try again. ${productionErrorMessage(error)}',
                              'رفع الصور غير متاح. فعّل Firebase Storage لهذا المشروع ثم حاول مجدداً. ${productionErrorMessage(error)}',
                            );
                          });
                          return;
                        }
                      }
                      if (context.mounted) {
                        Navigator.pop(context, (imageUrl: finalImageUrl));
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

  Future<void> manageRoles(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        abuText(context, 'Roles & administrators', 'الأدوار والمشرفون'),
      ),
      content: SizedBox(
        width: 680,
        height: 520,
        child: StreamBuilder<List<AbuUserProfile>>(
          stream: repository.watchUsers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(productionErrorMessage(snapshot.error!)),
              );
            }
            final users = snapshot.data ?? const [];
            if (users.isEmpty) {
              return _ProductionEmpty(
                icon: Icons.people_outline_rounded,
                title: abuText(
                  context,
                  'No users found',
                  'لم يتم العثور على مستخدمين',
                ),
                body: abuText(
                  context,
                  'New accounts will appear here after registration.',
                  'ستظهر الحسابات الجديدة هنا بعد التسجيل.',
                ),
              );
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
                    items: [
                      DropdownMenuItem(
                        value: 'user',
                        child: Text(abuText(context, 'User', 'مستخدم')),
                      ),
                      DropdownMenuItem(
                        value: 'moderator',
                        child: Text(abuText(context, 'Moderator', 'مشرف')),
                      ),
                      DropdownMenuItem(
                        value: 'editor',
                        child: Text(abuText(context, 'Editor', 'محرر')),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text(abuText(context, 'Admin', 'مدير')),
                      ),
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
          child: Text(abuText(context, 'DONE', 'تم')),
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
            'Create a Video Question or Player Card event above.',
            'أنشئ سؤال فيديو أو فعالية بطاقة لاعب أعلاه.',
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
                        child: Text(abuText(context, 'REWARD', 'المكافأة')),
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
                              child: Text(
                                abuText(
                                  context,
                                  '${event.rewardPoints} points',
                                  '${event.rewardPoints} نقطة',
                                ),
                              ),
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
                          abuText(
                            context,
                            '${event.rewardPoints} points · ${_productionDate(event.availableUntil)}',
                            '${event.rewardPoints} نقطة · ${_productionDate(event.availableUntil)}',
                          ),
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
                style: const TextStyle(color: _muted, height: 1.5),
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
