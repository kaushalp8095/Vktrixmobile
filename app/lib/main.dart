import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/login.dart';
import 'screens/admin_home.dart';
import 'screens/shop_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true)),
      home: Api.token == null
          ? const LoginScreen()
          : (Api.isSuperAdmin ? const AdminHome() : const ShopHome()),
    );
  }
}
