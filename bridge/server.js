// WA Legacy bridge: links to WhatsApp as a "linked device" (QR login, like WhatsApp Web)
// and exposes a small HTTP/JSON API for a legacy iOS app. Needs ffmpeg in PATH for media.
import makeWASocket, { useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, downloadMediaMessage } from '@whiskeysockets/baileys';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import QRCode from 'qrcode';
import pino from 'pino';

const PORT = Number(process.env.PORT || 3000);
const TOKEN = process.env.BRIDGE_TOKEN || '';
const AUTH_DIR = 'auth';
const CACHE_DIR = 'cache';
const MAX_UPLOAD = 60 * 1024 * 1024;
const logger = pino({ level: 'silent' });
fs.mkdirSync(CACHE_DIR, { recursive: true });

const state = { status: 'connecting', qr: null, me: null };
const names = new Map();     // jid -> display name
const chats = new Map();     // jid -> { jid, lastTs, last }
const messages = new Map();  // jid -> [message summaries]
const raw = new Map();       // message id -> raw media message (for downloads)
const inflight = new Map();  // message id -> Promise (media being prepared)
let sock = null;

const EXT = { image: 'jpg', video: 'mp4', audio: 'm4a' };
const MIME = { image: 'image/jpeg', video: 'video/mp4', audio: 'audio/mp4' };

// ---------- helpers ----------

function ffmpeg(args) {
  return new Promise((resolve, reject) => {
    execFile('ffmpeg', ['-y', '-loglevel', 'error', ...args], { timeout: 240000 }, (err, _out, stderr) =>
      err ? reject(new Error(stderr || err.message)) : resolve());
  });
}

function unwrap(msg) {
  let c = msg.message;
  while (c) {
    if (c.ephemeralMessage) c = c.ephemeralMessage.message;
    else if (c.viewOnceMessage) c = c.viewOnceMessage.message;
    else if (c.viewOnceMessageV2) c = c.viewOnceMessageV2.message;
    else if (c.documentWithCaptionMessage) c = c.documentWithCaptionMessage.message;
    else break;
  }
  return c;
}

function describe(m) {
  const c = unwrap(m);
  if (!c) return null;
  if (c.conversation) return { kind: 'text', text: c.conversation };
  if (c.extendedTextMessage?.text) return { kind: 'text', text: c.extendedTextMessage.text };
  if (c.imageMessage) return { kind: 'image', text: c.imageMessage.caption || '' };
  if (c.videoMessage) return { kind: 'video', text: c.videoMessage.caption || '', seconds: c.videoMessage.seconds || 0 };
  if (c.audioMessage) return { kind: 'audio', text: '', seconds: c.audioMessage.seconds || 0 };
  if (c.documentMessage) return { kind: 'doc', text: c.documentMessage.fileName || 'document' };
  if (c.stickerMessage) return { kind: 'sticker', text: '' };
  return null;
}

function mediaNode(m) {
  const c = unwrap(m);
  return c?.imageMessage || c?.videoMessage || c?.audioMessage || null;
}

function label(d) {
  switch (d.kind) {
    case 'text': return d.text;
    case 'image': return d.text ? 'Photo: ' + d.text : 'Photo';
    case 'video': return 'Video';
    case 'audio': return 'Voice message';
    case 'doc': return 'Document: ' + d.text;
    default: return 'Sticker';
  }
}

function addMessage(m) {
  const jid = m.key?.remoteJid;
  if (!jid || jid === 'status@broadcast') return;
  const d = describe(m);
  if (!d) return;
  const id = m.key.id;
  const list = messages.get(jid) || [];
  if (list.some((x) => x.id === id)) return;
  const ts = Number(m.messageTimestamp || 0);
  const node = mediaNode(m);
  list.push({
    id, fromMe: !!m.key.fromMe, kind: d.kind, text: d.text, seconds: Number(d.seconds || 0),
    ts, author: m.pushName || '', hasThumb: !!node?.jpegThumbnail?.length,
  });
  list.sort((a, b) => a.ts - b.ts);
  if (list.length > 200) list.splice(0, list.length - 200);
  messages.set(jid, list);

  if (node) {
    raw.set(id, m);
    if (raw.size > 400) raw.delete(raw.keys().next().value);
  }

  const prev = chats.get(jid);
  if (!prev || ts >= prev.lastTs) chats.set(jid, { jid, lastTs: ts, last: label(d) });
  if (!m.key.fromMe && m.pushName && !jid.endsWith('@g.us') && !names.has(jid)) names.set(jid, m.pushName);
  if (jid.endsWith('@g.us') && !names.has(jid) && sock) {
    sock.groupMetadata(jid).then((g) => names.set(jid, g.subject)).catch(() => {});
  }
}

