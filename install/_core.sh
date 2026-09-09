#!/usr/bin/env bash
# shared by the per-tool installers, not meant to be run directly
set -euo pipefail

DOTAGENT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "usage: $(basename "$0") /path/to/project"
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
if [ ! -d "$TARGET/.git" ]; then
  echo "error: $TARGET is not a git repository"
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 is required"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (the hooks and installers parse json with it)"
  exit 1
fi

core_install() {
  mkdir -p "$TARGET/.agent"
  cp "$DOTAGENT/schema.sql" "$TARGET/.agent/init-db.sql"

  # -n keeps files the user already edited, re-running only adds new ones
  mkdir -p "$TARGET/.agent/hooks"
  cp -Rn "$DOTAGENT/hooks/." "$TARGET/.agent/hooks/" 2>/dev/null || true
  find "$TARGET/.agent/hooks" -name '*.sh' -exec chmod +x {} +

  if [ ! -f "$TARGET/.agent/memory.db" ]; then
    sqlite3 "$TARGET/.agent/memory.db" < "$DOTAGENT/schema.sql"
    echo "created .agent/memory.db"
  else
    sqlite3 "$TARGET/.agent/memory.db" < "$DOTAGENT/schema.sql"
    echo "kept existing .agent/memory.db (schema applied, existing data untouched)"
  fi

  if [ -e "$TARGET/AGENTS.md" ] || [ -L "$TARGET/AGENTS.md" ]; then
    if ! cmp -s "$DOTAGENT/AGENTS.md" "$TARGET/AGENTS.md"; then
      echo "AGENTS.md already exists, left untouched. Merge $DOTAGENT/AGENTS.md into it manually."
    fi
  else
    cp "$DOTAGENT/AGENTS.md" "$TARGET/AGENTS.md"
    echo "created AGENTS.md"
  fi

  # memory.db is per developer, never committed
  if ! grep -qxF '.agent/memory.db' "$TARGET/.git/info/exclude" 2>/dev/null; then
    echo '.agent/memory.db' >> "$TARGET/.git/info/exclude"
  fi

  echo "core installed into $TARGET (.agent/ + AGENTS.md, memory.db git-excluded)"
}
