import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

@pragma('vm:entry-point')
void monitoringTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class MonitoringService {
  static Future<void> init() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'copilot_monitoring',
        channelName: 'AI Co-Pilot monitoring',
        channelDescription: 'Shown while drowsiness detection is running',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'AI Co-Pilot',
      notificationText: 'Drowsiness monitoring is on. Keep the phone on the dash.',
      callback: monitoringTaskCallback,
      serviceTypes: const [
        ForegroundServiceTypes.camera,
        ForegroundServiceTypes.microphone,
      ],
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    await WakelockPlus.disable();
  }

  static Future<void> setKeepScreenOn(bool enabled) async {
    if (enabled) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }
}
