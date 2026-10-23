/*
 * Detektor koin IMAGO untuk web.
 *
 * Memuat model yang SAMA PERSIS dengan mobile: assets/coin_model.tflite,
 * lengkap dengan labels.txt yang tertanam di metadatanya. MediaPipe
 * ImageClassifier menerimanya apa adanya (terbukti: 224x224 RGB + metadata),
 * jadi tidak ada ekspor kedua yang bisa melenceng dari yang dipakai mobile.
 *
 * Pembagian tugas dengan Dart:
 *   - berkas ini  : piksel. Memotong ROI, mengubah ukuran, mengklasifikasi.
 *   - Dart        : geometri. Menghitung ROI dalam koordinat video, memetakan
 *                   kotak hasil ke layar, menghaluskan, dan memutuskan kapan
 *                   overlay dilepas.
 *
 * Frame TIDAK pernah menyeberang ke Dart — yang menyeberang hanya objek hasil
 * sekitar seratus byte per frame.
 */
(function () {
  'use strict';

  var TASKS_VERSION = '0.10.14';
  var CDN = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@' + TASKS_VERSION;

  var classifier = null;
  var running = false;
  var callback = null;
  var lastAt = 0;
  var minIntervalMs = 200;

  // ROI dalam koordinat piksel video, diisi oleh Dart lewat setRoi().
  var roi = null;

  // Kanvas kerja 224x224 — tepat ukuran input model, jadi drawImage sekaligus
  // yang melakukan crop dan resize dalam satu langkah ber-akselerasi GPU.
  var canvas = null;
  var ctx = null;

  function workCanvas() {
    if (!canvas) {
      canvas = document.createElement('canvas');
      canvas.width = 224;
      canvas.height = 224;
      ctx = canvas.getContext('2d', { willReadFrequently: true });
    }
    return canvas;
  }

  function videoEl() {
    return document.getElementById('imago-camera');
  }

  window.ImagoDetector = {
    /// Memuat MediaPipe dan membangun classifier dari berkas model aplikasi.
    /// Mengembalikan { ok, error }.
    init: function (modelPath) {
      if (classifier) return Promise.resolve({ ok: true, error: null });
      return import(CDN)
        .then(function (mod) {
          return mod.FilesetResolver.forVisionTasks(CDN + '/wasm')
            .then(function (fileset) {
              return mod.ImageClassifier.createFromOptions(fileset, {
                baseOptions: { modelAssetPath: modelPath },
                maxResults: 4,
                runningMode: 'IMAGE',
              });
            });
        })
        .then(function (c) {
          classifier = c;
          return { ok: true, error: null };
        })
        .catch(function (e) {
          return {
            ok: false,
            error: (e && (e.message || e.name)) ? String(e.message || e.name) : String(e),
          };
        });
    },

    /// Menetapkan daerah yang diklasifikasi, dalam koordinat piksel video.
    /// Dart yang menghitungnya dari cincin bidik di layar, memakai kebalikan
    /// transformasi cover-fit yang sama dengan _trackedRectOnScreen().
    setRoi: function (x, y, w, h) {
      roi = { x: x, y: y, w: w, h: h };
    },

    /// Mendaftarkan penerima hasil. Dipanggil sekali dari Dart; tidak ada
    /// polling.
    onResult: function (cb) {
      callback = cb;
    },

    setInterval: function (ms) {
      minIntervalMs = ms;
    },

    start: function () {
      if (running || !classifier) return;
      running = true;
      tick();
    },

    stop: function () {
      running = false;
    },

    isRunning: function () {
      return running;
    },
  };

  function schedule() {
    if (!running) return;
    var v = videoEl();
    // requestVideoFrameCallback baru ada sejak Safari 15.4; di bawah itu
    // jatuh ke timer biasa.
    if (v && v.requestVideoFrameCallback) {
      v.requestVideoFrameCallback(tick);
    } else {
      setTimeout(tick, minIntervalMs);
    }
  }

  function tick() {
    if (!running) return;

    var v = videoEl();
    if (!v || !v.videoWidth || !classifier) {
      schedule();
      return;
    }

    var now = performance.now();
    if (now - lastAt < minIntervalMs) {
      schedule();
      return;
    }
    lastAt = now;

    var vw = v.videoWidth;
    var vh = v.videoHeight;

    // Tanpa ROI dari Dart, pakai kotak tengah sebagai cadangan agar detektor
    // tetap berguna sebelum geometri layar diketahui.
    var r = roi;
    if (!r) {
      var side = Math.round(Math.min(vw, vh) * 0.6);
      r = { x: (vw - side) / 2, y: (vh - side) / 2, w: side, h: side };
    }

    // Jepit ke dalam bingkai: ROI yang melewati tepi membuat drawImage
    // menggambar area kosong dan klasifikasinya jadi omong kosong.
    var x = Math.max(0, Math.min(r.x, vw - 1));
    var y = Math.max(0, Math.min(r.y, vh - 1));
    var w = Math.max(1, Math.min(r.w, vw - x));
    var h = Math.max(1, Math.min(r.h, vh - y));

    var t0 = performance.now();
    var label = '';
    var score = 0;
    try {
      var c = workCanvas();
      ctx.drawImage(v, x, y, w, h, 0, 0, 224, 224);
      var res = classifier.classify(c);
      var cats = res && res.classifications && res.classifications[0]
        ? res.classifications[0].categories
        : [];
      if (cats.length) {
        label = String(cats[0].categoryName || '');
        score = Number(cats[0].score || 0);
      }
    } catch (e) {
      // Satu frame gagal tidak boleh menghentikan loop.
      label = '';
      score = 0;
    }
    var dt = Math.round(performance.now() - t0);

    if (callback) {
      try {
        callback({
          label: label,
          confidence: score,
          x: x, y: y, w: w, h: h,
          srcW: vw, srcH: vh,
          // Classifier tidak punya konsep "ada objek atau tidak". Yang paling
          // dekat: kelas background yang memang dilatih untuk itu. Apa pun
          // selain background dihitung sebagai ada sesuatu di dalam ROI.
          sawAnyObject: label !== '' && label !== 'background',
          tMs: dt,
        });
      } catch (e) { /* abaikan */ }
    }

    schedule();
  }
})();
