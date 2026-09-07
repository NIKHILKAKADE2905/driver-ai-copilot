const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: "http://<YOUR_LOCAL_IP>:8000",
);
const Duration kBackendTimeout = Duration(seconds: 25);
const String kCannedOfflineStrong =
    "Pull over as soon as it is safe. I cannot reach the co-pilot right now.";
const String kCannedOfflineModerate =
    "You look tired. I cannot reach the co-pilot. Consider taking a short break.";
const String kCannedOfflineVoice =
    "I lost the connection. Stay safe, and pull over if you need to rest.";
const String kCannedNoGps =
    "I don't have your location, so I can't open maps. Pull over at the next safe place.";
const String kCannedFaceLost =
    "I can't see your face. Please check that the camera is on you.";
const String kSessionIdPrefKey = 'copilot_session_id';
const String kDisclaimerAcceptedPrefKey = 'copilot_disclaimer_accepted';

String missedStopPrompt(String stopName) {
  return "You missed $stopName. Turn around and go back there right away.";
}
