/*
 * Lapisan kamera IMAGO untuk web.
 *
 * Menggantikan plugin `camera` yang di web tidak bisa melakukan
 * startImageStream. Elemen <video> dideklarasikan di index.html dan dimiliki
 * oleh berkas ini, sehingga detektor nanti bisa menggambar frame darinya ke
 * sebuah canvas tanpa perantara apa pun.
 *
 * Dipanggil dari Dart lewat lib/platform/web_camera_web.dart.
 */
(function () {
  'use strict';

  var VIDEO_ID = 'imago-camera';
  var stream = null;

  function video() {
    return document.getElementById(VIDEO_ID);
  }

  /// Menunggu videoWidth/videoHeight terisi. Sebelum metadata tiba keduanya
  /// masih 0, dan ukuran sumber itulah yang dipakai untuk memetakan kotak
  /// koin ke koordinat layar — jadi tidak boleh ditebak.
  function waitForMetadata(v, timeoutMs) {
    if (v.videoWidth > 0) return Promise.resolve();
    return new Promise(function (resolve) {
      var done = false;
      function finish() {
        if (done) return;
        done = true;
        v.removeEventListener('loadedmetadata', finish);
        resolve();
      }
      v.addEventListener('loadedmetadata', finish);
      setTimeout(finish, timeoutMs || 4000);
    });
  }

  window.ImagoCamera = {
    /// Meminta izin kamera dan menyalakan preview.
    ///
    /// Di web, getUserMedia ITU SENDIRI adalah prompt izinnya — tidak ada
    /// permission_handler yang perlu dipanggil (paket itu tidak punya
    /// implementasi web dan selalu menjawab "denied").
    ///
    /// Mengembalikan { ok, error, width, height }.
    start: function () {
      var v = video();
      if (!v) {
        return Promise.resolve({
          ok: false, error: 'ElementMissing', width: 0, height: 0,
        });
      }
      if (stream) {
        v.style.display = 'block';
        return Promise.resolve({
          ok: true, error: null, width: v.videoWidth, height: v.videoHeight,
        });
      }
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        // Konteks tidak aman (http non-localhost) termasuk di sini.
        return Promise.resolve({
          ok: false, error: 'InsecureContextOrUnsupported', width: 0, height: 0,
        });
      }

      // facingMode ideal, bukan exact: di laptop tidak ada kamera belakang dan
      // `exact` akan menggagalkan permintaan sepenuhnya.
      var constraints = {
        audio: false,
        video: {
          facingMode: { ideal: 'environment' },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      };

      return navigator.mediaDevices.getUserMedia(constraints)
        .then(function (s) {
          stream = s;
          v.srcObject = s;
          var played = v.play();
          return (played && played.catch ? played.catch(function () {}) : Promise.resolve())
            .then(function () { return waitForMetadata(v, 4000); })
            .then(function () {
              v.style.display = 'block';
              return {
                ok: true, error: null,
                width: v.videoWidth, height: v.videoHeight,
              };
            });
        })
        .catch(function (e) {
          return {
            ok: false,
            error: (e && (e.name || e.message)) ? String(e.name || e.message) : String(e),
            width: 0, height: 0,
          };
        });
    },

    /// Mematikan kamera dan menyembunyikan lapisannya. Wajib dipanggil saat
    /// keluar dari layar scanner: tab yang masih memegang track kamera akan
    /// terus menampilkan indikator rekaman di browser.
    stop: function () {
      if (stream) {
        stream.getTracks().forEach(function (t) { t.stop(); });
        stream = null;
      }
      var v = video();
      if (v) {
        v.srcObject = null;
        v.style.display = 'none';
      }
    },

    /// Ukuran sumber video saat ini, atau 0x0 bila belum siap.
    size: function () {
      var v = video();
      return v
        ? { width: v.videoWidth, height: v.videoHeight }
        : { width: 0, height: 0 };
    },

    /// True bila kamera sedang menyala.
    isRunning: function () {
      return stream !== null;
    },
  };
})();
