--- neos-fusion.nvim — Neovim support for Neos CMS, Neos.Fusion and AFX.
---
--- The module is safe to load without `setup()`: it registers nothing on
--- import and falls back to the defaults from `neos_fusion.config`.
local M = {}

M.version = "0.1.0"

local augroup = nil

--- Registers the autocmds for Fusion buffers (idempotent).
local function create_autocmds()
  local config = require("neos_fusion.config")
  local cfg = config.get()

  augroup = vim.api.nvim_create_augroup("NeosFusion", { clear = true })

  if cfg.server.enable and cfg.server.autostart then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = cfg.server.filetypes,
      desc = "Start the Neos Fusion language server",
      callback = function(args)
        -- A failure during startup must not abort opening the file.
        local ok, err = pcall(require("neos_fusion.lsp").start, args.buf)
        if not ok then
          require("neos_fusion.util").error("Startup failed: " .. tostring(err))
        end
      end,
    })
  end

  if cfg.treesitter.enable then
    local warned = false
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = "fusion",
      desc = "Enable Tree-sitter for Fusion if the parser is available",
      callback = function(args)
        local ok = pcall(vim.treesitter.start, args.buf, "fusion")
        if not ok and cfg.treesitter.notify_missing and not warned then
          warned = true
          require("neos_fusion.util").warn(
            "Tree-sitter parser `fusion` missing — using the bundled Vim syntax instead.\n"
              .. "Installation: :TSInstall fusion"
          )
        end
      end,
    })
  end
end

--- Registers filetype detection.
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

--- Entry point.
---@param opts table|nil
---@return table config
function M.setup(opts)
  local config = require("neos_fusion.config")
  local cfg = config.setup(opts)

  register_filetypes()
  create_autocmds()
  require("neos_fusion.snippets").setup()

  -- Serve already open Fusion buffers after the fact (e.g. when the plugin is
  -- loaded later through `:Lazy load`).
  if cfg.server.enable and cfg.server.autostart then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(cfg.server.filetypes, vim.bo[bufnr].filetype) then
        require("neos_fusion.lsp").start(bufnr)
      end
    end
  end

  return cfg
end

--- Convenient access for user configurations.
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
