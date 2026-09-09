bool shouldPresentForegroundNotificationLocally({
  required bool isApplePlatform,
  required bool appleSystemPresentationEnabled,
  required bool hasNotificationPayload,
}) {
  // iOS/macOS can display a remote notification through the operating system
  // while the app is foregrounded. Rendering the same notification locally
  // would create two banners. Data-only messages still need a local banner.
  return !(isApplePlatform &&
      appleSystemPresentationEnabled &&
      hasNotificationPayload);
}
