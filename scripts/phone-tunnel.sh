#!/usr/bin/env bash
# Bring up the fully operational (hardened) Gosple / Gospel Command for phone pairing.
# Replaces dead/insecure trycloudflare backends with the verified WebAuthn build.
set -euo pipefail
cd "$(dirname "$0")/.."

export PORT="${PORT:-8788}"
export GOSPEL_DATA_DIR="${GOSPEL_DATA_DIR:-/workspace/data}"
mkdir -p "$GOSPEL_DATA_DIR"

# Prefer an existing pairing secret (env, saved state, or regenerate via server start).
if [[ -z "${GOSPEL_PAIRING_SECRET:-}" && -f "$GOSPEL_DATA_DIR/state.json" ]]; then
  GOSPEL_PAIRING_SECRET="$(python3 -c "import json; print(json.load(open('$GOSPEL_DATA_DIR/state.json')).get('pairingSecret',''))" 2>/dev/null || true)"
  export GOSPEL_PAIRING_SECRET
fi

# Do NOT force GOSPEL_RP_ID=localhost — phone over HTTPS tunnel needs the tunnel hostname as RP ID.
unset GOSPEL_RP_ID || true
unset GOSPEL_ORIGIN || true

CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-}"
if [[ -z "$CLOUDFLARED_BIN" ]]; then
  if command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED_BIN="$(command -v cloudflared)"
  elif [[ -x /tmp/cloudflared ]]; then
    CLOUDFLARED_BIN=/tmp/cloudflared
  else
    echo "Installing cloudflared to /tmp/cloudflared…"
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
    chmod +x /tmp/cloudflared
    CLOUDFLARED_BIN=/tmp/cloudflared
  fi
fi

./scripts/cloud-agent-start.sh

TUNNEL_LOG="$GOSPEL_DATA_DIR/tunnel.log"
TUNNEL_PID_FILE="$GOSPEL_DATA_DIR/tunnel.pid"
PAIRING_FILE="$GOSPEL_DATA_DIR/pairing.url"

if [[ -f "$TUNNEL_PID_FILE" ]] && kill -0 "$(cat "$TUNNEL_PID_FILE")" 2>/dev/null; then
  echo "Tunnel already running (pid $(cat "$TUNNEL_PID_FILE"))"
else
  : >"$TUNNEL_LOG"
  nohup "$CLOUDFLARED_BIN" tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate >"$TUNNEL_LOG" 2>&1 &
  echo $! >"$TUNNEL_PID_FILE"
fi

url=""
for _ in $(seq 1 45); do
  url="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1 || true)"
  if [[ -n "$url" ]]; then
    break
  fi
  sleep 0.5
done

if [[ -z "$url" ]]; then
  echo "Failed to obtain Cloudflare quick tunnel URL" >&2
  tail -n 40 "$TUNNEL_LOG" >&2 || true
  exit 1
fi

# Persist tunnel URL for /api/bridge and operators.
export GOSPEL_TUNNEL_URL="$url"
# Restart Gospel so /api/bridge advertises the tunnel (env is read at process start).
PID_FILE="$GOSPEL_DATA_DIR/gospel.pid"
if [[ -f "$PID_FILE" ]]; then
  old="$(cat "$PID_FILE" || true)"
  if [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null; then
    kill "$old" || true
    sleep 0.5
  fi
  rm -f "$PID_FILE"
fi
GOSPEL_TUNNEL_URL="$url" ./scripts/cloud-agent-start.sh

secret="$(python3 -c "import json; print(json.load(open('$GOSPEL_DATA_DIR/state.json'))['pairingSecret'])")"
pairing="${url}/?s=${secret}#s=${secret}"
printf '%s\n' "$pairing" >"$PAIRING_FILE"
printf '%s\n' "$url" >"$GOSPEL_DATA_DIR/tunnel.url"

# Smoke: hardened enroll must reject credentialId-only.
code="$(curl -sS -o /tmp/gospel-enroll-smoke.json -w '%{http_code}' -X POST "${url}/api/enroll" \
  -H 'Content-Type: application/json' \
  -d "{\"pairingSecret\":\"${secret}\",\"credentialId\":\"fake\"}")"
if [[ "$code" != "400" ]]; then
  echo "Hardening smoke failed: expected HTTP 400, got $code" >&2
  cat /tmp/gospel-enroll-smoke.json >&2 || true
  exit 1
fi

echo "Gosple / WWW Gospel Command (hardened) is up."
echo "Phone pairing URL:"
echo "  $pairing"
echo "Old insecure trycloudflare backends should be abandoned; use this URL on the phone."
