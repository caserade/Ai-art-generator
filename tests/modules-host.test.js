import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createServer } from 'node:http'

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gospel-host-'))
process.env.GOSPEL_DATA_DIR = path.join(tmpRoot, 'data')
process.env.GOSPEL_PAIRING_SECRET = 'host-test-pairing-secret'
process.env.GOSPEL_NO_LISTEN = '1'
process.env.GOSPEL_RP_ID = 'localhost'

const { createApp } = await import('../server/index.js')
const { resetStateForTests } = await import('../server/state.js')
const { createModuleApp } = await import('../modules/host.js')
const { MODULES, MODULE_MOUNT, getModule, mountPathFor, moduleIds } = await import(
  '../modules/registry.js'
)

let mainServer
let mainUrl
const standalone = new Map()

before(async () => {
  mainServer = createServer(createApp())
  await new Promise((resolve) => mainServer.listen(0, '127.0.0.1', resolve))
  mainUrl = `http://127.0.0.1:${mainServer.address().port}`

  for (const descriptor of MODULES) {
    const server = createServer(createModuleApp(descriptor))
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
    standalone.set(descriptor.id, {
      server,
      url: `http://127.0.0.1:${server.address().port}`,
    })
  }
})

after(async () => {
  for (const { server } of standalone.values()) {
    await new Promise((resolve) => server.close(resolve))
  }
  await new Promise((resolve) => mainServer.close(resolve))
  fs.rmSync(tmpRoot, { recursive: true, force: true })
})

async function text(url) {
  const res = await fetch(url)
  return { status: res.status, type: res.headers.get('content-type') || '', body: await res.text() }
}

async function json(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
  })
  return { status: res.status, body: await res.json().catch(() => ({})) }
}

describe('module registry', () => {
  test('exposes Art Scan and Learning', () => {
    assert.deepEqual(moduleIds().sort(), ['art-scan', 'learning'])
    assert.ok(getModule('art-scan'))
    assert.equal(getModule('nope'), null)
    assert.equal(mountPathFor('learning'), '/m/learning/')
  })
})

