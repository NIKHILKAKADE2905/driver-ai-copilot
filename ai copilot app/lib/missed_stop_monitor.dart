import 'package:geolocator/geolocator.dart';

enum StopWatchOutcome { none, arrived, missed }

class GuidedStop {
  final String name;
  final double latitude;
  final double longitude;

  const GuidedStop({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

/// Watches GPS after Maps is opened to a rest stop.
class MissedStopMonitor {
  static const closeMeters = 200.0;
  static const arrivedMeters = 100.0;
  static const leftMeters = 400.0;
  static const stoppedSpeedMps = 2.0;
  static const movingSpeedMps = 2.5;
  static const stoppedHold = Duration(seconds: 30);
  static const missCooldown = Duration(seconds: 90);

  GuidedStop? target;
  bool wasClose = false;
  DateTime? slowNearStart;
  bool settled = false;
  DateTime? lastMissAt;

  void arm(GuidedStop stop) {
    target = stop;
    wasClose = false;
    slowNearStart = null;
    settled = false;
  }

  void clear() {
    target = null;
    wasClose = false;
    slowNearStart = null;
    settled = true;
  }

  StopWatchOutcome observe({
    required double driverLat,
    required double driverLon,
    required double speedMps,
    required DateTime now,
  }) {
    final stop = target;
    if (stop == null || settled) return StopWatchOutcome.none;

    final distanceMeters = Geolocator.distanceBetween(
      driverLat,
      driverLon,
      stop.latitude,
      stop.longitude,
    );

    if (distanceMeters <= closeMeters) {
      wasClose = true;
    }

    final speedKnown = speedMps >= 0;
    final isSlow = speedKnown ? speedMps <= stoppedSpeedMps : distanceMeters <= 40;

    if (distanceMeters <= arrivedMeters && isSlow) {
      slowNearStart ??= now;
      if (now.difference(slowNearStart!) >= stoppedHold) {
        settled = true;
        return StopWatchOutcome.arrived;
      }
    } else {
      slowNearStart = null;
    }

    final isMoving = !speedKnown || speedMps >= movingSpeedMps;
    final cooldownOk =
        lastMissAt == null || now.difference(lastMissAt!) >= missCooldown;

    if (wasClose && distanceMeters >= leftMeters && isMoving && cooldownOk) {
      lastMissAt = now;
      wasClose = false;
      return StopWatchOutcome.missed;
    }

    return StopWatchOutcome.none;
  }
}
