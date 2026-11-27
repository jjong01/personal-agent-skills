# 전반적인 시스템 사용 가이드

Claude Code와 Antigravity(agy)를 연계한 개인 에이전트 작업 환경의 구성, 폴더 구조, 작업 흐름, 모델 관리 및 설정 가이드.

## 1. 구성 개요

| 역할 | 담당 | 하는 일 |
|---|---|---|
| 메인 세션 | Claude Code (Opus) | 계획·설계 판단, 사용자 질의응답, 결과 검토, 커밋·push 승인 |
| stage-runner | Claude 서브에이전트 (Sonnet) | 계획 문서의 한 단계를 delegate 절차로 끝까지 처리하고 결과 요약만 반환 |
| 백그라운드 작업자 | Claude 서브에이전트 (Sonnet) | 다단계 스크립트 작성·테스트·검토 등 병렬 처리 (메인 대화 지속 가능) |
| agy | Antigravity CLI (Gemini 등) | 코드 구현, 빌드·시험 수정, 대량 자료 조사, 브라우저 조작, 이미지 생성 |

- **세션 원칙**: 메인 세션 맥락에 대량 코드·빌드 로그·웹 문서·이미지를 넣지 않음. 긴 대화는 160k 자동 요약(`autoCompactWindow`), 기능 전환 시 `/clear`.
- **기록 유지**: 중요한 결정은 계획 문서와 Claude 메모리에 기록해 세션 요약·초기화 후에도 유지함.

## 2. 폴더 구성 및 링크 관계

### 폴더 구성
- `~/dev/`: 코드 프로젝트 작업 공간 (에이전트는 반드시 프로젝트 폴더 내에서 실행).
- `~/agent/`: 비프로젝트 전용 에이전트 작업 공간.
  - `system/`: OS 설정 및 유지보수 스크립트.
  - `storage/`: 외장 드라이브 및 영구 보관소 (예: `storage/image-backup/`).
  - `notes/`: 조사 보고서, 비교 분석, 기술 문서 (하위 `notes/handoff/`: 세션 인계 메모).
  - `lib/`: 저장소 `lib/`의 링크 (공용 실행 스크립트 모음).
  - `AGENTS.md`: 저장소 `global/AGENTS.md`의 링크 (전역 공통 규칙).

### 원본 및 링크 관계
| 원본 경로 (`personal-agent-skills`) | 연결 경로 | 설명 |
|---|---|---|
| `global/AGENTS.md` | `~/agent/AGENTS.md` | 공통 전역 규칙 (아래 두 파일의 원본) |
| `~/agent/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md` | Claude Code 및 agy에 동일 규칙 적용 |
| `skills/<분류>/<이름>/` | `~/.claude/skills/<이름>` | 도구별 평평한 구조로 링크 (`.claude-only` 제외 시 `~/.gemini/config/skills/<이름>`에도 연결) |
| `agents/*.md` | `~/.claude/agents/*.md` | Claude 서브에이전트 정의 (`stage-runner.md`) |
| `lib/` | `~/agent/lib` | 스킬 공용 스크립트 (`run-agy.sh`, `run-logged.sh`, `agy-denied.py` 등) |
| `extras/statusline.sh` | `~/.claude/statusline.sh` | 구독·맥락·할당량·Grok 주간 사용률 표시 상태줄 (jq 필요, Grok 사용량은 `grok usage --json` 지원 시 표시) |
| `extras/terminal-status.sh` | `~/.claude/hooks/terminal-status.sh` | 작업 종료·오류·알림 터미널 효과음/OS 알림 |
| `settings/` | `~/.claude/settings.json`, `~/.gemini/.../settings.json` | 공용 설정을 기기 설정에 병합 (기존 값 유지) |

## 3. 스킬별 용도 및 호출 예시

| 이름 | 언제 쓰나 | 호출 예 |
|---|---|---|
| `commit` | 변경 분석 후 저장소 형식에 맞는 커밋 메시지 작성 및 확인 후 커밋 (git·SVN, AI 흔적 차단) | `/commit`, `/commit --message-only` |
| `delegate` | 확정된 계획의 구현·시험 수정·브라우저 검증을 agy에 위임 (Claude 토큰 절약) | `stage-runner` 자동 호출, `/delegate docs/plan.md` |
| `offload` | 대량 읽기 작업(웹 조사, 자료 비교, 긴 문서 요약, 번역, 정리안 작성)을 agy에 읽기 전용 위임 | `/offload "AWS 요금 비교"`, `/offload "API 문서 요약" ./docs/` |
| `handoff` | 작업을 끊고 다른 날/PC에서 이어할 때 인계 메모 작성 및 새 대화에서 복원 | `/handoff <진행상황 요약>`, `/handoff load` |
| `image-edit` | 프로젝트 이미지 규격 변환·교체(직접) 및 텍스트 수정·생성(agy 위임) | `/image-edit ./icon.png "로고 텍스트 변경"`, `/image-edit ./banner.png 800x400` |

