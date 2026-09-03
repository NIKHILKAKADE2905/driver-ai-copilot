# AI Voice Co-Pilot Android App

The Flutter Android client for the AI Voice Co-Pilot. It uses the device camera and a custom TensorFlow Lite YOLO model to monitor driver-facing detections, classifies fatigue locally, and communicates with the Python FastAPI backend when an intervention is needed.

> **Safety notice:** This is an experimental prototype, not a certified automotive, medical, or emergency-safety system. Do not rely on it as a substitute for rest, safe driving practices, or emergency services.

## App Flow

1. **Trip Setup** collects a vehicle type and destination.
2. **Monitoring Session** loads `assets/yolo11n_best.tflite` through `YOLOView`.
3. `DrowsinessDetector` tracks eye closure, head position, and yawns over time.
4. Moderate or strong fatigue plays a local alert and sends location and destination to the backend.
5. The app speaks the backend response with Android text-to-speech.
6. Returned rest stops open in Google Maps navigation.

Moderate fatigue starts an automatic voice loop that records an eight-second WAV response. Strong fatigue requests route stops immediately.

## Requirements

- Flutter with Dart 3.13.1 or compatible
- Android Studio and Android SDK
- Android SDK compile level 37
- Java/Kotlin 17
- An Android emulator with a camera or a physical Android device
- The Python backend running on a reachable development machine

The complete workflow requires camera, microphone, location, Internet access, and Google Maps navigation support.

## Install

From this directory:

```powershell
flutter pub get
```

## Configure the Backend

Edit `lib/main.dart` and set `kBackendBaseUrl`:

```dart
// Android emulator
const String kBackendBaseUrl = "http://10.0.2.2:8000";

// Physical device example
// const String kBackendBaseUrl = "http://192.168.1.20:8000";
```

Use `10.0.2.2` to reach the host computer from an Android emulator. For a physical device, use the host computer's local network IP and keep both devices on the same network.

Start the backend from the repository root:

```powershell
uv run uvicorn server:app --reload --host 0.0.0.0 --port 8000
```

The backend requires `GROQ_API_KEY` and `MAPS_API_KEY` in the repository root `.env` file. See the root README for backend setup and API details.

## Run

Connect a device or start an emulator, then run:

```powershell
flutter run
```

Grant camera, microphone, and location permissions when requested. Enter a destination, select a vehicle type, choose **Proceed to Monitoring**, and press **START**.

## Detection Rules

The model classes are defined in `assets/labels.txt`:

```text
eye_closed
eye_open
head_dropped
head_straight
no_yawn
yawn
```

The detector uses a 60-second eye-closure buffer:

| State | Rule |
| --- | --- |
| `STRONG` | Eyes closed for at least 3 seconds and PERCLOS is at least 25% |
| `STRONG` | Head dropped for at least 3 seconds while eyes are closed |
| `MODERATE` | PERCLOS is 20% to below 25% and at least three valid yawns occurred within two minutes |
| `NORMAL` | All other cases |

Valid yawns last between three and eight seconds. A 15-second cooldown prevents repeated backend triggers.

## Assets

| Asset | Purpose |
| --- | --- |
| `assets/yolo11n_best.tflite` | Active on-device detection model |
| `assets/labels.txt` | Model class labels |
| `assets/moderate_level.mp3` | Moderate-fatigue alert sound |
| `assets/strong_level.mp3` | Strong-fatigue alert sound |
| `assets/yolo26n_best.tflite` | Present but currently unused and not declared in `pubspec.yaml` |

## Android Notes

The Android host declares camera, microphone, location, Internet, and foreground-service permissions. It uses Java/Kotlin 17 and application ID `com.example.demo_cam_application`.

Cleartext HTTP is enabled for local development and should be replaced with HTTPS before deployment. The current release configuration uses the debug signing key and is not ready for store distribution.

## Checks and Builds

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

For a release build, configure production signing first:

```powershell
flutter build apk --release
```

The repository contains one basic widget test. It expects monitoring controls immediately, while the app initially opens `TripSetupScreen`; update the test to navigate through setup before treating it as an acceptance test.

## Project Structure

```text
lib/main.dart          # UI, detector, permissions, audio, GPS, and API client
assets/                # TFLite model, labels, and alert audio
android/               # Android manifest, host activity, and Gradle configuration
test/widget_test.dart  # Flutter widget test
```

## Privacy and Limitations

- Camera inference runs on the device using the bundled model.
- Voice recordings are uploaded to the FastAPI backend and transcribed through Google Speech Recognition.
- Location and destination data are sent to the backend and Google Maps services for route planning.
- The vehicle type is displayed but does not currently change detection behavior.
- Detection accuracy depends on lighting, camera placement, driver position, model quality, and device performance.
- The app cannot guarantee that a driver is alert or that a recommended stop is safe or available.
