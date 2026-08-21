/**
 * Art Scan pipeline — plain RGBA math, no DOM and no Node built-ins.
 *
 * The phone imports this file directly as an ES module and feeds it Canvas
 * ImageData; the server imports the same file and feeds it decoded PNG pixels.
 * One implementation means the sprite the phone previews is the sprite the
 * server stores.
 *
 * An image is `{ width, height, data }` where `data` is RGBA bytes, which makes
 * a browser ImageData a valid input as-is.
 */

export const FRAME_NAMES = ['Idle', 'Walk A', 'Walk B', 'Jump']
export const FRAME_COUNT = FRAME_NAMES.length
export const DEFAULT_FRAME_SIZE = 128
export const DEFAULT_THRESHOLD = 42
export const ALPHA_CUTOFF = 16

export function createImage(width, height) {
  return { width, height, data: new Uint8ClampedArray(width * height * 4) }
}

export function cloneImage(image) {
  return {
    width: image.width,
    height: image.height,
    data: new Uint8ClampedArray(image.data),
  }
}

function clamp(value, min, max) {
  return value < min ? min : value > max ? max : value
}

/**
 * Average a small patch at each corner. Corners are where a photographed
 * sketch shows its paper, so their mean is a good background estimate. The
 * Flutter version sampled one lone pixel per corner, which a single speck of
 * dust or JPEG noise was enough to throw off.
 */
export function sampleBackgroundColor(image, patch = 3) {
  const { width, height, data } = image
  const corners = [
    [0, 0],
    [width - patch, 0],
    [0, height - patch],
    [width - patch, height - patch],
  ]
  let r = 0
  let g = 0
  let b = 0
  let count = 0
  for (const [cx, cy] of corners) {
    for (let y = 0; y < patch; y += 1) {
      for (let x = 0; x < patch; x += 1) {
        const sx = clamp(cx + x, 0, width - 1)
        const sy = clamp(cy + y, 0, height - 1)
        const o = (sy * width + sx) * 4
        r += data[o]
        g += data[o + 1]
        b += data[o + 2]
        count += 1
      }
    }
  }
  return { r: r / count, g: g / count, b: b / count }
}

/**
 * Knock out near-uniform background by RGB distance.
 *
 * `threshold` is a true Euclidean distance in 0-255 colour space. The Flutter
 * original compared a *squared* distance against the same 42, i.e. an
 * effective radius of 6.5, so paper that was a shade off pure white survived
 * and every scan came back with its background still attached.
 */
export function isolateBackground(image, { threshold = DEFAULT_THRESHOLD } = {}) {
  const out = cloneImage(image)
  const bg = sampleBackgroundColor(image)
  const limit = Math.max(0, threshold)
  let removed = 0
  for (let i = 0; i < out.data.length; i += 4) {
    const dr = out.data[i] - bg.r
    const dg = out.data[i + 1] - bg.g
    const db = out.data[i + 2] - bg.b
    if (Math.sqrt(dr * dr + dg * dg + db * db) < limit) {
      out.data[i] = 0
      out.data[i + 1] = 0
      out.data[i + 2] = 0
      out.data[i + 3] = 0
      removed += 1
    }
  }
  return { image: out, removed, total: out.width * out.height, background: bg }
}

/** Fraction of pixels that are meaningfully opaque. */
export function alphaCoverage(image, cutoff = ALPHA_CUTOFF) {
  let opaque = 0
  for (let i = 3; i < image.data.length; i += 4) {
    if (image.data[i] > cutoff) opaque += 1
  }
  return opaque / (image.width * image.height)
}

export function toGrayscale(image) {
  const out = cloneImage(image)
  for (let i = 0; i < out.data.length; i += 4) {
    const lum = 0.299 * out.data[i] + 0.587 * out.data[i + 1] + 0.114 * out.data[i + 2]
    out.data[i] = out.data[i + 1] = out.data[i + 2] = lum
  }
  return out
}

