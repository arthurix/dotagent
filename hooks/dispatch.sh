#!/bin/bash
# runs every executable in <event>/ next to this script in lexical order,
# run-parts style. the exec bit is the on switch, jsons and disabled scripts
# are skipped. first deny or block wins, context outputs concatenate, exit 2
# stderr is forwarded so a check hook can feed findings back to the model.
event="${1:-}"
[ -n "$event" ] || exit 0
# the caller's native event name, used in the json answer, defaults to canonical
native="${2:-$event}"
dir="$(cd "$(dirname "$0")" && pwd)/$event"
[ -d "$dir" ] || exit 0

payload="$(cat)"
context=""
feedback=""

for h in "$dir"/*; do
  [ -f "$h" ] || continue
  # a md file is standing instructions, injected as context, README.md excluded
  case "$h" in
    */README.md) continue ;;
    *.md)
      context="${context}$(cat "$h")
"
      continue
      ;;
  esac
  [ -x "$h" ] || continue
  errf="$(mktemp)"
  out="$(printf '%s' "$payload" | "$h" 2>"$errf")"
  rc=$?
  err="$(cat "$errf")"; rm -f "$errf"
  if [ "$rc" -eq 2 ]; then
    feedback="${feedback}${err}
"
    continue
  fi
  [ -n "$out" ] || continue
  if printf '%s' "$out" | jq -e '(.hookSpecificOutput.permissionDecision? == "deny") or (.decision? == "block")' >/dev/null 2>&1; then
    printf '%s\n' "$out"
    exit 0
  fi
  piece="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  [ -n "$piece" ] || piece="$out"
  context="${context}${piece}
"
done

if [ -n "$context" ]; then
  case "$event" in
    prompt-submit|session-start) printf '%s' "$context" ;;
    *) jq -cn --arg e "$native" --arg s "$context" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $s}}' ;;
  esac
fi

if [ -n "$feedback" ]; then
  printf '%s' "$feedback" >&2
  exit 2
fi
exit 0
