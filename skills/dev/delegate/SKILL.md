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
- [prompt-template.md](prompt-template.md)의 "준비도 점검용"으로 지시문을 만들고 `AGY_MODE=plan`으로 실행한다(모델은 `agy-pick.sh 점검` 출력, 4단계 실행 방식과 동일).
- Claude는 결과 목록만 읽고 항목별로 분류한다.
  - 코드·기존 결정(메모리·문서)으로 답할 수 있는 것 → Claude가 정한다.
  - 정책·업무 판단이 필요한 것 → 사용자에게 묻는다.
- 정한 내용은 **계획 문서에 반영한 뒤** 위임한다(지시문에만 적지 않음).
- "준비 완료"가 나오거나 남은 항목이 사소해질 때까지 반복하되 최대 2회.
- 결정이 필요했던 항목 수를 2단계 난이도 판정에 쓴다.

## 2. 모델 선택

인자 `--model`이 있으면 그대로 쓴다(이름은 `agy models`로 확인). 없으면 아래 순서로 정한다.

1. **난이도 판정**
   - 하: 위치·내용이 명세에 다 적힘, 변경 파일 3개 이하, 화면 문구·스타일 위주
   - 중: 여러 파일 일관 수정, 계산·권한·상태 전이 로직, 시험 추가
   - 상: 1단계에서 결정 항목이 3개 이상 나왔던 명세, 설계 판단 포함, 재위임
2. **모델 선택**: `~/agent/lib/agy-pick.sh 구현-<하|중|상>`(준비도 점검은 `점검`, 브라우저 확인은 `브라우저`)을 실행해 출력 1줄 `<모델>\t<근거>`의 모델을 그대로 쓴다. 용도→모델 매핑은 `~/agent/lib/agy-models.tsv`의 용도 열이 유일한 기준이며 이 문서에는 적지 않는다. 다르게 고르면(사용자 지시 포함) 보고에 사유를 적는다.
   - 스크립트가 묶음별(Gemini 공용·Argon·Claude·GPT) 남은 한도를 `~/.cache/agy-quota.tsv`로 확인한다. 5% 미만이면 소진으로 보고 대체 순서(tsv의 `대체-1`→`대체-2`→`대체-3`: Gemini 공용 → Argon → agy의 Claude·GPT 묶음)에서 소진되지 않은 묶음의 모델을 고른다. Claude·GPT 묶음은 Antigravity 구독 한도라 Claude Code 사용량과 별개이며, Gemini 묶음이 모두 소진됐을 때만 쓰인다.
   - 근거에 `부족`(남은 20% 미만)이 있으면 선택 전에 사용자에게 알린다. Gemini 공용 5시간이 부족하면 하·중 작업을 Argon으로 넘길지, 초기화 시각까지 기다릴지 묻는다. Gemini 공용 주간이 부족하면 난이도 상만 위임한다. Argon이 부족하면 난이도 상을 구현-중 모델로 낮출지 묻는다.
   - 근거가 `한도 미확인`이면(캐시 없음·30분 초과·Argon 행 없음) `agy -p "/usage"`로 직접 확인한다.
   - 출력이 `QUOTA`(종료 코드 3, **모든 묶음 소진**) → 위임하지 않고 멈춘다. 초기화 시각을 알리고 "초기화까지 대기 / Claude가 직접 구현" 중 사용자 선택을 받는다(직접 구현은 사용자 승인 시에만).
   - `조건부후보` 모델(Orchestrator)은 tsv 메모의 조건(독립 조각으로 나뉘는 작업)에 맞고 확인 사항이 끝난 경우에만 쓴다.
3. 고른 모델·난이도·근거(스크립트 출력)를 한 줄로 알린다.
4. **매핑 변경**은 tsv 한 줄(용도 열) 수정으로 한다. `~/agent/notes/agy-model-log.md`(8단계)에 같은 용도의 통과 기록이 3건 이상 쌓인 모델이 있으면 교체를 사용자에게 제안한다. 같은 모델·난이도에서 재작업이 2회 이상 쌓이면 한 단계 높은 용도(구현-하→구현-중→구현-상)로 올리자고 제안한다.

## 3. 지시문 작성

[prompt-template.md](prompt-template.md)를 채워 Claude 세션 scratchpad에 `agy_<작업>_prompt.txt`로 저장한다.

- 명세 문서는 **경로와 절 번호만** 적고 내용을 복사하지 않는다(agy가 직접 읽음).
- 금지 사항(커밋·push·DB·`.env`·기존 시험 의미 변경)과 완료 조건(시험 통과 명령)을 반드시 넣는다.
- 마지막 보고는 템플릿의 `=== REPORT ===` 형식으로만 출력하게 한다.

## 4. 실행

