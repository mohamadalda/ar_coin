import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'globals.dart';
import 'screens/home_screen.dart';
import 'models/hero_model.dart';
import 'utils/auth_service.dart';
import 'utils/file_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error: ${e.code}\nError Message: ${e.description}');
  }
  
  // Harus sebelum loadHeroes(): path berkas unggahan disimpan relatif dan
  // butuh folder dokumen aplikasi untuk bisa dibuka.
  await FileHelper.init();

  // Load heroes data from JSON
  await loadHeroes();

  // Initialize auth state
  await AuthService.init();
  
  runApp(const ARCoinApp());
}

class ARCoinApp extends StatelessWidget {
  const ARCoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Koin Pahlawan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6A0DAD),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A0DAD),
          primary: const Color(0xFF6A0DAD),
          secondary: const Color(0xFFD01B98),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: const HomeScreen(),
    );
  }
}
