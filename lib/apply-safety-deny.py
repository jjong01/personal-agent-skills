#!/usr/bin/env python3
# 공통 차단 목록(safety-deny.txt)을 Orca 작업자(agy·Grok)의 전역 설정에 반영함
# 사용:
#   apply-safety-deny.py agy-json                             agy 전역 settings에 병합할 JSON을 stdout으로 출력함
#   apply-safety-deny.py agy-shared <config.json> [--dry-run] agy 공용 config의 globalPermissionGrants.deny에 없는 항목만 추가함
#   apply-safety-deny.py grok <config.toml> [--dry-run]       Grok [permission] deny에 없는 항목만 추가함
import json, os, re, shutil, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ENV_REGEX = r"command(regex:.*\.env(\s|$|\.(?!example|template|sample)).*)"
SKIP_DIRS = {".git", "node_modules"}

def prefixes():
    with open(os.path.join(HERE, "safety-deny.txt"), encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")]

def env_files():
    base = os.path.join(os.path.expanduser("~"), "dev")
    out = []
    if not os.path.isdir(base):
        return out
    for root, dirs, files in os.walk(base):
        depth = os.path.relpath(root, base).count(os.sep) + (0 if root == base else 1)
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if depth >= 3:
            dirs[:] = []
        for f in files:
            if (f == ".env" or f.startswith(".env.")) and not f.endswith((".example", ".template", ".sample")):
                out.append(os.path.join(root, f))
    return sorted(out)

def agy_deny_list():
    return [f"command({c})" for c in prefixes()] + [ENV_REGEX] + [f"read_file({p})" for p in env_files()]

def agy_json():
    print(json.dumps({"permissions": {"deny": agy_deny_list()}}, ensure_ascii=False, indent=2))
    return 0

def agy_shared(path, dry):
    want = agy_deny_list()
    exists = os.path.exists(path)
    if exists:
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
        data = json.loads(text) if text else {}
    else:
        data = {}
    us = data.get("userSettings")
    if not isinstance(us, dict):
        us = {}
        data["userSettings"] = us
    grants = us.get("globalPermissionGrants")
    if not isinstance(grants, dict):
        grants = {}
        us["globalPermissionGrants"] = grants
    deny = grants.get("deny")
    if not isinstance(deny, list):
        deny = []
        grants["deny"] = deny
    seen = set(deny)
    missing = []
    for w in want:
        if w not in seen:
            seen.add(w)
            missing.append(w)
    prefix = "[dry-run] " if dry else ""
    if dry or (exists and not missing):
        print(f"{prefix}agy 공용 config deny 추가 {len(missing)}건")
        return 0
    deny.extend(missing)
    if exists:
        bak = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(path, bak)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print(f"agy 공용 config deny 추가 {len(missing)}건")
    return 0

def grok(path, dry):
    try:
        import tomllib
    except ImportError:
        print("확인 필요: python 3.11+ 필요(tomllib 없음). Grok deny 병합 건너뜀"); return 0
    want = [f"Bash({c}*)" for c in prefixes()] + ["Read(**/.env)", "Read(**/.env.*)"]
    text = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
    cur = tomllib.loads(text) if text.strip() else {}
    have = cur.get("permission", {}).get("deny", []) if isinstance(cur.get("permission"), dict) else []
    missing = [w for w in want if w not in have]
    if not missing:
        print(f"ok      {path} [permission] deny (변경 없음)"); return 0
    items = "".join(f"  {json.dumps(m, ensure_ascii=False)},\n" for m in missing)
    lines = text.split("\n")
    hdr = next((i for i, l in enumerate(lines) if re.match(r"^\[permission\]\s*(#.*)?$", l)), None)
    if hdr is None:
        sep = "" if not text.strip() else ("\n" if text.endswith("\n") else "\n\n")
        new = text + sep + ("\n" if text.strip() else "") + "[permission]\ndeny = [\n" + items + "]\n"
    else:
        end = next((i for i in range(hdr + 1, len(lines)) if re.match(r"^\[", lines[i])), len(lines))
        key = next((i for i in range(hdr + 1, end) if re.match(r"^\s*deny\s*=\s*\[", lines[i])), None)
        if key is None:
            lines[hdr + 1:hdr + 1] = ["deny = ["] + items.rstrip("\n").split("\n") + ["]"]
        else:
            m = re.match(r"^(\s*deny\s*=\s*\[)(.*)$", lines[key])
            lines[key] = m.group(1) + "\n" + items.rstrip("\n") + ("\n" + m.group(2) if m.group(2).strip() else "")
            if not m.group(2).strip():
                lines[key] = lines[key].rstrip("\n")
        new = "\n".join(lines)
    chk = tomllib.loads(new)  # 결과 검증(실패 시 예외로 중단, 파일 미변경)
    got = chk["permission"]["deny"]
    assert all(w in got for w in want) and all(h in got for h in have)
    for m in missing:
        print(("[dry-run] " if dry else "") + f"추가    {path} permission.deny[] {m}")
    if dry:
        return 0
    if os.path.exists(path):
        home = os.path.expanduser("~")
        bdst = os.path.join(home, ".agent-skills-backup", time.strftime("%Y%m%d-%H%M%S"), os.path.relpath(os.path.abspath(path), home))
        os.makedirs(os.path.dirname(bdst), exist_ok=True)
        shutil.copy2(path, bdst); print(f"backup  {path} -> {bdst}")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8", newline="\n") as f:
        f.write(new)
    os.replace(path + ".tmp", path)
    print(f"merged  {path}")
    return 0

if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if x != "--dry-run"]
    dry = "--dry-run" in sys.argv
    if a[:1] == ["agy-json"]:
        sys.exit(agy_json())
    if a[:1] == ["agy-shared"] and len(a) == 2:
        sys.exit(agy_shared(a[1], dry))
    if a[:1] == ["grok"] and len(a) == 2:
        sys.exit(grok(a[1], dry))
    print("usage: apply-safety-deny.py agy-json | agy-shared <config.json> [--dry-run] | grok <config.toml> [--dry-run]", file=sys.stderr); sys.exit(2)
