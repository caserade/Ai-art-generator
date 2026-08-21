/**
 * Free Brain — on-device design intelligence, ported from the Flutter Game
 * Maker's `lib/ai_vision/free_brain.dart` to dependency-free ES modules so it
 * runs in the phone browser and on the server with zero API cost.
 *
 * Differences from the Dart original, all deliberate:
 *  - Tile writes go through a bounds-checked helper. Dart threw a
 *    RangeError on the out-of-range writes in the vertical/puzzle carvers; in
 *    JS the same writes would silently land on negative array keys and quietly
 *    drop tiles from the map.
 *  - The RNG is seedable, so a given brief always produces the same level and
 *    the behaviour is testable.
 */

export const TILE = {
  air: 0,
  solidGround: 1,
  hazard: 2,
  playerSpawn: 3,
  item: 4,
}

export const TILE_LEGEND = '0 air · 1 ground · 2 hazard · 3 spawn · 4 item'

export const TOOL_NAMES = [
  'design_game',
  'generate_level',
  'tune_physics',
  'suggest_art_pipeline',
  'explain_mechanics',
]

export const DEFAULT_PHYSICS = {
  gravityY: 980,
  moveSpeed: 170,
  jumpVelocity: 420,
  acceleration: 1200,
  friction: 0.85,
  airControl: 0.75,
  doubleJump: false,
}