## 4. 작업 흐름

### 개발 구현 및 검증 흐름
```
[계획 수립] 메인(Opus): 계획 문서 작성 및 단계 분할 (HS1, WS1 등)
    │
    ▼
[단계 위임] 메인 세션: stage-runner(Sonnet) 호출 (사용자 사전 질의 없이 착수)
    │       ├─ agy 준비도 점검 (plan 모드, 변경 파일 ≤3개 시 생략)
    │       ├─ 질문 발생 시: QUESTIONS 반환 → 메인이 사용자 확인 후 재위임
    │       └─ agy 실행: run-agy.sh 기반 구현 및 run-logged.sh 기반 시험 수행
    ▼
[결과 검토] stage-runner 보고(STAGE REPORT) 수신 → 변경 diff 요약·로그·위험 파일 검토
    │
    ▼
[커밋 승인] 메인 세션: 사용자 승인 확인 후 /commit 실행 (경계 시 /clear 추천)
    │
    ▼
[화면 확인] 마지막 단계 완료 후: 메인이 확인 항목표(위치·동작·기대 결과) 제공 → 사용자 직접 확인
    │       (agy 브라우저 확인은 사용자 요청 시만. 느려서 기본에서 제외)
    │
    ▼
[병합 전 검토] 메인/서브에이전트: /code-review low 실행, 보안·인증 변경 시 /security-review 병행
    │
    ▼
[브랜치 병합] 검토 보고 확인 후 feature 브랜치를 대상 브랜치(develop 등)에 병합
```

### 일반 업무(Offload) 흐름
```
사용자 요청(조사·요약·비교) → /offload 실행 (지시문 작성)
    │
    ▼
run-offload.sh 호출 → agy plan 모드로 웹 검색/문서 독해 (읽기 전용 안전 격리)
    │
    ▼
결과 파일 생성(~/agent/notes/YYYYMMDD-<주제>.md) → Claude가 요약 및 핵심 출처만 확인 후 보고
    │
    ▼
(정리안 실행 필요 시) Claude가 생성된 스크립트 검토 → 사용자 승인 → 직접 실행
```

## 5. agy 모델 선택 및 한도 요약

모델 선택의 유일한 기준은 `lib/agy-models.tsv`(설치 후 `~/agent/lib/agy-models.tsv`)의 용도 열이며, 스킬은 `~/agent/lib/agy-pick.sh <용도>`가 출력하는 모델을 그대로 쓴다. 문서에 모델 매핑을 따로 적지 않는다.

- **용도 체계**: `구현-하|중|상`, `점검`(준비도), `브라우저`, `조사-기본|비교|분석|넓음`(offload), `이미지-기본|상`, `대체-1|2|3`(한도 소진 시 순서: Gemini 공용 → Argon → Claude·GPT), `평가중`, `조건부후보`, `사용안함`. 한 모델이 여러 용도면 쉼표로 적고, `묶음` 열(gemini/argon/claude-gpt)이 한도 묶음을 정한다.
- **실행**: `agy-pick.sh 구현-중` → `<모델>\t<근거>` 1줄. 근거에 용도·묶음·남은 %가 담기며 보고에 그대로 적는다.
- **한도 판단**: `~/.cache/agy-quota.tsv`(상태줄 5분 캐시, 환경 변수 `AGY_QUOTA_FILE`로 변경 가능)에서 묶음별 5시간·주간 중 작은 값을 쓴다. 5% 미만 소진 → 대체 순서의 다음 묶음 모델, 20% 미만 `부족` 표시. 캐시가 없거나 30분 초과, 또는 묶음 행이 없으면(Argon 등) 한도 미확인으로 tsv 선택을 그대로 쓴다.
- **전체 소진**: `QUOTA` 출력과 종료 코드 3 → 즉시 중단 후 초기화 시각 안내(대기 또는 사용자 승인 시 Claude 직접 구현).
- **매핑 변경·평가**: tsv 용도 열 한 줄 수정. `~/agent/notes/agy-model-log.md`에 같은 용도 통과 기록 3건 이상이면 교체 제안.
- 현재 tsv 기준 예시(변경될 수 있음): 구현-하 `gemini-4-hydrogen-medium`, 구현-중 `gemini-4-hydrogen-high`, 구현-상 `gemini-4-argon-medium`, 점검 `gemini-3.8-flash-high`, 브라우저 `gemini-3.8-flash-medium`.

