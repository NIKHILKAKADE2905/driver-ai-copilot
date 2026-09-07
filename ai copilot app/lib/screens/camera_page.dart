import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';
import 'package:demo_cam_application/config.dart';
import 'package:demo_cam_application/copilot_api.dart';
import 'package:demo_cam_application/drowsiness_detector.dart';
import 'package:demo_cam_application/missed_stop_monitor.dart';
import 'package:demo_cam_application/monitoring_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:url_launcher/url_launcher.dart';

class CameraPage extends StatefulWidget {
  final String vehicleType;
  final String destination;
  final String sessionId;
  final double destLat;
  final double destLon;

  const CameraPage({
    super.key,
    required this.vehicleType,
    required this.destination,
    required this.sessionId,
    required this.destLat,
    required this.destLon,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final YOLOViewController _yoloController = YOLOViewController();
  final DrowsinessDetector _drowsinessDetector = DrowsinessDetector(windowSeconds: 60);
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();
  late final CopilotApi _api;

  bool _isCoolingDown = false;
  bool _isConversing = false;
  bool _isListening = false;
  bool _copilotOffline = false;
  bool _showFaceLostBanner = false;
  bool _faceLostSpoken = false;
  DateTime? _faceLostSince;
  int _moderateRefusalCount = 0;
  Timer? _cooldownTimer;
  StreamSubscription<Position>? _gpsSub;
  final MissedStopMonitor _stopWatch = MissedStopMonitor();
  bool _handlingMissedStop = false;

  bool _isCameraRunning = false;
  bool _keepScreenOn = true;
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
    _api = CopilotApi(
      destination: widget.destination,
      sessionId: widget.sessionId,
      vehicleType: widget.vehicleType,
      destLat: widget.destLat,
      destLon: widget.destLon,
    );
    _initTts();
  }

  void _initTts() {
    _tts.setLanguage("en-US");
    _tts.setPitch(1.0);
    _tts.setSpeechRate(0.45);
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    await _tts.speak(text);
    return completer.future;
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
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

  Future<void> _selectAndLaunchNavigation(List<dynamic> stops) async {
    if (stops.isEmpty) return;

    dynamic selectedStop;
    for (final stop in stops) {
      final distance = (stop['distance_km'] ?? 0.0).toDouble();
      if (distance >= 2.0 && distance <= 10.0) {
        selectedStop = stop;
        break;
      }
    }
    selectedStop ??= stops.first;

    final locationMap = selectedStop['location'];
    final targetLat = (locationMap['latitude'] as num).toDouble();
    final targetLon = (locationMap['longitude'] as num).toDouble();
    final stopName = (selectedStop['displayName'] ?? 'the rest stop').toString();
    final distanceKm = (selectedStop['distance_km'] as num?)?.toDouble();
    final distanceBit = distanceKm == null
        ? ''
        : ', ${distanceKm.toStringAsFixed(1)} kilometers ahead';
    await _speak('Opening maps to $stopName$distanceBit.');
    _stopWatch.arm(
      GuidedStop(name: stopName, latitude: targetLat, longitude: targetLon),
    );
    await _openMapsTo(targetLat, targetLon);
  }

  Future<void> _openMapsTo(double targetLat, double targetLon) async {
    final googleMapsUri = Uri.parse(
      'google.navigation:q=$targetLat,$targetLon&mode=d',
    );

    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri, mode: LaunchMode.externalNonBrowserApplication);
    } else {
      final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$targetLat,$targetLon',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleStopWatch(Position pos) async {
    if (!_isCameraRunning || _handlingMissedStop) return;
    final outcome = _stopWatch.observe(
      driverLat: pos.latitude,
      driverLon: pos.longitude,
      speedMps: pos.speed,
      now: DateTime.now(),
    );
    if (outcome == StopWatchOutcome.arrived) {
      developer.log('Arrived at guided rest stop', name: 'MissedStop');
      return;
    }
    if (outcome != StopWatchOutcome.missed) return;

    final stop = _stopWatch.target;
    if (stop == null) return;

    _handlingMissedStop = true;
    try {
      await _speak(missedStopPrompt(stop.name));
      await _openMapsTo(stop.latitude, stop.longitude);
    } finally {
      _handlingMissedStop = false;
    }
  }

  void _startGpsWatch() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (pos) {
        _handleStopWatch(pos);
      },
      onError: (e) => developer.log('GPS stream error: $e'),
    );
  }

  void _stopGpsWatch() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _stopWatch.clear();
  }

  Future<void> _runVoiceLoop(double? lat, double? lon) async {
    var continueDialogue = true;

    while (continueDialogue && mounted) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!await Permission.microphone.request().isGranted) break;

      final tempDir = await getTemporaryDirectory();
      final recordingPath = '${tempDir.path}/driver_response.wav';

      if (mounted) setState(() => _isListening = true);

      try {
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: recordingPath,
        );
        await Future.delayed(const Duration(seconds: 8));
        await _recorder.stop();
      } catch (e) {
        developer.log("Recording Error: $e");
      } finally {
        if (mounted) setState(() => _isListening = false);
      }

      try {
        final streamedResponse = await _api.respondVoice(
          audioPath: recordingPath,
          startLat: lat,
          startLon: lon,
        );
        final response =
            await http.Response.fromStream(streamedResponse).timeout(kBackendTimeout);

        if (response.statusCode == 200) {
          if (mounted) setState(() => _copilotOffline = false);
          final data = jsonDecode(response.body);
          final speakText = data['speak_text'] ?? "";
          continueDialogue = data['continue_dialogue'] ?? false;
          final stops = data['stops'] as List? ?? [];

          if (speakText.isNotEmpty) {
            await _speak(speakText);
          }

          if (stops.isNotEmpty) {
            _moderateRefusalCount = 0;
            await _selectAndLaunchNavigation(stops);
            continueDialogue = false;
          } else if (!continueDialogue) {
            _moderateRefusalCount += 1;
          }
        } else {
          if (mounted) setState(() => _copilotOffline = true);
          await _speak(kCannedOfflineVoice);
          continueDialogue = false;
        }
      } catch (e) {
        developer.log("Voice loop backend error: $e");
        if (mounted) setState(() => _copilotOffline = true);
        await _speak(kCannedOfflineVoice);
        continueDialogue = false;
      }
    }
  }

  Future<void> _processAudioAlert(String alertState) async {
    if (_isCoolingDown || _isConversing) return;

    if (alertState == "STRONG" || alertState == "MODERATE") {
      var effectiveState = alertState;
      if (alertState == "MODERATE" && _moderateRefusalCount >= 2) {
        effectiveState = "STRONG";
      }

      _isConversing = true;
      _isCoolingDown = true;

      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      final audioSource = (effectiveState == "STRONG")
          ? AssetSource('strong_level.mp3')
          : AssetSource('moderate_level.mp3');

      final audioCompleter = Completer<void>();
      StreamSubscription? playerSub;

      playerSub = _audioPlayer.onPlayerComplete.listen((event) {
        if (!audioCompleter.isCompleted) audioCompleter.complete();
        playerSub?.cancel();
      });

      await _audioPlayer.play(audioSource);
      await audioCompleter.future;

      final pos = await _getCurrentPosition();
      final hasGps = pos != null;
      final currentLat = pos?.latitude;
      final currentLon = pos?.longitude;

      var usedOfflineCanned = false;

      try {
        final response = await _api.trigger(
          drowsinessLevel: effectiveState,
          startLat: currentLat,
          startLon: currentLon,
        );

        if (response.statusCode == 200) {
          if (mounted) setState(() => _copilotOffline = false);
          final data = jsonDecode(response.body);
          final speakText = (data['speak_text'] ?? "").toString().trim();
          final stops = data['stops'] as List? ?? [];

          if (speakText.isNotEmpty) {
            await _speak(speakText);
          }

          if (!hasGps) {
            await _speak(kCannedNoGps);
          } else if (stops.isNotEmpty) {
            await _selectAndLaunchNavigation(stops);
          }

          if (effectiveState == "MODERATE") {
            await _runVoiceLoop(currentLat, currentLon);
          }
        } else {
          usedOfflineCanned = true;
        }
      } catch (e) {
        developer.log("Backend Connection Error: $e");
        usedOfflineCanned = true;
      }

      if (usedOfflineCanned) {
        if (mounted) setState(() => _copilotOffline = true);
        await _speak(
          effectiveState == "STRONG"
              ? kCannedOfflineStrong
              : kCannedOfflineModerate,
        );
        if (!hasGps) {
          await _speak(kCannedNoGps);
        }
      }

      _isConversing = false;
      if (mounted) setState(() => _isListening = false);

      final cooldownSeconds = effectiveState == "STRONG" ? 8 : 15;
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(Duration(seconds: cooldownSeconds), () {
        _isCoolingDown = false;
      });
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

  Future<void> _startCamera() async {
    _drowsinessDetector.reset();
    _isCoolingDown = false;
    _isConversing = false;
    _isListening = false;
    _copilotOffline = false;
    _showFaceLostBanner = false;
    _faceLostSpoken = false;
    _faceLostSince = null;
    _cooldownTimer?.cancel();

    try {
      await MonitoringService.start();
      await MonitoringService.setKeepScreenOn(_keepScreenOn);
    } catch (e) {
      developer.log('Foreground service error: $e');
    }

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
    _startGpsWatch();
  }

  Future<void> _stopCamera() async {
    await _audioPlayer.stop();
    _tts.stop();
    _isCoolingDown = false;
    _isConversing = false;
    _isListening = false;
    _copilotOffline = false;
    _showFaceLostBanner = false;
    _faceLostSpoken = false;
    _faceLostSince = null;
    _cooldownTimer?.cancel();
    _stopGpsWatch();
    await MonitoringService.stop();

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

  Future<void> _toggleKeepScreenOn(bool value) async {
    setState(() => _keepScreenOn = value);
    if (_isCameraRunning) {
      await MonitoringService.setKeepScreenOn(value);
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _gpsSub?.cancel();
    _audioPlayer.dispose();
    _tts.stop();
    _recorder.dispose();
    MonitoringService.stop();
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
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Vehicle: ${widget.vehicleType}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'To: ${widget.destination}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Keep screen on while monitoring',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: _keepScreenOn,
                      onChanged: _toggleKeepScreenOn,
                    ),
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
                                  final result =
                                      _drowsinessDetector.update(results, _fps);

                                  if (!result.faceDetected) {
                                    _faceLostSince ??= DateTime.now();
                                    final lostSeconds = DateTime.now()
                                        .difference(_faceLostSince!)
                                        .inSeconds;
                                    final showBanner = lostSeconds >= 5;
                                    if (showBanner && !_faceLostSpoken) {
                                      _faceLostSpoken = true;
                                      _speak(kCannedFaceLost);
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _drowsinessStatus = result;
                                        _showFaceLostBanner = showBanner;
                                      });
                                    }
                                    return;
                                  }

                                  _faceLostSince = null;
                                  _faceLostSpoken = false;
                                  _processAudioAlert(result.state);

                                  if (mounted) {
                                    setState(() {
                                      _drowsinessStatus = result;
                                      _showFaceLostBanner = false;
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
                      if (_isListening)
                        Positioned(
                          top: 16,
                          left: 80,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.mic, color: Colors.white, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'LISTENING... SPEAK NOW',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_showFaceLostBanner && !_isListening)
                        Positioned(
                          top: 16,
                          left: 80,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "I CAN'T SEE YOUR FACE",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (_copilotOffline)
                        Positioned(
                          top: _isListening || _showFaceLostBanner ? 56 : 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'COPILOT OFFLINE',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
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
