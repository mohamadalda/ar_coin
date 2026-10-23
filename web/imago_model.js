/*
 * Aset 3D IMAGO untuk web.
 *
 * Di mobile, model-viewer dijalankan di dalam WebView lewat paket
 * model_viewer_plus. Paket itu TIDAK bisa dipakai di web, dan bukan karena
 * kurang matang — tiga hal di implementasi webnya saling menutup jalan:
 *
 *   1. Ia menulis HTML lewat `element.innerHTML`. Menurut spesifikasi HTML,
 *      <script> yang disisipkan dengan innerHTML tidak pernah dieksekusi, jadi
 *      seluruh kalibrasi yang dikirim lewat `relatedJs` tidak berjalan.
 *   2. Ia justru MENGHAPUS tag <script src="model-viewer.min.js"> dari
 *      templatnya, sehingga elemen <model-viewer> tidak pernah "naik kelas"
 *      dari elemen tak dikenal — hasilnya kotak kosong tanpa pesan kesalahan.
 *   3. `onWebViewCreated` dan `javascriptChannels` diterima constructor-nya
 *      lalu diabaikan, sehingga kanal ModelReady mati.
 *
 * Karena elemennya di web toh mendarat di dokumen utama — tanpa iframe, tanpa
 * closed shadow root — lebih sederhana memilikinya sendiri. Elemen ini duduk
 * di antara lapisan kamera dan kanvas Flutter, dan posisinya ditulis dari Dart
 * memakai nilai anchor yang SAMA dengan yang memposisikan panel keterangan.
 */
(function () {
  'use strict';

  var mv = null;
  var readyCb = null;
  var t0 = 0;

  // Faktor kalibrasi: radius_meter = K / tinggi_piksel_yang_diinginkan.
  var K = 0;
  var pending = 0;

  function calibrate() {
    if (!mv) return;
    try {
      var d = mv.getDimensions();
      var fov = mv.getFieldOfView() * Math.PI / 180;
      K = d.y * mv.clientHeight / (2 * Math.tan(fov / 2));
    } catch (e) {
      // getDimensions melempar sebelum model selesai dimuat.
      K = 0;
    }
  }

  function apply(px) {
    if (!mv || !K || !px) return;
    var o;
    try { o = mv.getCameraOrbit(); } catch (e) { return; }
    var want = K / px;
    // Ambang 2%: tanpa ini setiap pembaruan menimpa sudut yang sedang digeser
    // jari pengguna, dan modelnya terasa berkelahi dengan tangan.
    if (!o.radius || Math.abs(want - o.radius) / o.radius < 0.02) return;
    mv.cameraOrbit =
      (o.theta * 180 / Math.PI).toFixed(1) + 'deg ' +
      (o.phi * 180 / Math.PI).toFixed(1) + 'deg ' +
      want.toFixed(2) + 'm';
  }

  function onLoad() {
    calibrate();
    if (readyCb) {
      try { readyCb(Math.round(performance.now() - t0)); } catch (e) {}
    }
    // Permintaan ukuran yang tiba sebelum model selesai dimuat tidak boleh
    // hilang: kalau hilang, model tampil di ukuran bawaan sampai koin
    // kebetulan bergerak lagi.
    if (pending) apply(pending);
  }

  window.ImagoModel = {
    /// Membuat elemennya bila belum ada. Elemen dibuat SEKALI dan tidak pernah
    /// dibongkar: membongkarnya berarti mesin render 3D dan berkas GLB harus
    /// diunduh ulang dari nol setiap koin terdeteksi.
    ensure: function () {
      if (mv) return true;
      mv = document.createElement('model-viewer');
      mv.id = 'imago-model';
      mv.setAttribute('alt', '3D model');
      mv.setAttribute('loading', 'eager');
      mv.setAttribute('camera-controls', '');
      mv.setAttribute('disable-pan', '');
      mv.setAttribute('disable-zoom', '');
      mv.setAttribute('disable-tap', '');
      mv.setAttribute('interaction-prompt', 'none');
      mv.setAttribute('autoplay', '');
      // Batas orbit bawaan mengunci radius dengan 105% sebagai PLAFON, artinya
      // model hanya bisa mengecil. Tanpa membuka ini, penguncian ukuran ke
      // koin mustahil. phi dikunci tegak supaya model tidak bisa direbahkan.
      mv.setAttribute('min-camera-orbit', 'auto 75deg 5m');
      mv.setAttribute('max-camera-orbit', 'auto 95deg 120m');
      mv.setAttribute('camera-orbit', '0deg 75deg 105%');
      mv.setAttribute('interpolation-decay', '25');
      mv.setAttribute('ar', '');
      mv.setAttribute('ar-modes', 'scene-viewer webxr quick-look');
      mv.addEventListener('load', onLoad);
      document.body.appendChild(mv);
      window.addEventListener('resize', function () {
        calibrate();
        if (pending) apply(pending);
      });
      return true;
    },

    /// Mengganti model. Mengembalikan false bila src-nya sama, supaya Dart
    /// tidak mereset keadaan "siap" tanpa alasan.
    setSrc: function (url) {
      this.ensure();
      if (mv.getAttribute('src') === url) return false;
      K = 0;
      t0 = performance.now();
      mv.setAttribute('src', url);
      return true;
    },

    /// Posisi dan ukuran kotak render, dalam piksel CSS.
    setRect: function (left, top, w, h) {
      if (!mv) return;
      mv.style.left = left + 'px';
      mv.style.top = top + 'px';

      // Kalibrasi K bergantung pada clientHeight, jadi setiap perubahan TINGGI
      // elemen membuat K basi. Ini nyata, bukan teoretis: setRect pertama dari
      // Dart biasanya tiba SESUDAH event load, sehingga K terlanjur dihitung
      // dari tinggi yang lain dan seluruh penguncian ukuran meleset secara
      // proporsional. Listener resize window saja tidak menangkapnya, karena
      // elemen ini berubah ukuran tanpa jendelanya ikut berubah.
      var tinggiBerubah = mv.style.height !== h + 'px';
      mv.style.width = w + 'px';
      mv.style.height = h + 'px';
      if (tinggiBerubah) {
        calibrate();
        if (pending) apply(pending);
      }
    },

    /// visibility, BUKAN display:none — display:none menunda layout dan dekode,
    /// sehingga "pemanasan" tidak memanaskan apa pun dan clientHeight jadi 0
    /// yang merusak kalibrasi piksel-per-meter.
    setVisible: function (visible) {
      if (!mv) return;
      mv.style.visibility = visible ? 'visible' : 'hidden';
    },

    /// Mengunci ukuran tampil model ke tinggi koin dalam piksel.
    setSize: function (px) {
      pending = px;
      apply(px);
    },

    onReady: function (cb) {
      readyCb = cb;
    },

    isLoaded: function () {
      return !!mv && K > 0;
    },
  };
})();
