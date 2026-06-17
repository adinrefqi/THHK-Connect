// =============================================================================
// Cloudflare Worker: thhk-storage
// Deploy ini ke Worker "thhk-storage" di Cloudflare Dashboard
// 
// Binding R2 yang dibutuhkan:
//   Variable name: BUCKET
//   R2 bucket: thhk-connect
// =============================================================================

export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const corsHeaders = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
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
                const filename = url.searchParams.get('filename');
                if (!filename) {
                    return Response.json(
                        { success: false, error: 'Parameter filename diperlukan' },
                        { status: 400, headers: corsHeaders }
                    );
                }

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
                headers.set('Content-Type', object.httpMetadata?.contentType || 'application/octet-stream');
                headers.set('Cache-Control', 'public, max-age=31536000, immutable');

                return new Response(object.body, { headers });
            }

            // =================================================================
            // GET / — Health check + cek binding
            // =================================================================
            if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '')) {
                const bucket = env.LEAVE_ATTACHMENTS || env.BUCKET || env.R2_BUCKET || env.MY_BUCKET || env.THHK_BUCKET || env.r2;
                const bindings = Object.keys(env || {});
                return Response.json({
                    status: 'ok',
                    service: 'thhk-storage',
                    r2_connected: !!bucket,
                    env_bindings: bindings,
                    endpoints: ['POST /upload?filename=xxx', 'GET /file/{filename}']
                }, { headers: corsHeaders });
            }

            return Response.json(
                { error: 'Endpoint tidak ditemukan: ' + url.pathname },
                { status: 404, headers: corsHeaders }
            );

        } catch (err) {
            return Response.json(
                { success: false, error: err.message, stack: err.stack },
                { status: 500, headers: corsHeaders }
            );
        }
    }
};
