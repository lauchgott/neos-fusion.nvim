--- Installation and updating of the `neos-fusion-ls` language server.
---
--- Principles:
---  * Nothing is ever downloaded automatically at startup.
---  * Installing, updating and starting are separate operations.
---  * Nothing outside the installation directory is deleted.
local config = require("neos_fusion.config")
local util = require("neos_fusion.util")

local M = {}

M.PACKAGE = "neos-fusion-ls"

--- Path of the server entry file inside an npm prefix.
---@param prefix string
---@return string
function M.main_in_prefix(prefix)
  return util.join(prefix, "node_modules", M.PACKAGE, "out", "main.js")
end

--- Path of the installation managed by the plugin.
---@return string
function M.managed_main()
  return M.main_in_prefix(config.install_dir())
end

---@return boolean
function M.is_installed()
  return util.is_file(M.managed_main())
end

--- Reads the installed version from package.json.
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

--- Runs `npm install` in the installation directory.
---@param version string|nil  version or dist tag; nil = the configured version
---@param on_done fun(ok: boolean)|nil
function M.install(version, on_done)
  local cfg = config.get()
  if running then
    util.warn("An installation is already running.")
    return
  end

  local npm = cfg.server.npm
  if vim.fn.executable(npm) ~= 1 then
    util.error(("`%s` not found. npm (Node.js) is required for the installation."):format(npm))
    if on_done then
      on_done(false)
    end
    return
  end

  local dir = config.install_dir()
  local ok_mkdir, mkdir_err = pcall(vim.fn.mkdir, dir, "p")
  if not ok_mkdir then
    util.error(("Could not create the installation directory: %s"):format(mkdir_err))
    if on_done then
      on_done(false)
    end
    return
  end

  -- A minimal package.json keeps npm from walking upwards and modifying
  -- unrelated projects.
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
  util.notify(("Installing %s into %s ..."):format(spec, dir))
  util.spawn(cmd, { cwd = dir }, function(code, _, stderr)
    running = false
    if code == 0 and util.is_file(M.managed_main()) then
      util.notify(("%s installed (version %s)."):format(M.PACKAGE, M.installed_version() or "?"))
      if on_done then
        on_done(true)
      end
    else
      util.error(("Installation failed (exit %d).\n%s"):format(code, (stderr or ""):sub(1, 2000)))
      if on_done then
        on_done(false)
      end
    end
  end)
end

--- Updates to the configured version (or a value passed in).
---@param version string|nil
---@param on_done fun(ok: boolean)|nil
function M.update(version, on_done)
  M.install(version, on_done)
end

--- Human-readable status information.
---@return string
function M.info()
  local lsp = require("neos_fusion.lsp")
  local lines = {
    ("Package:              %s"):format(M.PACKAGE),
    ("Configured version:   %s"):format(config.get().server.version),
    ("Installation dir:     %s"):format(config.install_dir()),
    ("Installed:            %s"):format(M.is_installed() and (M.installed_version() or "yes") or "no"),
    ("Wrapper:              %s"):format(lsp.wrapper_path()),
  }
  local cmd = lsp.resolve_cmd()
  table.insert(lines, ("Resolved cmd:         %s"):format(cmd and table.concat(cmd, " ") or "— (no server found)"))
  return table.concat(lines, "\n")
end

return M
