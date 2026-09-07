import 'package:demo_cam_application/missed_stop_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stop = GuidedStop(name: 'Test Pump', latitude: 19.0760, longitude: 72.8777);

  // ~150 m north of the stop
  const nearLat = 19.07735;
  // ~500 m north of the stop
  const farLat = 19.0805;

  test('does not flag a miss until the driver has been close', () {
    final monitor = MissedStopMonitor()..arm(stop);
    final now = DateTime(2026, 1, 1, 12);
    final outcome = monitor.observe(
      driverLat: farLat,
      driverLon: 72.8777,
      speedMps: 15,
      now: now,
    );
    expect(outcome, StopWatchOutcome.none);
  });

  test('flags a miss after passing close then driving away', () {
    final monitor = MissedStopMonitor()..arm(stop);
    final now = DateTime(2026, 1, 1, 12);
    monitor.observe(
      driverLat: nearLat,
      driverLon: 72.8777,
      speedMps: 12,
      now: now,
    );
    final missed = monitor.observe(
      driverLat: farLat,
      driverLon: 72.8777,
      speedMps: 12,
      now: now.add(const Duration(seconds: 20)),
    );
    expect(missed, StopWatchOutcome.missed);
  });

  test('settles as arrived when slow near the pin for 30 seconds', () {
    final monitor = MissedStopMonitor()..arm(stop);
    final now = DateTime(2026, 1, 1, 12);
    final first = monitor.observe(
      driverLat: 19.0762,
      driverLon: 72.8777,
      speedMps: 0.4,
      now: now,
    );
    expect(first, StopWatchOutcome.none);
    final arrived = monitor.observe(
      driverLat: 19.0762,
      driverLon: 72.8777,
      speedMps: 0.3,
      now: now.add(const Duration(seconds: 31)),
    );
    expect(arrived, StopWatchOutcome.arrived);
  });
}
