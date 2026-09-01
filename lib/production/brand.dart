import 'package:flutter/material.dart';

/// Single source of truth for Abu 3meer identity and public contact details.
/// Business-owned values can later be loaded from `platformSettings/branding`
/// without changing feature screens.
abstract final class AbuBrand {
  static const appName = 'ABU 3MEER';
  static const shortName = 'ABU 3MEER';
  static const tagline = 'WATCH. PREDICT. ANSWER. FIND.';
  static const supportEmail = 'support@abu3meer.com';
  static const youtubeUrl = 'https://www.youtube.com/@abu3meer';
  static const instagramUrl = 'https://www.instagram.com/abu3meer';
  static const websiteUrl = 'https://ipixeldev.github.io/Abu-3meer/';
  static const privacyUrl = '${websiteUrl}privacy/';
  static const termsUrl = '${websiteUrl}terms/';
  static const competitionRulesUrl = '${websiteUrl}competition-rules/';
  static const supportUrl = '${websiteUrl}support/';
  static const accountDeletionUrl = '${websiteUrl}delete-account/';
  static const ageSuitabilityUrl = '${websiteUrl}age-suitability/';

  static const logoAsset = 'assets/images/latest_abu3meer.jpg';
  static const channelImageAsset = 'assets/images/latest_abu3meer.jpg';

  static const ink = Color(0xFF080B10);
  static const surface = Color(0xFF11161E);
  static const surfaceRaised = Color(0xFF181F2A);
  static const line = Color(0xFF28313E);
  static const lime = Color(0xFFC8FF38);
  static const gold = Color(0xFFFFC857);
  static const muted = Color(0xFF929CAA);
  static const red = Color(0xFFFF4D62);
}
