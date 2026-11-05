# Deploy IMAGO Web ke VPS

Caddy di dalam Docker, melayani hasil `flutter build web` sebagai berkas statis,
dengan sertifikat HTTPS yang terbit dan diperpanjang sendiri.

**HTTPS wajib, bukan opsional.** `getUserMedia` hanya tersedia di konteks aman.
Dibuka lewat `http://` atau lewat alamat IP, IMAGO tetap tampil rapi — tapi
scanner-nya mati total tanpa pesan yang jelas.

## Sekali di awal

**1. Pastikan DNS sudah mengarah.**

```bash
dig +short imago.peruri.co.id     # harus keluar IP VPS-mu
```

Lalu periksa apakah nama itu juga dikenal dari luar — jawabannya menentukan
sumber sertifikat yang bisa dipakai:

```bash
dig +short @1.1.1.1 imago.peruri.co.id
```

Kosong atau NXDOMAIN berarti servernya hanya ada di DNS internal. Let's Encrypt
tidak akan pernah bisa menerbitkan sertifikat untuknya — ia memverifikasi lewat
DNS publik, dan itu juga berlaku untuk DNS-01. Pakai `TLS_MODE=internal`.

**2. Siapkan VPS.** Docker dan plugin compose:

```bash
curl -fsSL https://get.docker.com | sh
```

Lalu buat direkturinya. `/srv` milik root, jadi perlu sudo — dan kepemilikannya
dipindah ke user SSH-mu supaya rsync bisa menulis ke sana tanpa sudo:

```bash
sudo mkdir -p /srv/imago
sudo chown -R "$USER:$USER" /srv/imago
```

Terakhir, izin menjalankan Docker. Skrip deploy memanggil `docker compose`
lewat SSH non-interaktif, dan di sana tidak ada tempat mengetik kata sandi
sudo. Dua pilihan:

```bash
# A. Masukkan user ke grup docker, lalu login ulang SSH agar berlaku.
sudo usermod -aG docker "$USER"

# B. Atau biarkan apa adanya dan jalankan deploy dengan:
#    DOCKER_CMD="sudo docker" VPS_HOST=... ./deploy/deploy.sh
#    (hanya berhasil kalau user boleh sudo TANPA kata sandi)
```

Pilihan A lebih praktis, tapi perlu disadari: anggota grup `docker` praktis
setara root di mesin itu, karena bisa menjalankan container yang me-mount
seluruh filesystem host. Di server produksi, pastikan itu memang diperbolehkan
kebijakan tempatmu.

Setelah login ulang, pastikan berhasil tanpa sudo:

```bash
docker ps
```

Port 80 dan 443 harus terbuka di firewall. Port 80 tetap diperlukan walau situs
hanya dilayani lewat HTTPS — di situlah verifikasi sertifikat berlangsung.

**3. Isi konfigurasi.** Salin `.env.example` jadi `/srv/imago/.env` di VPS:

```
DOMAIN=imago.domainmu.com
ACME_EMAIL=email-kamu@contoh.com
```

**4. Deploy dari mesin lokal:**

```bash
VPS_HOST=root@1.2.3.4 ./deploy/deploy.sh
```

**5. Daftarkan domainnya di Firebase.** Console → Authentication → Settings →
**Authorized domains** → tambahkan `imago.domainmu.com`. Tanpa ini halamannya
terbuka normal tapi **login gagal**, dan pesannya tidak menyebut domain sama
sekali sehingga sulit ditebak.

**6. Periksa Firestore Rules.** Konfigurasi Firebase untuk web ikut terkirim ke
setiap pengunjung — memang begitu rancangannya dan tidak bisa disembunyikan.
Yang benar-benar menjaga datamu adalah Rules. Pastikan tulis-menulis tidak
terbuka untuk publik.

## Server internal: memasang root CA di perangkat

Dengan `TLS_MODE=internal`, Caddy membuat CA-nya sendiri. Browser belum
mengenalnya, jadi akan muncul peringatan sertifikat — dan selama peringatan itu
ada, kamera tidak bisa dipercaya sepenuhnya oleh browser.

Pasang root CA-nya sekali di tiap perangkat yang dipakai mencoba. Ambil dulu
berkasnya dari container:

```bash
cd /srv/imago
sudo docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./imago-root-ca.crt
```

Pindahkan berkas itu ke HP, lalu:

**Android** — Settings → Security → Encryption & credentials → Install a
certificate → **CA certificate**. Chrome mempercayai CA yang dipasang pengguna
untuk penjelajahan, jadi ini cukup.

**iPhone** — buka berkasnya, pasang profilnya, lalu **wajib** aktifkan di
Settings → General → About → Certificate Trust Settings. Tanpa langkah kedua
itu, profilnya terpasang tapi tidak dipercaya.

## Memakai sertifikat dari CA internal perusahaan

Ini pilihan terbaik: root CA-nya biasanya sudah terpasang di perangkat kantor,
jadi tidak ada satu pun perangkat yang perlu disetel manual.

Sertifikatnya ditaruh di `/srv/imago/certs/` pada VPS. Cara paling aman lewat
skrip, yang memeriksa dulu sebelum mengirim:

```bash
VPS_HOST=svr-app-prd-imago@10.30.12.65 \
  ./deploy/install-cert.sh ~/Downloads/imago.crt ~/Downloads/imago.key
```

Skrip itu menolak lebih awal bila berkasnya bukan PEM, bila kunci dan
sertifikatnya bukan sepasang, dan memperingatkan bila rantai perantaranya
hilang. Ia juga menampilkan nama yang dicakup sertifikat, supaya bisa kamu
cocokkan dengan `DOMAIN` di `.env`.

