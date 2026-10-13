import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/pairing_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({Key? key}) : super(key: key);

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final partnerCodeCtrl = TextEditingController();
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    partnerCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final profile = authProvider.profile;

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context).pair)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: authProvider.isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, size: 64),
                      const SizedBox(height: 16),
                      Text(AppStrings.of(context).profileUnavailable, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        authProvider.lastError ?? AppStrings.of(context).pairingFailed,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).pair)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            if (profile.pairedWith != null) ...[
              const Icon(Icons.favorite, size: 64),
              const SizedBox(height: 16),
              Text(AppStrings.of(context).pairingAlreadyDone, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                AppStrings.of(context).pairingAlreadyDescription,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(AppStrings.of(context).backHome),
                ),
              ),
              const SizedBox(height: 24),
            ] else ...[
              Text(AppStrings.of(context).pair, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).primaryColor, width: 2),
              ),
              child: Column(
                children: [
                  Text(AppStrings.of(context).myCode, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SelectableText(
                    profile.pairCode,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 3),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: profile.pairCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${AppStrings.of(context).codeCopied} ✅')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(AppStrings.of(context).copy),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.of(context).shareCodeHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Text(AppStrings.of(context).pairingCode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
              ),
            TextField(
              controller: partnerCodeCtrl,
              decoration: InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.lock),
              ),
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () async {
                  FocusScope.of(context).unfocus();
                  setState(() => _error = null);
                  final code = partnerCodeCtrl.text.trim();
                  if (code.length != 6) {
                    setState(() => _error = AppStrings.of(context).invalidPairCode);
                    return;
                  }
                  setState(() => _isLoading = true);
                  final pairingService = PairingService(context.read<AuthProvider>().authService.client);
                  bool success = false;
                  try {
                    success = await pairingService.pairWithCode(profile.id, code);
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _error = '${AppStrings.of(context).pairingFailed}: ${e.toString()}';
                        _isLoading = false;
                      });
                    }
                    return;
                  }
                  if (success && mounted) {
                    final updatedProfile = await authProvider.authService.getProfile();
                    if (updatedProfile == null) {
                      if (mounted) {
                        setState(() {
                          _error = '${AppStrings.of(context).pairingFailed}: ${AppStrings.of(context).checkConnection}';
                          _isLoading = false;
                        });
                      }
                      return;
                    }

                    authProvider.updateProfile(updatedProfile);
                    partnerCodeCtrl.clear();
                    if (mounted) context.go('/home');
                  } else if (mounted) {
                    setState(() {
                      _error = '${AppStrings.of(context).pairingFailed}. ${AppStrings.of(context).checkConnection}';
                      _isLoading = false;
                    });
                  }
                },
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(AppStrings.of(context).pair),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }
}
