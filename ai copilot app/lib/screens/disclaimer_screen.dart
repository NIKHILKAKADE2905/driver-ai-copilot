import 'package:demo_cam_application/screens/trip_setup_screen.dart';
import 'package:demo_cam_application/session.dart';
import 'package:flutter/material.dart';

class DisclaimerScreen extends StatelessWidget {
  final String sessionId;

  const DisclaimerScreen({super.key, required this.sessionId});

  Future<void> _accept(BuildContext context) async {
    await acceptDisclaimer();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripSetupScreen(sessionId: sessionId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Before you drive'),
        backgroundColor: const Color(0xFF20252B),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Driver aid only',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'AI Co-Pilot is a driver aid. It can miss drowsiness, give a false alert, or fail if the camera, GPS, or internet is unavailable.',
                        style: TextStyle(fontSize: 15, height: 1.4),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'You remain fully responsible for the vehicle, for staying awake, and for stopping when it is safe. Do not rely on this app as a certified safety system.',
                        style: TextStyle(fontSize: 15, height: 1.4),
                      ),
                      SizedBox(height: 28),
                      Text(
                        'Privacy',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Your face is processed on this phone. Camera frames are not uploaded.',
                        style: TextStyle(fontSize: 15, height: 1.4),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'If you use the co-pilot, your voice audio, GPS location, destination, and vehicle type are sent to the backend so it can talk to you and find rest stops.',
                        style: TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _accept(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'I UNDERSTAND — CONTINUE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
