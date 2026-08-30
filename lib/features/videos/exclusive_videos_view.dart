import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../production/app_preferences.dart';
import '../../production/models.dart';
import '../../production/production_repository.dart';

const _exclusiveDarkLime = Color(0xFFC8FF38);
const _exclusiveLightPrimary = Color(0xFF2457D6);
const _exclusiveLightInk = Color(0xFF172033);
const _exclusiveLightSurface = Color(0xFFFFFFFF);
const _exclusiveLightLine = Color(0xFFD4DDEA);
const _exclusiveLightMuted = Color(0xFF66758A);

bool _exclusiveIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _exclusivePrimary(BuildContext context) =>
    _exclusiveIsDark(context) ? _exclusiveDarkLime : _exclusiveLightPrimary;

class ExclusiveVideosView extends StatefulWidget {
  const ExclusiveVideosView({
    super.key,
    required this.repository,
    required this.profile,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  State<ExclusiveVideosView> createState() => _ExclusiveVideosViewState();
}

class _ExclusiveVideosViewState extends State<ExclusiveVideosView> {
  void _refreshInBackground() {
    unawaited(() async {
      try {
        await widget.repository.refreshExclusiveVideos(force: true);
      } catch (error, stackTrace) {
        debugPrint(
          '[ExclusiveVideos] Background refresh failed: $error\n$stackTrace',
        );
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    // Visited shell tabs stay mounted. Force a network read whenever this page
    // is first opened so an earlier cached empty list cannot hide a new video.
    _refreshInBackground();
  }

  @override
  void didUpdateWidget(covariant ExclusiveVideosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.isYouTubeMember != widget.profile.isYouTubeMember) {
      _refreshInBackground();
    }
  }

  Future<void> _refresh() =>
      widget.repository.refreshExclusiveVideos(force: true);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExclusiveVideo>>(
      stream: widget.repository.watchExclusiveVideos(),
      builder: (context, snapshot) {
        final videos = snapshot.data ?? const <ExclusiveVideo>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            videos.isEmpty) {
          return Center(
            child: CircularProgressIndicator(color: _exclusivePrimary(context)),
          );
        }

        if (videos.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              return _VideoCard(
                video: video,
                isMember: widget.profile.isYouTubeMember,
                onTap: () => _openVideo(context, video),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final primary = _exclusivePrimary(context);
    final dark = _exclusiveIsDark(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: primary,
                size: 48,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              abuText(
                context,
                'Exclusive Videos For App Users',
                'فيديوهات حصرية لمستخدمي التطبيق',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? Colors.white : _exclusiveLightInk,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              abuText(
                context,
                'Stay tuned for unlisted videos and behind-the-scenes content published by Abu 3meer.',
                'ترقب الفيديوهات غير المدرجة والكواليس الخاصة التي ينشرها أبو عمير هنا قريباً.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? const Color(0xFF8C9BAE) : _exclusiveLightMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openVideo(BuildContext context, ExclusiveVideo video) async {
    if (video.memberOnly && !widget.profile.isYouTubeMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'This video is reserved for verified Gold Channel Members ⭐',
              'هذا الفيديو مخصص للأعضاء الذهبيين الموثقين فقط ⭐',
            ),
          ),
          backgroundColor: const Color(0xFF221A04),
        ),
      );
      return;
    }

    final rawUrl = video.videoUrl.trim().isNotEmpty
        ? video.videoUrl.trim()
        : 'https://www.youtube.com/watch?v=${video.youtubeId.trim()}';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      _showVideoOpenError(context);
      return;
    }

    try {
      // Android 11+ package visibility can make canLaunchUrl report false even
      // when ACTION_VIEW can open the link. Launch directly, then fall back to
      // the platform browser instead of leaving the play button silent.
      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && context.mounted) _showVideoOpenError(context);
    } catch (error, stackTrace) {
      debugPrint('[ExclusiveVideos] Could not open $uri: $error\n$stackTrace');
      if (context.mounted) _showVideoOpenError(context);
    }
  }

  void _showVideoOpenError(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            abuText(
              context,
              'YouTube could not be opened on this device.',
              'تعذّر فتح يوتيوب على هذا الجهاز.',
            ),
          ),
        ),
      );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.isMember,
    required this.onTap,
  });

  final ExclusiveVideo video;
  final bool isMember;
  final VoidCallback onTap;

  static const _gold = Color(0xFFFFD700);
  static const _surface = Color(0xFF10141D);
  static const _line = Color(0xFF222B3D);
  static const _muted = Color(0xFF8C9BAE);

  @override
  Widget build(BuildContext context) {
    final locked = video.memberOnly && !isMember;
    final dark = _exclusiveIsDark(context);
    final primary = _exclusivePrimary(context);
    final surface = dark ? _surface : _exclusiveLightSurface;
    final line = dark ? _line : _exclusiveLightLine;
    final muted = dark ? _muted : _exclusiveLightMuted;
    final ink = dark ? Colors.white : _exclusiveLightInk;

    final published = MaterialLocalizations.of(context)
        .formatCompactDate(video.publishedAt.toLocal());
    final views = _formatExclusiveViewCount(context, video.viewCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: video.memberOnly ? _gold.withValues(alpha: .4) : line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: locked
                ? abuText(
                    context,
                    'Gold members only: ${video.title}',
                    'للأعضاء الذهبيين فقط: ${video.title}',
                  )
                : abuText(
                    context,
                    'Play ${video.title}',
                    'تشغيل ${video.title}',
                  ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 142,
                    height: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            video.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: Colors.black45,
                              child: Icon(
                                Icons.video_library_rounded,
                                color: muted,
                                size: 32,
                              ),
                            ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: .58),
                                ],
                              ),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .76),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (locked ? _gold : primary).withValues(
                                    alpha: .85,
                                  ),
                                ),
                              ),
                              child: Icon(
                                locked
                                    ? Icons.lock_rounded
                                    : Icons.play_arrow_rounded,
                                color: locked ? _gold : primary,
                                size: 25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: SizedBox(
                      height: 96,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              height: 1.18,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (video.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              video.description.trim(),
                              style: TextStyle(
                                color: muted,
                                fontSize: 11.5,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              if (video.memberOnly) ...[
                                Icon(
                                  Icons.workspace_premium_rounded,
                                  color: _gold,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  '$views · $published',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.open_in_new_rounded,
                                color: primary,
                                size: 15,
                              ),
                            ],
                          ),
                        ],
                      ),
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

String _formatExclusiveViewCount(BuildContext context, int count) {
  late final String compactCount;
  if (count >= 1000000) {
    final value = count / 1000000;
    compactCount =
        '${value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}M';
  } else if (count >= 1000) {
    final value = count / 1000;
    compactCount =
        '${value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}K';
  } else {
    compactCount = '$count';
  }
  return abuText(
    context,
    '$compactCount ${count == 1 ? 'view' : 'views'}',
    '$compactCount مشاهدة',
  );
}
