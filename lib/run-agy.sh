#!/usr/bin/env bash
# agy 비대화 실행 래퍼
# - --settings가 전역 권한을 덮어쓰므로 전역 deny + 기본 deny + .env 차단을 매번 합쳐 전달함
# - 읽기 전용 명령을 기본 허용해 목록 밖 명령으로 실행이 중단되는 일을 줄임
# 사용: run-agy.sh <저장소> <모델> <지시문 파일> <로그 파일> [추가 allow 규칙...]
#   예: run-agy.sh ~/dev/app gemini-3.8-flash-high p.txt run.log 'command(mvn test)'
# 규칙은 공백 단위 접두어 일치: command(mvn test)는 'mvn test -q'는 허용하나 'mvn test-compile'·'mvn -q test'는 허용하지 않음. '*'를 붙이면 일치하지 않음
# 환경 변수 AGY_MODE: accept-edits(기본, 파일 수정 자동 승인) | plan(읽기 전용 점검)
#          AGY_BROWSER=1: 브라우저 확인용 chrome-devtools MCP 도구 허용(설치·디버깅·파일 업로드 도구 제외)
#          AGY_BROWSER_URLS: 열 수 있는 주소 접두어(공백 구분, 기본 http://localhost http://127.0.0.1 about:blank)
#          AGY_ADD_DIRS: 작업 공간에 더할 폴더(':' 구분), AGY_REPORT_MARK: 정상 종료 판단 표시(기본 '=== REPORT ===')
# 로그 끝 AGY_DENIED: <명령>: 권한 거부된 명령(agy-denied.py가 대화 transcript에서 추출)
#        AGY_NEW_MODELS: lib/agy-models.tsv에 없는 신규 모델 id 목록
# 위치: 저장소 lib/, 설치 후 ~/agent/lib/run-agy.sh 로 호출함
set -uo pipefail

