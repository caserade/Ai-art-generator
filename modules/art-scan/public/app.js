import { DEFAULT_THRESHOLD, FRAME_NAMES, processScan } from './pipeline.js'

/**
 * Art Scan phone client.
 *
 * The pipeline runs here, on the phone, against Canvas pixels — so preview is
 * instant and works with no PC and no network. Saving re-runs the identical
 * module on the server so the stored sheet always matches the preview.
 */

const MAX_SOURCE = 640
const FRAME_DELAY_MS = 180

const el = (id) => document.getElementById(id)
const statusEl = el('status')
const editor = el('editor')
const framesEl = el('frames')
const animCanvas = el('anim')
const metaEl = el('meta')
const thresholdInput = el('threshold')
const thresholdValue = el('thresholdValue')
const frameSizeInput = el('frameSize')
const nameInput = el('name')
const libraryEl = el('library')
const libraryHint = el('libraryHint')

let current = null
let animTimer = null
let animFrame = 0

function setStatus(text, kind = '') {
  statusEl.textContent = text
  statusEl.className = `status ${kind}`
}

async function api(pathname, options) {
  const res = await fetch(pathname, options)
  const data = await res.json().catch(() => ({}))
  if (!res.ok || data.ok === false) {
    throw new Error(data.message || `HTTP ${res.status}`)
  }
  return data
}

function toImageData(image) {
  try {
    return new ImageData(new Uint8ClampedArray(image.data), image.width, image.height)
  } catch {
    const ctx = document.createElement('canvas').getContext('2d')
    const out = ctx.createImageData(image.width, image.height)
    out.data.set(image.data)
    return out
  }
}

function canvasFrom(image) {
  const canvas = document.createElement('canvas')
  canvas.width = image.width
  canvas.height = image.height
  canvas.getContext('2d').putImageData(toImageData(image), 0, 0)
  return canvas
}

