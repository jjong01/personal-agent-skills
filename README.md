# personal-agent-skills

Claude Code와 Antigravity(agy)에서 함께 쓰는 개인 에이전트 스킬 모음.

| 스킬 | 설명 |
|---|---|
| [`commit`](skills/commit/SKILL.md) | 변경 내용을 분석해 저장소 형식에 맞는 커밋 메시지 생성 후 확인을 거쳐 커밋 (git·SVN) |
| [`handoff`](skills/handoff/SKILL.md) | 진행 상황을 인계 메모로 저장하고 새 대화에서 이어서 작업 |

## 설치

```sh
git clone https://github.com/jjong01/personal-agent-skills.git ~/dev/personal-agent-skills
cd ~/dev/personal-agent-skills
./install.sh            # --dry-run으로 미리 확인 가능
```

`skills/<이름>`을 아래 위치에 심볼릭 링크로 연결함. 같은 이름의 기존 폴더는 `~/.agent-skills-backup/`으로 옮김.

- Claude Code: `~/.claude/skills/<이름>`
- Antigravity: `~/.gemini/config/skills/<이름>`

## 스킬 추가·수정

1. `skills/<이름>/SKILL.md` 작성 (frontmatter에 `name`, `description` 필수)
2. 새 스킬이면 `./install.sh` 실행
3. 커밋·푸시. 다른 기기에서는 `git pull` 후 `./install.sh`

링크 방식이라 저장소 파일 수정이 두 도구에 바로 반영됨. 새 대화부터 적용됨.

## 확인

- Claude Code: 새 세션에서 `/commit`, `/handoff` 자동완성 확인
- agy: `agy -p "/commit --message-only" --settings '{"permissions":{"allow":["command(git status*)","command(git diff*)","command(git log*)"]}}'`
