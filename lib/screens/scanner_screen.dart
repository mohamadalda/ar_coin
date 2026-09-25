import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
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

  /// Ukuran panel yang benar-benar terukur setelah layout. Dipakai untuk
  /// menghitung titik sambung garis penghubung ke reticle; tanpa ini garisnya
  /// harus menebak tinggi panel yang berubah-ubah mengikuti panjang deskripsi.
  final GlobalKey _panelKey = GlobalKey();
  Size? _panelSize;

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
  /// Mengatur urutan kemunculan konten setelah objek terkunci. Dipisah dari
  /// _lockController (yang mengurus cincin bidik) karena durasinya jauh lebih
  /// panjang: di mode 'both', panel sengaja ditahan sampai model 3D tampil.
  late AnimationController _revealController;
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

    _revealController = AnimationController(
      duration: const Duration(milliseconds: 1500),
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

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || !mounted) return;

    // Panel hasil menetap sampai ditutup manual, jadi tidak ada gunanya terus
    // menjalankan inferensi. Menghentikannya di sini membebaskan CPU untuk
    // WebView yang merender model 3D. Preview kamera tetap hidup.
    if (_showResult) return;

    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds < 250) {
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

      // 1. Image labeling dulu. Objek seperti barong/rangda tidak punya teks,
      //    jadi menjalankan OCR lebih awal hanya menambah ratusan milidetik
      //    per frame untuk hasil yang sudah pasti kosong.
      if (_imageLabelerReady && _imageLabeler != null) {
        try {
          final labels = await _imageLabeler!.processImage(inputImage);
          // Urutkan supaya kandidat paling yakin diperiksa lebih dulu.
          labels.sort((a, b) => b.confidence.compareTo(a.confidence));
          hero = _matchCoinByImage(labels);
        } catch (e) {
          debugPrint('⚠️ Image labeling error (skipped): $e');
          _imageLabelerReady = false;
        }
      }

      // 2. Kalau gambarnya tidak dikenali, baru OCR untuk koin yang
      //    mengandalkan teks nominal / nama pahlawan.
      if (hero == null) {
        final recognizedText = await _textRecognizer.processImage(inputImage);
        hero = _matchCoinByText(recognizedText.text);
      }

      if (mounted) {
        if (hero != null) {
          _missingFrames = 0;
          if (_scannedHero == null || _scannedHero!.name['id'] != hero.name['id']) {
            setState(() {
              _scannedHero = hero;
              _showResult = true;
            });
            _lockController.forward(from: 0);
            _revealController.forward(from: 0);
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

  /// Ambang minimum confidence agar sebuah label dianggap sah.
  /// Model 3 kelas membagi confidence jauh lebih merata daripada model 2 kelas,
  /// sehingga 0.85 terlalu ketat dan membuat deteksi terasa lambat.
  static const double _kMinLabelConfidence = 0.70;

  /// Mencocokkan koin berdasarkan gambar (image labeling / classification)
  HeroModel? _matchCoinByImage(List<ImageLabel> labels) {
    for (final label in labels) {
      final labelText = label.label.trim().toLowerCase();
      debugPrint('🔍 Label: "$labelText" confidence=${label.confidence}');

      if (label.confidence < _kMinLabelConfidence) continue;
      if (labelText == 'background') continue;

      for (final hero in mockHeroes) {
        if (hero.label.isEmpty) continue;

        // Pencocokan HARUS persis. Sebelumnya dipakai substring, dan itu fatal
        // begitu model mengeluarkan label berupa angka: "0" ikut cocok dengan
        // "koin_1000" dan "2" dengan "koin_200".
        if (hero.label.toLowerCase() == labelText) {
          debugPrint('✅ Image match: ${hero.getName('id')}');
          return hero;
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
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inisialisasi posisi panel di tengah layar (sekali saja)
    if (!_panelPositionInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = MediaQuery.of(context).size;
        setState(() {
          // Ditaruh di bawah reticle, bukan di tengah layar. Sebelumnya panel
          // muncul persis menimpa objek yang sedang dipindai.
          _panelOffset = Offset(
            (size.width - 280) / 2,
            size.height / 2 + 110,
          );
          _panelPositionInitialized = true;
        });
      });
    }

    // Satu hero menampilkan SATU hal saja: model 3D atau kartu keterangan.
    final hero = _scannedHero;
    final show3d = _showResult &&
        hero != null &&
        hero.effectiveDisplayMode == HeroModel.displayBoth;
    final showPanel = _showResult && hero != null;

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

          // LAYER 1.5: Sapuan scanline, hanya saat masih mencari
          if (!_showResult)
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _rotateController,
                  builder: (_, __) => CustomPaint(
                    size: Size.infinite,
                    painter: _ScanlinePainter(progress: _rotateController.value),
                  ),
                ),
              ),
            ),

          // LAYER 2: AR targeting ring (tengah)
          _buildARTargeting(),

          // LAYER 2.2: Model 3D melayang tepat di titik bidik. Dirender oleh
          // <model-viewer> di dalam WebView transparan, jadi tidak butuh
          // ARCore dan tetap jalan di perangkat apa pun.
          if (show3d)
            Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: ModelViewer(
                  key: ValueKey(_scannedHero!.model),
                  // Path relatif tanpa skema. model_viewer_plus me-redirect
                  // src apa pun yang absolute (termasuk 'asset:///...') ke
                  // WebView, dan skema itu tidak dikenal browser sehingga
                  // modelnya gagal dimuat. Tanpa skema, ia dibaca rootBundle.
                  src: _scannedHero!.model,
                  alt: _scannedHero!.getName(
                      LanguageManager.currentLanguage.value),
                  autoRotate: true,
                  cameraControls: true,
                  disableZoom: true,
                  backgroundColor: Colors.transparent,
                  // Tombol AR bawaan model-viewer. Ia mendeteksi sendiri
                  // dukungan perangkat, jadi tombolnya otomatis tidak muncul
                  // di perangkat tanpa ARCore/ARKit.
                  ar: true,
                  arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                ),
              ),
            ),

          // LAYER 2.5: Garis penghubung reticle -> panel. Inilah yang membuat
          // panel terbaca sebagai label milik objek, bukan kartu yang melayang
          // lepas di atas video.
          if (showPanel && _panelPositionInitialized)
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation:
                      Listenable.merge([_rotateController, _revealController]),
                  builder: (_, __) => CustomPaint(
                    size: Size.infinite,
                    painter: _ARConnectorPainter(
                      panelOffset: _panelOffset,
                      panelSize: _panelSize ?? const Size(280, 200),
                      phase: _rotateController.value,
                      reveal: _panelReveal,
                    ),
                  ),
                ),
              ),
            ),

          // LAYER 3: Draggable info panel
          if (showPanel) _buildDraggablePanel(),


          // LAYER 4: Top HUD
          Column(
            children: [
              _buildHUD(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox();
    }

    // Sebelumnya dipakai SizedBox.expand, yang memaksa preview meregang
    // mengikuti rasio layar — itu penyebab gambarnya gepeng, karena rasio
    // sensor (mis. 4:3) hampir tidak pernah sama dengan rasio layar.
    // FittedBox.cover mempertahankan rasio asli dan memotong sisi yang lebih,
    // persis seperti aplikasi kamera bawaan.
    final screen = MediaQuery.of(context).size;
    final isLandscape = screen.width > screen.height;

    // aspectRatio dari controller selalu dalam orientasi sensor (landscape).
    // Saat layar portrait, CameraPreview memutar gambarnya sehingga rasio yang
    // terlihat menjadi kebalikannya.
    final previewRatio = controller.value.aspectRatio;
    final childHeight = isLandscape
        ? screen.width / previewRatio
        : screen.width * previewRatio;

    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: screen.width,
            height: childHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
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

  /// Progres kemunculan panel keterangan.
  /// Di mode 'both' panel ditahan sampai paruh kedua, supaya model 3D sempat
  /// tampil lebih dulu; di mode 'panel' ia langsung berjalan dari awal.
  double get _panelReveal {
    final staged =
        _scannedHero?.effectiveDisplayMode == HeroModel.displayBoth;
    const stagedInterval = Interval(0.6, 1.0, curve: Curves.easeOutCubic);
    const instantInterval = Interval(0.0, 0.4, curve: Curves.easeOutCubic);
    return (staged ? stagedInterval : instantInterval)
        .transform(_revealController.value);
  }

  // ===== DRAGGABLE INFO PANEL =====
  Widget _buildDraggablePanel() {
    final hero = _scannedHero!;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _panelKey.currentContext?.size;
      if (measured != null && measured != _panelSize && mounted) {
        setState(() => _panelSize = measured);
      }
    });

    return Positioned(
      left: _panelOffset.dx,
      top: _panelOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _panelOffset += details.delta;
          });
        },
        child: AnimatedBuilder(
          animation: _revealController,
          builder: (context, child) {
            // Panel tumbuh keluar dari reticle lalu mendarat di posisinya,
            // dengan kemiringan perspektif yang meluruh sampai rata. Berhenti
            // di 0 supaya teksnya tetap terbaca saat diam.
            final t = _panelReveal;
            if (t <= 0.0) return const SizedBox.shrink();
            final screen = MediaQuery.of(context).size;
            final panelCenter = _panelOffset +
                Offset(140, (_panelSize?.height ?? 200) / 2);
            final travel =
                (Offset(screen.width / 2, screen.height / 2) - panelCenter) *
                    (1 - t);

            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: travel,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(0.22 * (1 - t))
                    ..scale(0.75 + 0.25 * t),
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            key: _panelKey,
            width: 280,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E27).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF6A0DAD).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A0DAD).withValues(alpha: 0.15),
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
                        color: const Color(0xFF6A0DAD).withValues(alpha: 0.5),
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
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 16),
                      ),
                    ),
                  ],
                ),

                // Foto pahlawan (KLIK untuk audio). Disembunyikan di mode
                // '3D + keterangan' karena model 3D sudah mengambil perannya
                // sebagai visual utama; menampilkan keduanya cuma mengulang.
                if (hero.effectiveDisplayMode != HeroModel.displayBoth) ...[
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
                                  .withValues(alpha: 0.5),
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
                ] else if (hero.audio.isNotEmpty) ...[
                  // Foto itu juga merangkap tombol audio. Saat disembunyikan,
                  // audionya perlu jalan masuk sendiri. Ikon saja, tanpa teks,
                  // supaya tidak menambah string yang belum diterjemahkan.
                  GestureDetector(
                    onTap: () => _playHeroAudio(hero),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: _isPlayingAudio
                              ? Colors.greenAccent
                              : const Color(0xFFD01B98),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _isPlayingAudio
                            ? Icons.stop_rounded
                            : Icons.volume_up_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Badge nominal
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6A0DAD).withValues(alpha: 0.3),
                        const Color(0xFFD01B98).withValues(alpha: 0.2),
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
                        color: Colors.white.withValues(alpha: 0.7),
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
                        color: const Color(0xFFD01B98).withValues(alpha: 0.6),
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
                    color: Colors.black.withValues(alpha: 0.4),
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
                        ? const Color(0xFFD01B98).withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _showResult
                          ? const Color(0xFFD01B98).withValues(alpha: 0.5)
                          : const Color(0xFF6A0DAD).withValues(alpha: 0.4),
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
        ..color = const Color(0xFF6A0DAD).withValues(alpha: 0.15)
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
      ..color = const Color(0xFF6A0DAD).withValues(alpha: 0.5)
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
      ..color = const Color(0xFF6A0DAD).withValues(alpha: 0.4)
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
        ..color = const Color(0xFFD01B98).withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // Ring magenta solid
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFD01B98).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Ring luar tipis
    canvas.drawCircle(
      center,
      radius + 10,
      Paint()
        ..color = const Color(0xFF6A0DAD).withValues(alpha: 0.2)
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
      ..color = const Color(0xFFD01B98).withValues(alpha: 0.6)
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

// ===== GARIS PENGHUBUNG RETICLE -> PANEL =====
// Menarik garis dari titik bidik ke tepi panel terdekat, sehingga panel
// terbaca sebagai label yang menempel pada objek. Titik sambungnya dihitung
// ulang setiap panel digeser, jadi hubungan itu tetap terasa saat di-drag.
class _ARConnectorPainter extends CustomPainter {
  final Offset panelOffset;
  final Size panelSize;
  final double phase;
  final double reveal;

  _ARConnectorPainter({
    required this.panelOffset,
    required this.panelSize,
    required this.phase,
    required this.reveal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final target = Offset(size.width / 2, size.height / 2);
    final rect = panelOffset & panelSize;

    // Titik pada tepi panel yang paling dekat ke reticle.
    final anchor = Offset(
      target.dx.clamp(rect.left, rect.right),
      target.dy.clamp(rect.top, rect.bottom),
    );

    final t = Curves.easeOut.transform(reveal.clamp(0.0, 1.0));
    if (t <= 0.01) return;
    final end = Offset.lerp(target, anchor, t)!;
    if ((end - target).distance < 4) return;

    canvas.drawLine(
      target,
      end,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00D01B98), Color(0xCCD01B98)],
        ).createShader(Rect.fromPoints(target, end))
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Titik cahaya yang merayap sepanjang garis, memberi kesan data mengalir.
    final travel = Offset.lerp(target, end, (phase * 2) % 1.0)!;
    canvas.drawCircle(
      travel,
      2.5,
      Paint()..color = const Color(0xFFD01B98).withValues(alpha: 0.9),
    );

    // Simpul di tepi panel.
    canvas.drawCircle(
      end,
      4,
      Paint()
        ..color = const Color(0xFFD01B98).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ARConnectorPainter old) =>
      old.panelOffset != panelOffset ||
      old.panelSize != panelSize ||
      old.phase != phase ||
      old.reveal != reveal;
}

// ===== SAPUAN SCANLINE =====
// Pita tipis yang turun perlahan selama aplikasi masih mencari. Opasitasnya
// sengaja rendah supaya tidak mengganggu saat dipakai lama.
class _ScanlinePainter extends CustomPainter {
  final double progress;
  _ScanlinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const bandHeight = 160.0;
    final y = (progress * (size.height + bandHeight)) - bandHeight;
    final band = Rect.fromLTWH(0, y, size.width, bandHeight);

    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF6A0DAD).withValues(alpha: 0.0),
            const Color(0xFF6A0DAD).withValues(alpha: 0.10),
            const Color(0xFFD01B98).withValues(alpha: 0.16),
          ],
        ).createShader(band),
    );

    canvas.drawLine(
      Offset(0, y + bandHeight),
      Offset(size.width, y + bandHeight),
      Paint()
        ..color = const Color(0xFFD01B98).withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) =>
      old.progress != progress;
}
