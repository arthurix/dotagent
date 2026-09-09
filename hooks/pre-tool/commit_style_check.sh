#!/bin/bash
# PreToolUse(Bash) hook: enforce the commit message style on git commit.
# The checks live here, their texts live in commit_style_check_instructions.json.
# Mechanical violations are denied so the message gets rewritten; when the
# message cannot be extracted the style is injected as context instead.
cmd=$(jq -r '.tool_input.command // ""')
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac
[ "$(sqlite3 "${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0

conf="$(cd "$(dirname "$0")" && pwd)/commit_style_check_instructions.json"
[ -f "$conf" ] || exit 0

deny() {
  jq -cn --arg r "$(jq -r ".deny_$1 // \"commit style violation\"" "$conf")" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

case "$cmd" in
  *"Generated with"*|*🤖*|*"Co-Authored-By: Claude"*|*"Co-authored-by: Claude"*) deny ai_trailer ;;
esac

msg=$(printf '%s\n' "$cmd" | sed -n "s/.*-[a-zA-Z]*m '\([^']*\)'.*/\1/p" | head -1)
[ -z "$msg" ] && msg=$(printf '%s\n' "$cmd" | sed -n 's/.*-[a-zA-Z]*m "\([^"]*\)".*/\1/p' | head -1)

if [ -n "$msg" ]; then
  [ ${#msg} -gt 72 ] && deny summary_too_long
  case "$msg" in
    *.) deny trailing_period ;;
  esac
  exit 0
fi

style=$(jq -r '.style // ""' "$conf")
[ -n "$style" ] || exit 0
jq -cn --arg s "$style" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $s}}'
exit 0
