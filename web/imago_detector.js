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

  // Disimpan sendiri di server IMAGO (pentest temuan 10). import() dinamis
  // tidak bisa membawa atribut integrity, jadi berkasnya diambil dan diperiksa
  // SHA-256-nya saat build oleh tool/fetch_web_vendor.sh.
  var TASKS_VERSION = '0.10.14';
  var BASE = new URL('vendor/mediapipe/' + TASKS_VERSION + '/', document.baseURI).href;
  var BUNDLE = BASE + 'vision_bundle.mjs';

  var classifier = null;
  var running = false;
  var callback = null;
  var lastAt = 0;
  var minIntervalMs = 200;

  // ROI pencarian dalam koordinat piksel video, diisi oleh Dart dari cincin
  // bidik lewat setRoi().
  var roi = null;

  // Kotak koin yang terkunci di frame sebelumnya. Selama ada, ia dipakai
  // sebagai daerah pencarian berikutnya — DI SINILAH pelacakannya: potongan
  // mengikuti koin, sehingga koin boleh keluar dari cincin bidik dan tetap
  // terlacak. Begitu classifier menjawab background, kunci dilepas dan
  // pencarian kembali ke cincin.
  var trackBox = null;

  // True bila lingkaran hasil fit menyentuh tepi potongan, yang berarti koin
  // kemungkinan besar MELUAS keluar dari daerah pencarian. Dalam keadaan itu
  // jari-jarinya pasti diremehkan, dan tanpa penanganan khusus daerah
  // pencarian akan terus memeluk ukuran yang salah — pelacakan terkunci pada
  // potongan koin, bukan koinnya.
  var trackClipped = false;

  // Berapa frame berturut-turut daerah pencarian sudah dilebarkan tanpa
  // menghasilkan fit yang utuh. Tanpa batas ini pelebarannya kabur: koin yang
  // keluar total dari potongan membuat fit menangkap derau latar, menandainya
  // terpotong, lalu melebar lagi — dan seterusnya sampai mencakup seluruh
  // layar. Setelah batas ini kunci dilepas dan pencarian kembali ke cincin.
  var trackGrows = 0;
  var MAX_GROWS = 3;

  // Fase pencarian saat belum ada kunci.
  //
  // Mobile memakai ML Kit yang memindai SELURUH bingkai, jadi koin di mana pun
  // akan terdeteksi. Kalau web hanya pernah melihat cincin bidik, koin yang
  // berada di luar cincin tidak akan pernah ditemukan — perbedaan perilaku
  // yang akan terasa langsung oleh pengguna.
  //
  // Karena itu frame tanpa kunci MENYISIR: fase 0 adalah cincin bidik (peka
  // untuk koin dekat yang sedang dibidik), fase 1..3 adalah tiga jendela
  // setinggi bingkai yang digeser dari tepi kiri ke tepi kanan.
  //
  // Jendelanya harus PERSEGI, bukan selebar bingkai, karena potongan apa pun
  // berakhir di kanvas 224x224: jendela 16:9 akan dipenuhkan ke persegi dan
  // koinnya ikut gepeng, padahal model dilatih dari foto yang rasionya wajar.
  // Satu jendela persegi di tengah pun tidak cukup — pada bingkai 16:9 ia
  // meninggalkan dua pita di kiri dan kanan yang tidak pernah terlihat.
  var searchPhase = 0;
  var SWEEP_PHASES = 3;

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
      return import(BUNDLE)
        .then(function (mod) {
          return mod.FilesetResolver.forVisionTasks(BASE + 'wasm')
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

  // ===== PELOKALAN KOIN =====
  //
  // Mencari lingkaran koin di dalam potongan 224x224 yang sudah digambar ke
  // kanvas kerja. Tanpa pustaka luar: OpenCV.js berukuran ~3 MB terkompresi,
  // dan sebagian besar isinya tidak terpakai di sini.
  //
  // Masalahnya jauh lebih mudah daripada "cari lingkaran di gambar apa pun",
  // karena tiga batasan yang sudah dijamin pemanggilnya:
  //   1. Diharapkan TEPAT SATU objek di dalam potongan.
  //   2. Objek itu kira-kira memenuhi potongan — penggunanya sedang membidik.
  //   3. Classifier SUDAH memastikan isinya koin; kelas `background` yang
  //      dilatih sendiri yang menyaring salah tangkap.
  // Karena itu pencocokan bentuknya tidak perlu bertahan melawan serat kayu
  // meja; ia hanya perlu mempertajam posisi dan jari-jari di dalam daerah
  // yang sudah diketahui berisi koin.

  var EDGE_N = 56;          // sisi peta tepi; 224/4, cukup untuk jari-jari
  var EDGE_KEEP = 0.12;     // ambil 12% piksel bergradien terkuat sebagai tepi

  var gray = null;
  var edgeXs = null;
  var edgeYs = null;

  /// Peta abu-abu EDGE_N x EDGE_N dari potongan 224x224, dengan rata-rata
  /// blok 4x4 sekaligus sebagai peredam derau.
  function toGray(data) {
    if (!gray) gray = new Float32Array(EDGE_N * EDGE_N);
    var step = 224 / EDGE_N;
    for (var y = 0; y < EDGE_N; y++) {
      for (var x = 0; x < EDGE_N; x++) {
        var sum = 0;
        for (var by = 0; by < step; by++) {
          var sy = (y * step + by) | 0;
          for (var bx = 0; bx < step; bx++) {
            var sx = (x * step + bx) | 0;
            var i = (sy * 224 + sx) * 4;
            // Luma BT.601; cukup untuk mencari tepi.
            sum += 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
          }
        }
        gray[y * EDGE_N + x] = sum / (step * step);
      }
    }
    return gray;
  }

  /// Fit lingkaran aljabar (Kasa): meminimalkan
  ///   (x^2+y^2) + D*x + E*y + F = 0
  /// secara linear, jadi tanpa iterasi. Mengembalikan null bila sistemnya
  /// nyaris singular — yang terjadi kalau titik tepinya sebaris, misalnya saat
  /// yang terlihat hanya tepi meja dan bukan lingkaran.
  function fitCircle(xs, ys, idx) {
    var n = idx.length;
    if (n < 12) return null;
    var sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, sxz = 0, syz = 0, sz = 0;
    for (var k = 0; k < n; k++) {
      var x = xs[idx[k]], y = ys[idx[k]];
      var z = x * x + y * y;
      sx += x; sy += y; sz += z;
      sxx += x * x; syy += y * y; sxy += x * y;
      sxz += x * z; syz += y * z;
    }
    var a11 = sxx - sx * sx / n;
    var a12 = sxy - sx * sy / n;
    var a22 = syy - sy * sy / n;
    var b1 = (sxz - sx * sz / n) / 2;
    var b2 = (syz - sy * sz / n) / 2;
    var det = a11 * a22 - a12 * a12;
    if (Math.abs(det) < 1e-6) return null;
    var cx = (b1 * a22 - b2 * a12) / det;
    var cy = (a11 * b2 - a12 * b1) / det;
    var rsum = 0;
    for (var m = 0; m < n; m++) {
      var dx = xs[idx[m]] - cx, dy = ys[idx[m]] - cy;
      rsum += Math.sqrt(dx * dx + dy * dy);
    }
    return { cx: cx, cy: cy, r: rsum / n };
  }

  /// Mencari koin di dalam potongan. Mengembalikan { cx, cy, r } dalam satuan
  /// piksel potongan 224x224, atau null bila tidak meyakinkan.
  function localise(data) {
    var g = toGray(data);
    var N = EDGE_N;

    // Sobel, hanya magnitudonya.
    var mags = new Float32Array(N * N);
    var maxMag = 0;
    for (var y = 1; y < N - 1; y++) {
      for (var x = 1; x < N - 1; x++) {
        var i = y * N + x;
        var gx =
          -g[i - N - 1] - 2 * g[i - 1] - g[i + N - 1] +
           g[i - N + 1] + 2 * g[i + 1] + g[i + N + 1];
        var gy =
          -g[i - N - 1] - 2 * g[i - N] - g[i - N + 1] +
           g[i + N - 1] + 2 * g[i + N] + g[i + N + 1];
        var m = Math.sqrt(gx * gx + gy * gy);
        mags[i] = m;
        if (m > maxMag) maxMag = m;
      }
    }
    if (maxMag < 1e-3) return null;

    // Ambang adaptif: ambil EDGE_KEEP terkuat. Ambang mutlak akan gagal
    // begitu pencahayaannya berubah.
    var hist = new Int32Array(64);
    for (var h = 0; h < mags.length; h++) {
      hist[Math.min(63, (mags[h] / maxMag * 63) | 0)]++;
    }
    var want = Math.round(mags.length * EDGE_KEEP);
    var acc = 0, bin = 63;
    for (; bin > 0; bin--) { acc += hist[bin]; if (acc >= want) break; }
    var thr = bin / 63 * maxMag;

    // Lantai mutlak, relatif terhadap gradien terkuat di potongan ini.
    //
    // Tanpa ini ambangnya hanya mengambil FRAKSI TETAP piksel terkuat, berapa
    // pun lemahnya. Pada latar yang nyaris rata — meja polos dengan koin kecil
    // di satu sudut — 12% itu terpaksa diisi derau sensor yang tersebar
    // MERATA, dan titik yang tersebar merata justru memasang lingkaran besar
    // di tengah potongan dengan sebaran sudut yang sempurna. Itulah sumber
    // kunci palsu berjari-jari raksasa, dan tidak satu pun uji di bawah bisa
    // menangkapnya, karena secara geometri lingkaran itu memang "bagus".
    //
    // Tepi koin selalu termasuk gradien terkuat di dalam potongannya, jadi
    // lantai relatif ini tidak membuang tepi yang benar.
    thr = Math.max(thr, maxMag * 0.30);

    if (!edgeXs) { edgeXs = new Float32Array(N * N); edgeYs = new Float32Array(N * N); }
    var cnt = 0;
    for (var yy = 1; yy < N - 1; yy++) {
      for (var xx = 1; xx < N - 1; xx++) {
        if (mags[yy * N + xx] >= thr) { edgeXs[cnt] = xx; edgeYs[cnt] = yy; cnt++; }
      }
    }
    if (cnt < 20) return null;

    var idx = new Array(cnt);
    for (var p = 0; p < cnt; p++) idx[p] = p;

    var fit = fitCircle(edgeXs, edgeYs, idx);
    if (!fit) return null;

    // Dua kali pemangkasan outlier: tepi tulisan dan ornamen DI DALAM koin
    // ikut terambil sebagai titik tepi, dan tanpa dibuang mereka menarik
    // jari-jari hasil fit ke arah lebih kecil.
    for (var pass = 0; pass < 2; pass++) {
      var devs = new Float64Array(cnt);
      for (var q = 0; q < cnt; q++) {
        var ddx = edgeXs[q] - fit.cx, ddy = edgeYs[q] - fit.cy;
        devs[q] = Math.abs(Math.sqrt(ddx * ddx + ddy * ddy) - fit.r);
      }
      var sorted = Array.prototype.slice.call(devs).sort(function (a, b) { return a - b; });
      var med = sorted[(sorted.length / 2) | 0];
      var cut = Math.max(1.2, med * 2.0);
      var keep = [];
      for (var s = 0; s < cnt; s++) if (devs[s] <= cut) keep.push(s);
      var refit = fitCircle(edgeXs, edgeYs, keep);
      if (!refit) break;
      fit = refit;
      idx = keep;
    }

    // Tolak hasil yang tidak masuk akal: pusat di luar potongan, atau
    // jari-jari terlalu kecil/besar untuk sebuah koin yang sedang dibidik.
    var scale = 224 / N;
    var r = fit.r * scale;
    var cx = fit.cx * scale;
    var cy = fit.cy * scale;
    if (!(r > 224 * 0.12 && r < 224 * 0.80)) return null;
    if (cx < 0 || cy < 0 || cx > 224 || cy > 224) return null;

    // Seberapa banyak titik tepi yang benar-benar duduk di lingkaran hasil.
    // Di bawah ini hasilnya lebih baik dibuang daripada dipakai: kotak yang
    // ukurannya salah pada koin yang terklasifikasi BENAR justru membuat aset
    // berdenyut, dan itu lebih mengganggu daripada aset yang diam sejenak.
    if (idx.length < cnt * 0.25) return null;

    // Sebaran sudut titik pendukung.
    //
    // Inilah yang membedakan lingkaran sungguhan dari kebetulan aljabar. Fit
    // Kasa akan selalu mengembalikan SESUATU asal ada cukup titik, dan ketika
    // koinnya kecil di dalam jendela sapuan yang lebar, "sesuatu" itu berupa
    // lingkaran raksasa yang dipasang pada gradien latar yang berserak.
    // Tepi koin yang benar menutupi SELURUH keliling; derau hanya menduduki
    // beberapa arah saja. Uji inilah yang menolaknya, bukan ambang jari-jari —
    // lingkaran palsu tadi lolos semua batas ukuran.
    var SECTORS = 12;
    var terisi = new Uint8Array(SECTORS);
    var nSektor = 0;
    for (var t = 0; t < idx.length; t++) {
      var tx = edgeXs[idx[t]] - fit.cx;
      var ty = edgeYs[idx[t]] - fit.cy;
      var sektor = Math.floor((Math.atan2(ty, tx) + Math.PI) / (2 * Math.PI) * SECTORS) % SECTORS;
      if (!terisi[sektor]) { terisi[sektor] = 1; nSektor++; }
    }
    if (nSektor < 9) return null;

    // Lingkaran yang menyentuh tepi potongan berarti koin meluas keluar dari
    // daerah pencarian, sehingga jari-jari ini pasti terlalu kecil.
    var clipped = (cx - r < 4) || (cy - r < 4) ||
                  (cx + r > 220) || (cy + r > 220);

    return {
      cx: cx, cy: cy, r: r,
      clipped: clipped,
      inliers: idx.length, total: cnt,
    };
  }

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

    // Urutan pemilihan daerah pencarian:
    //   1. kotak koin yang sedang terkunci, dilebarkan agar koin yang bergerak
    //      tidak langsung keluar dari potongan antar-frame;
    //   2. cincin bidik yang dikirim Dart;
    //   3. kotak tengah, agar detektor tetap berguna sebelum geometri layar
    //      diketahui.
    var r;
    if (trackBox) {
      // Melebar jauh lebih agresif saat hasil sebelumnya terpotong, supaya
      // daerah pencarian tumbuh sampai seluruh koin masuk dan fit-nya pulih.
      var pad = trackClipped ? 1.0 : 0.45;
      var rw = trackBox.w * (1 + pad * 2);
      var rh = trackBox.h * (1 + pad * 2);
      // Daerah pencarian tidak pernah boleh melebihi bingkainya sendiri.
      var cap = Math.min(vw, vh);
      rw = Math.min(rw, cap);
      rh = Math.min(rh, cap);
      r = {
        x: trackBox.x + trackBox.w / 2 - rw / 2,
        y: trackBox.y + trackBox.h / 2 - rh / 2,
        w: rw,
        h: rh,
      };
    } else if (roi && searchPhase === 0) {
      r = roi;
    } else {
      // Jendela persegi setinggi bingkai, digeser merata dari tepi ke tepi.
      var side = Math.min(vw, vh);
      var slot = SWEEP_PHASES > 1 ? (searchPhase - 1) / (SWEEP_PHASES - 1) : 0.5;
      r = {
        x: (vw - side) * slot,
        y: (vh - side) / 2,
        w: side,
        h: side,
      };
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
    var box = { x: x, y: y, w: w, h: h };
    var located = false;
    var clipped = false;
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

      // Pelokalan hanya dijalankan setelah classifier memastikan isinya koin.
      // Urutan ini yang membuat pencocokan bentuk sederhana bisa diandalkan:
      // ia tidak pernah diminta memutuskan ADA atau TIDAK ADA koin, hanya
      // mempertajam posisi dan jari-jari di daerah yang sudah pasti berisi.
      if (label && label !== 'background') {
        var found = localise(ctx.getImageData(0, 0, 224, 224).data);
        if (found) {
          var sx = w / 224, sy = h / 224;
          var cxv = x + found.cx * sx;
          var cyv = y + found.cy * sy;
          var rxv = found.r * sx;
          var ryv = found.r * sy;
          box = { x: cxv - rxv, y: cyv - ryv, w: rxv * 2, h: ryv * 2 };
          clipped = found.clipped;
          // Fit yang terpotong PASTI salah ukuran, jadi tidak dilaporkan
          // sebagai temuan: aset lebih baik diam di ukuran terakhirnya
          // daripada berdenyut ke ukuran yang keliru. Kotaknya tetap dipakai
          // untuk melebarkan daerah pencarian frame berikutnya.
          located = !clipped;
        }
      }
    } catch (e) {
      // Satu frame gagal tidak boleh menghentikan loop.
      label = '';
      score = 0;
      located = false;
    }
    var dt = Math.round(performance.now() - t0);

    if (located) {
      trackBox = box;
      trackClipped = false;
      trackGrows = 0;
    } else if (clipped && trackGrows < MAX_GROWS) {
      // Masih menyimpan kuncinya, tapi melebar untuk mencari koin utuhnya.
      trackBox = box;
      trackClipped = true;
      trackGrows++;
    } else {
      trackBox = null;
      trackClipped = false;
      trackGrows = 0;
      // Hanya bergantian saat benar-benar belum ada kunci.
      // Tanpa cincin bidik dari Dart, fase 0 dilewati.
      var first = roi ? 0 : 1;
      searchPhase = searchPhase >= SWEEP_PHASES ? first : searchPhase + 1;
    }

    if (callback) {
      try {
        callback({
          label: label,
          confidence: score,
          x: box.x, y: box.y, w: box.w, h: box.h,
          // false berarti kotak di atas hanyalah daerah pencarian, bukan koin
          // yang benar-benar ditemukan. Dart memakai ini untuk memutuskan
          // apakah posisi aset boleh diperbarui.
          located: located,
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
