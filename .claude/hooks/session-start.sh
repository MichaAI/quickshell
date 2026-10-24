#!/usr/bin/env bash
# Облачная сессия Claude Code: собрать quickshell, niri и всё для tests/
# (см. tests/setup.sh). Состояние контейнера кешируется после хука, так
# что долго — только в первый раз
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

"$CLAUDE_PROJECT_DIR/tests/setup.sh"

# quickshell, niri и прочее — в PATH сессии
. "$CLAUDE_PROJECT_DIR/tests/qst.sh"
path=$QST/quickshell/bin
for d in "$QST"/*/bin; do path=$path:$d; done
echo "export PATH=\"$path:\$PATH\"" >> "$CLAUDE_ENV_FILE"
