import express from 'express'
import cors from 'cors'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  loadState,
  saveState,
  publicStatus,
  listModules,
} from './state.js'
import { issueChallenge, verifyEnroll, verifyUnlock, getRpId } from './webauthn.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const publicDir = path.join(__dirname, '..', 'public')
const PORT = Number(process.env.PORT || 8788)
const appName = 'WWW Gospel Command'

const app = express()
app.set('trust proxy', true)
app.use(cors())
app.use(express.json({ limit: '1mb' }))
app.use(express.static(publicDir))

function sendError(res, err) {
  const status = err.status || 500
  res.status(status).json({ ok: false, message: err.message || String(err) })
}

app.get('/api/state', (_req, res) => {
  const state = loadState()
  res.json(publicStatus(state))
})

app.get('/api/bridge', (req, res) => {
  const host = req.get('host') || `localhost:${PORT}`
  const proto = req.protocol || 'http'
  const base = `${proto}://${host}`
  res.json({
    ok: true,
    httpPort: PORT,
    httpsPort: Number(process.env.HTTPS_PORT || 8789),
    httpsReady: proto === 'https',
    httpUrl: `http://${host}/`,
    httpsUrl: proto === 'https' ? `${base}/` : `https://${host}/`,
    tunnelUrl: process.env.GOSPEL_TUNNEL_URL || base,
    appName,
  })
})

app.get('/api/modules', (_req, res) => {
  const state = loadState()
  res.json({ ok: true, modules: listModules(state) })
})

app.post('/api/modules', (req, res) => {
  const state = loadState()
  const name = String(req.body?.name || '').trim()
  const kind = String(req.body?.kind || 'fingerprint-scan')
  const description = String(req.body?.description || '').trim()
  if (!name) {
    return res.status(400).json({ ok: false, message: 'Module name required.' })
  }
  const mod = {
    id: `upload-${Date.now()}`,
    name,
    version: '0.1.0',
    kind,
    enabled: true,
    builtin: false,
    description: description || 'Uploaded module',
    uploadedAt: Date.now(),
  }
  state.uploadedModules = [...(state.uploadedModules || []), mod]
  saveState(state)
  res.json({ ok: true, message: `Module “${name}” uploaded.`, module: mod })
})

app.get('/api/challenge', async (req, res) => {
  try {
    const state = loadState()
    const forEnroll = !state.phoneEnrolled || !state.credential
    const { options, rpID } = await issueChallenge(state, req, { forEnroll })
    res.json({
      ok: true,
      challenge: options.challenge,
      rpId: rpID,
      options,
      mode: forEnroll ? 'enroll' : 'unlock',
      message: '',
    })
  } catch (err) {
    sendError(res, err)
  }
})

app.post('/api/enroll', async (req, res) => {
  try {
    const state = loadState()
    // Explicitly reject the old insecure shape: { pairingSecret, credentialId }
    if (req.body?.credentialId && !req.body?.response?.attestationObject) {
      return res.status(400).json({
        ok: false,
        message:
          'Hardened enroll requires a full WebAuthn registration response (attestationObject + clientDataJSON). credentialId alone is rejected.',
      })
    }
    const result = await verifyEnroll(state, req, req.body)
    res.json(result)
  } catch (err) {
    sendError(res, err)
  }
})

app.post('/api/unlock', async (req, res) => {
  try {
    const state = loadState()
    if (req.body?.credentialId && !req.body?.response?.authenticatorData) {
      return res.status(400).json({
        ok: false,
        message:
          'Hardened unlock requires a full WebAuthn assertion (authenticatorData + signature + clientDataJSON).',
      })
    }
    const result = await verifyUnlock(state, req, req.body)
    res.json(result)
  } catch (err) {
    sendError(res, err)
  }
})

app.post('/api/lock', (_req, res) => {
  const state = loadState()
  state.unlocked = false
  state.waitingForFingerprint = true
  saveState(state)
  res.json({ ok: true, message: 'PC locked. Waiting for fingerprint.', status: publicStatus(state) })
})

app.post('/api/reset-enrollment', (req, res) => {
  const state = loadState()
  const secret = req.body?.pairingSecret
  if (!secret || secret !== state.pairingSecret) {
    return res.status(401).json({ ok: false, message: 'Invalid pairing secret.' })
  }
  state.credential = null
  state.phoneEnrolled = false
  state.unlocked = false
  state.waitingForFingerprint = true
  state.currentChallenge = null
  state.failedAttempts = 0
  saveState(state)
  res.json({ ok: true, message: 'Enrollment cleared.', status: publicStatus(state) })
})

app.get(['/', '/phone'], (_req, res) => {
  res.sendFile(path.join(publicDir, 'index.html'))
})

app.use((req, res) => {
  res.status(404).json({ ok: false, message: 'Not found' })
})

export function createApp() {
  return app
}

if (process.env.GOSPEL_NO_LISTEN !== '1') {
  const state = loadState()
  app.listen(PORT, '0.0.0.0', () => {
    const rpHint = process.env.GOSPEL_RP_ID || 'localhost'
    console.log(`${appName} listening on http://0.0.0.0:${PORT}`)
    console.log(`Pairing secret: ${state.pairingSecret}`)
    console.log(`Open: http://127.0.0.1:${PORT}/?s=${state.pairingSecret}#s=${state.pairingSecret}`)
    console.log(`RP ID default: ${rpHint} (override with GOSPEL_RP_ID)`)
  })
}
