import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../widgets/pre_auth_preferences.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).signUp)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const PreAuthPreferences(),
            const SizedBox(height: 20),
            Text(AppStrings.of(context).newAccount, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 40),
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
                    Text(AppStrings.of(context).error, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                  ],
                ),
              ),
            TextField(
              controller: usernameCtrl,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).username,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.person),
                helperText: AppStrings.of(context).usernameLengthHelp,
              ),
            ),
            const SizedBox(height: 16),
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
                helperText: AppStrings.of(context).passwordLengthHelp,
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
                    if (usernameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                      setState(() => _error = AppStrings.of(context).fillAllFields);
                      return;
                    }
                    final username = usernameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    if (username.length < 3 || username.length > 20) {
                      setState(() => _error = AppStrings.of(context).usernameInvalid);
                      return;
                    }
                    if (!email.contains('@')) {
                      setState(() => _error = AppStrings.of(context).emailInvalid);
                      return;
                    }
                    if (passwordCtrl.text.length < 6) {
                      setState(() => _error = AppStrings.of(context).passwordInvalid);
                      return;
                    }
                    final ok = await auth.signUp(email, passwordCtrl.text, username);
                    if (!ok && mounted) {
                      setState(() => _error = auth.lastError ?? AppStrings.of(context).signupFailed);
                    } else if (ok && mounted) {
                      // Keep the language selected on the signup screen in the
                      // new Supabase profile as well as local preferences.
                      final locale = context.read<LocaleProvider>();
                      await locale.setLocale(locale.locale.languageCode);
                      if (mounted) context.go('/pairing');
                    }
                  },
                  child: auth.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(AppStrings.of(context).signUp),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(AppStrings.of(context).alreadyAccount + ' '),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: Text(AppStrings.of(context).signIn, style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
