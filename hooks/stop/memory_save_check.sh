#!/bin/bash
# Stop hook: refuse to end a turn that changed files without saving anything to
# .agent/memory.db. Blocks once, the stop_hook_active guard prevents loops.
payload="$(cat)"
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

root="${CLAUDE_PROJECT_DIR:-.}"
db="$root/.agent/memory.db"
marker="${DOTAGENT_PROMPT_MARKER:-$root/.agent/.last_prompt}"
{ [ -f "$db" ] && [ -f "$marker" ]; } || exit 0
[ "$(sqlite3 "$db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0
# marker strictly newer than the db means nothing was saved this turn,
# a tie counts as saved (-nt has whole-second granularity)
[ "$marker" -nt "$db" ] || exit 0

if [ -n "${DOTAGENT_EDIT_MARKER:-}" ]; then
  [ -f "$DOTAGENT_EDIT_MARKER" ] || exit 0
else
  transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // ""')"
  [ -f "$transcript" ] || exit 0
  since="$(cat "$marker")"
  jq -r --arg t "$since" 'select((.timestamp // "") > $t) | .message.content[]? | select(.type? == "tool_use") | .name' "$transcript" 2>/dev/null \
    | grep -qE '^(Edit|Write|NotebookEdit)$' || exit 0
fi

conf="$(cd "$(dirname "$0")" && pwd)/memory_save_check_instructions.json"
[ -f "$conf" ] || exit 0
reason=$(jq -r '.reason // ""' "$conf")
[ -n "$reason" ] || exit 0
jq -cn --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
