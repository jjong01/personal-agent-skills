#!/usr/bin/env python3
# 저장소 공용 설정을 기기 설정 파일에 병합함
# - 객체는 재귀 병합, 목록은 기존 순서 유지 후 없는 항목만 추가, 단일 값은 저장소 값 우선
# - 쓰기 전 기존 파일을 ~/.agent-skills-backup/<시각>/ 으로 백업함. 대상이 없으면 새로 만듦
# 사용: python -I merge-settings.py <저장소 json> <대상 json> [--dry-run]
import json, os, shutil, sys, time

def merge(base, add, path, log):
    for k, v in add.items():
        p = f"{path}.{k}" if path else k
        if k not in base:
            base[k] = v; log.append(f"추가    {p}")
        elif isinstance(base[k], dict) and isinstance(v, dict):
            merge(base[k], v, p, log)
        elif isinstance(base[k], list) and isinstance(v, list):
            for item in v:
                if item not in base[k]:
                    base[k].append(item); log.append(f"추가    {p}[] {json.dumps(item, ensure_ascii=False)}")
        elif base[k] != v:
            log.append(f"변경    {p}: {json.dumps(base[k], ensure_ascii=False)} -> {json.dumps(v, ensure_ascii=False)}")
            base[k] = v

def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if len(args) != 2:
        print("usage: merge-settings.py <repo-json> <target-json> [--dry-run]", file=sys.stderr); return 2
    src, dst = args
    with open(src, encoding="utf-8") as f:
        add = json.load(f)
    base = {}
    if os.path.exists(dst):
        with open(dst, encoding="utf-8") as f:
            text = f.read().strip()
        base = json.loads(text) if text else {}
    log = []
    merge(base, add, "", log)
    if not log:
        print(f"ok      {dst} (변경 없음)"); return 0
    for line in log:
        print(("[dry-run] " if dry else "") + line)
    if dry:
        return 0
    if os.path.exists(dst):
        home = os.path.expanduser("~")
        rel = os.path.relpath(os.path.abspath(dst), home)
        bdst = os.path.join(home, ".agent-skills-backup", time.strftime("%Y%m%d-%H%M%S"), rel)
        os.makedirs(os.path.dirname(bdst), exist_ok=True)
        shutil.copy2(dst, bdst); print(f"backup  {dst} -> {bdst}")
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    tmp = dst + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(base, f, ensure_ascii=False, indent=2); f.write("\n")
    os.replace(tmp, dst)
    print(f"merged  {dst}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
