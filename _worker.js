// AI-Xray Free Mode
// https://github.com/ScientificInternet/AI-Xray
// MIT License

import { connect } from 'cloudflare:sockets';

let cfgId = '';
let cfgRelay = '';

const WS_READY = 1;

export default {
  async fetch(request, env) {
    cfgId = env.UUID || cfgId;
    cfgRelay = env.RELAY || cfgRelay;
    if (!cfgId) return new Response('UUID not set', { status: 500 });

    const upgrade = request.headers.get('Upgrade');
    if (upgrade === 'websocket') {
      return handleStream(request);
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/+/, '');

    if (path === cfgId) {
      return buildConfigPage(request);
    }

    if (path === `sub/${cfgId}`) {
      return buildSubscription(request);
    }

    return renderDecoy();
  }
};

function renderDecoy() {
  return new Response(
    '<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>Service Running</h1><p>System operational.</p></body></html>',
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}

async function handleStream(request) {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept({ allowHalfOpen: true });

  // Decode early data from Sec-WebSocket-Protocol header
  const earlyProto = request.headers.get('sec-websocket-protocol') || '';
  let earlyData = null;
  if (earlyProto) {
    try {
      const raw = atob(earlyProto);
      earlyData = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i++) earlyData[i] = raw.charCodeAt(i);
    } catch (e) {
      earlyData = null;
    }
  }

  let headerDone = false;
  let tcpWriter = null;

  async function processChunk(chunk) {
    const data = new Uint8Array(chunk);

    if (!headerDone) {
      const parsed = parseHeader(data);
      if (parsed.error) {
        safeClose(server);
        return;
      }

      headerDone = true;
      const responseHeader = new Uint8Array([parsed.version, 0]);

      // Connect: try direct first, then relay
      let tcpSocket = null;
      try {
        tcpSocket = connect({ hostname: parsed.host, port: parsed.port });
        await tcpSocket.opened;
      } catch (e) {
        tcpSocket = null;
      }

      // Fallback to relay (direct TCP, NOT HTTP CONNECT)
      if (!tcpSocket && cfgRelay) {
        try {
          const relayHost = cfgRelay.split(':')[0];
          tcpSocket = connect({ hostname: relayHost, port: parsed.port });
          await tcpSocket.opened;
        } catch (e) {
          tcpSocket = null;
        }
      }

      if (!tcpSocket) {
        safeClose(server);
        return;
      }

      // Keep writer for the lifetime of the connection
      tcpWriter = tcpSocket.writable.getWriter();

      if (parsed.payload.byteLength > 0) {
        await tcpWriter.write(parsed.payload);
      }

      // Pipe TCP responses back to WebSocket
      pipeToWS(tcpSocket.readable, server, responseHeader);
    } else {
      if (tcpWriter) {
        await tcpWriter.write(data);
      }
    }
  }

  // Process early data first if present
  if (earlyData && earlyData.byteLength > 0) {
    await processChunk(earlyData.buffer);
  }

  server.addEventListener('message', async (event) => {
    try {
      await processChunk(event.data);
    } catch (e) {
      safeClose(server);
    }
  });

  server.addEventListener('close', () => {
    if (tcpWriter) tcpWriter.close().catch(() => {});
  });

  server.addEventListener('error', () => {
    if (tcpWriter) tcpWriter.abort().catch(() => {});
  });

  const responseHeaders = earlyProto
    ? { 'sec-websocket-protocol': earlyProto }
    : {};

  return new Response(null, {
    status: 101,
    webSocket: client,
    headers: responseHeaders,
  });
}

// [ver(1)][id(16)][optLen(1)][opt(N)][cmd(1)][port(2)][addrType(1)][addr(N)][payload...]
function parseHeader(buffer) {
  if (buffer.byteLength < 24) return { error: true };

  const version = buffer[0];
  const reqId = bytesToId(buffer.slice(1, 17));
  if (reqId !== cfgId) return { error: true };

  const optLen = buffer[17];
  const cmdIdx = 18 + optLen;
  if (cmdIdx >= buffer.byteLength) return { error: true };

  const cmd = buffer[cmdIdx];
  if (cmd !== 1) return { error: true }; // TCP only

  const portIdx = cmdIdx + 1;
  if (portIdx + 1 >= buffer.byteLength) return { error: true };
  const port = (buffer[portIdx] << 8) | buffer[portIdx + 1];

  const atIdx = portIdx + 2;
  if (atIdx >= buffer.byteLength) return { error: true };
  const addrType = buffer[atIdx];

  let host = '';
  let addrEnd = 0;

  switch (addrType) {
    case 1: {
      if (atIdx + 4 >= buffer.byteLength) return { error: true };
      host = `${buffer[atIdx + 1]}.${buffer[atIdx + 2]}.${buffer[atIdx + 3]}.${buffer[atIdx + 4]}`;
      addrEnd = atIdx + 5;
      break;
    }
    case 2: {
      const dLen = buffer[atIdx + 1];
      if (atIdx + 2 + dLen > buffer.byteLength) return { error: true };
      host = new TextDecoder().decode(buffer.slice(atIdx + 2, atIdx + 2 + dLen));
      addrEnd = atIdx + 2 + dLen;
      break;
    }
    case 3: {
      if (atIdx + 16 >= buffer.byteLength) return { error: true };
      const p = [];
      for (let i = 0; i < 8; i++) {
        p.push(((buffer[atIdx + 1 + i * 2] << 8) | buffer[atIdx + 1 + i * 2 + 1]).toString(16));
      }
      host = p.join(':');
      addrEnd = atIdx + 17;
      break;
    }
    default:
      return { error: true };
  }

  return { version, host, port, payload: buffer.slice(addrEnd), error: false };
}

