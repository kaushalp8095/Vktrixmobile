import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Server ka address login screen par set hota hai (e.g. https://api.yourdomain.com)
String baseUrl = 'https://vktrixmobile.onrender.com';

class Api {
  static String? token;
  static Map<String, dynamic>? user;
  /// Super admin kisi shop ka data dekh raha ho to (sirf chalu support session me)
  static int? viewShopId;
  /// Chalu support session ka reason (shop owner ko bhi yahi dikhta hai).
  static String? supportReason;
  /// Support session kab khatam hoga (server ke bache hue time se ginte hain).
  static DateTime? supportUntil;

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
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) throw Exception(body?['error'] ?? 'Error ${r.statusCode}');
    return body;
  }

  static Uri _u(String path, [Map<String, String>? q]) {
    final qp = {...?q, if (viewShopId != null) 'shop_id': '$viewShopId'};
    return Uri.parse('$baseUrl/api$path').replace(queryParameters: qp.isEmpty ? null : qp);
  }

  static Future<dynamic> get(String path, [Map<String, String>? q]) async =>
      _parse(await http.get(_u(path, q), headers: _h));
  /// Bina shop scope ke read (support access log): chalu support session ka
  /// `shop_id` yahan nahi judta, warna "sab shops ka log" ek shop me simat jata.
  static Future<dynamic> getUnscoped(String path) async =>
      _parse(await http.get(Uri.parse('$baseUrl/api$path'), headers: _h));
  static Future<dynamic> post(String path, Map body) async =>
      _parse(await http.post(_u(path), headers: _h, body: jsonEncode(body)));
  static Future<dynamic> put(String path, Map body) async =>
      _parse(await http.put(_u(path), headers: _h, body: jsonEncode(body)));
  static Future<dynamic> delete(String path) async =>
      _parse(await http.delete(_u(path), headers: _h));

  static Future<void> setServer(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final p = await SharedPreferences.getInstance();
    await p.setString('server', baseUrl);
  }

  static Future<void> login(String u, String pw) async {
    final r = await post('/auth/login', {'username': u, 'password': pw});
    token = r['token']; user = r['user']; viewShopId = null;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token!);
    await p.setString('user', jsonEncode(user));
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

String rs(dynamic v) {
  final n = num.tryParse('$v') ?? 0;
  return '₹${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},')}';
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