/** Sobel edge magnitude, used by the UI's outline preview. */
export function sobelEdges(image) {
  const gray = toGrayscale(image)
  const { width, height } = image
  const out = createImage(width, height)
  const kx = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
  const ky = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let gx = 0
      let gy = 0
      for (let ky2 = -1; ky2 <= 1; ky2 += 1) {
        for (let kx2 = -1; kx2 <= 1; kx2 += 1) {
          const sx = clamp(x + kx2, 0, width - 1)
          const sy = clamp(y + ky2, 0, height - 1)
          const lum = gray.data[(sy * width + sx) * 4]
          const k = (ky2 + 1) * 3 + (kx2 + 1)
          gx += lum * kx[k]
          gy += lum * ky[k]
        }
      }
      const mag = clamp(Math.sqrt(gx * gx + gy * gy), 0, 255)
      const o = (y * width + x) * 4
      out.data[o] = out.data[o + 1] = out.data[o + 2] = mag
      out.data[o + 3] = 255
    }
  }
  return out
}

/** Bounding box of pixels above the alpha cutoff, or null when fully clear. */
export function opaqueBounds(image, cutoff = ALPHA_CUTOFF) {
  const { width, height, data } = image
  let minX = width
  let minY = height
  let maxX = -1
  let maxY = -1
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * 4 + 3] > cutoff) {
        if (x < minX) minX = x
        if (y < minY) minY = y
        if (x > maxX) maxX = x
        if (y > maxY) maxY = y
      }
    }
  }
  if (maxX < 0) return null
  return { minX, minY, maxX, maxY, width: maxX - minX + 1, height: maxY - minY + 1 }
}

/** Crop to the subject then pad out to a centred square canvas. */
export function cropToContent(image, { padding = 4, cutoff = ALPHA_CUTOFF } = {}) {
  const bounds = opaqueBounds(image, cutoff)
  if (!bounds) return cloneImage(image)

  const minX = clamp(bounds.minX - padding, 0, image.width - 1)
  const minY = clamp(bounds.minY - padding, 0, image.height - 1)
  const maxX = clamp(bounds.maxX + padding, 0, image.width - 1)
  const maxY = clamp(bounds.maxY + padding, 0, image.height - 1)
  const w = maxX - minX + 1
  const h = maxY - minY + 1
  const side = Math.max(w, h)

  const out = createImage(side, side)
  const offX = Math.floor((side - w) / 2)
  const offY = Math.floor((side - h) / 2)
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      const src = ((minY + y) * image.width + (minX + x)) * 4
      const dst = ((offY + y) * side + (offX + x)) * 4
      out.data[dst] = image.data[src]
      out.data[dst + 1] = image.data[src + 1]
      out.data[dst + 2] = image.data[src + 2]
      out.data[dst + 3] = image.data[src + 3]
    }
  }
  return out
}

/**
 * Bilinear sample in premultiplied space so transparent neighbours cannot
 * bleed dark fringes into the sprite outline.
 */
function sampleBilinear(image, x, y, edge, out) {
  const { width, height, data } = image
  const x0 = Math.floor(x)
  const y0 = Math.floor(y)
  const fx = x - x0
  const fy = y - y0
  let r = 0
  let g = 0
  let b = 0
  let a = 0
  for (let dy = 0; dy < 2; dy += 1) {
    for (let dx = 0; dx < 2; dx += 1) {
      const w = (dx ? fx : 1 - fx) * (dy ? fy : 1 - fy)
      if (w <= 0) continue
      let sx = x0 + dx
      let sy = y0 + dy
      if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
        if (edge !== 'clamp') continue
        sx = clamp(sx, 0, width - 1)
        sy = clamp(sy, 0, height - 1)
      }
      const o = (sy * width + sx) * 4
      const al = data[o + 3] / 255
      r += data[o] * al * w
      g += data[o + 1] * al * w
      b += data[o + 2] * al * w
      a += al * w
    }
  }
  out[3] = Math.round(clamp(a * 255, 0, 255))
  if (a > 0) {
    out[0] = Math.round(clamp(r / a, 0, 255))
    out[1] = Math.round(clamp(g / a, 0, 255))
    out[2] = Math.round(clamp(b / a, 0, 255))
  } else {
    out[0] = out[1] = out[2] = 0
  }
}

