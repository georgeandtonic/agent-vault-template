#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -x "$SCRIPT_DIR/install.sh" ]]; then
  chmod +x "$SCRIPT_DIR/install.sh"
fi

exec "$SCRIPT_DIR/install.sh"
