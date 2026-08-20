--- Snippet-Anbindung.
---
--- Die Snippets liegen als VSCode-kompatibles JSON unter `snippets/fusion.json`
--- und koennen von jedem Loader gelesen werden, der dieses Format versteht.
--- Mit LuaSnip registriert das Plugin sie explizit, mit blink.cmp findet die
--- Engine sie selbst ueber den runtimepath.
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

local registered = false

---@return string
function M.snippets_dir()
  return util.join(util.plugin_root(), "snippets")
end

--- Welche Snippet-Engine ist vorhanden?
---@return "luasnip"|"blink"|nil
function M.engine()
  if pcall(require, "luasnip.loaders.from_vscode") then
    return "luasnip"
  end
  if pcall(require, "blink.cmp") then
    return "blink"
  end
  return nil
end

--- Registriert die Snippets bei der vorhandenen Engine.
---
--- LuaSnip braucht das Verzeichnis explizit. blink.cmp findet
--- VSCode-Snippetverzeichnisse selbst, indem es den runtimepath nach
--- `snippets/package.json` durchsucht — dort ist nichts zu tun, sobald das
--- Plugin geladen ist.
---@param force boolean|nil  erneut registrieren, auch wenn schon geschehen
---@return boolean ok
function M.setup(force)
  local cfg = config.get()
  local mode = cfg.snippets.luasnip
  if mode == false then
    return false
  end
  if registered and not force then
    return true
  end

  local engine = M.engine()

  if engine == "luasnip" then
    require("luasnip.loaders.from_vscode").lazy_load({ paths = { M.snippets_dir() } })
    registered = true
    return true
  end

  if engine == "blink" then
    -- Nichts zu registrieren; blink.cmp uebernimmt das ueber den runtimepath.
    registered = true
    return true
  end

  if mode == true then
    util.warn("Keine Snippet-Engine gefunden (LuaSnip oder blink.cmp) — Snippets wurden nicht registriert.")
  end
  return false
end

return M
