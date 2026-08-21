import assert from 'node:assert/strict'
import { after, before, beforeEach, describe, test } from 'node:test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createServer } from 'node:http'

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gospel-learning-'))
process.env.GOSPEL_MODULE_DATA_DIR = path.join(tmpRoot, 'modules')

const {
  TILE,
  TOOL_NAMES,
  generateLevel,
  invokeTool,
  levelToRows,
  routeIntent,
  think,
} = await import('../modules/learning/brain.js')
const { createMemory, MEMORY_DEFAULTS, signature, similarity, tokenize } = await import(
  '../modules/learning/memory.js'
)
const { createStore } = await import('../modules/shared/store.js')
const { createModuleApp } = await import('../modules/host.js')
const { learningModule } = await import('../modules/learning/index.js')

let server
let baseUrl

before(async () => {
  server = createServer(createModuleApp(learningModule))
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

function freshMemory(dirName) {
  const dir = path.join(tmpRoot, dirName)
  return createMemory(createStore({ dir, file: 'memory.json', defaults: MEMORY_DEFAULTS }))
}

const ALL_STYLES = [
  'classic',
  'vertical',
  'speedrun',
  'puzzle',
  'hazard_gauntlet',
  'collectathon',
]

describe('level generation', () => {
  test('every style produces a valid, fully in-bounds grid', () => {
    for (const style of ALL_STYLES) {
      for (const seed of [1, 7, 4242]) {
        const map = generateLevel({ style, seed, difficulty: 0.8 })
        assert.equal(
          map.tiles.length,
          map.width * map.height,
          `${style} grid length must match its dimensions`,
        )
        for (const tile of map.tiles) {
          assert.ok(
            Object.values(TILE).includes(tile),
            `${style} produced an unexpected tile ${tile}`,
          )
        }
        // The Dart carvers wrote past row ends and above row 0. In JS those
        // writes would have landed on stray array keys instead of throwing.
        assert.equal(
          Object.keys(map.tiles).length,
          map.width * map.height,
          `${style} wrote outside the grid`,
        )
        assert.equal(
          map.tiles.filter((t) => t === TILE.playerSpawn).length,
          1,
          `${style} needs exactly one spawn`,
        )
        assert.ok(map.items >= 1, `${style} needs at least one item`)
      }
    }
  })

  test('is deterministic for a seed and varies across seeds', () => {
    const a = generateLevel({ style: 'classic', seed: 99 })
    const b = generateLevel({ style: 'classic', seed: 99 })
    const c = generateLevel({ style: 'classic', seed: 100 })
    assert.deepEqual(a.tiles, b.tiles)
    assert.notDeepEqual(a.tiles, c.tiles)
  })

  test('clamps absurd dimensions', () => {
    const tiny = generateLevel({ width: 2, height: 2, seed: 1 })
    assert.equal(tiny.width, 12)
    assert.equal(tiny.height, 8)
    const huge = generateLevel({ width: 999, height: 999, seed: 1 })
    assert.equal(huge.width, 32)
    assert.equal(huge.height, 18)
  })

  test('always lays a solid floor', () => {
    const map = generateLevel({ style: 'speedrun', seed: 5 })
    for (let x = 0; x < map.width; x += 1) {
      assert.equal(map.tiles[(map.height - 1) * map.width + x], TILE.solidGround)
    }
  })

  test('renders one row string per grid row', () => {
    const map = generateLevel({ style: 'puzzle', seed: 3 })
    const rows = levelToRows(map)
    assert.equal(rows.length, map.height)
    for (const row of rows) assert.equal(row.length, map.width)
  })
})

describe('intent routing', () => {
  test('routes each kind of request to the matching tool', () => {
    assert.equal(routeIntent('design a brutal vertical climbing platformer').tool, 'design_game')
    assert.equal(routeIntent('generate map').tool, 'generate_level')
    assert.equal(routeIntent('floaty').tool, 'tune_physics')
    assert.equal(routeIntent('sprite').tool, 'suggest_art_pipeline')
    assert.equal(routeIntent('coyote time').tool, 'explain_mechanics')
    assert.equal(routeIntent('   '), null)
  })

  test('every advertised tool returns a message', () => {
    for (const name of TOOL_NAMES) {
      const result = invokeTool(name, { prompt: 'test', description: 'icy', question: 'why' })
      assert.equal(result.ok, true, `${name} should succeed`)
      assert.ok(result.message.length > 0, `${name} should say something`)
    }
  })

  test('reports unknown tools instead of throwing', () => {
    const result = invokeTool('teleport', {})
    assert.equal(result.ok, false)
    assert.match(result.message, /Unknown tool/)
  })

  test('an empty message asks for a brief', () => {
    assert.match(think('').text, /Tell me the game/)
  })

  test('excluding a tool falls through to the next interpretation', () => {
    assert.equal(routeIntent('sprite palette').tool, 'suggest_art_pipeline')
    assert.equal(
      routeIntent('sprite palette', { exclude: ['suggest_art_pipeline'] }).tool,
      'explain_mechanics',
    )
    // "generate a hazard map" matches the level rule first, then physics-free
    // wording sends it to the general explainer.
    assert.equal(routeIntent('generate a hazard map').tool, 'generate_level')
    assert.equal(
      routeIntent('generate a hazard map', { exclude: ['generate_level', 'design_game'] }).tool,
      'explain_mechanics',
    )
  })

  test('still answers when every tool has been rejected', () => {
    const route = routeIntent('sprite palette', {
      exclude: [...TOOL_NAMES],
    })
    assert.equal(route.tool, 'explain_mechanics', 'never refuses to answer')
  })

  test('the art tool points at the Art Scan module', () => {
    const result = invokeTool('suggest_art_pipeline', { character: 'giant boss sketch' })
    assert.equal(result.data.module, 'art-scan')
    assert.equal(result.data.frameSize, 128, 'a boss gets the larger frame')
    assert.equal(result.data.threshold, 55, 'a sketch gets the looser threshold')
  })
})

describe('memory helpers', () => {
  test('tokenizing drops filler words', () => {
    assert.deepEqual(tokenize('What is the ART style for you?'), ['art', 'style'])
  })

  test('signatures ignore word order', () => {
    assert.equal(signature('floaty gem platformer'), signature('platformer gem floaty'))
  })

  test('similarity is a Jaccard overlap', () => {
    assert.equal(similarity(['a', 'b'], ['a', 'b']), 1)
    assert.equal(similarity(['a'], ['b']), 0)
  })
})

describe('learning memory', () => {
  test('recalls a taught answer from a paraphrase', () => {
    const mem = freshMemory('recall')
    mem.teach({ trigger: 'our art style', response: 'Neon green on near-black.' })
    const hit = mem.recall('what is our art style?')
    assert.ok(hit, 'paraphrase should match the lesson')
    assert.equal(hit.lesson.response, 'Neon green on near-black.')
    assert.equal(mem.recall('generate a hazard map'), null, 'unrelated asks must not match')
  })

  test('re-teaching a trigger updates it instead of duplicating', () => {
    const mem = freshMemory('reteach')
    mem.teach({ trigger: 'jump feel', response: 'Snappy.' })
    mem.teach({ trigger: 'jump feel', response: 'Floaty now.' })
    const state = mem.read()
    assert.equal(state.lessons.length, 1)
    assert.equal(state.lessons[0].response, 'Floaty now.')
  })

  test('rejects an empty or filler-only lesson', () => {
    const mem = freshMemory('bad-teach')
    assert.throws(() => mem.teach({ trigger: '', response: 'x' }), /trigger/i)
    assert.throws(() => mem.teach({ trigger: 'x', response: '' }), /response/i)
    assert.throws(() => mem.teach({ trigger: 'the a of', response: 'x' }), /filler/i)
  })

  test('forgetting a lesson stops it being recalled', () => {
    const mem = freshMemory('forget')
    const lesson = mem.teach({ trigger: 'tile legend', response: '0 air 1 ground' })
    assert.ok(mem.recall('tile legend'))
    assert.ok(mem.forget(lesson.id))
    assert.equal(mem.recall('tile legend'), null)
    assert.equal(mem.forget('nope'), null)
  })

  test('counts hits on a recalled lesson', () => {
    const mem = freshMemory('hits')
    const lesson = mem.teach({ trigger: 'physics preset', response: 'Celeste-ish.' })
    mem.markRecalled(lesson.id)
    mem.markRecalled(lesson.id)
    assert.equal(mem.read().lessons[0].hits, 2)
    assert.equal(mem.summary().recalled, 2)
  })

  test('feedback retrains routing and survives a restart', () => {
    const mem = freshMemory('retrain')
    const turn = mem.recordInteraction({ message: 'sprite colors', tool: 'suggest_art_pipeline' })
    assert.equal(mem.routePreference('sprite colors'), null, 'no preference before feedback')

    mem.reinforce({ interactionId: turn.id, helpful: false, preferTool: 'explain_mechanics' })
    assert.equal(mem.routePreference('sprite colors'), 'explain_mechanics')
    assert.equal(mem.routePreference('colors sprite'), 'explain_mechanics', 'word order agnostic')

    // A brand new store over the same directory is what a restart looks like.
    assert.equal(freshMemory('retrain').routePreference('sprite colors'), 'explain_mechanics')
  })

  test('a single stray rating does not promote a tool', () => {
    const mem = freshMemory('margin')
    const turn = mem.recordInteraction({ message: 'gravity tuning', tool: 'tune_physics' })
    mem.reinforce({ interactionId: turn.id, helpful: true })
    assert.equal(mem.routePreference('gravity tuning'), null, 'one vote is below the margin')
  })

  test('one rejection demotes a tool for that phrase, and a thumbs-up undoes it', () => {
    const mem = freshMemory('demote')
    assert.deepEqual(mem.demotedTools('sprite palette'), [])

    const first = mem.recordInteraction({ message: 'sprite palette', tool: 'suggest_art_pipeline' })
    mem.reinforce({ interactionId: first.id, helpful: false })
    assert.deepEqual(mem.demotedTools('sprite palette'), ['suggest_art_pipeline'])
    assert.deepEqual(freshMemory('demote').demotedTools('sprite palette'), ['suggest_art_pipeline'])

    const second = mem.recordInteraction({ message: 'sprite palette', tool: 'suggest_art_pipeline' })
    mem.reinforce({ interactionId: second.id, helpful: true })
    assert.deepEqual(mem.demotedTools('sprite palette'), [], 'approval clears the demotion')
  })

  test('rejects feedback for an unknown interaction', () => {
    const mem = freshMemory('unknown-feedback')
    assert.throws(() => mem.reinforce({ interactionId: 'nope', helpful: true }), /Unknown/)
  })
})

describe('Learning API (standalone, no Gospel state)', () => {
  beforeEach(async () => {
    const state = await json('/api/memory')
    for (const lesson of state.body.lessons || []) {
      await json(`/api/memory/${lesson.id}`, { method: 'DELETE' })
    }
  })

  test('reports itself as a standalone module', async () => {
    const res = await json('/api/health')
    assert.equal(res.status, 200)
    assert.equal(res.body.module, 'learning')
    assert.equal(res.body.standalone, true)
  })

  test('lists its tools and legend', async () => {
    const res = await json('/api/tools')
    assert.deepEqual(res.body.tools, TOOL_NAMES)
    assert.match(res.body.legend, /air/)
  })

  test('designs a game with a drawable map', async () => {
    const res = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'make a floaty gem-hunt platformer' }),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.source, 'free-brain')
    assert.equal(res.body.tool, 'design_game')
    assert.ok(res.body.interactionId)
    assert.equal(res.body.result.map.rows.length, res.body.result.map.height)
    assert.match(res.body.text, /Designed/)
  })

  test('rejects an empty question', async () => {
    const res = await json('/api/ask', { method: 'POST', body: JSON.stringify({ message: '  ' }) })
    assert.equal(res.status, 400)
  })

  test('teaches, then answers that phrase from memory', async () => {
    const taught = await json('/api/teach', {
      method: 'POST',
      body: JSON.stringify({ trigger: 'shipping checklist', response: 'Tests, then tunnel.' }),
    })
    assert.equal(taught.status, 201)

    const asked = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'what is the shipping checklist?' }),
    })
    assert.equal(asked.body.source, 'learned')
    assert.equal(asked.body.text, 'Tests, then tunnel.')
    assert.equal(asked.body.learnedFrom.trigger, 'shipping checklist')
    assert.equal(asked.body.summary.recalled, 1)
  })

  test('rejecting an answer reroutes that phrase next time', async () => {
    // What the phone's "Not what I meant" button sends: no preferred tool.
    const first = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'character outline' }),
    })
    assert.equal(first.body.tool, 'suggest_art_pipeline')
    assert.equal(first.body.trainedRouting, false)

    const rated = await json('/api/feedback', {
      method: 'POST',
      body: JSON.stringify({ interactionId: first.body.interactionId, helpful: false }),
    })
    assert.equal(rated.status, 200)

    const second = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'character outline' }),
    })
    assert.equal(second.body.tool, 'explain_mechanics', 'the rejected tool was skipped')
    assert.equal(second.body.trainedRouting, true)
  })

  test('an explicit preferred tool is promoted for that phrase', async () => {
    const first = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'sprite palette' }),
    })
    assert.equal(first.body.tool, 'suggest_art_pipeline')

    await json('/api/feedback', {
      method: 'POST',
      body: JSON.stringify({
        interactionId: first.body.interactionId,
        helpful: false,
        preferTool: 'tune_physics',
      }),
    })

    const second = await json('/api/ask', {
      method: 'POST',
      body: JSON.stringify({ message: 'sprite palette' }),
    })
    assert.equal(second.body.tool, 'tune_physics', 'routing was retrained to the chosen tool')
    assert.equal(second.body.trainedRouting, true)
  })

  test('invokes a named tool directly', async () => {
    const res = await json('/api/tools/generate_level', {
      method: 'POST',
      body: JSON.stringify({ style: 'vertical', difficulty: 0.9, seed: 11 }),
    })
    assert.equal(res.status, 200)
    assert.equal(res.body.result.map.style, 'vertical')
    assert.equal(res.body.result.map.rows.length, res.body.result.map.height)
  })

  test('404s an unknown tool or lesson', async () => {
    assert.equal((await json('/api/tools/teleport', { method: 'POST', body: '{}' })).status, 404)
    assert.equal((await json('/api/memory/nope', { method: 'DELETE' })).status, 404)
  })
})
