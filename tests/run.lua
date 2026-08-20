-- Standalone test suite without external dependencies.
-- Usage: nvim --clean -n -i NONE --headless -u tests/minimal_init.lua -l tests/run.lua
local root = _G.NEOS_FUSION_TEST_ROOT or vim.fn.getcwd()

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(("  ok    %s\n"):format(name))
  else
    failed = failed + 1
    table.insert(failures, name .. ": " .. tostring(err))
    io.write(("  FAIL  %s\n         %s\n"):format(name, tostring(err)))
  end
end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(("%s\n         expected: %s\n         actual:   %s"):format(msg or "values differ", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function truthy(value, msg)
  if not value then
    error(msg or "value is falsy", 2)
  end
end

-- Test project (Neos-like layout) in a temporary directory.
local tmp = vim.fn.tempname()
local pkg = tmp .. "/DistributionPackages/Vendor.Site/Resources/Private/Fusion"
vim.fn.mkdir(pkg, "p")
vim.fn.writefile({ '{ "name": "vendor/site", "require": { "neos/neos": "^8.3" } }' }, tmp .. "/composer.json")
vim.fn.writefile({ '{ "name": "vendor/site-package" }' }, tmp .. "/DistributionPackages/Vendor.Site/composer.json")
vim.fn.writefile({
  "prototype(Vendor.Site:Component.Teaser) < prototype(Neos.Fusion:Component) {",
  "    title = ''",
  "    renderer = afx`",
  "        <h1>{props.title}</h1>",
  "    `",
  "}",
}, pkg .. "/Root.fusion")

io.write("\nneos-fusion.nvim — test suite\n\n")

io.write("Module loading\n")
test("require('neos_fusion') without setup() does not throw", function()
  local m = require("neos_fusion")
  truthy(type(m.setup) == "function", "setup() missing")
  truthy(type(m.config()) == "table", "config() returns no table")
end)

test("all submodules load", function()
  for _, name in ipairs({ "config", "util", "lsp", "installer", "snippets", "health" }) do
    local ok, err = pcall(require, "neos_fusion." .. name)
    truthy(ok, ("module neos_fusion.%s: %s"):format(name, err))
  end
end)

test("setup() with empty options", function()
  local cfg = require("neos_fusion").setup({})
  eq(cfg.server.enable, true, "server.enable")
end)

test("setup() merges deeply", function()
  local cfg = require("neos_fusion").setup({
    server = { settings = { neosFusionLsp = { logging = { level = "debug" } } } },
  })
  eq(cfg.server.settings.neosFusionLsp.logging.level, "debug", "log level applied")
  eq(cfg.server.settings.neosFusionLsp.inlayHint.depth, "literal", "defaults preserved")
  require("neos_fusion").setup({})
end)

io.write("\nServer configuration\n")
test("initializationOptions contains textDocumentSync.openClose", function()
  -- Without this value `initialize` fails on the server side.
  local cfg = require("neos_fusion.config").get()
  eq(cfg.server.init_options.textDocumentSync.openClose, true, "openClose")
end)

test("settings cover every branch the server reads", function()
  local s = require("neos_fusion.config").get().server.settings.neosFusionLsp
  for _, path in ipairs({
    "folders.packages",
    "folders.fusion",
    "folders.ignore",
    "folders.workspaceAsPackageFallback",
    "folders.followSymbolicLinks",
    "folders.includeHiddenDirectories",
    "logging.level",
    "diagnostics.enabled",
    "diagnostics.enabledDiagnostics",
    "diagnostics.ignore.folders",
    "diagnostics.levels.deprecations",
    "diagnostics.ignoreNodeTypes",
    "diagnostics.alwaysDiagnoseChangedFile",
    "code.deprecations.fusion.prototypes",
    "code.actions.createNodeTypeConfiguration.template",
    "inlayHint.depth",
  }) do
    local parts = vim.split(path, ".", { plain = true })
    local value = vim.tbl_get(s, unpack(parts))
    truthy(value ~= nil, "missing configuration branch: " .. path)
  end
end)

test("all 14 diagnostic switches present", function()
  local d = require("neos_fusion.config").get().server.settings.neosFusionLsp.diagnostics.enabledDiagnostics
  eq(vim.tbl_count(d), 14, "number of diagnostics")
end)

io.write("\nRoot detection\n")
test("finds the project root through composer.json with neos/neos", function()
  local lsp = require("neos_fusion.lsp")
  eq(lsp.find_root(pkg .. "/Root.fusion"), vim.fs.normalize(tmp), "project root")
end)

test("monorepo: a strong marker beats a .git further up", function()
  -- Exactly the layout seen in practice:
  --   <repo>/.git
  --   <repo>/app/{composer.json, flow, DistributionPackages}
  --   <repo>/{ci,deployment,docs,...}
  local repo = vim.fn.tempname()
  local app = repo .. "/app"
  local fusion = app .. "/DistributionPackages/Sndstrm.ComponentLibrary/Resources/Private/Fusion/Components"
  vim.fn.mkdir(fusion, "p")
  vim.fn.mkdir(repo .. "/.git", "p")
  vim.fn.mkdir(repo .. "/ci", "p")
  vim.fn.writefile({ '{ "require": { "neos/neos": "^8.3" } }' }, app .. "/composer.json")
  vim.fn.writefile({ "#!/usr/bin/env php" }, app .. "/flow")
  local file = fusion .. "/Teaser.fusion"
  vim.fn.writefile({ "prototype(Sndstrm.ComponentLibrary:Teaser) < prototype(Neos.Fusion:Component) {", "}" }, file)

  local lsp = require("neos_fusion.lsp")
  eq(lsp.find_root(file), vim.fs.normalize(app), "app/ instead of the repository root")
end)

test("only .git present -> .git applies as fallback", function()
  local repo = vim.fn.tempname()
  local deep = repo .. "/somewhere/deep"
  vim.fn.mkdir(deep, "p")
  vim.fn.mkdir(repo .. "/.git", "p")
  local file = deep .. "/x.fusion"
  vim.fn.writefile({ "x = 1" }, file)
  eq(require("neos_fusion.lsp").find_root(file), vim.fs.normalize(repo), "repository root as fallback")
end)

test("root_outermost applies inside the strong tier", function()
  -- The package composer.json also names neos/neos -> both levels are strong.
  local repo = vim.fn.tempname()
  local app = repo .. "/app"
  local package = app .. "/DistributionPackages/Vendor.Site"
  vim.fn.mkdir(package .. "/Resources/Private/Fusion", "p")
  vim.fn.mkdir(repo .. "/.git", "p")
  vim.fn.writefile({ '{ "require": { "neos/neos": "^8.3" } }' }, app .. "/composer.json")
  vim.fn.writefile({ '{ "require": { "neos/neos": "^8.3" } }' }, package .. "/composer.json")
  local file = package .. "/Resources/Private/Fusion/Root.fusion"
  vim.fn.writefile({ "x = 1" }, file)

  local lsp = require("neos_fusion.lsp")
  eq(lsp.find_root(file), vim.fs.normalize(app), "outermost strong candidate")

  require("neos_fusion").setup({ server = { root_outermost = false } })
  eq(lsp.find_root(file), vim.fs.normalize(package), "innermost with root_outermost = false")
  require("neos_fusion").setup({})
end)

test("a package composer.json alone is no root", function()
  local util = require("neos_fusion.util")
  eq(util.composer_looks_like_neos(tmp .. "/DistributionPackages/Vendor.Site/composer.json"), false, "package manifest")
  eq(util.composer_looks_like_neos(tmp .. "/composer.json"), true, "project manifest")
end)

io.write("\nCommand resolution\n")
test("reports a missing server instead of guessing", function()
  require("neos_fusion").setup({ server = { install_dir = tmp .. "/nonexistent" } })
  local cmd = require("neos_fusion.lsp").resolve_cmd(tmp)
  -- There may only be a cmd when a file actually exists.
  if cmd then
    truthy(vim.uv.fs_stat(cmd[#cmd - 1]) ~= nil or vim.uv.fs_stat(cmd[2]) ~= nil, "cmd points at a missing file")
  end
  require("neos_fusion").setup({})
end)

test("an explicit server.cmd takes precedence", function()
  require("neos_fusion").setup({ server = { cmd = { "node", "/x/main.js", "--stdio" } } })
  local cmd = require("neos_fusion.lsp").resolve_cmd(tmp)
  eq(table.concat(cmd, " "), "node /x/main.js --stdio", "cmd")
  require("neos_fusion").setup({})
end)

test("the wrapper is inserted into the command", function()
  local fake = tmp .. "/fakeprefix"
  vim.fn.mkdir(fake .. "/node_modules/neos-fusion-ls/out", "p")
  vim.fn.writefile({ "// fake" }, fake .. "/node_modules/neos-fusion-ls/out/main.js")
  vim.fn.writefile({ '{ "version": "0.0.0-test" }' }, fake .. "/node_modules/neos-fusion-ls/package.json")

  require("neos_fusion").setup({ server = { install_dir = fake } })
  local cmd, source = require("neos_fusion.lsp").resolve_cmd(tmp)
  truthy(cmd, "no cmd determined (" .. tostring(source) .. ")")
  eq(cmd[2], require("neos_fusion.lsp").wrapper_path(), "wrapper at position 2")
  eq(cmd[4], "--stdio", "--stdio")
  eq(require("neos_fusion.installer").installed_version(), "0.0.0-test", "installed version")

  require("neos_fusion").setup({ server = { install_dir = fake, sanitize_stdout = false } })
  local raw = require("neos_fusion.lsp").resolve_cmd(tmp)
  eq(#raw, 3, "three arguments without the wrapper")
  require("neos_fusion").setup({})
end)

test("client_config sets cmd_cwd and workspace_folders", function()
  local fake = tmp .. "/fakeprefix"
  require("neos_fusion").setup({ server = { install_dir = fake } })
  local c = require("neos_fusion.lsp").client_config(tmp)
  eq(c.cmd_cwd, tmp, "cmd_cwd")
  eq(c.root_dir, tmp, "root_dir")
  eq(#c.workspace_folders, 1, "exactly one workspace_folder")
  eq(c.workspace_folders[1].uri, vim.uri_from_fname(tmp), "workspace_folder uri")
  eq(c.capabilities.workspace.workspaceFolders, true, "workspaceFolders capability")
  eq(c.init_options.textDocumentSync.openClose, true, "init_options")
  require("neos_fusion").setup({})
end)

test("relative package folders are resolved to absolute paths", function()
  local fake = tmp .. "/fakeprefix"
  require("neos_fusion").setup({ server = { install_dir = fake } })
  local c = require("neos_fusion.lsp").client_config(tmp)
  local packages = c.settings.neosFusionLsp.folders.packages
  eq(packages[1], vim.fs.normalize(tmp .. "/DistributionPackages"), "first package folder absolute")
  require("neos_fusion").setup({ server = { install_dir = fake, resolve_package_folders = false } })
  local c2 = require("neos_fusion.lsp").client_config(tmp)
  eq(c2.settings.neosFusionLsp.folders.packages[1], "DistributionPackages", "unchanged when false")
  require("neos_fusion").setup({})
end)

test("custom/* notification handlers are registered", function()
  local c = require("neos_fusion.lsp").client_config(tmp)
  for _, name in ipairs({
    "custom/busy/create",
    "custom/busy/dispose",
    "custom/progressNotification/create",
    "custom/progressNotification/update",
    "custom/progressNotification/finish",
  }) do
    truthy(type(c.handlers[name]) == "function", "handler missing: " .. name)
  end
end)

io.write("\nSpecial buffers\n")
test("buf_file_path recognizes real files", function()
  local util = require("neos_fusion.util")
  vim.cmd.edit(pkg .. "/Root.fusion")
  local path = util.buf_file_path(0)
  truthy(path ~= nil, "no path returned")
  -- On macOS Neovim resolves /var to /private/var; therefore only check for an
  -- absolute path and the suffix.
  eq(path:sub(1, 1), "/", "absolute path")
  truthy(vim.endswith(path, "/Resources/Private/Fusion/Root.fusion"), "unexpected suffix: " .. path)
  eq(util.is_file(path), true, "file exists")
end)

test("buf_file_path rejects special buffers", function()
  local util = require("neos_fusion.util")

  vim.cmd("enew!")
  eq(util.buf_file_path(0), nil, "unnamed buffer")

  -- buftype set (as with checkhealth, quickfix, terminal)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "health://probe-nofile")
  vim.bo.buftype = "nofile"
  eq(util.buf_file_path(0), nil, "nofile buffer")

  -- URI scheme without buftype (as with oil.nvim)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "oil:///tmp/probe-uri")
  eq(util.buf_file_path(0), nil, "URI scheme")

  eq(util.buf_file_path(99999), nil, "invalid buffer number")
end)

test("lsp.start starts no client for special buffers", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "health://probe-start")
  vim.bo.buftype = "nofile"
  vim.bo.filetype = "fusion"
  eq(require("neos_fusion.lsp").start(0), nil, "no client for a nofile buffer")
end)

io.write("\nFiletype, syntax, indent\n")
test(".fusion is detected as fusion", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.filetype, "fusion", "filetype")
end)

test("commentstring and comments are set", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.commentstring, "// %s", "commentstring")
  truthy(vim.bo.comments:find("://", 1, true), "comments contains //")
end)

test("indentation options are set", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.shiftwidth, 4, "shiftwidth")
  eq(vim.bo.expandtab, true, "expandtab")
  eq(vim.bo.indentexpr, "GetFusionIndent()", "indentexpr")
end)

test("the Vim syntax loads without errors", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  vim.cmd("syntax on")
  vim.cmd("runtime! syntax/fusion.vim")
  eq(vim.b.current_syntax, "fusion", "current_syntax")
end)

test("syntax = false does not load the fallback syntax", function()
  require("neos_fusion").setup({ syntax = false })
  vim.cmd("enew!")
  vim.cmd.edit(root .. "/examples/component.fusion")
  eq(vim.b.current_syntax, nil, "current_syntax has to stay unset")
  require("neos_fusion").setup({})
  vim.cmd("enew!")
  vim.cmd.edit(root .. "/examples/afx.fusion")
  eq(vim.b.current_syntax, "fusion", "loaded again with syntax = true")
end)

test("the syntax recognizes prototype, AFX and Eel", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  vim.cmd("runtime! syntax/fusion.vim")
  local function group(lnum, col)
    return vim.fn.synIDattr(vim.fn.synID(lnum, col, 1), "name")
  end
  -- Line 1: prototype(...) < prototype(...)
  truthy(group(1, 1):match("^fusion"), "line 1 not recognized as Fusion: " .. group(1, 1))
  truthy(group(2, 13):match("^fusion"), "string not recognized: " .. group(2, 13))
  -- Line 4 lies inside the AFX region
  truthy(group(4, 10):match("^fusion"), "AFX not recognized: " .. group(4, 10))
end)

test("the indent function indents Fusion blocks", function()
  vim.cmd("enew!")
  vim.bo.filetype = "fusion"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "prototype(A:B) < prototype(Neos.Fusion:Component) {",
    "x = 1",
    "y = Neos.Fusion:Join {",
    "z = 2",
    "}",
    "}",
  })
  vim.cmd("normal! gg=G")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[2], "    x = 1", "line 2 indented")
  eq(lines[4], "        z = 2", "line 4 indented twice")
  eq(lines[5], "    }", "closing brace outdented")
  eq(lines[6], "}", "outer brace at column 0")
