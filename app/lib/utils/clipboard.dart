import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_snackbar.dart';

/// Copies [text] and shows a brief confirmation snackbar. Safe to call
/// from a widget that might already be gone by the time the copy
/// completes (checks `context.mounted` first).
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String confirmation = 'Copied',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  AppSnackBar.show(context, confirmation);
}
