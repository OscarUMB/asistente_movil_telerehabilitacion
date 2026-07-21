import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pure mathematical utilities for calculating human joint kinematics.
abstract final class KinematicsEngine {
  static const double _minimumMagnitude = 1e-12;

  /// Calculates the interior angle ABC in degrees, in the range [0, 180].
  static double calculateAngle(
    PoseLandmark puntoA,
    PoseLandmark verticeB,
    PoseLandmark puntoC,
  ) {
    final baX = puntoA.x - verticeB.x;
    final baY = puntoA.y - verticeB.y;
    final bcX = puntoC.x - verticeB.x;
    final bcY = puntoC.y - verticeB.y;

    final dotProduct = (baX * bcX) + (baY * bcY);
    final magnitudeBA = math.sqrt((baX * baX) + (baY * baY));
    final magnitudeBC = math.sqrt((bcX * bcX) + (bcY * bcY));

    if (magnitudeBA <= _minimumMagnitude || magnitudeBC <= _minimumMagnitude) {
      return 0;
    }

    final cosine = (dotProduct / (magnitudeBA * magnitudeBC)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
}
