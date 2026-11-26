#!/usr/bin/env bash
# agy 모델 선택: lib/agy-models.tsv의 용도 열 + 한도 캐시로 모델 1개를 고름
# 사용: agy-pick.sh <용도>   예: agy-pick.sh 구현-중
# 출력(1줄): <model>\t<근거: 용도·묶음·남은%>
# 규칙: 묶음 남은 양(5시간·주간 중 작은 값) 5% 미만=소진, 20% 미만=부족 표시.
#       소진이면 대체-1, 대체-2... 순서로 소진되지 않은 묶음의 모델을 고름(순서는 tsv에서 정함).
#       캐시가 없거나 30분 넘게 오래되면 한도 미확인으로 tsv 선택을 그대로 사용함.
#       모든 묶음이 소진되면 "QUOTA\t<묶음별 상태>" 출력 후 종료 코드 3.
# 환경 변수: AGY_QUOTA_FILE(기본 ~/.cache/agy-quota.tsv), AGY_MODELS_FILE(기본 이 스크립트 옆 agy-models.tsv)
# 종료 코드: 0 정상, 2 인자·파일 오류, 3 전체 소진
# 위치: 저장소 lib/, 설치 후 ~/agent/lib/agy-pick.sh 로 호출함
set -uo pipefail

[[ $# -ne 1 ]] && { echo "usage: $0 <용도>" >&2; exit 2; }
USE="$1"
SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MODELS="${AGY_MODELS_FILE:-$SELF_DIR/agy-models.tsv}"
QUOTA="${AGY_QUOTA_FILE:-$HOME/.cache/agy-quota.tsv}"
[[ -f "$MODELS" ]] || { echo "모델 목록 없음: $MODELS" >&2; exit 2; }

# 용도에 해당하는 첫 모델 id와 묶음을 반환(없으면 빈 값)
lookup() {
  # macOS awk는 한글 문자열 ==·split 비교가 부정확해 index()로 바이트 단위 일치를 확인함
  awk -F'\t' -v u="$1" '$1 !~ /^#/ && $1 != "id" && index("," $2 ",", "," u ",") { print $1 "\t" $3; exit }' "$MODELS"
}

# 캐시 최종 수정 후 경과 초(macOS: stat -f, Linux/Git Bash: stat -c)
cache_age() {
  local m
  m="$(stat -f %m "$QUOTA" 2>/dev/null || stat -c %Y "$QUOTA" 2>/dev/null)" || return 1
  echo $(( $(date +%s) - m ))
}

# 묶음별 남은 %(5시간·주간 중 최소)와 초기화 시각을 "남은%\t초기화ISO"로 출력. 행이 없으면 빈 값
bundle_left() {
  awk -F'\t' -v b="$1" '
    { name = tolower($1)
      if (b=="gemini" && name !~ /gemini models/) next
      if (b=="argon" && name !~ /argon/) next
      if (b=="claude-gpt" && name !~ /claude/) next
      v = $3; sub(/%.*/, "", v); v = int(v + 0)  # 소수 %는 버림(bash 정수 비교용)
      if (!found || v < min) { min = v; reset = $4 }
      found = 1 }
    END { if (found) print min "\t" reset }' "$QUOTA"
}

PRIMARY="$(lookup "$USE")"
[[ -z "$PRIMARY" ]] && { echo "용도 없음: $USE (agy-models.tsv의 용도 열 확인)" >&2; exit 2; }

AGE=""; CACHE_OK=0
if [[ -f "$QUOTA" ]] && AGE="$(cache_age)" && (( AGE <= 1800 )); then CACHE_OK=1; fi

if (( ! CACHE_OK )); then
  printf '%s\t%s\n' "${PRIMARY%%$'\t'*}" "${USE}·${PRIMARY#*$'\t'}·한도 미확인(캐시 없음 또는 30분 초과)"
  exit 0
fi

# 후보 순서: 용도 모델 → 대체-1 → 대체-2 → ... (tsv에 있는 대체-N 전부)
CANDS="$PRIMARY"
# 구현-상은 Argon 부족·소진 시 대체 순서 전에 구현-중 모델로 한 단계 내려감
STEPDOWN=""
[[ "$USE" == "구현-상" ]] && STEPDOWN="$(lookup "구현-중")"
[[ -n "$STEPDOWN" ]] && CANDS="$CANDS"$'\n'"$STEPDOWN"
for n in 1 2 3 4 5 6 7 8 9; do
  c="$(lookup "대체-$n")"
  [[ -n "$c" ]] && CANDS="$CANDS"$'\n'"$c"
done

STATUS=""; FIRST=1; TRIED=" "
while IFS=$'\t' read -r id bundle; do
  [[ -z "$id" ]] && continue
  case "$TRIED" in *" $bundle "*) continue ;; esac
  TRIED="$TRIED$bundle "
  info="$(bundle_left "$bundle")"
  if [[ -z "$info" ]]; then
    left="미확인"; state="unknown"
  else
    left="${info%%$'\t'*}"; reset="${info#*$'\t'}"
    if (( left < 5 )); then state="exhausted"
    elif (( left < 20 )); then state="low"
    else state="ok"; fi
  fi
  # 구현-상 1순위 묶음이 부족(20% 미만)이면 구현-중으로 내려감
  if (( FIRST )) && [[ -n "$STEPDOWN" && "$state" == "low" ]]; then
    STATUS="$STATUS$bundle ${left}% 부족 "; FIRST=0; continue
  fi
  if [[ "$state" == "exhausted" ]]; then
    STATUS="$STATUS$bundle ${left}%(초기화 $reset) "; FIRST=0
    continue
  fi
  if [[ "$state" == "unknown" ]]; then note="$bundle 한도 미확인"
  elif [[ "$state" == "low" ]]; then note="$bundle 남은 ${left}% 부족"
  else note="$bundle 남은 ${left}%"; fi
  if (( FIRST )); then
    printf '%s\t%s\n' "$id" "${USE}·$note"
  else
    printf '%s\t%s\n' "$id" "${USE}·${STATUS}소진→대체·$note"
  fi
  exit 0
done <<< "$CANDS"

printf 'QUOTA\t%s\n' "$STATUS"
exit 3
