"""agy 실행에서 권한 거부된 명령 추출
- CLI 로그(log/cli-*.log)에는 거부 단계 번호만 있으므로 대화 transcript에서 해당 단계 직전 도구 호출을 찾음
- 동시 실행 경합 방지: 시작 시각 이후 생성된 로그 중 작업 폴더·지시문 길이가 맞는 것을 고름
사용: python3 agy-denied.py <시작 epoch> <지시문 파일> <작업 폴더...>
출력: 거부가 있으면 'AGY_DENIED: <명령>' 줄들과 'AGY_DENIED_LOG: ...' 한 줄, 없으면 출력 없음
"""
import glob
import json
import os
import re
import sys
import time

HOME = os.path.join(os.path.expanduser("~"), ".gemini", "antigravity-cli")


def find_log(start, prompt_lens, dirs):
    cands = []
    for p in glob.glob(os.path.join(HOME, "log", "cli-*.log")):
        m = re.search(r"cli-(\d{8}_\d{6})\.log$", p)
        if not m:
            continue
        # 파일명 시각은 초 단위라 2초 여유를 둠
        if time.mktime(time.strptime(m.group(1), "%Y%m%d_%H%M%S")) < start - 2:
            continue
        try:
            txt = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        w = re.search(r"workspaceDirs=\[([^\]]*)\]", txt)
        if not w or not any(d in w.group(1).split() for d in dirs):
            continue
        pl = re.search(r"promptLength=(\d+)", txt)
        prompt_ok = bool(pl) and int(pl.group(1)) in prompt_lens
        cands.append((prompt_ok, "soft-denying" in txt, m.group(1), p, txt))
    return max(cands) if cands else None


def load_steps(cid):
    base = os.path.join(HOME, "brain", cid, ".system_generated", "logs")
    for name in ("transcript_full.jsonl", "transcript.jsonl"):
        path = os.path.join(base, name)
        if os.path.exists(path):
            steps = []
            for line in open(path, encoding="utf-8", errors="replace"):
                try:
                    steps.append(json.loads(line))
                except ValueError:
                    pass
            return steps
    return []


def describe(call):
    args = call.get("args") or {}
    if args.get("CommandLine"):
        return args["CommandLine"]
    brief = {k: v for k, v in args.items() if k not in ("toolSummary", "WaitMsBeforeAsync")}
    return f"{call.get('name', '?')} {json.dumps(brief, ensure_ascii=False)[:200]}"


def denied_commands(steps, step_no):
    # 거부 단계 이전의 마지막 도구 호출이 거부 대상임
    for s in reversed(steps):
        if s.get("step_index", -1) < step_no and s.get("tool_calls"):
            return [describe(c) for c in s["tool_calls"]][-1:]
    return []


def main():
    start, prompt_file, dirs = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
    raw = open(prompt_file, "rb").read()
    prompt_lens = {len(raw), len(raw.decode("utf-8", errors="replace"))}
    found = find_log(start, prompt_lens, dirs)
    if not found or not found[1]:
        return
    path, txt = found[3], found[4]
    cid = re.search(r"Created conversation ([0-9a-f-]{36})", txt)
    cid = cid.group(1) if cid else ""
    steps = load_steps(cid) if cid else []
    seen = []
    for tool, n in re.findall(r'soft-denying tool confirmation "([^"]+)" at step (\d+)', txt):
        cmds = denied_commands(steps, int(n)) or [f"({tool} 단계 {n}, 명령 확인 불가)"]
        for c in cmds:
            if c not in seen:
                seen.append(c)
                print(f"AGY_DENIED: {c}")
    print(f"AGY_DENIED_LOG: {path} (대화 {cid or '확인 불가'})")


if __name__ == "__main__":
    main()
