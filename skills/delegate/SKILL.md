---
name: delegate
description: 계획이 확정된 구현·시험 수정·브라우저 확인을 Antigravity CLI(agy)에 맡기고, Claude는 지시문 작성과 결과 검토만 해 Claude 토큰을 아낀다. 사용자가 위임, agy·Antigravity에 맡기기, /delegate를 요청하거나, 명세가 구체적인 구현 단계를 진행할 때 사용.
argument-hint: "<명세 문서 경로 또는 작업 설명> [--model <agy 모델>] [--browser]"
---

# agy 위임

Claude는 **지시문 작성 → 결과 요약 검토 → 최종 확인**만 하고, 코드 작성·시험 통과·화면 확인은 agy가 끝까지 처리한다. 원칙: Claude 맥락에 긴 출력(diff 전체, 빌드 로그, 화면 내용)을 넣지 않는다.

## 0. 시작 전 확인

- 명세가 구체적인지 확인: 변경 위치·규칙·완료 조건이 문서에 있어야 함. 모호하면 위임하지 말고 사용자와 먼저 정한다.
- `git status --short`로 작업 트리 확인. 커밋 안 된 변경이 있으면 위임 전 사용자에게 알린다(agy 변경과 섞임).
- `agy -p "/usage"`로 남은 양 기록. Gemini 주간 20% 미만이면 사용자에게 알린다. 크레딧(유료) 사용 설정은 켜지 않는다.
- Claude 맥락이 이미 크면(긴 대화 이어 옴) `/handoff` → `/clear` 후 새 세션에서 위임하도록 제안한다.

## 1. 모델 선택

| 작업 | 모델 |
|---|---|
| 위치·규칙이 명세에 다 적힌 수정, 화면 작업 | `gemini-3.8-flash-medium` |
| 여러 파일을 일관되게 고치는 구현, 계산·권한 로직 | `gemini-3.8-flash-high` (기본) |
| 설계 판단이 섞인 구현, 재위임(1차 결과 품질 부족) | `gemini-4-argon-medium` |
| 브라우저 확인 | `gemini-3.8-flash-medium` |

Claude·GPT 계열 agy 모델은 쓰지 않는다(Claude 몫과 겹침). 인자 `--model`이 있으면 그대로 쓴다. 고른 모델과 이유를 한 줄로 알린다.

## 2. 지시문 작성

[prompt-template.md](prompt-template.md)를 채워 Claude 세션 scratchpad에 `agy_<작업>_prompt.txt`로 저장한다.

- 명세 문서는 **경로와 절 번호만** 적고 내용을 복사하지 않는다(agy가 직접 읽음).
- 금지 사항(커밋·push·DB·`.env`·기존 시험 의미 변경)과 완료 조건(시험 통과 명령)을 반드시 넣는다.
- 마지막 보고는 템플릿의 `=== REPORT ===` 형식으로만 출력하게 한다.

## 3. 실행

반드시 [run-agy.sh](run-agy.sh)로 실행한다(`agy`를 직접 부르지 않음, `--dangerously-skip-permissions` 금지). 래퍼가 처리하는 것:

- `--settings`는 전역 권한을 **덮어쓰므로** 전역 deny, 기본 deny(git 상태 변경·DB·ssh·rm -rf), 저장소 `.env` 읽기 차단을 매번 합쳐 넘긴다.
- 읽기 전용 명령(ls, cat, grep, git status/diff/log 등)은 기본 허용한다. 비대화 모드에서는 allow 목록 밖 명령을 하나라도 쓰면 **보고 없이 종료**되기 때문이다.

추가 허용은 프로젝트의 시험·빌드 명령만 인자로 넘긴다. 규칙은 **접두어 일치**다(`command(mvn test)`는 `mvn test -q`도 허용). `*`를 붙이면 일치하지 않는다.

| 프로젝트 | 추가 allow 예 |
|---|---|
| Maven | `command(mvn test)`, `command(mvn -q test)`, `command(mvn clean test)`, `command(mvn compile)` |
| Gradle | `command(./gradlew test)`, `command(./gradlew assemble)`, `command(./gradlew lint)` |
| npm | `command(npm test)`, `command(npm run build)`, `command(npm run lint)`, `command(npx eslint)` |

```sh
S=<scratchpad>; ~/.claude/skills/delegate/run-agy.sh <저장소> <모델> $S/agy_<작업>_prompt.txt $S/agy_<작업>.log \
  'command(mvn test)' 'command(mvn -q test)'
```

- 로그 끝에 `AGY_DENIED`가 있으면 목록 밖 명령으로 멈춘 것이다. 해당 CLI 로그에서 명령을 확인해 안전하면 allow에 추가해 다시 실행하고, 위험하면 지시문에서 그 작업을 빼거나 Claude가 처리한다.
- Bash `run_in_background: true`로 실행한다. **완료 알림이 올 때까지 로그를 tail하거나 git status로 진행을 확인하지 않는다.**
- 사용자에게는 모델, 범위, 로그 경로를 3줄 이내로 알린다.

## 4. 결과 검토 (Claude 토큰 최소화)

1. 보고만 읽는다: `sed -n '/=== REPORT ===/,$p' $S/agy_<작업>.log | head -80`. 보고가 없으면 `tail -c 2000`만 본다.
2. `git status --short`, `git diff --stat`.
3. 위험 파일만 골라 해당 파일 diff를 본다: 권한·보안·결제, DB 마이그레이션, 설정, 삭제된 코드, 보고에 "불확실"로 적힌 곳. 전체 diff는 보지 않는다.
4. 확인 시험 1회: 결과는 요약만 본다(예: `mvn -q test 2>&1 | grep -E 'Tests run:|FAIL|ERROR' | tail -20`, `npm run build 2>&1 | tail -15`).
5. 금지 사항 위반 확인: 커밋 생성 여부(`git log -1`), 기존 시험 단언 변경 여부(`git diff --stat -- '*Test*' '*.test.*'`).

## 5. 수정

- 몇 줄 고치면 되는 문제 → Claude가 직접 고친다.
- 여러 곳이 틀렸거나 시험 실패가 남음 → 지적 사항만 적은 짧은 지시문으로 재위임(같은 모델 1회, 그다음 `gemini-4-argon-medium` 1회). 두 번 넘게 실패하면 멈추고 사용자에게 보고한다.

## 6. 브라우저 확인 (`--browser` 또는 사용자가 화면 확인 요청 시)

Claude 브라우저 도구 대신 agy(chrome-devtools 플러그인)에 맡긴다. 확인할 URL·계정·시나리오·기대 결과를 지시문에 적고, 결과는 시나리오별 `통과/실패 + 한 줄 근거`로만 보고하게 한다. 실패 항목만 Claude가 직접 다시 본다.

## 7. 마무리

- `agy -p "/usage"`로 사용량 변화를 기록한다.
- 사용자에게 보고: 바뀐 것(기능 단위), 검토하며 고친 것, 시험 결과, 남은 위험, 사용량 변화. 커밋은 사용자가 요청할 때 `/commit`으로 한다.
- 다음 단계가 이어지면 `/handoff` → `/clear` 후 새 세션에서 진행하도록 제안한다.
