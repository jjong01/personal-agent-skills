#!/usr/bin/env bash
# 시험·빌드 명령 실행 래퍼: 전체 출력은 로그 파일로, 화면에는 종료 코드와 요약만 출력함
# - 서브에이전트(stage-runner)에서 context-mode 훅이 mvn·mvnw·gradle·gradlew·sbt 직접 실행을 막으므로
#   이 래퍼로 감싸 실행함(훅은 첫 명령 이름만 검사함)
# 사용: run-logged.sh <로그 파일> <명령> [인자...]
#   예: run-logged.sh $S/test.log mvn -q -f backend/pom.xml test
#       run-logged.sh $S/test.log bash -c 'cd backend && ./gradlew test'
# 환경 변수 RUN_SUMMARY_PATTERN: 요약 추출 정규식(grep -E), RUN_SUMMARY_LINES: 요약 줄 수(기본 25)
set -uo pipefail

[[ $# -lt 2 ]] && { echo "usage: $0 <log-file> <command> [args...]" >&2; exit 2; }
LOG="$1"; shift
mkdir -p "$(dirname "$LOG")"

"$@" > "$LOG" 2>&1
code=$?

PAT="${RUN_SUMMARY_PATTERN:-Tests run:|Tests:|tests? (passed|failed)|FAIL|ERROR|BUILD (SUCCESS|FAILURE|FAILED)|COMPILATION ERROR|error:|Error:|[0-9]+ (passing|failing|passed|failed)}"
N="${RUN_SUMMARY_LINES:-25}"
echo "EXIT $code  LOG $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"
summary="$(grep -E -- "$PAT" "$LOG" | tail -n "$N")"
if [[ -n "$summary" ]]; then
  printf '%s\n' "$summary"
else
  tail -n 15 "$LOG"
fi
exit $code
