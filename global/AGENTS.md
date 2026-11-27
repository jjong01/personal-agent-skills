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
8. [Work Report] Report implementation/fix results only in this format, one line per item:
   - 성공: <task> — <result/verification>
   - 실패: <task> — 원인: <cause> — 조치: <action> — 결과: <outcome>
   - 미확인: <what was not verified> (only when applicable)
   - 결정 필요: <item needing the user's decision> (only when applicable)
   Keep progress notes to one line or less. Do not list per-file change details unless asked; point to the checklist, plan document or commit instead. Never drop unverified items or decisions needed for brevity.

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
7. [Simplicity & Clarity] 모든 답변은 간결하게 압축하여 작성하되, 핵심 내용을 직관적이고 이해하기 쉽게 전달한다.
8. [Work Report] 구현·수정 결과는 성공(작업—결과)·실패(작업—원인—조치—결과)·미확인·결정 필요 항목만 항목당 1줄로 보고한다. 진행 안내는 1줄 이하, 파일별 변경 설명은 요청 시만 쓰며, 미확인·결정 필요 항목은 압축 대상에서 제외한다. -->

## Delegation (Claude Code only; Antigravity/Grok ignore this section)

Same role mapping inside and outside Orca; only the execution path differs.

| Work type | Owner |
|---|---|
| Planning, decisions, user questions, diff/test log review, checklist, commits | Claude main |
| Finalized-spec implementation, test fixes, research (`/offload`), images | agy |
| Browser verification (including app server start/restart) | Separate agy worker (not the implementer) |
| Pre-merge cross-review, opinion requests | Grok (read-only); opinion requests run agy + Grok in parallel |

- Execution path: Orca session (`ORCA_TERMINAL_HANDLE` or `ORCA_CLI_COMMAND` set, or Orca chat) → `orchestration` skill `worker-start` (`--agent antigravity` / `grok`); outside Orca → `stage-runner` (agy), `agy -p`, `grok -p`. PreToolUse hook (`orca-guard.sh`) blocks direct `stage-runner` and `agy`/`grok -p` runs in Orca; `install.sh` global settings apply safety limits (git state changes, `rm -rf`, DB/ssh, `.env` reads) to both paths.
- Implementation delegation: run finalized plan-doc stages, clear ad-hoc specs (2+ files; decide design questions first), and many known-cause mechanical fixes (`/delegate`) without asking via the execution path, reading only the report (`worker_done` / `STAGE REPORT`). On `QUESTIONS`, ask the user and rerun with answers; on report, review diffs/tests, update checklist, record agy usage, summarize, and get approval before committing.
- Plan doc sync before commit: if a plan doc exists, verify implemented items are checked off with date before every commit (including main edits, screen-check fixes, and unplanned changes) and include the update in the commit.
- Browser verification: for plans with UI changes, run one agy browser verification by default after committing the last implementation stage, limited to browser-only checks (layout, height jump, loading/empty states, modal placement); verify logic/data via API/unit tests. Skip when no UI changes. Provide a manual check table for other items; Claude main never uses browser tools.
- Reading-heavy non-dev work (web research, comparing sources, summarizing long docs/many files, translation, cleanup plans): use `/offload` without asking when `agy` is installed; small tasks and system changes stay with Claude.
- Background subagent (sonnet): use for other multi-step non-product work (docs, plans, reviews, scripts, config, waiting on agy) or code when all agy quotas are exhausted; 1–2 command tasks, destructive confirmations, and commits/pushes stay in main (subagent never commits/pushes, returns policy questions, and never edits files concurrently with main).
- Pre-merge review: right before merging a feature branch into the integration branch (e.g. develop), run `/code-review low` (plus `/security-review` if auth, login, session, permission, role, payment, token, password, personal data, or file upload changed) in a background subagent (summary only) alongside Grok read-only cross-review (trial; decide adoption after the first run); report findings before merging and let the user decide fixes. Run `/simplify` only by suggestion.
- Parallel requests: run up to 3 concurrent subagents only for non-overlapping files/areas (`isolation: worktree` for code); overlapping files or 1–3 line changes run sequentially in one agent.
- Model & quota notice: for agy-delegated work, do not recommend a Claude model—state agy quota in one line from `~/.cache/agy-quota.tsv` (Gemini 5h/weekly remaining) before starting and relay model/quota change from the report. For Claude-only work, name the recommended model (`opus`/`sonnet`/`haiku`) and wait to switch if different (suggest `/clear` first in long sessions).
- Main-session edits & exclusions: main edits 1–3 lines only (larger goes to agy). Do directly: investigation/design decisions, unclear root-cause debugging, 1–3 line edits, git/DB/deploy/server work, final regression-test stage.
- Session reset: never run built-in commands; at a natural boundary, verify clean/recorded state (move conversation-only standing instructions to `CLAUDE.md`/memory first) and recommend `/clear` (with next-session starter) or `/handoff` (across days/PCs) once per boundary when helpful—not for context size alone.

@~/agent/delegation.md

## Environment

- Workspace layout:
  - `~/dev/` — code projects. Run agents from the project folder, not from `~`.
  - `~/agent/` — non-project agent work: `system/` (OS setup, cleanup), `storage/` (external drives, backups), `notes/` (research, documents; `notes/handoff/` for handoff memos).
- macOS: shell is zsh with aliases `ls`→`lsd`, `cat`→`bat --paging=never`. `grep` and `find` are NOT aliased; use them with standard syntax.
- Windows: Claude Code runs commands in Git Bash (no zsh aliases). Use `~`-style paths in Bash and `%USERPROFILE%` paths in PowerShell.
- Optional tools `rg`, `fd`, `zoxide`(`z`), `delta` may be missing on some machines; check with `command -v` before relying on them and fall back to `grep`/`find`.
- Do not move or rename tool config folders (`~/.claude`, `~/.gemini`, `~/.antigravity*`).
