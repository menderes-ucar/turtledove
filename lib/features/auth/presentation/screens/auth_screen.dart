import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _register = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'KPSS Kolay',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                if (_register) ...[
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: provider.loading ? null : (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (provider.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    provider.error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: provider.loading ? null : _submit,
                    child: provider.loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_register ? 'Kayıt Ol' : 'Giriş Yap'),
                  ),
                ),
                TextButton(
                  onPressed: provider.loading
                      ? null
                      : () {
                          setState(() {
                            _register = !_register;
                          });
                        },
                  child: Text(
                    _register
                        ? 'Zaten hesabım var'
                        : 'Hesap oluştur',
                  ),
                ),
                if (!_register)
                  TextButton(
                    onPressed: provider.loading ? null : _resetPassword,
                    child: const Text('Şifremi unuttum'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final provider = context.read<AuthProvider>();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      return;
    }

    try {
      if (_register) {
        await provider.signUp(
          email,
          password,
          name: _nameController.text.trim(),
        );
      } else {
        await provider.signIn(email, password);
      }

      // GoRouter observes AuthProvider and redirects to Home after login.
      // Do not pop the route here; the login page may be the root route.
      if (!mounted) {
        return;
      }
    } catch (_) {
      // AuthProvider exposes the user-facing error through its state.
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      return;
    }

    try {
      await context.read<AuthProvider>().resetPassword(email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şifre sıfırlama e-postası gönderildi.'),
        ),
      );
    } catch (_) {
      // AuthProvider exposes the user-facing error through its state.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
