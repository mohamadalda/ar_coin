import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
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

  /// Di mode '3D + keterangan', kartu keterangan tidak langsung muncul —
  /// ia menutupi asetnya. Baru tampil setelah tombol info ditekan.
  bool _panelExpanded = false;

  /// Menjadi true setelah <model-viewer> selesai memuat dan merender model.
  /// Tombol info menunggu ini supaya tidak muncul mendahului asetnya.
  bool _modelReady = false;
  HeroModel? _scannedHero;

  // Draggable panel position
  /// Geseran manual dari posisi dasarnya. Posisi dasar sendiri mengikuti koin,
  /// jadi yang disimpan adalah selisihnya — bukan koordinat absolut seperti
  /// dulu, yang membuat panel diam di tempat saat koin bergerak.
  Offset _panelDragDelta = Offset.zero;

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

  // Object detection dengan model TFLite kustom. Dipakai menggantikan image
  // labeling karena ia mengembalikan boundingBox selain label — tanpa itu
  // posisi objek tidak diketahui dan aset 3D terpaku di tengah layar.
  ObjectDetector? _objectDetector;
  bool _objectDetectorReady = false;

  /// Kotak objek terakhir, dalam koordinat gambar yang sudah tegak.
  Rect? _trackedRect;

  /// Ukuran gambar sumber setelah rotasi diterapkan. Dibutuhkan untuk
  /// memetakan _trackedRect ke koordinat layar.
  Size? _trackedSourceSize;


  bool _isBusy = false;
  int _missingFrames = 0;

  /// Masa tenggang sebelum overlay dilepas, dibedakan menurut penyebabnya.
  ///
  /// Kalau detektor sama sekali tidak menemukan objek, koin memang sudah keluar
  /// layar — lepas cepat. Kalau objeknya masih terlihat tapi label-nya meleset
  /// ('background'), itu cuma model yang ragu sesaat: tahan lebih lama, kalau
  /// tidak overlay akan berkedip-kedip. Pada throttle 250 ms, 2 frame ≈ 0,5 detik
  /// dan 8 frame ≈ 2 detik.
  /// Kendali sudut pandang model dikembalikan ke jari. Percobaan menggerakkannya
  /// dari sensor perangkat dibatalkan: sudut naik-turun diambil dari gravitasi,
  /// sedangkan memotret koin di meja berarti kamera menunduk — akibatnya model
  /// selalu tampak dari atas alias "tiduran".
  WebViewController? _modelWebView;

  /// Ukuran kotak render model dan ukuran layar terakhir. Disimpan di luar
  /// setState karena hanya dipakai saat mendorong ukuran ke WebView.
  Size? _lastScreenSize;
  double _modelSide = 300;

  /// Tinggi model 3D di layar, sebagai kelipatan tinggi kotak koin.
  /// Inilah yang membuat model ikut mengecil saat kamera dijauhkan dan
  /// membesar saat didekatkan.
  ///
  /// 1.0 = setinggi koin. Naikkan kalau ingin modelnya lebih besar dari koin
  /// (2.0 berarti dua kali tinggi koin).
  static const double _kModelHeightVsCoin = 1.0;

  /// Disuntikkan sekali ke halaman model-viewer. Menghitung sendiri faktor
  /// piksel-per-meter dari dimensi model dan field-of-view yang BENAR-BENAR
  /// dipakai saat render, lalu menyediakan setSize() untuk dipanggil dari Dart.
  ///
  /// setSize hanya menyentuh JARAK kamera dan mempertahankan sudut yang sedang
  /// dipegang pengguna — kalau ia ikut menulis sudut, ia akan berebut dengan
  /// jari yang sedang menggeser model.
  static const String _kLockJs = """
(function () {
  var mv = document.querySelector('model-viewer');
  if (!mv) return;
  var K = 0, pending = 0, t0 = performance.now();
  function calibrate() {
    try {
      var d = mv.getDimensions();
      var fov = mv.getFieldOfView() * Math.PI / 180;
      // radius_meter = K / tinggi_piksel_yang_diinginkan
      K = d.y * mv.clientHeight / (2 * Math.tan(fov / 2));
    } catch (e) { K = 0; }
  }
  function apply(px) {
    if (!K || !px) return;
    var o = mv.getCameraOrbit();
    var want = K / px;
    // Hanya tulis kalau ukurannya memang perlu berubah. Tanpa ambang ini,
    // tiap pembaruan menimpa sudut yang sedang digeser jari.
    if (!o.radius || Math.abs(want - o.radius) / o.radius < 0.02) return;
    mv.cameraOrbit = (o.theta * 180 / Math.PI).toFixed(1) + 'deg ' +
                     (o.phi * 180 / Math.PI).toFixed(1) + 'deg ' +
                     want.toFixed(2) + 'm';
  }
  mv.addEventListener('load', function () {
    calibrate();
    // Beri tahu Dart bahwa model sudah benar-benar siap tampil.
    try {
      if (window.ModelReady) {
        window.ModelReady.postMessage(String(Math.round(performance.now() - t0)));
      }
    } catch (e) {}
    // Permintaan ukuran yang tiba sebelum model selesai dimuat tidak boleh
    // hilang begitu saja — kalau hilang, model tampil di ukuran bawaan sampai
    // koin kebetulan bergerak lagi.
    if (pending) apply(pending);
  });
  window.addEventListener('resize', function () {
    calibrate();
    if (pending) apply(pending);
  });
  window.setSize = function (px) {
    pending = px;
    apply(px);
  };
})();
""";

  /// Jarak vertikal antara tepi bawah aset 3D dan tepi atas kartu keterangan,
  /// dalam piksel logis. Perbesar kalau kartunya masih terasa menutupi aset,
  /// perkecil kalau terlalu jauh terpisah.
  static const double _kPanelGapFromModel = 10.0;

  static const int _kFramesBeforeDropNoObject = 2;
  static const int _kFramesBeforeDropUnmatched = 8;
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
    _initObjectDetector();

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

  /// Inisialisasi object detector dengan custom TFLite model
  Future<void> _initObjectDetector() async {
    try {
      final modelPath = await _getModelPath('coin_model.tflite');
      final options = LocalObjectDetectorOptions(
        mode: DetectionMode.stream,
        modelPath: modelPath,
        classifyObjects: true,
        multipleObjects: false,
        confidenceThreshold: 0.5,
      );
      _objectDetector = ObjectDetector(options: options);
      _objectDetectorReady = true;
      debugPrint('✅ Object detector initialized');
    } catch (e) {
      debugPrint('❌ Object detector init error (OCR only mode): $e');
      _objectDetectorReady = false;
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

    final totalBytes =
        image.planes.fold(0, (sum, plane) => sum + plane.bytes.length);
    final bytes = Uint8List(totalBytes);
    int offset = 0;
    for (final plane in image.planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    // Konvensi koordinat kotak ML Kit BERBEDA antar platform. Di Android,
    // rotasi 90/270 membuat sumbu tertukar sehingga lebar/tinggi harus dibalik.
    // Di iOS tidak — ini mengikuti coordinates_translator.dart pada contoh
    // resmi google_mlkit, yang juga hanya membalik untuk Android.
    final swapAxes = !Platform.isIOS &&
        (rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg);
    final source = swapAxes
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    if (_trackedSourceSize != source) _trackedSourceSize = source;

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

    // Inferensi sengaja TIDAK dihentikan saat hasil tampil: aset 3D mengikuti
    // koin, jadi posisinya harus terus diperbarui. Ini memang lebih berat
    // daripada sebelumnya — throttle di bawah yang menahan biayanya.

    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!).inMilliseconds < 150) {
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

      // 1. Object detection dulu. Objek seperti barong/rangda tidak punya teks,
      //    jadi menjalankan OCR lebih awal hanya menambah ratusan milidetik
      //    per frame untuk hasil yang sudah pasti kosong.
      Rect? rect;
      var sawAnyObject = false;
      if (_objectDetectorReady && _objectDetector != null) {
        try {
          final objects = await _objectDetector!.processImage(inputImage);
          sawAnyObject = objects.isNotEmpty;
          for (final obj in objects) {
            final labels = [...obj.labels]
              ..sort((a, b) => b.confidence.compareTo(a.confidence));
            final match = _matchCoinByImage(labels);
            if (match != null) {
              hero = match;
              rect = obj.boundingBox;
              break;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Object detection error (skipped): $e');
          _objectDetectorReady = false;
        }
      }

      // 2. Kalau gambarnya tidak dikenali, baru OCR untuk koin yang
      //    mengandalkan teks nominal / nama pahlawan.
      if (hero == null) {
        final recognizedText = await _textRecognizer.processImage(inputImage);
        hero = _matchCoinByText(recognizedText.text);
      }

      if (mounted) {
        // Posisi diperbarui walau hero-nya sama, supaya aset 3D terus mengikuti.
        // Frame yang meleset (model mengembalikan 'background') SENGAJA tidak
        // menghapus kotak terakhir: mengosongkannya membuat anchor jatuh ke
        // tengah layar, dan aset terlihat melompat bolak-balik.
        if (rect != null) {
          // Dihaluskan di sumbernya, bukan lewat animasi widget yang panjang:
          // kotak dari detektor berderak antar-frame, tapi animasi widget
          // membuat model tertinggal di belakang koin.
          final prev = _trackedRect;
          final smoothed = prev == null
              ? rect
              : Rect.fromLTRB(
                  prev.left + (rect.left - prev.left) * 0.5,
                  prev.top + (rect.top - prev.top) * 0.5,
                  prev.right + (rect.right - prev.right) * 0.5,
                  prev.bottom + (rect.bottom - prev.bottom) * 0.5,
                );
          if (smoothed != _trackedRect) {
            setState(() => _trackedRect = smoothed);
            // Ukuran koin berubah -> jarak kamera 3D ikut disesuaikan.
            _pushSizeToModel();
          }
        }

        if (hero != null) {
          _missingFrames = 0;
          if (_scannedHero == null ||
              _scannedHero!.name['id'] != hero.name['id']) {
            setState(() {
              _scannedHero = hero;
              _showResult = true;
            });
            _lockController.forward(from: 0);
            _revealController.forward(from: 0);
            if (mounted) {
              debugPrint(
                  '✅ Image match (Skenario 1): ${hero.getName(LanguageManager.currentLanguage.value)}');
              _playHeroAudio(hero);
            }
          }
        } else {
          _missingFrames++;
          // Koin sudah lama tidak terlihat: seluruh overlay dilepas, bukan
          // hanya aset 3D. Menyisakan kartu keterangan yang mengambang tanpa
          // objek yang dijelaskannya tidak masuk akal di tampilan AR.
          final limit = sawAnyObject
              ? _kFramesBeforeDropUnmatched
              : _kFramesBeforeDropNoObject;
          if (_missingFrames >= limit && _showResult) {
            debugPrint('👋 Objek hilang, overlay dilepas');
            if (_isPlayingAudio) {
              await _audioPlayer.stop();
            }
            setState(() {
              _trackedRect = null;
              _showResult = false;
              _scannedHero = null;
              _isPlayingAudio = false;
              _panelDragDelta = Offset.zero;
              _panelExpanded = false;
            });
          }
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
  HeroModel? _matchCoinByImage(List<Label> labels) {
    for (final label in labels) {
      final labelText = label.text.trim().toLowerCase();
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
        await _audioPlayer.play(
            DeviceFileSource(FileHelper.resolve(hero.audio)));
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

  /// Tinggi model yang diinginkan di layar, dalam piksel logis.
  /// Diturunkan dari TINGGI kotak koin, bukan lebar atau diagonalnya: siluet
  /// model berubah lebar drastis saat theta berputar, sedangkan tingginya
  /// praktis tetap — memakai lebar akan membuat modelnya memompa membesar
  /// dan mengecil setiap kali perangkat diputar.
  /// Model yang dimuat ke WebView. Dipilih lebih awal — sebelum apa pun
  /// terdeteksi — supaya WebView sudah panas saat koin ditemukan.
  String? _lastWarmModel;

  String? get _warmModelPath {
    final hero = _scannedHero;
    if (hero != null && hero.model.isNotEmpty) {
      _lastWarmModel = hero.model;
      return hero.model;
    }
    // Bertahan pada model terakhir, bukan kembali ke model pertama. Mengganti
    // src berarti WebView memuat ulang dari nol — kalau ia mundur ke default
    // tiap overlay ditutup, memindai objek yang sama dua kali akan membayar
    // ongkos muat penuh untuk kedua kalinya.
    if (_lastWarmModel != null) return _lastWarmModel;
    for (final h in mockHeroes) {
      if (h.model.isNotEmpty) return _lastWarmModel = h.model;
    }
    return null;
  }

  double? _targetModelHeightPx() {
    final screen = _lastScreenSize;
    if (screen == null) return null;
    final r = _trackedRectOnScreen(screen);
    if (r == null) return null;
    return (r.height * _kModelHeightVsCoin).clamp(40.0, _modelSide * 0.95);
  }

  void _pushSizeToModel() {
    final controller = _modelWebView;
    final px = _targetModelHeightPx();
    if (controller == null || px == null) return;
    controller.runJavaScript(
      'window.setSize && window.setSize(${px.toStringAsFixed(1)});',
    );
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _objectDetector?.close();
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
    // Satu hero menampilkan SATU hal saja: model 3D atau kartu keterangan.
    final hero = _scannedHero;
    final screen = MediaQuery.of(context).size;
    final trackedOnScreen = _trackedRectOnScreen(screen);
    final anchor =
        trackedOnScreen?.center ?? Offset(screen.width / 2, screen.height / 2);
    // Kotak render TETAP. Mengubah ukuran platform view tiap frame memaksa
    // WebView relayout dan model-viewer membingkai ulang — jauh lebih mahal
    // daripada sekadar mengubah jarak kamera 3D di dalamnya.
    final modelSide = math.min(screen.shortestSide * 0.95, 560.0);
    _lastScreenSize = screen;
    _modelSide = modelSide;

    // Aset 3D menempel pada koin, jadi ia hanya masuk akal selama posisinya
    // diketahui. Begitu pelacakan lepas lebih dari masa tenggang, seluruh
    // overlay dilepas di _processCameraImage — termasuk kartu keterangan.
    final warmModel = _warmModelPath;
    // Tinggi model yang benar-benar terlihat. Berbeda jauh dari modelSide,
    // yaitu kotak WebView yang tetap besar — memposisikan apa pun terhadap
    // kotak itu membuat semuanya terasa jauh dari asetnya.
    final modelPx = _targetModelHeightPx() ?? 120.0;
    final show3d = _showResult &&
        hero != null &&
        hero.effectiveDisplayMode == HeroModel.displayBoth &&
        trackedOnScreen != null;
    // Di mode 3D, kartu menunggu tombol info. Di mode 'Keterangan saja',
    // kartu itulah satu-satunya isi, jadi langsung tampil.
    final showPanel =
        _showResult && hero != null && (!show3d || _panelExpanded);
    final showInfoButton = show3d && _modelReady && !_panelExpanded;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // LAYER 1: Camera
          if (_isCameraInitialized && _controller != null)
            _buildCamera()
          else
            const Center(
                child: CircularProgressIndicator(color: Color(0xFF6A0DAD))),

          // LAYER 1.5: Sapuan scanline, hanya saat masih mencari
          if (!_showResult)
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _rotateController,
                  builder: (_, __) => CustomPaint(
                    size: Size.infinite,
                    painter:
                        _ScanlinePainter(progress: _rotateController.value),
                  ),
                ),
              ),
            ),

          // LAYER 2: Cincin bidik, menempel pada koin yang terlacak
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            left: anchor.dx - 100,
            top: anchor.dy - 100,
            width: 200,
            height: 200,
            child: _buildARTargeting(),
          ),

          // LAYER 2.2: Model 3D melayang tepat di titik bidik. Dirender oleh
          // <model-viewer> di dalam WebView transparan, jadi tidak butuh
          // ARCore dan tetap jalan di perangkat apa pun.
          // Dipasang sejak layar dibuka dan TIDAK pernah dibongkar saat aset
          // disembunyikan. Membongkarnya berarti WebView, mesin render 3D
          // (956 KB) dan berkas GLB (882 KB) harus dimuat ulang dari nol setiap
          // kali koin terdeteksi — itulah penyebab aset lama keluarnya.
          if (warmModel != null)
            AnimatedPositioned(
              // Dipersingkat dari 260 ms: dengan easing panjang, model berenang
              // menyusul koin seperempat detik kemudian alih-alih menempel.
              duration: const Duration(milliseconds: 110),
              curve: Curves.linear,
              left: anchor.dx - modelSide / 2,
              top: anchor.dy - modelSide / 2,
              width: modelSide,
              height: modelSide,
              child: IgnorePointer(
                ignoring: !show3d,
                // Opacity, bukan Offstage: Offstage melayout anaknya dengan
                // ukuran nol, sehingga clientHeight jadi 0 dan kalibrasi
                // piksel-per-meter di dalam JS ikut rusak.
                child: Opacity(
                  // BUKAN 0.0: RenderOpacity melewati pelukisan sepenuhnya
                  // saat alpha nol, sehingga WebView tidak pernah dirender dan
                  // "pemanasan" ini tidak memanaskan apa pun. 0.004 membulat
                  // ke alpha 1 — kasatmata tidak terlihat, tapi tetap dilukis.
                  opacity: show3d ? 1.0 : 0.004,
                  child: SizedBox(
                width: modelSide,
                height: modelSide,
                child: ModelViewer(
                  key: ValueKey(warmModel),
                  // Path relatif tanpa skema. model_viewer_plus me-redirect
                  // src apa pun yang absolute (termasuk 'asset:///...') ke
                  // WebView, dan skema itu tidak dikenal browser sehingga
                  // modelnya gagal dimuat. Tanpa skema, ia dibaca rootBundle.
                  // Berkas dari penyimpanan perangkat harus memakai skema
                  // file:// — tanpa itu model_viewer_plus mencarinya di dalam
                  // rootBundle dan gagal. Aset bawaan tetap path relatif.
                  src: FileHelper.isLocalFile(warmModel)
                      ? Uri.file(FileHelper.resolve(warmModel)).toString()
                      : warmModel,
                  alt: hero?.getName(LanguageManager.currentLanguage.value) ??
                      'Model 3D',
                  // Tanpa ini, GLB beranimasi tampil diam di pose awalnya.
                  autoPlay: true,
                  // Muat segera, jangan tunggu terlihat — justru itu intinya.
                  loading: Loading.eager,
                  // Diputar dengan jari. autoRotate tetap mati supaya model
                  // diam sampai pengguna sendiri yang menggesernya.
                  autoRotate: false,
                  cameraControls: true,
                  disableZoom: true,
                  disablePan: true,
                  disableTap: true,
                  interactionPrompt: InteractionPrompt.none,
                  // Batas orbit bawaan model-viewer mengunci radius ke rentang
                  // sempit dengan 105% sebagai PLAFON — artinya model hanya bisa
                  // mengecil, tidak pernah membesar. Tanpa membuka batas ini,
                  // penguncian ukuran ke koin mustahil. Satuan meter dipakai
                  // supaya lepas dari persentase yang basisnya berbeda-beda.
                  // phi dikunci di kisaran tegak (75°-95°) supaya model tidak
                  // bisa direbahkan jadi tampak-atas. Geseran jari praktis
                  // tinggal kiri-kanan saja.
                  minCameraOrbit: 'auto 75deg 5m',
                  maxCameraOrbit: 'auto 95deg 120m',
                  cameraOrbit: '0deg 75deg 105%',
                  interpolationDecay: 25,
                  relatedJs: _kLockJs,
                  // Bilah progres bawaan model-viewer digambar di tepi atas
                  // elemennya selebar penuh. Karena kotak WebView hampir
                  // selebar layar, ia tampak sebagai garis panjang melintang
                  // di atas aset.
                  relatedCss: 'model-viewer::part(default-progress-bar)'
                      '{display:none !important;}',
                  backgroundColor: Colors.transparent,
                  onWebViewCreated: (controller) {
                    _modelWebView = controller;
                    // Model berganti berarti memuat dari nol lagi; tombol info
                    // harus menunggu sinyal siap yang baru.
                    if (_modelReady) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _modelReady = false);
                      });
                    }
                  },
                  javascriptChannels: {
                    JavascriptChannel('ModelReady',
                        onMessageReceived: (msg) {
                      debugPrint('⏱️ Model 3D siap dalam ${msg.message} ms '
                          'sejak halaman model-viewer dimuat');
                      if (mounted && !_modelReady) {
                        setState(() => _modelReady = true);
                      }
                    }),
                  },
                  // Tombol AR bawaan model-viewer. Ia mendeteksi sendiri
                  // dukungan perangkat, jadi tombolnya otomatis tidak muncul
                  // di perangkat tanpa ARCore/ARKit.
                  ar: true,
                  arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                    ),
                  ),
                ),
              ),
            ),

          // Tombol info di bawah aset, sejajar tengah, dan baru muncul setelah
          // modelnya benar-benar siap — bukan mendahuluinya. Ia menghilang saat
          // kartu dibuka, jadi keduanya tidak pernah bertumpuk.
          if (showInfoButton)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 110),
              curve: Curves.linear,
              left: anchor.dx - 22,
              top: anchor.dy + modelPx / 2 + 10,
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () {
                  setState(() => _panelExpanded = true);
                  _revealController.forward(from: 0);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E27).withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFFD01B98), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6A0DAD).withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.info_outline,
                      color: Colors.white, size: 20),
                ),
              ),
            ),

          // LAYER 3: Draggable info panel
          if (showPanel) _buildDraggablePanel(anchor, screen, modelPx),

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
    final childHeight =
        isLandscape ? screen.width / previewRatio : screen.width * previewRatio;

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

  /// Memetakan kotak objek dari koordinat gambar ke koordinat layar.
  /// Harus memakai aturan yang sama dengan _buildCamera(): gambar tegak
  /// di-cover ke layar, sisi yang berlebih dipotong dan sisanya ditengahkan.
  Rect? _trackedRectOnScreen(Size screen) {
    final rect = _trackedRect;
    final src = _trackedSourceSize;
    if (rect == null || src == null || src.isEmpty) return null;

    final scale =
        math.max(screen.width / src.width, screen.height / src.height);
    final dx = (screen.width - src.width * scale) / 2;
    final dy = (screen.height - src.height * scale) / 2;

    return Rect.fromLTRB(
      rect.left * scale + dx,
      rect.top * scale + dy,
      rect.right * scale + dx,
      rect.bottom * scale + dy,
    );
  }

  /// Progres kemunculan panel keterangan.
  /// Di mode 'both' panel ditahan sampai paruh kedua, supaya model 3D sempat
  /// tampil lebih dulu; di mode 'panel' ia langsung berjalan dari awal.
  double get _panelReveal {
    // Dulu di mode 3D kemunculannya ditunda agar aset sempat tampil lebih dulu.
    // Penundaan itu tidak diperlukan lagi: kartunya kini dibuka manual lewat
    // tombol info, jadi begitu diminta ia harus langsung naik.
    const interval = Interval(0.0, 0.4, curve: Curves.easeOutCubic);
    return interval.transform(_revealController.value);
  }

  // ===== DRAGGABLE INFO PANEL =====
  Widget _buildDraggablePanel(Offset anchor, Size screen, double modelPx) {
    final hero = _scannedHero!;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measured = _panelKey.currentContext?.size;
      if (measured != null && measured != _panelSize && mounted) {
        setState(() => _panelSize = measured);
      }
    });

    final panelSize = _panelSize ?? const Size(280, 200);
    // Posisi dasar: di bawah aset 3D, ditambah geseran manual pengguna.
    // Sengaja TIDAK di-clamp ke tepi layar: menahannya di tepi membuat kartu
    // lepas dari koin dan terlihat palsu. Lebih baik ikut bergeser keluar dan
    // terpotong, seperti benda yang benar-benar menempel pada objeknya.
    final left = anchor.dx - panelSize.width / 2 + _panelDragDelta.dx;
    final top =
        anchor.dy + modelPx / 2 + _kPanelGapFromModel + _panelDragDelta.dy;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _panelDragDelta += details.delta;
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
            final panelCenter =
                Offset(left + panelSize.width / 2, top + panelSize.height / 2);
            final travel = (anchor - panelCenter) * (1 - t);

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
                    const SizedBox(
                        width: 24), // Placeholder untuk balance layout
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
                        // Di mode 3D, menutup kartu berarti kembali ke tombol
                        // info — asetnya tetap terkunci pada koin. Di mode
                        // 'Keterangan saja', kartu itu satu-satunya isi,
                        // sehingga menutupnya membubarkan overlay.
                        if (hero.effectiveDisplayMode ==
                            HeroModel.displayBoth) {
                          setState(() {
                            _panelExpanded = false;
                            _panelDragDelta = Offset.zero;
                          });
                          return;
                        }
                        setState(() {
                          _showResult = false;
                          _scannedHero = null;
                          _trackedRect = null;
                          _panelDragDelta = Offset.zero;
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
                        child: const Icon(Icons.close,
                            color: Colors.white70, size: 16),
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
                              color: _isPlayingAudio
                                  ? Colors.greenAccent
                                  : const Color(0xFF6A0DAD),
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
                                    File(FileHelper.resolve(hero.image)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
                      }),
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
                    }),
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
                    }),

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
                    }),
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
                        icon: const Icon(Icons.language,
                            color: Colors.white70, size: 16),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
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
                }),
            const SizedBox(width: 12),
            // Status indicator
            ValueListenableBuilder<String>(
                valueListenable: LanguageManager.currentLanguage,
                builder: (context, currentLang, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              ? (currentLang == 'id'
                                  ? "Terdeteksi"
                                  : "Detected")
                              : (currentLang == 'id'
                                  ? "Scanning..."
                                  : "Scanning..."),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
      Offset(
          p.dx + len * cos(angle + pi / 4), p.dy + len * sin(angle + pi / 4)),
      paint,
    );
    canvas.drawLine(
      p,
      Offset(
          p.dx + len * cos(angle - pi / 4), p.dy + len * sin(angle - pi / 4)),
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