async function pipeToWS(readable, ws, header) {
  let headerSent = false;
  try {
    const reader = readable.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (ws.readyState !== WS_READY) break;

      if (!headerSent) {
        const merged = new Uint8Array(header.byteLength + value.byteLength);
        merged.set(header, 0);
        merged.set(new Uint8Array(value), header.byteLength);
        ws.send(merged.buffer);
        headerSent = true;
      } else {
        ws.send(value);
      }
    }
  } catch (e) {}
  safeClose(ws);
}

function safeClose(ws) {
  try { if (ws.readyState <= 1) ws.close(); } catch (e) {}
}

function bytesToId(bytes) {
  const h = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`.toLowerCase();
}

// ==================== UI ====================

function buildConfigPage(request) {
  const host = request.headers.get('Host') || '';
  const link = buildLink(host);

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>AI-Xray</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:system-ui;max-width:640px;margin:40px auto;padding:0 20px;background:#0d1117;color:#e6edf3}
h1{font-size:20px;color:#58a6ff}
.box{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px;margin:16px 0;word-break:break-all;font-family:monospace;font-size:13px}
.label{font-size:12px;color:#8b949e;margin-bottom:8px}
button{background:#238636;color:#fff;border:none;padding:8px 16px;border-radius:6px;cursor:pointer;font-size:14px}
button:hover{background:#2ea043}
.ok{color:#3fb950;font-size:12px;display:none}
a{color:#58a6ff}
</style></head><body>
<h1>AI-Xray</h1>
<div class="label">Node Link</div>
<div class="box" id="link">${link}</div>
<button onclick="copy('link','c1')">Copy</button> <span class="ok" id="c1">Copied</span>
<br><br>
<div class="label">Subscription URL</div>
<div class="box" id="sub">https://${host}/sub/${cfgId}</div>
<button onclick="copy('sub','c2')">Copy</button> <span class="ok" id="c2">Copied</span>
<br><br>
<div class="label">Supported Clients</div>
<div class="box">
Windows: v2rayN, Clash Verge Rev<br>
macOS: Clash Verge Rev, V2rayU<br>
Android: v2rayNG, ClashMeta<br>
iOS: Shadowrocket, Stash<br>
OpenWrt: OpenClash, Passwall2
</div>
<script>
function copy(id,ok){navigator.clipboard.writeText(document.getElementById(id).textContent);var e=document.getElementById(ok);e.style.display='inline';setTimeout(()=>e.style.display='none',2000)}
</script>
</body></html>`;

  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

function buildSubscription(request) {
  const host = request.headers.get('Host') || '';
  const ua = (request.headers.get('User-Agent') || '').toLowerCase();
  const link = buildLink(host);

  if (ua.includes('clash') || ua.includes('mihomo') || ua.includes('stash')) {
    return new Response(buildClashConfig(host), {
      headers: {
        'Content-Type': 'text/yaml; charset=utf-8',
        'Content-Disposition': 'attachment; filename=ai-xray.yaml',
        'Profile-Update-Interval': '24',
      }
    });
  }

  return new Response(btoa(link), {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Subscription-Userinfo': 'upload=0; download=0; total=10737418240; expire=0',
      'Profile-Update-Interval': '24',
    }
  });
}

function buildLink(host) {
  return `vless://${cfgId}@${host}:443?encryption=none&security=tls&sni=${host}&fp=randomized&type=ws&host=${host}&path=%2F%3Fed%3D2048#AI-Xray-${host}`;
}

function buildClashConfig(host) {
  return `mixed-port: 7890
allow-lan: true
mode: rule
log-level: info

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query

proxies:
  - name: AI-Xray-${host}
    type: vless
    server: ${host}
    port: 443
    uuid: ${cfgId}
    network: ws
    tls: true
    udp: false
    sni: ${host}
    client-fingerprint: randomized
    ws-opts:
      path: /?ed=2048
      headers:
        Host: ${host}

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - AI-Xray-${host}
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
`;
}
