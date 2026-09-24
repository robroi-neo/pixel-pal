import 'package:flutter/material.dart';

/// Strokes [path] as a dashed line — used for the "add a room" button's
/// dashed rounded rect and the room screen's empty member slots. Flutter
/// has no built-in dashed stroke, so this segments the path's own
/// geometry via [Path.computeMetrics] rather than approximating with a
/// shape-specific formula.
void paintDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dashWidth = 8,
  double gapWidth = 6,
}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = distance + dashWidth;
      canvas.drawPath(
        metric.extractPath(distance, next.clamp(0, metric.length)),
        paint,
      );
      distance = next + gapWidth;
    }
  }
}
