import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const dataDir = process.env.GOSPEL_DATA_DIR || path.join(__dirname, '..', 'data')
const statePath = path.join(dataDir, 'state.json')

const BUILTIN_MODULES = [
  {
    id: 'fingerprint-scan',
    name: 'Fingerprint Scan',
    version: '1.0.0',
    kind: 'fingerprint-scan',
    enabled: true,
    builtin: true,
    description: "Uses this phone's fingerprint sensor (WebAuthn). Gospel never sees the print.",
    uploadedAt: 0,
  },
  {
    id: 'phone-find',
    name: 'Find Phone',
    version: '1.0.0',
    kind: 'phone-find',
    enabled: true,
    builtin: true,
    description: 'Finds this phone when it is connected to Gospel on the PC.',
    uploadedAt: 0,
  },
  {
    id: 'phonelink-bridge',
    name: 'Phone Link Bridge',
    version: '1.0.0',
    kind: 'phonelink-bridge',
    enabled: true,
    builtin: true,
    description: 'Falls back to Windows Phone Link when Bluetooth is not working.',
    uploadedAt: 0,
  },
  {
    id: 'ble-link',
    name: 'Gospel Bluetooth Link',
    version: '1.1.0',
    kind: 'phone-find',
    enabled: true,
    builtin: true,
    description: 'PC half Bluetooth-links to the WWW Gospel Command APK to finish fingerprint.',
    uploadedAt: 0,
  },
]

function defaultState() {
  const pairingSecret =
    process.env.GOSPEL_PAIRING_SECRET || crypto.randomBytes(24).toString('base64url')
  return {
    unlocked: false,
    phoneEnrolled: false,
    phoneName: 'USB phone',
    waitingForFingerprint: true,
    operatorName: process.env.GOSPEL_OPERATOR_NAME || 'Mike',
    pairingSecret,
    credential: null,
    currentChallenge: null,
    challengeExpiresAt: 0,
    uploadedModules: [],
    lockoutUntil: 0,
    failedAttempts: 0,
  }
}

function ensureDir() {
  fs.mkdirSync(dataDir, { recursive: true })
}

export function loadState() {
  ensureDir()
  if (!fs.existsSync(statePath)) {
    const state = defaultState()
    if (process.env.GOSPEL_PAIRING_SECRET) state.pairingSecret = process.env.GOSPEL_PAIRING_SECRET
    saveState(state)
    return state
  }
  const raw = JSON.parse(fs.readFileSync(statePath, 'utf8'))
  const state = { ...defaultState(), ...raw }
  if (process.env.GOSPEL_PAIRING_SECRET) state.pairingSecret = process.env.GOSPEL_PAIRING_SECRET
  return state
}

export function saveState(state) {
  ensureDir()
  const tmp = `${statePath}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2))
  fs.renameSync(tmp, statePath)
}

export function publicStatus(state) {
  return {
    unlocked: Boolean(state.unlocked),
    phoneEnrolled: Boolean(state.phoneEnrolled),
    phoneName: state.phoneName || 'USB phone',
    waitingForFingerprint: !state.unlocked && Boolean(state.waitingForFingerprint),
    challenge: state.currentChallenge || '',
    appName: 'WWW Gospel Command',
    link: {
      installed: true,
      running: true,
      connected: true,
      deviceName: '',
      message: 'Phone Link reports your phone is linked to this PC.',
    },
    nearbyVia: 'phonelink',
    usb: {
      connected: false,
      adb: false,
      deviceId: '',
      reversed: false,
      message:
        'USB cable is fine through Phone Link. For fingerprint over the wire, turn on USB debugging so Gospel can use ADB.',
    },
  }
}

export function listModules(state) {
  return [...BUILTIN_MODULES, ...(state.uploadedModules || [])]
}

export function resetStateForTests(overrides = {}) {
  ensureDir()
  const state = { ...defaultState(), ...overrides }
  saveState(state)
  return state
}

export { dataDir, statePath, BUILTIN_MODULES }
