import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/home/presentation/screens/home_screen.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class KpssKolayApp extends StatelessWidget {
  final SupabaseClient? client;
  final AppConfig config;

  const KpssKolayApp({
    super.key,
    required this.config,
    this.client,
  });

  @override
  Widget build(BuildContext context) {
    if (!config.isConfigured || client == null) {
      return MaterialApp(
        title: 'KPSS Kolay',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: const _ConfigurationScreen(),
      );
    }

    return MultiProvider(
      providers: AppProviders.create(client!),
      child: const _ConfiguredApp(),
    );
  }
}

class _ConfiguredApp extends StatelessWidget {
  const _ConfiguredApp();

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final router = AppRouter(authProvider).router;

    return MaterialApp.router(
      title: 'KPSS Kolay',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ConfigurationScreen extends StatelessWidget {
  const _ConfigurationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'KPSS Kolay yapılandırılmamış',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'SUPABASE_URL ve SUPABASE_ANON_KEY değerlerini '
                  'build sırasında --dart-define ile sağlayın.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