## 6. 자주 겪는 문제와 대처

- **`AGY_DENIED: <명령>` 발생**:
  - 원인: `run-agy.sh`의 allow 목록(공백 단위 접두어 일치)에 없는 명령을 agy가 실행하려 함.
  - 대처: 안전한 빌드/시험 명령이면 호출 인자에 `command(<명령>)`을 추가해 재실행 (예: `command(mvn -q test)`). 위험 명령이면 지시문에서 제외하거나 Claude가 직접 처리. `(명령 확인 불가)` 시 transcript_full.jsonl 끝의 CommandLine 확인.
- **보고 없이 중단 / `(명령 확인 불가)`**:
  - 원인: 비대화 모드에서 허용되지 않은 명령 실행 시도 또는 대화형 프롬프트 대기.
  - 대처: 로그 파일 끝의 `AGY_USAGE` 및 `AGY_EXIT` 확인. 필요 시 transcript 확인 후 allow 추가.
- **서브에이전트 시험 실행 차단 (context-mode 훅)**:
  - 원인: context-mode 플러그인이 서브에이전트 내 `mvn`·`gradle` 등 빌드 도구 직접 실행을 차단.
  - 대처: 반드시 `~/agent/lib/run-logged.sh <로그> <명령...>` 래퍼를 통해 실행함.
- **한도 소진 중단 (`QUOTA`)**:
  - 원인: 실행 도중 Gemini/Argon 할당량 소진 (남은 양 5% 미만).
  - 대처: 변경된 파일은 유지하고, `agy-pick.sh`를 다시 실행해 나온 다음 묶음 모델로 "이미 수정된 파일을 이어 완성"하도록 재위임.
- **브라우저 확인 실패 / 로그인 불가**:
  - 원인: MCP 등록 누락 또는 테스트 계정 미지정.
  - 대처: `agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.10.1` 설치 확인. `.env` 탐색은 차단되어 있으므로 `AGENTS.md` 계정 또는 메인 세션을 통해 사용자에게 계정을 받아 진행.

## 7. 새 PC 설정 순서

| 순서 | macOS | Windows |
|---|---|---|
| 1. Claude Code | 공식 설치 안내 후 `claude` 로그인 | 같음 (Git Bash 환경에서 실행) |
| 2. Git | 기본 포함 | `winget install Git.Git` |
| 3. Python·PIL | `brew install python && pip3 install pillow` | `winget install Python.Python.3.12` 후 `pip install pillow` |
| 4. agy | `brew install --cask antigravity-cli` 후 `agy` 로그인, `agy models` 확인 | 설치 후 동일하게 로그인 및 모델 확인 |
| 5. 저장소 | `git clone … ~/dev/personal-agent-skills` | `git clone … $HOME\dev\personal-agent-skills` |
| 6. 설치 | `./install.sh --dry-run` → `./install.sh` | 개발자 모드 활성화 후 `install.ps1 -DryRun` → `install.ps1` |
| 7. 플러그인 | Claude Code에서 `/plugin install context-mode@context-mode` | 같음 |
| 7-1. 브라우저 확인 | `agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.10.1` | 같음 (요청 시 agy 브라우저 확인에만 필요) |
| 8. 점검 | 설치 스크립트 출력의 `확인 필요` 항목 해결 | 같음 |
| 9. 사용량 확인 | `npx ccusage@latest`로 토큰 사용량 확인 | 같음 |

설치 스크립트 동작: 디렉터리 생성(`~/dev`, `~/agent/...`), 공통 규칙·스킬·서브에이전트·스크립트 심볼릭 링크 생성, `settings/` 설정을 기기 설정에 안전 병합(기존 값 유지, 백업 후 쓰기).

## 8. 기기별로 따로 필요한 것

공개 저장소에 포함되지 않는 로컬 고유 설정:

