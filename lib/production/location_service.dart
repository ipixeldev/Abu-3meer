import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class CountryInfo {
  final String code;
  final String nameAr;
  final String nameEn;
  final String flag;

  const CountryInfo({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.flag,
  });
}

class LocationService {
  static const List<CountryInfo> supportedCountries = [
    CountryInfo(
      code: 'SA',
      nameAr: 'المملكة العربية السعودية',
      nameEn: 'Saudi Arabia',
      flag: '🇸🇦',
    ),
    CountryInfo(
      code: 'AE',
      nameAr: 'الإمارات العربية المتحدة',
      nameEn: 'United Arab Emirates',
      flag: '🇦🇪',
    ),
    CountryInfo(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt', flag: '🇪🇬'),
    CountryInfo(code: 'KW', nameAr: 'الكويت', nameEn: 'Kuwait', flag: '🇰🇼'),
    CountryInfo(code: 'QA', nameAr: 'قطر', nameEn: 'Qatar', flag: '🇶🇦'),
    CountryInfo(code: 'BH', nameAr: 'البحرين', nameEn: 'Bahrain', flag: '🇧🇭'),
    CountryInfo(code: 'OM', nameAr: 'عُمان', nameEn: 'Oman', flag: '🇴🇲'),
    CountryInfo(code: 'JO', nameAr: 'الأردن', nameEn: 'Jordan', flag: '🇯🇴'),
    CountryInfo(code: 'IQ', nameAr: 'العراق', nameEn: 'Iraq', flag: '🇮🇶'),
    CountryInfo(code: 'MA', nameAr: 'المغرب', nameEn: 'Morocco', flag: '🇲🇦'),
    CountryInfo(code: 'DZ', nameAr: 'الجزائر', nameEn: 'Algeria', flag: '🇩🇿'),
    CountryInfo(code: 'TN', nameAr: 'تونس', nameEn: 'Tunisia', flag: '🇹🇳'),
    CountryInfo(code: 'LY', nameAr: 'ليبيا', nameEn: 'Libya', flag: '🇱🇾'),
    CountryInfo(code: 'SD', nameAr: 'السودان', nameEn: 'Sudan', flag: '🇸🇩'),
    CountryInfo(code: 'LB', nameAr: 'لبنان', nameEn: 'Lebanon', flag: '🇱🇧'),
    CountryInfo(
      code: 'PS',
      nameAr: 'فلسطين',
      nameEn: 'Palestine',
      flag: '🇵🇸',
    ),
    CountryInfo(code: 'YE', nameAr: 'اليمن', nameEn: 'Yemen', flag: '🇾🇪'),
    CountryInfo(code: 'SY', nameAr: 'سوريا', nameEn: 'Syria', flag: '🇸🇾'),
    CountryInfo(code: 'TR', nameAr: 'تركيا', nameEn: 'Turkey', flag: '🇹🇷'),
    CountryInfo(
      code: 'GB',
      nameAr: 'المملكة المتحدة',
      nameEn: 'United Kingdom',
      flag: '🇬🇧',
    ),
    CountryInfo(
      code: 'US',
      nameAr: 'الولايات المتحدة',
      nameEn: 'United States',
      flag: '🇺🇸',
    ),
    CountryInfo(code: 'DE', nameAr: 'ألمانيا', nameEn: 'Germany', flag: '🇩🇪'),
    CountryInfo(code: 'FR', nameAr: 'فرنسا', nameEn: 'France', flag: '🇫🇷'),
    CountryInfo(code: 'ES', nameAr: 'إسبانيا', nameEn: 'Spain', flag: '🇪🇸'),
    CountryInfo(code: 'IT', nameAr: 'إيطاليا', nameEn: 'Italy', flag: '🇮🇹'),
    CountryInfo(code: 'SE', nameAr: 'السويد', nameEn: 'Sweden', flag: '🇸🇪'),
  ];

  static CountryInfo getCountryByCode(String code) {
    return _countryByCodeOrNull(code) ??
        const CountryInfo(
          code: 'SA',
          nameAr: 'المملكة العربية السعودية',
          nameEn: 'Saudi Arabia',
          flag: '🇸🇦',
        );
  }

  static CountryInfo? _countryByCodeOrNull(String code) {
    final clean = code.toUpperCase().trim();
    for (final country in supportedCountries) {
      if (country.code == clean) return country;
    }
    return null;
  }

  /// Requests location permission from the device and detects the user's country code.
  /// Falls back smoothly to IP-based detection or device locale.
  static Future<CountryInfo> detectUserCountry() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        if (serviceEnabled) {
          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 4),
              ),
            );

            final countryCode = await _reverseGeocodeToCountry(
              position.latitude,
              position.longitude,
            );
            final country = countryCode == null
                ? null
                : _countryByCodeOrNull(countryCode);
            if (country != null) {
              return country;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Fallback: IP-based lookup
    final ipCountry = await _detectCountryFromIp();
    final ipMatch = ipCountry == null ? null : _countryByCodeOrNull(ipCountry);
    if (ipMatch != null) return ipMatch;

    // If location access is declined or unavailable, prefer the device's
    // country setting before falling back to the editable onboarding default.
    final localeCode = PlatformDispatcher.instance.locale.countryCode;
    final localeMatch = localeCode == null
        ? null
        : _countryByCodeOrNull(localeCode);
    if (localeMatch != null) return localeMatch;

    // Default locale fallback
    return const CountryInfo(
      code: 'SA',
      nameAr: 'المملكة العربية السعودية',
      nameEn: 'Saudi Arabia',
      flag: '🇸🇦',
    );
  }

  static Future<String?> _reverseGeocodeToCountry(
    double lat,
    double lng,
  ) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=3',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'Abu3meerApp/1.0'})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final code = data['address']?['country_code']?.toString().toUpperCase();
        if (code != null) return code;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _detectCountryFromIp() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['country_code']?.toString().toUpperCase();
      }
    } catch (_) {}
    return null;
  }
}
