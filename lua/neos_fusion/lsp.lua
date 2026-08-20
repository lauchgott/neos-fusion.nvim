--- LSP integration for the Neos Fusion language server.
---
--- `nvim-lspconfig` is deliberately not required: upstream has (as of this
--- analysis) no `fusion` server definition. The server is started through
--- `vim.lsp.start`, available since Neovim 0.10, which reuses the client for
--- the same configuration and the same root.
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

M.CLIENT_NAME = "neos_fusion_ls"

--- Errors reported once per root, so that not every buffer nags.
local reported = {}
--- Last progress text seen per client (for :NeosFusionServerInfo).
M.progress = {}

---@return string
function M.wrapper_path()
  return util.join(util.plugin_root(), "bin", "neos-fusion-ls-stdio.js")
end

--- Looks for the server entry file.
---@param root string|nil
---@return string|nil main_js
---@return string source  description of where it was found
function M.find_server_main(root)
  local cfg = config.get()
  local installer = require("neos_fusion.installer")

  if cfg.server.prefer_local and root then
    local local_main = installer.main_in_prefix(root)
    if util.is_file(local_main) then
      return local_main, "project (node_modules)"
    end
  end

  if installer.is_installed() then
    return installer.managed_main(), "plugin installation"
  end

  -- Global npm installation: the bin file has no shebang and no executable
  -- bit, but as a symlink to out/main.js it is easy to locate.
  local bin = vim.fn.exepath("neos-fusion-ls")
  if bin == "" then
    -- exepath only finds executable files; additionally look directly inside
    -- the npm bin directory.
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
      return vim.fs.normalize(real), "global npm installation"
    end
  end

  return nil, "not found"
end

--- Builds the start command.
---@param root string|nil
---@return string[]|nil cmd
---@return string source
function M.resolve_cmd(root)
  local cfg = config.get()
  if cfg.server.cmd and #cfg.server.cmd > 0 then
    return vim.deepcopy(cfg.server.cmd), "server.cmd (configuration)"
  end

  local main, source = M.find_server_main(root)
  if not main then
    return nil, source
  end

  local node = cfg.server.node
  if vim.fn.executable(node) ~= 1 then
    return nil, ("`%s` is not executable"):format(node)
  end

  if cfg.server.sanitize_stdout then
    return { node, M.wrapper_path(), main, "--stdio" }, source
  end
  return { node, main, "--stdio" }, source
end

--- Root detection for a Neos/Flow project.
---@param start_path string
---@return string|nil
function M.find_root(start_path)
  local cfg = config.get()
  local start = vim.fs.normalize(start_path)
  local dir = util.is_dir(start) and start or vim.fs.dirname(start)

  --- Does one of the markers apply to `d`?
  local function matches(d, markers)
    for _, marker in ipairs(markers or {}) do
      local p = util.join(d, marker)
      if util.exists(p) then
        -- composer.json on its own is weak: every Neos package contains a
        -- package composer.json. Only accept it if it looks like Neos/Flow.
        if marker == "composer.json" and not util.composer_looks_like_neos(p) then
          -- continue with the next marker
        else
          return true
        end
      end
    end
    return false
  end

  --- All directories from `dir` upwards that match `markers`.
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

  -- Strong markers always win, no matter how deep they sit. A `.git` further
  -- up must not outvote a Neos project living in a subdirectory.
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

--- Resolves relative package folders against the project root.
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

--- Handlers for the server's non-standard `custom/...` notifications. Without
--- them Neovim logs "unhandled notification".
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

--- Builds the complete client configuration.
---@param root string
---@return table
function M.client_config(root)
  local cfg = config.get()
  local cmd = M.resolve_cmd(root)

  local capabilities = vim.lsp.protocol.make_client_capabilities()
  -- The server initializes its workspaces exclusively from
  -- `params.workspaceFolders`; the capability has to be announced.
  capabilities.workspace = capabilities.workspace or {}
  capabilities.workspace.workspaceFolders = true
  capabilities.workspace.configuration = true

  -- Detect the completion engine. blink.cmp first (LazyVim default since v14),
  -- then nvim-cmp. Both are optional; without an engine the default
  -- capabilities stay in place.
  local ok_blink, blink = pcall(require, "blink.cmp")
  if ok_blink and type(blink.get_lsp_capabilities) == "function" then
    -- Second argument `false` = do not fill the passed table with the Neovim
    -- defaults (already done above).
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
    -- Important: the server checks relative package folders with
    -- `fs.existsSync()` against the working directory of the process.
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

