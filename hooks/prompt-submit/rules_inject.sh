#!/bin/bash
# UserPromptSubmit: inject the active rules rows into every prompt, so a style
# or behavior rule survives even the longest session
db="${CLAUDE_PROJECT_DIR:-.}/.agent/memory.db"
[ -f "$db" ] || exit 0
sqlite3 "$db" "SELECT content FROM rules WHERE active=1 AND COALESCE((SELECT value FROM state WHERE key='dotagent'),'on') <> 'off'" 2>/dev/null || true
exit 0
