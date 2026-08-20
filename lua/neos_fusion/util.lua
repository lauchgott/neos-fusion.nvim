--- Kleine Hilfsfunktionen fuer neos-fusion.nvim.
--- Bewusst frei von Seiteneffekten beim Laden.
local M = {}

M.PLUGIN_NAME = "neos-fusion.nvim"

--- Meldungen werden immer verzoegert ausgegeben. In Autocommands (z.B.
--- `FileType`) wuerde eine direkte Fehlermeldung den restlichen Ablauf
--- abbrechen — eine fehlende Serverinstallation darf das Oeffnen einer Datei
--- aber nicht verhindern.
---@param msg string
---@param level integer|nil vim.log.levels.*
function M.notify(msg, level)
  vim.schedule(function()
    vim.notify(("[neos-fusion] %s"):format(msg), level or vim.log.levels.INFO)
  end)
end

---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- Wurzelverzeichnis dieses Plugins (das Verzeichnis ueber `lua/`).
---@return string
function M.plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- .../lua/neos_fusion/util.lua -> ...
  return vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))))
end

---@param path string
---@return boolean
function M.exists(path)
  if path == nil or path == "" then
    return false
  end
  return (vim.uv or vim.loop).fs_stat(path) ~= nil
end

---@param path string
---@return boolean
function M.is_file(path)
  local stat = (vim.uv or vim.loop).fs_stat(path or "")
  return stat ~= nil and stat.type == "file"
end

---@param path string
---@return boolean
function M.is_dir(path)
  local stat = (vim.uv or vim.loop).fs_stat(path or "")
  return stat ~= nil and stat.type == "directory"
end

---@param ... string
---@return string
function M.join(...)
  return vim.fs.normalize(table.concat({ ... }, "/"))
end

--- Liest eine Datei vollstaendig ein.
---@param path string
---@return string|nil
function M.read_file(path)
  local fd = (vim.uv or vim.loop).fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local uv = vim.uv or vim.loop
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0) or nil
  uv.fs_close(fd)
  return data
end

--- Startet einen Prozess asynchron. Nutzt `vim.system` (Neovim 0.10+) und
--- faellt sonst auf `jobstart` zurueck.
---@param cmd string[]
---@param opts table|nil { cwd = string }
---@param on_exit fun(code: integer, stdout: string, stderr: string)
function M.spawn(cmd, opts, on_exit)
  opts = opts or {}
  if vim.system then
    vim.system(cmd, { cwd = opts.cwd, text = true }, function(res)
      vim.schedule(function()
        on_exit(res.code, res.stdout or "", res.stderr or "")
      end)
    end)
    return
  end

  local out, err = {}, {}
  vim.fn.jobstart(cmd, {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      vim.list_extend(out, data or {})
    end,
    on_stderr = function(_, data)
      vim.list_extend(err, data or {})
    end,
    on_exit = function(_, code)
      on_exit(code, table.concat(out, "\n"), table.concat(err, "\n"))
    end,
  })
end

--- Loest `nil` und die Kurzform `0` auf die echte Buffernummer auf.
--- Wichtig, weil `0` in Lua truthy ist: `bufnr or current` haette `0`
--- durchgelassen, und Nachschlagen wie `client.attached_buffers[0]` schlaegt
--- damit immer fehl.
---@param bufnr integer|nil
---@return integer
function M.resolve_buf(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

--- Prueft, ob ein Buffer eine echte Datei auf der Platte ist.
--- Schliesst Sonderbuffer aus: `health://`, `oil://`, `fugitive://`,
--- Terminals, Quickfix, unbenannte Buffer.
---@param bufnr integer
---@return string|nil path  normalisierter Pfad oder nil
function M.buf_file_path(bufnr)
  bufnr = M.resolve_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if vim.bo[bufnr].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  -- URI-Schema (z.B. `oil:///pfad`) ist keine Datei im Dateisystem.
  if name:match("^%a[%w+.-]*://") then
    return nil
  end
  return vim.fs.normalize(name)
end

--- Sucht aufwaerts ab `start` nach dem ersten Verzeichnis, fuer das `matcher`
--- true liefert.
---@param start string
---@param matcher fun(dir: string): boolean
---@return string|nil
function M.find_upwards(start, matcher)
  local dir = vim.fs.normalize(start)
  local previous = nil
  while dir and dir ~= previous do
    if matcher(dir) then
      return dir
    end
    previous = dir
    dir = vim.fs.dirname(dir)
  end
  return nil
end

--- Prueft, ob eine composer.json nach einem Neos-/Flow-Projekt aussieht.
---@param composer_json_path string
---@return boolean
function M.composer_looks_like_neos(composer_json_path)
  local content = M.read_file(composer_json_path)
  if not content then
    return false
  end
  -- Bewusst kein JSON-Parsing: eine einfache Suche genuegt und ist robust
  -- gegenueber kaputten oder sehr grossen Dateien.
  return content:find("neos/neos", 1, true) ~= nil
    or content:find("neos/flow", 1, true) ~= nil
    or content:find("neos/fusion", 1, true) ~= nil
    or content:find("typo3/flow", 1, true) ~= nil
end

--- Tiefes, nicht destruktives Mergen von Tabellen (Listen werden ersetzt).
---@param base table
---@param override table|nil
---@return table
function M.deep_merge(base, override)
  return vim.tbl_deep_extend("force", vim.deepcopy(base), override or {})
end

return M
