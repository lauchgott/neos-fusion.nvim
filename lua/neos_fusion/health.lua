--- `:checkhealth neos_fusion`
local M = {}

local function report_start(name)
  (vim.health.start or vim.health.report_start)(name)
end
local function ok(msg)
  (vim.health.ok or vim.health.report_ok)(msg)
end
local function warn(msg, advice)
  (vim.health.warn or vim.health.report_warn)(msg, advice)
end
local function err(msg, advice)
  (vim.health.error or vim.health.report_error)(msg, advice)
end
local function info(msg)
  (vim.health.info or vim.health.report_info)(msg)
end

function M.check()
  local config = require("neos_fusion.config")
  local installer = require("neos_fusion.installer")
  local lsp = require("neos_fusion.lsp")
  local util = require("neos_fusion.util")
  local cfg = config.get()

  report_start("neos-fusion.nvim")

  if config.is_configured() then
    ok("setup() was called")
  else
    warn("setup() was not called — the defaults apply", {
      'require("neos_fusion").setup({})',
    })
  end

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    err("Neovim 0.10 or newer is required")
  end

  report_start("Node.js")
  if vim.fn.executable(cfg.server.node) == 1 then
    local out = vim.fn.system({ cfg.server.node, "--version" })
    ok(("`%s` found (%s)"):format(cfg.server.node, vim.trim(out)))
  else
    err(("`%s` not found"):format(cfg.server.node), { "Install Node.js" })
  end
  if vim.fn.executable(cfg.server.npm) == 1 then
    ok(("`%s` found"):format(cfg.server.npm))
  else
    warn(("`%s` not found"):format(cfg.server.npm), {
      "Without npm, :NeosFusionInstallServer does not work.",
    })
  end

  report_start("Language server")
  info("Installation directory: " .. config.install_dir())
  if installer.is_installed() then
    ok(("neos-fusion-ls installed (version %s)"):format(installer.installed_version() or "?"))
  else
    warn("neos-fusion-ls is not installed through the plugin", {
      ":NeosFusionInstallServer",
    })
  end

  -- The checkhealth buffer itself is not a file; without this check the root
  -- of `health://neos_fusion` would end up here.
  local buf_path = util.buf_file_path(0)
  local root = buf_path and lsp.find_root(buf_path) or vim.fn.getcwd()
  if buf_path then
    info(("Detected project root: %s  (from %s)"):format(root, buf_path))
  else
    info(("Detected project root: %s  (current working directory — for a meaningful "
      .. "check, run :checkhealth from a .fusion file)"):format(root))
  end

  local cmd, source = lsp.resolve_cmd(root)
  if cmd then
    ok(("Start command (%s): %s"):format(source, table.concat(cmd, " ")))
  else
    err("No start command could be determined: " .. source, {
      ":NeosFusionInstallServer",
      'or set server.cmd = { "node", "/path/out/main.js", "--stdio" }',
    })
  end

  if util.is_file(lsp.wrapper_path()) then
    ok("stdio wrapper present: " .. lsp.wrapper_path())
  else
    err("stdio wrapper missing: " .. lsp.wrapper_path())
  end
  if not cfg.server.sanitize_stdout then
    warn("server.sanitize_stdout is disabled", {
      "The server writes log lines to stdout and can thereby break the LSP framing.",
    })
  end

  info(lsp.status())

  report_start("Syntax / Tree-sitter")
  -- `vim.treesitter.language.add` does not throw, it returns `true` or `nil`.
  local ok_add, added = pcall(vim.treesitter.language.add, "fusion")
  if ok_add and added then
    ok("Tree-sitter parser `fusion` available")
  else
    -- Not a WARNING: `fusion` is no longer part of current nvim-treesitter
    -- (branch `main`), where `:TSInstall fusion` reports "skipping unsupported
    -- language". The Vim syntax is the intended path, not a stopgap.
    ok("Vim syntax active (syntax/fusion.vim)")
    info("Tree-sitter parser `fusion` not loaded — expected on nvim-treesitter `main`, "
      .. "which no longer carries the grammar. Only branch `master` provides a parser "
      .. "for :TSInstall fusion.")
  end

  report_start("Snippets")
  local snippets = require("neos_fusion.snippets")
  local engine = snippets.engine()
  if engine == "luasnip" then
    ok("LuaSnip found — snippets are being registered")
  elseif engine == "blink" then
    if snippets.in_blink_search_paths() then
      ok("blink.cmp knows the plugin's snippet directory")
    else
      warn("blink.cmp found, but it does not know the snippet directory", {
        "blink only searches stdpath('config')/snippets and friendly-snippets,",
        "not the runtimepath. Current search paths: "
          .. table.concat(snippets.blink_search_paths(), ", "),
        "Fix: :help neos-fusion-snippets  or",
        'print require("neos_fusion.snippets").blink_hint()',
      })
    end
  else
    info("No snippet engine found. The snippets are available as VSCode JSON in "
      .. snippets.snippets_dir())
  end
end

return M
