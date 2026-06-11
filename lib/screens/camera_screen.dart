import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/storage_service.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  final String personName;

  const CameraScreen({super.key, required this.personName});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  String? _errorMessage;

  // Countdown
  bool _countdownEnabled = false;
  int _countdownSeconds = 15;
  int _remaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _countdownEnabled = prefs.getBool('countdown_enabled') ?? false;
    _countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'Aucune caméra disponible');
        return;
      }
      // Prefer back camera as the starting lens
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startController(_cameras[_cameraIndex]);
    } catch (e) {
      setState(() => _errorMessage = 'Impossible d\'accéder à la caméra : $e');
    }
  }

  Future<void> _startController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _maybeStartCountdown();
      }
    } on CameraException catch (e) {
      setState(() => _errorMessage = 'Erreur caméra : ${e.description}');
    }
  }

  void _maybeStartCountdown() {
    if (!_countdownEnabled || _timer != null) return;
    _remaining = _countdownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 3 && _remaining > 0) {
        HapticFeedback.lightImpact();
      }
      if (_remaining <= 0) {
        timer.cancel();
        // Temps écoulé : capture automatique pour forcer la spontanéité
        _takePhoto();
      }
    });
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isTakingPhoto) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    setState(() => _isInitialized = false);
    await _startController(_cameras[_cameraIndex]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(controller.description);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPhoto) {
      return;
    }

    _timer?.cancel();
    setState(() => _isTakingPhoto = true);
    HapticFeedback.heavyImpact();

    try {
      final xFile = await controller.takePicture();
      final entry = await StorageService.savePhoto(
        photoFile: File(xFile.path),
        personName: widget.personName,
      );

      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultScreen(entry: entry),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTakingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _ErrorView(message: _errorMessage!);
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Viewfinder BeReal : cadre arrondi plein écran
        Padding(
          padding: EdgeInsets.only(top: topPad + 70, bottom: bottomPad + 150),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: CameraPreview(_controller!),
          ),
        ),

        // En-tête : prénom à capturer + compte à rebours
        Positioned(
          top: topPad + 12,
          left: 0,
          right: 0,
          child: _Header(
            personName: widget.personName,
            countdownEnabled: _countdownEnabled,
            remaining: _remaining,
          ),
        ),

        // Bas : flip caméra + bouton capture
        Positioned(
          bottom: bottomPad + 36,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 64),
              Expanded(
                child: Center(
                  child: _CaptureButton(
                    onPressed: _isTakingPhoto ? null : _takePhoto,
                    isLoading: _isTakingPhoto,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: _cameras.length > 1
                    ? _FlipButton(onPressed: _isTakingPhoto ? null : _flipCamera)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        Positioned(
          bottom: bottomPad + 120,
          left: 0,
          right: 0,
          child: const Text(
            'Une seule chance — pas de seconde prise',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String personName;
  final bool countdownEnabled;
  final int remaining;

  const _Header({
    required this.personName,
    required this.countdownEnabled,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = remaining <= 3;
    return Column(
      children: [
        Text(
          personName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'capture maintenant',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        if (countdownEnabled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: urgent ? Colors.red : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '⏱ $remaining s',
              style: TextStyle(
                color: urgent ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FlipButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _FlipButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.cameraswitch_outlined,
            color: Colors.white, size: 26),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _CaptureButton({required this.onPressed, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: isLoading ? 72 : 82,
        height: isLoading ? 72 : 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(color: Colors.white, width: 5),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Retour',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}
