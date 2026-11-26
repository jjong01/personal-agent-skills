#!/usr/bin/env bash
# 에이전트 작업 환경 설치: 폴더 구조, 공통 규칙(AGENTS.md) 연결, 스킬 연결
# 사용: ./install.sh [--dry-run] [--with-ping]
#   --with-ping: macOS 전용 정기 ping(launchd) 등록. 기본은 설치 안 함
# 다시 실행해도 안전함. 기존 파일·폴더는 ~/.agent-skills-backup/<시각>/ 으로 옮긴 뒤 링크함
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.agent-skills-backup/$(date +%Y%m%d-%H%M%S)"
DRY=0
WITH_PING=0
# 정기 ping 실행 시각(평일, HH:MM 공백 구분). 5시간 구간 경계에 1분씩 마진을 둔 값임
PING_TIMES="${PING_TIMES:-06:30 11:31 16:32}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --with-ping) WITH_PING=1 ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 2 ;;
  esac
done

run() { if (( DRY )); then echo "[dry-run] $*"; else "$@"; fi; }

# 링크 생성. 이미 같은 대상을 가리키면 건너뛰고, 다른 파일·링크가 있으면 백업 후 교체함
link() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "ok      $dest"
    return
  fi
  run mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    local rel="${dest#"$HOME"/}"
    run mkdir -p "$BACKUP/$(dirname "$rel")"
    run mv "$dest" "$BACKUP/$rel"
    echo "backup  $dest -> $BACKUP/$rel"
  fi
  run ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
}

echo "## 1. 폴더 구조"
for d in "$HOME/dev" "$HOME/agent/system" "$HOME/agent/storage" "$HOME/agent/notes/handoff"; do
  [[ -d "$d" ]] && echo "ok      $d" || { run mkdir -p "$d"; echo "created $d"; }
done

echo "## 2. 공통 규칙"
link "$REPO_DIR/global/AGENTS.md" "$HOME/agent/AGENTS.md"
link "$HOME/agent/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link "$HOME/agent/AGENTS.md" "$HOME/.gemini/GEMINI.md"

echo "## 3. 스킬 (skills/<분류>/<이름> → 도구별 skills/<이름>)"
# 저장소에서 사라진 스킬을 가리키는 링크 정리(폴더 구조 변경·이름 변경 대비)
for dir in "$HOME/.claude/skills" "$HOME/.gemini/config/skills"; do
  for l in "$dir"/*; do
    [[ -L "$l" ]] || continue
    t="$(readlink "$l")"
    [[ "$t" == "$REPO_DIR"/* && ! -e "$t" ]] && { run rm "$l"; echo "removed $l (대상 없음)"; }
  done
done
seen=" "
for skill in "$REPO_DIR"/skills/*/*/; do
  skill="${skill%/}"
  name="$(basename "$skill")"
  [[ -f "$skill/SKILL.md" ]] || continue
  [[ "$seen" == *" $name "* ]] && { echo "중복 스킬 이름: $name ($skill) 건너뜀" >&2; continue; }
  seen+="$name "
  link "$skill" "$HOME/.claude/skills/$name"
  # .claude-only 표시가 있는 스킬은 Claude Code에만 연결함
  [[ -f "$skill/.claude-only" ]] || link "$skill" "$HOME/.gemini/config/skills/$name"
done

echo "## 3-1. 공용 스크립트"
link "$REPO_DIR/lib" "$HOME/agent/lib"
link "$REPO_DIR/extras/statusline.sh" "$HOME/.claude/statusline.sh"   # 상태줄(구독·맥락·agy 할당량 사용률)
link "$REPO_DIR/extras/terminal-status.sh" "$HOME/.claude/hooks/terminal-status.sh"   # 터미널별 효과음·알림 훅

