#!/usr/bin/env bash
# Claude Code PreToolUse 훅: Orca 세션에서 stage-runner·agy/grok 직접 실행 차단함
# - Orca 세션 판정: ORCA_TERMINAL_HANDLE 또는 ORCA_CLI_COMMAND가 비어 있지 않음(아니면 통과)
# - 차단 대상: Agent(subagent_type="stage-runner"), Bash의 agy/grok -p|--print|--prompt·run-agy.sh·run-logged.sh
# - 차단 시 PreToolUse deny JSON 출력 후 exit 0 반환함

[[ -n "${ORCA_TERMINAL_HANDLE:-}" || -n "${ORCA_CLI_COMMAND:-}" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

exec python3 -I -c '
import json, re, sys

CMD_RE = re.compile(
    r"(?:^|[;&|(`\s])(?:agy|grok)\s+(?:.*\s)?(?:-p|--print|--prompt)(?:[\s=]|$)"
    r"|run-agy\.sh"
    r"|run-logged\.sh"
)
REASON = (
    "Orca 세션: stage-runner·agy/grok 직접 실행 대신 /orchestration 스킬로 "
    "worker-start 사용(구현은 --agent antigravity, 의견 요청은 antigravity·grok "
    "읽기 전용 작업자 병렬 시작)"
)

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

tool = data.get("tool_name")
inp = data.get("tool_input")
if not isinstance(inp, dict):
    sys.exit(0)

deny = False
if tool == "Agent" and inp.get("subagent_type") == "stage-runner":
    deny = True
elif tool == "Bash":
    cmd = inp.get("command")
    if isinstance(cmd, str) and CMD_RE.search(cmd):
        deny = True

if deny:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }
    }, ensure_ascii=False, separators=(",", ":")))
'
