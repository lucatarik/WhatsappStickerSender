/**
 * Cloudflare Worker - CORS Proxy per WhatsApp API
 * 
 * Deploy: wrangler deploy
 * Uso:    https://mediavault.lucatarik.workers.dev/?url=http://192.168.1.1:3000/user/info
 * 
 * Gestisce CORS headers, forward di richieste GET/POST/PUT/DELETE
 * e supporta multipart/form-data per l'upload di immagini sticker.
 */

const ALLOWED_ORIGINS = [
  'https://lucatarik.github.io',  // GitHub Pages
  'http://localhost:3000',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
];

// Se vuoi permettere qualsiasi origine (meno sicuro)
const ALLOW_ALL_ORIGINS = true;

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return handleCORS(request);
    }

    const url = new URL(request.url);
    const targetUrl = url.searchParams.get('url');

    if (!targetUrl) {
      return new Response(JSON.stringify({
        error: 'Missing ?url= parameter',
        usage: 'GET/POST /?url=<encoded_target_url>',
        example: '/?url=http%3A%2F%2F192.168.1.1%3A3000%2Fuser%2Finfo'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(request) }
      });
    }

    try {
      // Validazione URL target
      const target = new URL(targetUrl);

      // Blocca richieste a URL pericolosi
      const blockedHosts = ['metadata.google', '169.254.169.254', 'localhost'];
      if (blockedHosts.some(h => target.hostname.includes(h))) {
        return new Response('Blocked', { status: 403, headers: corsHeaders(request) });
      }

      // Forward della richiesta
      const headers = new Headers();

      // Copia header rilevanti dalla richiesta originale
      const forwardHeaders = [
        'content-type', 'authorization', 'accept',
        'x-requested-with', 'user-agent'
      ];

      for (const h of forwardHeaders) {
        if (request.headers.has(h)) {
          headers.set(h, request.headers.get(h));
        }
      }

      const fetchOpts = {
        method: request.method,
        headers: headers,
      };

      // Forward body per POST/PUT/PATCH
      if (['POST', 'PUT', 'PATCH'].includes(request.method)) {
        fetchOpts.body = request.body;
        // Duplex per streaming body
        fetchOpts.duplex = 'half';
      }

      const response = await fetch(targetUrl, fetchOpts);

      // Crea risposta con CORS headers
      const responseHeaders = new Headers(response.headers);
      const cors = corsHeaders(request);
      for (const [k, v] of Object.entries(cors)) {
        responseHeaders.set(k, v);
      }

      // Rimuovi header che possono causare problemi
      responseHeaders.delete('x-frame-options');
      responseHeaders.delete('content-security-policy');

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders
      });

    } catch (err) {
      return new Response(JSON.stringify({
        error: 'Proxy error',
        message: err.message,
        target: targetUrl
      }), {
        status: 502,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(request) }
      });
    }
  }
};

function corsHeaders(request) {
  const origin = request.headers.get('Origin') || '*';
  const allowedOrigin = ALLOW_ALL_ORIGINS ? '*' :
    (ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]);

  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept, X-Requested-With',
    'Access-Control-Max-Age': '86400',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Type',
  };
}

function handleCORS(request) {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(request)
  });
}
