#!/usr/bin/env bash
# Claude Code 훅: 실행 중인 터미널에 맞춰 상태 표시·효과음·알림 처리
#   iTerm2           → iTerm2 cc-status(탭 상태 표시)에 그대로 전달(모든 이벤트)
#   Ghostty·WezTerm  → 종료·오류·알림 이벤트에 효과음 + OS 알림(macOS: afplay·osascript, Windows: PowerShell)
# 설치 시 ~/.claude/hooks/terminal-status.sh 로 연결함. 기본 등록 이벤트: Stop, StopFailure, Notification

input=$(cat)

case "${TERM_PROGRAM:-}" in
  iTerm.app)
    cc="$HOME/.config/iterm2/cc-status"
    [ -x "$cc" ] && printf '%s' "$input" | "$cc"
    exit 0
    ;;
  ghostty|WezTerm) ;;
  *) exit 0 ;;
esac

field() { printf '%s' "$input" | grep -o "\"$1\" *: *\"[^\"]*\"" | head -1 | sed 's/.*: *"\(.*\)"$/\1/'; }
event=$(field hook_event_name)

case "$event" in
  Stop)         kind=done; msg="작업이 끝났습니다" ;;
  StopFailure)  kind=fail; msg="오류로 작업이 중단됐습니다" ;;
  Notification) kind=info; msg="$(field message)"; [ -z "$msg" ] && msg="확인이 필요합니다" ;;
  *) exit 0 ;;
esac

case "$(uname -s)" in
  Darwin)
    case "$kind" in done) s=Glass ;; fail) s=Basso ;; *) s=Ping ;; esac
    /usr/bin/afplay "/System/Library/Sounds/$s.aiff" >/dev/null 2>&1 &
    # Ghostty는 Notification 문구를 Claude Code가 직접 띄우므로 중복 알림 생략
    if [ "$kind" != info ] || [ "$TERM_PROGRAM" = WezTerm ]; then
      /usr/bin/osascript -e "display notification \"${msg//\"/}\" with title \"Claude Code\"" >/dev/null 2>&1 &
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    case "$kind" in done) s=Asterisk ;; fail) s=Hand ;; *) s=Exclamation ;; esac
    # 문구는 환경 변수로 넘겨 따옴표 처리 문제를 피함. 토스트는 Windows PowerShell 5.1 WinRT API 사용
    CC_MSG="$msg" CC_SOUND="$s" powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command '
      [System.Media.SystemSounds]::$env:CC_SOUND.Play()
      try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        $x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $t = $x.GetElementsByTagName("text")
        $t.Item(0).AppendChild($x.CreateTextNode("Claude Code")) > $null
        $t.Item(1).AppendChild($x.CreateTextNode($env:CC_MSG)) > $null
        $id = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
        [Windows.UI.Notifications.ToastNotificationManager]::CreateNotifier($id).Show([Windows.UI.Notifications.ToastNotification]::new($x))
      } catch {}
      Start-Sleep -Milliseconds 800
    ' >/dev/null 2>&1 &
    ;;
esac
exit 0