// Downloads a media message and converts it into something iOS 6-9 can play. Cached on disk.
function ensureFull(id) {
  const m = raw.get(id);
  if (!m) return Promise.reject(new Error('unknown message'));
  const d = describe(m);
  const ext = EXT[d.kind];
  if (!ext) return Promise.reject(new Error('not a media message'));
  const out = path.join(CACHE_DIR, `${id}.${ext}`);
  if (fs.existsSync(out)) return Promise.resolve({ file: out, kind: d.kind });
  if (inflight.has(id)) return inflight.get(id);

  const p = (async () => {
    const buf = await downloadMediaMessage(m, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
    const src = path.join(CACHE_DIR, `${id}.src`);
    const tmp = path.join(CACHE_DIR, `${id}.tmp.${ext}`);
    fs.writeFileSync(src, buf);
    try {
      if (d.kind === 'image') {
        await ffmpeg(['-i', src, '-frames:v', '1', '-vf', "scale='min(1024,iw)':-2", '-q:v', '4', tmp]);
      } else if (d.kind === 'video') {
        await ffmpeg(['-i', src, '-vf', "scale=-2:'min(480,trunc(ih/2)*2)'", '-c:v', 'libx264', '-profile:v', 'baseline',
          '-level', '3.0', '-pix_fmt', 'yuv420p', '-preset', 'veryfast', '-crf', '28', '-c:a', 'aac', '-b:a', '64k',
          '-movflags', '+faststart', tmp]);
      } else {
        await ffmpeg(['-i', src, '-vn', '-c:a', 'aac', '-b:a', '48k', '-ac', '1', tmp]);
      }
      fs.renameSync(tmp, out);
    } finally {
      fs.rmSync(src, { force: true });
      fs.rmSync(tmp, { force: true });
    }
    return { file: out, kind: d.kind };
  })().finally(() => inflight.delete(id));

  inflight.set(id, p);
  return p;
}

async function getThumb(id) {
  const m = raw.get(id);
  if (!m) throw new Error('unknown message');
  const t = mediaNode(m)?.jpegThumbnail;
  if (t?.length) return { buffer: typeof t === 'string' ? Buffer.from(t, 'base64') : Buffer.from(t) };
  const d = describe(m);
  const full = await ensureFull(id);
  if (d.kind === 'image') return { file: full.file };
  if (d.kind === 'video') {
    const thumb = path.join(CACHE_DIR, `${id}.thumb.jpg`);
    if (!fs.existsSync(thumb)) await ffmpeg(['-ss', '0.5', '-i', full.file, '-frames:v', '1', '-vf', 'scale=240:-2', thumb]);
    return { file: thumb };
  }
  throw new Error('no thumbnail');
}

// ---------- HTTP ----------

function send(res, code, body, type = 'application/json') {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}

// Serves a file with HTTP Range support (iOS media players require it).
function serveFile(req, res, file, type) {
  const size = fs.statSync(file).size;
  const range = req.headers.range;
  if (range) {
    const match = /bytes=(\d*)-(\d*)/.exec(range);
    const start = match && match[1] ? parseInt(match[1], 10) : 0;
    let end = match && match[2] ? parseInt(match[2], 10) : size - 1;
    if (Number.isNaN(start) || start >= size) {
      res.writeHead(416, { 'Content-Range': `bytes */${size}` });
      return res.end();
    }
    end = Math.min(end, size - 1);
    res.writeHead(206, {
      'Content-Type': type, 'Accept-Ranges': 'bytes',
      'Content-Range': `bytes ${start}-${end}/${size}`, 'Content-Length': end - start + 1,
    });
    return fs.createReadStream(file, { start, end }).pipe(res);
  }
  res.writeHead(200, { 'Content-Type': type, 'Accept-Ranges': 'bytes', 'Content-Length': size });
  fs.createReadStream(file).pipe(res);
}

function readJSON(req) {
  return readRaw(req, 1e5).then((b) => { try { return JSON.parse(b.toString() || '{}'); } catch { return {}; } });
}

function readRaw(req, limit) {
  return new Promise((resolve, reject) => {
    const parts = [];
    let total = 0;
    req.on('data', (c) => {
      total += c.length;
      if (total > limit) { reject(new Error('too large')); req.destroy(); return; }
      parts.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(parts)));
    req.on('error', reject);
  });
}

const validId = (s) => typeof s === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(s);

async function handleSendMedia(req, res, url) {
  const jid = url.searchParams.get('jid');
  const kind = url.searchParams.get('kind');
  const seconds = Number(url.searchParams.get('seconds') || 0);
  if (!jid || !EXT[kind] || state.status !== 'open') return send(res, 400, { error: 'bad request or not connected' });

  const body = await readRaw(req, MAX_UPLOAD);
  const stamp = `up-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const src = path.join(CACHE_DIR, `${stamp}.src`);
  const out = path.join(CACHE_DIR, `${stamp}.${kind === 'audio' ? 'ogg' : 'mp4'}`);
  fs.writeFileSync(src, body);
  try {
    let content;
    if (kind === 'image') {
      content = { image: body };
    } else if (kind === 'video') {
      try {
        await ffmpeg(['-i', src, '-c', 'copy', '-movflags', '+faststart', '-f', 'mp4', out]); // fast remux
      } catch {
        await ffmpeg(['-i', src, '-vf', "scale=-2:'min(720,trunc(ih/2)*2)'", '-c:v', 'libx264', '-preset', 'veryfast',
          '-crf', '27', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', out]);
      }
      content = { video: fs.readFileSync(out), mimetype: 'video/mp4' };
    } else {
      await ffmpeg(['-i', src, '-vn', '-c:a', 'libopus', '-b:a', '32k', '-ar', '48000', '-ac', '1', '-f', 'ogg', out]);
      content = { audio: fs.readFileSync(out), ptt: true, mimetype: 'audio/ogg; codecs=opus', seconds: Math.round(seconds) };
    }
    const sent = await sock.sendMessage(jid, content);
    // keep a locally playable copy so our own messages open instantly
    const target = path.join(CACHE_DIR, `${sent.key.id}.${EXT[kind]}`);
    fs.copyFileSync(kind === 'video' ? out : src, target);
    addMessage(sent);
    send(res, 200, { ok: true });
  } finally {
    fs.rmSync(src, { force: true });
    fs.rmSync(out, { force: true });
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (TOKEN && (url.searchParams.get('key') || req.headers['x-token']) !== TOKEN) return send(res, 401, { error: 'unauthorized' });

  try {
    if (url.pathname === '/status') return send(res, 200, { status: state.status, me: state.me });

    if (url.pathname === '/qr.png') {
      if (!state.qr) return send(res, 404, { error: 'no qr' });
      return send(res, 200, await QRCode.toBuffer(state.qr, { width: 280, margin: 2 }), 'image/png');
    }

    if (url.pathname === '/chats') {
      const out = [...chats.values()]
        .sort((a, b) => b.lastTs - a.lastTs)
        .slice(0, 100)
        .map((c) => ({ jid: c.jid, name: names.get(c.jid) || c.jid.split('@')[0], last: c.last, ts: c.lastTs }));
      return send(res, 200, out);
    }

    if (url.pathname === '/messages') {
      return send(res, 200, (messages.get(url.searchParams.get('jid')) || []).slice(-100));
    }

    if (url.pathname === '/send' && req.method === 'POST') {
      const { jid, text } = await readJSON(req);
      if (!jid || !text || state.status !== 'open') return send(res, 400, { error: 'bad request or not connected' });
      addMessage(await sock.sendMessage(jid, { text }));
      return send(res, 200, { ok: true });
    }

    if (url.pathname === '/send-media' && req.method === 'POST') return await handleSendMedia(req, res, url);

    if (url.pathname === '/prepare') {
      const id = url.searchParams.get('id');
      if (!validId(id)) return send(res, 400, { error: 'bad id' });
      await ensureFull(id);
      return send(res, 200, { ok: true });
    }

    if (url.pathname === '/media') {
      const id = url.searchParams.get('id');
      if (!validId(id)) return send(res, 400, { error: 'bad id' });
      if (url.searchParams.get('v') === 'thumb') {
        const t = await getThumb(id);
        if (t.buffer) return send(res, 200, t.buffer, 'image/jpeg');
        return serveFile(req, res, t.file, 'image/jpeg');
      }
      const full = await ensureFull(id);
      return serveFile(req, res, full.file, MIME[full.kind]);
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    if (!res.headersSent) send(res, 500, { error: String(e.message || e) });
  }
});

// ---------- WhatsApp connection ----------

async function start() {
  const { state: auth, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();
  sock = makeWASocket({ version, auth, logger, printQRInTerminal: false, browser: ['WA Legacy', 'Chrome', '1.0'] });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
    if (qr) { state.qr = qr; state.status = 'qr'; }
    if (connection === 'open') { state.status = 'open'; state.qr = null; state.me = sock.user?.id || null; }
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      state.status = 'connecting';
      if (code === DisconnectReason.loggedOut) {
        state.me = null;
        fs.rmSync(AUTH_DIR, { recursive: true, force: true });
        chats.clear(); messages.clear(); raw.clear();
      }
      setTimeout(() => start().catch(console.error), 1500);
    }
  });

  sock.ev.on('contacts.upsert', (list) => list.forEach((c) => { const n = c.name || c.notify; if (n) names.set(c.id, n); }));
  sock.ev.on('messaging-history.set', ({ messages: msgs = [], contacts = [] }) => {
    contacts.forEach((c) => { const n = c.name || c.notify; if (n) names.set(c.id, n); });
    msgs.forEach(addMessage);
  });
  sock.ev.on('messages.upsert', ({ messages: msgs }) => msgs.forEach(addMessage));
}

server.listen(PORT, () => console.log(`WA Legacy bridge on :${PORT}${TOKEN ? ' (token required)' : ' (NO TOKEN SET)'}`));
start().catch(console.error);
