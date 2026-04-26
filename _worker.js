// AI-Xray Free Mode - Cloudflare Workers/Pages
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

// Decoy page - looks like a normal site
function renderDecoy() {
  return new Response(
    '<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>Service Running</h1><p>System operational.</p></body></html>',
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}

// Handle WebSocket stream
async function handleStream(request) {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();

  let headerDone = false;
  let targetHost = '';
  let targetPort = 0;
  let tcpSocket = null;
  let responseHeader = null;

  const readableStream = new ReadableStream({
    start(controller) {
      server.addEventListener('message', (event) => {
        controller.enqueue(event.data);
      });
      server.addEventListener('close', () => {
        controller.close();
      });
      server.addEventListener('error', (err) => {
        controller.error(err);
      });
    },
    cancel() {
      safeClose(server);
    }
  });

  const writer = new WritableStream({
    async write(chunk) {
      if (!headerDone) {
        const parsed = parseHeader(new Uint8Array(chunk));
        if (parsed.error) {
          safeClose(server);
          return;
        }

        headerDone = true;
        targetHost = parsed.host;
        targetPort = parsed.port;
        responseHeader = new Uint8Array([parsed.version, 0]);

        const payload = parsed.payload;

        // Try direct connection first, then relay
        tcpSocket = await connectTarget(targetHost, targetPort);

        if (!tcpSocket) {
          safeClose(server);
          return;
        }

        const tcpWriter = tcpSocket.writable.getWriter();

        // Send initial payload
        if (payload.byteLength > 0) {
          await tcpWriter.write(payload);
        }
        tcpWriter.releaseLock();

        // Pipe TCP responses back to WebSocket
        pipeToWS(tcpSocket.readable, server, responseHeader);
      } else {
        // Subsequent messages - relay directly to TCP
        if (tcpSocket) {
          const tcpWriter = tcpSocket.writable.getWriter();
          await tcpWriter.write(chunk);
          tcpWriter.releaseLock();
        }
      }
    },
    close() {
      if (tcpSocket) {
        safeClose(server);
      }
    },
    abort() {
      if (tcpSocket) {
        safeClose(server);
      }
    }
  });

  readableStream.pipeTo(writer).catch(() => {
    safeClose(server);
  });

  return new Response(null, { status: 101, webSocket: client });
}

// Parse protocol header
// Format: [version(1)] [uuid(16)] [optLen(1)] [opt(N)] [cmd(1)] [port(2)] [addrType(1)] [addr(N)] [payload...]
function parseHeader(buffer) {
  if (buffer.byteLength < 24) {
    return { error: true };
  }

  const version = buffer[0];

  // Validate UUID
  const reqId = formatUUID(buffer.slice(1, 17));
  if (reqId !== cfgId) {
    return { error: true };
  }

  const optLen = buffer[17];
  const cmd = buffer[18 + optLen];

  // Only support TCP (cmd=1)
  if (cmd !== 1) {
    return { error: true };
  }

  const portStart = 18 + optLen + 1;
  const port = (buffer[portStart] << 8) | buffer[portStart + 1];

  const addrType = buffer[portStart + 2];
  let host = '';
  let addrEnd = 0;

  switch (addrType) {
    case 1: // IPv4
      host = `${buffer[portStart + 3]}.${buffer[portStart + 4]}.${buffer[portStart + 5]}.${buffer[portStart + 6]}`;
      addrEnd = portStart + 7;
      break;
    case 2: // Domain
      const domainLen = buffer[portStart + 3];
      host = new TextDecoder().decode(buffer.slice(portStart + 4, portStart + 4 + domainLen));
      addrEnd = portStart + 4 + domainLen;
      break;
    case 3: // IPv6
      const ipv6Parts = [];
      for (let i = 0; i < 8; i++) {
        ipv6Parts.push(((buffer[portStart + 3 + i * 2] << 8) | buffer[portStart + 3 + i * 2 + 1]).toString(16));
      }
      host = ipv6Parts.join(':');
      addrEnd = portStart + 19;
      break;
    default:
      return { error: true };
  }

  const payload = buffer.slice(addrEnd);

  return { version, host, port, payload, error: false };
}

// Connect to target, with relay fallback
async function connectTarget(host, port) {
  // Try direct connection
  try {
    const sock = connect({ hostname: host, port: port });
    const info = await sock.opened;
    return sock;
  } catch (e) {
    // Direct connection failed
  }

  // Try relay if configured
  if (cfgRelay) {
    try {
      const [relayHost, relayPort] = parseRelay(cfgRelay);
      const sock = connect({ hostname: relayHost, port: relayPort || 443 });
      await sock.opened;

      // Send actual target info through relay
      const connectCmd = `CONNECT ${host}:${port} HTTP/1.1\r\nHost: ${host}:${port}\r\n\r\n`;
      const writer = sock.writable.getWriter();
      await writer.write(new TextEncoder().encode(connectCmd));
      writer.releaseLock();

      // Read relay response
      const reader = sock.readable.getReader();
      const { value } = await reader.read();
      reader.releaseLock();

      const response = new TextDecoder().decode(value);
      if (response.includes('200')) {
        return sock;
      }
    } catch (e) {
      // Relay also failed
    }
  }

  return null;
}

function parseRelay(relay) {
  const match = (relay || '').match(/^(.*?)(?::(\d+))?$/);
  return [match ? match[1] : relay, match ? parseInt(match[2]) : 443];
}

// Pipe TCP readable stream to WebSocket
async function pipeToWS(readable, ws, header) {
  let headerSent = false;

  try {
    const reader = readable.getReader();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      if (ws.readyState !== WS_READY) break;

      if (!headerSent) {
        // Prepend response header to first chunk
        const merged = new Uint8Array(header.byteLength + value.byteLength);
        merged.set(header, 0);
        merged.set(new Uint8Array(value), header.byteLength);
        ws.send(merged.buffer);
        headerSent = true;
      } else {
        ws.send(value);
      }
    }
  } catch (e) {
    // Stream error
  }

  safeClose(ws);
}

