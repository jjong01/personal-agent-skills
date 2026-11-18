# 공통 에이전트 규칙 (Claude Code · Antigravity 공용)
<!-- 원본: personal-agent-skills 저장소 global/AGENTS.md (install.sh로 연결)
     연결: ~/agent/AGENTS.md → 이 파일, ~/.claude/CLAUDE.md·~/.gemini/GEMINI.md → ~/agent/AGENTS.md
     이 파일만 수정하면 두 도구에 모두 반영됨 -->

## Rules

1. [Language] Write all responses in Korean, excluding development terminology.
2. [Commit Message] Before suggesting a commit message, analyze the pending changes and output it as a code snippet.
   - Existing repository: follow the format of its recent commit history (detect from the last ~20 commits).
   - New repository (no or few commits): Conventional Commits with a Korean subject and a per-file body:
     <type>(<scope>): <Korean summary ending with a noun>
     (blank line)
     - <file or area>: <change>
     types: feat, fix, refactor, docs, style, test, chore, perf
   - Never leave any trace of AI agent use in commits or PRs: no `Co-Authored-By` trailers for AI, no "Generated with ..." lines, no mention of Claude/Antigravity/Gemini/AI in messages, branch names, or PR descriptions.
   - Claude Code: use the `/commit` skill.
3. [Documentation] Write Tasks and Implementation Plans in Korean, clearly distinguishing each step.
4. [Commenting] Do not use colloquial language (~해요, ~입니다) in comments. Use a concise and clear written style (~함, ~함에 따라 처리). Omit unnecessary modifiers for readability.
5. [Token Optimization] Do not include greetings, additional explanations, introductions, or conclusions (e.g., 'Yes, I understand', 'Please refer to the following code'). Output only the requested deliverables (code, plans, etc.) immediately.
6. [Code Output] When modifying or suggesting code, do not reprint the entire file. Provide only the required changes (Diff) or the core logic to be added concisely.
7. [Simplicity & Clarity] Keep all responses concise and condensed, while conveying core content intuitively and clearly.

All responses must be in Korean (except for development terminology).

<!-- 1. [Language] 모든 응답은 한국어로 작성한다. (개발 용어 제외)
2. [Commit Message] 커밋 메시지 제안 시 커밋 대기 중인 변경 내역을 분석해 코드 스니펫으로 생성한다.
   - 기존 저장소: 최근 커밋 이력(약 20개)의 형식을 따른다.
   - 새 저장소: Conventional Commits + 한국어 요약(명사형 종결) + 본문에 파일별 변경사항.
   - 커밋·PR에 AI 에이전트 사용 흔적(Co-Authored-By, Generated with, Claude·Antigravity·AI 언급)을 남기지 않는다.
   - Claude Code에서는 /commit 스킬을 사용한다.
3. [Documentation] Task 및 Implementation Plan은 한글로 작성하며, 단계별로 명확히 구분한다.
4. [Commenting] 주석 작성 시 구어체(~해요, ~입니다)를 금지하고, 짧고 명확한 문어체(~함, ~함에 따라 처리)를 사용한다. 가독성을 위해 불필요한 수식어는 생략한다.
5. [Token Optimization] 인사말, 부연 설명, 서론 및 결론(예: '네, 알겠습니다', '다음 코드를 참고하세요' 등)을 절대 사용하지 않으며, 요청받은 결과물(코드, 플랜 등)만 즉시 출력한다.
6. [Code Output] 코드 수정이나 제안 시, 파일 전체를 다시 출력하지 않고 변경이 필요한 부분(Diff)이나 추가할 핵심 로직만 간결하게 제공한다.
7. [Simplicity & Clarity] 모든 답변은 간결하게 압축하여 작성하되, 핵심 내용을 직관적이고 이해하기 쉽게 전달한다. -->

## Environment

- Workspace layout:
  - `~/dev/` — code projects. Run agents from the project folder, not from `~`.
  - `~/agent/` — non-project agent work: `system/` (OS setup, cleanup), `storage/` (external drives, backups), `notes/` (research, documents; `notes/handoff/` for handoff memos).
- macOS: shell is zsh with aliases `ls`→`lsd`, `cat`→`bat --paging=never`. `grep` and `find` are NOT aliased; use them with standard syntax.
- Windows: Claude Code runs commands in Git Bash (no zsh aliases). Use `~`-style paths in Bash and `%USERPROFILE%` paths in PowerShell.
- Optional tools `rg`, `fd`, `zoxide`(`z`), `delta` may be missing on some machines; check with `command -v` before relying on them and fall back to `grep`/`find`.
- Do not move or rename tool config folders (`~/.claude`, `~/.gemini`, `~/.antigravity*`).
