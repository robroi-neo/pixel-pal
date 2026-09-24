import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The app's one user-changeable color — Design.md's "yellow" role.
///
/// Every other token in [AppColors] is fixed forever (that's the whole
/// point of Design.md §2). This one isn't: it's exposed as a
/// [ValueNotifier] so a future settings screen can call
/// `AppAccent.notifier.value = someColor` and have every screen listening
/// via `AppTheme.build` repaint immediately, with no other plumbing.
///
/// Kept as a bare [ValueNotifier] rather than a full state-management
/// dependency because there's exactly one value to hold today. If more
/// user-configurable theme knobs show up later, promote this to a proper
/// controller class then — not preemptively now.
class AppAccent {
  AppAccent._();

  static final ValueNotifier<Color> notifier = ValueNotifier<Color>(
    AppColors.yellowDefault,
  );
}
