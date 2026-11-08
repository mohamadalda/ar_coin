/*
 * Memuat Firebase JS SDK dari server IMAGO sendiri, lalu baru menyalakan
 * Flutter.
 *
 * Tanpa ini, plugin firebase_core_web menyuntikkan firebase-app.js,
 * firebase-auth.js, dan firebase-firestore-pipelines.js dari www.gstatic.com
 * saat runtime, tanpa pemeriksaan integritas (pentest IMAGO temuan 10).
 *
 * Mekanismenya resmi dari plugin: bila window.firebase_core sudah ada saat
 * Firebase.initializeApp() dipanggil, plugin menganggap skrip sudah dimuat
 * pemilik halaman dan TIDAK menyuntikkan apa pun. Nama variabelnya mengikuti
 * plugin: firebase_core, firebase_auth, firebase_firestore, firebase_app_check.
 *
 * flutter_bootstrap.js sengaja baru dimuat SETELAH ketiganya siap. Kalau
 * dimuat bersamaan, main() bisa memanggil initializeApp() lebih dulu dan
 * plugin kembali menyuntik dari CDN.
 *
 * Berkasnya diambil saat build oleh tool/fetch_web_vendor.sh (dengan
 * pemeriksaan SHA-256). Bila salinan lokal tidak ada, ketiga variabel
 * dikosongkan lagi agar plugin memakai jalur bawaannya — aplikasi tetap
 * jalan, dan kesalahannya terlihat di konsol.
 */
(function () {
  'use strict';

  var FB = 'vendor/firebase/13.0.0/';

  function url(path) {
    return new URL(path, document.baseURI).href;
  }

  function startFlutter() {
    var s = document.createElement('script');
    s.src = 'flutter_bootstrap.js';
    s.async = true;
    document.body.appendChild(s);
  }

  // firebase-app.js lebih dulu: kedua bundel lain mengimpornya, dan memuat
  // semuanya serentak memicu cacat evaluasi modul di Safari/WebKit
  // (flutterfire#18436).
  import(url(FB + 'firebase-app.js'))
    .then(function (app) {
      window.firebase_core = app;
      return Promise.all([
        import(url(FB + 'firebase-auth.js')),
        import(url(FB + 'firebase-firestore-pipelines.js')),
        // App Check (pentest temuan 4). Bundel ini sendiri memuat skrip
        // reCAPTCHA dari www.google.com — satu-satunya yang tidak bisa
        // disimpan sendiri, dan diizinkan terbatas di CSP.
        import(url(FB + 'firebase-app-check.js')),
      ]);
    })
    .then(function (mods) {
      window.firebase_auth = mods[0];
      window.firebase_firestore = mods[1];
      window.firebase_app_check = mods[2];
    })
    .catch(function (e) {
      console.error(
        '[IMAGO] Firebase SDK lokal tidak termuat; jalankan ' +
          'tool/fetch_web_vendor.sh sebelum build.',
        e
      );
      delete window.firebase_core;
      delete window.firebase_auth;
      delete window.firebase_firestore;
      delete window.firebase_app_check;
    })
    .then(startFlutter);
})();
