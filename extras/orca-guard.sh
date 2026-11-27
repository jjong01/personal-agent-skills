#!/usr/bin/env bash
# Claude Code PreToolUse 훅: Orca 세션에서 stage-runner·agy/grok 직접 실행 차단함
# - Orca 세션 판정: ORCA_TERMINAL_HANDLE 또는 ORCA_CLI_COMMAND가 비어 있지 않음(아니면 통과)
# - Agent 판정: subagent_type="stage-runner" 차단함
# - Bash 판정: heredoc 본문·따옴표 내용·주석 제거 후 명령 위치(접두어 제외)의 agy/grok -p|--print|--prompt와 남은 토큰의 run-agy.sh·run-logged.sh 차단함(bash/sh/zsh -c·eval은 깊이 3까지 재귀 검사함)
# - 차단 시 PreToolUse deny JSON 출력 후 exit 0 반환하며, 파싱 예외 시 통과함

[[ -n "${ORCA_TERMINAL_HANDLE:-}" || -n "${ORCA_CLI_COMMAND:-}" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

exec python3 -I -c '
import json, re, sys

REASON = (
    "Orca 세션: stage-runner·agy/grok 직접 실행 대신 /orchestration 스킬로 "
    "worker-start 사용(구현은 --agent antigravity, 의견 요청은 antigravity·grok "
    "읽기 전용 작업자 병렬 시작)"
)

VAR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
BLOCKED_SCRIPTS = ("run-agy.sh", "run-logged.sh")
BLOCKED_BINS = ("agy", "grok")
SHELL_BINS = ("bash", "sh", "zsh")
KEYWORDS = ("!", "{", "if", "then", "elif", "else", "do", "while", "until")
SQ = "\x27"
ANSI_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", SQ: SQ, "\"": "\""}


def read_heredoc_delim(text, i):
    n = len(text)
    while i < n and text[i] in " \t":
        i += 1
    parts = []
    while i < n:
        ch = text[i]
        if ch in " \t\r\n;|&()<>":
            break
        if ch == SQ:
            i += 1
            end = text.find(SQ, i)
            if end == -1:
                parts.append(text[i:])
                i = n
            else:
                parts.append(text[i:end])
                i = end + 1
        elif ch == "\"":
            i += 1
            while i < n and text[i] != "\"":
                if text[i] == "\\" and i + 1 < n:
                    nxt = text[i + 1]
                    i += 2
                    parts.append(nxt if nxt in "\"\\$`" else "\\" + nxt)
                else:
                    parts.append(text[i])
                    i += 1
            if i < n:
                i += 1
        elif ch == "\\" and i + 1 < n:
            parts.append(text[i + 1])
            i += 2
        else:
            parts.append(ch)
            i += 1
    return "".join(parts), i


def consume_heredocs(text, i, pending):
    n = len(text)
    for delim, strip_tabs in pending:
        while i < n:
            nl = text.find("\n", i)
            if nl == -1:
                line = text[i:]
                i = n
            else:
                line = text[i:nl]
                i = nl + 1
            cmp_line = line[:-1] if line.endswith("\r") else line
            if strip_tabs:
                cmp_line = cmp_line.lstrip("\t")
            if cmp_line == delim:
                break
    pending.clear()
    return i


def tokenize(text):
    tokens = []
    pending_heredocs = []
    i = 0
    n = len(text)

    while i < n:
        ch = text[i]

        if ch in " \t\r":
            i += 1
            continue

        if ch == "\\" and i + 1 < n and text[i + 1] == "\n":
            i += 2
            continue

        if ch == "\n":
            tokens.append(("OP", "\n"))
            i += 1
            if pending_heredocs:
                i = consume_heredocs(text, i, pending_heredocs)
            continue

        if ch == "#":
            nl = text.find("\n", i)
            i = n if nl == -1 else nl
            continue

        if text[i:i + 2] == "$(" and text[i:i + 3] != "$((":
            tokens.append(("OP", "$("))
            i += 2
            continue

        if text[i:i + 2] in ("<(", ">("):
            tokens.append(("OP", "$("))
            i += 2
            continue

        if text[i:i + 3] == "&>>":
            tokens.append(("REDIR", "&>>"))
            i += 3
            continue

        if text[i:i + 2] == "&>":
            tokens.append(("REDIR", "&>"))
            i += 2
            continue

        # fd 번호가 바로 붙은 리다이렉션 처리함(예: 2>&1, 2>/dev/null)
        j = i
        while j < n and text[j].isdigit():
            j += 1
        if j < n and text[j] in "<>" and text[j:j + 2] not in ("<(", ">("):
            i = j
            if text[i:i + 3] == "<<<":
                tokens.append(("REDIR", "<<<"))
                i += 3
                continue
            if text[i:i + 2] == "<<":
                strip_tabs = text[i:i + 3] == "<<-"
                op = "<<-" if strip_tabs else "<<"
                i += 3 if strip_tabs else 2
                delim, i = read_heredoc_delim(text, i)
                if delim:
                    pending_heredocs.append((delim, strip_tabs))
                tokens.append(("REDIR", op))
                continue
            if text[i:i + 2] in (">>", ">&", "<&", "<>", ">|"):
                tokens.append(("REDIR", text[i:i + 2]))
                i += 2
                continue
            tokens.append(("REDIR", text[i]))
            i += 1
            continue

        if text[i:i + 3] == ";;&":
            tokens.append(("OP", ";;&"))
            i += 3
            continue

        if text[i:i + 2] in (";;", ";&", "&&", "||", "|&"):
            tokens.append(("OP", text[i:i + 2]))
            i += 2
            continue

        if ch in ";&|()`":
            tokens.append(("OP", ch))
            i += 1
            continue

        # 일반 단어 토큰 파싱함(따옴표 내용은 cleaned에서 제거하고 raw에만 보관함)
        cleaned = []
        raw = []
        while i < n:
            ch = text[i]
            if ch in " \t\r\n;|&()<>`":
                break
            if ch == "$" and i + 1 < n and text[i + 1] == "(":
                if text[i:i + 3] == "$((":
                    start = i
                    i += 3
                    depth = 2
                    while i < n and depth > 0:
                        if text[i] == "(":
                            depth += 1
                        elif text[i] == ")":
                            depth -= 1
                        i += 1
                    seg = text[start:i]
                    cleaned.append(seg)
                    raw.append(seg)
                    continue
                break
            if ch == "$" and i + 1 < n and text[i + 1] == SQ:
                i += 2
                while i < n and text[i] != SQ:
                    if text[i] == "\\" and i + 1 < n:
                        esc = text[i + 1]
                        i += 2
                        raw.append(ANSI_ESC.get(esc, "\\" + esc))
                    else:
                        raw.append(text[i])
                        i += 1
                if i < n:
                    i += 1
                continue
            if ch == SQ:
                i += 1
                end = text.find(SQ, i)
                if end == -1:
                    raw.append(text[i:])
                    i = n
                else:
                    raw.append(text[i:end])
                    i = end + 1
                continue
            if ch == "\"" or (ch == "$" and i + 1 < n and text[i + 1] == "\""):
                i += 2 if ch == "$" else 1
                while i < n and text[i] != "\"":
                    if text[i] == "\\" and i + 1 < n:
                        nxt = text[i + 1]
                        i += 2
                        if nxt == "\n":
                            continue
                        raw.append(nxt if nxt in "\"\\$`" else "\\" + nxt)
                    else:
                        raw.append(text[i])
                        i += 1
                if i < n:
                    i += 1
                continue
            if ch == "\\":
                if i + 1 < n:
                    nxt = text[i + 1]
                    i += 2
                    if nxt == "\n":
                        continue
                    cleaned.append(nxt)
                    raw.append(nxt)
                else:
                    cleaned.append(ch)
                    raw.append(ch)
                    i += 1
                continue
            cleaned.append(ch)
            raw.append(ch)
            i += 1

        tokens.append(("WORD", "".join(cleaned), "".join(raw)))

    return tokens


def extract_commands(tokens):
    commands = []
    # 각 프레임: [단어 목록, 다음 단어 리다이렉션 대상 스킵 여부, 연 기호]
    stack = [[[], False, None]]

    def flush_top():
        if stack[-1][0]:
            commands.append(stack[-1][0])
            stack[-1][0] = []
        stack[-1][1] = False

    for tok in tokens:
        kind = tok[0]
        if kind == "WORD":
            if stack[-1][1]:
                stack[-1][1] = False
            else:
                stack[-1][0].append((tok[1], tok[2]))
        elif kind == "REDIR":
            if tok[1] not in ("<<", "<<-"):
                stack[-1][1] = True
        elif kind == "OP":
            op = tok[1]
            if op in ("$(", "("):
                stack[-1][1] = False
                stack.append([[], False, op])
            elif op == ")":
                flush_top()
                if len(stack) > 1 and stack[-1][2] in ("(", "$("):
                    stack.pop()
                else:
                    flush_top()
            elif op == "`":
                if len(stack) > 1 and stack[-1][2] == "`":
                    flush_top()
                    stack.pop()
                else:
                    stack[-1][1] = False
                    stack.append([[], False, "`"])
            else:
                flush_top()

    while stack:
        flush_top()
        stack.pop()

    return commands


def skip_prefixes(cmd):
    i = 0
    n = len(cmd)
    while i < n:
        tok = cmd[i][0]
        base = tok.rsplit("/", 1)[-1]
        if tok in KEYWORDS or VAR_RE.match(tok):
            i += 1
            continue
        if base == "env":
            i += 1
            while i < n:
                t = cmd[i][0]
                if t == "--":
                    i += 1
                    break
                if t in ("-u", "-C", "-S", "--unset", "--chdir", "--split-string"):
                    i += 2
                    continue
                if t == "-" or (t.startswith("-") and len(t) > 1):
                    i += 1
                    continue
                if VAR_RE.match(t):
                    i += 1
                    continue
                break
            continue
        if base == "nohup":
            i += 1
            if i < n and cmd[i][0] == "--":
                i += 1
            continue
        if base == "timeout":
            i += 1
            while i < n:
                t = cmd[i][0]
                if t == "--":
                    i += 1
                    break
                if t in ("-k", "-s", "--kill-after", "--signal"):
                    i += 2
                    continue
                if t.startswith("-") and len(t) > 1:
                    i += 1
                    continue
                break
            if i < n:
                i += 1
            continue
        if tok == "command":
            i += 1
            inspect_only = False
            while i < n:
                t = cmd[i][0]
                if t == "--":
                    i += 1
                    break
                if t.startswith("-") and len(t) > 1 and not t.startswith("--"):
                    if "v" in t[1:] or "V" in t[1:]:
                        inspect_only = True
                    i += 1
                    continue
                break
            if inspect_only:
                return n
            continue
        if tok == "exec":
            i += 1
            while i < n:
                t = cmd[i][0]
                if t == "--":
                    i += 1
                    break
                if t == "-a":
                    i += 2
                    continue
                if t.startswith("-") and len(t) > 1 and not t.startswith("--"):
                    i += 1
                    continue
                break
            continue
        if base == "time":
            i += 1
            while i < n:
                t = cmd[i][0]
                if t == "--":
                    i += 1
                    break
                if t in ("-f", "-o", "--format", "--output"):
                    i += 2
                    continue
                if t.startswith("-") and len(t) > 1:
                    i += 1
                    continue
                break
            continue
        break
    return i


def extract_shell_c(args):
    i = 0
    has_c = False
    n = len(args)
    while i < n:
        c, r = args[i]
        if c == "--":
            i += 1
            if has_c and i < n:
                return args[i][1]
            return None
        if c in ("-o", "+o", "--rcfile", "--init-file"):
            i += 2
            continue
        if c.startswith("--"):
            i += 1
            continue
        if len(c) >= 2 and c[0] in ("-", "+") and c[1] != "-":
            if c[0] == "-" and "c" in c[1:]:
                has_c = True
            if c.endswith("o"):
                i += 2
                continue
            i += 1
            continue
        if has_c:
            return r
        return None
    return None


def is_blocked_bash(text, depth=0):
    tokens = tokenize(text)

    # 정리 후 남은 토큰에 차단 대상 스크립트명이 있으면 차단함
    for tok in tokens:
        if tok[0] == "WORD":
            base = tok[1].rsplit("/", 1)[-1]
            if base in BLOCKED_SCRIPTS:
                return True

    for cmd in extract_commands(tokens):
        idx = skip_prefixes(cmd)
        if idx >= len(cmd):
            continue
        exe_cleaned = cmd[idx][0]
        exe_base = exe_cleaned.rsplit("/", 1)[-1]
        args = cmd[idx + 1:]

        if exe_base in BLOCKED_BINS:
            for arg_cleaned, _ in args:
                if arg_cleaned in ("-p", "--print", "--prompt") or arg_cleaned.startswith("--prompt="):
                    return True
        elif depth < 3 and exe_base in SHELL_BINS:
            sub = extract_shell_c(args)
            if sub and is_blocked_bash(sub, depth + 1):
                return True
        elif depth < 3 and exe_cleaned == "eval":
            eval_args = args[1:] if args and args[0][0] == "--" else args
            if eval_args:
                sub = " ".join(r for _, r in eval_args)
                if sub and is_blocked_bash(sub, depth + 1):
                    return True

    return False


try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        sys.exit(0)

    tool = data.get("tool_name")
    inp = data.get("tool_input")
    if not isinstance(inp, dict):
        sys.exit(0)

    deny = False
    if tool == "Agent" and inp.get("subagent_type") == "stage-runner":
        deny = True
    elif tool == "Bash":
        cmd = inp.get("command")
        if isinstance(cmd, str) and is_blocked_bash(cmd):
            deny = True

    if deny:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": REASON,
            }
        }, ensure_ascii=False, separators=(",", ":")))
except Exception:
    sys.exit(0)
'