echo "## 4. 서브에이전트 (Claude Code 전용)"
for agent in "$REPO_DIR"/agents/*.md; do
  [[ -f "$agent" ]] || continue
  link "$agent" "$HOME/.claude/agents/$(basename "$agent")"
done

echo "## 5. 설정 병합 (저장소 settings/ → 기기 설정, 기존 값 유지)"
PY="$(command -v python3 || command -v python || true)"
if [[ -z "$PY" ]]; then
  echo "python 없음: 설정 병합 건너뜀"
else
  DRYFLAG=(); (( DRY )) && DRYFLAG=(--dry-run)
  "$PY" -I "$REPO_DIR/lib/merge-settings.py" "$REPO_DIR/settings/claude.json" "$HOME/.claude/settings.json" "${DRYFLAG[@]+"${DRYFLAG[@]}"}"
  "$PY" -I "$REPO_DIR/lib/merge-settings.py" "$REPO_DIR/settings/agy.json" "$HOME/.gemini/antigravity-cli/settings.json" "${DRYFLAG[@]+"${DRYFLAG[@]}"}"
fi

echo "## 6. 도구 확인"
missing=()
for t in claude agy node git jq lsd bat rg fd zoxide delta; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if (( ${#missing[@]} )); then
  echo "없음: ${missing[*]}"
  echo "  lsd·bat는 AGENTS.md의 zsh 별칭 전제, rg·fd·zoxide·delta는 선택(없으면 grep·find 사용)"
  echo "  jq는 상태줄(statusline.sh)에 필요"
  echo "  macOS 설치 예: brew install jq lsd bat ripgrep fd zoxide git-delta node"
  echo "                 brew install --cask antigravity-cli   # agy"
else
  echo "ok      필요한 도구 모두 있음"
fi

echo "## 7. 점검"
warn=0
for l in "$HOME/agent/AGENTS.md" "$HOME/agent/lib" "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME"/.claude/skills/* "$HOME"/.gemini/config/skills/* "$HOME"/.claude/agents/*.md; do
  [[ -L "$l" && ! -e "$l" ]] && { echo "깨진 링크: $l"; warn=1; }
done
(( warn )) || echo "ok      링크 정상"
if command -v agy >/dev/null 2>&1; then
  if agy models 2>/dev/null | grep -q gemini; then echo "ok      agy 모델 목록 조회됨(로그인 상태)"
  else echo "확인 필요: agy models 실패. agy를 한 번 실행해 로그인"; fi
  if agy mcp list 2>/dev/null | grep -q '^chrome-devtools'; then echo "ok      agy chrome-devtools MCP 등록됨(브라우저 확인)"
  else echo "선택: 브라우저 확인을 맡기려면 agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.10.1"; fi
else
  echo "확인 필요: agy 없음. delegate·offload·image-edit는 agy가 있어야 위임함"
fi
if [[ -n "$PY" ]]; then
  "$PY" -c "import PIL" 2>/dev/null && echo "ok      python·PIL" || echo "참고: PIL 없음(image-edit만 필요): pip install pillow"
else
  echo "확인 필요: python 없음(run-agy.sh·설정 병합에 필요)"
fi
if [[ -d "$HOME/.claude/plugins" ]] && find "$HOME/.claude/plugins" -maxdepth 4 -type d -name 'context-mode*' 2>/dev/null | grep -q .; then
  echo "ok      context-mode 플러그인"
else
  echo "확인 필요: Claude Code에서 /plugin install context-mode@context-mode 실행"
fi

if (( WITH_PING )); then
  echo "## 8. 정기 ping (launchd, macOS 전용)"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "건너뜀: macOS에서만 지원함"
  else
    link "$REPO_DIR/extras/scheduled-ping" "$HOME/agent/scheduled-ping"
    # 평일(월~금) × PING_TIMES 항목 생성
    schedule=""
    for wd in 1 2 3 4 5; do
      for t in $PING_TIMES; do
        schedule+="        <dict><key>Weekday</key><integer>$wd</integer><key>Hour</key><integer>$((10#${t%%:*}))</integer><key>Minute</key><integer>$((10#${t##*:}))</integer></dict>"$'\n'
      done
    done
    schedule="${schedule%$'\n'}"
    uid="$(id -u)"
    for f in "$HOME"/Library/LaunchAgents/*.claude-ping.plist "$HOME"/Library/LaunchAgents/*.agy-ping.plist; do
      [[ -f "$f" ]] || continue
      old="$(basename "$f" .plist)"
      echo "경고    기존 작업 $old 존재: 중복 실행됨. 제거하지 않았으니 필요 시 직접 bootout 후 plist 삭제"
    done
    for n in claude agy; do
      label="local.agent-ping.$n"
      dest="$HOME/Library/LaunchAgents/$label.plist"
      tpl="$REPO_DIR/extras/scheduled-ping/$n.plist.template"
      run mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
      if (( DRY )); then
        echo "[dry-run] $tpl -> $dest (__HOME__=$HOME, 시각: $PING_TIMES)"
      else
        content="$(<"$tpl")"; content="${content//__SCHEDULE__/$schedule}"; content="${content//__HOME__/$HOME}"; printf '%s\n' "$content" > "$dest"
        echo "wrote   $dest"
      fi
      if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
        run launchctl bootout "gui/$uid/$label"
      fi
      run launchctl bootstrap "gui/$uid" "$dest"
      echo "등록    $label"
    done
    security find-generic-password -a "$(id -un)" -s claude-ping-oauth >/dev/null 2>&1 \
      && echo "ok      키체인 토큰(claude-ping-oauth) 있음" \
      || echo "확인 필요: 키체인 토큰 없음. docs/GUIDE.md 13절 참고"
  fi
fi
