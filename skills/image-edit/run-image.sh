#!/usr/bin/env bash
# agy generate_image로 이미지 내용을 편집하고 결과를 원본 규격으로 맞춰 저장함
# - agy는 결과를 ~/.gemini/antigravity-cli/brain/<대화ID>/ 에 JPEG로만 저장하므로 실행 후 찾아서 옮김
# - 기본으로 원본 크기에 맞춰 가운데 기준 잘라 맞춤(cover), 출력 확장자 형식으로 변환
# 사용: run-image.sh <참고 이미지> <지시 파일> <출력 경로> [모델] [--keep-size]
#   지시 파일: 바꿀 내용만 적음(예: 글자 'A'를 'B'로, 나머지 유지)
# 출력: 마지막 줄에 IMAGE_RESULT {json} (결과 경로, 크기, 미리보기 경로, 후보 수)
set -uo pipefail

[[ $# -lt 3 ]] && { echo "usage: $0 <ref-image> <instruction-file> <out-path> [model] [--keep-size]" >&2; exit 2; }
REF="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; INSTR="$2"; OUT="$3"; shift 3
MODEL="gemini-3.8-flash-medium"; KEEP=0
for a in "$@"; do
  case "$a" in --keep-size) KEEP=1 ;; *) MODEL="$a" ;; esac
done
[[ -f "$REF" ]] || { echo "참고 이미지 없음: $REF" >&2; exit 2; }
[[ -e "$OUT" && "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" == "$REF" ]] && { echo "출력 경로가 원본과 같음. 원본은 덮어쓰지 않음" >&2; exit 2; }

PY="$(command -v python3 || command -v python || true)"
[[ -z "$PY" ]] && { echo "python3(PIL)이 필요함" >&2; exit 2; }
"$PY" -c "import PIL" 2>/dev/null || { echo "PIL 필요: pip install pillow" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
MARK="$WORK/start"; touch "$MARK"; sleep 1
SIZE="$("$PY" -c "from PIL import Image;import sys;w,h=Image.open(sys.argv[1]).size;print(f'{w}x{h}')" "$REF")"

cat > "$WORK/prompt.txt" <<EOF
반드시 generate_image 도구로 편집해. 코드(python·swift 등)로 그리거나 셸 명령을 실행하지 마. 파일을 옮기거나 복사하지도 마.
참고 이미지: $REF (크기 $SIZE)
편집 지시:
$(cat "$INSTR")
지시에 없는 부분(배경·색·글꼴 느낌·구도·다른 글자)은 그대로 유지하고, 가로세로 비율은 참고 이미지와 같게.
생성이 끝나면 다른 작업 없이 '완료'라고만 출력.
EOF

LOG="$WORK/agy.log"
"$(dirname "$0")/../delegate/run-agy.sh" "$(dirname "$REF")" "$MODEL" "$WORK/prompt.txt" "$LOG" >/dev/null 2>&1
grep -q 'AGY_DENIED' "$LOG" && echo "참고: agy가 허용 밖 명령을 시도해 중간에 멈춤(생성 결과가 있으면 계속 진행)" >&2

"$PY" -I - "$MARK" "$REF" "$OUT" "$KEEP" <<'EOF'
import json, os, sys, glob
from PIL import Image
mark, ref, out, keep = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
t0 = os.path.getmtime(mark)
brain = os.path.expanduser("~/.gemini/antigravity-cli/brain")
cands = [f for ext in ("png", "jpg", "jpeg", "webp")
         for f in glob.glob(f"{brain}/**/*.{ext}", recursive=True)
         if ".system_generated" not in f and os.path.getmtime(f) > t0]
if not cands:
    print("IMAGE_RESULT " + json.dumps({"ok": False, "reason": "생성된 이미지 없음"}, ensure_ascii=False)); sys.exit(1)
src = max(cands, key=os.path.getmtime)
im = Image.open(src).convert("RGB")
rw, rh = Image.open(ref).size
if not keep:
    # 원본 비율로 가운데 잘라낸 뒤 원본 크기로 조정
    w, h = im.size; tr = rw / rh
    if w / h > tr:
        nw = int(h * tr); im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(w / tr); im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    im = im.resize((rw, rh), Image.LANCZOS)
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
ext = os.path.splitext(out)[1].lower()
if ext in (".jpg", ".jpeg"): im.save(out, "JPEG", quality=92)
elif ext == ".webp": im.save(out, "WEBP", quality=90)
else: im.save(out)
# 미리보기는 프로젝트 폴더에 섞이지 않도록 임시 폴더에 둠
pv = os.path.join(os.environ.get("TMPDIR", "/tmp"), "image-edit-preview-" + os.path.splitext(os.path.basename(out))[0] + ".jpg")
p = im.copy(); p.thumbnail((500, 500)); p.save(pv, "JPEG", quality=80)
print("IMAGE_RESULT " + json.dumps({"ok": True, "out": os.path.abspath(out), "size": f"{im.size[0]}x{im.size[1]}",
      "ref_size": f"{rw}x{rh}", "generated": src, "candidates": len(cands), "preview": pv}, ensure_ascii=False))
EOF
