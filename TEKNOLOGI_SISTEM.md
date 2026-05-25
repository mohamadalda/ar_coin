# Dokumentasi Spesifikasi Teknologi Sistem - IMAGO (AR Koin Pahlawan)

Dokumen ini disusun untuk mempermudah penulisan Karya Tulis Ilmiah (KTI), khususnya pada bagian **Metodologi Penelitian**, **Perancangan Sistem**, atau **Implementasi Teknologi**.

---

## 1. Deskripsi Singkat Sistem

Sistem yang dikembangkan adalah **IMAGO**, sebuah aplikasi seluler berbasis Android/iOS yang dirancang untuk mengenali uang koin Rupiah fisik secara *real-time*. Sistem ini memanfaatkan teknologi *Computer Vision* dan *Machine Learning* lokal (*on-device AI*) untuk mengenali profil Pahlawan Nasional Indonesia yang tertera pada koin, serta menyajikan informasi tersebut melalui antarmuka interaktif yang menyerupai *Augmented Reality* (AR) lengkap dengan narasi suara.

---

## 2. Tabel Spesifikasi Teknologi Sistem

Berikut adalah rincian pustaka (*library*), perangkat lunak, dan teknologi pendukung yang digunakan dalam pembangunan aplikasi IMAGO:

| Komponen/Lapisan Sistem | Teknologi / Library | Versi | Fungsi & Peran Utama dalam Sistem |
| :--- | :--- | :--- | :--- |
| **Framework Utama** | Flutter SDK & Dart | SDK `>=3.0.6 <4.0.0` | Framework pengembangan aplikasi multiplatform (Android & iOS) menggunakan satu basis kode (*single codebase*). |
| **Pengenalan Teks (OCR)** | Google ML Kit Text Recognition | `^0.13.1` | Memproses aliran bingkai gambar (*image stream*) untuk mendeteksi dan membaca karakter teks nominal atau nama pahlawan pada koin secara lokal. |
| **Klasifikasi Gambar Kustom** | Google ML Kit Image Labeling (Custom TFLite) | `^0.12.0` | Menjalankan model klasifikasi gambar kustom berbasis TensorFlow Lite (`coin_model.tflite`) untuk mengenali gambar fisik pahlawan pada koin jika teks tidak terbaca. |
| **Input Kamera Fisik** | Camera | `^0.10.5+9` | Mengontrol modul kamera perangkat keras untuk menangkap aliran data video (*live image stream*) beresolusi sedang secara *real-time*. |
| **Manajemen Otorisasi** | Permission Handler | `^11.0.1` | Mengelola perizinan sistem operasi secara dinamis, khususnya untuk otorisasi akses kamera dan penyimpanan perangkat. |
| **Umpan Balik Suara** | Audioplayers | `^5.2.1` | Memutar berkas audio narasi biografi pahlawan sebagai umpan balik multimedia interaktif bagi pengguna. |
| **Desain Antarmuka (UI/UX)** | Glassmorphism | `^3.0.0` | Menghasilkan efek visual buram transparan (*frosted glass effect*) pada kartu profil pahlawan untuk meningkatkan estetika antarmuka. |
| **Animasi Mikro** | Animate Do | `^3.0.2` | Menyediakan pustaka animasi transisi (seperti *fade-in*, *pulse*, dan *slide*) agar transisi status deteksi pada antarmuka terasa dinamis. |
| **Tipografi Sistem** | Google Fonts | `^5.1.0` | Mengintegrasikan keluarga huruf (font) *Outfit* dari Google Fonts secara langsung ke dalam tema aplikasi. |
| **Aset Ikonografi** | Cupertino Icons | `^1.0.2` | Menyediakan pustaka ikon bawaan bergaya iOS untuk elemen navigasi dan tombol aksi pada HUD aplikasi. |

---

## 3. Alur Kerja Integrasi Teknologi

Alur interaksi antarkomponen teknologi dalam sistem ini dirancang dengan tahapan sebagai berikut:

1. **Inisialisasi Perangkat Keras**: Aplikasi menggunakan `permission_handler` untuk memastikan izin kamera telah diberikan oleh sistem operasi. Setelah izin diperoleh, library `camera` akan mengaktifkan kamera belakang dan memancarkan aliran gambar per bingkai (*frame-by-frame image stream*).
2. **Pra-pemrosesan Data Gambar**: Setiap bingkai gambar dari aliran kamera dikonversi menjadi format `InputImage` dengan menyesuaikan rotasi sensor dan format piksel perangkat (NV21 untuk Android atau BGRA8888 untuk iOS).
3. **Analisis Hibrida (Machine Learning)**:
   - **Pendekatan Pertama (OCR)**: Sistem mengirimkan data gambar ke `google_mlkit_text_recognition` untuk mengidentifikasi teks atau angka nominal pada koin.
   - **Pendekatan Kedua (Klasifikasi Pola)**: Jika teks tidak terdeteksi, sistem menggunakan `google_mlkit_image_labeling` dengan model lokal `coin_model.tflite` untuk mendeteksi pola gambar pahlawan pada koin.
4. **Rendering Antarmuka Interaktif**: Ketika data koin cocok dengan basis data pahlawan (`mockHeroes`), sistem menampilkan overlay informasi yang dianimasikan dengan `animate_do` dan dibingkai menggunakan efek visual transparan dari `glassmorphism`.
5. **Output Audio**: Pengguna dapat mengetuk foto pahlawan pada overlay untuk memicu pemutaran rekaman suara biografi yang dikelola oleh library `audioplayers`.
