--- LSP-Anbindung fuer den Neos Fusion Language Server.
---
--- Es wird bewusst kein `nvim-lspconfig` vorausgesetzt: upstream existiert
--- (Stand der Analyse) keine `fusion`-Serverdefinition. Gestartet wird ueber
--- `vim.lsp.start`, das ab Neovim 0.10 verfuegbar ist und den Client bei
--- gleicher Konfiguration und gleicher Root wiederverwendet.
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

M.CLIENT_NAME = "neos_fusion_ls"

--- Pro Root einmalig gemeldete Fehler, damit nicht jeder Buffer nervt.
local reported = {}
--- Zuletzt gesehener Fortschrittstext je Client (fuer :NeosFusionServerInfo).
M.progress = {}

---@return string
function M.wrapper_path()
  return util.join(util.plugin_root(), "bin", "neos-fusion-ls-stdio.js")
end

--- Sucht die Server-Einstiegsdatei.
---@param root string|nil
---@return string|nil main_js
---@return string source  Beschreibung der Fundstelle
function M.find_server_main(root)
  local cfg = config.get()
  local installer = require("neos_fusion.installer")

  if cfg.server.prefer_local and root then
    local local_main = installer.main_in_prefix(root)
    if util.is_file(local_main) then
      return local_main, "Projekt (node_modules)"
    end
  end

  if installer.is_installed() then
    return installer.managed_main(), "Plugin-Installation"
  end

  -- Globale npm-Installation: die Bin-Datei hat keinen Shebang und kein
  -- Ausfuehrungsbit, ist als Symlink auf out/main.js aber gut auffindbar.
  local bin = vim.fn.exepath("neos-fusion-ls")
  if bin == "" then
    -- exepath findet nur ausfuehrbare Dateien; zusaetzlich direkt im
    -- npm-Bin-Verzeichnis nachsehen.
    for _, candidate in ipairs(vim.fn.split(vim.env.PATH or "", ":")) do
      local link = util.join(candidate, "neos-fusion-ls")
      if util.exists(link) then
        bin = link
        break
      end
    end
  end
  if bin ~= "" and util.exists(bin) then
    local real = vim.fn.resolve(bin)
    if util.is_file(real) then
      return vim.fs.normalize(real), "globale npm-Installation"
    end
  end

  return nil, "nicht gefunden"
end

--- Baut das Startkommando.
---@param root string|nil
---@return string[]|nil cmd
---@return string source
function M.resolve_cmd(root)
  local cfg = config.get()
  if cfg.server.cmd and #cfg.server.cmd > 0 then
    return vim.deepcopy(cfg.server.cmd), "server.cmd (Konfiguration)"
  end

  local main, source = M.find_server_main(root)
  if not main then
    return nil, source
  end

  local node = cfg.server.node
  if vim.fn.executable(node) ~= 1 then
    return nil, ("`%s` nicht ausfuehrbar"):format(node)
  end

  if cfg.server.sanitize_stdout then
    return { node, M.wrapper_path(), main, "--stdio" }, source
  end
  return { node, main, "--stdio" }, source
end

