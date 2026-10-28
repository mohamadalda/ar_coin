# Deploy IMAGO Web ke VPS

Caddy di dalam Docker, melayani hasil `flutter build web` sebagai berkas statis,
dengan sertifikat HTTPS yang terbit dan diperpanjang sendiri.

**HTTPS wajib, bukan opsional.** `getUserMedia` hanya tersedia di konteks aman.
Dibuka lewat `http://` atau lewat alamat IP, IMAGO tetap tampil rapi — tapi
scanner-nya mati total tanpa pesan yang jelas.

## Sekali di awal

**1. Pastikan DNS sudah mengarah.** Record `A` domain/subdomainmu harus menunjuk
ke IP VPS **sebelum** container dinyalakan. Caddy membuktikan kepemilikan domain
lewat HTTP, dan pembuktian itu gagal kalau DNS-nya belum sampai.

```bash
dig +short imago.domainmu.com     # harus keluar IP VPS-mu
```

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
| Koin tidak pernah dikenali | MediaPipe diambil dari CDN; perlu internet di perangkat |
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
