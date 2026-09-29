import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';
import 'admin_home.dart';
import 'shop_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final u = TextEditingController(), p = TextEditingController(), server = TextEditingController(text: baseUrl);
  bool loading = false;

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      await Api.setServer(server.text);
      await Api.login(u.text.trim(), p.text);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => Api.isSuperAdmin ? const AdminHome() : const ShopHome()));
    } catch (e) {
      toast(context, '$e', err: true);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.phone_android, size: 80, color: Colors.indigo),
              const Text('Mobile Shop', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              field(u, 'Username'),
              field(p, 'Password', obscure: true),
              ExpansionTile(title: const Text('Server Setting', style: TextStyle(fontSize: 14)), tilePadding: EdgeInsets.zero,
                  children: [field(server, 'Server URL (e.g. https://api.myshop.com)', type: TextInputType.url)]),
              SizedBox(width: double.infinity, height: 48,
                  child: FilledButton(onPressed: loading ? null : _login,
                      child: loading ? const CircularProgressIndicator() : const Text('Login'))),
            ]),
          ),
        ),
      );
}
