import 'dart:collection';

import 'package:demo_cam_application/driver_face_selector.dart';
import 'package:flutter/material.dart';

class DrowsinessResult {
  final String state; // "NORMAL", "MODERATE", "STRONG"
  final double perclos;
  final String message;
  final Color statusColor;
  final bool faceDetected;

  DrowsinessResult({
    required this.state,
    required this.perclos,
    required this.message,
    required this.statusColor,
    this.faceDetected = true,
  });
}

class DrowsinessDetector {
  final int windowSeconds;
  final Queue<int> _eyeClosedBuffer = Queue<int>();

  DateTime? _eyeClosedStart;
  DateTime? _headDroppedStart;
  DateTime? _yawnStart;

  final List<DateTime> _validYawnTimestamps = [];

  DrowsinessDetector({this.windowSeconds = 60});

  void reset() {
    _eyeClosedBuffer.clear();
    _eyeClosedStart = null;
    _headDroppedStart = null;
    _yawnStart = null;
    _validYawnTimestamps.clear();
  }

  DrowsinessResult update(List<dynamic> detections, double currentFps) {
    final now = DateTime.now();
    final effectiveFps = currentFps > 0 ? currentFps : 10.0;
    final maxBufferSize = (effectiveFps * windowSeconds).round();

    final driverDetections = selectDriverDetections(detections);
    final classNames =
        driverDetections.map((d) => d.className.toString()).toSet();

    final hasHeadState =
        classNames.contains("head_straight") || classNames.contains("head_dropped");
    final hasEyeState =
        classNames.contains("eye_open") || classNames.contains("eye_closed");
    final hasMouthState =
        classNames.contains("yawn") || classNames.contains("no_yawn");

    final isFaceDetected = hasHeadState && hasEyeState && hasMouthState;

    if (!isFaceDetected) {
      _eyeClosedStart = null;
      _headDroppedStart = null;
      _yawnStart = null;

      final totalClosedFrames = _eyeClosedBuffer.where((val) => val == 1).length;
      final currentPerclos = _eyeClosedBuffer.isNotEmpty
          ? (totalClosedFrames / _eyeClosedBuffer.length) * 100.0
          : 0.0;

      return DrowsinessResult(
        state: "NORMAL",
        perclos: currentPerclos,
        message: "👤 Face Not Detected",
        statusColor: Colors.orangeAccent,
        faceDetected: false,
      );
    }

    final isEyeClosed = classNames.contains("eye_closed");
    final isYawn = classNames.contains("yawn");
    final isHeadDropped = classNames.contains("head_dropped");

    _eyeClosedBuffer.addLast(isEyeClosed ? 1 : 0);
    while (_eyeClosedBuffer.length > maxBufferSize && _eyeClosedBuffer.isNotEmpty) {
      _eyeClosedBuffer.removeFirst();
    }

    double currentClosureDuration = 0.0;
    if (isEyeClosed) {
      _eyeClosedStart ??= now;
      currentClosureDuration =
          now.difference(_eyeClosedStart!).inMilliseconds / 1000.0;
    } else {
      _eyeClosedStart = null;
    }

    double headDropDuration = 0.0;
    if (isHeadDropped) {
      _headDroppedStart ??= now;
      headDropDuration =
          now.difference(_headDroppedStart!).inMilliseconds / 1000.0;
    } else {
      _headDroppedStart = null;
    }

    if (isYawn) {
      _yawnStart ??= now;
    } else {
      if (_yawnStart != null) {
        final yawnDuration = now.difference(_yawnStart!).inMilliseconds / 1000.0;
        if (yawnDuration >= 3.0 && yawnDuration <= 8.0) {
          _validYawnTimestamps.add(now);
        }
        _yawnStart = null;
      }
    }

    _validYawnTimestamps.removeWhere((t) => now.difference(t).inSeconds > 120);

    final totalClosedFrames = _eyeClosedBuffer.where((val) => val == 1).length;
    final perclos = _eyeClosedBuffer.isNotEmpty
        ? (totalClosedFrames / _eyeClosedBuffer.length) * 100.0
        : 0.0;
    final yawnCount = _validYawnTimestamps.length;

    if (currentClosureDuration >= 3.0 && perclos >= 25.0) {
      return DrowsinessResult(
        state: "STRONG",
        perclos: perclos,
        message:
            "🚨 CRITICAL: Microsleep detected (${currentClosureDuration.toStringAsFixed(1)}s)!",
        statusColor: const Color(0xFFFF4D4D),
      );
    }

    if (headDropDuration >= 3.0 && isEyeClosed) {
      return DrowsinessResult(
        state: "STRONG",
        perclos: perclos,
        message: "🚨 CRITICAL: Head dropped while eyes closed!",
        statusColor: const Color(0xFFFF4D4D),
      );
    } else if ((perclos >= 20.0 && perclos < 25.0) && yawnCount >= 3) {
      return DrowsinessResult(
        state: "MODERATE",
        perclos: perclos,
        message: "⚠️ WARNING: Notable fatigue detected!",
        statusColor: const Color(0xFFFFB020),
      );
    } else {
      return DrowsinessResult(
        state: "NORMAL",
        perclos: perclos,
        message: "🟢 Driver Alert",
        statusColor: const Color(0xFF62D5B2),
      );
    }
  }
}
