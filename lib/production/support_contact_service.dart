import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

enum SupportContactResult { opened, notConfigured, unavailable, launchFailed }

/// Reads only the public contact endpoint. Never sends account or receipt data.
class SupportContactService {
  SupportContactService({AbuApiClient? api, Future<bool> Function(Uri)? launch})
    : _api = api ?? AbuApiClient(),
      _launch = launch ?? _launchExternal;

  static final instance = SupportContactService();
  final AbuApiClient _api;
  final Future<bool> Function(Uri) _launch;

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Uri? validatedWhatsAppUri(dynamic value) {
    if (value is! String ||
        !RegExp(r'^https://wa\.me/[1-9][0-9]{5,14}$').hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'wa.me' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^/[1-9][0-9]{5,14}$').hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  Future<SupportContactResult> openWhatsApp({
    bool Function()? isStillActive,
  }) async {
    dynamic response;
    try {
      response = await _api
          .get('/support/contact', bypassCache: true)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return SupportContactResult.unavailable;
    }
    final data = response is Map ? response['data'] : null;
    if (data is! Map || !data.containsKey('whatsappUrl')) {
      return SupportContactResult.unavailable;
    }
    if (data['whatsappUrl'] == null) return SupportContactResult.notConfigured;
    final uri = validatedWhatsAppUri(data['whatsappUrl']);
    if (uri == null) return SupportContactResult.unavailable;
    // Do not open an external app after the initiating screen was closed.
    if (isStillActive?.call() == false) return SupportContactResult.unavailable;
    try {
      return await _launch(uri).timeout(const Duration(seconds: 10))
          ? SupportContactResult.opened
          : SupportContactResult.launchFailed;
    } catch (_) {
      return SupportContactResult.launchFailed;
    }
  }
}
