--- Load point: registers only the commands and filetype detection.
--- Deliberately starts nothing and forces no configuration.
if vim.g.loaded_neos_fusion then
  return
end
vim.g.loaded_neos_fusion = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("[neos-fusion] requires Neovim 0.10 or newer.", vim.log.levels.ERROR)
  return
end

-- Filetype detection even without setup(), so `.fusion` always works.
vim.filetype.add({ extension = { fusion = "fusion" } })

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("NeosFusionInstallServer", function(args)
  require("neos_fusion.installer").install(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Install the Neos Fusion language server" })

cmd("NeosFusionUpdateServer", function(args)
  require("neos_fusion.installer").update(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Update the Neos Fusion language server" })

cmd("NeosFusionServerInfo", function()
  local installer = require("neos_fusion.installer")
  local lsp = require("neos_fusion.lsp")
  local lines = vim.split(installer.info(), "\n")
  vim.list_extend(lines, { "", lsp.status() })
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show the status of the Neos Fusion language server" })

cmd("NeosFusionStart", function()
  require("neos_fusion.lsp").start()
end, { desc = "Start the language server for the current buffer" })

cmd("NeosFusionStop", function()
  require("neos_fusion.lsp").stop()
end, { desc = "Stop the language server" })

cmd("NeosFusionRestart", function()
  require("neos_fusion.lsp").restart()
end, { desc = "Restart the language server" })

cmd("NeosFusionReloadWorkspace", function()
  require("neos_fusion.lsp").reload_workspace()
end, { desc = "Rebuild the Fusion workspaces inside the server" })

cmd("NeosFusionSetLogLevel", function(args)
  require("neos_fusion.lsp").set_log_level(args.args)
end, {
  nargs = 1,
  complete = function()
    return { "error", "info", "verbose", "debug" }
  end,
  desc = "Set the server log level at runtime",
})

cmd("NeosFusionDoctor", function()
  local report = require("neos_fusion.lsp").doctor()
  -- Into a scratch buffer, so the text stays copyable.
  vim.cmd("botright new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_name(bufnr, "neos-fusion://doctor")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(report, "\n"))
  vim.bo[bufnr].modifiable = false
end, { desc = "Diagnostics: why does the server return nothing?" })

cmd("NeosFusionLog", function()
  vim.cmd.tabnew(vim.lsp.get_log_path())
end, { desc = "Open the LSP log file" })