// Safe WebSocket close
function safeClose(ws) {
  try {
    if (ws.readyState === WS_READY || ws.readyState === 2) {
      ws.close();
    }
  } catch (e) {
    // Already closed
  }
}

// Format UUID from bytes
function formatUUID(bytes) {
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`.toLowerCase();
}

// Build config page
function buildConfigPage(request) {
  const host = request.headers.get('Host') || '';
  const link = buildLink(host);

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>AI-Xray Config</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:system-ui;max-width:640px;margin:40px auto;padding:0 20px;background:#0d1117;color:#e6edf3}
h1{font-size:20px;color:#58a6ff}
.box{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px;margin:16px 0;word-break:break-all;font-family:monospace;font-size:13px}
.label{font-size:12px;color:#8b949e;margin-bottom:8px}
button{background:#238636;color:#fff;border:none;padding:8px 16px;border-radius:6px;cursor:pointer;font-size:14px}
button:hover{background:#2ea043}
a{color:#58a6ff}
</style></head><body>
<h1>AI-Xray</h1>
<div class="label">Node Link</div>
<div class="box" id="link">${link}</div>
<button onclick="navigator.clipboard.writeText(document.getElementById('link').textContent)">Copy Link</button>
<br><br>
<div class="label">Subscription (Clash / V2rayN / Shadowrocket)</div>
<div class="box"><a href="https://${host}/sub/${cfgId}">https://${host}/sub/${cfgId}</a></div>
<br>
<div class="label">Supported Clients</div>
<div class="box">
Windows: v2rayN, Clash Verge Rev<br>
macOS: Clash Verge Rev, V2rayU<br>
Android: v2rayNG, ClashMeta<br>
iOS: Shadowrocket, Stash<br>
OpenWrt: OpenClash, Passwall2
</div>
</body></html>`;

  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' }
  });
}

// Build subscription response
function buildSubscription(request) {
  const host = request.headers.get('Host') || '';
  const ua = (request.headers.get('User-Agent') || '').toLowerCase();
  const link = buildLink(host);

  // Clash format
  if (ua.includes('clash') || ua.includes('mihomo')) {
    const clash = buildClashConfig(host);
    return new Response(clash, {
      headers: {
        'Content-Type': 'text/yaml; charset=utf-8',
        'Content-Disposition': 'attachment; filename=ai-xray.yaml'
      }
    });
  }

  // Default: base64 encoded links (v2rayN, Shadowrocket, etc.)
  const encoded = btoa(link);
  return new Response(encoded, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Subscription-Userinfo': 'upload=0; download=0; total=10737418240; expire=0'
    }
  });
}

// Build node link
function buildLink(host) {
  return `vless://${cfgId}@${host}:443?encryption=none&security=tls&sni=${host}&fp=randomized&type=ws&host=${host}&path=%2F%3Fed%3D2048#AI-Xray-${host}`;
}

// Build Clash/Mihomo config
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
