#!/bin/zsh
#
# DNS Bench — launch the packaged app, building it first when needed.
#
#   ./scripts/run.sh            build if ../releases/DNS Bench.app is missing, then open
#   ./scripts/run.sh --build    always rebuild, then open
#   ./scripts/run.sh --args …   extra arguments are forwarded to the app
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd -- "$ROOT/.." && pwd -P)"
BUNDLE="$REPO_ROOT/releases/DNS Bench.app"

die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1 }

command -v open >/dev/null 2>&1 || die "'open' is missing — this script is macOS only"

rebuild=0
forward=()
for arg in "$@"; do
  case "$arg" in
    --build|-b) rebuild=1 ;;
    --help|-h)
      printf 'usage: %s [--build] [-- app args…]\n' "${0:t}"
      exit 0
      ;;
    *) forward+=("$arg") ;;
  esac
done

if (( rebuild )) || [[ ! -d "$BUNDLE" ]]; then
  "$ROOT/scripts/build.sh"
fi

[[ -d "$BUNDLE" ]] || die "no app bundle at $BUNDLE — run scripts/build.sh"

if (( ${#forward[@]} )); then
  open "$BUNDLE" --args "${forward[@]}"
else
  open "$BUNDLE"
fi

printf '\033[32m✓\033[0m launched %s\n' "$BUNDLE"
