#!/usr/bin/env bash
# Fuehrt Lua-/Node-Syntaxpruefung und die Neovim-Testsuite aus.
#
# Die Tests laufen hermetisch: XDG-Verzeichnisse zeigen auf ein temporaeres
# Verzeichnis, damit weder die Nutzerkonfiguration noch LSP-Logs der laufenden
# Neovim-Installation beeinflusst werden.
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

echo "== Lua-Syntaxpruefung =="
"$root/scripts/luacheck.sh" || status=1

echo
echo "== Node-Syntaxpruefung =="
if command -v node >/dev/null 2>&1; then
  node --check "$root/bin/neos-fusion-ls-stdio.js" && echo "ok    bin/neos-fusion-ls-stdio.js" || status=1
else
  echo "skip  node nicht gefunden"
fi

echo
echo "== Neovim-Testsuite =="
nvim --clean -n -i NONE --headless -u "$root/tests/minimal_init.lua" -l "$root/tests/run.lua" || status=1

echo
echo "== LSP-Smoke-Test =="
if [ -n "${NEOS_FUSION_LS_MAIN:-}" ] || [ -f "$XDG_DATA_HOME/nvim/neos-fusion.nvim/server/node_modules/neos-fusion-ls/out/main.js" ]; then
  nvim --clean -n -i NONE --headless -u "$root/tests/minimal_init.lua" -l "$root/tests/lsp_smoke.lua" || status=1
else
  echo "skip  kein Server installiert (NEOS_FUSION_LS_MAIN setzen oder :NeosFusionInstallServer)"
fi

exit "$status"
