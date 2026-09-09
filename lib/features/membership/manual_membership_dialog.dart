import 'package:flutter/material.dart';

import '../../production/app_preferences.dart';
import '../../production/api_client.dart';
import '../../production/production_repository.dart';
import '../../production/youtube_membership_check.dart';

String? channelIdFromProfileLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      !const {
        'youtube.com',
        'www.youtube.com',
        'm.youtube.com',
      }.contains(uri.host.toLowerCase())) {
    return null;
  }
  final match = RegExp(r'^/channel/(UC[A-Za-z0-9_-]{22})/?$')
      .firstMatch(uri.path);
  return match?.group(1);
}

bool isYouTubeProfileLink(String value) {
  final candidate = value.trim();
  if (candidate.length > 2048 ||
      candidate.contains(r'\') ||
      !RegExp(
        r'^https://(?:www\.|m\.)?youtube\.com/',
        caseSensitive: false,
      ).hasMatch(candidate)) {
    return false;
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      !const {
        'youtube.com',
        'www.youtube.com',
        'm.youtube.com',
      }.contains(uri.host.toLowerCase())) {
    return false;
  }
  if (channelIdFromProfileLink(candidate) != null) return true;
  List<String> segments;
  try {
    segments = uri.pathSegments.toList();
  } on FormatException {
    return false;
  }
  if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
  String? name;
  if (segments.length == 1 && segments.first.startsWith('@')) {
    name = segments.first.substring(1);
  } else if (segments.length == 2 &&
      const {'c', 'user'}.contains(segments.first)) {
    name = segments.last;
  }
  return name != null &&
      name.isNotEmpty &&
      name.length <= 100 &&
      name != '.' &&
      name != '..' &&
      !RegExp(r'[\s\x00-\x1f\x7f/@?#%\\]', unicode: true).hasMatch(name);
}

String _manualMembershipErrorMessage(BuildContext context, Object error) {
  if (error is AbuApiException) {
    final serverDetails = '${error.message} ${error.details ?? ''}'
        .toLowerCase();
    final legacyGoogleCheck =
        error.statusCode == 400 &&
        (serverDetails.contains('accesstoken') ||
            serverDetails.contains('google access token') ||
            serverDetails.contains('short-lived google'));
    if (error.statusCode == 404 || legacyGoogleCheck) {
      return abuText(
        context,
        'Membership checking needs a server update. Contact support.',
        'التحقق من العضوية يحتاج إلى تحديث الخادم. تواصل مع الدعم.',
      );
    }
  }
  return productionErrorMessage(error);
}

class ManualMembershipDialog extends StatefulWidget {
  const ManualMembershipDialog({super.key, required this.onCheck});
  final Future<YouTubeMembershipCheckResult> Function(String profileLink)
  onCheck;

  @override
  State<ManualMembershipDialog> createState() => _ManualMembershipDialogState();
}

class _ManualMembershipDialogState extends State<ManualMembershipDialog> {
  final _link = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onCheck(_link.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _manualMembershipErrorMessage(context, error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const Key('youtube-membership-check-dialog'),
      title: Text(
        abuText(context, 'Check YouTube membership', 'التحقق من عضوية يوتيوب'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  abuText(
                    context,
                    'Paste your channel profile link. The server matches its channel ID with the latest uploaded members list. No Google sign-in is required.',
                    'ألصق رابط ملف قناتك. يقارن الخادم معرّف القناة بأحدث قائمة أعضاء مرفوعة. لا يلزم تسجيل الدخول إلى Google.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('youtube-profile-link-input'),
                  controller: _link,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: abuText(
                      context,
                      'Your YouTube profile link',
                      'رابط قناتك على يوتيوب',
                    ),
                    hintText: 'https://www.youtube.com/@yourhandle',
                    errorMaxLines: 4,
                  ),
                  validator: (value) => isYouTubeProfileLink(value ?? '')
                      ? null
                      : abuText(
                          context,
                          'Paste your full YouTube profile link, such as https://youtube.com/@yourhandle or a /channel/UC… link. Video links are not supported.',
                          'ألصق رابط قناتك الكامل مثل https://youtube.com/@yourhandle أو رابط /channel/UC…. روابط الفيديو غير مدعومة.',
                        ),
                  onFieldSubmitted: (_) => _check(),
                ),
                const SizedBox(height: 12),
                Text(
                  abuText(
                    context,
                    'In YouTube, open your channel → Share → Copy link. The server resolves @handle links automatically. Membership is only as current as the last CSV upload.',
                    'افتح قناتك في يوتيوب ← مشاركة ← نسخ الرابط. يحوّل الخادم رابط @القناة تلقائياً. تعتمد حالة العضوية على أحدث ملف CSV مرفوع.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _check,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(
                    abuText(
                      context,
                      _busy ? 'Checking…' : 'Check membership',
                      _busy ? 'جارٍ التحقق…' : 'تحقق من العضوية',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(abuText(context, 'Cancel', 'إلغاء')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
