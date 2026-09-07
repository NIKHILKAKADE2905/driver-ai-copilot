import 'dart:convert';

import 'package:demo_cam_application/config.dart';
import 'package:http/http.dart' as http;

class GeocodeResult {
  final double latitude;
  final double longitude;
  final String destination;

  GeocodeResult({
    required this.latitude,
    required this.longitude,
    required this.destination,
  });
}

class CopilotApi {
  CopilotApi({
    required this.destination,
    required this.sessionId,
    required this.vehicleType,
    required this.destLat,
    required this.destLon,
  });

  final String destination;
  final String sessionId;
  final String vehicleType;
  final double destLat;
  final double destLon;

  Map<String, String> tripFields() {
    return {
      'destination': destination,
      'session_id': sessionId,
      'vehicle_type': vehicleType,
      'dest_lat': destLat.toString(),
      'dest_lon': destLon.toString(),
    };
  }

  static Future<http.Response> geocode(String destination) {
    return http
        .post(
          Uri.parse('$kBackendBaseUrl/api/destination/geocode'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'destination': destination}),
        )
        .timeout(kBackendTimeout);
  }

  Future<http.Response> trigger({
    required String drowsinessLevel,
    double? startLat,
    double? startLon,
  }) {
    final body = <String, String>{
      'drowsiness_level': drowsinessLevel,
      ...tripFields(),
    };
    if (startLat != null && startLon != null) {
      body['start_lat'] = startLat.toString();
      body['start_lon'] = startLon.toString();
    }
    return http
        .post(Uri.parse('$kBackendBaseUrl/api/drowsiness/trigger'), body: body)
        .timeout(kBackendTimeout);
  }

  Future<http.StreamedResponse> respondVoice({
    required String audioPath,
    double? startLat,
    double? startLon,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$kBackendBaseUrl/api/drowsiness/respond-voice'),
    );
    request.fields.addAll(tripFields());
    if (startLat != null && startLon != null) {
      request.fields['start_lat'] = startLat.toString();
      request.fields['start_lon'] = startLon.toString();
    }
    request.files.add(await http.MultipartFile.fromPath('audio_file', audioPath));
    return request.send().timeout(kBackendTimeout);
  }
}
