import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createStore, moduleDataDir } from '../shared/store.js'
import { decodePng, encodePng } from './png.js'
import { DEFAULT_FRAME_SIZE, DEFAULT_THRESHOLD, processScan } from './pipeline.js'

const here = path.dirname(fileURLToPath(import.meta.url))

export const ART_SCAN_ID = 'art-scan'

const MAX_SOURCE_PIXELS = 4096 * 4096

function sheetsDir() {
  return path.join(moduleDataDir(ART_SCAN_ID), 'sheets')
}

function spriteStore() {
  return createStore({
    dir: moduleDataDir(ART_SCAN_ID),
    file: 'sprites.json',
    defaults: { sprites: [] },
  })
}

function badRequest(message) {
  const err = new Error(message)
  err.status = 400
  return err
}

function decodeBase64Png(value) {
  if (typeof value !== 'string' || !value.trim()) {
    throw badRequest('Send the scan as base64 PNG in "imagePng".')
  }
  // Accept a raw base64 body or a full data: URL from the phone's canvas.
  const base64 = value.includes(',') && value.trim().startsWith('data:')
    ? value.slice(value.indexOf(',') + 1)
    : value
  let buffer
  try {
    buffer = Buffer.from(base64, 'base64')
  } catch {
    throw badRequest('Scan payload is not valid base64.')
  }
  if (!buffer.length) throw badRequest('Scan payload is empty.')
  let image
  try {
    image = decodePng(buffer)
  } catch (err) {
    throw badRequest(`Could not decode the scan: ${err.message}`)
  }
  if (image.width * image.height > MAX_SOURCE_PIXELS) {
    throw badRequest('Scan is too large. Resize it below 4096x4096 first.')
  }
  return image
}

function numberInRange(value, fallback, min, max) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

function publicSprite(sprite, base = '') {
  const { sheetFile, ...rest } = sprite
  return { ...rest, sheetUrl: `${base}api/sprites/${sprite.id}/sheet.png` }
}

function api(router) {
  router.get('/sprites', (req, res) => {
    const { sprites } = spriteStore().read()
    const base = req.baseUrl.replace(/api$/, '')
    res.json({
      ok: true,
      count: sprites.length,
      sprites: sprites.map((s) => publicSprite(s, base)),
    })
  })

  router.post('/sprites', (req, res, next) => {
    try {
      const name = String(req.body?.name || '').trim() || 'Untitled scan'
      const threshold = numberInRange(req.body?.threshold, DEFAULT_THRESHOLD, 0, 255)
      const frameSize = Math.round(
        numberInRange(req.body?.frameSize, DEFAULT_FRAME_SIZE, 16, 256),
      )
      const image = decodeBase64Png(req.body?.imagePng)

      const result = processScan({ image, threshold, frameSize })
      const id = crypto.randomUUID()
      const dir = sheetsDir()
      fs.mkdirSync(dir, { recursive: true })
      const sheetFile = path.join(dir, `${id}.png`)
      fs.writeFileSync(sheetFile, encodePng(result.sheet))

      const sprite = {
        id,
        name,
        threshold,
        frameSize: result.frameSize,
        frameCount: result.frameCount,
        frameNames: result.frameNames,
        hitbox: result.hitbox,
        backgroundRemoved: result.backgroundRemoved,
        coverage: Number(result.coverage.toFixed(4)),
        removedPixels: result.removedPixels,
        source: result.sourceSize,
        sheetWidth: result.sheet.width,
        sheetHeight: result.sheet.height,
        sheetFile,
        createdAt: Date.now(),
      }

      spriteStore().update((state) => {
        state.sprites = [sprite, ...state.sprites].slice(0, 200)
        return state
      })

      const base = req.baseUrl.replace(/api$/, '')
      res.status(201).json({
        ok: true,
        message: result.backgroundRemoved
          ? `Scanned “${name}” into a ${result.frameCount}-frame sprite.`
          : `Scanned “${name}”, but no background was found to remove — raised the threshold keeps more of the subject.`,
        sprite: publicSprite(sprite, base),
      })
    } catch (err) {
      next(err)
    }
  })

  router.get('/sprites/:id/sheet.png', (req, res) => {
    const { sprites } = spriteStore().read()
    const sprite = sprites.find((s) => s.id === req.params.id)
    if (!sprite || !fs.existsSync(sprite.sheetFile)) {
      res.status(404).json({ ok: false, message: 'Sprite sheet not found.' })
      return
    }
    res.type('png').set('Cache-Control', 'public, max-age=31536000, immutable')
    res.sendFile(sprite.sheetFile)
  })

  router.delete('/sprites/:id', (req, res) => {
    let removed = null
    spriteStore().update((state) => {
      removed = state.sprites.find((s) => s.id === req.params.id) || null
      state.sprites = state.sprites.filter((s) => s.id !== req.params.id)
      return state
    })
    if (!removed) {
      res.status(404).json({ ok: false, message: 'Sprite not found.' })
      return
    }
    fs.rmSync(removed.sheetFile, { force: true })
    res.json({ ok: true, message: `Deleted “${removed.name}”.` })
  })

  // Express 5 surfaces thrown errors here; keep the module's own shape.
  router.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ ok: false, message: err.message || String(err) })
  })
}

export const artScanModule = {
  id: ART_SCAN_ID,
  name: 'Art Scan',
  version: '2.0.0',
  kind: 'art-scan',
  description:
    'Camera or gallery photo to a 4-frame sprite sheet with auto hitbox. Runs on its own, no fingerprint unlock needed.',
  publicDir: path.join(here, 'public'),
  extraStatic: {
    '/pipeline.js': path.join(here, 'pipeline.js'),
    '/gospel.css': path.join(here, '..', 'shared', 'public', 'gospel.css'),
  },
  bodyLimit: '24mb',
  manifest: {
    name: 'Gospel Art Scan',
    short_name: 'Art Scan',
    description: 'Turn a sketch into a 4-frame game sprite, offline on your phone.',
    theme_color: '#0b0d0c',
  },
  api,
}

export default artScanModule
