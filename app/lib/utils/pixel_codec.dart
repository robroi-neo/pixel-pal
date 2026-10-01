import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Packs a drawing's pixels into a compact base64 string for storage —
/// one byte per pixel: 0-15 is an index into [AppPalette.colors], 16
/// means "still empty".
///
/// Empty *is* white now: `AppColors.canvas` is #FFFFFF, the palette's own
/// white, so an unpainted pixel encodes as the white swatch and painting
/// white is the same as leaving it empty. 16 only appears in drawings
/// made before that change, and still decodes to the canvas fill.
///
/// Implementations.md's real design calls for true nibble-packing (2
/// pixels per byte, since 16 colors fit in 4 bits) plus base64. This is a
/// byte-per-pixel stand-in instead: canvases top out at 64×64 (4096 bytes
/// raw, ~5.5KB base64) either way, trivial for Firestore, and true
/// nibble-packing would also need a separate scheme for the 17th "empty"
/// state that doesn't fit in 4 bits alongside 16 real colors. Revisit if
/// canvas sizes grow or storage actually matters.
class PixelCodec {
  PixelCodec._();

  static const _emptyMarker = 16;

  static String encode(List<Color> pixels) {
    final bytes = Uint8List(pixels.length);
    for (var i = 0; i < pixels.length; i++) {
      final index = AppPalette.colors.indexOf(pixels[i]);
      bytes[i] = index == -1 ? _emptyMarker : index;
    }
    return base64Encode(bytes);
  }

  static List<Color> decode(String encoded) {
    final bytes = base64Decode(encoded);
    return [
      for (final b in bytes)
        b == _emptyMarker ? AppColors.canvas : AppPalette.colors[b],
    ];
  }

  /// Nothing but the (white) canvas — blank, or painted white only. A
  /// round drawing may still be submitted blank (the editor asks first);
  /// the profile icon editor refuses one, since a blank icon is no icon.
  static bool isEmpty(List<Color> pixels) =>
      pixels.every((color) => color == AppColors.canvas);
}
