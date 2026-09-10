import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../production/ad_service.dart';

/// A single unobtrusive banner that collapses completely when ads are off,
/// consent is unavailable, or Google cannot fill the request.
class InlineBannerAd extends StatefulWidget {
  const InlineBannerAd({super.key, this.hidden = false});

  final bool hidden;

  @override
  State<InlineBannerAd> createState() => _InlineBannerAdState();
}

class _InlineBannerAdState extends State<InlineBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AdMobService.instance.addListener(_serviceChanged);
    _loadIfAllowed();
  }

  @override
  void didUpdateWidget(covariant InlineBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hidden && !oldWidget.hidden) {
      _disposeBanner();
    } else if (!widget.hidden && oldWidget.hidden) {
      _loadIfAllowed();
    }
  }

  void _serviceChanged() {
    if (!mounted) return;
    final previousBanner = _banner;
    previousBanner?.dispose();
    setState(() {
      _banner = null;
      _loaded = false;
    });
    if (AdMobService.instance.canShowAds) _loadIfAllowed();
  }

  void _loadIfAllowed() {
    if (widget.hidden || _banner != null || !AdMobService.instance.canShowAds) {
      return;
    }
    final unitId = AdMobConfiguration.bannerAdUnitId;
    if (unitId.isEmpty) return;
    final banner = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: AdMobService.privacyPreservingRequest,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || ad != _banner) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdMob] Banner failed (${error.code}): ${error.message}');
          ad.dispose();
          if (mounted && ad == _banner) {
            setState(() {
              _banner = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _banner = banner;
    banner.load();
  }

  void _disposeBanner() {
    _banner?.dispose();
    _banner = null;
    _loaded = false;
  }

  @override
  void dispose() {
    AdMobService.instance.removeListener(_serviceChanged);
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (!_loaded || banner == null || widget.hidden) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      label: 'Advertisement',
      child: Center(
        child: SizedBox(
          width: banner.size.width.toDouble(),
          height: banner.size.height.toDouble(),
          child: AdWidget(ad: banner),
        ),
      ),
    );
  }
}
