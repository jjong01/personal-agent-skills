---
name: commit
description: 커밋 대기 중인 변경을 분석해 저장소 형식에 맞는 커밋 메시지를 만들고, 확인 후 커밋한다(git·SVN 지원). 사용자가 커밋, 커밋 메시지 작성, /commit을 요청할 때 사용.
argument-hint: "[--message-only] [추가 지시]"
---

# 커밋

변경 내용을 분석해 커밋 메시지를 만들고, 사용자 확인 후 커밋한다. 인자에 `--message-only`가 있으면 메시지만 출력하고 커밋하지 않는다.

## 1. 저장소 종류 확인

- `git rev-parse --is-inside-work-tree`와 `svn info` 결과로 판단한다.
- git·SVN이 함께 있으면 어느 쪽에 커밋할지 사용자에게 묻는다. 프로젝트 `CLAUDE.md`에 지정돼 있으면 그대로 따른다.

## 2. 변경 내용 수집

- git: `git status --short`, `git diff --staged`. 스테이징된 변경이 없으면 변경 파일 목록을 보여 주고 무엇을 포함할지 묻는다. 관련 없는 파일을 임의로 `git add`하지 않는다.
- SVN: `svn status`, `svn diff`. 커밋할 경로를 명시해 관련 없는 변경이 섞이지 않게 한다.
- `.env`, 키·비밀번호가 든 파일, 빌드 결과물(`dist/`, `target/`, `build/`)이 포함되면 커밋 전에 알린다.

## 3. 형식 결정

최근 커밋 약 20개의 제목(git `git log -20 --format=%s`, SVN `svn log -l 20`)을 확인한다.

- 프로젝트 `CLAUDE.md`·`CONTRIBUTING.md`에 커밋 규칙이 있으면 그것을 우선한다.
- 절반 이상이 `type(scope): ...` 또는 `type: ...` 형태 → **Conventional Commits**.
- 그 외 이력이 5개 이상 → **기존 이력 형식**을 따른다(언어, 말투, 길이, PR 번호 표기 등).
- 이력이 없거나 5개 미만인 새 저장소 → **기본 형식**:

```
<type>(<scope>): <한국어 요약, 명사형 종결>

- <파일 또는 영역>: <변경 내용>
- <파일 또는 영역>: <변경 내용>
```

type: `feat` 기능, `fix` 버그, `refactor` 구조 개선, `docs` 문서, `style` 화면 스타일·포맷, `test` 테스트, `chore` 설정·빌드·의존성, `perf` 성능. scope는 생략할 수 있으며 한국어도 허용한다.

## 4. 작성 규칙

- 제목은 무엇을 왜 바꿨는지 한 줄로 쓰고, 파일 나열은 본문에 둔다. 변경이 한두 줄로 자명하면 본문을 생략한다.
- 이슈 번호가 보이면(브랜치명 등) 푸터에 `Closes #번호`를 단다.
- **AI 사용 흔적을 남기지 않는다**: `Co-Authored-By` 트레일러, "Generated with ..." 문구, Claude·Antigravity·Gemini·AI 언급을 메시지·브랜치명·PR 설명 어디에도 넣지 않는다.

## 5. 확인 후 커밋

1. 메시지를 코드 블록으로 보여 주고 포함 파일 목록과 함께 커밋 여부를 묻는다.
2. 승인되면 커밋한다. 여러 줄 메시지는 HEREDOC로 넘긴다.
   - git: `git commit -F - <<'EOF' ... EOF`
   - SVN: `svn commit <경로...> -F <임시 파일>` (서버에 바로 반영되므로 반드시 사전 승인)
3. `git push`는 사용자가 따로 요청할 때만 한다.
4. 커밋 후 `git log -1 --format=%B`(SVN은 `svn log -l 1`)로 메시지에 AI 관련 문구가 없는지 확인한다.
