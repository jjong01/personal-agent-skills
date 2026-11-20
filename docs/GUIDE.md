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
| `extras/statusline.sh` | `~/.claude/statusline.sh` | 구독·맥락·할당량 표시 상태줄 (jq 필요) |
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
[커밋 승인] 메인 세션: 사용자 승인 확인 후 /commit 실행 (기능 전환 시 /handoff → /clear)
    │
    ▼
[화면 확인] 마지막 단계 완료 후: stage-runner --browser 로 agy chrome-devtools MCP 검증
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

`delegate` 및 `offload` 실행 시 적용되는 모델 매핑 및 한도 관리 기준:

| 난이도 / 용도 | 기본 모델 | 모델 성격 및 한도 규칙 |
|---|---|---|
| 난이도 하 | `gemini-4-hydrogen-medium` | 변경 파일 ≤3개, 명세 명확, 스타일 위주 (Gemini 공용 묶음) |
| 난이도 중 (기본) | `gemini-3.8-flash-high` | 여러 파일 일관 수정, 비즈니스 로직, 시험 추가. 준비도 점검 겸용 |
| 난이도 중 (비교) | `gemini-4-hydrogen-high` | flash-high 결과 비교용 또는 Argon 주간 한도 부족 시 난이도 상 대체 |
| 난이도 상 | `gemini-4-argon-medium` | 설계 판단 필요, 점검 시 결정 항목 ≥3개. 주간 한도 별도 관리 |
| 준비도 점검 | `gemini-3.8-flash-high` | plan 모드로 구현 전 명세 빈 곳 사전 검토 |
| 브라우저 확인 | `gemini-3.8-flash-medium` | chrome-devtools MCP 전용, 시나리오별 통과/실패 판정 |
| 심층/넓은 조사 | `gemini-pro-orchestrator-neon` | offload 전용: 독립 주제 3개 이상 꼼꼼한 조사 시 하위 에이전트 분할 활용 |
| 최후 대체 | `claude-sonnet-5-5-medium` | Gemini·Argon 묶음 모두 소진 시 agy 내 Claude 묶음 활용 |

- **한도 소진 시 대체 순서**: Gemini 공용(남은 양 <5%) → Argon(`gemini-4-argon-medium`) → agy Claude·GPT(`claude-sonnet-5-5-medium`).
- **전체 소진 시**: 즉시 중단 후 사용자에게 초기화 시각 안내 (대기 또는 사용자 승인 시 Claude 직접 구현).

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
  - 대처: 변경된 파일은 유지하고, 대체 순서의 다음 모델로 "이미 수정된 파일을 이어 완성"하도록 재위임.
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
| 7-1. 브라우저 확인 | `agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.10.1` | 같음 (delegate 브라우저 검증 시 필수) |
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
