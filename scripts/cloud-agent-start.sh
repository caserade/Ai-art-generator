#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PORT="${PORT:-8788}"
export GOSPEL_DATA_DIR="${GOSPEL_DATA_DIR:-/workspace/data}"
mkdir -p "$GOSPEL_DATA_DIR"
PID_FILE="$GOSPEL_DATA_DIR/gospel.pid"

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Gospel already running (pid $(cat "$PID_FILE"))"
else
  nohup npm start >"$GOSPEL_DATA_DIR/gospel.log" 2>&1 &
  echo $! >"$PID_FILE"
fi

for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT}/api/state" >/dev/null; then
    echo "Gospel ready on :${PORT}"
    exit 0
  fi
  sleep 0.5
done
echo "Gospel failed to become ready" >&2
tail -n 50 "$GOSPEL_DATA_DIR/gospel.log" >&2 || true
exit 1