/** Decode any camera format via the browser, downscaled to a workable size. */
async function readSource(file) {
  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, MAX_SOURCE / Math.max(bitmap.width, bitmap.height))
  const width = Math.max(1, Math.round(bitmap.width * scale))
  const height = Math.max(1, Math.round(bitmap.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(bitmap, 0, 0, width, height)
  bitmap.close?.()
  return { canvas, imageData: ctx.getImageData(0, 0, width, height) }
}

function stopAnimation() {
  if (animTimer) clearInterval(animTimer)
  animTimer = null
}

function renderPreview() {
  if (!current) return
  const { result } = current
  const size = result.frameSize
  const sheetCanvas = canvasFrom(result.sheet)

  framesEl.innerHTML = ''
  for (let i = 0; i < result.frameCount; i += 1) {
    const figure = document.createElement('figure')
    const canvas = document.createElement('canvas')
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext('2d')
    ctx.imageSmoothingEnabled = false
    ctx.drawImage(sheetCanvas, i * size, 0, size, size, 0, 0, size, size)
    const caption = document.createElement('figcaption')
    caption.textContent = FRAME_NAMES[i] || `Frame ${i + 1}`
    figure.append(canvas, caption)
    framesEl.append(figure)
  }

  animCanvas.width = size
  animCanvas.height = size
  const animCtx = animCanvas.getContext('2d')
  animCtx.imageSmoothingEnabled = false
  stopAnimation()
  const drawFrame = () => {
    animCtx.clearRect(0, 0, size, size)
    animCtx.drawImage(sheetCanvas, animFrame * size, 0, size, size, 0, 0, size, size)
    animFrame = (animFrame + 1) % result.frameCount
  }
  drawFrame()
  animTimer = setInterval(drawFrame, FRAME_DELAY_MS)

  const { hitbox } = result
  metaEl.innerHTML = [
    `<b>${result.frameCount} frames</b> at ${size}×${size}`,
    `Sheet <b>${result.sheet.width}×${result.sheet.height}</b>`,
    `Hitbox <b>${hitbox.width}×${hitbox.height}</b> at ${hitbox.x},${hitbox.y}`,
    result.backgroundRemoved
      ? `Background removed: <b>${Math.round((result.removedPixels / (result.sourceSize.width * result.sourceSize.height)) * 100)}%</b>`
      : '<b>No background found</b> — raise the threshold',
  ].join('<br />')
}

function runPipeline() {
  if (!current) return
  const threshold = Number(thresholdInput.value)
  const frameSize = Number(frameSizeInput.value)
  try {
    current.result = processScan({ image: current.imageData, threshold, frameSize })
    renderPreview()
    setStatus('Preview built on this phone. Adjust the threshold, then save.', 'ok')
  } catch (err) {
    setStatus(err.message || String(err), 'bad')
  }
}

async function handleFile(file) {
  if (!file) return
  stopAnimation()
  setStatus('Reading artwork…', 'busy')
  try {
    const { canvas, imageData } = await readSource(file)
    current = { canvas, imageData, result: null }
    editor.hidden = false
    if (!nameInput.value.trim()) {
      nameInput.value = (file.name || 'Hero').replace(/\.[^.]+$/, '').slice(0, 40) || 'Hero'
    }
    runPipeline()
  } catch (err) {
    setStatus(`Could not read that image: ${err.message || err}`, 'bad')
  }
}

async function loadLibrary() {
  try {
    const data = await api('api/sprites')
    libraryHint.textContent = data.count
      ? `${data.count} sprite${data.count === 1 ? '' : 's'} saved in this module's own storage.`
      : 'No sprites yet. Scan something above.'
    libraryEl.innerHTML = ''
    for (const sprite of data.sprites) {
      const li = document.createElement('li')
      const title = document.createElement('strong')
      title.textContent = sprite.name
      const info = document.createElement('span')
      info.textContent = `${sprite.frameCount} frames · ${sprite.frameSize}px · hitbox ${sprite.hitbox.width}×${sprite.hitbox.height} · threshold ${sprite.threshold}`
      const img = document.createElement('img')
      img.src = sprite.sheetUrl
      img.alt = `${sprite.name} sprite sheet`
      img.style.width = '100%'
      img.style.imageRendering = 'pixelated'
      img.style.marginTop = '0.35rem'
      img.style.borderRadius = '8px'
      const del = document.createElement('button')
      del.className = 'danger'
      del.textContent = 'Delete'
      del.addEventListener('click', async () => {
        del.disabled = true
        try {
          await api(`api/sprites/${sprite.id}`, { method: 'DELETE' })
          setStatus(`Deleted “${sprite.name}”.`, 'ok')
          await loadLibrary()
        } catch (err) {
          setStatus(err.message || String(err), 'bad')
          del.disabled = false
        }
      })
      li.append(title, info, img, del)
      libraryEl.append(li)
    }
  } catch (err) {
    libraryHint.textContent = `Library unavailable: ${err.message || err}. Scanning still works offline.`
    libraryEl.innerHTML = ''
  }
}

el('pick').addEventListener('click', () => el('file').click())
el('pickGallery').addEventListener('click', () => el('fileGallery').click())
el('file').addEventListener('change', (e) => handleFile(e.target.files?.[0]))
el('fileGallery').addEventListener('change', (e) => handleFile(e.target.files?.[0]))

thresholdInput.addEventListener('input', () => {
  thresholdValue.textContent = thresholdInput.value
})
thresholdInput.addEventListener('change', runPipeline)
frameSizeInput.addEventListener('change', runPipeline)

el('discard').addEventListener('click', () => {
  stopAnimation()
  current = null
  editor.hidden = true
  framesEl.innerHTML = ''
  setStatus('Discarded. Scan another piece whenever you are ready.', '')
})

el('save').addEventListener('click', async () => {
  if (!current?.result) return
  const button = el('save')
  button.disabled = true
  setStatus('Saving sprite…', 'busy')
  try {
    const imagePng = current.canvas.toDataURL('image/png')
    const data = await api('api/sprites', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: nameInput.value.trim() || 'Untitled scan',
        threshold: Number(thresholdInput.value),
        frameSize: Number(frameSizeInput.value),
        imagePng,
      }),
    })
    setStatus(data.message || 'Saved.', 'ok')
    await loadLibrary()
  } catch (err) {
    setStatus(`Could not save: ${err.message || err}`, 'bad')
  } finally {
    button.disabled = false
  }
})

el('reload').addEventListener('click', () => void loadLibrary())

async function boot() {
  thresholdInput.value = String(DEFAULT_THRESHOLD)
  thresholdValue.textContent = String(DEFAULT_THRESHOLD)

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(() => {})
  }

  try {
    const health = await api('api/health')
    el('nav').hidden = health.standalone
    setStatus(
      health.standalone
        ? 'Art Scan is running on its own. Pick a photo to begin.'
        : 'Art Scan ready — running independently of the Gospel unlock. Pick a photo to begin.',
      'ok',
    )
  } catch {
    setStatus('Art Scan is offline, but scanning still works on this phone. Saving needs the server.', '')
  }
  await loadLibrary()
}

void boot()
