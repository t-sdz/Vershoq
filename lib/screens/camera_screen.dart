import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/storage_service.dart';
import '../theme/v_theme.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  /// Alerte pour laquelle on prend la photo (null = ancien mode « libre »).
  final String? alertId;

  /// Prénoms à afficher en mode « libre » (sans alerte).
  final String personName;

  const CameraScreen({super.key, this.alertId, this.personName = ''});

  /// Vrai tant qu'un écran caméra est affiché : les appelants le vérifient
  /// avant d'en pousser un autre (pas de caméras empilées).
  static bool get isOpen => _CameraScreenState._openCount > 0;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

/// État de l'alerte associée à l'écran.
enum _AlertState { loading, ready, unavailable, tooLate }

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static int _openCount = 0;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;
  bool _starting = false;
  // Contrôleur libéré quand l'app passe en arrière-plan → à relancer au retour.
  bool _needsRestart = false;
  String? _errorMessage;

  AlertMoment? _alert;
  _AlertState _state = _AlertState.loading;

  // Compte à rebours strict : deadline = sentAt + cd (même pour tout le groupe).
  Timer? _timer;
  int _remainingMs = 0;
  int _lastShownSecs = -1;
  bool _expired = false;

  bool get _hasCountdown => _alert?.hasCountdown ?? false;

  String get _names => _alert?.names ?? widget.personName;

  @override
  void initState() {
    super.initState();
    _openCount++;
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = widget.alertId;
    if (id == null) {
      // Ancien mode : pas d'alerte, pas de compte à rebours.
      _state = _AlertState.ready;
      await _initCamera();
      return;
    }
    var m = await NotificationService.momentById(id);
    if (m == null) {
      // Alerte inconnue en local : on la relit sur le serveur.
      await PushService.syncLastAlert();
      m = await NotificationService.momentById(id);
    }
    // Notif d'une alerte remplacée par une plus récente : on ouvre la
    // caméra pour l'alerte EN COURS du groupe.
    m ??= await NotificationService.peekActiveAlert();
    final consumed = m == null || await NotificationService.isConsumed(m.id);
    if (!mounted) return;
    if (m == null || consumed) {
      setState(() => _state = _AlertState.unavailable);
      return;
    }
    if (m.isExpired()) {
      setState(() => _state = _AlertState.tooLate);
      return;
    }
    setState(() {
      _alert = m;
      _state = _AlertState.ready;
    });
    if (m.hasCountdown) _startTicker();
    await _initCamera();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _tick();
  }

  /// Recalcule le temps restant à partir de l'horloge murale (pas de dérive).
  void _tick() {
    final alert = _alert;
    if (!mounted || alert == null) return;
    final ms = alert.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    final secs = ms <= 0 ? 0 : (ms / 1000).ceil();
    if (secs != _lastShownSecs) {
      if (secs <= 3 && secs > 0) HapticFeedback.lightImpact();
      _lastShownSecs = secs;
    }
    setState(() => _remainingMs = ms > 0 ? ms : 0);
    if (ms <= 0) {
      _timer?.cancel();
      _timer = null;
      _onDeadline();
    }
  }

  /// Temps écoulé : capture automatique si la caméra est prête, sinon trop
  /// tard (pas de photo pour cette alerte).
  void _onDeadline() {
    if (_expired) return;
    _expired = true;
    if (_isTakingPhoto) return; // la photo en cours compte
    final c = _controller;
    if (_isInitialized && c != null && c.value.isInitialized) {
      _takePhoto(auto: true);
    } else {
      _goTooLate();
    }
  }

  void _goTooLate() {
    _timer?.cancel();
    _timer = null;
    _expired = true;
    final c = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _state = _AlertState.tooLate;
      });
    }
    c?.dispose();
  }

  Future<void> _initCamera() async {
    try {
      // Demande explicite de la permission caméra (requise sur MIUI/Xiaomi)
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() => _errorMessage =
            'Permission caméra refusée.\nActive-la dans les paramètres de l\'app.');
        return;
      }

      _cameras = await availableCameras();
      if (!mounted) return;
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
      if (mounted) {
        setState(() => _errorMessage = 'Impossible d\'accéder à la caméra : $e');
      }
    }
  }

  Future<void> _startController(CameraDescription camera) async {
    if (_starting) return;
    _starting = true;
    try {
      for (final preset in [
        ResolutionPreset.high,
        ResolutionPreset.medium,
        ResolutionPreset.low,
      ]) {
        final controller = CameraController(
          camera,
          preset,
          enableAudio: false,
        );
        _controller = controller;
        try {
          await controller.initialize();
          if (!mounted || _state != _AlertState.ready) {
            // Écran fermé ou alerte expirée entre-temps.
            if (_controller == controller) _controller = null;
            await controller.dispose();
            return;
          }
          setState(() => _isInitialized = true);
          return;
        } on CameraException {
          await controller.dispose();
          if (_controller == controller) _controller = null;
        }
      }
      if (mounted) {
        setState(() => _errorMessage = 'Impossible d\'initialiser la caméra');
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _isTakingPhoto || _expired) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final old = _controller;
    _controller = null;
    setState(() => _isInitialized = false);
    await old?.dispose();
    await _startController(_cameras[_cameraIndex]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      // Pas pendant une capture (sinon la photo en cours échoue).
      if (controller == null || _isTakingPhoto) return;
      // On marque non-initialisé AVANT de libérer, sinon l'aperçu se
      // reconstruit sur un contrôleur libéré → exception / écran noir.
      _controller = null;
      _needsRestart = true;
      if (mounted) setState(() => _isInitialized = false);
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!_needsRestart || _controller != null) return;
      _needsRestart = false;
      final alert = _alert;
      if (alert != null && (alert.isExpired() || _expired)) {
        _goTooLate();
        return;
      }
      if (_state == _AlertState.ready &&
          _errorMessage == null &&
          _cameras.isNotEmpty) {
        _startController(_cameras[_cameraIndex]);
      }
    }
  }

  @override
  void dispose() {
    _openCount--;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<File> _maybeFlip(File file) async {
    final isFront = _cameras.isNotEmpty &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    if (!isFront) return file;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return file;
    final flipped = img.flipHorizontal(decoded);
    await file.writeAsBytes(img.encodeJpg(flipped, quality: 90));
    return file;
  }

  Future<void> _takePhoto({bool auto = false}) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPhoto) {
      return;
    }
    // Une fois le temps écoulé, plus de capture manuelle.
    final alert = _alert;
    if (!auto && alert != null && (_expired || alert.isExpired())) {
      _goTooLate();
      return;
    }

    _timer?.cancel();
    _timer = null;
    setState(() => _isTakingPhoto = true);
    HapticFeedback.heavyImpact();

    final names = _names;
    try {
      final xFile = await controller.takePicture();
      // Une photo par alerte : consommée dès que la capture a eu lieu.
      await _consume();
      final photoFile = await _maybeFlip(File(xFile.path));
      final entry = await StorageService.savePhoto(
        photoFile: photoFile,
        personName: names,
      );

      // Upload synchronously so the photo is in the group feed when we navigate back.
      // The capture loading indicator stays visible during the upload.
      final uploaded = await StorageService.uploadToGroup(
        File(entry.localPath),
        names,
      );

      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultScreen(entry: entry, uploadedToGroup: uploaded),
          ),
        );
      }
    } catch (e) {
      // Capture ratée : l'alerte est quand même consommée (une seule chance).
      await _consume();
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          if (alert != null) _state = _AlertState.unavailable;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _consume() async {
    // L'alerte réellement utilisée (peut être plus récente que celle de la
    // notif tapée, si celle-ci a été remplacée).
    final id = _alert?.id ?? widget.alertId;
    if (id == null) return;
    try {
      await NotificationService.consumeAlert(id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) return CameraPreview(_controller!);

    // previewSize is landscape (width > height); invert for portrait
    final w = previewSize.height;
    final h = previewSize.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: w, height: h, child: CameraPreview(_controller!)),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _AlertState.loading:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      case _AlertState.unavailable:
        return const _InfoView(
          emoji: '📭',
          title: 'Plus de photo à prendre pour cette alerte',
        );
      case _AlertState.tooLate:
        return const _InfoView(
          emoji: '⏰',
          title: 'Trop tard ⏰',
          subtitle: 'Le temps est écoulé pour cette alerte.',
        );
      case _AlertState.ready:
        break;
    }

    if (_errorMessage != null) {
      return _ErrorView(message: _errorMessage!);
    }

    if (!_isInitialized || _controller == null) {
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
            child: _buildPreview(),
          ),
        ),

        // En-tête : prénom à capturer + compte à rebours
        Positioned(
          top: topPad + 12,
          left: 0,
          right: 0,
          child: _Header(
            personName: _names,
            countdownEnabled: _hasCountdown,
            remainingMs: _remainingMs,
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
                    onPressed:
                        (_isTakingPhoto || _expired) ? null : () => _takePhoto(),
                    isLoading: _isTakingPhoto,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: _cameras.length > 1
                    ? _FlipButton(
                        onPressed: (_isTakingPhoto || _expired)
                            ? null
                            : _flipCamera)
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
  final int remainingMs;

  const _Header({
    required this.personName,
    required this.countdownEnabled,
    required this.remainingMs,
  });

  /// « 45 s » sous la minute, sinon « m:ss ».
  static String _fmt(int ms) {
    final secs = ms <= 0 ? 0 : (ms / 1000).ceil();
    if (secs < 60) return '$secs s';
    final m = secs ~/ 60;
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final urgent = remainingMs <= 3000;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
          stops: const [0.0, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          const Text(
            'PRENDS VITE EN PHOTO',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            personName,
            textAlign: TextAlign.center,
            style: VTheme.grotesk(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              shadows: const [Shadow(blurRadius: 12, color: Colors.black87)],
            ),
          ),
          if (countdownEnabled) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: urgent ? Colors.red : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '⏱ ${_fmt(remainingMs)}',
                style: TextStyle(
                  color: urgent ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Écran simple (alerte indisponible / trop tard) avec un bouton retour.
class _InfoView extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;

  const _InfoView({required this.emoji, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: VTheme.grotesk(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
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
