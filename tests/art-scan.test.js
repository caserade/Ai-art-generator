import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import zlib from 'node:zlib'
import { createServer } from 'node:http'

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gospel-art-scan-'))
process.env.GOSPEL_MODULE_DATA_DIR = path.join(tmpRoot, 'modules')

const { decodePng, encodePng } = await import('../modules/art-scan/png.js')
const {
  alphaCoverage,
  buildSpriteSheet,
  computeHitbox,
  cropToContent,
  isolateBackground,
  opaqueBounds,
  processScan,
  resize,
  rotate,
  sampleBackgroundColor,
} = await import('../modules/art-scan/pipeline.js')
const { createModuleApp } = await import('../modules/host.js')
const { artScanModule } = await import('../modules/art-scan/index.js')

let server
let baseUrl

before(async () => {
  server = createServer(createModuleApp(artScanModule))
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  baseUrl = `http://127.0.0.1:${server.address().port}`
})

after(async () => {
  await new Promise((resolve) => server.close(resolve))
  fs.rmSync(tmpRoot, { recursive: true, force: true })
})

async function json(pathname, options = {}) {
  const res = await fetch(`${baseUrl}${pathname}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
  })
  return { status: res.status, body: await res.json().catch(() => ({})) }
}

function makeImage(width, height, fill) {
  const data = new Uint8ClampedArray(width * height * 4)
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const [r, g, b, a] = fill(x, y)
      const o = (y * width + x) * 4
      data[o] = r
      data[o + 1] = g
      data[o + 2] = b
      data[o + 3] = a
    }
  }
  return { width, height, data }
}

/** Paper with a soft shadow, plus a dark subject block — a realistic phone photo. */
function shadowedSketch(width = 80, height = 80) {
  return makeImage(width, height, (x, y) => {
    const inSubject = x >= 30 && x < 50 && y >= 20 && y < 60
    if (inSubject) return [30, 30, 30, 255]
    // Right half sits in shadow: 18 units from the lit paper the corners see.
    return x > width / 2 ? [232, 232, 232, 255] : [250, 250, 250, 255]
  })
}

describe('PNG codec', () => {
  test('round-trips RGBA pixels exactly', () => {
    const source = makeImage(9, 5, (x, y) => [x * 20, y * 40, (x + y) * 10, x % 2 ? 128 : 255])
    const decoded = decodePng(encodePng(source))
    assert.equal(decoded.width, 9)
    assert.equal(decoded.height, 5)
    assert.deepEqual([...decoded.data], [...source.data])
  })

  test('decodes truecolor PNGs that carry no alpha channel', () => {
    // Hand-built colorType 2 so the decoder is exercised on real 3-channel data.
    const width = 2
    const height = 2
    const pixels = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]
    const raw = Buffer.alloc(height * (width * 3 + 1))
    for (let y = 0; y < height; y += 1) {
      raw[y * (width * 3 + 1)] = 0
      for (let i = 0; i < width * 3; i += 1) {
        raw[y * (width * 3 + 1) + 1 + i] = pixels[y * width * 3 + i]
      }
    }
    const ihdr = Buffer.alloc(13)
    ihdr.writeUInt32BE(width, 0)
    ihdr.writeUInt32BE(height, 4)
    ihdr[8] = 8
    ihdr[9] = 2
    const png = Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      chunk('IHDR', ihdr),
      chunk('IDAT', zlib.deflateSync(raw)),
      chunk('IEND', Buffer.alloc(0)),
    ])
    const decoded = decodePng(png)
    assert.deepEqual([...decoded.data.slice(0, 4)], [255, 0, 0, 255])
    assert.deepEqual([...decoded.data.slice(4, 8)], [0, 255, 0, 255])
    assert.equal(decoded.data[15], 255, 'missing alpha channel becomes fully opaque')
  })

  test('rejects data that is not a PNG', () => {
    assert.throws(() => decodePng(Buffer.from('definitely not a png')), /signature/i)
  })
})

function crc32(buf) {
  let c = 0xffffffff
  for (let i = 0; i < buf.length; i += 1) {
    c ^= buf[i]
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  }
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length, 0)
  const typeBuf = Buffer.from(type, 'ascii')
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0)
  return Buffer.concat([len, typeBuf, data, crc])
}

describe('background isolation', () => {
  test('estimates the paper colour from the corners', () => {
    const bg = sampleBackgroundColor(shadowedSketch())
    assert.ok(Math.abs(bg.r - 241) <= 10, `corner average was ${bg.r}`)
  })

  test('removes shaded paper the squared-distance threshold used to keep', () => {
    const source = shadowedSketch()
    const { image } = isolateBackground(source, { threshold: 42 })

    // Lit paper and shadowed paper both go; the subject stays.
    assert.equal(image.data[(10 * 80 + 10) * 4 + 3], 0, 'lit paper should be cleared')
    assert.equal(image.data[(10 * 80 + 70) * 4 + 3], 0, 'shadowed paper should be cleared')
    assert.equal(image.data[(40 * 80 + 40) * 4 + 3], 255, 'subject must survive')

    // The shadow sits ~31 units from the corner average. Comparing a squared
    // distance (≈972) against the raw threshold of 42, as the Flutter pipeline
    // did, would have left every shadowed pixel opaque.
    const shadowDistance = Math.sqrt(3 * 18 ** 2)
    assert.ok(shadowDistance < 42, 'shadow is inside the true-distance threshold')
    assert.ok(shadowDistance ** 2 > 42, 'and outside the old squared comparison')
  })

  test('a threshold of zero removes nothing', () => {
    const { removed } = isolateBackground(shadowedSketch(), { threshold: 0 })
    assert.equal(removed, 0)
  })
})

describe('crop and hitbox', () => {
  test('crops to a centred square around the subject', () => {
    const source = makeImage(60, 40, (x, y) =>
      x >= 20 && x < 30 && y >= 10 && y < 30 ? [10, 200, 10, 255] : [0, 0, 0, 0],
    )
    const cropped = cropToContent(source, { padding: 2 })
    assert.equal(cropped.width, cropped.height, 'result must be square')
    assert.equal(cropped.width, 24, '20px tall subject plus 2px padding each side')

    const bounds = opaqueBounds(cropped)
    const leftGap = bounds.minX
    const rightGap = cropped.width - 1 - bounds.maxX
    assert.ok(Math.abs(leftGap - rightGap) <= 1, 'subject should be horizontally centred')
  })

  test('leaves a fully transparent image alone', () => {
    const empty = makeImage(8, 8, () => [0, 0, 0, 0])
    const cropped = cropToContent(empty)
    assert.equal(cropped.width, 8)
    assert.equal(alphaCoverage(cropped), 0)
  })

  test('derives the hitbox from the idle frame only', () => {
    const character = makeImage(64, 64, (x, y) =>
      x >= 16 && x < 48 && y >= 8 && y < 56 ? [200, 40, 40, 255] : [0, 0, 0, 0],
    )
    const sheet = buildSpriteSheet(character, { frameSize: 64 })
    const hitbox = computeHitbox(sheet, { frameSize: 64 })
    assert.ok(hitbox.width > 0 && hitbox.height > 0)
    assert.ok(hitbox.x + hitbox.width <= 64, 'hitbox stays inside the frame')
    assert.ok(hitbox.y + hitbox.height <= 64)
    assert.ok(hitbox.height > hitbox.width, 'tall subject gives a tall hitbox')
  })
})

describe('geometry helpers', () => {
  test('rotation keeps the canvas size, unlike rotate-then-resize', () => {
    const square = makeImage(32, 32, (x, y) =>
      x >= 8 && x < 24 && y >= 8 && y < 24 ? [255, 255, 255, 255] : [0, 0, 0, 0],
    )
    const turned = rotate(square, 6)
    assert.equal(turned.width, 32)
    assert.equal(turned.height, 32)
    assert.ok(alphaCoverage(turned) > 0.1, 'subject survives the rotation')
  })

  test('downscale averages instead of dropping pixels', () => {
    // A 1px checkerboard halved should read as a flat mid-grey, not noise.
    const checker = makeImage(32, 32, (x, y) =>
      (x + y) % 2 === 0 ? [255, 255, 255, 255] : [0, 0, 0, 255],
    )
    const small = resize(checker, 16, 16)
    assert.equal(small.width, 16)
    for (let i = 0; i < small.data.length; i += 4) {
      assert.ok(
        small.data[i] > 100 && small.data[i] < 155,
        `expected an averaged mid-grey, saw ${small.data[i]}`,
      )
    }
  })
})

describe('processScan', () => {
  test('produces a four-frame sheet with distinct frames', () => {
    const result = processScan({ image: shadowedSketch(), threshold: 42, frameSize: 64 })
    assert.equal(result.frameCount, 4)
    assert.equal(result.sheet.width, 64 * 4)
    assert.equal(result.sheet.height, 64)
    assert.equal(result.backgroundRemoved, true)
    assert.deepEqual(result.frameNames, ['Idle', 'Walk A', 'Walk B', 'Jump'])

    const frameAlpha = []
    for (let f = 0; f < 4; f += 1) {
      let bottom = -1
      let opaque = 0
      for (let y = 0; y < 64; y += 1) {
        for (let x = f * 64; x < (f + 1) * 64; x += 1) {
          if (result.sheet.data[(y * result.sheet.width + x) * 4 + 3] > 16) {
            opaque += 1
            bottom = y
          }
        }
      }
      frameAlpha.push({ opaque, bottom })
    }
    for (const frame of frameAlpha) assert.ok(frame.opaque > 0, 'every frame has pixels')
    assert.ok(
      frameAlpha[3].bottom < frameAlpha[0].bottom,
      'the jump frame sits above the idle baseline',
    )
    assert.ok(
      frameAlpha[1].opaque !== frameAlpha[0].opaque,
      'the walk frame differs from idle',
    )
  })

  test('keeps the raw image when the threshold would erase everything', () => {
    const flat = makeImage(40, 40, () => [200, 200, 200, 255])
    const result = processScan({ image: flat, threshold: 200, frameSize: 32 })
    assert.equal(result.backgroundRemoved, false, 'flags that nothing survived isolation')
    assert.ok(alphaCoverage(result.sheet) > 0, 'still returns a usable sprite, not a blank one')
  })

  test('rejects an image with no size', () => {
    assert.throws(() => processScan({ image: { width: 0, height: 0, data: [] } }), /non-zero/i)
  })
})

describe('Art Scan API (standalone, no Gospel state)', () => {
  test('reports itself as a standalone module', async () => {
    const res = await json('/api/health')
    assert.equal(res.status, 200)
    assert.equal(res.body.module, 'art-scan')
    assert.equal(res.body.standalone, true)
  })

  test('starts with an empty library', async () => {
    const res = await json('/api/sprites')
    assert.equal(res.status, 200)
    assert.equal(res.body.count, 0)
  })

  test('scans, lists, serves and deletes a sprite', async () => {
    const png = encodePng(shadowedSketch()).toString('base64')
    const created = await json('/api/sprites', {
      method: 'POST',
      body: JSON.stringify({ name: 'Test Hero', imagePng: png, threshold: 42, frameSize: 64 }),
    })
    assert.equal(created.status, 201)
    assert.equal(created.body.sprite.frameCount, 4)
    assert.equal(created.body.sprite.frameSize, 64)
    assert.ok(created.body.sprite.hitbox.width > 0)
    assert.ok(!('sheetFile' in created.body.sprite), 'server paths stay off the wire')

    const list = await json('/api/sprites')
    assert.equal(list.body.count, 1)
    assert.equal(list.body.sprites[0].name, 'Test Hero')

    const sheetRes = await fetch(`${baseUrl}${created.body.sprite.sheetUrl}`)
    assert.equal(sheetRes.status, 200)
    assert.equal(sheetRes.headers.get('content-type'), 'image/png')
    const sheet = decodePng(Buffer.from(await sheetRes.arrayBuffer()))
    assert.equal(sheet.width, 256)
    assert.equal(sheet.height, 64)

    const deleted = await json(`/api/sprites/${created.body.sprite.id}`, { method: 'DELETE' })
    assert.equal(deleted.status, 200)
    assert.equal((await json('/api/sprites')).body.count, 0)
  })

  test('accepts a data: URL from the phone canvas', async () => {
    const png = encodePng(shadowedSketch()).toString('base64')
    const res = await json('/api/sprites', {
      method: 'POST',
      body: JSON.stringify({ name: 'Data URL', imagePng: `data:image/png;base64,${png}` }),
    })
    assert.equal(res.status, 201)
    await json(`/api/sprites/${res.body.sprite.id}`, { method: 'DELETE' })
  })

  test('rejects a missing or unreadable image', async () => {
    const missing = await json('/api/sprites', { method: 'POST', body: JSON.stringify({}) })
    assert.equal(missing.status, 400)
    assert.match(missing.body.message, /imagePng/)

    const garbage = await json('/api/sprites', {
      method: 'POST',
      body: JSON.stringify({ imagePng: Buffer.from('nope').toString('base64') }),
    })
    assert.equal(garbage.status, 400)
    assert.match(garbage.body.message, /could not decode/i)
  })

  test('clamps out-of-range scan settings instead of failing', async () => {
    const png = encodePng(shadowedSketch()).toString('base64')
    const res = await json('/api/sprites', {
      method: 'POST',
      body: JSON.stringify({ name: 'Clamped', imagePng: png, frameSize: 9000, threshold: -5 }),
    })
    assert.equal(res.status, 201)
    assert.equal(res.body.sprite.frameSize, 256)
    assert.equal(res.body.sprite.threshold, 0)
    await json(`/api/sprites/${res.body.sprite.id}`, { method: 'DELETE' })
  })

  test('404s an unknown sprite', async () => {
    assert.equal((await json('/api/sprites/nope/sheet.png')).status, 404)
    assert.equal((await json('/api/sprites/nope', { method: 'DELETE' })).status, 404)
  })
})
