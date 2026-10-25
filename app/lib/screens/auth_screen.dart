import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _pass.text.isEmpty) return snack(context, 'أدخل البريد وكلمة المرور');
    if (_register && _name.text.trim().isEmpty) return snack(context, 'أدخل اسمك');
    setState(() => _busy = true);
    try {
      if (_register) {
        final res = await sb.auth.signUp(email: email, password: _pass.text, data: {'name': _name.text.trim()});
        if (res.session == null && mounted) {
          snack(context, 'تم التسجيل. فعّل حسابك من الرابط المرسل لبريدك ثم سجّل الدخول');
          setState(() => _register = false);
        }
      } else {
        await sb.auth.signInWithPassword(email: email, password: _pass.text);
      }
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: Image.asset('assets/logo.webp', width: 170),
                  ),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(controller: _name, decoration: const InputDecoration(hintText: 'الاسم')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'البريد الإلكتروني'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'كلمة المرور'),
                  ),
                  const SizedBox(height: 22),
                  GradientButton(text: _register ? 'إنشاء حساب' : 'تسجيل الدخول', loading: _busy, onTap: _submit),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(_register ? 'عندي حساب، تسجيل الدخول' : 'ما عندي حساب؟ سجّل الآن'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
