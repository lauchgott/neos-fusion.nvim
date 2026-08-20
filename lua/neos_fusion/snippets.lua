--- Snippet-Anbindung.
---
--- Die Snippets liegen als VSCode-kompatibles JSON unter `snippets/fusion.json`
--- und koennen von jedem Loader gelesen werden, der dieses Format versteht.
--- Mit LuaSnip registriert das Plugin sie explizit. blink.cmp durchsucht den
--- runtimepath nicht; dort muss das Verzeichnis in der blink-Konfiguration
--- stehen (siehe M.blink_hint()).
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

--- Die Suchpfade, die blink.cmp fuer VSCode-Snippets verwendet.
---
--- blink durchsucht **nicht** den runtimepath. Laut
--- `blink/cmp/sources/snippets/default/registry.lua` gilt:
---   search_paths = { stdpath("config") .. "/snippets" }
--- und zusaetzlich, bei `friendly_snippets = true`, alle
--- runtimepath-Eintraege, deren Pfad auf `friendly.snippets` passt.
--- Ein Plugin-Verzeichnis wird also nie automatisch gefunden.
---@return string[]
function M.blink_search_paths()
  local ok, cfg = pcall(require, "blink.cmp.config")
  if not ok then
    return {}
  end
  local paths = vim.tbl_get(cfg, "sources", "providers", "snippets", "opts", "search_paths")
  if type(paths) ~= "table" then
    -- Nutzer hat nichts gesetzt: blinks Default.
    paths = { vim.fn.stdpath("config") .. "/snippets" }
  end
  return vim.tbl_map(function(path)
    return vim.fs.normalize(path)
  end, paths)
end

--- Kennt blink.cmp das Snippetverzeichnis dieses Plugins?
---@return boolean
function M.in_blink_search_paths()
  local want = M.snippets_dir()
  for _, path in ipairs(M.blink_search_paths()) do
    if path == want then
      return true
    end
  end
  return false
end

--- Fertiger lazy.nvim-Spec-Ausschnitt, der das Verzeichnis eintraegt.
---@return string
function M.blink_hint()
  return table.concat({
    "blink.cmp durchsucht das Plugin-Verzeichnis nicht selbst. In die",
    "lazy.nvim-Spec aufnehmen:",
    "",
    '  {',
    '    "saghen/blink.cmp",',
    "    opts = function(_, opts)",
    "      local dir = require(\"neos_fusion.snippets\").snippets_dir()",
    "      opts.sources = opts.sources or {}",
    "      opts.sources.providers = opts.sources.providers or {}",
    "      local snippets = opts.sources.providers.snippets or {}",
    "      snippets.opts = snippets.opts or {}",
    "      local paths = snippets.opts.search_paths",
    "        or { vim.fn.stdpath(\"config\") .. \"/snippets\" }",
    "      table.insert(paths, dir)",
    "      snippets.opts.search_paths = paths",
    "      opts.sources.providers.snippets = snippets",
    "    end,",
    '  },',
    "",
    "Verzeichnis dieses Plugins: " .. M.snippets_dir(),
  }, "\n")
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
    -- Bei blink.cmp kann das Plugin nichts registrieren: die Snippet-Registry
    -- wird einmalig beim Erzeugen der Source gebaut (blink-Setup), also bevor
    -- ein ft-lazy geladenes Plugin ueberhaupt existiert. Nachtraegliches
    -- Anpassen der Konfiguration bleibt wirkungslos. Der Pfad muss deshalb in
    -- der blink-Konfiguration selbst stehen — siehe M.blink_hint().
    registered = true
    if mode == true and not M.in_blink_search_paths() then
      util.warn(M.blink_hint())
    end
    return M.in_blink_search_paths()
  end

  if mode == true then
    util.warn("Keine Snippet-Engine gefunden (LuaSnip oder blink.cmp) — Snippets wurden nicht registriert.")
  end
  return false
end

return M
