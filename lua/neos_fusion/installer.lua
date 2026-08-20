--- Installation und Aktualisierung des Language Servers `neos-fusion-ls`.
---
--- Grundsaetze:
---  * Es wird niemals automatisch beim Start etwas heruntergeladen.
---  * Installieren, Aktualisieren und Starten sind getrennte Operationen.
---  * Es wird nichts ausserhalb des Installationsverzeichnisses geloescht.
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

M.PACKAGE = "neos-fusion-ls"

--- Pfad der Server-Einstiegsdatei innerhalb eines npm-Prefix.
---@param prefix string
---@return string
function M.main_in_prefix(prefix)
  return util.join(prefix, "node_modules", M.PACKAGE, "out", "main.js")
end

--- Pfad der vom Plugin verwalteten Installation.
---@return string
function M.managed_main()
  return M.main_in_prefix(config.install_dir())
end

---@return boolean
function M.is_installed()
  return util.is_file(M.managed_main())
end

--- Liest die installierte Version aus der package.json.
---@return string|nil
function M.installed_version()
  local pkg = util.join(config.install_dir(), "node_modules", M.PACKAGE, "package.json")
  local content = util.read_file(pkg)
  if not content then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded.version
end

local running = false

--- Fuehrt `npm install` im Installationsverzeichnis aus.
---@param version string|nil  Version oder Dist-Tag; nil = konfigurierte Version
---@param on_done fun(ok: boolean)|nil
function M.install(version, on_done)
  local cfg = config.get()
  if running then
    util.warn("Installation laeuft bereits.")
    return
  end

  local npm = cfg.server.npm
  if vim.fn.executable(npm) ~= 1 then
    util.error(("`%s` nicht gefunden. npm (Node.js) wird fuer die Installation benoetigt."):format(npm))
    if on_done then
      on_done(false)
    end
    return
  end

  local dir = config.install_dir()
  local ok_mkdir, mkdir_err = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    util.error(("Installationsverzeichnis konnte nicht angelegt werden: %s"):format(mkdir_err))
    if on_done then
      on_done(false)
    end
    return
  end

  -- Ein minimales package.json verhindert, dass npm nach oben wandert und
  -- fremde Projekte veraendert.
  local manifest = util.join(dir, "package.json")
  if not util.is_file(manifest) then
    local fd = (vim.uv or vim.loop).fs_open(manifest, "w", 420)
    if fd then
      (vim.uv or vim.loop).fs_write(fd, '{\n  "name": "neos-fusion-nvim-server",\n  "private": true\n}\n', 0)
      ;(vim.uv or vim.loop).fs_close(fd)
    end
  end

  local spec = ("%s@%s"):format(M.PACKAGE, version or cfg.server.version)
  local cmd = { npm, "install", spec, "--no-audit", "--no-fund", "--loglevel", "error" }

  running = true
  util.notify(("Installiere %s in %s ..."):format(spec, dir))
  util.spawn(cmd, { cwd = dir }, function(code, _, stderr)
    running = false
    if code == 0 and util.is_file(M.managed_main()) then
      util.notify(("%s installiert (Version %s)."):format(M.PACKAGE, M.installed_version() or "?"))
      if on_done then
        on_done(true)
      end
    else
      util.error(("Installation fehlgeschlagen (exit %d).\n%s"):format(code, (stderr or ""):sub(1, 2000)))
      if on_done then
        on_done(false)
      end
    end
  end)
end

--- Aktualisiert auf die konfigurierte Version (oder einen uebergebenen Wert).
---@param version string|nil
---@param on_done fun(ok: boolean)|nil
function M.update(version, on_done)
  M.install(version, on_done)
end

--- Menschlich lesbare Statusinformation.
---@return string
function M.info()
  local lsp = require("neos_fusion.lsp")
  local lines = {
    ("Paket:                %s"):format(M.PACKAGE),
    ("Konfig. Version:      %s"):format(config.get().server.version),
    ("Installationsordner:  %s"):format(config.install_dir()),
    ("Installiert:          %s"):format(M.is_installed() and (M.installed_version() or "ja") or "nein"),
    ("Wrapper:              %s"):format(lsp.wrapper_path()),
  }
  local cmd = lsp.resolve_cmd()
  table.insert(lines, ("Aufgeloestes cmd:     %s"):format(cmd and table.concat(cmd, " ") or "— (kein Server gefunden)"))
  return table.concat(lines, "\n")
end

return M
