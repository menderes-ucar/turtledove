
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../localization/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/profile_model.dart';
import '../../services/pairing_service.dart';

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
  bool _signingOut = false;
  bool _deletingAccount = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    _usernameController = TextEditingController(
      text: profile?.username ?? '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final strings = AppStrings.of(context);
    final value = _usernameController.text.trim();

    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${strings.username} cannot be empty'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final ok = await context
          .read<AuthProvider>()
          .updateProfileDetails(username: value);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? strings.profileUpdated : strings.profileUpdateFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.profileUpdateFailed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? AppStrings.of(context).photoUpdated
                : AppStrings.of(context).photoUploadFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).photoSelectFailed),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    if (_changingStatus) return;

    setState(() => _changingStatus = true);

    try {
      final ok = await context.read<AuthProvider>().setPresence(status);

      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).profileUpdateFailed,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).profileUpdateFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
  }

  Future<void> _endPairing(Profile profile) async {
    final strings = AppStrings.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.endPairing),
        content: Text(strings.endPairingDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.endPairing),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await PairingService(_supabase).unpairCurrentUser();

      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', profile.id)
          .single();

      if (!mounted) return;

      context.read<AuthProvider>().updateProfile(
        Profile.fromMap(Map<String, dynamic>.from(row)),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.pairingEnded)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${strings.pairingFailed}: $e'),
        ),
      );
    }
  }

  Future<bool> _showConfirmation({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    final strings = AppStrings.of(context);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _signOut() async {
    if (_signingOut || _deletingAccount) return;

    final strings = AppStrings.of(context);

    final confirmed = await _showConfirmation(
      title: strings.signOut,
      message: strings.signOutConfirmation,
      confirmText: strings.signOut,
    );

    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);

    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.signOutSuccess)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.signOutFailed)),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount || _signingOut) return;

    final strings = AppStrings.of(context);

    final confirmed = await _showConfirmation(
      title: strings.deleteAccount,
      message: strings.deleteAccountConfirmation,
      confirmText: strings.deleteAccount,
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    final secondConfirmation = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool acknowledged = false;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(strings.deleteAccountFinalConfirmation),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.deleteAccountFinalDescription),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(strings.deleteAccountAcknowledgement),
                  onChanged: (value) {
                    setDialogState(() {
                      acknowledged = value ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: acknowledged
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(strings.deleteAccountPermanently),
              ),
            ],
          ),
        );
      },
    );

    if (secondConfirmation != true || !mounted) return;

    setState(() => _deletingAccount = true);

    try {
      await _supabase.functions.invoke('delete-account');
      await _supabase.auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.deleteAccountSuccess)),
      );
    } on FunctionException catch (e) {
      if (!mounted) return;

      final details = e.details?.toString();
      final reason = details != null && details.isNotEmpty
          ? details
          : e.reasonPhrase;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.deleteAccountFailed}'
                '${reason != null && reason.isNotEmpty ? ': $reason' : ''}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.deleteAccountFailed),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
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
            body: Center(
              child: auth.isLoading
                  ? const CircularProgressIndicator()
                  : Text(strings.profileUnavailable),
            ),
          );
        }

        final busy = _signingOut || _deletingAccount;

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
                      backgroundImage: profile.avatarUrl == null
                          ? null
                          : NetworkImage(profile.avatarUrl!),
                      child: profile.avatarUrl == null
                          ? const Icon(Icons.person, size: 58)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: FloatingActionButton.small(
                        onPressed:
                        _uploading || busy ? null : _pickAvatar,
                        child: _uploading
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
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
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: strings.username,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving || busy ? null : _saveUsername,
                icon: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.save),
                label: Text(strings.save),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tag_rounded),
                  title: Text(strings.pairingCode),
                  subtitle: Text(
                    profile.pairCode,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: profile.pairCode),
                      );

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.codeCopied)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.status,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: {'online', 'away', 'offline'}
                            .contains(profile.status)
                            ? profile.status
                            : 'online',
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          suffixIcon: _changingStatus
                              ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                              : null,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'online',
                            child: Text(strings.online),
                          ),
                          DropdownMenuItem(
                            value: 'away',
                            child: Text(strings.away),
                          ),
                          DropdownMenuItem(
                            value: 'offline',
                            child: Text(strings.offline),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                          if (value != null) {
                            _changeStatus(value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (profile.pairedWith != null &&
                  profile.pairedWith!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link_off_rounded),
                    title: Text(strings.endPairing),
                    subtitle: Text(strings.endPairingDescription),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    enabled: !busy,
                    onTap: () => _endPairing(profile),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildThemeCard(context),
              const SizedBox(height: 12),
              _buildLanguageCard(context),
              const SizedBox(height: 24),
              Text(
                strings.accountActions,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: Text(strings.signOut),
                  subtitle: Text(strings.signOutSubtitle),
                  trailing: _signingOut
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.chevron_right_rounded),
                  enabled: !busy,
                  onTap: _signOut,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    strings.deleteAccount,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(strings.deleteAccountSubtitle),
                  trailing: _deletingAccount
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.chevron_right_rounded),
                  enabled: !busy,
                  onTap: _deleteAccount,
                ),
              ),
              if (_deletingAccount) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  strings.deleteAccountInProgress,
                  textAlign: TextAlign.center,
                ),
              ],
              if (auth.lastError != null) ...[
                const SizedBox(height: 16),
                Text(
                  auth.lastError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.of(context).themeSettings,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(AppStrings.of(context).darkTheme),
                value: theme.isDark,
                onChanged: (value) => theme.toggleDarkMode(),
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
                          color: selected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: selected
                            ? [
                          BoxShadow(
                            color: ThemeProvider.colors[i]
                                .withOpacity(.45),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, locale, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.of(context).language,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: locale.locale.languageCode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'tr',
                    child: Text('🇹🇷 Türkçe'),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text('🇺🇸 English'),
                  ),
                  DropdownMenuItem(
                    value: 'de',
                    child: Text('🇩🇪 Deutsch'),
                  ),
                  DropdownMenuItem(
                    value: 'es',
                    child: Text('🇪🇸 Español'),
                  ),
                  DropdownMenuItem(
                    value: 'fr',
                    child: Text('🇫🇷 Français'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) locale.setLocale(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
