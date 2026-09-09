#!/bin/bash
# UserPromptSubmit hook: stamp the turn marker used by memory_save_check, and
# when the prompt reads like a correction inject the save-feedback instruction.
# The correction pattern and the injected text live in feedback_capture_instructions.json.
payload="$(cat)"
root="${CLAUDE_PROJECT_DIR:-.}"
[ "$(sqlite3 "$root/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0
mkdir -p "$root/.agent"
date -u +%Y-%m-%dT%H:%M:%S > "${DOTAGENT_PROMPT_MARKER:-$root/.agent/.last_prompt}"

conf="$(cd "$(dirname "$0")" && pwd)/feedback_capture_instructions.json"
[ -f "$conf" ] || exit 0
pattern="$(jq -r '.pattern // ""' "$conf")"
context="$(jq -r '.context // ""' "$conf")"
{ [ -n "$pattern" ] && [ -n "$context" ]; } || exit 0

prompt="$(printf '%s' "$payload" | jq -r '.prompt // ""')"
printf '%s' "$prompt" | grep -qiE "$pattern" || exit 0
jq -cn --arg c "$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
exit 0
