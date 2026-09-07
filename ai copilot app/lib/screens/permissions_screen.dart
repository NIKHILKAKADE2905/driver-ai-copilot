import 'package:demo_cam_application/screens/camera_page.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  final String vehicleType;
  final String destination;
  final String sessionId;
  final double destLat;
  final double destLon;

  const PermissionsScreen({
    super.key,
    required this.vehicleType,
    required this.destination,
    required this.sessionId,
    required this.destLat,
    required this.destLon,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _camera = false;
  bool _location = false;
  bool _microphone = false;
  bool _notifications = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    final notification = await Permission.notification.status;
    var locationOk = false;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) {
      final loc = await Geolocator.checkPermission();
      locationOk = loc == LocationPermission.always ||
          loc == LocationPermission.whileInUse;
    }
    if (!mounted) return;
    setState(() {
      _camera = camera.isGranted;
      _microphone = mic.isGranted;
      _notifications = notification.isGranted;
      _location = locationOk;
    });
  }

  Future<void> _requestAll() async {
    setState(() => _busy = true);
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.notification.request();
    final loc = await Geolocator.requestPermission();
    if (loc == LocationPermission.deniedForever && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is blocked. Enable it in system settings.'),
        ),
      );
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  bool get _requiredOk => _camera && _location && _microphone;

  void _continue() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(
          vehicleType: widget.vehicleType,
          destination: widget.destination,
          sessionId: widget.sessionId,
          destLat: widget.destLat,
          destLon: widget.destLon,
        ),
      ),
    );
  }

  Widget _row(String label, bool granted) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        granted ? Icons.check_circle : Icons.error_outline,
        color: granted ? const Color(0xFF62D5B2) : Colors.orangeAccent,
      ),
      title: Text(label),
      subtitle: Text(granted ? 'Allowed' : 'Required'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        backgroundColor: const Color(0xFF20252B),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Allow these before you start driving',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Camera watches your face on-device. Location finds rest stops. Microphone is for the co-pilot. Notifications keep monitoring alive.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              _row('Camera', _camera),
              _row('Location', _location),
              _row('Microphone', _microphone),
              _row('Notifications (recommended)', _notifications),
              const Spacer(),
              OutlinedButton(
                onPressed: _busy ? null : _requestAll,
                child: Text(_busy ? 'Requesting...' : 'Grant permissions'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _requiredOk ? _continue : null,
                child: const Text('CONTINUE TO MONITORING'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
