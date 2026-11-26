#!/bin/bash
# 정기 ping: Antigravity CLI(agy)로 '.' 한 번 실행해 사용량 구간 시작 시각을 맞춤
# 실행 시각은 launchd plist(install.sh --with-ping의 PING_TIMES)에서 지정함

AGY_BIN="${AGY_BIN:-/opt/homebrew/bin/agy}"
MODEL="${MODEL:-gemini-3.8-flash-low}"
PRINT_TIMEOUT="${PRINT_TIMEOUT:-120s}"

[[ -x "$AGY_BIN" ]] || AGY_BIN="$(command -v agy || true)"
if [[ -z "$AGY_BIN" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] agy 실행 파일 없음"
  exit 127
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping start (agy, $MODEL)"
"$AGY_BIN" -p "." --model "$MODEL" --print-timeout "$PRINT_TIMEOUT" 2>&1
RC=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping done (exit=$RC)"
exit "$RC"
