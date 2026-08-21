# Gospel Kaiju / WWW Gospel Command (Gosple)

Phone fingerprint unlock bridge for Gospel Kaiju / Gosplekaiju, plus two **standalone modules** — **Art Scan** and **Learning** — that run independently of the unlock flow.

The phone UI talks to a Gospel server over a pairing link; **enroll and unlock require a verified WebAuthn response** (not a bare `credentialId`).

## Quick start (local)

```bash
npm ci
npm start
```

Open the pairing URL printed in the console (includes `?s=…`) via **`http://localhost`** (Chrome rejects WebAuthn on bare `127.0.0.1`). On a phone (HTTPS or localhost), tap **Bind fingerprint module**.

## Standalone modules

Art Scan and Learning are self-contained web apps. Each has its own UI, its own `/api`, its own service worker scope, its own manifest and its own data directory. **They do not need a pairing secret, an enrolled phone or an unlocked PC** — that independence is covered by tests in `tests/modules-host.test.js`.

| Module | What it does |
| --- | --- |
| **Art Scan** | Phone photo → background isolation → 4-frame sprite sheet (Idle / Walk A / Walk B / Jump) + auto hitbox. The pipeline runs on the phone via Canvas, so preview is instant and works offline. |
| **Learning** | Free Brain game-design intelligence (design games, generate levels, tune physics, explain mechanics) that **remembers what you teach it** and retrains its routing from your feedback. |

Reach them two ways.

**Mounted on the main app** — same server, same tunnel, no extra process:

```
http://localhost:8788/m/art-scan/
http://localhost:8788/m/learning/
```

**As their own processes** — the main app does not need to be running at all:

```bash
npm run start:modules                  # art-scan on 8790, learning on 8791
npm run start:art-scan                 # just Art Scan
node modules/serve.js learning --port 9100
```

Both paths serve identical code, so a sprite scanned standalone is byte-identical to one scanned through the main app.

### Module API

| Endpoint | Purpose |
| --- | --- |
| `GET /api/health` | Module id, version, and whether it is standalone |
| `GET|POST /api/sprites` | List / create sprite sheets (Art Scan) |
| `GET /api/sprites/:id/sheet.png` | The generated sheet (Art Scan) |
| `POST /api/ask` | Ask the brain; answers from memory when it has been taught (Learning) |
| `POST /api/teach` | Teach a phrase → answer pair (Learning) |
| `POST /api/feedback` | Rate an answer to retrain tool routing (Learning) |
| `GET /api/memory` | Everything it has learned (Learning) |
| `POST /api/tools/:name` | Invoke a tool directly (Learning) |

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
| `GOSPEL_MODULE_DATA_DIR` | Module data root (defaults to `GOSPEL_DATA_DIR`) |
| `GOSPEL_TUNNEL_URL` | Optional public tunnel URL advertised by `/api/bridge` |

## API

- `GET /api/state` — unlock / enroll / Phone Link status
- `GET /api/challenge` — fresh WebAuthn challenge + options
- `POST /api/enroll` — full WebAuthn registration response + pairing secret
- `POST /api/unlock` — full WebAuthn assertion + pairing secret
- `POST /api/lock` — mark PC locked again
- `GET|POST /api/modules` — standalone / builtin / uploaded modules, with launch urls
- `GET /api/bridge` — tunnel url plus absolute module urls for the phone
