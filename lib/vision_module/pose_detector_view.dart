import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'camera_view.dart';

/// Runs on-device pose detection over the live camera stream.
class PoseDetectorView extends StatefulWidget {
  const PoseDetectorView({super.key});

  @override
  State<PoseDetectorView> createState() => _PoseDetectorViewState();
}

class _PoseDetectorViewState extends State<PoseDetectorView> {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;
  CustomPaint? _poseOverlay;
  String? _errorMessage;
  bool _canProcess = true;
  bool _isBusy = false;

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess || _isBusy) {
      return;
    }

    _isBusy = true;
    try {
      final poses = await _poseDetector.processImage(inputImage);
      if (!_canProcess || !mounted) {
        return;
      }

      final metadata = inputImage.metadata;
      setState(() {
        _errorMessage = null;
        _poseOverlay = metadata == null || poses.isEmpty
            ? null
            : CustomPaint(
                painter: PosePainter(
                  poses: poses,
                  imageSize: metadata.size,
                  rotation: metadata.rotation,
                  cameraLensDirection: _cameraLensDirection,
                ),
              );
      });
    } catch (error) {
      if (_canProcess && mounted) {
        setState(() {
          _errorMessage = 'No fue posible procesar el frame: $error';
          _poseOverlay = null;
        });
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _closeDetector() async {
    try {
      await _poseDetector.close();
    } catch (_) {
      // The platform channel may already be closed while the app shuts down.
    }
  }

  @override
  void dispose() {
    _canProcess = false;
    unawaited(_closeDetector());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edge-AI · Detección de pose')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraView(
            initialCameraLensDirection: CameraLensDirection.front,
            onCameraLensDirectionChanged: (direction) {
              _cameraLensDirection = direction;
            },
            onImage: _processImage,
            customPaint: _poseOverlay,
          ),
          if (_errorMessage case final message?)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints every landmark reported by ML Kit (33 points per complete pose).
class PosePainter extends CustomPainter {
  const PosePainter({
    required this.poses,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = Colors.lightGreenAccent
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final pose in poses) {
      for (final landmark in pose.landmarks.values) {
        final point = Offset(
          _translateX(landmark.x, size),
          _translateY(landmark.y, size),
        );
        canvas
          ..drawCircle(point, 5, borderPaint)
          ..drawCircle(point, 3.5, pointPaint);
      }
    }
  }

  double _translateX(double x, Size canvasSize) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (isIos ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            (x *
                canvasSize.width /
                (isIos ? imageSize.width : imageSize.height));
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        final translatedX = x * canvasSize.width / imageSize.width;
        return cameraLensDirection == CameraLensDirection.back
            ? translatedX
            : canvasSize.width - translatedX;
    }
  }

  double _translateY(double y, Size canvasSize) {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (isIos ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) =>
      oldDelegate.poses != poses ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.rotation != rotation ||
      oldDelegate.cameraLensDirection != cameraLensDirection;
}
