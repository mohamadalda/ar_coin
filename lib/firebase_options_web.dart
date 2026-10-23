import 'package:firebase_core/firebase_core.dart';

/// Konfigurasi Firebase KHUSUS WEB.
///
/// Android dan iOS tidak membaca berkas ini sama sekali: keduanya tetap memakai
/// `google-services.json` / `GoogleService-Info.plist` lewat
/// `Firebase.initializeApp()` tanpa argumen, persis seperti sebelum port web
/// ini ada. Jadi mengubah berkas ini tidak bisa memengaruhi aplikasi mobile.
///
/// Web berbeda karena tidak ada berkas konfigurasi yang ikut ter-bundle —
/// nilainya harus ditanam di dalam kode.
///
/// CARA MENGISI:
///   1. Firebase Console → project `imago-3137c` → Project settings
///   2. Your apps → Add app → pilih Web (ikon `</>`)
///   3. Salin objek `firebaseConfig` yang muncul ke [kWebFirebaseOptions]
///   4. Authentication → Settings → Authorized domains → tambahkan domain
///      tempat web ini di-deploy (localhost sudah ada secara bawaan)
///
/// `appId` web BERBEDA dari `appId` Android dan tidak bisa diturunkan darinya,
/// karena itu nilai ini tidak bisa diisi otomatis dari google-services.json.
///
/// Selama masih null, [FirebaseService] akan berjalan dengan `ready == false`
/// dan seluruh data jatuh ke penyimpanan lokal — aplikasi tetap berfungsi.
const FirebaseOptions? kWebFirebaseOptions = null;

// Contoh bentuk isiannya:
//
// const FirebaseOptions? kWebFirebaseOptions = FirebaseOptions(
//   apiKey: '...',
//   appId: '1:1008830387025:web:...',
//   messagingSenderId: '1008830387025',
//   projectId: 'imago-3137c',
//   authDomain: 'imago-3137c.firebaseapp.com',
//   storageBucket: 'imago-3137c.firebasestorage.app',
// );
