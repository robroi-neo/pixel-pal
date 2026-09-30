import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/user_profile.dart';
import '../../router/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/app_snackbar.dart';

/// Reached by tapping your avatar on the room list. A full screen rather
/// than a drawer (the app has one destination, the room list) or a half
/// sheet (a text field plus a keyboard leaves no room for anything else).
///
/// No notifications row: sending pushes needs a trusted sender (a Cloud
/// Function), which Spark doesn't have — a row that toggles nothing would
/// be a lie. No photo/library icon options either: Cloud Storage needs
/// Blaze, and the icon is pixel art drawn in the app's own editor.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _nameController = TextEditingController();

  /// Null until the profile loads.
  String? _savedName;
  String? _loadError;

  String get _typed => _nameController.text.trim();
  bool get _isDirty => _savedName != null && _typed != _savedName;
  bool get _isTooShort => _typed.length < UserProfile.minNameLength;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await _profileService.ensureOwnProfile();
      if (!mounted) return;
      setState(() {
        _savedName = profile.displayName;
        _nameController.text = profile.displayName;
      });
    } on ProfileServiceException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  /// True if saved.
  Future<bool> _save() async {
    final name = _typed;
    try {
      await _profileService.saveDisplayName(name);
    } on ProfileServiceException catch (e) {
      _showSnack(e.message);
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _savedName = name;
      _nameController.text = name;
    });
    _showSaved('Everyone sees $name now');
    return true;
  }

  void _discard() => _nameController.text = _savedName ?? '';

  void _showSnack(String message) {
    if (!mounted) return;
    AppSnackBar.show(context, message);
  }

  void _showSaved(String message) {
    if (!mounted) return;
    AppSnackBar.success(context, message);
  }

  Future<void> _confirmLeave() async {
    final leave = await _KeepChangesDialog.show(
      context,
      newName: _typed,
      canSave: !_isTooShort,
      onSave: _save,
    );
    if (leave && mounted) {
      _discard();
      context.pop();
    }
  }

  Future<void> _openIconSheet(UserProfile? profile) async {
    final action = await _IconSheet.show(
      context,
      hasIcon: profile?.icon != null,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _IconAction.draw:
        context.push(AppRoutes.profileIcon, extra: profile?.icon);
      case _IconAction.reset:
        try {
          await _profileService.clearIcon();
          _showSaved('Everyone sees your initial again');
        } on ProfileServiceException catch (e) {
          _showSnack(e.message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = FirebaseAuth.instance.currentUser;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_outlined),
            // maybePop, not context.pop — it's what lets PopScope catch
            // an unsaved rename.
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text('Profile', style: textTheme.titleMedium),
        ),
        body: SafeArea(
          child: user == null
              ? Center(
                  child: Text(
                    'Sign in to see your profile.',
                    style: textTheme.bodyMedium,
                  ),
                )
              : _loadError != null
              ? Center(child: Text(_loadError!, style: textTheme.bodyMedium))
              : _savedName == null
              ? const LoadingView()
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: ProfileBuilder(
                                uid: user.uid,
                                builder: (context, profile) => _EditableAvatar(
                                  uid: user.uid,
                                  fallbackName: _savedName,
                                  onTap: () => _openIconSheet(profile),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _NameField(
                              controller: _nameController,
                              showError: _isDirty && _isTooShort,
                            ),
                            if (_isDirty && !_isTooShort) ...[
                              const SizedBox(height: AppSpacing.md),
                              _SaveBar(onDiscard: _discard, onSave: _save),
                            ],
                            const SizedBox(height: AppSpacing.xl),
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.ink.withValues(alpha: 0.1),
                                borderRadius: AppRadius.chipRadius,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _SignedInRow(user: user),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: TextButton(
                        onPressed: () => AuthService().signOut(),
                        child: const Text('Sign out'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.uid,
    required this.fallbackName,
    required this.onTap,
  });

  final String uid;
  final String? fallbackName;
  final VoidCallback onTap;

  static const _size = 120.0;
  static const _badgeSize = 44.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change your icon',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size + _badgeSize / 4,
          height: _size + _badgeSize / 4,
          child: Stack(
            children: [
              ProfileAvatar(uid: uid, fallbackName: fallbackName, size: _size),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cream,
                    border: Border.all(
                      color: AppColors.ink,
                      width: AppBorders.thick,
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: AppSizes.icon,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.showError});

  final TextEditingController controller;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final borderColor = showError ? theme.colorScheme.error : AppColors.ink;
    OutlineInputBorder border(double width) => OutlineInputBorder(
      borderRadius: AppRadius.controlRadius,
      borderSide: BorderSide(color: borderColor, width: width),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Display name',
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            LengthLimitingTextInputFormatter(UserProfile.maxNameLength),
          ],
          style: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            enabledBorder: border(AppBorders.thick),
            focusedBorder: border(AppBorders.thick),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (showError)
          // Design.md §2: `error` is for exactly this — inline validation.
          Text(
            'At least ${UserProfile.minNameLength} characters',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  "Shown in every room you're in, including on drawings "
                  "you've already made.",
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${controller.text.length}/${UserProfile.maxNameLength}',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Only appears once the name has actually changed — nothing before.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onDiscard, required this.onSave});

  final VoidCallback onDiscard;
  final Future<bool> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: onDiscard,
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
            child: const Text('Discard'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 3,
          child: AppButton(label: 'Save changes', onPressed: onSave),
        ),
      ],
    );
  }
}

class _SignedInRow extends StatelessWidget {
  const _SignedInRow({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viaGoogle = user.providerData.any(
      (p) => p.providerId == GoogleAuthProvider.PROVIDER_ID,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Row(
        children: [
          const Icon(Icons.mail_outline, size: AppSizes.iconMax),
          const SizedBox(width: AppSpacing.md),
          Text(
            viaGoogle ? 'Signed in with Google' : 'Signed in with email',
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              user.email ?? '',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Backing out with an unsaved rename. Resolves true if the screen should
/// close (saved, or discarded on purpose).
class _KeepChangesDialog extends StatelessWidget {
  const _KeepChangesDialog({
    required this.newName,
    required this.canSave,
    required this.onSave,
  });

  final String newName;
  final bool canSave;
  final Future<bool> Function() onSave;

  static Future<bool> show(
    BuildContext context, {
    required String newName,
    required bool canSave,
    required Future<bool> Function() onSave,
  }) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => _KeepChangesDialog(
        newName: newName,
        canSave: canSave,
        onSave: onSave,
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.ink, width: AppBorders.thick),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Keep your changes?', style: textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.md),
            Text(
              canSave
                  ? "You renamed yourself to $newName but haven't saved it."
                  : 'A name needs at least ${UserProfile.minNameLength} '
                        "characters, so this one can't be saved.",
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (canSave)
              AppButton(
                label: 'Save and leave',
                onPressed: () async {
                  final saved = await onSave();
                  if (saved && context.mounted) Navigator.of(context).pop(true);
                },
              )
            else
              AppButton(
                label: 'Keep editing',
                onPressed: () async => Navigator.of(context).pop(false),
              ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(backgroundColor: AppColors.white),
              child: const Text('Discard and leave'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _IconAction { draw, reset }

/// "Your icon". Pixel art only — drawn in the same editor as a round's
/// drawing. No camera/library options (Cloud Storage needs Blaze).
class _IconSheet extends StatelessWidget {
  const _IconSheet({required this.hasIcon});

  final bool hasIcon;

  static Future<_IconAction?> show(
    BuildContext context, {
    required bool hasIcon,
  }) {
    return AppSheet.show<_IconAction>(
      context,
      builder: (_) => _IconSheet(hasIcon: hasIcon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tokens = theme.extension<AppTokens>()!;
    final accent = theme.colorScheme.primary;

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your icon', style: textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
          // §4: the shadow marks the thing to act on. The fill has to be
          // on the same decoration as the shadow — a BoxShadow paints
          // under its own decoration's colour, so with the fill on a
          // Material behind it instead, the ink shadow covered the whole
          // button. The inner transparent Material keeps the ripple above
          // the fill.
          Container(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: AppRadius.controlRadius,
              border: Border.all(color: AppColors.ink, width: AppBorders.thick),
              boxShadow: tokens.hardShadow,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: AppRadius.controlRadius,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(_IconAction.draw),
                borderRadius: AppRadius.controlRadius,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: AppRadius.controlRadius,
                        ),
                        child: Icon(Icons.edit_outlined, color: accent),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasIcon ? 'Redraw it' : 'Draw one',
                              style: textTheme.titleMedium,
                            ),
                            Text(
                              '${UserProfile.iconSize} × '
                              '${UserProfile.iconSize}, in the editor you '
                              'already know',
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasIcon) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.1),
                borderRadius: AppRadius.chipRadius,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Material(
              color: AppColors.cream,
              borderRadius: AppRadius.controlRadius,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(_IconAction.reset),
                borderRadius: AppRadius.controlRadius,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.controlRadius,
                    border: Border.all(
                      color: AppColors.grey,
                      width: AppBorders.thick,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.remove_circle_outline,
                        color: AppColors.ink.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'Go back to my initial',
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 16,
                          color: AppColors.ink.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}
