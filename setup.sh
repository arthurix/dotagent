#!/usr/bin/env bash
# curl -fsSL https://raw.githubusercontent.com/arthurix/dotagent/master/setup.sh | bash -s -- claude /path/to/project
set -euo pipefail

TOOL="${1:-all}"
TARGET="${2:-.}"
DIR="${DOTAGENT_HOME:-$HOME/.dotagent}"

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull -q
else
  git clone -q https://github.com/arthurix/dotagent.git "$DIR"
fi

exec "$DIR/install/$TOOL" "$TARGET"
