#!/bin/zsh

set -euo pipefail

APP_DIR="${0:A:h}"
PORT="8765"

if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "端口 ${PORT} 已被占用，尝试打开已有的本地工具页面。"
else
  cd "${APP_DIR}"
  python3 -m http.server "${PORT}" --bind 127.0.0.1 >/tmp/broll-namer-http.log 2>&1 &
  SERVER_PID=$!
  trap 'kill "${SERVER_PID}" 2>/dev/null || true' EXIT INT TERM
  sleep 0.4
fi

TOOL_URL="http://127.0.0.1:${PORT}/index.html"
if [[ -d "/Applications/Google Chrome.app" ]]; then
  open -a "Google Chrome" "${TOOL_URL}"
elif [[ -d "/Applications/Microsoft Edge.app" ]]; then
  open -a "Microsoft Edge" "${TOOL_URL}"
else
  open "${TOOL_URL}"
fi

if [[ -n "${SERVER_PID:-}" ]]; then
  wait "${SERVER_PID}"
fi
