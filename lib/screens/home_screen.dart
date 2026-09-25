import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'scanner_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import '../utils/language_manager.dart';
import '../utils/auth_service.dart';

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
                color: const Color(0xFF6A0DAD).withValues(alpha: 0.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6A0DAD).withValues(alpha: 0.5), blurRadius: 100),
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
                color: const Color(0xFFD01B98).withValues(alpha: 0.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFD01B98).withValues(alpha: 0.4), blurRadius: 80),
                ],
              ),
            ),
          ),
          
          // Top controls: Language Dropdown and Login/Logout Button
          Positioned(
            top: 40,
            right: 20,
            child: Row(
              children: [
                // Language Dropdown
                ValueListenableBuilder<String>(
                  valueListenable: LanguageManager.currentLanguage,
                  builder: (context, currentLang, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentLang,
                          dropdownColor: const Color(0xFF1E293B),
                          icon: const Icon(Icons.language, color: Colors.white70, size: 18),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
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
                
                // Login/Logout Button
                ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isLoggedIn,
                  builder: (context, isLoggedIn, _) {
                    return GestureDetector(
                      onTap: () {
                        if (isLoggedIn) {
                          AuthService.logout();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Berhasil logout')),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isLoggedIn ? Colors.red.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: isLoggedIn ? Colors.red.withValues(alpha: 0.5) : Colors.white24),
                        ),
                        child: Icon(
                          isLoggedIn ? Icons.logout : Icons.person,
                          color: isLoggedIn ? Colors.redAccent : Colors.white70,
                          size: 20,
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),

          // Konten Utama
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeInDown(
                  child: Hero(
                    tag: 'logo',
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 150,
                      height: 150,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeInDown(
                  delay: const Duration(milliseconds: 200),
                  child: Text(
                    "IMAGO",
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.white,
                      shadows: [Shadow(color: const Color(0xFF6A0DAD).withValues(alpha: 0.5), blurRadius: 15)],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeInDown(
                  delay: const Duration(milliseconds: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: ValueListenableBuilder<String>(
                      valueListenable: LanguageManager.currentLanguage,
                      builder: (context, lang, _) {
                        return Text(
                          lang == 'id' 
                              ? "Scan fisik koin untuk melihat profil Tokoh dalam format Augmented Reality."
                              : (lang == 'en' ? "Scan coins to view Figures profiles in Augmented Reality format."
                              : "Scan coins to view figures in AR."), // Fallback sederhana, karena terjemahan UI statis tidak ikut API translation di mockHeroes
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        );
                      }
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
                          colors: [Color(0xFF6A0DAD), Color(0xFFD01B98)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6A0DAD).withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Text(
                            "MULAI SCAN",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Settings Button (Admin Only)
                ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isLoggedIn,
                  builder: (context, isLoggedIn, _) {
                    if (!isLoggedIn) return const SizedBox.shrink();
                    
                    return FadeInUp(
                      delay: const Duration(milliseconds: 700),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AdminScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.settings, color: Colors.white70, size: 20),
                              SizedBox(width: 10),
                              Text(
                                "PENGATURAN HERO",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.0,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

