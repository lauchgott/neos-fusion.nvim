-- End-to-end smoke test against the real language server.
--
-- Usage:
--   NEOS_FUSION_LS_MAIN=/path/to/neos-fusion-ls/out/main.js \
--     nvim --clean -n -i NONE --headless -u tests/minimal_init.lua -l tests/lsp_smoke.lua
--
-- Without an installed server scripts/test.sh skips this test.
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

-- Create the test project.
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

io.write("\nneos-fusion.nvim — LSP smoke test\n\n")

local lsp = require("neos_fusion.lsp")
local cmd, source = lsp.resolve_cmd(project)
check("start command determined (" .. tostring(source) .. ")", cmd ~= nil, source)
if not cmd then
  vim.cmd("cq")
end
io.write("        cmd: " .. table.concat(cmd, " ") .. "\n")

vim.cmd.edit(file)
local bufnr = vim.api.nvim_get_current_buf()
check("filetype is fusion", vim.bo.filetype == "fusion", vim.bo.filetype)

local client_id = lsp.start(bufnr)
check("client started", client_id ~= nil)
if not client_id then
  vim.cmd("cq")
end

-- Wait for initialize.
local function wait(pred, timeout)
  return vim.wait(timeout or 20000, pred, 100)
end

local client = vim.lsp.get_client_by_id(client_id)
check("initialize succeeded (no stdout framing error)", wait(function()
  client = vim.lsp.get_client_by_id(client_id)
  return client ~= nil and client.initialized == true
end), "timeout during initialize")

client = vim.lsp.get_client_by_id(client_id)
if not client then
  io.write("  FAIL  client disappeared\n")
  vim.cmd("cq")
end

local caps = client.server_capabilities or {}
check("hoverProvider announced", caps.hoverProvider == true)
check("definitionProvider announced", caps.definitionProvider == true)
check("completionProvider announced", caps.completionProvider ~= nil)
check("semanticTokensProvider announced", caps.semanticTokensProvider ~= nil)
check("documentSymbolProvider announced", caps.documentSymbolProvider == true)

check("client attached to the buffer", wait(function()
  return client.attached_buffers and client.attached_buffers[bufnr] == true
end), "not attached")

-- The server initializes its workspaces only after didChangeConfiguration.
-- Neovim sends that automatically because `settings` is set.
vim.wait(3000, function()
  return false
end, 200)

-- Hover on `Neos.Fusion:Component` (line 1, column ~55).
local hover_result, hover_err
client:request("textDocument/hover", {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  position = { line = 0, character = 55 },
}, function(err, result)
  hover_err = err
  hover_result = result or false
end, bufnr)
check("hover returns an answer", wait(function()
  return hover_result ~= nil
end, 10000), hover_err and vim.inspect(hover_err) or "timeout")
if type(hover_result) == "table" then
  local value = vim.tbl_get(hover_result, "contents", "value") or ""
  io.write("        hover: " .. value:gsub("\n", " ") .. "\n")
  check("hover names the prototype", value:find("Neos.Fusion:Component", 1, true) ~= nil, value)
else
  check("hover names the prototype", false, "no contents")
end

-- documentSymbol
local symbols
client:request("textDocument/documentSymbol", {
  textDocument = { uri = vim.uri_from_bufnr(bufnr) },
}, function(_, result)
  symbols = result or false
end, bufnr)
check("documentSymbol returns an answer", wait(function()
  return symbols ~= nil
end, 10000), "timeout")
if type(symbols) == "table" and symbols[1] then
  io.write("        symbol: " .. tostring(symbols[1].name) .. "\n")
  check("documentSymbol names the prototype", symbols[1].name == "Vendor.Site:Component.Teaser", symbols[1].name)
else
  check("documentSymbol names the prototype", false, vim.inspect(symbols))
end

-- Diagnostics: insert a broken line and wait for publishDiagnostics.
vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "    unclosed = afx`<div>`" })
vim.cmd("silent write")
local ns_ok = wait(function()
  return #vim.diagnostic.get(bufnr) > 0
end, 15000)
check("diagnostics are delivered", ns_ok, "no diagnostics within 15s")
if ns_ok then
  local d = vim.diagnostic.get(bufnr)[1]
  io.write(("        diagnostic: %s\n"):format((d.message or ""):gsub("\n", " ")))
end

-- Shut down cleanly.
client:stop(true)
check("client stops", wait(function()
  return vim.lsp.get_client_by_id(client_id) == nil or client:is_stopped()
end, 10000))

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq")
end
vim.cmd("qa!")
