#!/bin/bash
# SessionStart hook: inject the branch memory snapshot deterministically at
# session open. sqlite runs locally at startup, tokens are only spent when the
# first prompt is sent because the output rides along with it.
root="${CLAUDE_PROJECT_DIR:-.}"
db="$root/.agent/memory.db"
[ -f "$db" ] || exit 0

conf="$(cd "$(dirname "$0")" && pwd)/session_restore_instructions.json"

if [ "$(sqlite3 "$db" "SELECT value FROM state WHERE key='dotagent'" 2>/dev/null)" = "off" ]; then
  [ -f "$conf" ] && jq -r '.off // ""' "$conf"
  exit 0
fi

branch="$(git -C "$root" branch --show-current 2>/dev/null)"
branch="${branch//\'/}"
[ -n "$branch" ] || branch="unknown"
sqlite3 "$db" "INSERT OR IGNORE INTO branches (name) VALUES ('$branch')" 2>/dev/null

q() { sqlite3 -header -column "$db" "$1" 2>/dev/null; }

echo "-- dotagent memory snapshot, checkout branch: $branch --"
echo "[rules]"
q "SELECT name, content FROM rules WHERE active=1"
echo
echo "[memories]"
q "SELECT type, count(*) AS count FROM memories GROUP BY type ORDER BY type"
echo
echo "[diary]"
q "SELECT entry, workstream, created_at FROM diary ORDER BY id DESC LIMIT 2"
echo
echo "[last session]"
q "SELECT summary, next_steps FROM sessions WHERE branch='$branch' ORDER BY started_at DESC LIMIT 1"
echo
echo "[pending tasks]"
q "SELECT id, title, status FROM tasks WHERE branch='$branch' AND status <> 'done' ORDER BY id"
echo
echo "[general tasks]"
q "SELECT id, title, status FROM tasks WHERE branch='general' AND status <> 'done' ORDER BY id"
echo
echo "[open bugs]"
q "SELECT id, title, status FROM bugs WHERE branch='$branch' AND status = 'open'"
echo
echo "[refactorings]"
q "SELECT id, title, status FROM refactorings WHERE branch='$branch' AND status <> 'done' ORDER BY id"
echo
echo "[decisions]"
q "SELECT id, category, title FROM decisions WHERE branch='$branch' AND status = 'active' ORDER BY created_at DESC LIMIT 5"
echo
echo "[learnings]"
q "SELECT content FROM learnings WHERE (branch='$branch' OR branch IS NULL) ORDER BY created_at DESC LIMIT 5"
echo
[ -f "$conf" ] && jq -r '.footer // ""' "$conf"
exit 0