| 항목 | 위치 | 설정 및 주의점 |
|---|---|---|
| 프로젝트 지시 파일 | 각 프로젝트 `AGENTS.md` / `CLAUDE.md` | `/init`으로 생성하거나 별도 복사. 없으면 구조 탐색으로 토큰 소모 증가 |
| Claude 기억 | `~/.claude/projects/*/memory/` | 핵심 설계 결정은 프로젝트 문서에도 기록 권장 |
| 테마 및 추가 훅 | `~/.claude/settings.json` | 기기별 설정 (공용 설정에는 기본 훅 3종만 등록됨) |
| claude.ai 동기화 스킬 | `~/.claude/skills/synced/` | 동일 계정 로그인 시 자동 동기화 |
| 프로젝트 `.env` 차단 | agy 실행 설정 | `run-agy.sh` 실행 시 저장소 내 `.env` 경로를 자동으로 읽기 거부 등록 |
| 계정 로그인 및 한도 | Claude Code / agy | 각 PC에서 독립적으로 인증 진행 |

## 9. 내장 명령 (설치 불필요)

| 명령 | 언제 쓰나 |
|---|---|
| `/init` | 프로젝트 최초 셋업 시 지시 파일 생성 (토큰 절약 핵심) |
| `/code-review low` | PR 생성 및 브랜치 병합 전 버그/품질 검토 |
| `/security-review` | 인증·권한·결제·개인정보·토큰 관련 코드 수정 시 필수 검토 |
| `/simplify` | 구현 완료 후 불필요한 코드 및 중복 정리 제안 |
| `/fewer-permission-prompts` | 1~2주 사용 후 반복되는 읽기 권한 일괄 허용 |
| `/context` | 현재 대화 맥락 사용량 확인 |
| `/compact` | 수동 대화 요약 (기본은 자동 요약에 위임) |
| `/clear` | 작업 주제나 기능이 바뀔 때 맥락 초기화 |

## 10. 토큰 절약 체크리스트

- [ ] 프로젝트마다 `/init`으로 작성된 지시 파일이 존재하는가
- [ ] 명세가 구체적인 구현·수정은 `stage-runner` 및 agy에 위임하는가
- [ ] 대량 문서 독해, 조사, 번역은 `/offload`를 사용하는가
- [ ] 이미지나 대용량 로그를 직접 붙여넣지 않고 파일 경로로 넘기는가
- [ ] 작업 주제가 전환될 때 `/clear`를 실행하는가
- [ ] `context-mode` 플러그인이 정상 작동 중인가
- [ ] 주기적으로 `npx ccusage@latest`로 사용량을 점검하는가

## 11. 도입 이력·추천 순위

2026-11-18 토큰 절약 설정 작업에서 정한 추천 순위와 적용 상태. 상세 근거는 개인 인계 메모(`~/agent/notes/handoff/`)에 기록함.

| 순위 | 항목 | 상태 | 비고 |
|---|---|---|---|
| 1 | `/init`으로 프로젝트 지시 파일 생성 | 적용 (2026-11-18) | 기존 프로젝트 4곳. 각 저장소 ignore 목록에 `/CLAUDE.md` 추가(SVN 저장소는 svn:ignore도) |
| 2 | 사용자 스킬 `commit`·`handoff` | 적용 | 이후 이 저장소 `skills/`로 이관 |
| 3 | context-mode 플러그인 (mksglu/context-mode) | 적용 | 훅·스크립트 검토 후 설치. 서브에이전트 빌드 명령 차단은 `run-logged.sh`로 대응 |
| 보류 | ccusage 재측정 | 예정 | 기준값 `~/agent/notes/ccusage-baseline-20261118.json`. 1~2주 사용 후 `npx -y ccusage@latest monthly --by-agent`로 비교 |
| 보류 | Ponytail (DietrichGebert/ponytail) | 미정 | 재측정 결과 보고 결정. 적용 시 코드 프로젝트만, `PONYTAIL_MAP=0`, Task board 끔, `lite`로 시작 |
| 낮음 | `/android-build` 스킬 | 미생성 | 필요할 때 생성 |

- 판단 근거: Claude 토큰의 96~98%가 캐시 읽기(누적 맥락)이므로 맥락 축소(`/init`, `/clear`, context-mode, 위임)가 우선이고 출력 축소 도구(Ponytail 등)는 효과가 작음.

## 12. agy에서 스킬 사용

agy도 같은 `SKILL.md` 형식을 읽음(전역 `~/.gemini/config/skills/<이름>/`, 설명 매칭 자동 사용 또는 `/<이름>` 호출). 설치 스크립트는 `.claude-only` 표시가 없는 스킬만 agy 쪽에 링크함.

