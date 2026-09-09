#!/usr/bin/env bash
set -euo pipefail

native="${1:?native event required}"
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$hooks_dir/../.." && pwd)"
export CLAUDE_PROJECT_DIR="$root"
payload="$(jq -ce 'select(type == "object")')"
original_payload="$payload"
canonical=""
case "$native" in
  SessionStart) canonical=session-start ;;
  UserPromptSubmit) canonical=prompt-submit ;;
  PreToolUse) canonical=pre-tool ;;
  PostToolUse) canonical=post-tool ;;
  Stop) canonical=stop ;;
  SessionEnd) canonical=session-end ;;
esac

if [ -f "$root/.agent/memory.db" ] && [ "$(sqlite3 "$root/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'")" = off ]; then
  if [ "$native" = SessionStart ]; then
    printf '%s' "$payload" | bash "$hooks_dir/dispatch.sh" session-start "$native"
  fi
  exit 0
fi

session_dir=""
if session_key="$(printf '%s' "$payload" | jq -er '.session_id | select(type == "string" and length > 0) | @uri')"; then
  session_dir="$root/.agent/.codex-turns/session-$session_key"
  if turn_key="$(printf '%s' "$payload" | jq -er '.turn_id | select(type == "string" and length > 0) | @uri')"; then
    turn_dir="$session_dir/turn-$turn_key"
    export DOTAGENT_PROMPT_MARKER="$turn_dir/prompt"
    export DOTAGENT_EDIT_MARKER="$turn_dir/edited"
    case "$native" in
      UserPromptSubmit) mkdir -p "$turn_dir" ;;
      PostToolUse)
        if printf '%s' "$payload" | jq -e '.tool_name == "apply_patch"' >/dev/null; then
          mkdir -p "$turn_dir"
          touch "$DOTAGENT_EDIT_MARKER"
        fi
        ;;
    esac
  fi
fi

outputs='[]'
blocked=false
status=0
collect() {
  local output="$1" response
  [ -n "$output" ] || return 0
  if response="$(printf '%s' "$output" | jq -ce 'select(type == "object")' 2>/dev/null)"; then
    :
  else
    response="$(jq -cn --arg event "$native" --arg context "$output" '{hookSpecificOutput: {hookEventName: $event, additionalContext: $context}}')"
  fi
  outputs="$(printf '%s' "$outputs" | jq -c --argjson response "$response" '. + [$response]')"
  if printf '%s' "$response" | jq -e '.decision == "block" or .continue == false or .hookSpecificOutput.permissionDecision == "deny" or .hookSpecificOutput.decision.behavior == "deny"' >/dev/null; then
    blocked=true
  fi
}

dispatch() {
  local input="$1" output result=0
  output="$(printf '%s' "$input" | bash "$hooks_dir/dispatch.sh" "$canonical" "$native")" || result=$?
  if [ "$result" -ne 0 ]; then
    status="$result"
    [ "$result" -eq 2 ] && blocked=true
  fi
  collect "$output"
}

if [ -n "$canonical" ]; then
  if { [ "$native" = PreToolUse ] || [ "$native" = PostToolUse ]; } && printf '%s' "$payload" | jq -e '.tool_name == "apply_patch"' >/dev/null; then
    paths="$(printf '%s' "$payload" | jq -c '[.tool_input.command | split("\n")[] | select(test("^\\*\\*\\* (Add File|Update File|Delete File|Move to): ")) | sub("^\\*\\*\\* (Add File|Update File|Delete File|Move to): "; "")] | unique')"
    count="$(printf '%s' "$paths" | jq 'length')"
    if [ "$count" -eq 0 ]; then
      dispatch "$payload"
    else
      index=0
      while [ "$index" -lt "$count" ]; do
        file="$(printf '%s' "$paths" | jq -r --argjson index "$index" '.[$index]')"
        case "$file" in
          /*) ;;
          *) file="$(printf '%s' "$payload" | jq -er '.cwd')/$file" ;;
        esac
        mapped="$(printf '%s' "$payload" | jq -c --arg file "$file" '.tool_input.file_path = $file')"
        dispatch "$mapped"
        [ "$blocked" = true ] && break
        index=$((index + 1))
      done
    fi
  else
    dispatch "$payload"
  fi
fi

if [ "$blocked" = false ]; then
  for script in "$hooks_dir/codex/$native"/*; do
    [ -f "$script" ] && [ -x "$script" ] || continue
    result=0
    output="$(printf '%s' "$original_payload" | "$script")" || result=$?
    if [ "$result" -ne 0 ]; then
      status="$result"
      [ "$result" -eq 2 ] && blocked=true
    fi
    collect "$output"
    [ "$blocked" = true ] && break
  done
fi

if [ "$outputs" != '[]' ]; then
  printf '%s' "$outputs" | jq -c 'reduce .[] as $response ({};
    ([.hookSpecificOutput.additionalContext, $response.hookSpecificOutput.additionalContext] | map(select(. != null)) | join("\n")) as $context
    | . * $response
    | if $context != "" then .hookSpecificOutput.additionalContext = $context else . end)'
fi

if [ "$native" = SessionEnd ] && [ -n "$session_dir" ]; then
  rm -rf -- "$session_dir"
fi
exit "$status"
