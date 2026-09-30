// =============================================================================
// Cloudflare Worker: thhk-storage
// Deploy ini ke Worker "thhk-storage" di Cloudflare Dashboard
// 
// Binding R2 yang dibutuhkan:
//   Variable name: BUCKET
//   R2 bucket: thhk-connect
// =============================================================================

// Supabase untuk verifikasi sesi upload (URL & anon key memang publik, sama
// dengan yang ada di index.html).
const SUPABASE_URL = 'https://tknvnlyxipxjkospcpbt.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrbnZubHl4aXB4amtvc3BjcGJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwOTYzOTksImV4cCI6MjA5NTY3MjM5OX0.lsZR2gsTFRqOwUqMMjBfMNP0zZFHTMPvTFC6BcXasG8';

// Token = token sesi staf (create_staff_session) atau siswa (create_student_session).
// Dicek ke server lewat RPC verify_upload_token (create_upload_sessions.sql).
async function isValidSessionToken(token) {
    if (!token) return false;
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/verify_upload_token`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            apikey: SUPABASE_ANON_KEY,
            Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({ p_token: token }),
    });
    return res.ok && (await res.json()) === true;
}

// Batas ukuran upload (foto HP ~3-5 MB, berkas tugas bisa lebih besar).
const MAX_UPLOAD_BYTES = 20 * 1024 * 1024;

// Hanya tipe ini yang ditampilkan langsung di browser. Tipe lain (HTML, SVG,
// JS, dll.) dipaksa diunduh agar bucket tidak bisa dipakai untuk hosting
// halaman phishing / XSS di domain workers.dev.
const INLINE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'];

// Nama file ditentukan server: awalan dari client disaring, lalu ditambah UUID,
// sehingga upload tidak pernah bisa menimpa file yang sudah ada.
function makeObjectKey(clientName) {
    const name = String(clientName || '');
    const dot = name.lastIndexOf('.');
    const ext = dot > 0 ? name.slice(dot + 1).toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 10) : '';
    const base = (dot > 0 ? name.slice(0, dot) : name).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 80);
    return (base ? base + '_' : '') + crypto.randomUUID() + (ext ? '.' + ext : '');
}

export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const corsHeaders = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Upload-Token',
        };

        // Handle CORS preflight
        if (request.method === 'OPTIONS') {
            return new Response(null, { status: 204, headers: corsHeaders });
        }

        try {
            // =================================================================
            // POST /upload?filename=xxx — Upload file ke R2
            // =================================================================
            if (request.method === 'POST' && url.pathname === '/upload') {
                // Cek sesi: header X-Upload-Token berisi token sesi staf/siswa.
                // Masa transisi: token bersama lama (Secret UPLOAD_TOKEN) masih diterima
                // selama Secret itu ada. Hapus Secret-nya untuk mematikan token bersama.
                const token = request.headers.get('X-Upload-Token') || '';
                const allowed = (env.UPLOAD_TOKEN && token === env.UPLOAD_TOKEN)
                    || await isValidSessionToken(token);
                if (!allowed) {
                    return Response.json(
                        { success: false, error: 'Sesi tidak valid atau kedaluwarsa. Silakan keluar lalu login ulang.' },
                        { status: 401, headers: corsHeaders }
                    );
                }

                const declaredSize = Number(request.headers.get('Content-Length') || 0);
                if (declaredSize > MAX_UPLOAD_BYTES) {
                    return Response.json(
                        { success: false, error: 'File terlalu besar (maks 20 MB).' },
                        { status: 413, headers: corsHeaders }
                    );
                }

                const filename = makeObjectKey(url.searchParams.get('filename'));

                // Cek R2 binding
                const bucket = env.LEAVE_ATTACHMENTS || env.BUCKET || env.R2_BUCKET || env.MY_BUCKET || env.THHK_BUCKET || env.r2;
                if (!bucket) {
                    return Response.json(
                        { success: false, error: 'R2 binding tidak ditemukan. Cek Settings > Variables > R2 Bucket Bindings.' },
                        { status: 500, headers: corsHeaders }
                    );
                }

                const body = await request.arrayBuffer();
                if (!body || body.byteLength === 0) {
                    return Response.json(
                        { success: false, error: 'Body kosong' },
                        { status: 400, headers: corsHeaders }
                    );
                }
                if (body.byteLength > MAX_UPLOAD_BYTES) {
                    return Response.json(
                        { success: false, error: 'File terlalu besar (maks 20 MB).' },
                        { status: 413, headers: corsHeaders }
                    );
                }

                const contentType = request.headers.get('Content-Type') || 'application/octet-stream';

                await bucket.put(filename, body, {
                    httpMetadata: { contentType },
                });

                const fileUrl = `${url.origin}/file/${encodeURIComponent(filename)}`;

                return Response.json(
                    { success: true, url: fileUrl, filename, size: body.byteLength },
                    { headers: corsHeaders }
                );
            }

            // =================================================================
            // GET /file/{filename} — Serve file dari R2
            // =================================================================
            if (request.method === 'GET' && url.pathname.startsWith('/file/')) {
                const filename = decodeURIComponent(url.pathname.slice(6)); // hapus "/file/"
                if (!filename) {
                    return Response.json(
                        { error: 'Filename kosong' },
                        { status: 400, headers: corsHeaders }
                    );
                }

                const bucket = env.LEAVE_ATTACHMENTS || env.BUCKET || env.R2_BUCKET || env.MY_BUCKET || env.THHK_BUCKET || env.r2;
                if (!bucket) {
                    return Response.json(
                        { error: 'R2 binding tidak ditemukan' },
                        { status: 500, headers: corsHeaders }
                    );
                }

                const object = await bucket.get(filename);
                if (!object) {
                    return Response.json(
                        { error: 'File tidak ditemukan: ' + filename },
                        { status: 404, headers: corsHeaders }
                    );
                }

                const headers = new Headers(corsHeaders);
                const storedType = (object.httpMetadata?.contentType || '').split(';')[0].trim().toLowerCase();
                if (INLINE_TYPES.includes(storedType)) {
                    headers.set('Content-Type', storedType);
                } else {
                    headers.set('Content-Type', 'application/octet-stream');
                    headers.set('Content-Disposition', 'attachment');
                }
                headers.set('X-Content-Type-Options', 'nosniff');
                headers.set('Cache-Control', 'public, max-age=31536000, immutable');

                return new Response(object.body, { headers });
            }

            // =================================================================
            // GET / — Health check + cek binding
            // =================================================================
            if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
                const bucket = env.LEAVE_ATTACHMENTS || env.BUCKET || env.R2_BUCKET || env.MY_BUCKET || env.THHK_BUCKET || env.r2;
                return Response.json({
                    status: 'ok',
                    service: 'thhk-storage',
                    r2_connected: !!bucket,
                    endpoints: ['POST /upload?filename=xxx', 'GET /file/{filename}']
                }, { headers: corsHeaders });
            }

            return Response.json(
                { error: 'Endpoint tidak ditemukan: ' + url.pathname },
                { status: 404, headers: corsHeaders }
            );

        } catch (err) {
            return Response.json(
                { success: false, error: err.message },
                { status: 500, headers: corsHeaders }
            );
        }
    }
};
