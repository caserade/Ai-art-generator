# Gospel Kaiju / WWW Gospel Command (Gosple)

Phone fingerprint unlock bridge for Gospel Kaiju / Gosplekaiju. The phone UI talks to a Gospel server over a pairing link; **enroll and unlock require a verified WebAuthn response** (not a bare `credentialId`).

## Quick start (local)

```bash
npm ci
npm start
```

Open the pairing URL printed in the console (includes `?s=…`) via **`http://localhost`** (Chrome rejects WebAuthn on bare `127.0.0.1`). On a phone (HTTPS or localhost), tap **Bind fingerprint module**.

## Phone / Cloudflare (fully operational)

When the PC-side tunnel is down (502) or still running the old insecure enroll path, start the hardened command and a fresh phone tunnel:

```bash
npm ci
./scripts/phone-tunnel.sh
```

The script prints a pairing URL (`https://….trycloudflare.com/?s=…`). Open that on the phone — it serves the hardened UI and rejects `credentialId`-only enroll.

> Quick tunnels get a new hostname each run. Re-bind the fingerprint after a new tunnel URL, or use a named Cloudflare tunnel with a stable hostname for lasting enrollments.

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
