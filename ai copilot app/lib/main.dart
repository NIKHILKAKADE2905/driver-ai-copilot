import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// --- SERVER CONFIGURATION ---
// Emulator URL: "http://10.0.2.2:8000"
// Physical Device URL: "http://<YOUR_LOCAL_IP>:8000"
const String kBackendBaseUrl = "http://192.168.0.101:8000";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drowsiness Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF171A1F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF62D5B2),
          brightness: Brightness.dark,
        ),
      ),
      home: const TripSetupScreen(),
    );
  }
}

// ============================================================================
// 1️⃣ TRIP SETUP SCREEN
// ============================================================================
class TripSetupScreen extends StatefulWidget {
  const TripSetupScreen({super.key});

  @override
  State<TripSetupScreen> createState() => _TripSetupScreenState();
}

class _TripSetupScreenState extends State<TripSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final List<String> _vehicleTypes = [
    'Car / Sedan',
    'SUV / Truck',
    'Bus',
    'Commercial Hauler',
    'Motorcycle'
  ];

  String? _selectedVehicle;
  final TextEditingController _destinationController = TextEditingController();

  void _proceedToMonitoring() {
    if (_formKey.currentState!.validate()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraPage(
            vehicleType: _selectedVehicle!,
            destination: _destinationController.text.trim(),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Setup'),
        backgroundColor: const Color(0xFF20252B),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Driver & Trip Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please fill in all mandatory fields before initiating drowsiness monitoring.',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 32),

                DropdownButtonFormField<String>(
                  initialValue: _selectedVehicle,
                  decoration: InputDecoration(
                    labelText: 'Select Vehicle Type *',
                    prefixIcon: const Icon(Icons.directions_car),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252B32),
                  ),
                  items: _vehicleTypes.map((vehicle) {
                    return DropdownMenuItem(
                      value: vehicle,
                      child: Text(vehicle),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedVehicle = val),
                  validator: (val) => val == null ? 'Please select a vehicle type' : null,
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _destinationController,
                  decoration: InputDecoration(
                    labelText: 'Trip Destination *',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF252B32),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your destination';
                    }
                    return null;
                  },
                ),

                const Spacer(),

                FilledButton.icon(
                  onPressed: _proceedToMonitoring,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text(
                    'PROCEED TO MONITORING',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🧠 DROWSINESS DETECTOR ENGINE
// ============================================================================
class DrowsinessResult {
  final String state; // "NORMAL", "MODERATE", "STRONG"
  final double perclos;
  final String message;
  final Color statusColor;

  DrowsinessResult({
    required this.state,
    required this.perclos,
    required this.message,
    required this.statusColor,
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

    final classNames = detections.map((d) => d.className.toString()).toSet();
    final isEyeClosed = classNames.contains("eye_closed");
    final isYawn = classNames.contains("yawn");
    final isHeadDropped = classNames.contains("head_dropped");

    // PERCLOS & Eye Closure Tracking
    _eyeClosedBuffer.addLast(isEyeClosed ? 1 : 0);
    while (_eyeClosedBuffer.length > maxBufferSize && _eyeClosedBuffer.isNotEmpty) {
      _eyeClosedBuffer.removeFirst();
    }

    double currentClosureDuration = 0.0;
    if (isEyeClosed) {
      _eyeClosedStart ??= now;
      currentClosureDuration = now.difference(_eyeClosedStart!).inMilliseconds / 1000.0;
    } else {
      _eyeClosedStart = null;
    }

    // Continuous Head Drop Duration
    double headDropDuration = 0.0;
    if (isHeadDropped) {
      _headDroppedStart ??= now;
      headDropDuration = now.difference(_headDroppedStart!).inMilliseconds / 1000.0;
    } else {
      _headDroppedStart = null;
    }

    // Yawn Duration Tracker
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

    // Warning Levels
    if (currentClosureDuration >= 3.0 && perclos >= 25.0) {
      return DrowsinessResult(
        state: "STRONG",
        perclos: perclos,
        message: "🚨 CRITICAL: Microsleep detected (${currentClosureDuration.toStringAsFixed(1)}s)!",
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

// ============================================================================
// 📱 CAMERA PAGE UI & HANDS-FREE AI CO-PILOT INTEGRATION
// ============================================================================
class CameraPage extends StatefulWidget {
  final String vehicleType;
  final String destination;

  const CameraPage({
    super.key,
    required this.vehicleType,
    required this.destination,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final YOLOViewController _yoloController = YOLOViewController();
  final DrowsinessDetector _drowsinessDetector = DrowsinessDetector(windowSeconds: 60);
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Hands-free Voice & Audio Services
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isCoolingDown = false;
  bool _isConversing = false;
  Timer? _cooldownTimer;

  bool _isCameraRunning = false;
  double _fps = 0;
  DateTime? _lastFrameTime;

  DrowsinessResult _drowsinessStatus = DrowsinessResult(
    state: "NORMAL",
    perclos: 0.0,
    message: "Press START to begin",
    statusColor: const Color(0xFF62D5B2),
  );

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _tts.setLanguage("en-US");
    _tts.setPitch(1.0);
    _tts.setSpeechRate(0.45);
  }

  /// Awaits completion of Text-to-Speech output
  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    Completer<void> completer = Completer();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    return completer.future;
  }

  /// Fetches current GPS Position
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      developer.log("GPS Location Error: $e");
      return null;
    }
  }

  /// Filter Stop List (Prefers 2km - 10km, fallback to index 0) and Open Google Maps Externally
  void _selectAndLaunchNavigation(List<dynamic> stops) async {
    if (stops.isEmpty) return;

    dynamic selectedStop;

    for (var stop in stops) {
      double distance = (stop['distance_km'] ?? 0.0).toDouble();
      if (distance >= 2.0 && distance <= 10.0) {
        selectedStop = stop;
        break;
      }
    }

    // Fallback to first location if none in 2km-10km range
    selectedStop ??= stops.first;

    // Extract nested location map
    final locationMap = selectedStop['location'];
    double targetLat = (locationMap['latitude'] as num).toDouble();
    double targetLon = (locationMap['longitude'] as num).toDouble();

    // Launch external turn-by-turn navigation in Google Maps
    final Uri googleMapsUri = Uri.parse(
      'google.navigation:q=$targetLat,$targetLon&mode=d',
    );

    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri, mode: LaunchMode.externalNonBrowserApplication);
    } else {
      // Fallback web browser deep link
      final Uri webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$targetLat,$targetLon',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Automatic hands-free multi-turn voice response loop
  Future<void> _runVoiceLoop(double lat, double lon) async {
    bool continueDialogue = true;

    while (continueDialogue && mounted) {
      await Future.delayed(const Duration(milliseconds: 1000));

      // Check mic permissions
      if (!await Permission.microphone.request().isGranted) break;

      final tempDir = await getTemporaryDirectory();
      String recordingPath = '${tempDir.path}/driver_response.wav';

      // Automatically record voice response for 5 seconds
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: recordingPath,
      );
      await Future.delayed(const Duration(seconds: 8));
      await _recorder.stop();

      // Send recorded audio to backend API
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$kBackendBaseUrl/api/drowsiness/respond-voice'),
      );

      request.fields['start_lat'] = lat.toString();
      request.fields['start_lon'] = lon.toString();
      request.fields['destination'] = widget.destination;
      request.fields['session_id'] = 'driver_session';

      request.files.add(
        await http.MultipartFile.fromPath('audio_file', recordingPath),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String speakText = data['speak_text'] ?? "";
        continueDialogue = data['continue_dialogue'] ?? false;

        if (speakText.isNotEmpty) {
          await _speak(speakText);
        }

        // Auto-launch Google Maps if rest stops were parsed
        if (data['stops'] != null && (data['stops'] as List).isNotEmpty) {
          _selectAndLaunchNavigation(data['stops']);
          continueDialogue = false;
        }
      } else {
        continueDialogue = false;
      }
    }
  }

  /// Primary Alert Processing Handler
  Future<void> _processAudioAlert(String alertState) async {
    if (_isCoolingDown || _isConversing) return;

    if (alertState == "STRONG" || alertState == "MODERATE") {
      _isConversing = true;
      _isCoolingDown = true;

      // Local chime audio
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      if (alertState == "STRONG") {
        await _audioPlayer.play(AssetSource('strong_level.mp3'));
      } else {
        await _audioPlayer.play(AssetSource('moderate_level.mp3'));
      }

      Position? pos = await _getCurrentPosition();
      double currentLat = pos?.latitude ?? 0.0;
      double currentLon = pos?.longitude ?? 0.0;

      // Terminal summary log
      developer.log('''
{
  vehicle_type: ${widget.vehicleType},
  destination: ${widget.destination},
  driver_location: "$currentLat, $currentLon",
  drowsiness_level: $alertState
}
''', name: 'DrowsinessAlert');

      try {
        // Post trigger to Python FastAPI backend
        final response = await http.post(
          Uri.parse('$kBackendBaseUrl/api/drowsiness/trigger'),
          body: {
            'drowsiness_level': alertState,
            'start_lat': currentLat.toString(),
            'start_lon': currentLon.toString(),
            'destination': widget.destination,
            'session_id': 'driver_session',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String speakText = data['speak_text'] ?? "";

          await _speak(speakText);

          // Handle stops & turn-by-turn navigation for STRONG fatigue
          if (data['stops'] != null && (data['stops'] as List).isNotEmpty) {
            _selectAndLaunchNavigation(data['stops']);
          }

          // Trigger automated voice response loop for MODERATE fatigue
          if (alertState == "MODERATE") {
            await _runVoiceLoop(currentLat, currentLon);
          }
        }
      } catch (e) {
        developer.log("Backend Connection Error: $e");
      } finally {
        _isConversing = false;
        
        // 15-second cooldown to avoid continuous triggers
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(const Duration(seconds: 15), () {
          _isCoolingDown = false;
        });
      }
    }
  }

  void _updateFps() {
    final now = DateTime.now();
    final lastFrameTime = _lastFrameTime;

    if (lastFrameTime != null) {
      final elapsedMs = now.difference(lastFrameTime).inMilliseconds;
      if (elapsedMs > 0) {
        final currentFps = 1000 / elapsedMs;
        _fps = (_fps * 0.7) + (currentFps * 0.3);
      }
    }
    _lastFrameTime = now;
  }

  void _startCamera() {
    _drowsinessDetector.reset();
    _isCoolingDown = false;
    _isConversing = false;
    _cooldownTimer?.cancel();

    setState(() {
      _isCameraRunning = true;
      _fps = 0;
      _lastFrameTime = null;
      _drowsinessStatus = DrowsinessResult(
        state: "NORMAL",
        perclos: 0.0,
        message: "Starting detector...",
        statusColor: const Color(0xFF62D5B2),
      );
    });
  }

  void _stopCamera() async {
    await _audioPlayer.stop();
    _tts.stop();
    _isCoolingDown = false;
    _isConversing = false;
    _cooldownTimer?.cancel();

    setState(() {
      _isCameraRunning = false;
      _fps = 0;
      _lastFrameTime = null;
      _drowsinessStatus = DrowsinessResult(
        state: "NORMAL",
        perclos: 0.0,
        message: "Camera stopped",
        statusColor: Colors.grey,
      );
    });
  }

  void _flipCamera() {
    if (_isCameraRunning) {
      _yoloController.switchCamera();
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _audioPlayer.dispose();
    _tts.stop();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring Session'),
        backgroundColor: const Color(0xFF20252B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isCameraRunning)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              tooltip: 'Flip Camera',
              onPressed: _flipCamera,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252B32),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Vehicle: ${widget.vehicleType}', style: const TextStyle(color: Colors.white70)),
                    Text('To: ${widget.destination}', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      ColoredBox(
                        color: const Color(0xFF252B32),
                        child: _isCameraRunning
                            ? YOLOView(
                                modelPath: 'assets/yolo11n_best.tflite',
                                controller: _yoloController,
                                task: YOLOTask.detect,
                                onResult: (results) {
                                  if (!_isCameraRunning) return;

                                  _updateFps();
                                  final result = _drowsinessDetector.update(results, _fps);

                                  _processAudioAlert(result.state);

                                  if (mounted) {
                                    setState(() {
                                      _drowsinessStatus = result;
                                    });
                                  }
                                },
                              )
                            : Center(
                                child: Icon(
                                  Icons.videocam_outlined,
                                  size: 64,
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                              ),
                      ),

                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'FPS ${_fps.toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                      if (_isCameraRunning)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _drowsinessStatus.statusColor,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _drowsinessStatus.message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _drowsinessStatus.statusColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'PERCLOS: ${_drowsinessStatus.perclos.toStringAsFixed(1)}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isCameraRunning ? null : _startCamera,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('START'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _isCameraRunning ? _flipCamera : null,
                    icon: const Icon(Icons.cameraswitch),
                    tooltip: 'Switch Camera',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isCameraRunning ? _stopCamera : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('STOP'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}