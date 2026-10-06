import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../app_config.dart';
import '../storage/secure_store.dart';

/// Typed error raised by [ApiClient].
///
/// [code] is the machine code from the server (`detail.code`) or one of the
/// client-side codes: `OFFLINE`, `TIMEOUT`, `NETWORK`, `BAD_RESPONSE`,
/// `UNAUTHORIZED`.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.statusCode,
    required this.messageBn,
    this.detail,
  });

  final String code;
  final int statusCode;
  final String messageBn;

  /// Raw `detail` object from the server when available.
  final Map<String, dynamic>? detail;

  bool get isOffline =>
      code == 'OFFLINE' || code == 'NETWORK' || code == 'TIMEOUT';
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode $code): $messageBn';
}

/// Lightweight JSON HTTP client for `AppConfig.baseUrl`.
///
/// - adds `Authorization: Bearer` from [SecureStore]
/// - on 401 refreshes the token once (single-flight) and retries
/// - maps errors to [ApiException] with Bangla messages
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const Duration timeout = Duration(seconds: 20);

  final http.Client _http = http.Client();
  final SecureStore _store = SecureStore.instance;

  /// Called after a successful token refresh with the full refresh payload
  /// (same shape as login) so providers can update shop/license.
  void Function(Map<String, dynamic> payload)? onSessionRefreshed;

  /// Called when refresh fails permanently (refresh token rejected).
  void Function()? onSessionExpired;

  Future<Map<String, dynamic>>? _refreshing;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  /// Quick connectivity probe (no network call).
  static Future<bool> isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // assume online if the plugin fails
    }
  }

  // ---------------- Public helpers ----------------

  Future<dynamic> get(String path,
          {Map<String, String>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path,
          {Object? body, bool auth = true, bool retryOn401 = true}) =>
      _send('POST', path, body: body, auth: auth, retryOn401: retryOn401);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  /// A file part for [postMultipart].
  static http.MultipartFile fileFromBytes(
    String field,
    List<int> bytes, {
    required String filename,
    String mimeType = 'image/jpeg',
  }) =>
      http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      );

  /// `multipart/form-data` POST (registration / KYC uploads).
  ///
  /// Same error mapping as [post]; 60 s timeout because of the file payload.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    bool auth = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!await isOnline()) {
      throw ApiException(
        code: 'OFFLINE',
        statusCode: 0,
        messageBn: 'ইন্টারনেট সংযোগ নেই। সংযোগ চালু করে আবার চেষ্টা করুন।',
      );
    }
    final req = http.MultipartRequest('POST', _uri(path));
    req.headers['Accept'] = 'application/json';
    if (auth) {
      final token = await _store.accessToken;
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
    }
    req.fields.addAll(fields);
    req.files.addAll(files);

    http.Response res;
    try {
      final streamed = await _http.send(req).timeout(timeout);
      res = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        code: 'TIMEOUT',
        statusCode: 0,
        messageBn: 'আপলোড শেষ হয়নি। ইন্টারনেট ভালো জায়গায় গিয়ে আবার চেষ্টা করুন।',
      );
    } on HandshakeException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'নিরাপদ সংযোগ স্থাপন করা যায়নি।',
      );
    } on SocketException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'সার্ভারের সাথে সংযোগ করা যাচ্ছে না।',
      );
    } on http.ClientException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'সার্ভারের সাথে সংযোগ করা যাচ্ছে না।',
      );
    }
    return _handle(res);
  }

  // ---------------- Core ----------------

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    bool retryOn401 = true,
  }) async {
    if (!await isOnline()) {
      throw ApiException(
        code: 'OFFLINE',
        statusCode: 0,
        messageBn: 'ইন্টারনেট সংযোগ নেই। সংযোগ চালু করে আবার চেষ্টা করুন।',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await _store.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response res;
    try {
      res = await _raw(method, _uri(path, query), headers, body)
          .timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        code: 'TIMEOUT',
        statusCode: 0,
        messageBn: 'সার্ভার সাড়া দিচ্ছে না। একটু পরে আবার চেষ্টা করুন।',
      );
    } on HandshakeException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'নিরাপদ সংযোগ স্থাপন করা যায়নি।',
      );
    } on SocketException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'সার্ভারের সাথে সংযোগ করা যাচ্ছে না।',
      );
    } on http.ClientException {
      throw ApiException(
        code: 'NETWORK',
        statusCode: 0,
        messageBn: 'সার্ভারের সাথে সংযোগ করা যাচ্ছে না।',
      );
    }

    if (res.statusCode == 401 && auth && retryOn401) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        return _send(method, path,
            query: query, body: body, auth: auth, retryOn401: false);
      }
    }

    return _handle(res);
  }

  Future<http.Response> _raw(
      String method, Uri uri, Map<String, String> headers, Object? body) {
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _http.delete(uri, headers: headers, body: encoded);
      default:
        throw ArgumentError('Unsupported method $method');
    }
  }

  dynamic _handle(http.Response res) {
    final status = res.statusCode;
    dynamic json;
    if (res.bodyBytes.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        json = null;
      }
    }

    if (status >= 200 && status < 300) return json;

    // FastAPI style: {"detail": "..."} or {"detail": {"code": ..., ...}}
    String code = 'HTTP_$status';
    String message = _defaultMessage(status);
    Map<String, dynamic>? detail;
    if (json is Map<String, dynamic>) {
      final d = json['detail'];
      if (d is Map<String, dynamic>) {
        detail = d;
        code = (d['code'] as String?) ?? code;
        message = (d['message_bn'] as String?) ??
            (d['hint'] as String?) ??
            (d['message'] as String?) ??
            message;
        // Field-level validation errors: show the server's own reasons.
        final errs = d['errors'];
        if (errs is List && errs.isNotEmpty) {
          final parts = <String>[];
          for (final e in errs) {
            if (e is Map) {
              final msg = (e['msg'] ?? '').toString();
              final loc = (e['loc'] is List && (e['loc'] as List).isNotEmpty) ? (e['loc'] as List).last.toString() : '';
              if (msg.isNotEmpty) parts.add(loc.isEmpty ? msg : '$loc: $msg');
            }
          }
          if (parts.isNotEmpty) message = parts.join('\n');
        }
      } else if (d is String) {
        message = _translateDetail(d, status);
      } else if (d is List) {
        code = 'VALIDATION';
        message = 'তথ্য সঠিকভাবে পূরণ করুন।';
      }
    }
    if (status == 401 && code == 'HTTP_401') code = 'UNAUTHORIZED';

    throw ApiException(
      code: code,
      statusCode: status,
      messageBn: message,
      detail: detail,
    );
  }

  String _translateDetail(String d, int status) {
    final lower = d.toLowerCase();
    if ((lower.contains('invalid') && lower.contains('credential')) ||
        lower.contains('incorrect') ||
        lower.contains('invalid phone') ||
        lower.contains('wrong')) {
      return 'ফোন নম্বর বা পাসওয়ার্ড ভুল।';
    }
    // Non-ASCII text is most likely already Bangla from the server.
    if (d.runes.any((r) => r > 0x7f)) return d;
    return _defaultMessage(status);
  }

  String _defaultMessage(int status) {
    switch (status) {
      case 400:
        return 'অনুরোধটি সঠিক নয়।';
      case 401:
        return 'ফোন নম্বর বা পাসওয়ার্ড ভুল।';
      case 403:
        return 'এই কাজের অনুমতি নেই।';
      case 404:
        return 'তথ্য পাওয়া যায়নি।';
      case 413:
        return 'ছবির সাইজ অনেক বড়। আবার ছবি তুলুন।';
      case 422:
        return 'তথ্য সঠিকভাবে পূরণ করুন।';
      case 409:
        return 'অন্য ফোনে লগইন আছে, অ্যাডমিনের সাথে যোগাযোগ করুন।';
      case 423:
        return 'এই ডিভাইসটি লক করা আছে।';
      case 429:
        return 'অনেকবার চেষ্টা করা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।';
      default:
        if (status >= 500) {
          return 'সার্ভারে সমস্যা হয়েছে। পরে আবার চেষ্টা করুন।';
        }
        return 'কিছু একটা সমস্যা হয়েছে।';
    }
  }

  // ---------------- Refresh (single-flight) ----------------

  /// Refreshes the session using the stored refresh token.
  /// Returns true on success. Concurrent callers share one in-flight request.
  Future<bool> _refreshTokens() async {
    final inFlight = _refreshing;
    if (inFlight != null) {
      try {
        await inFlight;
        return true;
      } catch (_) {
        return false;
      }
    }
    final completer = Completer<Map<String, dynamic>>();
    _refreshing = completer.future;
    completer.future.ignore(); // errors are observed via the return value
    try {
      final refresh = await _store.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        throw ApiException(
            code: 'UNAUTHORIZED', statusCode: 401, messageBn: 'লগইন করুন।');
      }
      final res = await _http
          .post(
            _uri('/app/auth/refresh'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(timeout);
      final json = _handle(res);
      if (json is! Map<String, dynamic> || json['access_token'] == null) {
        throw ApiException(
            code: 'BAD_RESPONSE', statusCode: res.statusCode, messageBn: '');
      }
      await _store.saveTokens(
        access: json['access_token'] as String,
        refresh: (json['refresh_token'] as String?) ?? refresh,
      );
      if (json['shop'] is Map<String, dynamic>) {
        await _store.saveShop(json['shop'] as Map<String, dynamic>);
      }
      if (json['license'] is Map<String, dynamic>) {
        await _store.saveLicense(json['license'] as Map<String, dynamic>);
      }
      onSessionRefreshed?.call(json);
      completer.complete(json);
      return true;
    } catch (e) {
      completer.completeError(e);
      // Only drop the session if the server explicitly rejected the token.
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await _store.clearTokens();
        onSessionExpired?.call();
      }
      return false;
    } finally {
      _refreshing = null;
    }
  }
}
