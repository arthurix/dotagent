#!/usr/bin/env bash
# Project-style checker. Inspects only the lines THIS change added (via git
# diff) so editing legacy files never trips on pre-existing code. The checks
# are data in style_check_instructions.json: {pattern, message, glob?}, glob
# scopes a check to matching file paths. Findings go to stderr with exit 2,
# the harness feeds them back to the model.

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
[ -n "$file" ] && [ -f "$file" ] || exit 0
[ "$(sqlite3 "${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ] && exit 0

conf="$(cd "$(dirname "$0")" && pwd)/style_check_instructions.json"
[ -f "$conf" ] || exit 0

# skip test files, style rules are for app code
case "$file" in
  *_test.*|*.test.*|*.spec.*|*/test/*|*/tests/*|*/spec/*) exit 0 ;;
esac

repo="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)" || exit 0

if git -C "$repo" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
  added="$(git -C "$repo" diff --unified=0 HEAD -- "$file" 2>/dev/null | sed -n 's/^+//p' | grep -v '^++')"
else
  added="$(cat "$file")"   # new/untracked file: check the whole thing
fi
[ -n "$added" ] || exit 0

findings=""
count="$(jq '.checks | length' "$conf")"
i=0
while [ "$i" -lt "$count" ]; do
  pattern="$(jq -r ".checks[$i].pattern" "$conf")"
  message="$(jq -r ".checks[$i].message" "$conf")"
  glob="$(jq -r ".checks[$i].glob // \"*\"" "$conf")"
  i=$((i + 1))
  case "$file" in
    $glob) ;;
    *) continue ;;
  esac
  hits="$(printf '%s\n' "$added" | grep -E "$pattern" | head -3)"
  [ -n "$hits" ] && findings="${findings}
- $message
$(printf '%s\n' "$hits" | sed 's/^/    /')"
done

[ -z "$findings" ] && exit 0

printf 'Project-style check flagged newly-added lines in %s:%s\n' "${file#"$repo"/}" "$findings" >&2
exit 2
