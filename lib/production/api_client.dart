import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AbuApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;
  final Duration? retryAfter;

  AbuApiException({
    required this.statusCode,
    required this.message,
    this.details,
    this.retryAfter,
  });

  @override
  String toString() => 'AbuApiException($statusCode): $message';
}

class _ApiCacheEntry {
  const _ApiCacheEntry(this.value, this.expiresAt);

  final dynamic value;
  final DateTime expiresAt;
}

class AbuApiClient {
  AbuApiClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = _normalizeBaseUrl(baseUrl ?? defaultBaseUrl),
      _client = httpClient ?? http.Client();

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.abu3meer.com/api/v1',
  );
  final String baseUrl;
  final http.Client _client;
  final Map<String, Future<dynamic>> _inFlightGets = {};
  final Map<String, _ApiCacheEntry> _publicGetCache = {};

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw ArgumentError('API_BASE_URL cannot be empty.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('API_BASE_URL must be a complete http or https URL.');
    }
    return normalized;
  }

  Future<Map<String, String>> _headers({bool requireAuth = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};

    final user = requireAuth ? FirebaseAuth.instance.currentUser : null;
    if (requireAuth && user != null) {
      try {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (error) {
        if (requireAuth) {
          throw AbuApiException(
            statusCode: 401,
            message: 'Could not refresh your sign-in session: $error',
          );
        }
      }
    }
    if (requireAuth && !headers.containsKey('Authorization')) {
      throw AbuApiException(
        statusCode: 401,
        message: 'Authentication required',
      );
    }

    return headers;
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    bool requireAuth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path')
        .replace(queryParameters: queryParams);
    final identity = requireAuth
        ? FirebaseAuth.instance.currentUser?.uid ?? 'signed-out'
        : 'public';
    final requestKey = '$identity:$uri';
    if (!requireAuth) {
      final cached = _publicGetCache[requestKey];
      if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
        return cached.value;
      }
    }
    final running = _inFlightGets[requestKey];
    if (running != null) return running;

    late final Future<dynamic> operation;
    operation = () async {
      final headers = await _headers(requireAuth: requireAuth);
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        final decoded = _handleResponse(response);
        if (!requireAuth) {
          _publicGetCache[requestKey] = _ApiCacheEntry(
            decoded,
            DateTime.now().add(const Duration(seconds: 15)),
          );
        }
        return decoded;
      } catch (error) {
        if (error is AbuApiException) rethrow;
        throw AbuApiException(
          statusCode: 0,
          message: 'Network connection failed: $error',
        );
      } finally {
        if (identical(_inFlightGets[requestKey], operation)) {
          _inFlightGets.remove(requestKey);
        }
      }
    }();
    _inFlightGets[requestKey] = operation;
    return operation;
  }

  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(requireAuth: requireAuth);
    if (body != null) headers['Content-Type'] = 'application/json';

    try {
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _handleResponse(response);
      _publicGetCache.clear();
      return decoded;
    } catch (e) {
      if (e is AbuApiException) rethrow;
      throw AbuApiException(
        statusCode: 0,
        message: 'Network connection failed: $e',
      );
    }
  }

  Future<dynamic> postMultipart(
    String path, {
    required List<int> bytes,
    required String fileName,
    String fieldName = 'file',
    Map<String, String> fields = const <String, String>{},
    bool requireAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(requireAuth: requireAuth);
    // MultipartRequest creates its own boundary-aware Content-Type header.
    headers.remove('Content-Type');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(fieldName, bytes, filename: fileName),
        );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      final decoded = _handleResponse(response);
      _publicGetCache.clear();
      return decoded;
    } catch (e) {
      if (e is AbuApiException) rethrow;
      throw AbuApiException(statusCode: 0, message: 'Image upload failed: $e');
    }
  }

  Future<dynamic> put(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(requireAuth: requireAuth);
    if (body != null) headers['Content-Type'] = 'application/json';

    try {
      final response = await _client
          .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _handleResponse(response);
      _publicGetCache.clear();
      return decoded;
    } catch (e) {
      if (e is AbuApiException) rethrow;
      throw AbuApiException(
        statusCode: 0,
        message: 'Network connection failed: $e',
      );
    }
  }

  Future<dynamic> delete(String path, {bool requireAuth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(requireAuth: requireAuth);

    try {
      final response = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      final decoded = _handleResponse(response);
      _publicGetCache.clear();
      return decoded;
    } catch (e) {
      if (e is AbuApiException) rethrow;
      throw AbuApiException(
        statusCode: 0,
        message: 'Network connection failed: $e',
      );
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return response.body;
      }
    }

    String message = 'API request failed with status ${response.statusCode}';
    try {
      final errorJson = jsonDecode(response.body);
      if (errorJson is Map && errorJson.containsKey('message')) {
        message = errorJson['message'];
      }
    } catch (_) {}

    final retryAfterSeconds = int.tryParse(
      response.headers['retry-after']?.trim() ?? '',
    );
    throw AbuApiException(
      statusCode: response.statusCode,
      message: message,
      details: response.body,
      retryAfter: retryAfterSeconds == null
          ? null
          : Duration(seconds: retryAfterSeconds),
    );
  }
}
