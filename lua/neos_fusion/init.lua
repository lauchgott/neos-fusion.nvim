--- neos-fusion.nvim — Neovim-Unterstuetzung fuer Neos CMS, Neos.Fusion und AFX.
---
--- Das Modul ist ohne `setup()` gefahrlos ladbar: es registriert beim Import
--- nichts und faellt auf die Defaults aus `neos_fusion.config` zurueck.
local M = {}

M.version = "0.1.0"

local augroup = nil

--- Autocmds fuer Fusion-Buffer registrieren (idempotent).
local function create_autocmds()
  local config = require("neos_fusion.config")
  local cfg = config.get()

  augroup = vim.api.nvim_create_augroup("NeosFusion", { clear = true })

  if cfg.server.enable and cfg.server.autostart then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = cfg.server.filetypes,
      desc = "Neos Fusion Language Server starten",
      callback = function(args)
        -- Ein Fehler beim Start darf das Oeffnen der Datei nicht abbrechen.
        local ok, err = pcall(require("neos_fusion.lsp").start, args.buf)
        if not ok then
          require("neos_fusion.util").error("Start fehlgeschlagen: " .. tostring(err))
        end
      end,
    })
  end

  if cfg.treesitter.enable then
    local warned = false
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = "fusion",
      desc = "Tree-sitter fuer Fusion aktivieren, falls Parser vorhanden",
      callback = function(args)
        local ok = pcall(vim.treesitter.start, args.buf, "fusion")
        if not ok and cfg.treesitter.notify_missing and not warned then
          warned = true
          require("neos_fusion.util").warn(
            "Tree-sitter-Parser `fusion` fehlt — es wird die mitgelieferte Vim-Syntax verwendet.\n"
              .. "Installation: :TSInstall fusion"
          )
        end
      end,
    })
  end
end

--- Filetype-Erkennung registrieren.
local function register_filetypes()
  local cfg = require("neos_fusion.config").get()
  local extensions = {}
  if cfg.filetypes.fusion then
    extensions.fusion = "fusion"
  end
  if cfg.filetypes.afx then
    extensions.afx = "fusion"
  end
  if next(extensions) then
    vim.filetype.add({ extension = extensions })
  end
end

--- Einstiegspunkt.
---@param opts table|nil
---@return table config
function M.setup(opts)
  local config = require("neos_fusion.config")
  local cfg = config.setup(opts)

  register_filetypes()
  create_autocmds()
  require("neos_fusion.snippets").setup()

  -- Bereits geoeffnete Fusion-Buffer nachtraeglich bedienen (z.B. wenn das
  -- Plugin per `:Lazy load` nachgeladen wird).
  if cfg.server.enable and cfg.server.autostart then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(cfg.server.filetypes, vim.bo[bufnr].filetype) then
        require("neos_fusion.lsp").start(bufnr)
      end
    end
  end

  return cfg
end

--- Bequemer Zugriff fuer Nutzerkonfigurationen.
---@return table
function M.config()
  return require("neos_fusion.config").get()
end

function M.start()
  return require("neos_fusion.lsp").start()
end

function M.stop()
  return require("neos_fusion.lsp").stop()
end

function M.restart()
  return require("neos_fusion.lsp").restart()
end

function M.install_server(version)
  return require("neos_fusion.installer").install(version)
end

return M
