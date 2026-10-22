# Aturan R8 tambahan untuk build rilis.

# --- ML Kit Text Recognition ---
# Plugin google_mlkit_text_recognition merujuk SELURUH varian aksara
# (Mandarin, Devanagari, Jepang, Korea) di dalam initialize(), padahal aplikasi
# ini hanya memakai aksara Latin. Dependensi varian lain tidak disertakan, jadi
# kelasnya memang tidak ada dan R8 menganggapnya rujukan yang hilang.
#
# Dibungkam, BUKAN ditambahkan: menyertakan keempat paket aksara itu akan
# membengkakkan aplikasi puluhan megabyte untuk kemampuan yang tidak dipakai.
# Selama kode tidak pernah meminta aksara selain Latin, rujukan itu tidak akan
# pernah dieksekusi.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# --- ML Kit custom model ---
# Model TFLite dimuat lewat refleksi oleh ML Kit; tanpa ini R8 bisa membuang
# kelas yang hanya dirujuk secara dinamis.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