end)

test("the indent function indents AFX tags", function()
  vim.cmd("enew!")
  vim.bo.filetype = "fusion"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "renderer = afx`",
    "<div>",
    "<span>x</span>",
    "</div>",
    "`",
  })
  vim.cmd("normal! gg=G")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[2], "    <div>", "opening tag")
  eq(lines[3], "        <span>x</span>", "nested tag")
  eq(lines[4], "    </div>", "closing tag outdented")
  eq(lines[5], "`", "end of afx outdented")
end)

io.write("\nCommands\n")
test("all user commands are registered", function()
  local commands = vim.api.nvim_get_commands({})
  for _, name in ipairs({
    "NeosFusionInstallServer",
    "NeosFusionUpdateServer",
    "NeosFusionServerInfo",
    "NeosFusionStart",
    "NeosFusionStop",
    "NeosFusionRestart",
    "NeosFusionReloadWorkspace",
    "NeosFusionSetLogLevel",
    "NeosFusionLog",
    "NeosFusionDoctor",
  }) do
    truthy(commands[name] ~= nil, "command missing: " .. name)
  end
end)

test("the checkhealth module runs through", function()
  local health = require("neos_fusion.health")
  -- vim.health expects a running health buffer; here it is enough to show that
  -- check() runs through without a runtime error.
  local ok, err = pcall(function()
    vim.cmd("checkhealth neos_fusion")
  end)
  truthy(ok, "checkhealth: " .. tostring(err))
  truthy(type(health.check) == "function", "check() missing")
end)

