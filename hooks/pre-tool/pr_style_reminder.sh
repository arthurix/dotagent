#!/bin/bash
# PreToolUse(Bash) hook: fires when a command creates a PR or PATCHes a PR body,
# injects the style from pr_style_reminder_instructions.json so it is in context at write time
cmd=$(jq -r '.tool_input.command // ""')
case "$cmd" in
  *"gh pr create"*|*pulls*PATCH*|*PATCH*pulls*) ;;
  *) exit 0 ;;
esac
[ "$(sqlite3 "${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0

conf="$(cd "$(dirname "$0")" && pwd)/pr_style_reminder_instructions.json"
[ -f "$conf" ] || exit 0

style=$(jq -r '.style // ""' "$conf")
[ -n "$style" ] || exit 0
jq -cn --arg s "$style" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $s}}'
exit 0
