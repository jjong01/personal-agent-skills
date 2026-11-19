---
name: delegate
description: 계획이 확정된 구현·시험 수정·브라우저 확인을 Antigravity CLI(agy)에 맡기고, Claude는 지시문 작성과 결과 검토만 해 Claude 토큰을 아낀다. 사용자가 위임, agy·Antigravity에 맡기기, /delegate를 요청하거나, 명세가 구체적인 구현 단계를 진행할 때 사용.
argument-hint: "<명세 문서 경로 또는 작업 설명> [--model <agy 모델>] [--browser]"
---

# agy 위임

Claude는 **준비도 점검 결과 판단 → 모델 선택 → 지시문 작성 → 결과 요약 검토 → 최종 확인**만 하고, 코드 작성·시험 통과·화면 확인은 agy가 끝까지 처리한다. 원칙: Claude 맥락에 긴 출력(diff 전체, 빌드 로그, 화면 내용)을 넣지 않는다.

**실행 위치**: 메인 세션에서 계획 단계를 진행할 때는 이 절차를 직접 실행하지 말고 `stage-runner` 서브에이전트(Agent 도구, `subagent_type: stage-runner`)에 저장소·계획 문서·단계명을 넘겨 실행한다. 메인은 반환된 보고만 읽는다.
- `QUESTIONS`가 오면 메인이 사용자에게 묻고, 답을 "사용자 결정 사항"으로 붙여 stage-runner를 다시 실행한다.
- `STAGE REPORT`가 오면 사용자에게 요약하고 커밋 승인을 받는다.
- 메인 세션이 이미 이 스킬을 따르는 서브에이전트 안이면 이 단락은 무시한다.

## 0. 시작 전 확인

- `git status --short`로 작업 트리 확인. 커밋 안 된 변경이 있으면 위임 전 사용자에게 알린다(agy 변경과 섞임).
- Claude 맥락이 이미 크면(긴 대화 이어 옴) `/handoff` → `/clear` 후 새 세션에서 위임하도록 제안한다.
- 크레딧(유료) 사용 설정은 켜지 않는다.

## 1. 준비도 점검 (agy plan 모드, 코드 수정 없음)

명세를 쓴 Claude는 빈 곳을 놓치기 쉬우므로 구현자 관점 점검을 agy에 맡긴다.

- **건너뛰는 경우**: 변경 파일 3개 이하이고 위치·내용이 명세에 다 적힌 작업.
- [prompt-template.md](prompt-template.md)의 "준비도 점검용"으로 지시문을 만들고 `AGY_MODE=plan`으로 실행한다(모델 `gemini-3.8-flash-high`, 4단계 실행 방식과 동일).
- Claude는 결과 목록만 읽고 항목별로 분류한다.
  - 코드·기존 결정(메모리·문서)으로 답할 수 있는 것 → Claude가 정한다.
  - 정책·업무 판단이 필요한 것 → 사용자에게 묻는다.
- 정한 내용은 **계획 문서에 반영한 뒤** 위임한다(지시문에만 적지 않음).
- "준비 완료"가 나오거나 남은 항목이 사소해질 때까지 반복하되 최대 2회.
- 결정이 필요했던 항목 수를 2단계 난이도 판정에 쓴다.

## 2. 모델 선택

인자 `--model`이 있으면 그대로 쓴다(이름은 `agy models`로 확인). 없으면 아래 순서로 정한다.

1. **남은 한도 확인**: `agy -p "/usage"`. 한도 묶음이 따로 있다: Gemini 공용(Flash·Hydrogen) 5시간·주간, Gemini 4 Argon 주간, Claude·GPT.
2. **난이도 판정**
   - 하: 위치·내용이 명세에 다 적힘, 변경 파일 3개 이하, 화면 문구·스타일 위주
   - 중: 여러 파일 일관 수정, 계산·권한·상태 전이 로직, 시험 추가
   - 상: 1단계에서 결정 항목이 3개 이상 나왔던 명세, 설계 판단 포함, 재위임
