import 'dart:async';

import 'package:flutter/material.dart';
import 'api.dart';
import 'design/components/components.dart';
import 'design/design.dart';
import 'screens/login.dart';
import 'screens/splash.dart';

/// Theme mode controller: system / light / dark, persisted via Api prefs.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// 401 hone par login screen tak pahunchne ke liye (koi bhi screen ho).
final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  themeMode.value = switch (await Api.themeMode()) {
    'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system,
  };
  Api.onUnauthorized = _routeToLogin;
  runApp(const MyApp());
}

/// Session expire ho gayi (30 din, ya password kisi aur phone se badla) — warna
/// har tab "Couldn't load…" par atak jata aur login ka koi raasta nahi bachta.
void _routeToLogin() {
  unawaited(Api.logout());
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  nav.pushAndRemoveUntil(
    SharedAxisRoute<dynamic>(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => IndigoMintTheme(
        builder: (light, dark) => ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) => MaterialApp(
            title: 'Vktrix Mobile',
            navigatorKey: appNavigatorKey,
            debugShowCheckedModeBanner: false,
            theme: light, darkTheme: dark, themeMode: mode,
            home: const SplashScreen(),
          ),
        ),
      );
}
