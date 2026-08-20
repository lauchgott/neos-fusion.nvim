#!/usr/bin/env bash
# Runs the Lua/Node syntax checks and the Neovim test suite.
#
# The tests run hermetically: the XDG directories point at a temporary
# directory, so that neither the user configuration nor the LSP logs of the
# running Neovim installation are touched.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

state="$(mktemp -d)"
export XDG_STATE_HOME="$state/state"
export XDG_DATA_HOME="$state/data"
export XDG_CACHE_HOME="$state/cache"
export XDG_CONFIG_HOME="$state/config"
mkdir -p "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
trap 'rm -rf "$state"' EXIT

status=0

echo "== Lua syntax check =="
"$root/scripts/luacheck.sh" || status=1

echo
echo "== Node syntax check =="
if command -v node >/dev/null 2>&1; then
  node --check "$root/bin/neos-fusion-ls-stdio.js" && echo "ok    bin/neos-fusion-ls-stdio.js" || status=1
else
  echo "skip  node not found"
fi

echo
echo "== Neovim test suite =="
nvim --clean -n -i NONE --headless -u "$root/tests/minimal_init.lua" -l "$root/tests/run.lua" || status=1

echo
echo "== LSP smoke test =="
if [ -n "${NEOS_FUSION_LS_MAIN:-}" ] || [ -f "$XDG_DATA_HOME/nvim/neos-fusion.nvim/server/node_modules/neos-fusion-ls/out/main.js" ]; then
  nvim --clean -n -i NONE --headless -u "$root/tests/minimal_init.lua" -l "$root/tests/lsp_smoke.lua" || status=1
else
  echo "skip  no server installed (set NEOS_FUSION_LS_MAIN or run :NeosFusionInstallServer)"
fi

exit "$status"
