import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

typedef InputImageCallback = Future<void> Function(InputImage inputImage);

/// Displays the live camera feed and converts every frame for ML Kit.
class CameraView extends StatefulWidget {
  const CameraView({
    required this.onImage,
    this.customPaint,
    this.onCameraLensDirectionChanged,
    this.initialCameraLensDirection = CameraLensDirection.front,
    super.key,
  });

  final InputImageCallback onImage;
  final CustomPaint? customPaint;
  final ValueChanged<CameraLensDirection>? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  CameraDescription? _camera;
  String? _errorMessage;
  int _sessionId = 0;
  bool _appIsActive = true;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appIsActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;

    if (_appIsActive) {
      unawaited(_initializeCamera());
    } else {
      unawaited(_releaseCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (!_appIsActive || _controller != null) {
      return;
    }

    if (!_isSupportedPlatform) {
      _setError('La detección de poses solo está disponible en Android e iOS.');
      return;
    }

    final sessionId = ++_sessionId;
    CameraController? nextController;

    try {
      final cameras = await availableCameras();
      if (!_isCurrentSession(sessionId)) {
        return;
      }
      if (cameras.isEmpty) {
        _setError('No se encontró una cámara disponible.');
        return;
      }

      final camera = _selectCamera(cameras);
      nextController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await nextController.initialize();
      if (!_isCurrentSession(sessionId)) {
        await _disposeController(nextController);
        return;
      }

      _camera = camera;
      _controller = nextController;
      await nextController.startImageStream(_processCameraImage);

      if (!_isCurrentSession(sessionId)) {
        _controller = null;
        _camera = null;
        await _disposeController(nextController);
        return;
      }

      widget.onCameraLensDirectionChanged?.call(camera.lensDirection);
      if (mounted) {
        setState(() => _errorMessage = null);
      }
    } on CameraException catch (error) {
      if (identical(_controller, nextController)) {
        _controller = null;
        _camera = null;
      }
      if (nextController != null) {
        await _disposeController(nextController);
      }
      if (_isCurrentSession(sessionId)) {
        _setError(_cameraErrorMessage(error));
      }
    } catch (error) {
      if (identical(_controller, nextController)) {
        _controller = null;
        _camera = null;
      }
      if (nextController != null) {
        await _disposeController(nextController);
      }
      if (_isCurrentSession(sessionId)) {
        _setError('No fue posible inicializar la cámara: $error');
      }
    }
  }

  CameraDescription _selectCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == widget.initialCameraLensDirection) {
        return camera;
      }
    }
    return cameras.first;
  }

  bool _isCurrentSession(int sessionId) =>
      mounted && _appIsActive && sessionId == _sessionId;

  void _processCameraImage(CameraImage image) {
    final controller = _controller;
    final camera = _camera;
    if (controller == null || camera == null) {
      return;
    }

    final inputImage = _inputImageFromCameraImage(image, controller, camera);
    if (inputImage != null) {
      unawaited(widget.onImage(inputImage));
    }
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
    CameraDescription camera,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final isValidFormat =
        format != null &&
        ((defaultTargetPlatform == TargetPlatform.android &&
                format == InputImageFormat.nv21) ||
            (defaultTargetPlatform == TargetPlatform.iOS &&
                format == InputImageFormat.bgra8888));

    if (!isValidFormat || image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _releaseCamera() async {
    _sessionId++;
    final controller = _controller;
    _controller = null;
    _camera = null;
    if (controller != null) {
      await _disposeController(controller);
    }
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // The native camera may already be unavailable during app suspension.
    }
    await controller.dispose();
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'Permiso de cámara denegado.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Habilita el permiso de cámara desde los ajustes del dispositivo.';
      case 'CameraAccessRestricted':
        return 'El acceso a la cámara está restringido en este dispositivo.';
      default:
        return 'Error de cámara (${error.code}): ${error.description ?? 'desconocido'}';
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appIsActive = false;
    unawaited(_releaseCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: CameraPreview(controller, child: widget.customPaint),
      ),
    );
  }
}
