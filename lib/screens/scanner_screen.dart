import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:permission_handler/permission_handler.dart';
import '../globals.dart';
import '../models/hero_model.dart';
import '../utils/file_helper.dart';
import '../utils/language_manager.dart';

class ARScannerScreen extends StatefulWidget {
  const ARScannerScreen({super.key});

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _showResult = false;
  HeroModel? _scannedHero;

  // Draggable panel position
  Offset _panelOffset = Offset.zero;
  bool _panelPositionInitialized = false;

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;

  // OCR (text recognition)
  final TextRecognizer _textRecognizer = TextRecognizer();

  // Image labeling (untuk koin bergambar seperti Semar)
  ImageLabeler? _imageLabeler;
  bool _imageLabelerReady = false;

  bool _isBusy = false;
  int _missingFrames = 0;
  DateTime? _lastProcessedTime;

  // Animasi
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _lockController;
  late Animation<double> _lockScale;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndInitCamera();
    _initImageLabeler();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _lockController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _lockScale = Tween<double>(begin: 1.5, end: 1.0).animate(
      CurvedAnimation(parent: _lockController, curve: Curves.elasticOut),
    );
  }

  /// Salin model TFLite dari assets ke temp directory (selalu overwrite untuk mencegah cache lama)
  Future<String> _getModelPath(String assetFileName) async {
    final file = File('${Directory.systemTemp.path}/$assetFileName');
    // Selalu overwrite file lama di cache temp
    if (await file.exists()) {
      await file.delete();
    }
    final byteData = await rootBundle.load('assets/$assetFileName');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file.path;
  }

  /// Inisialisasi image labeler dengan custom TFLite model
  Future<void> _initImageLabeler() async {
    try {
      final modelPath = await _getModelPath('coin_model.tflite');
      final options = LocalLabelerOptions(
        modelPath: modelPath,
        confidenceThreshold: 0.5,
      );
      _imageLabeler = ImageLabeler(options: options);
      _imageLabelerReady = true;
      debugPrint('✅ Image labeler initialized');
    } catch (e) {
      debugPrint('❌ Image labeler init error (OCR only mode): $e');
      _imageLabelerReady = false;
    }
  }

  Future<void> _requestPermissionAndInitCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _initCamera();
    } else {
      debugPrint("Camera permission denied");
    }
  }

  void _initCamera() {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controller?.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
      _controller?.startImageStream(_processCameraImage);
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera = cameras[0];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rc = 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rc = (sensorOrientation + rc) % 360;
      } else {
        rc = (sensorOrientation - rc + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rc);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final totalBytes = image.planes.fold(0, (sum, plane) => sum + plane.bytes.length);
    final bytes = Uint8List(totalBytes);
    int offset = 0;
    for (final plane in image.planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  String _debugLabel = '';

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || !mounted) return;

    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds < 500) {
      return;
    }

    _isBusy = true;
    _lastProcessedTime = now;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }

      HeroModel? hero;
      String currentDebug = '';

      // 1. Coba OCR dulu
      final recognizedText = await _textRecognizer.processImage(inputImage);
      hero = _matchCoinByText(recognizedText.text);

      // 2. Jika OCR gagal, coba Image Labeling (untuk koin bergambar)
      if (hero == null && _imageLabelerReady && _imageLabeler != null) {
        try {
          final labels = await _imageLabeler!.processImage(inputImage);
          if (labels.isNotEmpty) {
            // Simpan label tertinggi untuk debug UI
            labels.sort((a, b) => b.confidence.compareTo(a.confidence));
            currentDebug = '${labels.first.label} (${(labels.first.confidence * 100).toStringAsFixed(0)}%)';
          }
          hero = _matchCoinByImage(labels);
        } catch (e) {
          debugPrint('⚠️ Image labeling error (skipped): $e');
          _imageLabelerReady = false;
        }
      }

      if (mounted) {
        if (currentDebug.isNotEmpty && _debugLabel != currentDebug) {
          setState(() => _debugLabel = currentDebug);
        }

        if (hero != null) {
          _missingFrames = 0;
          if (_scannedHero == null || _scannedHero!.name['id'] != hero.name['id']) {
            setState(() {
              _scannedHero = hero;
              _showResult = true;
            });
            _lockController.forward(from: 0);
            if (mounted) {
              debugPrint('✅ Image match (Skenario 1): ${hero.getName(LanguageManager.currentLanguage.value)}');
              _playHeroAudio(hero);
            }
          }
        } else {
          _missingFrames++;
          // AR panel now persists until user manually closes it.
        }
      }
    } catch (e) {
      debugPrint("❌ Detection Error: $e");
    } finally {
      _isBusy = false;
    }
  }

  /// Mencocokkan koin berdasarkan teks (OCR)
  HeroModel? _matchCoinByText(String text) {
    if (text.isEmpty) return null;
    final cleaned = text.replaceAll(RegExp(r'[\s.,]'), '').toUpperCase();
    HeroModel? bestMatch;
    int bestLen = 0;

    for (final hero in mockHeroes) {
      for (final keyword in hero.keywords) {
        if (cleaned.contains(keyword) && keyword.length > bestLen) {
          bestMatch = hero;
          bestLen = keyword.length;
        }
      }
    }
    return bestMatch;
  }

  /// Mencocokkan koin berdasarkan gambar (image labeling / classification)
  HeroModel? _matchCoinByImage(List<ImageLabel> labels) {
    if (labels.isEmpty) {
      debugPrint('🔍 No labels detected by Image Labeler');
    }
    
    for (final label in labels) {
      debugPrint('🔍 Label: "${label.label}" confidence=${label.confidence}');
      final labelText = label.label.trim().toLowerCase();
      
      // Threshold dinaikkan ke 0.85 (85%) untuk menghindari "salah deteksi"
      // Jika koin lain terdeteksi sebagai Semar, berarti confidence modelnya kurang dari 85%, atau model salah mengenali.
      if (label.confidence >= 0.85) {
        
        // Cek jika label adalah 'background' atau 'class 2' (sering digunakan sbg background di TM)
        if (labelText.contains('background') || labelText == '1' || labelText == 'class 2') {
          continue; // Abaikan background
        }

        for (final hero in mockHeroes) {
          if (hero.label.isEmpty) continue;
          final heroLabel = hero.label.toLowerCase();
          
          // Skenario 1: Metadata benar
          if (labelText.contains(heroLabel) || heroLabel.contains(labelText)) {
            debugPrint('✅ Image match (Skenario 1): ${hero.getName('id')}');
            return hero;
          }
          
          // Skenario 2: Index TFLite (0) atau default class (class 1)
          if ((labelText == '0' || labelText == 'class 1') && heroLabel == 'semar') {
            debugPrint('✅ Image match (Skenario 2/Fallback): ${hero.getName('id')}');
            return hero;
          }
        }
      }
    }
    return null;
  }

  /// Putar audio saat gambar diklik
  Future<void> _playHeroAudio(HeroModel hero) async {
    if (hero.audio.isEmpty) return;
    try {
      if (_isPlayingAudio) {
        await _audioPlayer.stop();
        setState(() => _isPlayingAudio = false);
        return;
      }
      if (FileHelper.isLocalFile(hero.audio)) {
        await _audioPlayer.play(DeviceFileSource(hero.audio));
      } else {
        await _audioPlayer.play(AssetSource(hero.audio));
      }
      setState(() => _isPlayingAudio = true);
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlayingAudio = false);
      });
    } catch (e) {
      debugPrint('❌ Audio error: $e');
      setState(() => _isPlayingAudio = false);
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _imageLabeler?.close();
    _audioPlayer.dispose();
    _controller?.stopImageStream();
    _controller?.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    _lockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inisialisasi posisi panel di tengah layar (sekali saja)
    if (!_panelPositionInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = MediaQuery.of(context).size;
        setState(() {
          _panelOffset = Offset(
            (size.width - 300) / 2, // Lebar panel ~300
            (size.height - 200) / 2, // Tinggi panel ~200
          );
          _panelPositionInitialized = true;
        });
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // LAYER 1: Camera
          if (_isCameraInitialized && _controller != null)
            _buildCamera()
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF6A0DAD))),

          // LAYER 2: AR targeting ring (tengah)
          _buildARTargeting(),

          // LAYER 3: Draggable info panel
          if (_showResult && _scannedHero != null) _buildDraggablePanel(),

          // LAYER 4: Top HUD
          Column(
            children: [
              _buildHUD(),
              if (!_showResult && _debugLabel.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AI sees: $_debugLabel',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox();
    }
    return SizedBox.expand(
      child: CameraPreview(_controller!),
    );
  }

  // ===== AR TARGETING (ring di tengah) =====
  Widget _buildARTargeting() {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [_pulseController, _rotateController, _lockController]),
        builder: (context, _) {
          final pulseVal =
              Tween<double>(begin: 0.85, end: 1.15).evaluate(_pulseController);
          final rotateVal = _rotateController.value * 2 * pi;

          if (_showResult) {
            return Transform.scale(
              scale: _lockScale.value,
              child: SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(
                  painter: _LockedRingPainter(rotation: rotateVal),
                ),
              ),
            );
          } else {
            return Transform.scale(
              scale: pulseVal,
              child: Transform.rotate(
                angle: rotateVal,
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _ScanRingPainter(progress: rotateVal),
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // ===== DRAGGABLE INFO PANEL =====
  Widget _buildDraggablePanel() {
    final hero = _scannedHero!;
    return Positioned(
      left: _panelOffset.dx,
      top: _panelOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _panelOffset += details.delta;
          });
        },
        child: FadeInUp(
          duration: const Duration(milliseconds: 400),
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E27).withOpacity(0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF6A0DAD).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A0DAD).withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle & Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 24), // Placeholder untuk balance layout
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A0DAD).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showResult = false;
                          _scannedHero = null;
                        });
                        if (_isPlayingAudio) {
                          _audioPlayer.stop();
                          setState(() => _isPlayingAudio = false);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 16),
                      ),
                    ),
                  ],
                ),

                // Foto pahlawan (KLIK untuk audio)
                GestureDetector(
                  onTap: () => _playHeroAudio(hero),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isPlayingAudio ? Colors.greenAccent : const Color(0xFF6A0DAD),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_isPlayingAudio
                                      ? Colors.greenAccent
                                      : const Color(0xFF6A0DAD))
                                  .withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: FileHelper.isLocalFile(hero.image)
                              ? Image.file(
                                  File(hero.image),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.blueGrey[900],
                                    child: const Icon(Icons.person,
                                        size: 40, color: Colors.grey),
                                  ),
                                )
                              : Image.asset(
                                  hero.image,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.blueGrey[900],
                                    child: const Icon(Icons.person,
                                        size: 40, color: Colors.grey),
                                  ),
                                ),
                        ),
                      ),
                      // Ikon audio overlay
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _isPlayingAudio
                                ? Colors.greenAccent
                                : const Color(0xFFD01B98),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlayingAudio
                                ? Icons.stop_rounded
                                : Icons.volume_up_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Badge nominal
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6A0DAD).withOpacity(0.3),
                        const Color(0xFFD01B98).withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ValueListenableBuilder<String>(
                    valueListenable: LanguageManager.currentLanguage,
                    builder: (context, lang, _) {
                      return Text(
                        hero.getCoin(lang),
                        style: const TextStyle(
                          color: Color(0xFFD01B98),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }
                  ),
                ),
                const SizedBox(height: 6),

                // Nama
                ValueListenableBuilder<String>(
                  valueListenable: LanguageManager.currentLanguage,
                  builder: (context, lang, _) {
                    return Text(
                      hero.getName(lang),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                ),
                const SizedBox(height: 4),

                // Deskripsi
                ValueListenableBuilder<String>(
                  valueListenable: LanguageManager.currentLanguage,
                  builder: (context, lang, _) {
                    return Text(
                      hero.getDescription(lang),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    );
                  }
                ),

                // Hint: klik untuk audio
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: LanguageManager.currentLanguage,
                  builder: (context, lang, _) {
                    return Text(
                      lang == 'id'
                          ? '🔊 Ketuk gambar untuk mendengar'
                          : '🔊 Tap image to listen',
                      style: TextStyle(
                        color: const Color(0xFFD01B98).withOpacity(0.6),
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== HUD (top bar) =====
  Widget _buildHUD() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // Language Switcher
            ValueListenableBuilder<String>(
              valueListenable: LanguageManager.currentLanguage,
              builder: (context, currentLang, _) {
                return Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentLang,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(Icons.language, color: Colors.white70, size: 16),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: LanguageManager.supportedLanguages.map((lang) {
                        return DropdownMenuItem<String>(
                          value: lang['code'],
                          child: Text(lang['name']!),
                        );
                      }).toList(),
                      onChanged: (newLang) {
                        if (newLang != null) {
                          LanguageManager.changeLanguage(newLang, context);
                        }
                      },
                    ),
                  ),
                );
              }
            ),
            const SizedBox(width: 12),
            // Status indicator
            ValueListenableBuilder<String>(
              valueListenable: LanguageManager.currentLanguage,
              builder: (context, currentLang, _) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showResult
                        ? const Color(0xFFD01B98).withOpacity(0.6)
                        : Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _showResult
                          ? const Color(0xFFD01B98).withOpacity(0.5)
                          : const Color(0xFF6A0DAD).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showResult ? Icons.check_circle : Icons.view_in_ar,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showResult
                            ? (currentLang == 'id' ? "Terdeteksi" : "Detected")
                            : (currentLang == 'id' ? "Scanning..." : "Scanning..."),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  // ===== End HUD =====
}

// ===== SCAN RING PAINTER (saat belum mendeteksi) =====
class _ScanRingPainter extends CustomPainter {
  final double progress;
  _ScanRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Outer ring tipis
    canvas.drawCircle(
      center,
      radius + 8,
      Paint()
        ..color = const Color(0xFF6A0DAD).withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Arc segment utama
    final arcPaint = Paint()
      ..color = const Color(0xFFD01B98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, progress, pi * 0.6, false, arcPaint);
    canvas.drawArc(rect, progress + pi, pi * 0.4, false, arcPaint);

    // Crosshair kecil di tengah
    final crossPaint = Paint()
      ..color = const Color(0xFF6A0DAD).withOpacity(0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - 10, center.dy),
        Offset(center.dx + 10, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 10),
        Offset(center.dx, center.dy + 10), crossPaint);

    // 4 corner brackets
    _drawCorner(canvas, center, radius, 0);
    _drawCorner(canvas, center, radius, pi / 2);
    _drawCorner(canvas, center, radius, pi);
    _drawCorner(canvas, center, radius, 3 * pi / 2);
  }

  void _drawCorner(Canvas canvas, Offset center, double radius, double angle) {
    const len = 12.0;
    final paint = Paint()
      ..color = const Color(0xFF6A0DAD).withOpacity(0.4)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final p = Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );

    canvas.drawLine(
      p,
      Offset(p.dx + len * cos(angle + pi / 4), p.dy + len * sin(angle + pi / 4)),
      paint,
    );
    canvas.drawLine(
      p,
      Offset(p.dx + len * cos(angle - pi / 4), p.dy + len * sin(angle - pi / 4)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanRingPainter old) => true;
}

// ===== LOCKED RING PAINTER (saat terdeteksi) =====
class _LockedRingPainter extends CustomPainter {
  final double rotation;
  _LockedRingPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Glow circle
    canvas.drawCircle(
      center,
      radius - 5,
      Paint()
        ..color = const Color(0xFFD01B98).withOpacity(0.08)
        ..style = PaintingStyle.fill,
    );

    // Ring magenta solid
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFD01B98).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Ring luar tipis
    canvas.drawCircle(
      center,
      radius + 10,
      Paint()
        ..color = const Color(0xFF6A0DAD).withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Rotating accent arc
    final arcPaint = Paint()
      ..color = const Color(0xFFD01B98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius + 10);
    canvas.drawArc(rect, rotation, pi / 3, false, arcPaint);

    // Crosshair
    final crossPaint = Paint()
      ..color = const Color(0xFFD01B98).withOpacity(0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - 15, center.dy),
        Offset(center.dx - 5, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx + 5, center.dy),
        Offset(center.dx + 15, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 15),
        Offset(center.dx, center.dy - 5), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy + 5),
        Offset(center.dx, center.dy + 15), crossPaint);

    // Center dot
    canvas.drawCircle(
      center,
      3,
      Paint()..color = const Color(0xFFD01B98),
    );
  }

  @override
  bool shouldRepaint(covariant _LockedRingPainter old) => true;
}