/** Deterministic small-state PRNG (mulberry32) so levels are reproducible. */
export function createRng(seed = 1) {
  let a = seed >>> 0 || 1
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

export function seedFromString(text) {
  let hash = 2166136261
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

function clamp(value, min, max) {
  return value < min ? min : value > max ? max : value
}

function matches(lower, keys) {
  return keys.some((key) => lower.includes(key))
}

// —— Physics presets ——

export function physicsForDescription(description) {
  const lower = String(description || '').toLowerCase()
  let m = { ...DEFAULT_PHYSICS }
  if (matches(lower, ['floaty', 'dreamy', 'balloon'])) {
    m = { ...m, gravityY: 620, jumpVelocity: 380, airControl: 0.9 }
  }
  if (matches(lower, ['heavy', 'weighty', 'tank'])) {
    m = { ...m, gravityY: 1400, jumpVelocity: 460, friction: 0.9 }
  }
  if (matches(lower, ['fast', 'speed', 'sonic'])) {
    m = { ...m, moveSpeed: 260, acceleration: 1600 }
  }
  if (matches(lower, ['double jump', 'doublejump', 'air dash'])) {
    m = { ...m, doubleJump: true }
  }
  if (matches(lower, ['icy', 'ice', 'slippery'])) {
    m = { ...m, friction: 0.96, acceleration: 700 }
  }
  return m
}

export function inferLevelStyle(lower) {
  if (matches(lower, ['vertical', 'climb', 'tower'])) return 'vertical'
  if (matches(lower, ['speed', 'race', 'dash'])) return 'speedrun'
  if (matches(lower, ['puzzle', 'think', 'brain'])) return 'puzzle'
  if (matches(lower, ['hazard', 'spike', 'danger', 'gauntlet'])) return 'hazard_gauntlet'
  if (matches(lower, ['collect', 'coin', 'gem', 'hunt'])) return 'collectathon'
  return 'classic'
}

export function inferDifficulty(lower) {
  if (matches(lower, ['easy', 'chill', 'kids', 'relax'])) return 0.25
  if (matches(lower, ['hard', 'brutal', 'nightmare', 'punishing'])) return 0.85
  if (matches(lower, ['medium', 'normal'])) return 0.5
  return 0.45
}

export function guessTitle(prompt) {
  const words = String(prompt || '')
    .replace(/[^\w\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2)
    .slice(0, 3)
    .map((w) => w[0].toUpperCase() + w.slice(1).toLowerCase())
  return words.length ? words.join(' ') : 'Free Brain Game'
}

// —— Level generation ——

function createGrid(width, height) {
  const tiles = new Array(width * height).fill(TILE.air)
  const set = (x, y, value) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return false
    tiles[y * width + x] = value
    return true
  }
  const get = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return TILE.solidGround
    return tiles[y * width + x]
  }
  return { tiles, width, height, set, get }
}

function scatterHazards(grid, rng, count) {
  const y = grid.height - 3
  let placed = 0
  let guard = 0
  while (placed < count && guard < 400) {
    guard += 1
    const x = 1 + Math.floor(rng() * Math.max(1, grid.width - 2))
    if (grid.get(x, y) === TILE.air && grid.set(x, y, TILE.hazard)) placed += 1
  }
  return placed
}

function carveClassic(grid, rng, difficulty) {
  const platforms = 3 + Math.round(difficulty * 4)
  for (let i = 0; i < platforms; i += 1) {
    const span = Math.max(1, grid.height - 5)
    const y = 3 + Math.floor(rng() * span)
    const len = 3 + Math.floor(rng() * 5)
    const x0 = Math.floor(rng() * Math.max(1, grid.width - len))
    for (let x = x0; x < x0 + len; x += 1) grid.set(x, y, TILE.solidGround)
    if (rng() < 0.35 + difficulty * 0.4) {
      grid.set(x0 + Math.floor(len / 2), y - 1, TILE.item)
    }
  }
  scatterHazards(grid, rng, Math.round(2 + difficulty * 5))
}

function carveVertical(grid, rng, difficulty) {
  for (let step = 0; step < grid.height - 3; step += 2) {
    const y = grid.height - 3 - step
    if (y < 1) break
    const side = step % 2 === 0 ? 2 : Math.floor(grid.width / 2)
    const len = Math.floor(grid.width / 3)
    for (let x = side; x < side + len && x < grid.width - 1; x += 1) {
      grid.set(x, y, TILE.solidGround)
    }
    if (step % 3 === 0) grid.set(side + 1, y - 1, TILE.item)
  }
  scatterHazards(grid, rng, Math.round(1 + difficulty * 4))
}

function carveSpeedrun(grid, rng, difficulty) {
  let x = 2
  let y = grid.height - 4
  while (x < grid.width - 3) {
    const gap = 1 + Math.round(difficulty * 3)
    const run = 2 + Math.floor(rng() * 4)
    for (let i = 0; i < run && x < grid.width; i += 1, x += 1) {
      grid.set(x, y, TILE.solidGround)
    }
    x += gap
    y = clamp(y + (rng() < 0.5 ? -1 : 1), 3, grid.height - 3)
  }
  scatterHazards(grid, rng, Math.round(3 + difficulty * 4))
}

function carvePuzzle(grid, rng, difficulty) {
  const stride = Math.max(1, Math.floor((grid.width - 4) / 6))
  for (let i = 0; i < 6; i += 1) {
    const x = 2 + i * stride
    const y = grid.height - 4 - (i % 3)
    grid.set(x, y, TILE.solidGround)
    grid.set(x + 1, y, TILE.solidGround)
    if (i % 2 === 1) grid.set(x, y - 1, TILE.item)
  }
  scatterHazards(grid, rng, Math.round(1 + difficulty * 3))
}

function carveCollectathon(grid, rng, difficulty) {
  carveClassic(grid, rng, difficulty * 0.7)
  const extras = 8 + Math.round(difficulty * 6)
  for (let i = 0; i < extras; i += 1) {
    const x = 1 + Math.floor(rng() * Math.max(1, grid.width - 2))
    const y = 1 + Math.floor(rng() * Math.max(1, grid.height - 3))
    if (grid.get(x, y) === TILE.air) grid.set(x, y, TILE.item)
  }
}

function forceSpawn(grid) {
  for (let i = 0; i < grid.tiles.length; i += 1) {
    if (grid.tiles[i] === TILE.playerSpawn) grid.tiles[i] = TILE.air
  }
  grid.set(2, grid.height - 3, TILE.playerSpawn)
}

export function generateLevel({
  style = 'classic',
  width = 20,
  height = 12,
  difficulty = 0.45,
  seed = 1,
} = {}) {
  const w = Math.round(clamp(width, 12, 32))
  const h = Math.round(clamp(height, 8, 18))
  const d = clamp(difficulty, 0, 1)
  const rng = createRng(seed)
  const grid = createGrid(w, h)

  for (let x = 0; x < w; x += 1) {
    grid.set(x, h - 1, TILE.solidGround)
    grid.set(x, h - 2, TILE.solidGround)
  }

  switch (style) {
    case 'vertical':
      carveVertical(grid, rng, d)
      break
    case 'speedrun':
      carveSpeedrun(grid, rng, d)
      break
    case 'puzzle':
      carvePuzzle(grid, rng, d)
      break
    case 'hazard_gauntlet':
      carveClassic(grid, rng, d)
      scatterHazards(grid, rng, Math.round(6 + d * 8))
      break
    case 'collectathon':
      carveCollectathon(grid, rng, d)
      break
    default:
      carveClassic(grid, rng, d)
  }

  forceSpawn(grid)
  if (!grid.tiles.includes(TILE.item)) {
    grid.set(Math.floor(w / 2), 2, TILE.item)
  }

  return {
    width: w,
    height: h,
    tiles: grid.tiles,
    style,
    difficulty: d,
    hazards: grid.tiles.filter((t) => t === TILE.hazard).length,
    items: grid.tiles.filter((t) => t === TILE.item).length,
  }
}

/** Render a level as text rows — the phone UI draws these directly. */
export function levelToRows(map) {
  const rows = []
  for (let y = 0; y < map.height; y += 1) {
    rows.push(map.tiles.slice(y * map.width, (y + 1) * map.width).join(''))
  }
  return rows
}

function styleBiasPhysics(base, style, difficulty) {
  switch (style) {
    case 'speedrun':
      return {
        ...base,
        moveSpeed: base.moveSpeed + 40,
        acceleration: base.acceleration + 200,
        friction: clamp(base.friction - 0.05, 0.5, 0.98),
      }
    case 'vertical':
      return { ...base, jumpVelocity: base.jumpVelocity + 30, doubleJump: true, airControl: 0.85 }
    case 'hazard_gauntlet':
      return { ...base, gravityY: base.gravityY + 80 * difficulty, airControl: 0.7 }
    default:
      return base
  }
}

// —— MCP-style tools ——

export function invokeTool(name, args = {}) {
  switch (name) {
    case 'design_game':
      return toolDesignGame(args)
    case 'generate_level':
      return toolGenerateLevel(args)
    case 'tune_physics':
      return toolTunePhysics(args)
    case 'suggest_art_pipeline':
      return toolSuggestArt(args)
    case 'explain_mechanics':
      return toolExplain(args)
    default:
      return {
        toolName: name,
        ok: false,
        message: `Unknown tool "${name}". Available: ${TOOL_NAMES.join(', ')}.`,
      }
  }
}

function toolDesignGame({ prompt = '', name, seed }) {
  const lower = String(prompt).toLowerCase()
  const style = inferLevelStyle(lower)
  const difficulty = inferDifficulty(lower)
  const physics = styleBiasPhysics(physicsForDescription(prompt), style, difficulty)
  const map = generateLevel({
    style,
    width: style === 'vertical' ? 14 : 22,
    height: style === 'vertical' ? 16 : 12,
    difficulty,
    seed: seed ?? seedFromString(prompt),
  })
  const title = String(name || '').trim() || guessTitle(prompt)
  const brief = prompt.length > 120 ? `${prompt.slice(0, 120)}…` : prompt
  return {
    toolName: 'design_game',
    ok: true,
    message:
      `Designed "${title}" (${style}, difficulty ${Math.round(difficulty * 100)}%).\n` +
      `Style: ${style} · Physics: g=${Math.round(physics.gravityY)} / spd=${Math.round(physics.moveSpeed)} / jmp=${Math.round(physics.jumpVelocity)}` +
      `${physics.doubleJump ? ' / double-jump' : ''}.\nBrief: ${brief}`,
    project: { name: title, description: prompt, map, physics },
    map,
    physics,
    data: { style, difficulty },
  }
}

function toolGenerateLevel({ style, difficulty, width, height, seed, prompt = '' }) {
  const lower = String(prompt).toLowerCase()
  const map = generateLevel({
    style: style || inferLevelStyle(lower),
    difficulty: difficulty ?? inferDifficulty(lower),
    width: width ?? 20,
    height: height ?? 12,
    seed: seed ?? seedFromString(prompt || style || 'level'),
  })
  return {
    toolName: 'generate_level',
    ok: true,
    message: `Generated ${map.style} level ${map.width}x${map.height} with ${map.hazards} hazards and ${map.items} items.\nLegend: ${TILE_LEGEND}`,
    map,
    data: { style: map.style, difficulty: map.difficulty },
  }
}

function toolTunePhysics({ description = '' }) {
  const lower = String(description).toLowerCase()
  let m = physicsForDescription(description)
  if (matches(lower, ['super float', 'moon'])) {
    m = { ...m, gravityY: 480, jumpVelocity: 360, airControl: 0.95, doubleJump: true }
  } else if (matches(lower, ['sticky', 'ice'])) {
    m = { ...m, friction: 0.96, acceleration: 700, airControl: 0.3 }
  } else if (matches(lower, ['arcade', 'mario'])) {
    m = { ...m, gravityY: 1100, jumpVelocity: 460, moveSpeed: 200, friction: 0.8 }
  } else if (matches(lower, ['precision', 'celeste'])) {
    m = {
      ...m,
      gravityY: 900,
      jumpVelocity: 400,
      moveSpeed: 190,
      acceleration: 1400,
      friction: 0.78,
      doubleJump: true,
      airControl: 0.9,
    }
  }
  return {
    toolName: 'tune_physics',
    ok: true,
    message:
      `Physics tuned for “${description}”.\n` +
      `g=${Math.round(m.gravityY)} spd=${Math.round(m.moveSpeed)} jmp=${Math.round(m.jumpVelocity)}` +
      `${m.doubleJump ? ' · double-jump' : ''}`,
    physics: m,
    data: m,
  }
}

function toolSuggestArt({ character = 'hero' }) {
  const lower = String(character).toLowerCase()
  const frameSize = matches(lower, ['boss', 'big', 'giant']) ? 128 : 64
  const threshold = matches(lower, ['sketch', 'pencil', 'faint']) ? 55 : 42
  const frames = 'Idle → Walk A → Walk B → Jump'
  return {
    toolName: 'suggest_art_pipeline',
    ok: true,
    message:
      `Art pipeline for “${character}”:\n` +
      '• Capture on a plain contrasting background\n' +
      `• Threshold ≈ ${threshold} · target ${frameSize}×${frameSize}\n` +
      `• Sprite sheet frames: ${frames}\n` +
      '• Auto-hitbox from the opaque pixels of the Idle frame\n' +
      'Open the Art Scan module and these settings are already the defaults.',
    data: { frameSize, threshold, frames, module: 'art-scan' },
  }
}

function toolExplain({ question = '', physics }) {
  const p = { ...DEFAULT_PHYSICS, ...(physics || {}) }
  const feel =
    p.gravityY < 700 ? 'floaty / dreamy' : p.gravityY > 1200 ? 'snappy / weighty' : 'balanced arcade'
  return {
    toolName: 'explain_mechanics',
    ok: true,
    message:
      `Free Brain read: current feel is ${feel} ` +
      `(g=${Math.round(p.gravityY)}, move=${Math.round(p.moveSpeed)}, jump=${Math.round(p.jumpVelocity)}` +
      `${p.doubleJump ? ', double-jump on' : ''}).\n` +
      `Q: ${question}\n` +
      'Try “make it floaty double jump” or “generate a hazard gauntlet map” — I route those through tools instantly, free.',
    physics: p,
  }
}

/**
 * Ordered routing rules. Order matters: the first match wins, so excluding a
 * tool makes the message fall through to the next best interpretation.
 */
const ROUTING_RULES = [
  {
    tool: 'design_game',
    test: (lower, wordCount) =>
      wordCount >= 6 ||
      matches(lower, [
        'design',
        'make a game',
        'create a game',
        'build me',
        'new game',
        'platformer',
        'metroidvania',
        'roguelike',
      ]),
    args: (text) => ({ prompt: text, name: guessTitle(text) }),
  },
  {
    tool: 'generate_level',
    test: (lower) => matches(lower, ['level', 'map', 'stage', 'generate map', 'new map']),
    args: (text, lower) => ({
      prompt: text,
      style: inferLevelStyle(lower),
      difficulty: inferDifficulty(lower),
    }),
  },
  {
    tool: 'tune_physics',
    test: (lower) =>
      matches(lower, ['physics', 'gravity', 'feel', 'floaty', 'tight', 'controls', 'icy', 'moon']),
    args: (text) => ({ description: text }),
  },
  {
    tool: 'suggest_art_pipeline',
    test: (lower) => matches(lower, ['art', 'sprite', 'character', 'scan', 'draw']),
    args: (text) => ({ character: text }),
  },
]

const FALLBACK_TOOL = 'explain_mechanics'

/**
 * Pick the tool a free-text message should route to.
 *
 * `exclude` lists tools the user has told us are wrong for this phrase, so the
 * message falls through to the next rule instead.
 */
export function routeIntent(message, { exclude = [] } = {}) {
  const text = String(message || '').trim()
  if (!text) return null
  const lower = text.toLowerCase()
  const wordCount = text.split(/\s+/).filter(Boolean).length

  for (const rule of ROUTING_RULES) {
    if (exclude.includes(rule.tool)) continue
    if (rule.test(lower, wordCount)) {
      return { tool: rule.tool, args: rule.args(text, lower) }
    }
  }
  // Always answer with something, even if every tool has been demoted.
  return { tool: FALLBACK_TOOL, args: { question: text } }
}

/**
 * Answer a free-text message with Free Brain alone (no learned memory).
 * The router layers persistent learning on top of this.
 */
export function think(message, { physics, exclude = [] } = {}) {
  const route = routeIntent(message, { exclude })
  if (!route) {
    return {
      ok: true,
      source: 'free-brain',
      text: 'Tell me the game you want — genre, feel, or a one-line fantasy.',
    }
  }
  const args = { ...route.args }
  if (route.tool === 'explain_mechanics' && physics) args.physics = physics
  const result = invokeTool(route.tool, args)
  const suffix =
    route.tool === 'design_game' ? '\n\nTip: say “generate map” or “make it floaty” to refine.' : ''
  return {
    ok: true,
    source: 'free-brain',
    tool: route.tool,
    text: `${result.message}${suffix}`,
    result,
  }
}
