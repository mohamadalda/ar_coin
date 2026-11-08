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
///
/// `apiKey` di bawah BUKAN rahasia. Konfigurasi Firebase untuk web memang
/// dirancang untuk ikut terkirim ke setiap browser, dan tidak bisa
/// disembunyikan di aplikasi sisi klien. Yang menjaga data tetap aman adalah
/// Firestore Security Rules dan daftar Authorized domains di Authentication,
/// bukan kerahasiaan nilai ini.
/// Site key reCAPTCHA Enterprise untuk Firebase App Check di web (pentest
/// temuan 4). Kunci "IMAGO web App Check" di Google Cloud → Security →
/// Fraud Defense, proyek imago-3137c, hanya berlaku untuk imago.peruri.co.id.
///
/// Site key memang publik — ia ikut terkirim ke browser. Tidak ada secret
/// key: reCAPTCHA Enterprise dinilai langsung oleh App Check di proyek yang
/// sama.
///
/// Null berarti App Check tidak diaktifkan. Selama App Check di-enforce di
/// Console, build web tanpa site key akan ditolak Firestore dan Auth.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? kWebRecaptchaSiteKey = '6Ld1MBYuAAAAAIEhGISRS2-PTZcWdEuCoUkccgHE';

// Tipenya SENGAJA nullable meski sekarang terisi: nilai null adalah jalur
// "belum dikonfigurasi" yang dibaca FirebaseService, dan jalur itu harus tetap
// hidup supaya siapa pun yang meng-clone repo ini tanpa project Firebase
// sendiri tetap bisa menjalankan aplikasinya dengan penyimpanan lokal.
// ignore: unnecessary_nullable_for_final_variable_declarations
const FirebaseOptions? kWebFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyB6a_mdwET2gNchjdZrd-LjxQtv6KObKug',
  appId: '1:1008830387025:web:0c90897d3c938686393970',
  messagingSenderId: '1008830387025',
  projectId: 'imago-3137c',
  authDomain: 'imago-3137c.firebaseapp.com',
  storageBucket: 'imago-3137c.firebasestorage.app',
  measurementId: 'G-E6Y8E8HBCE',
);
