import 'package:flutter/material.dart';

class SnackbarService {
  static void showSuccess(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    _showSnackbar(
      context,
      message: message,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      textColor: Theme.of(context).colorScheme.onPrimaryContainer,
      icon: Icons.check_circle_outline,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    _showSnackbar(
      context,
      message: message,
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      textColor: Theme.of(context).colorScheme.onErrorContainer,
      icon: Icons.error_outline,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    _showSnackbar(
      context,
      message: message,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      textColor: Theme.of(context).colorScheme.onSecondaryContainer,
      icon: Icons.info_outline,
      duration: duration,
    );
  }

  static void showWarning(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    _showSnackbar(
      context,
      message: message,
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      textColor: Theme.of(context).colorScheme.onTertiaryContainer,
      icon: Icons.warning_amber_outlined,
      duration: duration,
    );
  }

  static void _showSnackbar(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required Color textColor,
    required IconData icon,
    Duration? duration,
  }) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: duration ?? const Duration(seconds: 4),
      dismissDirection: DismissDirection.horizontal,
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
