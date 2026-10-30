const express = require('express');
const multer = require('multer');
const path = require('path');

const {
  ROBLOX_API_KEY,
  CREATOR_USER_ID,
  UPLOAD_PASSWORD,
  PORT = 3000,
} = process.env;

const app = express();
const upload = multer({ limits: { fileSize: 50 * 1024 * 1024, files: 20 } });

function auth(req, res, next) {
  if (!UPLOAD_PASSWORD) return res.status(500).json({ error: 'UPLOAD_PASSWORD belum di-set' });
  if ((req.headers['x-password'] || '') !== UPLOAD_PASSWORD) {
    return res.status(401).json({ error: 'password salah' });
  }
  next();
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function pollOperation(opPath) {
  for (let i = 0; i < 60; i++) {
    await sleep(1000);
    const r = await fetch(`https://apis.roblox.com/assets/v1/${opPath}`, {
      headers: { 'x-api-key': ROBLOX_API_KEY },
    });
    const j = await r.json();
    if (j.done) {
      if (j.error) throw new Error(JSON.stringify(j.error));
      return String(j.response.assetId);
    }
  }
  throw new Error('timeout nunggu operasi upload');
}

app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/upload', auth, upload.array('files', 20), async (req, res) => {
  if (!ROBLOX_API_KEY || !CREATOR_USER_ID) {
    return res.status(500).json({ error: 'ROBLOX_API_KEY / CREATOR_USER_ID belum di-set' });
  }

  const forced = req.body.assetType; // Animation | Audio | Model | kosong = auto
  const results = [];

  for (const f of req.files || []) {
    const name = f.originalname;
    try {
      let type = forced;
      if (!type) {
        type = name.toLowerCase().endsWith('.rbxm') ? 'Animation' : 'Audio';
      }

      const requestJson = {
        assetType: type,
        displayName: name.replace(/\.[^.]+$/, '').slice(0, 50) || 'asset',
        description: 'uploaded via asset-uploader',
        creationContext: { creator: { userId: String(CREATOR_USER_ID) } },
      };

      const form = new FormData();
      form.append('request', new Blob([JSON.stringify(requestJson)], { type: 'application/json' }));
      form.append('fileContent', new Blob([f.buffer], { type: f.mimetype || 'application/octet-stream' }), name);

      const r = await fetch('https://apis.roblox.com/assets/v1/assets', {
        method: 'POST',
        headers: { 'x-api-key': ROBLOX_API_KEY },
        body: form,
      });
      const op = await r.json();
      if (!r.ok) throw new Error(JSON.stringify(op));

      const assetId = await pollOperation(op.path);
      results.push({ file: name, type, assetId, ok: true });
    } catch (e) {
      results.push({ file: name, ok: false, error: String(e.message || e) });
    }
  }

  res.json({ results });
});

app.listen(PORT, () => console.log(`asset-uploader jalan di port ${PORT}`));