3. **기본 매핑**

| 용도 | 모델 |
|---|---|
| 난이도 하 | `gemini-3.8-flash-medium` |
| 난이도 중 (기본) | `gemini-3.8-flash-high` |
| 난이도 상 | `gemini-4-argon-medium` |
| 준비도 점검 | `gemini-3.8-flash-high` |
| 브라우저 확인 | `gemini-3.8-flash-medium` |

4. **한도 반영**
   - Gemini 공용 5시간 20% 미만 → 하·중 작업을 Argon으로 넘길지, 초기화 시각까지 기다릴지 사용자에게 묻는다.
   - Gemini 공용 주간 20% 미만 → 사용자에게 알리고 난이도 상만 위임한다.
   - Argon 주간 20% 미만 → 난이도 상은 `gemini-4-hydrogen-high`로 한다.
   - **한도 소진 시 대체 순서**(남은 양 5% 미만이면 소진으로 봄): Gemini 공용 → Argon(`gemini-4-argon-medium`) → agy의 Claude·GPT 묶음(`claude-sonnet-5-5-medium`). Claude·GPT 묶음은 Antigravity 구독 한도라 Claude Code 사용량과 별개이며, Gemini 묶음이 모두 소진됐을 때만 쓴다.
   - **모든 묶음 소진** → 위임하지 않고 멈춘다. 초기화 시각을 알리고 "초기화까지 대기 / Claude가 직접 구현" 중 사용자 선택을 받는다(직접 구현은 사용자 승인 시에만).
5. 고른 모델·난이도·근거가 된 남은 한도를 한 줄로 알린다.
6. 매핑을 바꿀 때는 `~/agent/notes/agy-model-log.md` 기록(8단계)을 근거로 한다. 같은 모델·난이도에서 재작업이 2회 이상 쌓이면 한 단계 높은 모델을 제안한다.

## 3. 지시문 작성

[prompt-template.md](prompt-template.md)를 채워 Claude 세션 scratchpad에 `agy_<작업>_prompt.txt`로 저장한다.

- 명세 문서는 **경로와 절 번호만** 적고 내용을 복사하지 않는다(agy가 직접 읽음).
- 금지 사항(커밋·push·DB·`.env`·기존 시험 의미 변경)과 완료 조건(시험 통과 명령)을 반드시 넣는다.
- 마지막 보고는 템플릿의 `=== REPORT ===` 형식으로만 출력하게 한다.

## 4. 실행

반드시 [run-agy.sh](../../../lib/run-agy.sh)(설치 후 `~/agent/lib/run-agy.sh`)로 실행한다(`agy`를 직접 부르지 않음, `--dangerously-skip-permissions` 금지). 래퍼가 처리하는 것:

- `--settings`는 전역 권한을 **덮어쓰므로** 전역 deny, 기본 deny(git 상태 변경·DB·ssh·rm -rf), 저장소 `.env` 읽기 차단을 매번 합쳐 넘긴다.
- 읽기 전용 명령(ls, cat, grep, git status/diff/log 등)은 기본 허용한다. 비대화 모드에서는 allow 목록 밖 명령을 하나라도 쓰면 **보고 없이 종료**되기 때문이다.

추가 허용은 프로젝트의 시험·빌드 명령만 인자로 넘긴다. 규칙은 **접두어 일치**다(`command(mvn test)`는 `mvn test -q`도 허용). `*`를 붙이면 일치하지 않는다.

| 프로젝트 | 추가 allow 예 |
|---|---|
| Maven | `command(mvn test)`, `command(mvn -q test)`, `command(mvn clean test)`, `command(mvn compile)` |
| Gradle | `command(./gradlew test)`, `command(./gradlew assemble)`, `command(./gradlew lint)` |
| npm | `command(npm test)`, `command(npm run build)`, `command(npm run lint)`, `command(npx eslint)` |

