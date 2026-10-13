import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).signIn)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 60),
            Icon(Icons.favorite, size: 80, color: Theme.of(context).primaryColor),
            const SizedBox(height: 24),
            Text('Bestie', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 60),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context).error,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: emailCtrl,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).email,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).password,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Consumer<AuthProvider>(
              builder: (ctx, auth, _) => SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: auth.isLoading ? null : () async {
                    setState(() => _error = null);
                    if (emailCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                      setState(() => _error = AppStrings.of(context).invalidCredentials);
                      return;
                    }
                    final ok = await auth.signIn(emailCtrl.text, passwordCtrl.text);
                    if (!ok && mounted) {
                      setState(() => _error = auth.lastError ?? AppStrings.of(context).loginFailed);
                    } else if (ok && mounted) {
                      // Navigate to home or pairing
                      if (auth.isPaired) {
                        context.go('/home');
                      } else {
                        context.go('/pairing');
                      }
                    }
                  },
                  child: auth.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(AppStrings.of(context).signIn),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(AppStrings.of(context).noAccount + ' '),
              GestureDetector(
                onTap: () => context.go('/signup'),
                child: Text(AppStrings.of(context).signUp, style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
