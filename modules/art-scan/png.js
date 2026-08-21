import zlib from 'node:zlib'

/**
 * Dependency-free PNG decode/encode.
 *
 * The art pipeline runs on both the phone (Canvas decodes the camera JPEG) and
 * the server (this codec), so Art Scan needs no native image packages and stays
 * installable on any Node 20+ host.
 */

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n += 1) {
    let c = n
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    }
    table[n] = c
  }
  return table
})()

function crc32(buf) {
  let c = 0xffffffff
  for (let i = 0; i < buf.length; i += 1) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
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

const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }

function paeth(a, b, c) {
  const p = a + b - c
  const pa = Math.abs(p - a)
  const pb = Math.abs(p - b)
  const pc = Math.abs(p - c)
  if (pa <= pb && pa <= pc) return a
  if (pb <= pc) return b
  return c
}

function unfilter(raw, width, height, bpp, bytesPerRow) {
  const out = Buffer.alloc(height * bytesPerRow)
  let pos = 0
  for (let y = 0; y < height; y += 1) {
    const filter = raw[pos]
    pos += 1
    const rowStart = y * bytesPerRow
    const prevStart = rowStart - bytesPerRow
    for (let x = 0; x < bytesPerRow; x += 1) {
      const value = raw[pos + x]
      const left = x >= bpp ? out[rowStart + x - bpp] : 0
      const up = y > 0 ? out[prevStart + x] : 0
      const upLeft = y > 0 && x >= bpp ? out[prevStart + x - bpp] : 0
      let recon
      switch (filter) {
        case 0:
          recon = value
          break
        case 1:
          recon = value + left
          break
        case 2:
          recon = value + up
          break
        case 3:
          recon = value + ((left + up) >> 1)
          break
        case 4:
          recon = value + paeth(left, up, upLeft)
          break
        default:
          throw new Error(`Unsupported PNG row filter ${filter}`)
      }
      out[rowStart + x] = recon & 0xff
    }
    pos += bytesPerRow
  }
  return out
}

/** Read `count` samples of `depth` bits from a row, scaled up to 0-255. */
function readSamples(row, depth, count) {
  if (depth === 8) return row.subarray(0, count)
  const out = new Uint8Array(count)
  if (depth === 16) {
    for (let i = 0; i < count; i += 1) out[i] = row[i * 2]
    return out
  }
  const max = (1 << depth) - 1
  const perByte = 8 / depth
  for (let i = 0; i < count; i += 1) {
    const byte = row[Math.floor(i / perByte)]
    const shift = 8 - depth * ((i % perByte) + 1)
    const value = (byte >> shift) & max
    out[i] = Math.round((value * 255) / max)
  }
  return out
}

/**
 * Decode a PNG buffer into a flat RGBA image.
 * @returns {{width:number,height:number,data:Uint8ClampedArray}}
 */
export function decodePng(buffer) {
  const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer)
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIGNATURE)) {
    throw new Error('Not a PNG image (bad signature).')
  }

  let offset = 8
  let header = null
  let palette = null
  let transparency = null
  const idat = []

  while (offset + 8 <= buf.length) {
    const length = buf.readUInt32BE(offset)
    const type = buf.toString('ascii', offset + 4, offset + 8)
    const data = buf.subarray(offset + 8, offset + 8 + length)
    offset += 12 + length

    if (type === 'IHDR') {
      header = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        bitDepth: data[8],
        colorType: data[9],
        interlace: data[12],
      }
    } else if (type === 'PLTE') {
      palette = Buffer.from(data)
    } else if (type === 'tRNS') {
      transparency = Buffer.from(data)
    } else if (type === 'IDAT') {
      idat.push(Buffer.from(data))
    } else if (type === 'IEND') {
      break
    }
  }

  if (!header) throw new Error('PNG is missing its IHDR header.')
  if (header.interlace) throw new Error('Interlaced PNGs are not supported.')
  const channels = CHANNELS[header.colorType]
  if (!channels) throw new Error(`Unsupported PNG color type ${header.colorType}`)
  if (![1, 2, 4, 8, 16].includes(header.bitDepth)) {
    throw new Error(`Unsupported PNG bit depth ${header.bitDepth}`)
  }

  const { width, height, bitDepth, colorType } = header
  const raw = zlib.inflateSync(Buffer.concat(idat))
  const bitsPerPixel = channels * bitDepth
  const bytesPerRow = Math.ceil((bitsPerPixel * width) / 8)
  const bpp = Math.max(1, Math.ceil(bitsPerPixel / 8))
  const rows = unfilter(raw, width, height, bpp, bytesPerRow)

  const data = new Uint8ClampedArray(width * height * 4)
  for (let y = 0; y < height; y += 1) {
    const row = rows.subarray(y * bytesPerRow, (y + 1) * bytesPerRow)
    const samples = readSamples(row, bitDepth, width * channels)
    for (let x = 0; x < width; x += 1) {
      const o = (y * width + x) * 4
      const s = x * channels
      switch (colorType) {
        case 0:
          data[o] = data[o + 1] = data[o + 2] = samples[s]
          data[o + 3] = 255
          break
        case 2:
          data[o] = samples[s]
          data[o + 1] = samples[s + 1]
          data[o + 2] = samples[s + 2]
          data[o + 3] = 255
          break
        case 3: {
          if (!palette) throw new Error('Indexed PNG is missing its palette.')
          // Palette indices must not be rescaled the way color samples are.
          const max = (1 << bitDepth) - 1
          const index = Math.round((samples[s] * max) / 255)
          data[o] = palette[index * 3]
          data[o + 1] = palette[index * 3 + 1]
          data[o + 2] = palette[index * 3 + 2]
          data[o + 3] = transparency && index < transparency.length ? transparency[index] : 255
          break
        }
        case 4:
          data[o] = data[o + 1] = data[o + 2] = samples[s]
          data[o + 3] = samples[s + 1]
          break
        case 6:
          data[o] = samples[s]
          data[o + 1] = samples[s + 1]
          data[o + 2] = samples[s + 2]
          data[o + 3] = samples[s + 3]
          break
        default:
          throw new Error(`Unsupported PNG color type ${colorType}`)
      }
    }
  }

  return { width, height, data }
}

/** Encode a flat RGBA image as an 8-bit RGBA PNG buffer. */
export function encodePng({ width, height, data }) {
  if (!width || !height) throw new Error('Cannot encode a zero-sized PNG.')
  const bytesPerRow = width * 4
  const raw = Buffer.alloc(height * (bytesPerRow + 1))
  for (let y = 0; y < height; y += 1) {
    const rowStart = y * (bytesPerRow + 1)
    raw[rowStart] = 0
    for (let x = 0; x < bytesPerRow; x += 1) {
      raw[rowStart + 1 + x] = data[y * bytesPerRow + x]
    }
  }

  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8
  ihdr[9] = 6
  ihdr[10] = 0
  ihdr[11] = 0
  ihdr[12] = 0

  return Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}
