--- Ladepunkt: registriert nur Kommandos und die Filetype-Erkennung.
--- Es wird bewusst nichts gestartet und keine Konfiguration erzwungen.
if vim.g.loaded_neos_fusion then
  return
end
vim.g.loaded_neos_fusion = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("[neos-fusion] benoetigt Neovim 0.10 oder neuer.", vim.log.levels.ERROR)
  return
end

-- Filetype-Erkennung auch ohne setup(), damit `.fusion` immer funktioniert.
vim.filetype.add({ extension = { fusion = "fusion" } })

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("NeosFusionInstallServer", function(args)
  require("neos_fusion.installer").install(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Neos Fusion Language Server installieren" })

cmd("NeosFusionUpdateServer", function(args)
  require("neos_fusion.installer").update(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Neos Fusion Language Server aktualisieren" })

cmd("NeosFusionServerInfo", function()
  local installer = require("neos_fusion.installer")
  local lsp = require("neos_fusion.lsp")
  local lines = vim.split(installer.info(), "\n")
  vim.list_extend(lines, { "", lsp.status() })
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Status des Neos Fusion Language Servers anzeigen" })

cmd("NeosFusionStart", function()
  require("neos_fusion.lsp").start()
end, { desc = "Language Server fuer den aktuellen Buffer starten" })

cmd("NeosFusionStop", function()
  require("neos_fusion.lsp").stop()
end, { desc = "Language Server stoppen" })

cmd("NeosFusionRestart", function()
  require("neos_fusion.lsp").restart()
end, { desc = "Language Server neu starten" })

cmd("NeosFusionReloadWorkspace", function()
  require("neos_fusion.lsp").reload_workspace()
end, { desc = "Fusion-Workspaces im Server neu aufbauen" })

cmd("NeosFusionSetLogLevel", function(args)
  require("neos_fusion.lsp").set_log_level(args.args)
end, {
  nargs = 1,
  complete = function()
    return { "error", "info", "verbose", "debug" }
  end,
  desc = "Log-Level des Servers zur Laufzeit setzen",
})

cmd("NeosFusionDoctor", function()
  local report = require("neos_fusion.lsp").doctor()
  -- In einen Scratch-Buffer, damit der Text kopierbar bleibt.
  vim.cmd("botright new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_name(bufnr, "neos-fusion://doctor")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(report, "\n"))
  vim.bo[bufnr].modifiable = false
end, { desc = "Diagnose: warum liefert der Server nichts?" })

cmd("NeosFusionLog", function()
  vim.cmd.tabnew(vim.lsp.get_log_path())
end, { desc = "LSP-Logdatei oeffnen" })
