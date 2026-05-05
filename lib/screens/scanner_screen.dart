import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:animate_do/animate_do.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../globals.dart';
import '../models/hero_model.dart';
import '../widgets/hero_card.dart';

class ARScannerScreen extends StatefulWidget {
  const ARScannerScreen({super.key});

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _showResult = false;
  HeroModel? _scannedHero;

  late AnimationController _animationController;
  late Animation<double> _scanLineAnimation;

  // ML Kit Text Recognition
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isBusy = false;
  int _missingFrames = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndInitCamera();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 250.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
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
      ResolutionPreset.high, // Resolusi tinggi agar teks lebih terbaca
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

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ===== PROSES FRAME KAMERA =====
  void _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }

      final recognizedText = await _textRecognizer.processImage(inputImage);
      final allText = recognizedText.text;

      if (allText.isNotEmpty) {
        debugPrint('OCR TEXT: $allText');
      }

      // Cari angka nominal koin di teks yang terbaca
      final hero = _matchCoinFromText(allText);

      if (hero != null && mounted) {
        _missingFrames = 0;
        setState(() {
          _scannedHero = hero;
          _showResult = true;
        });
      } else {
        _registerMissingFrame();
      }
    } catch (e) {
      debugPrint(e.toString());
    }

    _isBusy = false;
  }

  /// Cocokkan teks yang terbaca OCR dengan nominal koin
  HeroModel? _matchCoinFromText(String text) {
    if (text.isEmpty) return null;

    // Bersihkan teks: hapus spasi, titik, koma
    final cleaned = text.replaceAll(RegExp(r'[\s.,]'), '').toUpperCase();

    // Cek dari nominal terbesar ke terkecil agar "1000" tidak salah match "100"
    if (cleaned.contains('1000') || cleaned.contains('1.000')) {
      debugPrint('MATCHED: Rp 1.000');
      return mockHeroes[0];
    }
    if (cleaned.contains('500')) {
      debugPrint('MATCHED: Rp 500');
      return mockHeroes[1];
    }
    if (cleaned.contains('200')) {
      debugPrint('MATCHED: Rp 200');
      return mockHeroes[2];
    }
    if (cleaned.contains('100')) {
      debugPrint('MATCHED: Rp 100');
      return mockHeroes[3];
    }

    return null; // Tidak ada nominal yang cocok
  }

  void _registerMissingFrame() {
    _missingFrames++;
    // Hilangkan AR card jika teks tidak terbaca selama 15 frame
    if (_missingFrames > 15 && _showResult && mounted) {
      setState(() => _showResult = false);
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _controller?.stopImageStream();
    _controller?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ===== BUILD UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          if (_isCameraInitialized && _controller != null)
            _buildCameraPreview()
          else
            const Center(child: CircularProgressIndicator(color: Colors.cyan)),

          // 2. Scanner overlay (tampil saat belum ada hasil)
          if (!_showResult) _buildScannerUI(),

          // 3. AR Hero Card (tampil saat koin terbaca)
          if (_showResult && _scannedHero != null)
            Center(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ZoomIn(
                    duration: const Duration(milliseconds: 300),
                    child: HeroCard(hero: _scannedHero!),
                  ),
                ),
              ),
            ),

          // Tombol Back
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  Widget _buildScannerUI() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 48),
          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: Stack(
                children: [
                  _buildCorner(Alignment.topLeft),
                  _buildCorner(Alignment.topRight),
                  _buildCorner(Alignment.bottomLeft),
                  _buildCorner(Alignment.bottomRight),
                  AnimatedBuilder(
                    animation: _scanLineAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanLineAnimation.value,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.cyan,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyan.withOpacity(0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: Column(
              children: [
                const CircularProgressIndicator(
                    color: Colors.cyan, strokeWidth: 2),
                const SizedBox(height: 12),
                Text(
                  "Arahkan angka pada koin ke kamera...",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            top: (alignment == Alignment.topLeft ||
                    alignment == Alignment.topRight)
                ? const BorderSide(color: Colors.cyan, width: 4)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.cyan, width: 4)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft ||
                    alignment == Alignment.bottomLeft)
                ? const BorderSide(color: Colors.cyan, width: 4)
                : BorderSide.none,
            right: (alignment == Alignment.topRight ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.cyan, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
