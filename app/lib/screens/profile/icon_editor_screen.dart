import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_palette.dart';
import '../../utils/pixel_codec.dart';
import '../../widgets/app_button.dart';
import '../../widgets/pixel_editor.dart';
import '../../widgets/profile_avatar.dart';

/// Draw your profile icon — the same [PixelEditor] as a round's drawing,
/// at 16×16, with the preview showing the round avatar crop instead of the
/// gallery thumbnail.
class IconEditorScreen extends StatefulWidget {
  const IconEditorScreen({super.key, this.initialIcon});

  /// The current icon, to redraw rather than start blank.
  final List<Color>? initialIcon;

  @override
  State<IconEditorScreen> createState() => _IconEditorScreenState();
}

class _IconEditorScreenState extends State<IconEditorScreen> {
  late final _editor = PixelEditorController(
    canvasSize: UserProfile.iconSize,
    initialPixels: widget.initialIcon,
  );

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (PixelCodec.isEmpty(_editor.pixels)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Draw something first.')),
      );
      return;
    }
    try {
      await ProfileService().saveIcon(_editor.pixels);
    } on ProfileServiceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Everyone sees your new icon now')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => context.pop(),
        ),
        title: Text('Your icon', style: textTheme.titleMedium),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PixelEditor(
                controller: _editor,
                previewBuilder: (context, pixels) => Column(
                  children: [
                    PixelIconAvatar(pixels: pixels, size: 44),
                    const SizedBox(height: 2),
                    Text(
                      'as your icon',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: 'Use this icon', onPressed: _save),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  '${UserProfile.iconSize}×${UserProfile.iconSize} · fixed '
                  '${AppPalette.colors.length}-colour palette · shown round',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.6),
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