test("Tree-sitter detection evaluates the return value", function()
  -- vim.treesitter.language.add() does not throw, it returns true or nil.
  local ok, added = pcall(vim.treesitter.language.add, "definitelynotalanguage")
  truthy(ok, "language.add() should not throw")
  eq(added, nil, "an unknown language returns nil")
end)

test("resolve_buf resolves 0 and nil to the real number", function()
  local util = require("neos_fusion.util")
  vim.cmd.edit(pkg .. "/Root.fusion")
  local real = vim.api.nvim_get_current_buf()
  -- 0 is truthy in Lua; without normalization lookups such as
  -- `client.attached_buffers[0]` always fail.
  eq(util.resolve_buf(0), real, "0 -> current number")
  eq(util.resolve_buf(nil), real, "nil -> current number")
  eq(util.resolve_buf(real), real, "a real number stays")
end)

test("doctor() runs without a client and without errors", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  local report = require("neos_fusion.lsp").doctor(0)
  truthy(type(report) == "string", "not a string")
  truthy(report:find("no client", 1, true) ~= nil, "expected a hint about the missing client:\n" .. report)
end)

io.write("\nSnippets\n")
test("engine detection returns luasnip, blink or nil", function()
  local engine = require("neos_fusion.snippets").engine()
  truthy(engine == nil or engine == "luasnip" or engine == "blink", "unexpected value: " .. tostring(engine))
end)

