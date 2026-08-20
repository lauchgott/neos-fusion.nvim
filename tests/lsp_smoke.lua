-- End-to-End-Smoke-Test gegen den echten Language Server.
--
-- Aufruf:
--   NEOS_FUSION_LS_MAIN=/pfad/zu/neos-fusion-ls/out/main.js \
--     nvim --clean -n -i NONE --headless -u tests/minimal_init.lua -l tests/lsp_smoke.lua
--
-- Ohne installierten Server wird der Test von scripts/test.sh uebersprungen.
local root_plugin = _G.NEOS_FUSION_TEST_ROOT or vim.fn.getcwd()

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    io.write(("  ok    %s\n"):format(name))
  else
    failed = failed + 1
    io.write(("  FAIL  %s%s\n"):format(name, detail and ("\n         " .. tostring(detail)) or ""))
  end
end

-- Testprojekt anlegen.
local project = vim.fn.tempname()
local fusion_dir = project .. "/DistributionPackages/Vendor.Site/Resources/Private/Fusion"
vim.fn.mkdir(fusion_dir, "p")
vim.fn.mkdir(project .. "/DistributionPackages/Vendor.Site/Configuration", "p")
vim.fn.writefile({ '{ "name": "vendor/neos-site", "require": { "neos/neos": "^8.3" } }' }, project .. "/composer.json")
vim.fn.writefile(
  { '{ "name": "vendor/site", "type": "neos-site", "extra": { "neos": { "package-key": "Vendor.Site" } } }' },
  project .. "/DistributionPackages/Vendor.Site/composer.json"
)
vim.fn.writefile({ "'Vendor.Site:Content.Teaser':", "  superTypes:", "    'Neos.Neos:Content': true" },
  project .. "/DistributionPackages/Vendor.Site/Configuration/NodeTypes.yaml")
local file = fusion_dir .. "/Root.fusion"
vim.fn.writefile({
  "prototype(Vendor.Site:Component.Teaser) < prototype(Neos.Fusion:Component) {",
  "    title = 'Hallo'",
  "    renderer = afx`",
  "        <h1>{props.title}</h1>",
  "    `",
  "}",
}, file)

local opts = {}
local main = vim.env.NEOS_FUSION_LS_MAIN
if main and main ~= "" then
  opts.server = { cmd = { "node", root_plugin .. "/bin/neos-fusion-ls-stdio.js", main, "--stdio" } }
end

require("neos_fusion").setup(opts)

io.write("\nneos-fusion.nvim — LSP-Smoke-Test\n\n")

local lsp = require("neos_fusion.lsp")
local cmd, source = lsp.resolve_cmd(project)
check("Startkommando ermittelt (" .. tostring(source) .. ")", cmd ~= nil, source)
if not cmd then
  vim.cmd("cq")
end
io.write("        cmd: " .. table.concat(cmd, " ") .. "\n")

vim.cmd.edit(file)
local bufnr = vim.api.nvim_get_current_buf()
check("Filetype ist fusion", vim.bo.filetype == "fusion", vim.bo.filetype)

local client_id = lsp.start(bufnr)
check("Client gestartet", client_id ~= nil)
if not client_id then
  vim.cmd("cq")
end

-- Auf initialize warten.
local function wait(pred, timeout)
  return vim.wait(timeout or 20000, pred, 100)
end

local client = vim.lsp.get_client_by_id(client_id)
check("initialize erfolgreich (kein stdout-Framing-Fehler)", wait(function()
  client = vim.lsp.get_client_by_id(client_id)
  return client ~= nil and client.initialized == true
end), "Timeout beim initialize")

client = vim.lsp.get_client_by_id(client_id)
if not client then
  io.write("  FAIL  Client verschwunden\n")
  vim.cmd("cq")
end

local caps = client.server_capabilities or {}
check("hoverProvider angekuendigt", caps.hoverProvider == true)
check("definitionProvider angekuendigt", caps.definitionProvider == true)
check("completionProvider angekuendigt", caps.completionProvider ~= nil)
check("semanticTokensProvider angekuendigt", caps.semanticTokensProvider ~= nil)
check("documentSymbolProvider angekuendigt", caps.documentSymbolProvider == true)

check("Client an Buffer attached", wait(function()
  return client.attached_buffers and client.attached_buffers[bufnr] == true
end), "nicht attached")

-- Der Server initialisiert die Workspaces erst nach didChangeConfiguration.
-- Neovim sendet das automatisch, weil `settings` gesetzt ist.
vim.wait(3000, function()
  return false
end, 200)

-- Hover auf `Neos.Fusion:Component` (Zeile 1, Spalte ~55).
local hover_result, hover_err
client:request("textDocument/hover", {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  position = { line = 0, character = 55 },
}, function(err, result)
  hover_err = err
  hover_result = result or false
end, bufnr)
check("Hover liefert Antwort", wait(function()
  return hover_result ~= nil
end, 10000), hover_err and vim.inspect(hover_err) or "Timeout")
if type(hover_result) == "table" then
  local value = vim.tbl_get(hover_result, "contents", "value") or ""
  io.write("        hover: " .. value:gsub("\n", " ") .. "\n")
  check("Hover nennt den Prototyp", value:find("Neos.Fusion:Component", 1, true) ~= nil, value)
else
  check("Hover nennt den Prototyp", false, "keine contents")
end

-- documentSymbol
local symbols
client:request("textDocument/documentSymbol", {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
}, function(_, result)
  symbols = result or false
end, bufnr)
check("documentSymbol liefert Antwort", wait(function()
  return symbols ~= nil
end, 10000), "Timeout")
if type(symbols) == "table" and symbols[1] then
  io.write("        symbol: " .. tostring(symbols[1].name) .. "\n")
  check("documentSymbol nennt den Prototyp", symbols[1].name == "Vendor.Site:Component.Teaser", symbols[1].name)
else
  check("documentSymbol nennt den Prototyp", false, vim.inspect(symbols))
end

-- Diagnostics: fehlerhafte Zeile einfuegen und auf publishDiagnostics warten.
vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "    unclosed = afx`<div>`" })
vim.cmd("silent write")
local ns_ok = wait(function()
  return #vim.diagnostic.get(bufnr) > 0
end, 15000)
check("Diagnostics werden geliefert", ns_ok, "keine Diagnostics innerhalb von 15s")
if ns_ok then
  local d = vim.diagnostic.get(bufnr)[1]
  io.write(("        diagnostic: %s\n"):format((d.message or ""):gsub("\n", " ")))
end

-- Sauber beenden.
client:stop(true)
check("Client stoppt", wait(function()
  return vim.lsp.get_client_by_id(client_id) == nil or client:is_stopped()
end, 10000))

io.write(("\n%d bestanden, %d fehlgeschlagen\n"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
end
vim.cmd("qa!")
