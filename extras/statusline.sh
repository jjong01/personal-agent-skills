#!/bin/bash
# Claude Code 상태줄: Claude 구독 사용률 + 맥락 사용률 + Antigravity 할당량 + Grok 사용량
# 필요: jq. agy가 없으면 AG 부분은 생략함. grok이 없으면 Grok 부분은 생략함
# AG 할당량은 agy 실행이 느려(약 6초) 캐시 파일을 읽고, 5분 경과 시 백그라운드 갱신함
# Grok 사용량은 캐시 파일을 읽고, 5분 경과 시 백그라운드에서 grok usage --json 갱신함

input=$(cat)
# macOS(BSD)와 Linux·Git Bash(GNU) 명령 차이 처리
mtime() { if [ "$(uname)" = Darwin ]; then stat -f %m "$1" 2>/dev/null; else stat -c %Y "$1" 2>/dev/null; fi || echo 0; }
hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null; }
AG_CACHE="$HOME/.cache/agy-quota.tsv"
AG_LOCK="$HOME/.cache/agy-quota.lock"
AG_TTL=300
GROK_CACHE="$HOME/.cache/grok-usage.json"
GROK_CHECKED="$HOME/.cache/grok-usage.checked"
GROK_LOCK="$HOME/.cache/grok-usage.lock"
GROK_TTL=300

c_reset=$'\e[0m'; c_dim=$'\e[2m'
color() {  # 사용률(%)에 따른 색상: 50 미만 초록, 80 미만 노랑, 이상 빨강
  local p=${1%.*}
  if [ -z "$p" ]; then printf ''; elif [ "$p" -ge 80 ]; then printf $'\e[31m'; elif [ "$p" -ge 50 ]; then printf $'\e[33m'; else printf $'\e[32m'; fi
}
pct() { [ -n "$1" ] && printf "%s%.0f%%%s" "$(color "$1")" "$1" "$c_reset"; }

j() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
h5=$(j '.rate_limits.five_hour.used_percentage')
h5_reset=$(j '.rate_limits.five_hour.resets_at')
d7=$(j '.rate_limits.seven_day.used_percentage')
ctx=$(j '.context_window.used_percentage')

out="Claude"
if [ -n "$h5" ]; then
  out+=" 5h $(pct "$h5")"
  [ -n "$h5_reset" ] && out+="${c_dim}($(hhmm "${h5_reset%.*}"))${c_reset}"
fi
[ -n "$d7" ] && out+=" 주 $(pct "$d7")"
[ -n "$ctx" ] && out+=" · 맥락 $(pct "$ctx")"

# AG 캐시 갱신: 오래됐고 갱신 중이 아니면 백그라운드 실행 (잠금은 2분 지나면 무효 처리)
mkdir -p "$HOME/.cache"
age=$(( $(date +%s) - $(mtime "$AG_CACHE") ))
if [ "$age" -ge "$AG_TTL" ] && command -v agy >/dev/null; then
  [ -d "$AG_LOCK" ] && [ $(( $(date +%s) - $(mtime "$AG_LOCK") )) -ge 120 ] && rmdir "$AG_LOCK" 2>/dev/null
  if mkdir "$AG_LOCK" 2>/dev/null; then
    ( cd "$HOME/agent" 2>/dev/null || cd "$HOME"
      agy -p "/quota" > "$AG_CACHE.tmp" 2>/dev/null && grep -q 'Remaining' "$AG_CACHE.tmp" && mv "$AG_CACHE.tmp" "$AG_CACHE"
      rm -f "$AG_CACHE.tmp"; rmdir "$AG_LOCK" ) >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null
  fi
fi

# AG는 남은 비율로 보고하므로 사용률(100-남은)로 변환해 Claude와 표기를 맞춤
if [ -f "$AG_CACHE" ]; then
  ag_used() { awk -F'\t' -v g="$1" -v k="$2" '$1==g && $2==k {gsub("%","",$3); print 100-$3; exit}' "$AG_CACHE"; }
  ag_group() {  # $1=그룹명 $2=표시 라벨
    local u5 u7; u5=$(ag_used "$1" "Five Hour Limit Remaining"); u7=$(ag_used "$1" "Weekly Limit Remaining")
    [ -n "$u5$u7" ] && printf ' %s 5h %s 주 %s' "$2" "$(pct "$u5")" "$(pct "$u7")"
  }
  stale=""; [ "$age" -ge $((AG_TTL * 3)) ] && stale="${c_dim}*${c_reset}"
  ag="$(ag_group "Gemini Models" "Gemini")$(ag_group "Claude and GPT models" "· Claude/GPT")"
  [ -n "$ag" ] && out+=" │ AG${ag}${stale}"
fi

# Grok 사용량 갱신 및 표시: grok 미설치 시 전체 생략함
GROK_BIN=$(command -v grok 2>/dev/null)
[ -z "$GROK_BIN" ] && [ -x "$HOME/.grok/bin/grok" ] && GROK_BIN="$HOME/.grok/bin/grok"
if [ -n "$GROK_BIN" ]; then
  now=$(date +%s)
  grok_cache_mtime=$(mtime "$GROK_CACHE")
  grok_checked_mtime=$(mtime "$GROK_CHECKED")
  grok_last_mtime=$grok_cache_mtime
  [ "$grok_checked_mtime" -gt "$grok_last_mtime" ] && grok_last_mtime=$grok_checked_mtime
  grok_age=$(( now - grok_last_mtime ))
  grok_cache_age=$(( now - grok_cache_mtime ))
  if [ "$grok_age" -ge "$GROK_TTL" ]; then
    [ -d "$GROK_LOCK" ] && [ $(( now - $(mtime "$GROK_LOCK") )) -ge 120 ] && rmdir "$GROK_LOCK" 2>/dev/null
    if mkdir "$GROK_LOCK" 2>/dev/null; then
      ( "$GROK_BIN" usage --json > "$GROK_CACHE.tmp" 2>/dev/null \
        && [ -s "$GROK_CACHE.tmp" ] \
        && jq -e . "$GROK_CACHE.tmp" >/dev/null 2>&1 \
        && mv "$GROK_CACHE.tmp" "$GROK_CACHE" \
        || touch "$GROK_CHECKED"
        rm -f "$GROK_CACHE.tmp"; rmdir "$GROK_LOCK" ) >/dev/null 2>&1 </dev/null &
      disown 2>/dev/null
    fi
  fi
  grok_pct=""
  if [ -f "$GROK_CACHE" ]; then
    grok_pct=$(jq -r '
      ([first(
        paths(type == "number") as $p
        | select(($p[-1] | type) == "string")
        | ($p[-1] | ascii_downcase) as $k
        | select($k | contains("percent"))
        | getpath($p) as $v
        | if ($k | contains("remain") or contains("left")) then (100 - $v) else $v end
      )] | .[0])
      // ([first(
        .. | objects
        | (.used // empty) as $u
        | (.limit // .total // empty) as $l
        | select(($u | type) == "number" and ($l | type) == "number" and $l > 0)
        | ($u / $l * 100)
      )] | .[0])
      // empty
    ' "$GROK_CACHE" 2>/dev/null)
  fi
  if [ -n "$grok_pct" ]; then
    grok_pct=$(printf '%.2f' "$grok_pct" 2>/dev/null)
    stale=""; [ "$grok_cache_age" -ge $((GROK_TTL * 3)) ] && stale="${c_dim}*${c_reset}"
    out+=" │ Grok 주 $(pct "$grok_pct")${stale}"
  else
    out+="${c_dim} │ Grok -${c_reset}"
  fi
fi

printf '%s' "$out"