--- Starts (or finds) the client for the current buffer.
---@param bufnr integer|nil
---@return integer|nil client_id
function M.start(bufnr)
  bufnr = util.resolve_buf(bufnr)
  local cfg = config.get()

  if not cfg.server.enable then
    return nil
  end

  -- Real files only: special buffers (health://, oil://, terminals) would
  -- otherwise produce a nonsensical project root.
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
        "No Neos Fusion language server found (" .. source .. ").",
        "Install:  :NeosFusionInstallServer",
        "Details:  :NeosFusionServerInfo  /  :checkhealth neos_fusion",
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

--- All clients belonging to this plugin.
---@return vim.lsp.Client[]
function M.clients()
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  return get({ name = M.CLIENT_NAME })
end

function M.stop()
  local clients = M.clients()
  if #clients == 0 then
    util.notify("No running Fusion language server.")
    return
  end
  for _, client in ipairs(clients) do
    client:stop()
  end
  util.notify(("Stopped %d client(s)."):format(#clients))
end

--- Stops all clients and restarts them for every Fusion buffer.
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
    util.notify("Language server restarted.")
  end, 500)
end

--- Sends the configuration again. The server then rebuilds all Fusion
--- workspaces (see `LanguageServer.onDidChangeConfiguration`).
function M.reload_workspace()
  local clients = M.clients()
  if #clients == 0 then
    util.notify("No running Fusion language server.")
    return
  end
  for _, client in ipairs(clients) do
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
  util.notify("Workspace reload requested.")
end

--- Sets the log level at runtime and thereby triggers a reload.
---@param level string "error"|"info"|"verbose"|"debug"
function M.set_log_level(level)
  local valid = { error = true, info = true, verbose = true, debug = true }
  if not valid[level] then
    util.error(("Invalid log level `%s` (error|info|verbose|debug)."):format(level))
    return
  end
  local clients = M.clients()
  if #clients == 0 then
    util.notify("No running Fusion language server.")
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
  util.notify(("Log level set to `%s`."):format(level))
end

local watchers = {}

--- The server does not register `workspace/didChangeWatchedFiles` itself (in
--- VSCode the client configuration `synchronize.fileEvents` took care of it).
--- The plugin therefore reports writes inside the project on its own.
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

--- Detailed diagnostics for the current buffer.
---
--- Separates the three common causes of "hover/definition returns nothing":
---   1. The server found no packages (folder names do not match).
---   2. The file lies outside the configured Fusion folders.
---   3. The cursor sits on a target the server offers nothing for.
---@param bufnr integer|nil
function M.doctor(bufnr)
  bufnr = util.resolve_buf(bufnr)
  local out = {}
  local function add_line(fmt, ...)
    table.insert(out, select("#", ...) > 0 and fmt:format(...) or fmt)
  end

  local file = util.buf_file_path(bufnr)
  add_line("File:         %s", file or "— (not a file buffer)")
  add_line("Filetype:     %s", vim.bo[bufnr].filetype)

  local clients = vim.tbl_filter(function(c)
    return c.attached_buffers and c.attached_buffers[bufnr]
  end, M.clients())

  if #clients == 0 then
    add_line("Client:       — no client attached to this buffer")
    add_line("")
    add_line("Next step: :NeosFusionStart or :NeosFusionServerInfo")
    return table.concat(out, "\n")
  end

  local client = clients[1]
  local root = client.config.root_dir
  add_line("Client:       #%d", client.id)
  add_line("Project root: %s", root or "—")

  local settings = client.settings or {}
  local folders = vim.tbl_get(settings, "neosFusionLsp", "folders") or {}

  add_line("")
  add_line("folders.packages (the server checks these paths with existsSync):")
  local found_any = false
  for _, dir in ipairs(folders.packages or {}) do
    local exists = util.is_dir(dir)
    if exists then
      found_any = true
    end
    add_line("  [%s] %s", exists and "x" or " ", dir)
  end
  if not found_any then
    add_line("  -> NO directory present. The server falls back to")
    add_line("     workspaceAsPackageFallback and only indexes the root.")
    add_line("     Fix: adjust settings.neosFusionLsp.folders.packages.")
  end

  -- Which package directories actually exist below the root?
  if root then
    local candidates = {}
    for name, type_ in vim.fs.dir(root) do
      if type_ == "directory" and not name:match("^%.") then
        table.insert(candidates, name)
      end
    end
    table.sort(candidates)
    add_line("")
    add_line("Directories in the project root: %s", table.concat(candidates, ", "))
  end

  add_line("")
  add_line("folders.fusion (Fusion folders inside a package):")
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
    add_line("  -> This file is %s one of those folders (%s)",
      matched and "INSIDE" or "NOT inside", rel)
  end

  -- Probes the server's project index. `workspace/symbol` answers from the
  -- index of all packages, not only from the open file.
  add_line("")
  local ws = client:request_sync("workspace/symbol", { query = "" }, 5000, bufnr)
  local ws_count = (ws and type(ws.result) == "table") and #ws.result or 0
  add_line("workspace/symbol (empty query): %d prototypes in the index", ws_count)
  if ws_count == 0 then
    add_line("  -> The index is empty. The server found no Fusion files.")
    add_line("     The cause is in folders.packages/folders.fusion above.")
  else
    local names = {}
    for i = 1, math.min(5, ws_count) do
      table.insert(names, tostring(ws.result[i].name))
    end
    add_line("  Examples: %s", table.concat(names, ", "))
  end

  -- Probes whether the server has parsed the open file.
  add_line("")
  local sym = client:request_sync("textDocument/documentSymbol",
    { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }, 5000, bufnr)
  local symbols = sym and sym.result or nil
  if type(symbols) == "table" and #symbols > 0 then
    add_line("documentSymbol: %d entries — the file is being parsed.", #symbols)
    add_line("  first: %s", tostring(symbols[1].name))
    add_line("  -> Parsing and indexing work. If hover still returns nothing,")
    add_line("     the cursor is not on a supported target. The server only")
    add_line("     answers for prototype names, Fusion properties, Eel helpers,")
    add_line("     resource URIs and controller/action references.")
  else
    add_line("documentSymbol: EMPTY — the server does not know this file.")
    add_line("  -> The cause is in folders.packages/folders.fusion above,")
    add_line("     not the cursor. For log details: :NeosFusionSetLogLevel debug")
    add_line("     and then :NeosFusionLog")
  end

  return table.concat(out, "\n")
end

--- Status information for :NeosFusionServerInfo / :checkhealth.
---@return string
function M.status()
  local clients = M.clients()
  if #clients == 0 then
    return "No client active."
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
