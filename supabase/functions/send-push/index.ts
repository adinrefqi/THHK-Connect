// ============================================================================
// EDGE FUNCTION: send-push
// ----------------------------------------------------------------------------
// Pengirim push notification THHK Connect. Dipicu oleh Database Webhook saat
// terjadi perubahan pada:
//   - leave_requests     (UPDATE status)  -> notif ke SISWA pemilik izin
//   - bullying_reports   (INSERT)         -> notif ke semua perangkat role 'piket'
//   - delegated_tasks    (INSERT)         -> notif ke SISWA pada kelas terkait
//
// Mengirim ke Firebase Cloud Messaging memakai HTTP v1 API (OAuth2 via service
// account). Token perangkat diambil lewat RPC helper get_tokens_* (service_role).
//
// ENV YANG DIBUTUHKAN (Supabase > Edge Functions > Secrets):
//   SUPABASE_URL                  -> otomatis tersedia
//   SUPABASE_SERVICE_ROLE_KEY     -> otomatis tersedia
//   FCM_PROJECT_ID                -> project id Firebase (mis. "thhk-connect")
//   FCM_CLIENT_EMAIL              -> client_email dari service account JSON
//   FCM_PRIVATE_KEY               -> private_key dari service account JSON
//                                    (tempel apa adanya, termasuk baris BEGIN/END)
//
// DEPLOY:
//   supabase functions deploy send-push --no-verify-jwt
//   (--no-verify-jwt karena dipanggil oleh Database Webhook, bukan user login)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ----------------------------------------------------------------------------
// Konfigurasi target URL per channel (route dibuka di WebView saat notif diketuk)
// ----------------------------------------------------------------------------
const APP_BASE = "https://thhkconnect.vercel.app/";

interface PushMessage {
  tokens: string[];
  title: string;
  body: string;
  channel: string; // "izin" | "bullying" | "tugas"
  route: string; // mis. "/#riwayat"
}

// ----------------------------------------------------------------------------
// OAuth2: tukar service account jadi access token untuk FCM v1.
// Menandatangani JWT RS256 memakai WebCrypto (tanpa dependency eksternal).
// ----------------------------------------------------------------------------
async function getAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL")!;
  let privateKey = Deno.env.get("FCM_PRIVATE_KEY")!;
  // Secret sering tersimpan dengan "\n" literal; ubah jadi newline asli.
  privateKey = privateKey.replace(/\\n/g, "\n");

  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const header = enc({ alg: "RS256", typ: "JWT" });
  const payload = enc(claim);
  const unsigned = `${header}.${payload}`;

  // Impor private key PEM (PKCS#8) ke WebCrypto.
  const pemBody = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sigBuf = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${unsigned}.${sig}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth gagal: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.access_token as string;
}

// ----------------------------------------------------------------------------
// Kirim satu pesan ke banyak token via FCM v1 (per-token, kumpulkan kegagalan).
// Token yang ditolak (UNREGISTERED) dikembalikan agar bisa dibersihkan.
// ----------------------------------------------------------------------------
async function sendToFcm(msg: PushMessage): Promise<string[]> {
  if (msg.tokens.length === 0) return [];
  const projectId = Deno.env.get("FCM_PROJECT_ID")!;
  const accessToken = await getAccessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const staleTokens: string[] = [];

  await Promise.all(
    msg.tokens.map(async (token) => {
      const payload = {
        message: {
          token,
          notification: { title: msg.title, body: msg.body },
          data: {
            channel: msg.channel,
            route: msg.route,
            url: APP_BASE,
          },
          android: {
            priority: "high",
            notification: { channel_id: msg.channel },
          },
        },
      };
      const r = await fetch(url, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      if (!r.ok) {
        const errText = await r.text();
        // Token mati/terhapus -> tandai untuk dibersihkan.
        if (r.status === 404 || errText.includes("UNREGISTERED") || errText.includes("INVALID_ARGUMENT")) {
          staleTokens.push(token);
        }
        console.error(`FCM gagal (${r.status}) token=${token.slice(0, 12)}...: ${errText}`);
      }
    }),
  );

  return staleTokens;
}

// ----------------------------------------------------------------------------
// Handler utama: terima payload Database Webhook, tentukan sasaran, kirim.
// Format webhook Supabase: { type, table, record, old_record, schema }
// ----------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body = await req.json();
    const { type, table, record, old_record } = body;

    let msg: PushMessage | null = null;

    // -------------------------------------------------------------------------
    // A. leave_requests: status berubah -> notif ke siswa pemilik
    // -------------------------------------------------------------------------
    if (table === "leave_requests" && type === "UPDATE") {
      const statusBaru = record?.status;
      const statusLama = old_record?.status;
      if (statusBaru && statusBaru !== statusLama && record?.user_id) {
        const { data } = await supabase.rpc("get_tokens_for_user", { p_user_id: record.user_id });
        const tokens = (data ?? []).map((r: { token: string }) => r.token);
        const label = statusBaru === "APPROVED" ? "disetujui ✅" : statusBaru === "REJECTED" ? "ditolak ❌" : statusBaru;
        msg = {
          tokens,
          title: "Status Pengajuan Izin",
          body: `Pengajuan izin kamu telah ${label}.`,
          channel: "izin",
          route: "/#riwayat",
        };
      }
    }

    // -------------------------------------------------------------------------
    // B. bullying_reports: laporan baru -> notif ke semua perangkat 'piket'
    // -------------------------------------------------------------------------
    else if (table === "bullying_reports" && type === "INSERT") {
      const { data } = await supabase.rpc("get_tokens_for_role", { p_role: "piket" });
      const tokens = (data ?? []).map((r: { token: string }) => r.token);
      msg = {
        tokens,
        title: "Aduan Perundungan Baru ⚠️",
        body: `Ada laporan baru${record?.incident_location ? ` (Lokasi: ${record.incident_location})` : ""}. Segera tindak lanjuti.`,
        channel: "bullying",
        route: "/#bullying",
      };
    }

    // -------------------------------------------------------------------------
    // C. delegated_tasks: tugas baru -> notif ke siswa pada kelas terkait
    // -------------------------------------------------------------------------
    else if (table === "delegated_tasks" && type === "INSERT") {
      const kelas = record?.class_name;
      if (kelas) {
        const { data } = await supabase.rpc("get_tokens_for_kelas", { p_kelas: kelas });
        const tokens = (data ?? []).map((r: { token: string }) => r.token);
        msg = {
          tokens,
          title: "Tugas Titipan Baru 📚",
          body: `Ada tugas baru untuk kelas ${kelas}${record?.subject ? ` — ${record.subject}` : ""}.`,
          channel: "tugas",
          route: "/#tugas",
        };
      }
    }

    if (!msg) {
      return new Response(JSON.stringify({ skipped: true, reason: "Tidak ada notifikasi untuk event ini." }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const stale = await sendToFcm(msg);

    // Bersihkan token mati agar tabel tidak menumpuk token usang.
    if (stale.length > 0) {
      await supabase.from("device_tokens").delete().in("token", stale);
    }

    return new Response(
      JSON.stringify({ sent: msg.tokens.length - stale.length, removed: stale.length, channel: msg.channel }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
