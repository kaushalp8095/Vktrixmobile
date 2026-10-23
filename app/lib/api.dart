import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Default server. Login/Profile se badla ja sakta hai; reset bhi isi par jata hai.
const defaultBaseUrl = 'https://vktrixmobile.onrender.com';

/// Server ka address login screen par set hota hai (e.g. https://api.yourdomain.com)
String baseUrl = defaultBaseUrl;

/// Har request ka maximum wait. Server (Render free) so gaya ho, Wi-Fi captive
/// portal ho, ya connection mar raha ho — screen hamesha spinner par na atke.
const apiRequestTimeout = Duration(seconds: 30);

/// Server ka structured error: wahi message jo pehle `Exception` me tha, saath me
/// HTTP status aur (ho to) machine-readable `code` — jaise `shop_has_history`.
/// `toString()` jaan-boojh kar pehle jaisa hai, kyunki har screen `'$e'` hi
/// dikhati hai aur wahan se `Exception: ` strip hota hai.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  const ApiException(this.message, this.statusCode, [this.code]);
  @override
  String toString() => 'Exception: $message';
}

class Api {
  static String? token;
  static Map<String, dynamic>? user;
  /// Super admin kisi shop ka data dekh raha ho to (sirf chalu support session me)
  static int? viewShopId;
  /// Chalu support session ka reason (shop owner ko bhi yahi dikhta hai).
  static String? supportReason;
  /// Support session kab khatam hoga (server ke bache hue time se ginte hain).
  static DateTime? supportUntil;