/** Area-average downscale — avoids the aliasing a phone photo would show. */
function resizeArea(image, dw, dh) {
  const out = createImage(dw, dh)
  const sx = image.width / dw
  const sy = image.height / dh
  for (let dy = 0; dy < dh; dy += 1) {
    const y0 = dy * sy
    const y1 = (dy + 1) * sy
    const iy0 = Math.floor(y0)
    const iy1 = Math.min(image.height - 1, Math.ceil(y1) - 1)
    for (let dx = 0; dx < dw; dx += 1) {
      const x0 = dx * sx
      const x1 = (dx + 1) * sx
      const ix0 = Math.floor(x0)
      const ix1 = Math.min(image.width - 1, Math.ceil(x1) - 1)
      let r = 0
      let g = 0
      let b = 0
      let a = 0
      let wsum = 0
      for (let yy = iy0; yy <= iy1; yy += 1) {
        const wy = Math.min(y1, yy + 1) - Math.max(y0, yy)
        if (wy <= 0) continue
        for (let xx = ix0; xx <= ix1; xx += 1) {
          const wx = Math.min(x1, xx + 1) - Math.max(x0, xx)
          if (wx <= 0) continue
          const w = wx * wy
          const o = (yy * image.width + xx) * 4
          const al = image.data[o + 3] / 255
          r += image.data[o] * al * w
          g += image.data[o + 1] * al * w
          b += image.data[o + 2] * al * w
          a += al * w
          wsum += w
        }
      }
      const o = (dy * dw + dx) * 4
      if (wsum > 0) {
        out.data[o + 3] = Math.round(clamp((a / wsum) * 255, 0, 255))
        if (a > 0) {
          out.data[o] = Math.round(clamp(r / a, 0, 255))
          out.data[o + 1] = Math.round(clamp(g / a, 0, 255))
          out.data[o + 2] = Math.round(clamp(b / a, 0, 255))
        }
      }
    }
  }
  return out
}

export function resize(image, dw, dh) {
  if (dw <= 0 || dh <= 0) throw new Error('Resize target must be positive.')
  if (dw === image.width && dh === image.height) return cloneImage(image)
  if (dw <= image.width && dh <= image.height) return resizeArea(image, dw, dh)
  const out = createImage(dw, dh)
  const px = new Uint8ClampedArray(4)
  for (let y = 0; y < dh; y += 1) {
    for (let x = 0; x < dw; x += 1) {
      sampleBilinear(
        image,
        ((x + 0.5) * image.width) / dw - 0.5,
        ((y + 0.5) * image.height) / dh - 0.5,
        'clamp',
        px,
      )
      const o = (y * dw + x) * 4
      out.data[o] = px[0]
      out.data[o + 1] = px[1]
      out.data[o + 2] = px[2]
      out.data[o + 3] = px[3]
    }
  }
  return out
}

/**
 * Rotate about the centre keeping the canvas size fixed.
 *
 * The Flutter version rotated into an expanded canvas and then squeezed it back
 * to the frame size, so the walk frames came out visibly narrower than idle.
 */
export function rotate(image, degrees) {
  const out = createImage(image.width, image.height)
  const rad = (degrees * Math.PI) / 180
  const cos = Math.cos(-rad)
  const sin = Math.sin(-rad)
  const cx = (image.width - 1) / 2
  const cy = (image.height - 1) / 2
  const px = new Uint8ClampedArray(4)
  for (let y = 0; y < out.height; y += 1) {
    const dy = y - cy
    for (let x = 0; x < out.width; x += 1) {
      const dx = x - cx
      sampleBilinear(image, cx + dx * cos - dy * sin, cy + dx * sin + dy * cos, 'transparent', px)
      const o = (y * out.width + x) * 4
      out.data[o] = px[0]
      out.data[o + 1] = px[1]
      out.data[o + 2] = px[2]
      out.data[o + 3] = px[3]
    }
  }
  return out
}

