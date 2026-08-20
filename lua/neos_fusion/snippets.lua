--- Snippet integration.
---
--- The snippets live as VSCode-compatible JSON in `snippets/fusion.json` and
--- can be read by any loader that understands that format. With LuaSnip the
--- plugin registers them explicitly. blink.cmp does not search the
--- runtimepath; there the directory has to be listed in the blink
--- configuration (see M.blink_hint()).
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

local registered = false

---@return string
function M.snippets_dir()
  return util.join(util.plugin_root(), "snippets")
end

--- Which snippet engine is present?
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

--- The search paths blink.cmp uses for VSCode snippets.
---
--- blink does **not** search the runtimepath. According to
--- `blink/cmp/sources/snippets/default/registry.lua`:
---   search_paths = { stdpath("config") .. "/snippets" }
--- plus, with `friendly_snippets = true`, all runtimepath entries whose path
--- matches `friendly.snippets`.
--- A plugin directory is therefore never found automatically.
---@return string[]
function M.blink_search_paths()
  local ok, cfg = pcall(require, "blink.cmp.config")
  if not ok then
    return {}
  end
  local paths = vim.tbl_get(cfg, "sources", "providers", "snippets", "opts", "search_paths")
  if type(paths) ~= "table" then
    -- The user set nothing: blink's default.
    paths = { vim.fn.stdpath("config") .. "/snippets" }
  end
  return vim.tbl_map(function(path)
    return vim.fs.normalize(path)
  end, paths)
end

--- Does blink.cmp know this plugin's snippet directory?
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

--- Ready-made lazy.nvim spec excerpt that adds the directory.
---@return string
function M.blink_hint()
  return table.concat({
    "blink.cmp does not search the plugin directory on its own. Add this to",
    "the lazy.nvim spec:",
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
    "Directory of this plugin: " .. M.snippets_dir(),
  }, "\n")
end

--- Registers the snippets with whichever engine is present.
---
--- LuaSnip needs the directory explicitly. With blink.cmp nothing can be
--- registered from here — the path has to be part of the blink configuration
--- itself (see M.blink_hint()).
---@param force boolean|nil  register again, even if already done
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
    -- With blink.cmp the plugin cannot register anything: the snippet registry
    -- is built once when the source is created (blink setup), i.e. before an
    -- ft-lazy plugin even exists. Adjusting the configuration afterwards has
    -- no effect. The path therefore has to be in the blink configuration
    -- itself — see M.blink_hint().
    registered = true
    if mode == true and not M.in_blink_search_paths() then
      util.warn(M.blink_hint())
    end
    return M.in_blink_search_paths()
  end

  if mode == true then
    util.warn("No snippet engine found (LuaSnip or blink.cmp) — snippets were not registered.")
  end
  return false
end

return M