describe('module shell served from the main app', () => {
  for (const id of ['art-scan', 'learning']) {
    test(`${id} serves a UI at ${MODULE_MOUNT}/${id}/`, async () => {
      const res = await text(`${mainUrl}${MODULE_MOUNT}/${id}/`)
      assert.equal(res.status, 200)
      assert.match(res.type, /html/)
      assert.match(res.body, new RegExp(`<base href="/m/${id}/" />`))
      assert.match(res.body, /<script type="module" src="app\.js">/)
    })

    test(`${id} resolves assets without the trailing slash`, async () => {
      // A phone that types the URL by hand omits the slash; the injected <base>
      // is absolute so relative assets still resolve to the module, not to /m/.
      const res = await text(`${mainUrl}${MODULE_MOUNT}/${id}`)
      assert.equal(res.status, 200)
      assert.match(res.body, new RegExp(`<base href="/m/${id}/" />`))
    })

    test(`${id} scopes its manifest to its mount`, async () => {
      const mounted = await json(`${mainUrl}${MODULE_MOUNT}/${id}/manifest.webmanifest`)
      assert.equal(mounted.status, 200)
      assert.equal(mounted.body.scope, `/m/${id}/`)
      assert.equal(mounted.body.start_url, `/m/${id}/`)

      const alone = await json(`${standalone.get(id).url}/manifest.webmanifest`)
      assert.equal(alone.body.scope, '/', 'standalone owns the whole origin')
    })

    test(`${id} ships a service worker that never caches its API`, async () => {
      const res = await text(`${mainUrl}${MODULE_MOUNT}/${id}/sw.js`)
      assert.equal(res.status, 200)
      assert.match(res.type, /javascript/)
      assert.match(res.body, new RegExp(`const BASE = "/m/${id}/"`))
      assert.match(res.body, /BASE \+ 'api\/'/, 'API requests are singled out')
      assert.match(res.body, /caches\.match\(BASE\)/, 'offline fallback is the module shell')
    })

    test(`${id} serves its own icon and stylesheet`, async () => {
      for (const asset of ['icon.png', 'gospel.css', 'app.js']) {
        const res = await fetch(`${mainUrl}${MODULE_MOUNT}/${id}/${asset}`)
        assert.equal(res.status, 200, `${asset} should be served`)
      }
    })
  }

  test('art-scan serves the pipeline as a browser module', async () => {
    const res = await text(`${mainUrl}${MODULE_MOUNT}/art-scan/pipeline.js`)
    assert.equal(res.status, 200)
    assert.match(res.body, /export function processScan/)
    assert.doesNotMatch(res.body, /require\(|node:/, 'must stay browser-safe')
  })

  test('learning serves the brain as a browser module', async () => {
    const res = await text(`${mainUrl}${MODULE_MOUNT}/learning/brain.js`)
    assert.equal(res.status, 200)
    assert.match(res.body, /export function generateLevel/)
    assert.doesNotMatch(res.body, /require\(|node:/, 'must stay browser-safe')
  })
})

describe('modules do not depend on the main app', () => {
  test('they work while the PC is locked and no phone is enrolled', async () => {
    resetStateForTests({
      pairingSecret: process.env.GOSPEL_PAIRING_SECRET,
      unlocked: false,
      phoneEnrolled: false,
      credential: null,
      waitingForFingerprint: true,
    })

    const state = await json(`${mainUrl}/api/state`)
    assert.equal(state.body.unlocked, false)
    assert.equal(state.body.phoneEnrolled, false)

    // This is the whole point: no unlock, no enrollment, no pairing secret, and
    // both modules still answer.
    const art = await json(`${mainUrl}${MODULE_MOUNT}/art-scan/api/health`)
    assert.equal(art.status, 200)
    assert.equal(art.body.ok, true)

    const learn = await json(`${mainUrl}${MODULE_MOUNT}/learning/api/ask`, {
      method: 'POST',
      body: JSON.stringify({ message: 'generate a hazard gauntlet map' }),
    })
    assert.equal(learn.status, 200)
    assert.equal(learn.body.result.map.style, 'hazard_gauntlet')
  })

  test('they need no pairing secret', async () => {
    const res = await json(`${mainUrl}${MODULE_MOUNT}/learning/api/tools`)
    assert.equal(res.status, 200)
    assert.ok(res.body.tools.length > 0)
  })

  test('standalone processes report standalone, mounted ones do not', async () => {
    for (const id of moduleIds()) {
      const alone = await json(`${standalone.get(id).url}/api/health`)
      assert.equal(alone.body.standalone, true)
      assert.equal(alone.body.mountedAt, '/')

      const mounted = await json(`${mainUrl}${MODULE_MOUNT}/${id}/api/health`)
      assert.equal(mounted.body.standalone, false)
      assert.equal(mounted.body.mountedAt, `/m/${id}/`)
    }
  })

  test('a standalone module 404s in its own voice', async () => {
    const res = await json(`${standalone.get('art-scan').url}/nope`)
    assert.equal(res.status, 404)
    assert.match(res.body.message, /art-scan/)
  })
})

describe('main app advertises the modules', () => {
  test('/api/modules lists them first, with launchable urls', async () => {
    const res = await json(`${mainUrl}/api/modules`)
    assert.equal(res.status, 200)
    const launchable = res.body.modules.filter((m) => m.url)
    assert.equal(launchable.length, 2)
    assert.deepEqual(
      launchable.map((m) => m.url).sort(),
      ['/m/art-scan/', '/m/learning/'],
    )
    for (const mod of launchable) {
      assert.equal(mod.standalone, true)
      assert.ok(mod.description, 'the launcher needs a description to show')
    }
    // The legacy fingerprint modules must survive alongside them.
    assert.ok(res.body.modules.some((m) => m.id === 'fingerprint-scan'))
  })

  test('/api/bridge hands the phone absolute module urls', async () => {
    const res = await json(`${mainUrl}/api/bridge`)
    assert.equal(res.status, 200)
    assert.equal(res.body.modules.length, 2)
    for (const mod of res.body.modules) {
      assert.match(mod.url, /^https?:\/\/.+\/m\/(art-scan|learning)\/$/)
    }
  })

  test('the phone shell renders a launcher and escapes module text', async () => {
    const res = await text(`${mainUrl}/`)
    assert.equal(res.status, 200)
    assert.match(res.body, /id="launcher"/)
    // Module names come from an unauthenticated POST /api/modules, so the shell
    // must escape them rather than injecting them as HTML.
    assert.match(res.body, /function escapeHtml/)
    assert.match(res.body, /escapeHtml\(m\.name\)/)
  })

  test('the main service worker leaves live state and modules uncached', async () => {
    const res = await text(`${mainUrl}/sw.js`)
    assert.equal(res.status, 200)
    assert.match(res.body, /startsWith\('\/api\/'\)/, 'API responses bypass the cache')
    assert.match(res.body, /startsWith\('\/m\/'\)/, 'module scopes are left alone')
  })
})

describe('main app not-found handling', () => {
  test('an html navigation gets a page with module links', async () => {
    const res = await text(`${mainUrl}/definitely-not-a-page`)
    assert.equal(res.status, 404)
    assert.match(res.type, /html/)
    assert.match(res.body, /\/m\/art-scan\//)
    assert.match(res.body, /\/m\/learning\//)
  })

  test('an api call still gets json', async () => {
    const res = await fetch(`${mainUrl}/api/nope`, { headers: { Accept: 'application/json' } })
    assert.equal(res.status, 404)
    assert.match(res.headers.get('content-type') || '', /json/)
    assert.equal((await res.json()).ok, false)
  })
})
