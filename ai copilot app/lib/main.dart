import 'package:demo_cam_application/monitoring_service.dart';
import 'package:demo_cam_application/screens/disclaimer_screen.dart';
import 'package:demo_cam_application/screens/trip_setup_screen.dart';
import 'package:demo_cam_application/session.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MonitoringService.init();
  final sessionId = await loadOrCreateSessionId();
  final disclaimerAccepted = await hasAcceptedDisclaimer();
  runApp(MyApp(sessionId: sessionId, disclaimerAccepted: disclaimerAccepted));
}

class MyApp extends StatelessWidget {
  final String sessionId;
  final bool disclaimerAccepted;

  const MyApp({
    super.key,
    required this.sessionId,
    this.disclaimerAccepted = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Co-Pilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF171A1F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF62D5B2),
          brightness: Brightness.dark,
        ),
      ),
      home: disclaimerAccepted
          ? TripSetupScreen(sessionId: sessionId)
          : DisclaimerScreen(sessionId: sessionId),
    );
  }
}
