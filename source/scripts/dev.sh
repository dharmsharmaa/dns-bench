#!/bin/zsh
#
# DNS Bench — run the app straight from source with the local Electron binary.
# Extra arguments are handed to the app (e.g. --dev, --screenshot=…).
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
APP_SRC="$ROOT/app"

die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1 }

step() { printf '\033[36m▸\033[0m %s\n' "$*" }

command -v node >/dev/null 2>&1 \
  || die "'node' not found in PATH — install Node.js 18+ from https://nodejs.org and retry"
command -v npm >/dev/null 2>&1 \
  || die "'npm' not found in PATH — reinstall Node.js and retry"

cd "$APP_SRC"

if [[ ! -d node_modules/electron ]]; then
  step "installing dependencies (first run, this can take a minute)"
  npm install --no-audit --no-fund
fi

[[ -x "./node_modules/.bin/electron" ]] \
  || die "Electron is not installed — remove app/node_modules and rerun this script"

step "rendering icons"
node "$ROOT/scripts/make-icon.js"

step "starting Electron (dev)"
exec ./node_modules/.bin/electron . "$@"
