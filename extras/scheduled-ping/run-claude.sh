#!/bin/bash
# 정기 ping: Claude Code로 '.' 한 번 실행해 사용량 구간 시작 시각을 맞춤
# 실행 시각은 launchd plist(install.sh --with-ping의 PING_TIMES)에서 지정함
# 토큰은 키체인(service claude-ping-oauth)에서 읽음. 저장소에 비밀값을 두지 않음

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
MODEL="${MODEL:-haiku}"
KEYCHAIN_SERVICE="claude-ping-oauth"

[[ -x "$CLAUDE_BIN" ]] || CLAUDE_BIN="$(command -v claude || true)"
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] claude 실행 파일 없음"
  exit 127
fi

# launchd에서 USER가 비어 있을 수 있어 id -un 사용
OAUTH_TOKEN="$(security find-generic-password -a "$(id -un)" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)"
if [[ -n "$OAUTH_TOKEN" ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$OAUTH_TOKEN"
fi
unset OAUTH_TOKEN

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping start (claude, $MODEL)"
"$CLAUDE_BIN" -p "." --model "$MODEL" 2>&1
RC=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ping done (exit=$RC)"
exit "$RC"