반드시 [run-agy.sh](../../../lib/run-agy.sh)(설치 후 `~/agent/lib/run-agy.sh`)로 실행한다(`agy`를 직접 부르지 않음, `--dangerously-skip-permissions` 금지). 래퍼가 처리하는 것:

- `--settings`는 전역 권한을 **덮어쓰므로** 전역 deny, 기본 deny(git 상태 변경·DB·ssh·rm -rf), 저장소 `.env` 읽기 차단을 매번 합쳐 넘긴다.
- 읽기 전용 명령(ls, cat, grep, sort, diff, git status/diff/log/grep/ls-files/branch 등)은 기본 허용한다. 비대화 모드에서는 allow 목록 밖 명령을 하나라도 쓰면 **보고 없이 종료**되기 때문이다.

추가 허용은 프로젝트의 시험·빌드 명령만 인자로 넘긴다. 규칙은 **공백 단위 접두어 일치**다: `command(mvn test)`는 `mvn test -q`는 허용하지만 `mvn test-compile`·`mvn -q test`·`mvn -f backend/pom.xml test`는 허용하지 않는다. 옵션 위치·하위 목표별로 따로 넣고, 지시문의 시험 명령도 넣은 형태 그대로 적는다. `*`를 붙이면 일치하지 않는다.

| 프로젝트 | 추가 allow 예 |
|---|---|
| Maven | `compile`·`test-compile`·`test`를 함께 넣는다. 예: `command(mvn compile)`, `command(mvn test-compile)`, `command(mvn test)`, `command(mvn -q compile)`, `command(mvn -q test-compile)`, `command(mvn -q test)`. pom이 하위 폴더면 `command(mvn -f backend/pom.xml compile)`, `command(mvn -f backend/pom.xml test-compile)`, `command(mvn -f backend/pom.xml test)`, `command(mvn -q -f backend/pom.xml test)`. `./mvnw`도 같은 방식 |
| Gradle | `command(./gradlew test)`, `command(./gradlew compileJava)`, `command(./gradlew compileTestJava)`, `command(./gradlew assemble)`, `command(./gradlew lint)` |
| npm | `command(npm test)`, `command(npm run build)`, `command(npm run lint)`, `command(npx eslint)` |

```sh
S=<scratchpad>; ~/agent/lib/run-agy.sh <저장소> <모델> $S/agy_<작업>_prompt.txt $S/agy_<작업>.log \
  'command(mvn compile)' 'command(mvn test-compile)' 'command(mvn test)' 'command(mvn -q test)'
```

- 로그 끝에 `AGY_DENIED: <명령>`이 있으면 그 명령이 allow 목록 밖이라 거부된 것이다(래퍼가 agy 대화 기록에서 추출, `AGY_DENIED_LOG` 줄에 CLI 로그·대화 id). 보고가 없으면 그 지점에서 멈춘 것이다. 명령이 안전하면 그 형태 그대로 allow에 추가해 다시 실행하고, 위험하면 지시문에서 그 작업을 빼거나 Claude가 처리한다. `(명령 확인 불가)`면 `~/.gemini/antigravity-cli/brain/<대화 id>/.system_generated/logs/transcript_full.jsonl` 끝의 `CommandLine`을 본다.
- Bash `run_in_background: true`로 실행한다. **완료 알림이 올 때까지 로그를 tail하거나 git status로 진행을 확인하지 않는다.**
- 사용자에게는 모델, 범위, 로그 경로를 3줄 이내로 알린다.

## 5. 결과 검토 (Claude 토큰 최소화)

1. 보고만 읽는다: `sed -n '/=== REPORT ===/,$p' $S/agy_<작업>.log | head -80`. 보고가 없으면 `tail -c 2000`만 본다.
2. `git status --short`, `git diff --stat`.
3. 위험 파일만 골라 해당 파일 diff를 본다: 권한·보안·결제, DB 마이그레이션, 설정, 삭제된 코드, 보고에 "불확실"로 적힌 곳. 전체 diff는 보지 않는다.
4. 확인 시험 1회: [run-logged.sh](../../../lib/run-logged.sh)로 실행해 종료 코드와 요약만 본다(전체 출력은 로그 파일). 예: `~/agent/lib/run-logged.sh $S/test.log mvn -q test`, `~/agent/lib/run-logged.sh $S/build.log npm run build`. 서브에이전트(stage-runner)에서는 context-mode 훅이 `mvn`·`mvnw`·`gradle`·`gradlew`·`sbt` 직접 실행을 막으므로(파일로 돌려도 막힘) 반드시 이 래퍼를 쓴다. 셸 구문이 필요하면 `run-logged.sh <로그> bash -c 'cd backend && mvn -q test'`.
5. 금지 사항 위반 확인: 커밋 생성 여부(`git log -1`), 기존 시험 단언 변경 여부(`git diff --stat -- '*Test*' '*.test.*'`).
6. 로그에 `AGY_NEW_MODELS: <id...>`가 있으면 사용자에게 한 줄로 알리고 평가 여부를 묻는다(모델은 자동으로 바꾸지 않음). 절차는 아래 "새 모델 평가 절차".

