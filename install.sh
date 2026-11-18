#!/usr/bin/env bash
# skills/ 하위 스킬을 Claude Code·Antigravity 전역 스킬 폴더에 심볼릭 링크로 연결함
# 사용: ./install.sh [--dry-run]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/skills"
TARGETS=("$HOME/.claude/skills" "$HOME/.gemini/config/skills")
BACKUP="$HOME/.agent-skills-backup/$(date +%Y%m%d-%H%M%S)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

run() { if (( DRY )); then echo "[dry-run] $*"; else "$@"; fi; }

for target in "${TARGETS[@]}"; do
  run mkdir -p "$target"
  for skill in "$SRC"/*/; do
    name="$(basename "$skill")"
    [[ -f "$skill/SKILL.md" ]] || continue
    dest="$target/$name"
    # 이미 저장소를 가리키는 링크면 건너뜀
    if [[ -L "$dest" && "$(readlink "$dest")" == "${skill%/}" ]]; then
      echo "ok      $dest"
      continue
    fi
    # 기존 실제 폴더·다른 링크는 백업 후 교체
    if [[ -e "$dest" || -L "$dest" ]]; then
      run mkdir -p "$BACKUP/$(basename "$(dirname "$target")")"
      run mv "$dest" "$BACKUP/$(basename "$(dirname "$target")")/$name"
      echo "backup  $dest -> $BACKUP"
    fi
    run ln -s "${skill%/}" "$dest"
    echo "linked  $dest -> ${skill%/}"
  done
done
