# Edge Function: send-push

Pengirim push notification THHK Connect (FCM HTTP v1). Dipicu oleh Database
Webhook saat `leave_requests` / `bullying_reports` / `delegated_tasks` berubah.

## Prasyarat
1. `setup_push_notif.sql` sudah dijalankan (tabel `device_tokens` + RPC helper).
2. Project Firebase sudah dibuat (yang sama dengan google-services.json di app Android).

---

## Langkah 1 — Ambil Service Account dari Firebase
1. Firebase Console > ⚙️ Project Settings > tab **Service accounts**.
2. Klik **Generate new private key** > unduh file JSON.
3. Dari JSON itu, catat tiga nilai: `project_id`, `client_email`, `private_key`.

## Langkah 2 — Set Secrets di Supabase
Supabase Dashboard > Edge Functions > **Secrets** (atau via CLI). Tambahkan:

```
FCM_PROJECT_ID    = <project_id dari JSON>
FCM_CLIENT_EMAIL  = <client_email dari JSON>
FCM_PRIVATE_KEY   = <private_key dari JSON, termasuk -----BEGIN/END PRIVATE KEY----->
```

> Catatan: `SUPABASE_URL` dan `SUPABASE_SERVICE_ROLE_KEY` otomatis tersedia, tidak perlu diisi.
> Untuk `FCM_PRIVATE_KEY`, tempel apa adanya. Function sudah menangani `\n` literal maupun newline asli.

Via CLI (alternatif):
```
supabase secrets set FCM_PROJECT_ID="thhk-connect"
supabase secrets set FCM_CLIENT_EMAIL="xxx@xxx.iam.gserviceaccount.com"
supabase secrets set FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

## Langkah 3 — Deploy Function
```
supabase functions deploy send-push --no-verify-jwt
```
`--no-verify-jwt` wajib: function dipanggil Database Webhook, bukan user yang login.

## Langkah 4 — Buat Database Webhooks
Supabase Dashboard > Database > **Webhooks** > Create. Buat **3 webhook**, semua
mengarah ke function `send-push` (HTTP POST, tipe "Supabase Edge Functions").

| Nama          | Table              | Events  | Keterangan                          |
|---------------|--------------------|---------|-------------------------------------|
| push_izin     | `leave_requests`   | UPDATE  | Notif status izin ke siswa          |
| push_bullying | `bullying_reports` | INSERT  | Notif aduan baru ke piket           |
| push_tugas    | `delegated_tasks`  | INSERT  | Notif tugas baru ke siswa per-kelas |

Setiap webhook mengirim payload `{ type, table, record, old_record }` yang sudah
ditangani function. Tidak perlu header khusus (function memakai service_role internal).

---

## Uji coba
1. Pastikan minimal satu perangkat sudah mendaftar token (login di app Android).
2. Trigger salah satu event, mis. ubah status sebuah baris `leave_requests` lewat
   SQL Editor:
   ```sql
   UPDATE public.leave_requests SET status = 'APPROVED' WHERE id = '<id>';
   ```
3. Cek **Edge Functions > Logs**: harus muncul `{ sent: N, removed: M, channel: 'izin' }`.
4. Notifikasi muncul di HP.

## Troubleshooting
- **OAuth gagal 401/400**: `FCM_CLIENT_EMAIL`/`FCM_PRIVATE_KEY` salah atau private key
  rusak (pastikan baris BEGIN/END utuh).
- **sent: 0**: belum ada token untuk sasaran itu (siswa belum login di app, atau role/kelas tidak cocok).
- **FCM 404 / UNREGISTERED**: token mati — function otomatis menghapusnya dari `device_tokens`.
- **Webhook tidak memicu**: cek tab Webhooks > Logs; pastikan event (INSERT/UPDATE) & table benar.

## Channel notifikasi (harus cocok dengan app Android)
Field `channel` di payload menentukan NotificationChannel di app:
`izin`, `bullying`, `tugas`. Pastikan app membuat channel dengan id yang sama.