--- Root-Erkennung fuer ein Neos-/Flow-Projekt.
---@param start_path string
---@return string|nil
function M.find_root(start_path)
  local cfg = config.get()
  local start = vim.fs.normalize(start_path)
  local dir = util.is_dir(start) and start or vim.fs.dirname(start)

  --- Trifft einer der Marker auf `d` zu?
  local function matches(d, markers)
    for _, marker in ipairs(markers or {}) do
      local p = util.join(d, marker)
      if util.exists(p) then
        -- composer.json allein ist schwach: eine Paket-composer.json liegt in
        -- jedem Neos-Package. Nur uebernehmen, wenn sie nach Neos/Flow aussieht.
        if marker == "composer.json" and not util.composer_looks_like_neos(p) then
          -- weiter mit dem naechsten Marker
        else
          return true
        end
      end
    end
    return false
  end

  --- Alle Verzeichnisse von `dir` aufwaerts, die auf `markers` passen.
  local function collect(markers)
    local found = {}
    local current = dir
    local previous = nil
    while current and current ~= previous do
      if matches(current, markers) then
        table.insert(found, current)
      end
      previous = current
      current = vim.fs.dirname(current)
    end
    return found
  end

  local function pick(list)
    if #list == 0 then
      return nil
    end
    return cfg.server.root_outermost and list[#list] or list[1]
  end

  -- Starke Marker gewinnen immer, egal wie tief sie liegen. Ein `.git` weiter
  -- oben darf ein Neos-Projekt in einem Unterordner nicht ueberstimmen.
  local strong = pick(collect(cfg.server.root_markers))
  if strong then
    return strong
  end

  local weak = pick(collect(cfg.server.root_fallback_markers))
  if weak then
    return weak
  end

  if cfg.server.root_fallback_to_file_dir then
    return dir
  end
  return nil
end

--- Loest relative Package-Ordner gegen die Projektwurzel auf.
---@param settings table
---@param root string
---@return table
local function resolve_settings(settings, root)
  local cfg = config.get()
  local resolved = vim.deepcopy(settings)
  if not cfg.server.resolve_package_folders then
    return resolved
  end

  local folders = vim.tbl_get(resolved, "neosFusionLsp", "folders")
  if type(folders) ~= "table" or type(folders.packages) ~= "table" then
    return resolved
  end

  local out = {}
  for _, entry in ipairs(folders.packages) do
    if entry:sub(1, 1) == "/" or entry:match("^%a:[/\\]") then
      table.insert(out, vim.fs.normalize(entry))
    else
      table.insert(out, util.join(root, entry))
    end
  end
  folders.packages = out
  return resolved
end

--- Handler fuer die nicht standardisierten `custom/...`-Notifications des
--- Servers. Ohne sie protokolliert Neovim "unhandled notification".
---@param cfg table
---@return table<string, function>
local function custom_handlers(cfg)
  if not cfg.server.progress.handle then
    return {}
  end

  local function set(client_id, text)
    M.progress[client_id] = text
    if cfg.server.progress.notify and text then
      util.notify(text)
    end
  end

  return {
    ["custom/busy/create"] = function(_, result, ctx)
      local detail = type(result) == "table" and (result.configuration and result.configuration.detail) or nil
      set(ctx.client_id, detail or ("busy: " .. tostring(result and result.id)))
    end,
    ["custom/busy/dispose"] = function(_, _, ctx)
      set(ctx.client_id, nil)
    end,
    ["custom/progressNotification/create"] = function(_, result, ctx)
      set(ctx.client_id, result and result.title or "Fusion")
    end,
    ["custom/progressNotification/update"] = function(_, result, ctx)
      local payload = result and result.payload or {}
      if payload.message then
        set(ctx.client_id, payload.message)
      end
    end,
    ["custom/progressNotification/finish"] = function(_, _, ctx)
      set(ctx.client_id, nil)
    end,
  }
end

--- Baut die vollstaendige Client-Konfiguration.
---@param root string
---@return table
function M.client_config(root)
  local cfg = config.get()
  local cmd = M.resolve_cmd(root)

  local capabilities = vim.lsp.protocol.make_client_capabilities()
  -- Der Server initialisiert seine Workspaces ausschliesslich aus
  -- `params.workspaceFolders`; die Faehigkeit muss angekuendigt werden.
  capabilities.workspace = capabilities.workspace or {}
  capabilities.workspace.workspaceFolders = true
  capabilities.workspace.configuration = true

  -- Completion-Engine erkennen. blink.cmp zuerst (LazyVim-Default ab v14),
  -- danach nvim-cmp. Beide sind optional; ohne Engine bleiben die
  -- Standard-Capabilities.
  local ok_blink, blink = pcall(require, "blink.cmp")
  if ok_blink and type(blink.get_lsp_capabilities) == "function" then
    -- Zweites Argument `false` = die uebergebene Tabelle nicht mit den
    -- Neovim-Defaults auffuellen (das haben wir oben schon getan).
    local ok_caps, merged = pcall(blink.get_lsp_capabilities, capabilities, false)
    if ok_caps and type(merged) == "table" then
      capabilities = merged
    end
  else
    local ok_cmp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
    if ok_cmp then
      capabilities = vim.tbl_deep_extend("force", capabilities, cmp_lsp.default_capabilities())
    end
  end
  if cfg.server.capabilities then
    capabilities = vim.tbl_deep_extend("force", capabilities, cfg.server.capabilities)
  end

  return {
    name = M.CLIENT_NAME,
    cmd = cmd,
    -- Wichtig: relative Package-Ordner prueft der Server mit
    -- `fs.existsSync()` gegen das Arbeitsverzeichnis des Prozesses.
    cmd_cwd = root,
    root_dir = root,
    workspace_folders = {
      { uri = vim.uri_from_fname(root), name = vim.fs.basename(root) },
    },
    init_options = vim.deepcopy(cfg.server.init_options),
    settings = resolve_settings(cfg.server.settings, root),
    capabilities = capabilities,
    handlers = custom_handlers(cfg),
    on_attach = cfg.server.on_attach,
  }
end

--- Startet (oder findet) den Client fuer den aktuellen Buffer.
---@param bufnr integer|nil
---@return integer|nil client_id
function M.start(bufnr)
  bufnr = util.resolve_buf(bufnr)
  local cfg = config.get()

  if not cfg.server.enable then
    return nil
  end

  -- Nur echte Dateien: Sonderbuffer (health://, oil://, Terminals) wuerden
  -- sonst eine unsinnige Projektwurzel erzeugen.
  local fname = util.buf_file_path(bufnr)
  if not fname then
    return nil
  end

  local root = M.find_root(fname)
  if not root then
    return nil
  end

  local cmd, source = M.resolve_cmd(root)
  if not cmd then
    if not reported[root] then
      reported[root] = true
      util.error(table.concat({
        "Kein Neos-Fusion-Language-Server gefunden (" .. source .. ").",
        "Installation:  :NeosFusionInstallServer",
        "Details:       :NeosFusionServerInfo  /  :checkhealth neos_fusion",
      }, "\n"))
    end
    return nil
  end

  local client_config = M.client_config(root)
  local client_id = vim.lsp.start(client_config, { bufnr = bufnr })

  if client_id and cfg.server.watch_files then
    M.attach_file_watcher(root, client_id)
  end
  return client_id
end

--- Alle Clients dieses Plugins.
---@return vim.lsp.Client[]
function M.clients()
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  return get({ name = M.CLIENT_NAME })
end

function M.stop()
  local clients = M.clients()
  if #clients == 0 then
    util.notify("Kein laufender Fusion-Language-Server.")
    return
  end
  for _, client in ipairs(clients) do
    client:stop()
  end
  util.notify(("%d Client(s) gestoppt."):format(#clients))
end

--- Stoppt alle Clients und startet fuer alle Fusion-Buffer neu.
function M.restart()
  local buffers = {}
  for _, client in ipairs(M.clients()) do
    for bufnr in pairs(client.attached_buffers or {}) do
      table.insert(buffers, bufnr)
    end
    client:stop(true)
  end
  reported = {}

  vim.defer_fn(function()
    if #buffers == 0 then
      buffers = vim.tbl_filter(function(b)
        return vim.bo[b].filetype == "fusion"
      end, vim.api.nvim_list_bufs())
    end
    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        M.start(bufnr)
      end
    end
    util.notify("Language Server neu gestartet.")
  end, 500)
end

--- Sendet die Konfiguration erneut. Der Server baut daraufhin alle
--- Fusion-Workspaces neu auf (siehe `LanguageServer.onDidChangeConfiguration`).
function M.reload_workspace()
  local clients = M.clients()
  if #clients == 0 then
    util.notify("Kein laufender Fusion-Language-Server.")
    return
  end
  for _, client in ipairs(clients) do
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
  util.notify("Workspace-Reload angefordert.")
end

--- Setzt das Log-Level zur Laufzeit und loest damit einen Reload aus.
---@param level string "error"|"info"|"verbose"|"debug"
function M.set_log_level(level)
  local valid = { error = true, info = true, verbose = true, debug = true }
  if not valid[level] then
    util.error(("Ungueltiges Log-Level `%s` (error|info|verbose|debug)."):format(level))
    return
  end
  local clients = M.clients()
  if #clients == 0 then
    util.notify("Kein laufender Fusion-Language-Server.")
    return
  end
  for _, client in ipairs(clients) do
    local settings = vim.deepcopy(client.settings or {})
    settings.neosFusionLsp = settings.neosFusionLsp or {}
    settings.neosFusionLsp.logging = settings.neosFusionLsp.logging or {}
    settings.neosFusionLsp.logging.level = level
    client.settings = settings
    client:notify("workspace/didChangeConfiguration", { settings = settings })
  end
  util.notify(("Log-Level auf `%s` gesetzt."):format(level))
end

local watchers = {}

--- Der Server registriert selbst keine `workspace/didChangeWatchedFiles`
--- (in VSCode uebernahm das die Client-Konfiguration `synchronize.fileEvents`).
--- Deshalb meldet das Plugin Schreibvorgaenge im Projekt selbst.
---@param root string
---@param client_id integer
function M.attach_file_watcher(root, client_id)
  if watchers[root] then
    return
  end
  local cfg = config.get()
  local group = vim.api.nvim_create_augroup("NeosFusionWatch:" .. root, { clear = true })
  watchers[root] = group

  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group,
    pattern = cfg.server.watch_patterns,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(client_id)
      if not client or client.is_stopped() then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        watchers[root] = nil
        return
      end
      local file = vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf))
      if file == "" or not vim.startswith(file, root) then
        return
      end
      client:notify("workspace/didChangeWatchedFiles", {
        changes = { { uri = vim.uri_from_fname(file), type = 2 } }, -- 2 = Changed
      })
    end,
  })