test("blink search paths are read correctly", function()
  local sn = require("neos_fusion.snippets")
  -- Without blink.cmp: empty list, the directory counts as not registered.
  eq(vim.tbl_count(sn.blink_search_paths()), 0, "no paths without blink")
  eq(sn.in_blink_search_paths(), false, "not registered")

  -- With a faked blink configuration.
  package.loaded["blink.cmp.config"] = {
    sources = { providers = { snippets = { opts = { search_paths = { "/x/y" } } } } },
  }
  local paths = sn.blink_search_paths()
  eq(paths[1], "/x/y", "path read")
  eq(sn.in_blink_search_paths(), false, "a foreign path does not count")

  package.loaded["blink.cmp.config"] = {
    sources = { providers = { snippets = { opts = { search_paths = { sn.snippets_dir() } } } } },
  }
  eq(sn.in_blink_search_paths(), true, "own directory recognized")
  package.loaded["blink.cmp.config"] = nil
end)

test("blink_hint names the directory and the spec", function()
  local sn = require("neos_fusion.snippets")
  local hint = sn.blink_hint()
  truthy(hint:find("saghen/blink.cmp", 1, true) ~= nil, "spec missing")
  truthy(hint:find("search_paths", 1, true) ~= nil, "search_paths missing")
  truthy(hint:find(sn.snippets_dir(), 1, true) ~= nil, "directory missing")
end)

