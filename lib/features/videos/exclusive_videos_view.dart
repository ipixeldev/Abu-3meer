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

class ExclusiveVideosView extends StatelessWidget {
  const ExclusiveVideosView({
    super.key,
    required this.repository,
    required this.profile,
  });

  final ProductionRepository repository;
  final AbuUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExclusiveVideo>>(
      stream: repository.watchExclusiveVideos(),
      builder: (context, snapshot) {
        final videos = snapshot.data ?? const <ExclusiveVideo>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            videos.isEmpty) {
          return Center(
            child: CircularProgressIndicator(color: _exclusivePrimary(context)),
          );
        }

        if (videos.isEmpty) {
          return _buildEmptyState(context);
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return _VideoCard(
              video: video,
              isMember: profile.isYouTubeMember,
              onTap: () => _openVideo(context, video),
            );
          },
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
    if (video.memberOnly && !profile.isYouTubeMember) {
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

    final uri = Uri.parse(
      video.videoUrl.isNotEmpty
          ? video.videoUrl
          : 'https://www.youtube.com/watch?v=${video.youtubeId}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: video.memberOnly ? _gold.withValues(alpha: .4) : line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.black45,
                        child: Center(
                          child: Icon(
                            Icons.video_library_rounded,
                            color: muted,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: .7),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (locked ? _gold : primary).withValues(alpha: .9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (locked ? _gold : primary).withValues(
                              alpha: .4,
                            ),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        locked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 32,
                      ),
                    ),
                  ),
                  if (video.memberOnly)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Colors.black,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              abuText(
                                context,
                                'GOLD MEMBERS ONLY',
                                'للأعضاء الذهبيين فقط',
                              ),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: .6,
                              ),
                            ),
                          ],
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
                    video.title,
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (video.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      video.description,
                      style: TextStyle(color: muted, fontSize: 12, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
