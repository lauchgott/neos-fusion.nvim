#!/usr/bin/env bash
# Syntax check of all the plugin's Lua files with Neovim's own LuaJIT.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
while IFS= read -r file; do
  if nvim --clean -n -i NONE --headless \
      -c "lua local f, err = loadfile('$file'); if not f then io.stderr:write(err .. '\n'); vim.cmd('cq') end" \
      -c "qa!" 2>/tmp/nf-luacheck.err; then
    echo "ok    $(basename "$(dirname "$file")")/$(basename "$file")"
  else
    echo "FAIL  $file"
    cat /tmp/nf-luacheck.err
    fail=1
  fi
done < <(find "$root" -name '*.lua' -not -path '*/.git/*' | sort)
exit "$fail"