test("setup() does not abort without a snippet engine", function()
  -- Neither LuaSnip nor blink.cmp is installed in the test environment.
  local ok, err = pcall(require("neos_fusion.snippets").setup, true)
  truthy(ok, "setup() threw: " .. tostring(err))
end)

test("capabilities contain completion even without an engine", function()
  local c = require("neos_fusion.lsp").client_config(tmp)
  truthy(vim.tbl_get(c.capabilities, "textDocument", "completion") ~= nil, "completion capability missing")
  truthy(vim.tbl_get(c.capabilities, "textDocument", "hover") ~= nil, "hover capability missing")
end)

test("snippets/fusion.json is valid JSON", function()
  local dir = require("neos_fusion.snippets").snippets_dir()
  local content = table.concat(vim.fn.readfile(dir .. "/fusion.json"), "\n")
  local decoded = vim.json.decode(content)
  truthy(decoded["Neos.Fusion:Component"] ~= nil, "Component snippet missing")
  truthy(#vim.tbl_keys(decoded) >= 15, "too few snippets")
end)

test("the example files open as fusion", function()
  for _, name in ipairs({ "component.fusion", "afx.fusion", "package-layout.fusion" }) do
    vim.cmd.edit(root .. "/examples/" .. name)
    eq(vim.bo.filetype, "fusion", name)
  end
end)

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
  io.write("\nFailed:\n")
  for _, f in ipairs(failures) do
    io.write("  - " .. f .. "\n")
  end
  vim.cmd("cq")
end
vim.cmd("qa!")
