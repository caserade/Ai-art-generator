import {
  generateRegistrationOptions,
  generateAuthenticationOptions,
  verifyRegistrationResponse,
  verifyAuthenticationResponse,
} from '@simplewebauthn/server'
import { saveState } from './state.js'

const CHALLENGE_TTL_MS = 5 * 60 * 1000

export function getRpId(req) {
  const forced = process.env.GOSPEL_RP_ID
  if (forced) return forced
  const host = String(req.hostname || '').split(':')[0]
  if (!host || host === 'localhost' || /^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    return 'localhost'
  }
  return host
}

export function getOrigins(req) {
  const forced = process.env.GOSPEL_ORIGIN
  if (forced) return [forced]
  const proto = req.protocol || 'http'
  const host = req.get('host') || `localhost:${process.env.PORT || 8788}`
  return [`${proto}://${host}`, `http://localhost:${process.env.PORT || 8788}`, `http://127.0.0.1:${process.env.PORT || 8788}`]
}

export async function issueChallenge(state, req, { forEnroll }) {
  const rpID = getRpId(req)
  let options
  if (forEnroll || !state.credential) {
    options = await generateRegistrationOptions({
      rpName: 'WWW Gospel Command',
      rpID,
      userName: 'mike',
      userDisplayName: state.operatorName || 'Mike',
      userID: new TextEncoder().encode('mike-operator-phone'),
      attestationType: 'none',
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        userVerification: 'required',
        residentKey: 'preferred',
      },
      supportedAlgorithmIDs: [-7, -257],
    })
  } else {
    options = await generateAuthenticationOptions({
      rpID,
      allowCredentials: [
        {
          id: state.credential.id,
          transports: state.credential.transports,
        },
      ],
      userVerification: 'required',
    })
  }

  state.currentChallenge = options.challenge
  state.challengeExpiresAt = Date.now() + CHALLENGE_TTL_MS
  saveState(state)
  return { options, rpID }
}

function assertFreshChallenge(state, challenge) {
  if (!state.currentChallenge || !challenge) {
    throw new Error('No active challenge. Refresh and try again.')
  }
  if (state.currentChallenge !== challenge) {
    throw new Error('Challenge mismatch. Refresh and try again.')
  }
  if (Date.now() > Number(state.challengeExpiresAt || 0)) {
    throw new Error('Challenge expired. Refresh and try again.')
  }
}

export async function verifyEnroll(state, req, body) {
  const {
    pairingSecret,
    id,
    rawId,
    type,
    response,
    challenge,
  } = body || {}

  if (!pairingSecret || pairingSecret !== state.pairingSecret) {
    const err = new Error('Invalid pairing secret.')
    err.status = 401
    throw err
  }

  if (!response?.clientDataJSON || !response?.attestationObject || !id || !rawId) {
    const err = new Error(
      'Hardened enroll requires a full WebAuthn registration response (attestationObject + clientDataJSON). credentialId alone is rejected.',
    )
    err.status = 400
    throw err
  }

  assertFreshChallenge(state, challenge || state.currentChallenge)

  const verification = await verifyRegistrationResponse({
    response: {
      id,
      rawId: rawId || id,
      type: type || 'public-key',
      response,
      clientExtensionResults: body.clientExtensionResults || {},
    },
    expectedChallenge: state.currentChallenge,
    expectedOrigin: getOrigins(req),
    expectedRPID: getRpId(req),
    requireUserVerification: true,
  })

  if (!verification.verified || !verification.registrationInfo) {
    const err = new Error('WebAuthn registration verification failed.')
    err.status = 401
    throw err
  }

  const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo
  state.credential = {
    id: credential.id,
    publicKey: Buffer.from(credential.publicKey).toString('base64url'),
    counter: credential.counter,
    transports: response.transports || credential.transports || [],
    deviceType: credentialDeviceType,
    backedUp: credentialBackedUp,
  }
  state.phoneEnrolled = true
  state.unlocked = true
  state.waitingForFingerprint = false
  state.failedAttempts = 0
  state.currentChallenge = null
  state.challengeExpiresAt = 0
  saveState(state)
  return {
    ok: true,
    message: 'Phone fingerprint bound. Gospel cannot see it.',
    status: {
      enrolled: true,
      phoneBound: true,
      phoneEnrolled: true,
      phoneName: state.phoneName,
      unlocked: true,
      operatorName: state.operatorName,
    },
  }
}

export async function verifyUnlock(state, req, body) {
  const { pairingSecret, id, rawId, type, response, challenge } = body || {}

  if (!pairingSecret || pairingSecret !== state.pairingSecret) {
    const err = new Error('Invalid pairing secret.')
    err.status = 401
    throw err
  }
  if (!state.credential) {
    const err = new Error('No phone enrolled. Bind fingerprint first.')
    err.status = 400
    throw err
  }
  if (!response?.clientDataJSON || !response?.authenticatorData || !response?.signature || !id) {
    const err = new Error(
      'Hardened unlock requires a full WebAuthn assertion (authenticatorData + signature + clientDataJSON).',
    )
    err.status = 400
    throw err
  }

  assertFreshChallenge(state, challenge || state.currentChallenge)

  const credentialId = id || rawId
  if (credentialId !== state.credential.id) {
    const err = new Error('Unknown credential.')
    err.status = 401
    throw err
  }

  const verification = await verifyAuthenticationResponse({
    response: {
      id: credentialId,
      rawId: rawId || credentialId,
      type: type || 'public-key',
      response,
      clientExtensionResults: body.clientExtensionResults || {},
    },
    expectedChallenge: state.currentChallenge,
    expectedOrigin: getOrigins(req),
    expectedRPID: getRpId(req),
    credential: {
      id: state.credential.id,
      publicKey: Buffer.from(state.credential.publicKey, 'base64url'),
      counter: state.credential.counter,
      transports: state.credential.transports,
    },
    requireUserVerification: true,
  })

  if (!verification.verified) {
    state.failedAttempts = Number(state.failedAttempts || 0) + 1
    saveState(state)
    const err = new Error('WebAuthn authentication verification failed.')
    err.status = 401
    throw err
  }

  state.credential.counter = verification.authenticationInfo.newCounter
  state.unlocked = true
  state.waitingForFingerprint = false
  state.failedAttempts = 0
  state.currentChallenge = null
  state.challengeExpiresAt = 0
  saveState(state)
  return {
    ok: true,
    message: 'PC unlocked with fingerprint module.',
    status: {
      unlocked: true,
      phoneEnrolled: true,
      operatorName: state.operatorName,
    },
  }
}