/** Source-over composite of `src` onto `dst`, clipped to the destination. */
export function composite(dst, src, dstX = 0, dstY = 0) {
  for (let y = 0; y < src.height; y += 1) {
    const ty = dstY + y
    if (ty < 0 || ty >= dst.height) continue
    for (let x = 0; x < src.width; x += 1) {
      const tx = dstX + x
      if (tx < 0 || tx >= dst.width) continue
      const s = (y * src.width + x) * 4
      const sa = src.data[s + 3] / 255
      if (sa <= 0) continue
      const d = (ty * dst.width + tx) * 4
      const da = dst.data[d + 3] / 255
      const outA = sa + da * (1 - sa)
      for (let c = 0; c < 3; c += 1) {
        dst.data[d + c] = Math.round(
          (src.data[s + c] * sa + dst.data[d + c] * da * (1 - sa)) / (outA || 1),
        )
      }
      dst.data[d + 3] = Math.round(clamp(outA * 255, 0, 255))
    }
  }
  return dst
}

/** Horizontal 4-frame sheet: Idle, Walk A, Walk B, Jump. */
export function buildSpriteSheet(character, { frameSize = DEFAULT_FRAME_SIZE, lean = 6 } = {}) {
  const base = resize(character, frameSize, frameSize)
  const sheet = createImage(frameSize * FRAME_COUNT, frameSize)

  composite(sheet, base, 0, 0)
  composite(sheet, rotate(base, -lean), frameSize, 0)
  composite(sheet, rotate(base, lean), frameSize * 2, 0)

  // Jump: narrower silhouette, and 4px of ground clearance under the feet.
  const lift = 4
  const jump = resize(base, Math.max(1, Math.round(frameSize * 0.86)), frameSize - lift)
  composite(sheet, jump, frameSize * 3 + Math.floor((frameSize - jump.width) / 2), 0)

  return sheet
}

/** Auto hitbox from the opaque pixels of the Idle frame. */
export function computeHitbox(sheet, { frameSize = DEFAULT_FRAME_SIZE, cutoff = ALPHA_CUTOFF } = {}) {
  const frame = createImage(frameSize, frameSize)
  for (let y = 0; y < frameSize && y < sheet.height; y += 1) {
    for (let x = 0; x < frameSize && x < sheet.width; x += 1) {
      const s = (y * sheet.width + x) * 4
      const d = (y * frameSize + x) * 4
      frame.data[d] = sheet.data[s]
      frame.data[d + 1] = sheet.data[s + 1]
      frame.data[d + 2] = sheet.data[s + 2]
      frame.data[d + 3] = sheet.data[s + 3]
    }
  }
  const bounds = opaqueBounds(frame, cutoff)
  if (!bounds) {
    return {
      x: Math.round(frameSize * 0.2),
      y: Math.round(frameSize * 0.2),
      width: Math.round(frameSize * 0.6),
      height: Math.round(frameSize * 0.6),
    }
  }
  return { x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height }
}

/**
 * Full scan: isolate background, crop, build the sheet, derive the hitbox.
 *
 * If the threshold would erase essentially everything (a close-up with no
 * visible background, or a dark sketch on a dark surface) the raw image is kept
 * instead of returning the blank sprite the Flutter pipeline produced.
 */
export function processScan({
  image,
  threshold = DEFAULT_THRESHOLD,
  frameSize = DEFAULT_FRAME_SIZE,
  padding = 4,
  minCoverage = 0.01,
} = {}) {
  if (!image || !image.width || !image.height) {
    throw new Error('Art Scan needs a decoded image with a non-zero size.')
  }
  const isolated = isolateBackground(image, { threshold })
  const coverage = alphaCoverage(isolated.image)
  const backgroundRemoved = coverage >= minCoverage
  const working = backgroundRemoved ? isolated.image : cloneImage(image)
  const cropped = cropToContent(working, { padding })
  const sheet = buildSpriteSheet(cropped, { frameSize })
  return {
    sheet,
    hitbox: computeHitbox(sheet, { frameSize }),
    frameSize,
    frameCount: FRAME_COUNT,
    frameNames: [...FRAME_NAMES],
    backgroundRemoved,
    coverage,
    removedPixels: isolated.removed,
    sourceSize: { width: image.width, height: image.height },
  }
}
