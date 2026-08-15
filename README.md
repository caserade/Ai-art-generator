# Gospel Kaiju / WWW Gospel Command

Phone fingerprint unlock bridge for Gospel Kaiju. The phone UI talks to a local Gospel server over a pairing link; **enroll and unlock require a verified WebAuthn response** (not a bare `credentialId`).

## Quick start

```bash
npm ci
npm start
```

Open the pairing URL printed in the console (includes `?s=…`). On a phone (HTTPS or localhost), tap **Bind fingerprint module**.

## Hardening

The previous tunnel build accepted `POST /api/enroll` with only `{ pairingSecret, credentialId }`, which unlocked without a fingerprint attestation. This tree rejects that shape and verifies registration/authentication with `@simplewebauthn/server`.

```bash
npm test
```

## Environment

| Variable | Purpose |
| --- | --- |
| `PORT` | HTTP port (default `8788`) |
| `GOSPEL_PAIRING_SECRET` | Fixed pairing secret (otherwise generated) |
| `GOSPEL_RP_ID` | WebAuthn RP ID (default host / `localhost`) |
| `GOSPEL_ORIGIN` | Expected origin(s), comma not needed — single origin override |
| `GOSPEL_DATA_DIR` | State directory (default `./data`) |
| `GOSPEL_TUNNEL_URL` | Optional public tunnel URL advertised by `/api/bridge` |

## API

- `GET /api/state` — unlock / enroll / Phone Link status
- `GET /api/challenge` — fresh WebAuthn challenge + options
- `POST /api/enroll` — full WebAuthn registration response + pairing secret
- `POST /api/unlock` — full WebAuthn assertion + pairing secret
- `POST /api/lock` — mark PC locked again
- `GET|POST /api/modules` — builtin / uploaded modules
