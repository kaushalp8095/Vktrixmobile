import 'package:flutter/material.dart';
import 'api.dart';
import 'design/design.dart';
import 'screens/splash.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => IndigoMintTheme(
        builder: (light, dark) => MaterialApp(
          title: 'Vktrix Mobile',
          debugShowCheckedModeBanner: false,
          theme: light, darkTheme: dark, themeMode: ThemeMode.system,
          home: const SplashScreen(),
        ),
      );
}