## 6. 수정

- 몇 줄 고치면 되는 문제 → Claude가 직접 고친다.
- 여러 곳이 틀렸거나 시험 실패가 남음 → 지적 사항만 적은 짧은 지시문으로 재위임(같은 모델 1회, 그다음 한 단계 높은 용도의 모델 1회: 구현-하 → 구현-중 → 구현-상, 각 모델은 `agy-pick.sh`로 고름). 두 번 넘게 실패하면 멈추고 사용자에게 보고한다.
- 실행 중 한도가 소진돼 멈춘 경우(로그 끝 `AGY_USAGE`에 5% 미만 묶음) → 바뀐 파일은 그대로 두고, `agy-pick.sh`가 고른 다음 묶음(대체 순서) 모델로 "이미 바뀐 파일을 이어서 완성"하는 지시문을 다시 위임한다.

## 7. 브라우저 확인 (`--browser` 또는 사용자 명시 요청 시만. 기본은 사용자 직접 확인용 항목표 제공)

Claude 브라우저 도구 대신 agy의 chrome-devtools MCP에 맡긴다.
- 준비(기기당 1회): `agy mcp list`에 `chrome-devtools`가 없으면 사용자 확인 후 `agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.10.1`. chrome-devtools 플러그인만으로는 브라우저 조작 도구가 없음.
- 실행: `AGY_BROWSER=1`을 붙여 `run-agy.sh`를 실행한다(필요한 MCP 도구만 허용, 형식 `mcp(<서버>/<도구>)`). 페이지 열기는 `execute_url(<주소 접두어>)` 권한이 따로 필요하며 기본은 `http://localhost`·`http://127.0.0.1`·`about:blank`만 허용한다. 다른 주소(개발 서버 도메인 등)는 `AGY_BROWSER_URLS="<접두어> ..."`로 지정한다. `mcp(*)`·서버 전체 허용은 쓰지 않는다. agy가 `~/.gemini/config/mcp_config.json`을 읽으려다 거부되면 허용하지 말고 지시문에 "MCP 설정 파일은 읽지 말 것"을 넣어 재실행한다.
- MCP 브라우저는 별도 프로필로 열려 로그인 상태가 없다고 가정한다. 로그인 계정은 프로젝트 `AGENTS.md`의 로컬 시험 계정을 지시문에 적고, 없으면 사용자에게 받는다(`.env`에서 찾지 않음). 확인할 URL·계정·시나리오·기대 결과를 지시문에 적고, 결과는 시나리오별 `통과/실패 + 한 줄 근거`로만 보고하게 한다. 실패 항목만 Claude가 직접 다시 본다.

## 8. 마무리

- `agy -p "/usage"`로 사용량 변화를 확인한다.
- `~/agent/notes/agy-model-log.md`에 한 줄 추가한다(없으면 머리글 포함 생성):
  `| 날짜 | 프로젝트 | 작업 | 난이도 | 모델 | 결과(통과/Claude 수정/재위임 n회/실패) | 사용량 변화 |`
- 사용자에게 보고: 바뀐 것(기능 단위), 검토하며 고친 것, 시험 결과, 남은 위험, 사용량 변화. 커밋은 사용자가 요청할 때 `/commit`으로 한다.
- 다음 단계가 이어지면 `/handoff` → `/clear` 후 새 세션에서 진행하도록 제안한다.

## 새 모델 평가 절차

`lib/agy-models.tsv`(모델별 용도 목록)에 없는 모델이 `agy models`에 생기면 래퍼가 로그에 `AGY_NEW_MODELS`를 남긴다.

1. 사용자가 평가를 승인하면, 같은 소규모 작업(시험이 있는 작은 구현)을 기준 모델과 새 모델로 각각 돌린다. 실행 전후 `agy -p "/usage"`를 기록하고, 실행 사이에 작업 폴더를 원래 상태로 되돌린다.
2. 소요 시간·사용 한도 묶음과 감소량·시험 통과·시험 파일 변경 여부·보고 형식·결과 품질을 `~/agent/notes/agy-model-log.md`에 기록한다.
3. 사용자가 결과를 보고 채택 여부를 정한다. 승인되면 `lib/agy-models.tsv`의 용도·메모를 고친다(매핑은 용도 열 한 줄 수정). 평가하지 않기로 하면 용도를 `사용안함`으로 적어 알림을 끈다.
