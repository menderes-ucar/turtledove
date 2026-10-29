import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

/// Language and appearance controls displayed from the login settings sheet.
class PreAuthPreferences extends StatelessWidget {
  const PreAuthPreferences({super.key});

  static const _languages = <String, String>{
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.language_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Consumer<LocaleProvider>(
                    builder: (context, locale, _) =>
                        DropdownButtonFormField<String>(
                      value: _languages.containsKey(locale.locale.languageCode)
                          ? locale.locale.languageCode
                          : 'en',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Language / Dil',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _languages.entries
                          .map((entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              ))
                          .toList(),
                      onChanged: (code) {
                        if (code != null) {
                          context.read<LocaleProvider>().setLocale(code);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Consumer<ThemeProvider>(
              builder: (context, theme, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(theme.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded),
                    title: const Text('Dark theme / Koyu tema'),
                    value: theme.isDark,
                    onChanged: (_) => theme.toggleDarkMode(),
                  ),
                  const SizedBox(height: 4),
                  const Text('Color / Renk'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: List.generate(ThemeProvider.colors.length, (i) {
                      final selected = theme.colorIndex == i;
                      return Semantics(
                        button: true,
                        label: 'Color ${i + 1}',
                        child: InkWell(
                          onTap: () => theme.setColor(i),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: ThemeProvider.colors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
