-- Eigenstaendige Testsuite ohne externe Abhaengigkeiten.
-- Aufruf: nvim --clean -n -i NONE --headless -u tests/minimal_init.lua -l tests/run.lua
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
    error(("%s\n         erwartet: %s\n         erhalten: %s"):format(msg or "Werte ungleich", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function truthy(value, msg)
  if not value then
    error(msg or "Wert ist falsy", 2)
  end
end

-- Testprojekt (Neos-aehnliches Layout) in einem temporaeren Verzeichnis.
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

io.write("\nneos-fusion.nvim — Testsuite\n\n")

io.write("Modul-Laden\n")
test("require('neos_fusion') ohne setup() wirft nicht", function()
  local m = require("neos_fusion")
  truthy(type(m.setup) == "function", "setup() fehlt")
  truthy(type(m.config()) == "table", "config() liefert keine Tabelle")
end)

test("alle Submodule laden", function()
  for _, name in ipairs({ "config", "util", "lsp", "installer", "snippets", "health" }) do
    local ok, err = pcall(require, "neos_fusion." .. name)
    truthy(ok, ("Modul neos_fusion.%s: %s"):format(name, err))
  end
end)

test("setup() mit leeren Optionen", function()
  local cfg = require("neos_fusion").setup({})
  eq(cfg.server.enable, true, "server.enable")
end)

test("setup() merged tief", function()
  local cfg = require("neos_fusion").setup({
    server = { settings = { neosFusionLsp = { logging = { level = "debug" } } } },
  })
  eq(cfg.server.settings.neosFusionLsp.logging.level, "debug", "Log-Level uebernommen")
  eq(cfg.server.settings.neosFusionLsp.inlayHint.depth, "literal", "Defaults erhalten")
  require("neos_fusion").setup({})
end)

io.write("\nServer-Konfiguration\n")
test("initializationOptions enthaelt textDocumentSync.openClose", function()
  -- Ohne diesen Wert schlaegt `initialize` serverseitig fehl.
  local cfg = require("neos_fusion.config").get()
  eq(cfg.server.init_options.textDocumentSync.openClose, true, "openClose")
end)

test("settings decken alle vom Server gelesenen Zweige ab", function()
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
    truthy(value ~= nil, "fehlender Konfigurationszweig: " .. path)
  end
end)

test("alle 14 Diagnose-Schalter vorhanden", function()
  local d = require("neos_fusion.config").get().server.settings.neosFusionLsp.diagnostics.enabledDiagnostics
  eq(vim.tbl_count(d), 14, "Anzahl Diagnosen")
end)

io.write("\nRoot-Erkennung\n")
test("findet Projektwurzel ueber composer.json mit neos/neos", function()
  local lsp = require("neos_fusion.lsp")
  eq(lsp.find_root(pkg .. "/Root.fusion"), vim.fs.normalize(tmp), "Projektwurzel")
end)

test("Monorepo: starker Marker schlaegt .git weiter oben", function()
  -- Genau das Layout aus der Praxis:
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
  eq(lsp.find_root(file), vim.fs.normalize(app), "app/ statt Repo-Wurzel")
end)

test("nur .git vorhanden -> .git greift als Fallback", function()
  local repo = vim.fn.tempname()
  local deep = repo .. "/irgendwo/tief"
  vim.fn.mkdir(deep, "p")
  vim.fn.mkdir(repo .. "/.git", "p")
  local file = deep .. "/x.fusion"
  vim.fn.writefile({ "x = 1" }, file)
  eq(require("neos_fusion.lsp").find_root(file), vim.fs.normalize(repo), "Repo-Wurzel als Fallback")
end)

test("root_outermost wirkt innerhalb der starken Stufe", function()
  -- Paket-composer.json nennt ebenfalls neos/neos -> beide Ebenen sind stark.
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
  eq(lsp.find_root(file), vim.fs.normalize(app), "aeusserster starker Kandidat")

  require("neos_fusion").setup({ server = { root_outermost = false } })
  eq(lsp.find_root(file), vim.fs.normalize(package), "innerster bei root_outermost = false")
  require("neos_fusion").setup({})
end)

test("Package-composer.json allein ist keine Wurzel", function()
  local util = require("neos_fusion.util")
  eq(util.composer_looks_like_neos(tmp .. "/DistributionPackages/Vendor.Site/composer.json"), false, "Paketmanifest")
  eq(util.composer_looks_like_neos(tmp .. "/composer.json"), true, "Projektmanifest")
end)

io.write("\nKommando-Aufloesung\n")
test("meldet fehlenden Server statt zu raten", function()
  require("neos_fusion").setup({ server = { install_dir = tmp .. "/nonexistent" } })
  local cmd = require("neos_fusion.lsp").resolve_cmd(tmp)
  -- Es darf nur dann ein cmd geben, wenn tatsaechlich eine Datei existiert.
  if cmd then
    truthy(vim.uv.fs_stat(cmd[#cmd - 1]) ~= nil or vim.uv.fs_stat(cmd[2]) ~= nil, "cmd zeigt auf nicht vorhandene Datei")
  end
  require("neos_fusion").setup({})
end)

test("explizites server.cmd hat Vorrang", function()
  require("neos_fusion").setup({ server = { cmd = { "node", "/x/main.js", "--stdio" } } })
  local cmd = require("neos_fusion.lsp").resolve_cmd(tmp)
  eq(table.concat(cmd, " "), "node /x/main.js --stdio", "cmd")
  require("neos_fusion").setup({})
end)

test("Wrapper wird in das Kommando eingesetzt", function()
  local fake = tmp .. "/fakeprefix"
  vim.fn.mkdir(fake .. "/node_modules/neos-fusion-ls/out", "p")
  vim.fn.writefile({ "// fake" }, fake .. "/node_modules/neos-fusion-ls/out/main.js")
  vim.fn.writefile({ '{ "version": "0.0.0-test" }' }, fake .. "/node_modules/neos-fusion-ls/package.json")

  require("neos_fusion").setup({ server = { install_dir = fake } })
  local cmd, source = require("neos_fusion.lsp").resolve_cmd(tmp)
  truthy(cmd, "kein cmd ermittelt (" .. tostring(source) .. ")")
  eq(cmd[2], require("neos_fusion.lsp").wrapper_path(), "Wrapper an Position 2")
  eq(cmd[4], "--stdio", "--stdio")
  eq(require("neos_fusion.installer").installed_version(), "0.0.0-test", "installierte Version")

  require("neos_fusion").setup({ server = { install_dir = fake, sanitize_stdout = false } })
  local raw = require("neos_fusion.lsp").resolve_cmd(tmp)
  eq(#raw, 3, "ohne Wrapper drei Argumente")
  require("neos_fusion").setup({})
end)

test("client_config setzt cmd_cwd und workspace_folders", function()
  local fake = tmp .. "/fakeprefix"
  require("neos_fusion").setup({ server = { install_dir = fake } })
  local c = require("neos_fusion.lsp").client_config(tmp)
  eq(c.cmd_cwd, tmp, "cmd_cwd")
  eq(c.root_dir, tmp, "root_dir")
  eq(#c.workspace_folders, 1, "genau ein workspace_folder")
  eq(c.workspace_folders[1].uri, vim.uri_from_fname(tmp), "workspace_folder uri")
  eq(c.capabilities.workspace.workspaceFolders, true, "workspaceFolders-Capability")
  eq(c.init_options.textDocumentSync.openClose, true, "init_options")
  require("neos_fusion").setup({})
end)

test("relative Package-Ordner werden absolut aufgeloest", function()
  local fake = tmp .. "/fakeprefix"
  require("neos_fusion").setup({ server = { install_dir = fake } })
  local c = require("neos_fusion.lsp").client_config(tmp)
  local packages = c.settings.neosFusionLsp.folders.packages
  eq(packages[1], vim.fs.normalize(tmp .. "/DistributionPackages"), "erster Package-Ordner absolut")
  require("neos_fusion").setup({ server = { install_dir = fake, resolve_package_folders = false } })
  local c2 = require("neos_fusion.lsp").client_config(tmp)
  eq(c2.settings.neosFusionLsp.folders.packages[1], "DistributionPackages", "unveraendert bei false")
  require("neos_fusion").setup({})
end)

test("custom/*-Notification-Handler sind registriert", function()
  local c = require("neos_fusion.lsp").client_config(tmp)
  for _, name in ipairs({
    "custom/busy/create",
    "custom/busy/dispose",
    "custom/progressNotification/create",
    "custom/progressNotification/update",
    "custom/progressNotification/finish",
  }) do
    truthy(type(c.handlers[name]) == "function", "Handler fehlt: " .. name)
  end
end)

io.write("\nSonderbuffer\n")
test("buf_file_path erkennt echte Dateien", function()
  local util = require("neos_fusion.util")
  vim.cmd.edit(pkg .. "/Root.fusion")
  local path = util.buf_file_path(0)
  truthy(path ~= nil, "kein Pfad geliefert")
  -- Auf macOS loest Neovim /var zu /private/var auf; deshalb nur auf
  -- absoluten Pfad und Endung pruefen.
  eq(path:sub(1, 1), "/", "absoluter Pfad")
  truthy(vim.endswith(path, "/Resources/Private/Fusion/Root.fusion"), "unerwartetes Ende: " .. path)
  eq(util.is_file(path), true, "Datei existiert")
end)

test("buf_file_path verwirft Sonderbuffer", function()
  local util = require("neos_fusion.util")

  vim.cmd("enew!")
  eq(util.buf_file_path(0), nil, "unbenannter Buffer")

  -- buftype gesetzt (wie bei checkhealth, quickfix, Terminal)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "health://probe-nofile")
  vim.bo.buftype = "nofile"
  eq(util.buf_file_path(0), nil, "nofile-Buffer")

  -- URI-Schema ohne buftype (wie bei oil.nvim)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "oil:///tmp/probe-uri")
  eq(util.buf_file_path(0), nil, "URI-Schema")

  eq(util.buf_file_path(99999), nil, "ungueltige Buffernummer")
end)

test("lsp.start startet fuer Sonderbuffer keinen Client", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "health://probe-start")
  vim.bo.buftype = "nofile"
  vim.bo.filetype = "fusion"
  eq(require("neos_fusion.lsp").start(0), nil, "kein Client fuer nofile-Buffer")
end)

io.write("\nFiletype, Syntax, Indent\n")
test(".fusion wird als fusion erkannt", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.filetype, "fusion", "filetype")
end)

test("commentstring und comments gesetzt", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.commentstring, "// %s", "commentstring")
  truthy(vim.bo.comments:find("://", 1, true), "comments enthaelt //")
end)

test("Einrueckungsoptionen gesetzt", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  eq(vim.bo.shiftwidth, 4, "shiftwidth")
  eq(vim.bo.expandtab, true, "expandtab")
  eq(vim.bo.indentexpr, "GetFusionIndent()", "indentexpr")
end)

test("Vim-Syntax laedt ohne Fehler", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  vim.cmd("syntax on")
  vim.cmd("runtime! syntax/fusion.vim")
  eq(vim.b.current_syntax, "fusion", "current_syntax")
end)

test("syntax = false laedt die Fallback-Syntax nicht", function()
  require("neos_fusion").setup({ syntax = false })
  vim.cmd("enew!")
  vim.cmd.edit(root .. "/examples/component.fusion")
  eq(vim.b.current_syntax, nil, "current_syntax muss ungesetzt bleiben")
  require("neos_fusion").setup({})
  vim.cmd("enew!")
  vim.cmd.edit(root .. "/examples/afx.fusion")
  eq(vim.b.current_syntax, "fusion", "mit syntax = true wieder geladen")
end)

test("Syntax erkennt Prototyp, AFX und Eel", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  vim.cmd("runtime! syntax/fusion.vim")
  local function group(lnum, col)
    return vim.fn.synIDattr(vim.fn.synID(lnum, col, 1), "name")
  end
  -- Zeile 1: prototype(...) < prototype(...)
  truthy(group(1, 1):match("^fusion"), "Zeile 1 nicht als Fusion erkannt: " .. group(1, 1))
  truthy(group(2, 13):match("^fusion"), "String nicht erkannt: " .. group(2, 13))
  -- Zeile 4 liegt in der AFX-Region
  truthy(group(4, 10):match("^fusion"), "AFX nicht erkannt: " .. group(4, 10))
end)

test("Indentfunktion rueckt Fusion-Bloecke ein", function()
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
  eq(lines[2], "    x = 1", "Zeile 2 eingerueckt")
  eq(lines[4], "        z = 2", "Zeile 4 doppelt eingerueckt")
  eq(lines[5], "    }", "schliessende Klammer ausgerueckt")
  eq(lines[6], "}", "aeussere Klammer auf Spalte 0")
end)

test("Indentfunktion rueckt AFX-Tags ein", function()
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
  eq(lines[2], "    <div>", "oeffnendes Tag")
  eq(lines[3], "        <span>x</span>", "verschachteltes Tag")
  eq(lines[4], "    </div>", "schliessendes Tag ausgerueckt")
  eq(lines[5], "`", "afx-Ende ausgerueckt")
end)

io.write("\nKommandos\n")
test("alle Nutzerkommandos registriert", function()
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
    truthy(commands[name] ~= nil, "Kommando fehlt: " .. name)
  end
end)

test("checkhealth-Modul laeuft durch", function()
  local health = require("neos_fusion.health")
  -- vim.health erwartet einen laufenden Health-Buffer; hier genuegt der
  -- Nachweis, dass check() ohne Laufzeitfehler durchlaeuft.
  local ok, err = pcall(function()
    vim.cmd("checkhealth neos_fusion")
  end)
  truthy(ok, "checkhealth: " .. tostring(err))
  truthy(type(health.check) == "function", "check() fehlt")
end)

test("Tree-sitter-Erkennung wertet den Rueckgabewert aus", function()
  -- vim.treesitter.language.add() wirft nicht, sondern liefert true bzw. nil.
  local ok, added = pcall(vim.treesitter.language.add, "definitelynotalanguage")
  truthy(ok, "language.add() sollte nicht werfen")
  eq(added, nil, "unbekannte Sprache liefert nil")
end)

test("resolve_buf loest 0 und nil auf die echte Nummer auf", function()
  local util = require("neos_fusion.util")
  vim.cmd.edit(pkg .. "/Root.fusion")
  local real = vim.api.nvim_get_current_buf()
  -- 0 ist in Lua truthy; ohne Normalisierung schlagen Nachschlagen wie
  -- `client.attached_buffers[0]` immer fehl.
  eq(util.resolve_buf(0), real, "0 -> aktuelle Nummer")
  eq(util.resolve_buf(nil), real, "nil -> aktuelle Nummer")
  eq(util.resolve_buf(real), real, "echte Nummer bleibt")
end)

test("doctor() laeuft ohne Client und ohne Fehler", function()
  vim.cmd.edit(pkg .. "/Root.fusion")
  local report = require("neos_fusion.lsp").doctor(0)
  truthy(type(report) == "string", "kein String")
  truthy(report:find("kein Client", 1, true) ~= nil, "Hinweis auf fehlenden Client erwartet:\n" .. report)
end)

io.write("\nSnippets\n")
test("Engine-Erkennung liefert luasnip, blink oder nil", function()
  local engine = require("neos_fusion.snippets").engine()
  truthy(engine == nil or engine == "luasnip" or engine == "blink", "unerwarteter Wert: " .. tostring(engine))
end)

test("setup() ohne Snippet-Engine bricht nicht ab", function()
  -- In der Testumgebung ist weder LuaSnip noch blink.cmp installiert.
  local ok, err = pcall(require("neos_fusion.snippets").setup, true)
  truthy(ok, "setup() hat geworfen: " .. tostring(err))
end)

test("Capabilities enthalten Completion auch ohne Engine", function()
  local c = require("neos_fusion.lsp").client_config(tmp)
  truthy(vim.tbl_get(c.capabilities, "textDocument", "completion") ~= nil, "completion-Capability fehlt")
  truthy(vim.tbl_get(c.capabilities, "textDocument", "hover") ~= nil, "hover-Capability fehlt")
end)

test("snippets/fusion.json ist gueltiges JSON", function()
  local dir = require("neos_fusion.snippets").snippets_dir()
  local content = table.concat(vim.fn.readfile(dir .. "/fusion.json"), "\n")
  local decoded = vim.json.decode(content)
  truthy(decoded["Neos.Fusion:Component"] ~= nil, "Component-Snippet fehlt")
  truthy(#vim.tbl_keys(decoded) >= 15, "zu wenige Snippets")
end)

test("Beispieldateien werden als fusion geoeffnet", function()
  for _, name in ipairs({ "component.fusion", "afx.fusion", "package-layout.fusion" }) do
    vim.cmd.edit(root .. "/examples/" .. name)
    eq(vim.bo.filetype, "fusion", name)
  end
end)

io.write(("\n%d bestanden, %d fehlgeschlagen\n"):format(passed, failed))
if failed > 0 then
  io.write("\nFehlgeschlagen:\n")
  for _, f in ipairs(failures) do
    io.write("  - " .. f .. "\n")
  end
  vim.cmd("cq")
end
vim.cmd("qa!")
