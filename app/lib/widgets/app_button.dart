import 'package:flutter/material.dart';

/// A themed button that shows a spinner and disables itself while
/// [onPressed] is awaiting — used on every auth screen so "sign in" /
/// "create account" / "send reset link" don't each need their own
/// loading-state boilerplate. Looks entirely come from
/// ElevatedButtonTheme / OutlinedButtonTheme in theme/app_theme.dart —
/// nothing is hardcoded here except which of those two themes to use.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.enabled = true,
  });

  final String label;
  final Future<void> Function() onPressed;

  /// true = secondary style (outlined). false = primary (ink fill, per
  /// Design.md §3). Design.md §4: avoid more than one primary button per
  /// screen.
  final bool secondary;

  /// false shows the button in its theme's disabled colors and ignores
  /// taps — e.g. prompt pick's "Start drawing" before anything's selected.
  final bool enabled;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _loading = false;

  Future<void> _handlePressed() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Primary button is ink-fill/accent-text; secondary is ink-on-transparent.
    // Matching the spinner to the button's own foreground keeps it in sync
    // if the accent color changes at runtime.
    final spinnerColor = widget.secondary ? scheme.onSurface : scheme.onSecondary;

    final child = _loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          )
        : Text(widget.label);

    final onPressed = (_loading || !widget.enabled) ? null : _handlePressed;

    return SizedBox(
      width: double.infinity,
      child: widget.secondary
          ? OutlinedButton(onPressed: onPressed, child: child)
          : ElevatedButton(onPressed: onPressed, child: child),
    );
  }
}
