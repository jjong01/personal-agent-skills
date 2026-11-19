#!/usr/bin/env bash
# agy 비대화 실행 래퍼
# - --settings가 전역 권한을 덮어쓰므로 전역 deny + 기본 deny + .env 차단을 매번 합쳐 전달함
# - 읽기 전용 명령을 기본 허용해 목록 밖 명령으로 실행이 중단되는 일을 줄임
# 사용: run-agy.sh <저장소> <모델> <지시문 파일> <로그 파일> [추가 allow 규칙...]
#   예: run-agy.sh ~/dev/app gemini-3.8-flash-high p.txt run.log 'command(mvn test)'
# 규칙은 접두어 일치: command(mvn test)는 'mvn test -q'도 허용함. '*'를 붙이면 일치하지 않음
# 환경 변수 AGY_MODE: accept-edits(기본, 파일 수정 자동 승인) | plan(읽기 전용 점검)
#          AGY_ADD_DIRS: 작업 공간에 더할 폴더(':' 구분), AGY_REPORT_MARK: 정상 종료 판단 표시(기본 '=== REPORT ===')
# 위치: 저장소 lib/, 설치 후 ~/agent/lib/run-agy.sh 로 호출함
set -uo pipefail

[[ $# -lt 4 ]] && { echo "usage: $0 <repo> <model> <prompt-file> <log-file> [allow...]" >&2; exit 2; }
REPO="$1"; MODEL="$2"; PROMPT="$3"; LOG="$4"; shift 4
# 작업 폴더로 이동하기 전에 상대 경로를 절대 경로로 바꿈
abspath() { (cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"); }
PROMPT="$(abspath "$PROMPT")"; LOG="$(abspath "$LOG")"
GLOBAL="$HOME/.gemini/antigravity-cli/settings.json"
MODE="${AGY_MODE:-accept-edits}"
case "$MODE" in accept-edits|plan) ;; *) echo "AGY_MODE는 accept-edits 또는 plan" >&2; exit 2 ;; esac

# 모델 이름 검증(잘못된 이름은 agy가 즉시 실패하므로 실행 전에 걸러 냄)
if ! agy models 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "알 수 없는 모델: $MODEL. 사용 가능 목록:" >&2
  agy models 2>/dev/null | grep -v '^Fetching' >&2
  exit 2
fi

# Windows(Git Bash)는 python3 대신 python만 있는 경우가 많음
PY="$(command -v python3 || command -v python || true)"
[[ -z "$PY" ]] && { echo "python3(또는 python)이 필요함" >&2; exit 2; }

SETTINGS="$("$PY" -I - "$REPO" "$GLOBAL" "$@" <<'EOF'
import json, os, sys
repo, glob_path, extra = os.path.realpath(sys.argv[1]), sys.argv[2], sys.argv[3:]
perm = {}
try:
    perm = json.load(open(glob_path)).get("permissions", {})
except Exception:
    pass
allow = list(perm.get("allow", []))
deny = list(perm.get("deny", []))
# 읽기 전용 명령 기본 허용
allow += [f"command({c})" for c in (
    "ls", "pwd", "cat", "head", "tail", "wc", "grep", "rg", "find", "fd", "sed -n",
    "git status", "git diff", "git log", "git show", "tree")]
allow += extra
# 상태 변경·위험 명령 차단
deny += [f"command({c})" for c in (
    "git commit", "git push", "git reset", "git checkout", "git switch", "git rebase",
    "git merge", "git stash", "git clean", "rm -rf", "sudo", "mysql", "mariadb", "ssh", "scp", "rsync")]
# 저장소 안 .env 파일 읽기 차단(예시 파일 제외)
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "target", "build", "dist", ".gradle")]
    if root.count(os.sep) - repo.count(os.sep) > 3:
        dirs[:] = []
    for f in files:
        if f.startswith(".env") and not f.endswith((".example", ".template", ".sample")):
            deny.append(f"read_file({os.path.join(root, f)})")
deny.append(r"command(regex:.*\.env(\s|$|\.(?!example|template|sample)).*)")
print(json.dumps({"permissions": {"allow": sorted(set(allow)), "deny": sorted(set(deny))}}, ensure_ascii=False))
EOF
)"

cd "$REPO" || exit 2
ADD=()
if [[ -n "${AGY_ADD_DIRS:-}" ]]; then
  IFS=':' read -ra _dirs <<< "$AGY_ADD_DIRS"
  for d in "${_dirs[@]}"; do [[ -n "$d" ]] && ADD+=(--add-dir "$d"); done
fi
agy --mode "$MODE" --model "$MODEL" --settings "$SETTINGS" "${ADD[@]+"${ADD[@]}"}" -p "$(cat "$PROMPT")" > "$LOG" 2>&1
code=$?
echo "AGY_EXIT $code" >> "$LOG"
# 권한 거부로 보고 없이 끝난 경우 원인 명령을 로그에 덧붙임
if grep -q 'no output produced' "$LOG"; then
  latest="$(ls -t "$HOME/.gemini/antigravity-cli/log/"*.log 2>/dev/null | head -1)"
  echo "AGY_DENIED: allow 목록 밖 명령으로 중단됨. CLI 로그: $latest" >> "$LOG"
elif ! grep -qF "${AGY_REPORT_MARK:-=== REPORT ===}" "$LOG"; then
  # 보고 없이 끝나면 한도 소진 여부 판단용 사용량을 덧붙임
  echo "AGY_USAGE:" >> "$LOG"
  agy -p "/usage" 2>&1 | head -8 >> "$LOG"
fi
exit $code
