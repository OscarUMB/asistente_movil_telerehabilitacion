import 'package:asistente_movil_tele_rehabilitacion/vision_module/kinematics_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() {
  group('KinematicsEngine.calculateAngle', () {
    test('calculates a right angle', () {
      final angle = KinematicsEngine.calculateAngle(
        _landmark(x: 1, y: 0),
        _landmark(x: 0, y: 0),
        _landmark(x: 0, y: 1),
      );

      expect(angle, closeTo(90, 1e-9));
    });

    test('calculates a straight angle', () {
      final angle = KinematicsEngine.calculateAngle(
        _landmark(x: -1, y: 0),
        _landmark(x: 0, y: 0),
        _landmark(x: 1, y: 0),
      );

      expect(angle, closeTo(180, 1e-9));
    });

    test('returns zero when a vector has no magnitude', () {
      final angle = KinematicsEngine.calculateAngle(
        _landmark(x: 0, y: 0),
        _landmark(x: 0, y: 0),
        _landmark(x: 1, y: 1),
      );

      expect(angle, 0);
    });
  });
}

PoseLandmark _landmark({required double x, required double y}) => PoseLandmark(
  type: PoseLandmarkType.leftElbow,
  x: x,
  y: y,
  z: 0,
  likelihood: 1,
);
