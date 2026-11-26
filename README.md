# personal-agent-skills

Claude Code와 Antigravity(agy)에서 함께 쓰는 개인 에이전트 공통 규칙과 스킬 모음.

전체 구조·새 PC 설정·기기별 준비 사항은 [사용 가이드](docs/GUIDE.md) 참고.

- `global/AGENTS.md`: 두 도구 공통 전역 규칙
- `settings/`: 기기 설정에 병합하는 공용 설정(`claude.json`: 자동 요약 160k·권한·context-mode, `agy.json`: `.env` 차단)
- `skills/<분류>/<이름>/`: 사용자 스킬. 분류는 저장소 정리용이며 설치 시 도구별 `skills/<이름>`으로 평평하게 연결함(이름 중복 금지)
- `extras/terminal-status.sh`: 작업 종료·오류·알림 시 효과음과 OS 알림(iTerm2·Ghostty·WezTerm, macOS·Windows). 설치 시 `~/.claude/hooks/`로 연결
- `extras/statusline.sh`: 상태줄(Claude 구독·맥락·agy 할당량 사용률). 설치 시 `~/.claude/statusline.sh`로 연결, jq 필요
- `extras/scheduled-ping/`: 평일 정시 `claude`·`agy` 호출로 사용량 구간 시작 시각을 맞추는 launchd 스크립트·plist 템플릿(macOS 전용, Windows 미지원). `./install.sh --with-ping`로 선택 설치, 절차는 가이드 13절
- `lib/`: 스킬 공용 스크립트(`run-agy.sh`: agy 비대화 실행 래퍼, `agy-denied.py`: 권한 거부 명령 추출, `run-logged.sh`: 시험·빌드 출력을 파일로 보내고 요약만 출력, `agy-models.tsv`: 모델 용도 기준, `agy-pick.sh`: 용도·한도 기준 모델 선택). 설치 후 `~/agent/lib`

| 분류 | 스킬 | 설명 |
|---|---|---|
| common | [`handoff`](skills/common/handoff/SKILL.md) | 진행 상황을 인계 메모로 저장하고 새 대화에서 이어서 작업 |
| dev | [`commit`](skills/dev/commit/SKILL.md) | 변경 내용을 분석해 저장소 형식에 맞는 커밋 메시지 생성 후 확인을 거쳐 커밋 (git·SVN) |
| dev | [`delegate`](skills/dev/delegate/SKILL.md) | 구현·시험·브라우저 확인을 agy에 맡기고 결과 요약만 검토 (Claude Code 전용) |
| general | [`offload`](skills/general/offload/SKILL.md) | 조사·요약·비교·번역·정리안을 agy에 읽기 전용으로 맡기고 결과 파일 요약만 검토 (Claude Code 전용) |
| general | [`image-edit`](skills/general/image-edit/SKILL.md) | 이미지 파일 작업은 직접, 내용 편집은 agy 이미지 생성으로 처리 후 원본 규격 맞춤·백업·교체 (Claude Code 전용, Python PIL 필요) |

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
- 스킬 폴더는 정션으로 연결함. agy 위임 스킬(delegate·offload·image-edit)은 Git Bash와 Python이 필요함.
- Git Bash에서 `install.sh`를 실행하면 링크 대신 복사본이 생길 수 있으므로 Windows에서는 `install.ps1`을 사용함.

새 PC에서도 한 번 실행하면 아래 구성이 만들어짐. 다시 실행해도 안전하며, 기존 파일·폴더는 `~/.agent-skills-backup/<시각>/`으로 옮긴 뒤 링크함.

```
~/dev/                          코드 프로젝트
~/agent/system|storage|notes/   프로젝트 외 작업 (notes/handoff: 인계 메모)
~/agent/AGENTS.md               → 저장소 global/AGENTS.md
~/.claude/CLAUDE.md             → ~/agent/AGENTS.md
~/.gemini/GEMINI.md             → ~/agent/AGENTS.md
~/agent/lib                     → 저장소 lib/
~/.claude/skills/<이름>          → 저장소 skills/<분류>/<이름>
~/.gemini/config/skills/<이름>   → 저장소 skills/<분류>/<이름> (.claude-only 제외)
```

이어서 `settings/`를 `~/.claude/settings.json`·`~/.gemini/antigravity-cli/settings.json`에 병합함(기존 값 유지, 목록은 없는 항목만 추가, 쓰기 전 백업). 필요한 도구(claude, agy, node, lsd, bat, rg, fd, zoxide, delta)가 없으면 설치 명령을 안내하고, 마지막 "점검"에서 깨진 링크·agy 로그인·python·PIL·context-mode 플러그인을 확인함. 플러그인은 Claude Code에서 `/plugin install context-mode@context-mode`로 설치함.

## 스킬 추가·수정

1. `skills/<분류>/<이름>/SKILL.md` 작성(분류: common·dev·general) (frontmatter에 `name`, `description` 필수)
2. 새 스킬이거나 폴더를 옮겼으면 `./install.sh` 실행(대상이 사라진 옛 링크는 자동 정리)
3. 커밋·푸시. 다른 기기에서는 `git pull` 후 `./install.sh`

링크 방식이라 저장소 파일 수정이 두 도구에 바로 반영됨. 새 대화부터 적용됨.

## 확인

- Claude Code: 새 세션에서 `/commit`, `/handoff` 자동완성 확인
- agy: `agy -p "/commit --message-only" --settings '{"permissions":{"allow":["command(git status)","command(git diff)","command(git log)"]}}'`