Manual, kalau lebih suka:

```bash
mkdir -p /srv/imago/certs && chmod 700 /srv/imago/certs
# salin imago.crt dan imago.key ke sana, lalu:
chmod 600 /srv/imago/certs/imago.key
# dan di .env:
#   TLS_MODE=/certs/imago.crt /certs/imago.key
```

### Formatnya harus PEM, dan harus rantai lengkap

Dua hal yang paling sering menggagalkan langkah ini.

**Kalau dapat `.pfx` atau `.p12`** (lazim dari CA Windows/AD), ubah dulu:

```bash
# leaf + seluruh rantai perantara, sekaligus
openssl pkcs12 -in imago.pfx -nokeys -nodes -out imago.crt

# kunci privat, tanpa sandi
openssl pkcs12 -in imago.pfx -nocerts -nodes -out imago.key
```

**Kalau dapat berkas terpisah** (leaf dan intermediate sendiri-sendiri),
gabungkan — leaf DULU, baru perantaranya:

```bash
cat leaf.crt intermediate.crt > imago.crt
```

Urutannya penting. Kalau hanya leaf-nya yang dipasang, browser desktop sering
tetap menerima karena sudah meng-cache perantaranya dari situs lain, tapi
**Android menolak** dan kameranya ikut mati — gejala yang menyesatkan karena
tampak seperti masalah aplikasi.

Periksa hasilnya sebelum dipakai:

```bash
openssl x509 -in imago.crt -noout -subject -dates
grep -c 'BEGIN CERTIFICATE' imago.crt    # harus >= 2 bila ada perantara
openssl rsa  -in imago.key -noout -check
```

Pastikan juga kunci dan sertifikatnya memang sepasang — keduanya harus
menghasilkan hash yang sama:

```bash
openssl x509 -in imago.crt -noout -modulus | openssl md5
openssl rsa  -in imago.key -noout -modulus | openssl md5
```

## Rilis berikutnya

```bash
VPS_HOST=root@1.2.3.4 ./deploy/deploy.sh
```

## Kalau ada yang salah

```bash
ssh root@1.2.3.4 'cd /srv/imago && docker compose logs -f caddy'
```

| Gejala | Sebab yang paling sering |
|---|---|
| Sertifikat tidak terbit | DNS belum mengarah, atau port 80 tertutup |
| Halaman terbuka, scanner diam | Dibuka lewat `http://` atau IP, bukan domain HTTPS |
| Kamera ditolak terus | Izin situs pernah diblokir — reset lewat ikon gembok di bilah alamat |
| Login Firebase gagal | Domain belum masuk Authorized domains (langkah 5) |
| Koin tidak pernah dikenali | `web/vendor/` kosong saat build — jalankan `bash tool/fetch_web_vendor.sh` (otomatis di `deploy.sh`) |
| `fetch_web_vendor.sh` berhenti: HASH TIDAK COCOK | Isi berkas di CDN berubah. JANGAN dilewati — selidiki dulu sebelum memperbarui hash |

## Keamanan (tindak lanjut pentest IMAGO, 4 Nov 2026)

- **Pustaka pihak ketiga disimpan sendiri.** model-viewer, MediaPipe (beserta
  WASM-nya), dan Firebase JS SDK diambil saat build oleh
  `tool/fetch_web_vendor.sh` ke `web/vendor/`, dengan SHA-256 yang dikunci.
  CanvasKit ikut di build (`--no-web-resources-cdn`). Font Outfit dibundel di
  aplikasi. Satu-satunya CDN yang tersisa adalah font cadangan engine Flutter
  (`fonts.gstatic.com`) untuk aksara non-Latin di pemilih bahasa.
- **CSP masih Report-Only.** Setelah diuji di HP (scan koin, model 3D, login
  admin) dan tidak ada pelanggaran di konsol, ubah nama header
  `Content-Security-Policy-Report-Only` di Caddyfile menjadi
  `Content-Security-Policy`.
- **Tidak ada fallback ke `index.html`.** Aplikasi memakai URL hash, jadi
  alamat yang tidak ada dibalas 404. Berkas bertitik dan `version.json` juga
  404.
- **`.env` tidak masuk git**, hanya `.env.example`.
| Deploy baru tapi tampilan lama | Harusnya tidak terjadi — aturan cache di Caddyfile mencegahnya. Kalau tetap, hapus data situs di browser |

## Soal batas Let's Encrypt

Volume `caddy_data` di `docker-compose.yml` menyimpan sertifikatnya. **Jangan
dihapus.** Let's Encrypt membatasi 5 sertifikat per domain per minggu; kalau
volume itu hilang di setiap restart, beberapa kali saja dan domainmu terkunci
sampai limitnya reset — biasanya tepat saat paling dibutuhkan.

`docker compose down` aman (volume bertahan). `docker compose down -v` yang
menghapusnya.

## Catatan ukuran

Hasil build ~55 MB di disk, tapi pengunjung tidak mengunduh semuanya: CanvasKit
punya beberapa varian dan browser hanya mengambil satu. Dengan kompresi zstd/gzip
yang sudah aktif, unduhan awal sekitar 10-15 MB — sebagian besarnya dua berkas
GLB. Kalau terasa lambat di jaringan seluler, yang paling berpengaruh adalah
mengompresi GLB-nya (`gltf-transform optimize`), bukan mengutak-atik server.
