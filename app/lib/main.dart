import 'package:flutter/material.dart';
import 'api.dart';
import 'design/design.dart';
import 'screens/splash.dart';

/// Theme mode controller: system / light / dark, persisted via Api prefs.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  themeMode.value = switch (await Api.themeMode()) {
    'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system,
  };
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => IndigoMintTheme(
        builder: (light, dark) => ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) => MaterialApp(
            title: 'Vktrix Mobile',
            debugShowCheckedModeBanner: false,
            theme: light, darkTheme: dark, themeMode: mode,
            home: const SplashScreen(),
          ),
        ),
      );
}