[[ $# -lt 4 ]] && { echo "usage: $0 <repo> <model> <prompt-file> <log-file> [allow...]" >&2; exit 2; }
REPO="$1"; MODEL="$2"; PROMPT="$3"; LOG="$4"; shift 4
# 작업 폴더로 이동하기 전에 상대 경로를 절대 경로로 바꿈
abspath() { (cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"); }
PROMPT="$(abspath "$PROMPT")"; LOG="$(abspath "$LOG")"
SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GLOBAL="$HOME/.gemini/antigravity-cli/settings.json"
MODE="${AGY_MODE:-accept-edits}"
case "$MODE" in accept-edits|plan) ;; *) echo "AGY_MODE는 accept-edits 또는 plan" >&2; exit 2 ;; esac

# 모델 이름 검증(잘못된 이름은 agy가 즉시 실패하므로 실행 전에 걸러 냄). 목록은 신규 모델 감지에 재사용함
MODELS_OUT="$(agy models 2>/dev/null | grep -v '^Fetching')"
if ! printf '%s\n' "$MODELS_OUT" | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "알 수 없는 모델: $MODEL. 사용 가능 목록:" >&2
  printf '%s\n' "$MODELS_OUT" >&2
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
# 읽기 전용 명령 기본 허용(상태를 바꾸지 않는 명령만. 접두어 일치라 하위 명령까지 적음)
allow += [f"command({c})" for c in (
    "ls", "pwd", "cat", "head", "tail", "wc", "grep", "egrep", "rg", "find", "fd", "sed -n", "tree",
    "mkdir -p", "mkdir",  # 작업 폴더 안 새 폴더 생성(기존 파일 변경 없음)
    "sort", "cut", "diff", "stat", "file", "basename", "dirname", "realpath", "which",
    # 환경 확인(버전 출력만)
    "java -version", "java --version", "javac -version", "mvn -v", "mvn --version", "./mvnw -v", "gradle -v", "./gradlew -v",
    "node -v", "node --version", "npm -v", "npm --version", "python3 --version", "python --version", "php -v", "git --version", "uname",
    "xargs grep", "xargs -0 grep", "xargs rg", "xargs wc", "xargs ls",
    "git status", "git diff", "git log", "git show", "git grep", "git ls-files", "git branch",
    "git blame", "git rev-parse", "git ls-tree", "git cat-file")]
allow += extra
# 브라우저 확인: MCP 규칙은 mcp(<서버>/<도구>) 형식. 서버 전체 와일드카드는 쓰지 않고 필요한 도구만 나열함
if os.environ.get("AGY_BROWSER") == "1":
    allow += [f"mcp(chrome-devtools/{t})" for t in (
        "list_pages", "new_page", "select_page", "close_page", "navigate_page", "resize_page",
        "take_snapshot", "take_screenshot", "wait_for", "click", "hover", "fill", "fill_form",
        "type_text", "press_key", "handle_dialog", "evaluate_script",
        "get_console_message", "list_network_requests", "get_network_request")]
    # 페이지 열기는 execute_url(<주소 접두어>) 권한이 따로 필요함. 기본은 로컬 주소만
    urls = os.environ.get("AGY_BROWSER_URLS", "http://localhost http://127.0.0.1 about:blank").split()
    allow += [f"execute_url({u})" for u in urls]
# 상태 변경·위험 명령 차단
deny += [f"command({c})" for c in (
    "git commit", "git push", "git reset", "git checkout", "git switch", "git rebase",
    "git merge", "git stash", "git clean", "git branch -d", "git branch -D", "git branch --delete",
    "git branch -m", "git branch -M", "git branch --move", "git branch -f", "git branch --force", "git branch -c", "git branch -C", "git branch --copy", "sort -o", "sort --output", "rm -rf", "sudo", "mysql", "mariadb", "ssh", "scp", "rsync")]
# 저장소 안 .env 파일 읽기 차단(예시 파일 제외)
for root, dirs, files in os.walk(repo):
    # 깊이 제한 없이 탐색함(모노레포 하위 패키지 .env 포함). 대용량 산출물 폴더만 제외
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "target", "build", "dist", ".gradle", ".venv", "venv", "__pycache__", ".next", "coverage", "vendor")]
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
# CLI 로그 선택 기준: 이 시각 이후 생성 + 작업 폴더 일치(동시 실행 경합 방지)
# 실행 전 사용량(상태줄 캐시)을 보관해 실행 후 값과 함께 로그에 남김
QBEFORE="$(cat "${AGY_QUOTA_FILE:-$HOME/.cache/agy-quota.tsv}" 2>/dev/null)"
START="$(date +%s)"
agy --mode "$MODE" --model "$MODEL" --settings "$SETTINGS" "${ADD[@]+"${ADD[@]}"}" -p "$(cat "$PROMPT")" > "$LOG" 2>&1
code=$?
echo "AGY_EXIT $code" >> "$LOG"
# 권한 거부 명령을 transcript에서 찾아 'AGY_DENIED: <명령>'으로 덧붙임
DENIED="$("$PY" -I "$SELF_DIR/agy-denied.py" "$START" "$PROMPT" "$(pwd)" "$(pwd -P)" 2>/dev/null)"
if [[ -n "$DENIED" ]]; then
  printf '%s\n' "$DENIED" >> "$LOG"
elif grep -q 'no output produced' "$LOG"; then
  echo "AGY_DENIED: (명령 확인 불가) 보고 없이 중단됨. ~/.gemini/antigravity-cli/log 확인 필요" >> "$LOG"
fi
# 사용량 전후 기록(보고 작성용, 보고 없이 끝난 경우 한도 소진 판단용)
{ echo "AGY_USAGE_BEFORE (캐시):"; printf '%s\n' "$QBEFORE"; echo "AGY_USAGE:"; agy -p "/usage" 2>&1 | head -8; } >> "$LOG"
# agy-models.tsv에 없는 모델이 목록에 생기면 로그 끝에 알림(모델 자동 전환은 하지 않음)
if [[ -f "$SELF_DIR/agy-models.tsv" ]]; then
  NEW_MODELS="$(printf '%s\n' "$MODELS_OUT" | awk '{print $1}' | grep -v '^$' \
    | grep -vxFf <(cut -f1 "$SELF_DIR/agy-models.tsv") | tr '\n' ' ' | sed 's/ $//')"
  [[ -n "$NEW_MODELS" ]] && echo "AGY_NEW_MODELS: $NEW_MODELS" >> "$LOG"
fi
exit $code
