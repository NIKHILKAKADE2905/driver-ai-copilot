import 'dart:math';

import 'package:demo_cam_application/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> loadOrCreateSessionId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(kSessionIdPrefKey);
  if (existing != null && existing.length >= 8) {
    return existing;
  }
  final id =
      'drv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
  await prefs.setString(kSessionIdPrefKey, id);
  return id;
}

Future<bool> hasAcceptedDisclaimer() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kDisclaimerAcceptedPrefKey) ?? false;
}

Future<void> acceptDisclaimer() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kDisclaimerAcceptedPrefKey, true);
}
