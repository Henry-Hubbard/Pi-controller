// DEXI Dash server. Zero dependencies: serves the dashboard and two small
// JSON endpoints that read host state. Run with --network host --pid=host so
// /proc, /sys and the network interfaces it reads belong to the drone.
'use strict';

const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = Number(process.env.PORT || 80);
const PUBLIC = path.join(__dirname, 'public');

const HEAD = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' +
  '<style>[hidden]{display:none!important}body{margin:0}</style></head><body>';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json', '.ico': 'image/x-icon',
};

function readText(file) {
  try { return fs.readFileSync(file, 'utf8').trim(); } catch { return null; }
}

// ---- CPU usage, sampled once a second from /proc/stat ----
let lastCpu = null;
let cpuPercent = null;
let cpuHistory = [];
function sampleCpu() {
  const line = readText('/proc/stat');
  if (!line) return;
  const f = line.split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
  const idle = f[3] + (f[4] || 0);
  const total = f.reduce((a, b) => a + b, 0);
  if (lastCpu) {
    const dt = total - lastCpu.total;
    const di = idle - lastCpu.idle;
    if (dt > 0) {
      cpuPercent = Math.round((1 - di / dt) * 1000) / 10;
      cpuHistory.push(cpuPercent);
      if (cpuHistory.length > 60) cpuHistory.shift();
    }
  }
  lastCpu = { total, idle };
}
sampleCpu();
setInterval(sampleCpu, 1000).unref();

function memInfo() {
  const txt = readText('/proc/meminfo') || '';
  const get = (k) => { const m = txt.match(new RegExp('^' + k + ':\\s+(\\d+)', 'm')); return m ? Number(m[1]) * 1024 : null; };
  const total = get('MemTotal') ?? os.totalmem();
  const avail = get('MemAvailable') ?? os.freemem();
  return { total, used: total - avail };
}

function tempC() {
  const raw = readText('/sys/class/thermal/thermal_zone0/temp');
  return raw ? Math.round(Number(raw) / 100) / 10 : null;
}

function disk() {
  try {
    const s = fs.statfsSync('/');
    const total = s.blocks * s.bsize;
    return { total, used: total - s.bavail * s.bsize };
  } catch { return null; }
}

function wifi() {
  // /proc/net/wireless: "wlan0: 0000   54.  -56.  -256 ..."
  const txt = readText('/proc/net/wireless') || '';
  const m = txt.match(/wlan0:\s+\S+\s+([\d.]+)\s+(-?[\d.]+)/);
  return m ? { link: Number(m[1]), signalDbm: Number(m[2]) } : null;
}

function addresses() {
  const out = [];
  for (const [name, list] of Object.entries(os.networkInterfaces())) {
    if (name === 'lo' || name.startsWith('docker') || name.startsWith('veth') || name.startsWith('br-')) continue;
    for (const a of list || []) if (a.family === 'IPv4' && !a.internal) out.push({ iface: name, ip: a.address });
  }
  return out;
}

function system() {
  const up = Number((readText('/proc/uptime') || '0').split(' ')[0]);
  return {
    hostname: readText('/etc/hostname') || os.hostname(),
    cpu: { percent: cpuPercent, history: cpuHistory, cores: os.cpus().length },
    load: os.loadavg(),
    memory: memInfo(),
    temperatureC: tempC(),
    disk: disk(),
    uptimeSec: Math.round(up),
    wifi: wifi(),
    addresses: addresses(),
  };
}

function version() {
  return {
    os: readText('/etc/dexi-version'),
    platform: readText('/etc/dexi-platform'),
    model: (readText('/etc/device-model') || '').replace(/\0/g, '') || null,
  };
}

function sendJson(res, body) {
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/api/system') return sendJson(res, system());
  if (url.pathname === '/api/version') return sendJson(res, version());

  let rel = url.pathname === '/' ? '/app.html' : decodeURIComponent(url.pathname);
  const file = path.join(PUBLIC, path.normalize(rel).replace(/^(\.\.[/\\])+/, ''));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('Not found'); }
    const ext = path.extname(file);
    res.writeHead(200, { 'Content-Type': TYPES[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    // app.html is written as a page fragment (so the same file can be published
    // as a demo); give it a proper document shell when serving it here.
    if (ext === '.html' && !/^\s*<!doctype/i.test(data.toString('utf8', 0, 64))) {
      res.end(HEAD + data.toString('utf8') + '</body></html>');
    } else {
      res.end(data);
    }
  });
}).listen(PORT, '0.0.0.0', () => console.log(`DEXI Dash on :${PORT}`));
