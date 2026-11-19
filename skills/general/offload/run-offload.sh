#!/usr/bin/env bash
# 일반 작업(조사·요약·번역·비교·정리안)을 agy에 읽기 전용으로 맡기고 결과를 파일로 저장함
# - agy는 plan 모드로 실행해 파일을 만들거나 고치지 못함. 결과는 출력에서 잘라 내 저장함
# 사용: run-offload.sh <작업 폴더> <지시 파일> <결과 파일> [모델]
#   환경 변수 OFFLOAD_DIRS: 함께 읽을 폴더(':' 구분)
# 출력: 요약 몇 줄과 마지막 줄 OFFLOAD_RESULT {json}
set -uo pipefail

[[ $# -lt 3 ]] && { echo "usage: $0 <workdir> <instruction-file> <out-file> [model]" >&2; exit 2; }
WORKDIR="$1"; INSTR="$2"; OUT="$3"; MODEL="${4:-gemini-3.8-flash-medium}"
[[ -d "$WORKDIR" ]] || { echo "작업 폴더 없음: $WORKDIR" >&2; exit 2; }
[[ -f "$INSTR" ]] || { echo "지시 파일 없음: $INSTR" >&2; exit 2; }
[[ -e "$OUT" ]] && { echo "결과 파일이 이미 있음(덮어쓰지 않음): $OUT" >&2; exit 2; }
command -v agy >/dev/null 2>&1 || { echo "OFFLOAD_RESULT {\"ok\": false, \"reason\": \"agy 없음\"}"; exit 3; }
PY="$(command -v python3 || command -v python || true)"
[[ -z "$PY" ]] && { echo "python3(또는 python)이 필요함" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/prompt.txt" <<P
읽기 전용 작업이다. 파일을 만들거나 고치거나 옮기거나 지우지 마. 셸 명령은 읽기 명령만 써.
작업 폴더: $WORKDIR${OFFLOAD_DIRS:+ (함께 읽을 폴더: $OFFLOAD_DIRS)}
작업:
$(cat "$INSTR")

규칙:
- 확인한 사실과 추정을 구분해. 읽지 못한 파일·찾지 못한 정보는 그렇다고 적어.
- 파일 이동·이름 변경·삭제가 필요한 작업이면 실행하지 말고 RESULT에 실행할 명령을 sh 코드 블록으로 적어.
- 한국어로, 아래 형식을 반드시 지켜.

=== RESULT ===
(결과 전체, 마크다운)
=== SUMMARY ===
(5줄 이내 요약)
=== SOURCES ===
(읽은 파일 경로·URL 목록)
P

LOG="$WORK/agy.log"
AGY_MODE=plan AGY_REPORT_MARK='=== SUMMARY ===' AGY_ADD_DIRS="${OFFLOAD_DIRS:-}" \
  "$HOME/agent/lib/run-agy.sh" "$WORKDIR" "$MODEL" "$WORK/prompt.txt" "$LOG" >/dev/null 2>&1

"$PY" -I - "$LOG" "$OUT" "$MODEL" <<'PYEOF'
import json, os, re, sys
log, out, model = sys.argv[1:4]
t = open(log, encoding="utf-8", errors="replace").read()
def sec(name, nxt):
    m = re.search(rf"=== {name} ===\n(.*?)(?=\n=== {nxt} ===|\nAGY_|\Z)", t, re.S)
    return m.group(1).strip() if m else ""
res, summ, src = sec("RESULT", "SUMMARY"), sec("SUMMARY", "SOURCES"), sec("SOURCES", "XX")
if not res:
    tail = [l for l in t.splitlines() if l.startswith("AGY_")]
    print("OFFLOAD_RESULT " + json.dumps({"ok": False, "reason": "결과 형식 없음", "agy": tail[-3:]}, ensure_ascii=False))
    sys.exit(1)
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    f.write(res + "\n\n## 출처\n\n" + (src or "(없음)") + "\n")
print(summ)
nm = re.search(r"^AGY_NEW_MODELS: (.*)$", t, re.M)
r = {"ok": True, "out": os.path.abspath(out), "chars": len(res),
     "sources": len([l for l in src.splitlines() if l.strip()]), "model": model}
if nm:
    r["new_models"] = nm.group(1)
print("OFFLOAD_RESULT " + json.dumps(r, ensure_ascii=False))
PYEOF
