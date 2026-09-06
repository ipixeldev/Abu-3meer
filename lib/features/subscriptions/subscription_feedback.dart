import 'dart:convert';

import '../../production/api_client.dart';

/// Keep an activation outage distinct from a declined or missing purchase.
/// These messages never grant access or expose raw server responses.
class SubscriptionFeedback {
  const SubscriptionFeedback(this.english, this.arabic);

  final String english;
  final String arabic;

  static SubscriptionFeedback serverFailure(Object error) {
    if (error is AbuApiException) {
      if (error.statusCode == 404) {
        return const SubscriptionFeedback(
          'Membership activation needs a server update. Contact support; refreshing again cannot fix this yet. Do not purchase again.',
          'يتطلب تفعيل العضوية تحديث الخادم. تواصل مع الدعم؛ إعادة التحديث لن تحل المشكلة حالياً. لا تشترِ مرة أخرى.',
        );
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const SubscriptionFeedback(
          'Your sign-in could not be confirmed. Sign in again, then refresh access. Do not purchase again.',
          'تعذر تأكيد تسجيل دخولك. سجّل الدخول مجدداً ثم حدّث الصلاحيات. لا تشترِ مرة أخرى.',
        );
      }
      if (error.statusCode == 0) {
        return const SubscriptionFeedback(
          'Could not reach the membership server. Check your connection and try Refresh access again. Do not purchase again.',
          'تعذر الاتصال بخادم العضوية. تحقق من اتصالك ثم أعد تحديث الصلاحيات. لا تشترِ مرة أخرى.',
        );
      }
      if (error.statusCode == 429) {
        return const SubscriptionFeedback(
          'Too many refresh requests. Wait a minute, then try again. Do not purchase again.',
          'تم إرسال طلبات تحديث كثيرة. انتظر دقيقة ثم حاول مجدداً. لا تشترِ مرة أخرى.',
        );
      }
      Object? details = error.details;
      if (details is String) {
        try {
          details = jsonDecode(details);
        } on FormatException {
          details = null;
        }
      }
      if (details is Map && details['code'] == 'subscriptions_not_configured') {
        return const SubscriptionFeedback(
          'Membership activation is not configured on the server yet. Please contact support. Do not purchase again.',
          'لم يكتمل إعداد تفعيل العضوية على الخادم بعد. يرجى التواصل مع الدعم. لا تشترِ مرة أخرى.',
        );
      }
    }
    return const SubscriptionFeedback(
      'The membership server could not confirm access. Try again later or contact support. Do not purchase again.',
      'تعذر على خادم العضوية تأكيد الصلاحيات. حاول لاحقاً أو تواصل مع الدعم. لا تشترِ مرة أخرى.',
    );
  }

  static SubscriptionFeedback checked({
    required bool serverActive,
    required bool storeActive,
    required bool isSandbox,
  }) {
    if (serverActive) {
      return const SubscriptionFeedback(
        'Membership confirmed. Your access and subscriber badge have been refreshed.',
        'تم تأكيد العضوية وتحديث صلاحياتك وشارة الاشتراك.',
      );
    }
    if (storeActive && isSandbox) {
      return const SubscriptionFeedback(
        'A test subscription was found, but server access is not active. Contact support to check test-purchase settings and account linking. Do not purchase again.',
        'تم العثور على اشتراك تجريبي، لكن صلاحيات الخادم غير مفعّلة. تواصل مع الدعم للتحقق من إعدادات المشتريات التجريبية وربط الحساب. لا تشترِ مرة أخرى.',
      );
    }
    if (storeActive) {
      return const SubscriptionFeedback(
        'Your store subscription was found, but membership activation is not confirmed. Contact support if it stays pending. Do not purchase again.',
        'تم العثور على اشتراكك في المتجر، لكن لم يتم تأكيد تفعيل العضوية. تواصل مع الدعم إذا استمر الانتظار. لا تشترِ مرة أخرى.',
      );
    }
    return const SubscriptionFeedback(
      'No active store subscription was found for this app account. If the store says you already subscribed, use Restore purchases. YouTube membership is checked separately.',
      'لم يُعثر على اشتراك متجر نشط لحساب التطبيق هذا. إذا أبلغك المتجر أنك مشترك بالفعل، استخدم استعادة المشتريات. يتم فحص عضوية يوتيوب بشكل منفصل.',
    );
  }
}
