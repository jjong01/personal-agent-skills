#!/usr/bin/env bash
# 에이전트 작업 환경 설치: 폴더 구조, 공통 규칙(AGENTS.md) 연결, 스킬 연결
# 사용: ./install.sh [--dry-run]
# 다시 실행해도 안전함. 기존 파일·폴더는 ~/.agent-skills-backup/<시각>/ 으로 옮긴 뒤 링크함
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.agent-skills-backup/$(date +%Y%m%d-%H%M%S)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

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

echo "## 3. 스킬"
for skill in "$REPO_DIR"/skills/*/; do
  skill="${skill%/}"
  name="$(basename "$skill")"
  [[ -f "$skill/SKILL.md" ]] || continue
  link "$skill" "$HOME/.claude/skills/$name"
  # .claude-only 표시가 있는 스킬은 Claude Code에만 연결함
  [[ -f "$skill/.claude-only" ]] || link "$skill" "$HOME/.gemini/config/skills/$name"
done

echo "## 4. 도구 확인"
missing=()
for t in claude agy node git lsd bat rg fd zoxide delta; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if (( ${#missing[@]} )); then
  echo "없음: ${missing[*]}"
  echo "  lsd·bat는 AGENTS.md의 zsh 별칭 전제, rg·fd·zoxide·delta는 선택(없으면 grep·find 사용)"
  echo "  macOS 설치 예: brew install lsd bat ripgrep fd zoxide git-delta node"
  echo "                 brew install --cask antigravity-cli   # agy"
else
  echo "ok      필요한 도구 모두 있음"
fi