  /// 401 (token expired / password badal gaya) par ek hi baar chalta hai.
  /// `main.dart` ise login screen par bhejne ke liye set karta hai.
  static void Function()? onUnauthorized;
  static bool _unauthorizedHandled = false;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('server') ?? baseUrl;
    token = p.getString('token');
    final u = p.getString('user');
    if (u != null) user = jsonDecode(u);
  }

  static Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    token = null; user = null;
    _unauthorizedHandled = false;
    endSupport();
  }

  // ---- Temporary support access (Super Admin) ----
  /// Super admin chalu support session me hai: shop data ab read-only hai.
  static bool get supportReadOnly => isSuperAdmin && viewShopId != null;
  static bool get supportActive => supportReadOnly;
  static Duration get supportRemaining {
    final until = supportUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
  static bool get supportExpired => supportReadOnly && supportUntil != null && supportRemaining == Duration.zero;
  /// Session shuru (backend reason + time limit + log ke saath deta hai).
  static void beginSupport({required int shopId, required String reason, required int expiresInMs}) {
    viewShopId = shopId;
    supportReason = reason;
    supportUntil = DateTime.now().add(Duration(milliseconds: expiresInMs));
  }
  static void endSupport() { viewShopId = null; supportReason = null; supportUntil = null; }

  static Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static dynamic _parse(http.Response r) {
    final body = _decode(r.body);
    final message = body is Map ? body['error'] : null;
    final code = body is Map && body['code'] is String ? body['code'] as String : null;
    if (r.statusCode == 401) _handleUnauthorized();
    if (r.statusCode >= 400) {
      throw ApiException(message is String && message.trim().isNotEmpty ? message : 'Error ${r.statusCode}',
          r.statusCode, code);
    }
    return body;
  }

  /// `_parse` ka test-friendly roop (network ke bina error mapping check karne ke liye).
  @visibleForTesting
  static dynamic parseResponse(http.Response r) => _parse(r);

  /// Body JSON na ho (proxy ka HTML error page), khaali ho, ya toota ho — screen
  /// par raw `FormatException` dikhane ke bajaye null lautte hain, aur asli
  /// status code se message banta hai.
  static dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    try { return jsonDecode(body); } catch (_) { return null; }
  }

  static void _handleUnauthorized() {
    // Login ke waqt token pehle se nahi hota; sirf expired/revoked session count kare.
    if (token == null || _unauthorizedHandled) return;
    _unauthorizedHandled = true;
    onUnauthorized?.call();
  }

  /// Har request par timeout, warna dead server par screen hamesha wait karti hai.
  static Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(apiRequestTimeout);
    } on TimeoutException {
      throw Exception('The server did not respond in time. Check your internet and try again.');
    }
  }

  static Uri _u(String path, [Map<String, String>? q]) {
    final qp = {...?q, if (viewShopId != null) 'shop_id': '$viewShopId'};
    return Uri.parse('$baseUrl/api$path').replace(queryParameters: qp.isEmpty ? null : qp);
  }

  static Future<dynamic> get(String path, [Map<String, String>? q]) async =>
      _parse(await _send(http.get(_u(path, q), headers: _h)));
  /// Bina shop scope ke read (support access log): chalu support session ka
  /// `shop_id` yahan nahi judta, warna "sab shops ka log" ek shop me simat jata.
  static Future<dynamic> getUnscoped(String path) async =>
      _parse(await _send(http.get(Uri.parse('$baseUrl/api$path'), headers: _h)));
  static Future<dynamic> post(String path, Map body) async =>
      _parse(await _send(http.post(_u(path), headers: _h, body: jsonEncode(body))));
  static Future<dynamic> put(String path, Map body) async =>
      _parse(await _send(http.put(_u(path), headers: _h, body: jsonEncode(body))));
  static Future<dynamic> delete(String path) async =>
      _parse(await _send(http.delete(_u(path), headers: _h)));

  /// Server address validation — login screen aur Profile dono yahi use karte hain.
  /// `null` = theek hai, warna user ko dikhane layak message.
  static String? validateServer(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return 'Enter the server address';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return 'Enter the full address, like https://vktrixmobile.onrender.com';
    }
    if (uri.scheme == 'http') return 'Use https:// so your password is not sent unencrypted';
    if (uri.scheme != 'https') return 'Address must start with https://';
    return null;
  }

  static Future<void> setServer(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    // Khaali/invalid URL kabhi save na ho — warna app ka har request fail hota hai.
    if (validateServer(clean) != null) throw Exception('Enter the full server address, like https://vktrixmobile.onrender.com');
    baseUrl = clean;
    await saveServer();
  }

  /// Current `baseUrl` ko prefs me likhta hai (reset ke liye bhi yahi).
  static Future<void> saveServer() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('server', baseUrl);
  }

  /// Default server par wapas; wahi value prefs me save hoti hai.
  static Future<void> resetServer() async {
    baseUrl = defaultBaseUrl;
    final p = await SharedPreferences.getInstance();
    await p.setString('server', baseUrl);
  }

  static Future<void> login(String u, String pw, {bool rememberMe = true}) async {
    final r = await post('/auth/login', {'username': u, 'password': pw});
    token = r['token']; user = r['user']; viewShopId = null;
    _unauthorizedHandled = false;
    final p = await SharedPreferences.getInstance();
    if (rememberMe) {
      await p.setString('token', token!);
      await p.setString('user', jsonEncode(user));
    } else {
      await p.remove('token');
      await p.remove('user');
    }
  }

  static bool get isSuperAdmin => user?['role'] == 'superadmin';

  // ---- Preferences (theme, onboarding) ----
  static Future<String> themeMode() async => (await SharedPreferences.getInstance()).getString('theme_mode') ?? 'system';
  static Future<void> setThemeMode(String m) async => (await SharedPreferences.getInstance()).setString('theme_mode', m);
  static Future<bool> onboardingSeen() async => (await SharedPreferences.getInstance()).getBool('onboarding_seen') ?? false;
  static Future<void> setOnboardingSeen() async => (await SharedPreferences.getInstance()).setBool('onboarding_seen', true);
  static Future<void> changePassword(String oldPw, String newPw) async =>
      post('/auth/change-password', {'old_password': oldPw, 'new_password': newPw});
}

/// Indian grouping (1,25,000) for a whole number already rendered as text.
String _group(String digits) =>
    digits.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},');

/// Money, poore app me ek hi tarah: `₹12,500` jab paise na hon, aur
/// `₹12,500.50` jab hon (`.00` kabhi force nahi hota). Pehle `toStringAsFixed(0)`
/// tha — ledger me 12,500.50 pada hota tha par invoice/customer ko ₹12,501
/// dikhta tha. Ab rupees + paise cents me ginte hain, isliye rounding ka jhagda
/// nahi (₹12500.50 → 500.50, not round-to-rupee).
String rs(dynamic v) {
  final n = num.tryParse('$v') ?? 0;
  final cents = (n.abs() * 100).round();
  final paise = cents % 100;
  final sign = cents != 0 && n < 0 ? '-' : '';
  return '$sign₹${_group('${cents ~/ 100}')}${paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}'}';
}



bool validImei(String s) {
  if (!RegExp(r'^\d{15}$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 15; i++) {
    var d = int.parse(s[i]);
    if (i % 2 == 1) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
  }
  return sum % 10 == 0;
}
