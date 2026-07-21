import 'package:asistente_movil_tele_rehabilitacion/main.dart';
import 'package:asistente_movil_tele_rehabilitacion/vision_module/pose_detector_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens the Edge-AI pose detector', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(PoseDetectorView), findsOneWidget);
    expect(find.text('Edge-AI · Detección de pose'), findsOneWidget);
  });
}
