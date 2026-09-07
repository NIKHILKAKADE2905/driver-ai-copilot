import 'dart:ui';

import 'package:demo_cam_application/driver_face_selector.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDet {
  _FakeDet(this.className, this.normalizedBox);
  final String className;
  final Rect normalizedBox;
}

void main() {
  test('picks the larger centered face over a small passenger', () {
    final detections = [
      _FakeDet('head_straight', const Rect.fromLTWH(0.35, 0.25, 0.28, 0.32)),
      _FakeDet('eye_open', const Rect.fromLTWH(0.42, 0.32, 0.08, 0.05)),
      _FakeDet('no_yawn', const Rect.fromLTWH(0.45, 0.46, 0.10, 0.06)),
      _FakeDet('head_dropped', const Rect.fromLTWH(0.82, 0.20, 0.10, 0.12)),
      _FakeDet('eye_closed', const Rect.fromLTWH(0.84, 0.24, 0.04, 0.03)),
      _FakeDet('yawn', const Rect.fromLTWH(0.85, 0.28, 0.04, 0.03)),
    ];

    final selected = selectDriverDetections(detections);
    final names = selected.map((d) => (d as _FakeDet).className).toSet();

    expect(names.contains('head_straight'), isTrue);
    expect(names.contains('eye_open'), isTrue);
    expect(names.contains('eye_closed'), isFalse);
    expect(names.contains('yawn'), isFalse);
  });

  test('keeps a single face unchanged', () {
    final detections = [
      _FakeDet('head_straight', const Rect.fromLTWH(0.4, 0.3, 0.2, 0.25)),
      _FakeDet('eye_closed', const Rect.fromLTWH(0.45, 0.35, 0.06, 0.04)),
      _FakeDet('no_yawn', const Rect.fromLTWH(0.48, 0.46, 0.08, 0.05)),
    ];
    final selected = selectDriverDetections(detections);
    expect(selected.length, 3);
  });
}
