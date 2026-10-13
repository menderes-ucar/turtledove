import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../localization/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _usernameController;
  bool _saving = false;
  bool _uploading = false;
  bool _changingStatus = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    _usernameController = TextEditingController(text: profile?.username ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStrings.of(context).username} cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<AuthProvider>().updateProfileDetails(username: value);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? AppStrings.of(context).profileUpdated : AppStrings.of(context).profileUpdateFailed)),
    );
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      final ok = await context.read<AuthProvider>().uploadAvatar(file);
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? AppStrings.of(context).photoUpdated : AppStrings.of(context).photoUploadFailed)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).photoSelectFailed)));
    }
  }

  Future<void> _changeStatus(String status) async {
    if (_changingStatus) return;
    setState(() => _changingStatus = true);
    final ok = await context.read<AuthProvider>().setPresence(status);
    if (!mounted) return;
    setState(() => _changingStatus = false);
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).profileUpdateFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final profile = auth.profile;
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: Text(strings.profile)),
            body: Center(child: auth.isLoading ? const CircularProgressIndicator() : Text(AppStrings.of(context).profileUnavailable)),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(strings.profile)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 58,
                      backgroundImage: profile.avatarUrl == null ? null : NetworkImage(profile.avatarUrl!),
                      child: profile.avatarUrl == null ? const Icon(Icons.person, size: 58) : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: FloatingActionButton.small(
                        onPressed: _uploading ? null : _pickAvatar,
                        child: _uploading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.camera_alt),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _usernameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: AppStrings.of(context).username, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _saveUsername,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: Text(AppStrings.of(context).save),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tag_rounded),
                  title: Text(AppStrings.of(context).pairingCode),
                  subtitle: Text(profile.pairCode, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: profile.pairCode));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.of(context).codeCopied)));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppStrings.of(context).status, style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: {'online', 'away', 'offline'}.contains(profile.status) ? profile.status : 'online',
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        suffixIcon: _changingStatus ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                      ),
                      items: [
                        DropdownMenuItem(value: 'online', child: Text(AppStrings.of(context).online)),
                        DropdownMenuItem(value: 'away', child: Text(AppStrings.of(context).away)),
                        DropdownMenuItem(value: 'offline', child: Text(AppStrings.of(context).offline)),
                      ],
                      onChanged: (value) { if (value != null) _changeStatus(value); },
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _buildThemeCard(context),
              const SizedBox(height: 12),
              _buildLanguageCard(context),
              if (auth.lastError != null) ...[
                const SizedBox(height: 16),
                Text(auth.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeCard(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppStrings.of(context).themeSettings, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.of(context).darkTheme),
              value: theme.isDark,
              onChanged: (_) => theme.toggleDarkMode(),
            ),
            const SizedBox(height: 4),
            Text(AppStrings.of(context).color),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: List.generate(ThemeProvider.colors.length, (i) {
                final selected = theme.colorIndex == i;
                return GestureDetector(
                  onTap: () => theme.setColor(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ThemeProvider.colors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: selected ? [BoxShadow(color: ThemeProvider.colors[i].withOpacity(.45), blurRadius: 12, spreadRadius: 2)] : null,
                    ),
                    child: selected ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, locale, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppStrings.of(context).language, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: locale.locale.languageCode,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'tr', child: Text('🇹🇷 Türkçe')),
                DropdownMenuItem(value: 'en', child: Text('🇺🇸 English')),
                DropdownMenuItem(value: 'de', child: Text('🇩🇪 Deutsch')),
                DropdownMenuItem(value: 'es', child: Text('🇪🇸 Español')),
                DropdownMenuItem(value: 'fr', child: Text('🇫🇷 Français')),
              ],
              onChanged: (value) {
                if (value != null) locale.setLocale(value);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

