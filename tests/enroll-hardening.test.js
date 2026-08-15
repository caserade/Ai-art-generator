import assert from 'node:assert/strict'
import { after, before, beforeEach, describe, test } from 'node:test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createServer } from 'node:http'

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gospel-test-'))
process.env.GOSPEL_DATA_DIR = path.join(tmpRoot, 'data')
process.env.GOSPEL_PAIRING_SECRET = 'test-pairing-secret-for-hardening'
process.env.GOSPEL_NO_LISTEN = '1'
process.env.GOSPEL_RP_ID = 'localhost'
process.env.GOSPEL_ORIGIN = 'http://127.0.0.1:0'

const { createApp } = await import('../server/index.js')
const { resetStateForTests, loadState } = await import('../server/state.js')

let server
let baseUrl

async function json(pathname, options = {}) {
  const res = await fetch(`${baseUrl}${pathname}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  })
  const body = await res.json().catch(() => ({}))
  return { status: res.status, body }
}

before(async () => {
  const app = createApp()
  server = createServer(app)
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address()
  baseUrl = `http://127.0.0.1:${port}`
  process.env.GOSPEL_ORIGIN = baseUrl
})

beforeEach(() => {
  resetStateForTests({ pairingSecret: process.env.GOSPEL_PAIRING_SECRET })
})

after(async () => {
  await new Promise((resolve) => server.close(resolve))
  fs.rmSync(tmpRoot, { recursive: true, force: true })
})

describe('Gospel Command API', () => {
  test('serves state and modules', async () => {
    const state = await json('/api/state')
    assert.equal(state.status, 200)
    assert.equal(state.body.unlocked, false)
    assert.equal(state.body.phoneEnrolled, false)

    const modules = await json('/api/modules')
    assert.equal(modules.status, 200)
    assert.ok(modules.body.modules.some((m) => m.id === 'fingerprint-scan'))
  })

  test('issues a challenge', async () => {
    const ch = await json('/api/challenge')
    assert.equal(ch.status, 200)
    assert.ok(ch.body.challenge)
    assert.equal(ch.body.rpId, 'localhost')
    assert.equal(ch.body.mode, 'enroll')
  })

  test('rejects credentialId-only enroll (the live-tunnel vuln)', async () => {
    await json('/api/challenge')
    const res = await json('/api/enroll', {
      method: 'POST',
      body: JSON.stringify({
        pairingSecret: process.env.GOSPEL_PAIRING_SECRET,
        credentialId: 'fake-cred-id-should-not-unlock',
      }),
    })
    assert.equal(res.status, 400)
    assert.match(res.body.message, /Hardened enroll|attestationObject/i)

    const state = await json('/api/state')
    assert.equal(state.body.unlocked, false)
    assert.equal(state.body.phoneEnrolled, false)
    assert.equal(loadState().credential, null)
  })

  test('rejects enroll with wrong pairing secret', async () => {
    await json('/api/challenge')
    const res = await json('/api/enroll', {
      method: 'POST',
      body: JSON.stringify({
        pairingSecret: 'wrong-secret',
        id: 'abc',
        rawId: 'abc',
        type: 'public-key',
        response: {
          clientDataJSON: 'e30',
          attestationObject: 'e30',
        },
        challenge: loadState().currentChallenge,
      }),
    })
    assert.equal(res.status, 401)
  })

  test('rejects unlock without full assertion', async () => {
    resetStateForTests({
      pairingSecret: process.env.GOSPEL_PAIRING_SECRET,
      phoneEnrolled: true,
      credential: {
        id: 'stored-cred',
        publicKey: Buffer.from('not-a-real-key').toString('base64url'),
        counter: 0,
        transports: [],
      },
    })
    const res = await json('/api/unlock', {
      method: 'POST',
      body: JSON.stringify({
        pairingSecret: process.env.GOSPEL_PAIRING_SECRET,
        credentialId: 'stored-cred',
      }),
    })
    assert.equal(res.status, 400)
    assert.match(res.body.message, /Hardened unlock|authenticatorData/i)
    assert.equal((await json('/api/state')).body.unlocked, false)
  })

  test('lock endpoint resets unlocked flag', async () => {
    resetStateForTests({
      pairingSecret: process.env.GOSPEL_PAIRING_SECRET,
      unlocked: true,
      phoneEnrolled: true,
      waitingForFingerprint: false,
    })
    const res = await json('/api/lock', { method: 'POST', body: '{}' })
    assert.equal(res.status, 200)
    assert.equal(res.body.status.unlocked, false)
  })
})
