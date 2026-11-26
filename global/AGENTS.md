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

## Delegation (Claude Code only; Antigravity ignores this section)

- Implement the stages of a finalized plan document (e.g., HS1–HS5, WS1–WS4, M1–M3) without asking the user first: run the `stage-runner` subagent (it follows the `/delegate` procedure in its own context) and read only its returned report. Keep the main session for planning, user questions and commits.
- Ad-hoc implementation requests outside a plan document: when the spec is clear and the change touches 2+ files, also run `stage-runner` without asking, passing the request text as the spec (no plan document needed). Decide design questions in the main session first, then delegate only the implementation.
- When stage-runner returns `QUESTIONS`, ask the user, then rerun stage-runner with the answers as user decisions. When it returns `STAGE REPORT`, summarize it and get approval before committing.
- Also use `/delegate` (via stage-runner) without asking for many mechanical fixes with a known cause.
- Screen verification: after the last implementation stage is committed, give the user a manual check table (screen location · action · expected result, by plan stage/checklist item) and record "브라우저 확인: 사용자 직접 확인 예정" in the checklist. Verify logic with API/unit tests, not the browser. Run agy browser verification via stage-runner only when the user explicitly asks; then use the project's local test accounts (ask the user if missing) and re-check only failed items. Do not verify with Claude browser tools in the main session. Repeated core flows may get Playwright scripts per project decision.
- Non-development work that needs a lot of reading (web research, comparing sources, summarizing long documents or many files, translation, cleanup plans): use `/offload` without asking when `agy` is installed. Small tasks and system changes stay with Claude.
- Other multi-step work that is not product code (documents, plans, reviews, scripts, config, waiting on agy), or code work when every agy quota is exhausted: run it in a background subagent (model sonnet; pass the needed context explicitly) so the main session can keep answering the user's questions meanwhile. One- or two-command tasks, destructive actions needing confirmation (format, delete), and commits/pushes stay in the main session. The subagent never commits or pushes and returns policy questions instead of deciding; the main session does not edit files the subagent is working on.
- Pre-merge review: right before merging a feature branch into the integration branch (e.g. develop), run `/code-review low` without asking. If the changed paths or diff mention auth, login, session, permission, role, payment, token, password, personal data or file upload, also run `/security-review`. Run them in a background subagent and read only the summary; report findings before merging and let the user decide what to fix. Do not run `/simplify` automatically; suggest it only when the review points to cleanup.
- Parallel requests: when several independent tasks are requested at once, run them as concurrent subagents (max 3) only if their target files/areas do not overlap; check the expected target files of each task first. Run code tasks with worktree isolation (`isolation: worktree`) to avoid build/test collisions. Tasks touching the same file or shared component, and 1–3 line changes, run sequentially in one agent. Collect results in the [Work Report] format.
- Model notice: for work delegated to stage-runner/agy, do not recommend a Claude model; before starting, state agy quota in one line from `~/.cache/agy-quota.tsv` (Gemini 5h/weekly remaining), and relay the agy model and quota change from the STAGE REPORT when summarizing it.
  For Claude-only work, name the recommended model (opus/sonnet/haiku). If it matches the current model, proceed; otherwise wait for the user to switch, suggesting `/clear` first in a long session (switching models rebuilds the prompt cache).
- Main session code edits: only changes of 1–3 lines; anything larger goes to stage-runner (agy).
- Exclusions (do these directly): investigation or design decisions, unclear root-cause debugging, changes of 1–3 lines, git/DB/deploy/server work, the final regression-test stage.
- Session reset: never run built-in commands; recommend one in the last line of a report when it clearly helps.
  Judge from context: 1) natural boundary? (work just finished or user stepping away) 2) what would be lost if the conversation ended now?
  Only when considering a recommendation, verify: `git status` and unpushed commits; plan doc/checklist records the current stage and decisions; no running subagents/agy; no pending questions.
  Before recommending `/clear`, move standing instructions given only in conversation (e.g. files never to commit, env/DB cautions) into the project CLAUDE.md or memory.
  Nothing lost → "`/clear` 권장 — 다음 시작 문장: <plan doc path · next stage · last commit · branch>" (note "push 안 됨" if applicable). Something unrecorded → record it or `/handoff`.
  At most once per boundary; if the user declines, do not repeat until the next boundary. Not for context size alone (auto-compact handles it). Use `/handoff` when pausing until a later day or moving to another PC.

## Environment

- Workspace layout:
  - `~/dev/` — code projects. Run agents from the project folder, not from `~`.
  - `~/agent/` — non-project agent work: `system/` (OS setup, cleanup), `storage/` (external drives, backups), `notes/` (research, documents; `notes/handoff/` for handoff memos).
- macOS: shell is zsh with aliases `ls`→`lsd`, `cat`→`bat --paging=never`. `grep` and `find` are NOT aliased; use them with standard syntax.
- Windows: Claude Code runs commands in Git Bash (no zsh aliases). Use `~`-style paths in Bash and `%USERPROFILE%` paths in PowerShell.
- Optional tools `rg`, `fd`, `zoxide`(`z`), `delta` may be missing on some machines; check with `command -v` before relying on them and fall back to `grep`/`find`.
- Do not move or rename tool config folders (`~/.claude`, `~/.gemini`, `~/.antigravity*`).