| 스킬 | agy | 비고 |
|---|---|---|
| `commit`, `handoff` | 동작 | 공통 링크 |
| `delegate`, `offload` | 제외 (`.claude-only`) | Claude 토큰 절약용 위임 구조라 agy 안에서는 불필요. agy에서는 직접 처리하거나 내장 서브에이전트(`research` 등)·워크플로 사용 |
| `image-edit` | 제외 (`.claude-only`) | agy에서는 내장 이미지 생성 기능과 `sips`·PIL 직접 사용 |

- 방침: 위임 계열 스킬은 agy용으로 따로 만들지 않음. `SKILL.md` 안 환경별 분기나 래퍼의 agy 내부 감지는 맥락 증가·세션 충돌 위험으로 채택하지 않음.
- 미확인: 비대화 모드(`agy -p`)에서 내장 서브에이전트 안정성, Windows Junction 링크 스킬 인식 여부.
- Orca 작업자 안전 제한: Orca가 띄우는 agy·Grok은 `--settings`가 없어 전역 설정이 적용됨. `install.sh` 5-1절이 `lib/safety-deny.txt`(git 상태 변경·`rm -rf`·`sudo`·DB·ssh 계열 명령 접두사 단일 원본)를 agy 전역 `settings.json`(`command(...)`, `.env` 명령 regex, `~/dev` 아래 `.env` 파일 `read_file`), agy 공용 `~/.gemini/config/config.json`(`userSettings.globalPermissionGrants.deny`), Grok `~/.grok/config.toml [permission] deny`(`Bash(<접두사>*)`, `Read(**/.env)`, `Read(**/.env.*)`)에 병합함(멱등, `--dry-run` 지원). Orca agy 채팅(ACP)은 CLI `settings.json`이 아니라 `~/.gemini/config/config.json`의 `globalPermissionGrants.deny`를 따르므로 `install.sh` 5-1절이 두 곳 모두에 병합함. `run-agy.sh`도 같은 파일을 읽어 `--settings`에 넣으므로 stage-runner 경로와 Orca 경로의 제한이 같음. 새 `~/dev` 프로젝트의 `.env`는 `install.sh` 재실행으로 반영.

## 13. 정기 ping (macOS 전용, 선택)

- 용도: 평일 정해진 시각에 `claude`·`agy`를 1회씩 호출해 사용량 5시간 구간의 시작 시각을 맞춤. 기본 시각 06:30 / 11:31 / 16:32(구간 경계에 1분 마진)
- 지원: macOS(launchd)만. Windows(`install.ps1`)는 미지원

### 설치

- `./install.sh --with-ping` (`--dry-run` 병행 가능). 시각 변경: `PING_TIMES="07:00 12:01" ./install.sh --with-ping`
- 동작: `extras/scheduled-ping/`를 `~/agent/scheduled-ping`으로 연결, plist 템플릿의 `__HOME__`·시각을 치환해 `~/Library/LaunchAgents/local.agent-ping.{claude,agy}.plist`에 쓰고 `launchctl bootstrap gui/<uid>`로 등록(이미 있으면 bootout 후 재등록)
- 기존 `*.claude-ping`·`*.agy-ping` 작업이 있으면 중복 실행되므로 경고만 출력함. 제거는 직접 수행
- 모델·바이너리 경로: 각 `run-*.sh` 상단 변수(`MODEL`, `CLAUDE_BIN`, `AGY_BIN`)
- 대상 아님: Grok Build CLI는 주간 한도만 있고 5시간 구간이 없어 ping 효과가 없음(한도만 소모). 2026-11-27 확인

### 토큰 발급·키체인 등록 (Claude용)

1. 별도 터미널에서 `claude setup-token` 실행 후 출력된 `sk-ant-oat01-...` 토큰 복사
2. `security add-generic-password -U -a "$(id -un)" -s claude-ping-oauth -w` 실행 후 프롬프트에 토큰 붙여넣기
3. 토큰이 없으면 기존 로그인 상태로 실행함(만료 시 실패 가능)

### 로그·점검·교체

- 로그: `~/Library/Logs/agent-ping-claude.log`, `~/Library/Logs/agent-ping-agy.log` (`exit=0`이 정상)
- 상태: `launchctl print gui/$(id -u)/local.agent-ping.claude`
- 토큰 만료 시: `claude setup-token`으로 재발급 후 2번 명령을 다시 실행(`-U`로 덮어씀). 재설치 불필요
- 제거: `launchctl bootout gui/$(id -u)/local.agent-ping.<claude|agy>` 후 plist 삭제
