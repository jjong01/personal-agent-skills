# 사용 가이드

이 저장소로 구성한 Claude Code·Antigravity(agy) 작업 환경의 전체 구조와 새 PC 설정 방법.

## 1. 구성 개요

| 역할 | 담당 | 하는 일 |
|---|---|---|
| 메인 세션 | Claude Code (Opus) | 계획·설계 판단, 사용자 질문 응답, 결과 검토, 커밋·push |
| stage-runner | Claude 서브에이전트 (Sonnet) | 계획 문서 한 단계를 delegate 절차로 끝까지 처리하고 짧은 보고만 반환 |
| 백그라운드 서브에이전트 | Claude 서브에이전트 (Sonnet) | 그 밖의 여러 단계 작업. 메인은 그동안 질문에 답함 |
| agy | Antigravity CLI (Gemini 등) | 실제 구현, 대량 읽기·조사, 이미지 생성 |

| 스킬 | 언제 | 비고 |
|---|---|---|
| `delegate` | 계획이 확정된 구현·시험 수정·브라우저 확인 | stage-runner가 실행. 계획 단계는 묻지 않고 진행 |
| `offload` | 웹 조사·자료 비교·긴 문서 요약·번역·정리안 | agy 읽기 전용, 결과는 파일로 |
| `image-edit` | 이미지 교체·자르기·글자 수정 등 | 파일 작업은 직접, 내용 편집은 agy 이미지 생성 |
| `commit` | 커밋 | 저장소 형식 감지, AI 흔적 없음 |
| `handoff` | 작업을 다른 날·다른 PC로 넘길 때 | 맥락 크기 때문에는 쓰지 않음 |

- 긴 세션: `autoCompactWindow` 160k에서 자동 요약됨. 기능이 바뀌면 `/clear`.
- 기록: 결정은 계획 문서와 Claude 기억(memory)에 남겨 요약·초기화 후에도 이어짐.
- agy 한도 소진 시 Gemini 공용 → Argon → agy Claude 묶음 순으로 바꾸고, 모두 소진되면 사용자 승인 후에만 Claude가 직접 구현함.

## 2. 새 PC 설정 순서

| 순서 | macOS | Windows |
|---|---|---|
| 1. Claude Code | 공식 설치 안내 후 `claude` 로그인 | 같음 (명령은 Git Bash에서 실행됨) |
| 2. Git | 기본 포함 | `winget install Git.Git` |
| 3. Python·PIL | `brew install python && pip3 install pillow` | `winget install Python.Python.3.12` 후 `pip install pillow` |
| 4. agy | `brew install --cask antigravity-cli` 후 `agy` 한 번 실행해 로그인, `agy models`로 확인 | 설치 후 같은 방법으로 로그인·확인 |
| 5. 저장소 | `git clone … ~/dev/personal-agent-skills` | `git clone … $HOME\dev\personal-agent-skills` |
| 6. 설치 | `./install.sh --dry-run` → `./install.sh` | 개발자 모드 켠 뒤 `install.ps1 -DryRun` → `install.ps1` |
| 7. 플러그인 | Claude Code에서 `/plugin install context-mode@context-mode` | 같음 |
| 8. 점검 | 설치 마지막 "점검" 결과에서 `확인 필요` 항목 해결 | 같음 |
| 9. 측정(선택) | `npx ccusage@latest`로 토큰 사용량 확인 | 같음 |

설치 스크립트가 하는 일: 폴더 구조(`~/dev`, `~/agent/...`), 공통 규칙·스킬·서브에이전트·`~/agent/lib` 링크, `settings/`의 공용 설정을 기기 설정에 병합(기존 값 유지, 백업 후 쓰기), 도구 확인, 점검.

## 3. 기기별로 따로 필요한 것

이 저장소는 공개 저장소이므로 아래는 올리지 않는다. 상태줄(`extras/statusline.sh`, jq 필요)은 저장소에 있으며 설치 시 연결·설정됨.

| 항목 | 위치 | 새 PC에서 |
|---|---|---|
| 프로젝트 지시 파일 | 각 프로젝트의 `AGENTS.md`·`CLAUDE.md` (gitignore된 경우) | 프로젝트에서 `/init`으로 다시 만들거나 비공개 경로로 복사. **없으면 에이전트가 구조를 매번 다시 탐색해 토큰을 더 씀** |
| Claude 기억 | `~/.claude/projects/*/memory/` | 필요한 결정은 프로젝트 문서에도 남겨 둠 |
| hooks·theme | `~/.claude/settings.json` | 기기별로 설정(알림 소리 등 터미널별 개인 설정) |
| claude.ai 동기화 스킬 | `~/.claude/skills/synced/` | 같은 계정으로 로그인하면 자동으로 받아짐(docs·pptx·xlsx 등) |
| 프로젝트 `.env` 읽기 차단(agy) | agy 설정 | `run-agy.sh`가 실행 때마다 자동 추가함 |
| 로그인·한도 | Claude·agy 계정 | 각 PC에서 로그인 |

## 4. 내장 명령 (설치 불필요)

| 명령 | 언제 |
|---|---|
| `/init` | 프로젝트마다 한 번. 프로젝트 지시 파일 생성 — 토큰 절약 효과가 가장 큼 |
| `/code-review low` | 커밋 전 버그 검토 |
| `/simplify` | 기능 구현 후 중복·불필요 코드 정리 |
| `/security-review` | 인증·결제·권한 관련 변경 시 |
| `/fewer-permission-prompts` | 1~2주 사용 후 한 번. 자주 쓰는 읽기 명령 허용 |
| `/context` | 맥락 크기 확인 |
| `/compact` | 수동 요약(보통은 자동 요약에 맡김) |
| `/clear` | 기능·주제가 바뀔 때 |

## 5. 토큰 절약 체크리스트

- 프로젝트마다 지시 파일(`/init`)이 있는지
- 구현은 stage-runner·agy, 대량 읽기는 offload로 맡기는지
- 이미지·긴 로그를 대화에 붙여 넣지 않고 파일 경로로 전달하는지
- 주제가 바뀌면 `/clear`, 긴 세션은 자동 요약에 맡기는지
- context-mode 플러그인이 설치돼 있는지(`/plugin`)
- 가끔 `npx ccusage@latest`로 사용량 확인
