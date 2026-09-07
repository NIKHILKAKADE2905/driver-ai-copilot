import 'package:demo_cam_application/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first launch shows disclaimer and privacy', (tester) async {
    await tester.pumpWidget(
      const MyApp(sessionId: 'test_session_01', disclaimerAccepted: false),
    );

    expect(find.text('Driver aid only'), findsOneWidget);
    expect(find.textContaining('You remain fully responsible'), findsOneWidget);
    expect(find.textContaining('face is processed on this phone'), findsOneWidget);
    expect(find.textContaining('voice audio, GPS location'), findsOneWidget);
    expect(find.text('I UNDERSTAND — CONTINUE'), findsOneWidget);
  });

  testWidgets('accepted disclaimer goes to trip setup', (tester) async {
    await tester.pumpWidget(
      const MyApp(sessionId: 'test_session_01', disclaimerAccepted: true),
    );

    expect(find.text('Trip Setup'), findsOneWidget);
    expect(find.text('PROCEED TO MONITORING'), findsOneWidget);
  });
}
