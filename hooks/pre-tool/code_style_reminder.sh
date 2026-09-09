#!/bin/bash
# pre-tool hook: inject the writing style for the file type being touched, so
# the voice is in context at write time. Styles are data in
# code_style_reminder_instructions.json, an ordered list of {globs, style},
# first matching glob wins, an empty style skips the file on purpose.
file=$(jq -r '.tool_input.file_path // ""')
[ -n "$file" ] || exit 0
[ "$(sqlite3 "${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0

conf="$(cd "$(dirname "$0")" && pwd)/code_style_reminder_instructions.json"
[ -f "$conf" ] || exit 0

# one glob<US>style line per glob, US is a byte that never appears in prose
while IFS= read -r line; do
  glob="${line%%$'\x1f'*}"
  style="${line#*$'\x1f'}"
  case "$file" in
    $glob)
      [ -n "$style" ] && jq -cn --arg s "$style" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $s}}'
      exit 0
      ;;
  esac
done < <(jq -r '.[] | .style as $s | .globs[] | . + "\u001f" + $s' "$conf")
exit 0
