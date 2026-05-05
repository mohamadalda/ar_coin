import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark blueish background
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Efek cahaya / Blob background
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyan.withOpacity(0.2),
                boxShadow: [
                  BoxShadow(color: Colors.cyan.withOpacity(0.5), blurRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.2),
                boxShadow: [
                  BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 80),
                ],
              ),
            ),
          ),
          
          // Konten Utama
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeInDown(
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    size: 100,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 20),
                FadeInDown(
                  delay: const Duration(milliseconds: 200),
                  child: Text(
                    "IMAGO",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.cyan.withOpacity(0.5), blurRadius: 10)],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeInDown(
                  delay: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: Text(
                      "Scan fisik uang koin Rupiah untuk melihat profil Pahlawan Nasional dalam format Augmented Reality.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60),
                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ARScannerScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.cyan, Colors.blue],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyan.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Text(
                            "Mulai Scan",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
