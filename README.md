# personal-agent-skills

Claude Code와 Antigravity(agy)에서 함께 쓰는 개인 에이전트 공통 규칙과 스킬 모음.

- `global/AGENTS.md`: 두 도구 공통 전역 규칙
- `skills/`: 사용자 스킬

| 스킬 | 설명 |
|---|---|
| [`commit`](skills/commit/SKILL.md) | 변경 내용을 분석해 저장소 형식에 맞는 커밋 메시지 생성 후 확인을 거쳐 커밋 (git·SVN) |
| [`handoff`](skills/handoff/SKILL.md) | 진행 상황을 인계 메모로 저장하고 새 대화에서 이어서 작업 |
| [`delegate`](skills/delegate/SKILL.md) | 구현·시험·브라우저 확인을 agy에 맡기고 결과 요약만 검토 (Claude Code 전용) |
| [`image-edit`](skills/image-edit/SKILL.md) | 이미지 파일 작업은 직접, 내용 편집은 agy 이미지 생성으로 처리 후 원본 규격 맞춤·백업·교체 (Claude Code 전용, Python PIL 필요) |

스킬 폴더에 `.claude-only` 파일이 있으면 Claude Code에만 연결함.

## 설치

macOS·Linux:

```sh
git clone https://github.com/jjong01/personal-agent-skills.git ~/dev/personal-agent-skills
cd ~/dev/personal-agent-skills
./install.sh            # --dry-run으로 미리 확인 가능
```

Windows (PowerShell):

```powershell
git clone https://github.com/jjong01/personal-agent-skills.git $HOME\dev\personal-agent-skills
cd $HOME\dev\personal-agent-skills
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun   # 먼저 확인
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

- 파일 심볼릭 링크 때문에 **개발자 모드**(설정 > 시스템 > 개발자용) 또는 관리자 권한이 필요함. 없으면 아무것도 바꾸지 않고 안내 후 종료함.
- 스킬 폴더는 정션으로 연결함. `delegate` 스킬은 Git Bash와 Python이 필요함.
- Git Bash에서 `install.sh`를 실행하면 링크 대신 복사본이 생길 수 있으므로 Windows에서는 `install.ps1`을 사용함.

새 PC에서도 한 번 실행하면 아래 구성이 만들어짐. 다시 실행해도 안전하며, 기존 파일·폴더는 `~/.agent-skills-backup/<시각>/`으로 옮긴 뒤 링크함.

```
~/dev/                          코드 프로젝트
~/agent/system|storage|notes/   프로젝트 외 작업 (notes/handoff: 인계 메모)
~/agent/AGENTS.md               → 저장소 global/AGENTS.md
~/.claude/CLAUDE.md             → ~/agent/AGENTS.md
~/.gemini/GEMINI.md             → ~/agent/AGENTS.md
~/.claude/skills/<이름>          → 저장소 skills/<이름>
~/.gemini/config/skills/<이름>   → 저장소 skills/<이름> (.claude-only 제외)
```

마지막에 필요한 도구(claude, agy, node, lsd, bat, rg, fd, zoxide, delta)가 없으면 설치 명령을 안내함. Claude Code 플러그인(context-mode 등)·권한 설정은 기기별로 따로 설정함.

## 스킬 추가·수정

1. `skills/<이름>/SKILL.md` 작성 (frontmatter에 `name`, `description` 필수)
2. 새 스킬이면 `./install.sh` 실행
3. 커밋·푸시. 다른 기기에서는 `git pull` 후 `./install.sh`

링크 방식이라 저장소 파일 수정이 두 도구에 바로 반영됨. 새 대화부터 적용됨.

## 확인

- Claude Code: 새 세션에서 `/commit`, `/handoff` 자동완성 확인
- agy: `agy -p "/commit --message-only" --settings '{"permissions":{"allow":["command(git status)","command(git diff)","command(git log)"]}}'`
