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
    ok("setup() wurde aufgerufen")
  else
    warn("setup() wurde nicht aufgerufen — es gelten die Defaults", {
      'require("neos_fusion").setup({})',
    })
  end

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    err("Neovim 0.10 oder neuer wird benoetigt")
  end

  report_start("Node.js")
  if vim.fn.executable(cfg.server.node) == 1 then
    local out = vim.fn.system({ cfg.server.node, "--version" })
    ok(("`%s` gefunden (%s)"):format(cfg.server.node, vim.trim(out)))
  else
    err(("`%s` nicht gefunden"):format(cfg.server.node), { "Node.js installieren" })
  end
  if vim.fn.executable(cfg.server.npm) == 1 then
    ok(("`%s` gefunden"):format(cfg.server.npm))
  else
    warn(("`%s` nicht gefunden"):format(cfg.server.npm), {
      "Ohne npm funktioniert :NeosFusionInstallServer nicht.",
    })
  end

  report_start("Language Server")
  info("Installationsordner: " .. config.install_dir())
  if installer.is_installed() then
    ok(("neos-fusion-ls installiert (Version %s)"):format(installer.installed_version() or "?"))
  else
    warn("neos-fusion-ls ist nicht ueber das Plugin installiert", {
      ":NeosFusionInstallServer",
    })
  end

  -- Der checkhealth-Buffer selbst ist keine Datei; ohne diese Pruefung
  -- landete hier die Wurzel von `health://neos_fusion`.
  local buf_path = util.buf_file_path(0)
  local root = buf_path and lsp.find_root(buf_path) or vim.fn.getcwd()
  if buf_path then
    info(("Erkannte Projektwurzel: %s  (aus %s)"):format(root, buf_path))
  else
    info(("Erkannte Projektwurzel: %s  (aktuelles Arbeitsverzeichnis — fuer eine "
      .. "belastbare Pruefung :checkhealth aus einer .fusion-Datei aufrufen)"):format(root))
  end

  local cmd, source = lsp.resolve_cmd(root)
  if cmd then
    ok(("Startkommando (%s): %s"):format(source, table.concat(cmd, " ")))
  else
    err("Kein Startkommando ermittelbar: " .. source, {
      ":NeosFusionInstallServer",
      'oder server.cmd = { "node", "/pfad/out/main.js", "--stdio" } setzen',
    })
  end

  if util.is_file(lsp.wrapper_path()) then
    ok("stdio-Wrapper vorhanden: " .. lsp.wrapper_path())
  else
    err("stdio-Wrapper fehlt: " .. lsp.wrapper_path())
  end
  if not cfg.server.sanitize_stdout then
    warn("server.sanitize_stdout ist deaktiviert", {
      "Der Server schreibt Logzeilen auf stdout und kann damit das LSP-Framing zerstoeren.",
    })
  end

  info(lsp.status())

  report_start("Syntax / Tree-sitter")
  -- `vim.treesitter.language.add` wirft nicht, sondern liefert `true` bzw. `nil`.
  local ok_add, added = pcall(vim.treesitter.language.add, "fusion")
  if ok_add and added then
    ok("Tree-sitter-Parser `fusion` verfuegbar")
  else
    -- Kein WARNING: `fusion` ist im aktuellen nvim-treesitter (Branch `main`)
    -- nicht mehr enthalten, `:TSInstall fusion` meldet dort
    -- "skipping unsupported language". Die Vim-Syntax ist der vorgesehene
    -- Weg, nicht ein Notbehelf.
    ok("Vim-Syntax aktiv (syntax/fusion.vim)")
    info("Tree-sitter-Parser `fusion` nicht geladen — erwartet auf nvim-treesitter `main`, "
      .. "das die Grammatik nicht mehr fuehrt. Nur auf Branch `master` liefert "
      .. ":TSInstall fusion einen Parser.")
  end

  report_start("Snippets")
  local snippets = require("neos_fusion.snippets")
  local engine = snippets.engine()
  if engine == "luasnip" then
    ok("LuaSnip gefunden — Snippets werden registriert")
  elseif engine == "blink" then
    ok("blink.cmp gefunden — Snippets werden ueber den runtimepath gefunden")
  else
    info("Keine Snippet-Engine gefunden. Snippets liegen als VSCode-JSON unter "
      .. snippets.snippets_dir())
  end
end

return M