```sh
S=<scratchpad>; ~/agent/lib/run-agy.sh <저장소> <모델> $S/agy_<작업>_prompt.txt $S/agy_<작업>.log \
  'command(mvn test)' 'command(mvn -q test)'
```

- 로그 끝에 `AGY_DENIED`가 있으면 목록 밖 명령으로 멈춘 것이다. 해당 CLI 로그에서 명령을 확인해 안전하면 allow에 추가해 다시 실행하고, 위험하면 지시문에서 그 작업을 빼거나 Claude가 처리한다.
- Bash `run_in_background: true`로 실행한다. **완료 알림이 올 때까지 로그를 tail하거나 git status로 진행을 확인하지 않는다.**
- 사용자에게는 모델, 범위, 로그 경로를 3줄 이내로 알린다.

## 5. 결과 검토 (Claude 토큰 최소화)

1. 보고만 읽는다: `sed -n '/=== REPORT ===/,$p' $S/agy_<작업>.log | head -80`. 보고가 없으면 `tail -c 2000`만 본다.
2. `git status --short`, `git diff --stat`.
3. 위험 파일만 골라 해당 파일 diff를 본다: 권한·보안·결제, DB 마이그레이션, 설정, 삭제된 코드, 보고에 "불확실"로 적힌 곳. 전체 diff는 보지 않는다.
4. 확인 시험 1회: 결과는 요약만 본다(예: `mvn -q test 2>&1 | grep -E 'Tests run:|FAIL|ERROR' | tail -20`, `npm run build 2>&1 | tail -15`).
5. 금지 사항 위반 확인: 커밋 생성 여부(`git log -1`), 기존 시험 단언 변경 여부(`git diff --stat -- '*Test*' '*.test.*'`).

## 6. 수정

- 몇 줄 고치면 되는 문제 → Claude가 직접 고친다.
- 여러 곳이 틀렸거나 시험 실패가 남음 → 지적 사항만 적은 짧은 지시문으로 재위임(같은 모델 1회, 그다음 한 단계 높은 모델 1회: flash-medium → flash-high → argon-medium → hydrogen-high). 두 번 넘게 실패하면 멈추고 사용자에게 보고한다.
- 실행 중 한도가 소진돼 멈춘 경우(로그 끝 `AGY_USAGE`에 5% 미만 묶음) → 바뀐 파일은 그대로 두고, 2단계 대체 순서의 다음 묶음 모델로 "이미 바뀐 파일을 이어서 완성"하는 지시문을 다시 위임한다.

## 7. 브라우저 확인 (`--browser`, 사용자 요청, 또는 화면 시나리오가 있는 계획의 마지막 구현 단계 커밋 후)

Claude 브라우저 도구 대신 agy(chrome-devtools 플러그인)에 맡긴다. 로그인 계정은 프로젝트 `AGENTS.md`의 로컬 시험 계정을 지시문에 적고, 없으면 사용자에게 받는다(`.env`에서 찾지 않음). 확인할 URL·계정·시나리오·기대 결과를 지시문에 적고, 결과는 시나리오별 `통과/실패 + 한 줄 근거`로만 보고하게 한다. 실패 항목만 Claude가 직접 다시 본다.

## 8. 마무리

- `agy -p "/usage"`로 사용량 변화를 확인한다.
- `~/agent/notes/agy-model-log.md`에 한 줄 추가한다(없으면 머리글 포함 생성):
  `| 날짜 | 프로젝트 | 작업 | 난이도 | 모델 | 결과(통과/Claude 수정/재위임 n회/실패) | 사용량 변화 |`
- 사용자에게 보고: 바뀐 것(기능 단위), 검토하며 고친 것, 시험 결과, 남은 위험, 사용량 변화. 커밋은 사용자가 요청할 때 `/commit`으로 한다.
- 다음 단계가 이어지면 `/handoff` → `/clear` 후 새 세션에서 진행하도록 제안한다.
