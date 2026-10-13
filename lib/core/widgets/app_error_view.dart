import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const AppErrorView( {
    super.key, required this.message, this.onRetry
  });
  @override
  Widget build(BuildContext context) => Center(
  child: Column(mainAxisSize: MainAxisSize.min, children: [
  const Icon(Icons.error_outline, size: 48),
  const SizedBox(height: 12), Text(message, textAlign: TextAlign.center),
  if (onRetry != null) ...[const SizedBox(height: 12), ElevatedButton(onPressed: onRetry, child: Text(AppStrings.of(context).t('retry')))],
  ]),
  );
}
