# 📱 Lucifax-PFS WhatsApp Auto-Sync Gateway (Baileys)

Microservice integrasi WhatsApp Web Multi-Device untuk menangkap chat pesanan dari Pak BC dan pelanggan secara otomatis tanpa copy-paste manual, khusus untuk role **Developer**.

---

## 🚀 Fitur Utama

1. **Jalur Perangkat Tertaut (Gratis 100% & Tanpa Biaya Bulanan WA API)**
   - Menggunakan `@whiskeysockets/baileys` yang menghubungkan sistem langsung ke WhatsApp Web via Scan QR.
   - Sesi tersimpan aman di folder `auth_info_baileys` (tidak perlu scan ulang setelah terhubung).

2. **Sinkronisasi Otomatis ke Firestore**
   - Setiap chat teks pesanan yang masuk otomatis dicatat ke koleksi `incoming_po_chats` dengan status `pending`.
   - Terintegrasi dengan pendeteksi kata kunci pesanan (`karton`, `ktn`, `dus`, `roll`, `beres`, `rolade`, dll).

3. **1-Klik ke AI PO Scanner di Aplikasi Kasir Lucifax-PFS**
   - Di menu Developer **WA Gateway Auto-PO**, terdapat daftar chat masuk real-time.
   - Tombol **🚀 Buka di AI PO Scanner** langsung membuka dialog scanner, menempelkan teks pesan, dan menjalankan analisa cerdas AI menjadi draf invoice PO secara instan.

4. **Web Dashboard & REST API Internal**
   - Dilengkapi dashboard web lokal di `http://localhost:3001` untuk memantau status, melihat QR code, atau merestart gateway.

---

## 🛠️ Cara Menjalankan

### 1. Jalankan di Komputer Lokal / Kasir
Buka terminal di folder proyek:
```bash
cd wa-gateway
npm start
```
Atau menggunakan mode auto-restart dev:
```bash
npm run dev
```

### 2. Hubungkan / Scan QR WhatsApp
1. Buka aplikasi Lucifax-PFS, login dengan akun ber-role **developer**.
2. Masuk ke menu **WA Gateway Auto-PO** (atau klik tombol **📱 WA Gateway** di menu Kamus & Otak AI).
3. Anda akan melihat QR Code WhatsApp di layar.
4. Buka WhatsApp di smartphone Anda:
   - Ketuk menu **Titik Tiga (⋮) > Perangkat Tertaut (Linked Devices)**.
   - Ketuk **Tautkan Perangkat (Link a Device)**.
   - Arahkan kamera ke QR Code di layar Lucifax-PFS.
5. Setelah berhasil, status akan berubah menjadi **TERHUBUNG** berwarna hijau neon dengan nomor telepon yang aktif.

---

## ⚙️ Konfigurasi Lingkungan (`.env`)

Salin file `.env.example` menjadi `.env`:
```env
PORT=3001

# Opsi Rekomendasi: Taruh file serviceAccountKey.json dari Firebase Console ke folder wa-gateway
# Atau isi email & password developer:
FIREBASE_USER_EMAIL=
FIREBASE_USER_PASSWORD=

# Filter nomor pengirim tertentu (kosongkan untuk menerima dari semua nomor):
TARGET_PHONE_NUMBERS=
```

---

## 🔄 Menjalankan di Server / Cloud (Opsional 24 Jam Non-Stop)
Jika ingin gateway berjalan 24 jam tanpa perlu membuka laptop kasir, jalankan menggunakan **PM2**:
```bash
npm install -g pm2
pm2 start server.js --name "lucifax-wa-gateway"
pm2 save
pm2 startup
```