end

--- Ausfuehrliche Diagnose fuer den aktuellen Buffer.
---
--- Trennt die drei haeufigen Ursachen fuer „Hover/Definition liefert nichts":
---   1. Der Server hat keine Packages gefunden (Ordnernamen passen nicht).
---   2. Die Datei liegt ausserhalb der konfigurierten Fusion-Ordner.
---   3. Der Cursor steht auf einem Ziel, fuer das der Server nichts anbietet.
---@param bufnr integer|nil
function M.doctor(bufnr)
  bufnr = util.resolve_buf(bufnr)
  local out = {}
  local function add_line(fmt, ...)
    table.insert(out, select("#", ...) > 0 and fmt:format(...) or fmt)
  end

  local file = util.buf_file_path(bufnr)
  add_line("Datei:        %s", file or "— (kein Datei-Buffer)")
  add_line("Filetype:     %s", vim.bo[bufnr].filetype)

  local clients = vim.tbl_filter(function(c)
    return c.attached_buffers and c.attached_buffers[bufnr]
  end, M.clients())

  if #clients == 0 then
    add_line("Client:       — kein Client an diesem Buffer")
    add_line("")
    add_line("Naechster Schritt: :NeosFusionStart bzw. :NeosFusionServerInfo")
    return table.concat(out, "\n")
  end

  local client = clients[1]
  local root = client.config.root_dir
  add_line("Client:       #%d", client.id)
  add_line("Projektwurzel: %s", root or "—")

  local settings = client.settings or {}
  local folders = vim.tbl_get(settings, "neosFusionLsp", "folders") or {}

  add_line("")
  add_line("folders.packages (der Server prueft diese Pfade mit existsSync):")
  local found_any = false
  for _, dir in ipairs(folders.packages or {}) do
    local exists = util.is_dir(dir)
    if exists then
      found_any = true
    end
    add_line("  [%s] %s", exists and "x" or " ", dir)
  end
  if not found_any then
    add_line("  -> KEIN Ordner vorhanden. Der Server faellt auf")
    add_line("     workspaceAsPackageFallback zurueck und indexiert nur die Wurzel.")
    add_line("     Loesung: settings.neosFusionLsp.folders.packages anpassen.")
  end

  -- Welche Ordner mit Packages gibt es tatsaechlich unter der Wurzel?
  if root then
    local candidates = {}
    for name, type_ in vim.fs.dir(root) do
      if type_ == "directory" and not name:match("^%.") then
        table.insert(candidates, name)
      end
    end
    table.sort(candidates)
    add_line("")
    add_line("Verzeichnisse in der Projektwurzel: %s", table.concat(candidates, ", "))
  end

  add_line("")
  add_line("folders.fusion (Fusion-Ordner innerhalb eines Packages):")
  for _, dir in ipairs(folders.fusion or {}) do
    add_line("  %s", dir)
  end
  if file and root then
    local rel = file:sub(#root + 2)
    local matched = false
    for _, dir in ipairs(folders.fusion or {}) do
      if rel:find(dir, 1, true) then
        matched = true
        break
      end
    end
    add_line("  -> Diese Datei liegt %s einem dieser Ordner (%s)",
      matched and "IN" or "NICHT in", rel)
  end

  -- Sondiert den Projektindex des Servers. `workspace/symbol` antwortet aus
  -- dem Index aller Packages, nicht nur aus der offenen Datei.
  add_line("")
  local ws = client:request_sync("workspace/symbol", { query = "" }, 5000, bufnr)
  local ws_count = (ws and type(ws.result) == "table") and #ws.result or 0
  add_line("workspace/symbol (leere Query): %d Prototypen im Index", ws_count)
  if ws_count == 0 then
    add_line("  -> Der Index ist leer. Der Server hat keine Fusion-Dateien")
    add_line("     gefunden. Ursache liegt in folders.packages/folders.fusion oben.")
  else
    local names = {}
    for i = 1, math.min(5, ws_count) do
      table.insert(names, tostring(ws.result[i].name))
    end
    add_line("  Beispiele: %s", table.concat(names, ", "))
  end

  -- Sondiert, ob der Server die geoeffnete Datei geparst hat.
  add_line("")
  local sym = client:request_sync("textDocument/documentSymbol",
    { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }, 5000, bufnr)
  local symbols = sym and sym.result or nil
  if type(symbols) == "table" and #symbols > 0 then
    add_line("documentSymbol: %d Eintraege — die Datei wird geparst.", #symbols)
    add_line("  erster: %s", tostring(symbols[1].name))
    add_line("  -> Parsing und Indexierung laufen. Liefert Hover trotzdem nichts,")
    add_line("     steht der Cursor auf keinem unterstuetzten Ziel. Der Server")
    add_line("     antwortet nur auf Prototypnamen, Fusion-Properties,")
    add_line("     Eel-Helper, Resource-URIs und Controller/Action-Angaben.")
  else
    add_line("documentSymbol: LEER — der Server kennt diese Datei nicht.")
    add_line("  -> Ursache liegt in folders.packages/folders.fusion oben,")
    add_line("     nicht am Cursor. Logdetails: :NeosFusionSetLogLevel debug")
    add_line("     und dann :NeosFusionLog")
  end

  return table.concat(out, "\n")
end

--- Statusinformationen fuer :NeosFusionServerInfo / :checkhealth.
---@return string
function M.status()
  local clients = M.clients()
  if #clients == 0 then
    return "Kein Client aktiv."
  end
  local lines = {}
  for _, client in ipairs(clients) do
    table.insert(
      lines,
      ("Client #%d  root=%s  cmd=%s  progress=%s"):format(
        client.id,
        client.config.root_dir or "?",
        type(client.config.cmd) == "table" and table.concat(client.config.cmd, " ") or tostring(client.config.cmd),
        M.progress[client.id] or "—"
      )
    )
  end
  return table.concat(lines, "\n")
end

return M
