--- Configuration of neos-fusion.nvim.
---
--- `M.defaults.server.settings.neosFusionLsp` mirrors exactly the defaults of
--- the VSCode extension `SimonSchmidt.vscode-neos-fusion-lsp` (v0.3.16).
--- The language server reads the configuration only in
--- `workspace/didChangeConfiguration` and initializes its workspaces there;
--- missing keys cause runtime errors on the server side. That is why every
--- branch is fully pre-populated.
local util = require("neos_fusion.util")

local M = {}

--- Default values.
M.defaults = {
  --- Filetype detection.
  filetypes = {
    --- Detect `*.fusion` as filetype `fusion`.
    fusion = true,
    --- Additionally detect `*.afx` as `fusion`. Off by default: the extension
    --- is uncommon in Neos (see docs/ANALYSE.md).
    afx = false,
  },

  --- Load the bundled Vim syntax.
  ---   true  — always (Tree-sitter still takes precedence once it runs)
  ---   false — never; then only Tree-sitter applies
  syntax = true,

  --- Tree-sitter integration.
  treesitter = {
    --- When a Fusion file is opened, check whether the `fusion` parser is
    --- available and call `vim.treesitter.start()`.
    enable = true,
    --- Warn once per session when the parser is missing.
    notify_missing = false,
  },

  --- ftplugin behaviour.
  editor = {
    --- commentstring for Fusion. "//" or "#".
    commentstring = "// %s",
    --- Set the indentation (shiftwidth/expandtab/indentexpr).
    indent = true,
    shiftwidth = 4,
    expandtab = true,
  },

  --- Snippets.
  snippets = {
    --- Register the snippets with whichever engine is present (LuaSnip or
    --- blink.cmp). `true` additionally warns when no engine is found.
    --- The key name is `luasnip` for compatibility reasons.
    --- "auto" | true | false
    luasnip = "auto",
  },

  --- Language server integration.
  server = {
    --- Start the LSP at all.
    enable = true,

    --- Explicit command. When set, all auto-detection is skipped.
    --- Example: { "node", "/path/to/out/main.js", "--stdio" }
    cmd = nil,

    --- Node binary used for auto-detection.
    node = "node",

    --- Server version for `:NeosFusionInstallServer`.
    --- Installed as `neos-fusion-ls@<version>`.
    version = "0.3.16",

    --- npm binary for the installer.
    npm = "npm",

    --- Installation directory. Default: stdpath("data")/neos-fusion.nvim/server
    install_dir = nil,

    --- Look for a server copy installed inside the project
    --- (`<root>/node_modules/neos-fusion-ls/out/main.js`).
    prefer_local = true,

    --- Sanitize the server's stdout.
    --- The server logs with `console.log` to stdout and thereby breaks the LSP
    --- framing (the VSCode extension uses IPC instead of stdio, where this
    --- goes unnoticed). The bundled wrapper `bin/neos-fusion-ls-stdio.js`
    --- redirects console.* to stderr. Disable for debugging only.
    sanitize_stdout = true,

    --- Start automatically when a Fusion file is opened.
    autostart = true,

    --- Passed through to `vim.lsp.start`.
    on_attach = nil,
    capabilities = nil,

    --- Additional filetypes the client should attach to.
    --- The server only understands Fusion documents.
    filetypes = { "fusion" },

    --- Root detection, two-tier.
    ---
    --- `root_markers` are strong markers: they prove a Neos/Flow project.
    --- The weak markers from `root_fallback_markers` only apply when none of
    --- them is found.
    ---
    --- The difference is decisive for monorepos. If the Neos project lives in
    --- a subdirectory (e.g. `<repo>/app/`) while `.git` sits at the repository
    --- root, a single-tier list combined with `root_outermost` would pick the
    --- repository root — where the server then finds no packages.
    root_markers = {
      "flow",
      "flow.bat",
      "composer.json",
      "DistributionPackages",
      "Packages",
      "Configuration/Settings.yaml",
    },
    --- Weak markers: only used when no strong marker was found.
    root_fallback_markers = { ".git" },
    --- With several candidates on the same tier, pick the outermost
    --- directory. Matches `getOuterMostWorkspaceFolder` of the VSCode
    --- extension.
    root_outermost = true,
    --- Fallback when no marker is found: the directory of the file.
    root_fallback_to_file_dir = true,

    --- Resolve relative paths in `settings.neosFusionLsp.folders.packages`
    --- against the project root at startup.
    --- Necessary because the server checks them with `fs.existsSync()`
    --- against the working directory of the process, and the ignore filter
    --- expects absolute paths.
    resolve_package_folders = true,

    --- Report file changes as `workspace/didChangeWatchedFiles`.
    --- The server registers no watchers itself (in VSCode the client did
    --- that), but it needs the events to refresh its caches.
    watch_files = true,
    watch_patterns = { "*.fusion", "*.php", "*.yaml", "*.yml", "*.xlf" },

    --- Show the server's progress/busy notifications.
    --- The server sends non-standard `custom/...` notifications.
    progress = {
      --- Register handlers so that Neovim logs no "unhandled notification"
      --- warnings.
      handle = true,
      --- Additionally emit them via `vim.notify`.
      notify = false,
    },

    --- Must stay set: the server reads
    --- `params.initializationOptions.textDocumentSync.openClose` without any
    --- guard and otherwise fails during `initialize`.
    init_options = {
      textDocumentSync = {
        openClose = true,
      },
    },

    --- Server configuration, exactly the structure the server expects under
    --- `settings.neosFusionLsp`.
    settings = {
      neosFusionLsp = {
        folders = {
          packages = {
            "DistributionPackages",
            "Packages/Application",
            "Packages/Framework",
            "Packages/Plugins",
            "Packages/Sites",
            "Packages/Neos",
            "Packages/Carbon",
          },
          fusion = {
            "Resources/Private/Fusion",
            "Resources/Private/FusionModule",
            "Resources/Private/FusionModules",
            "Resources/Private/FusionPlugins",
            "NodeTypes",
          },
          ignore = { "Packages/Libraries" },
          workspaceAsPackageFallback = true,
          followSymbolicLinks = false,
          includeHiddenDirectories = false,
        },
        logging = {
          -- "error" | "info" | "verbose" | "debug"
          level = "info",
          inspect = false,
        },
        diagnostics = {
          enabled = true,
          enabledDiagnostics = {
            FusionProperties = true,
            ResourceUris = true,
            TagNames = true,
            EelHelperArguments = true,
            PrototypeNames = true,
            EmptyEel = true,
            ActionUri = true,
            NodeTypeDefinitions = true,
            NonParsedFusion = true,
            RootFusionConfiguration = true,
            TranslationShortHand = true,
            ParserError = true,
            AfxWithDollarEel = true,
            DuplicateStatements = true,
          },
          ignore = {
            folders = { "Packages/" },
          },
          alwaysDiagnoseChangedFile = false,
          levels = {
            -- "hint" | "info" | "warning" | "error"
            deprecations = "hint",
          },
          ignoreNodeTypes = { "Neos.Neos:Plugin" },
        },
        code = {
          deprecations = {
            fusion = {
              prototypes = {
                ["Neos.Fusion:Array"] = "Neos.Fusion:Join",
                ["Neos.Fusion:Collection"] = "Neos.Fusion:Loop",
                ["Neos.Fusion:RawCollection"] = "Neos.Fusion:Map",
                ["Neos.Fusion:RawArray"] = "Neos.Fusion:DataStructure",
                ["Neos.Fusion:UriBuilder"] = "Neos.Fusion:ActionUri",
              },
            },
          },
          actions = {
            createNodeTypeConfiguration = {
              template = "{nodeTypeName}:\n  properties:",
              detectAbstractRegEx = "(?:A|a)bstract",
            },
          },
        },
        inlayHint = {
          -- "disabled" | "literal" | "always"
          depth = "literal",
        },
        --- Only relevant for the VSCode extension; the server ignores it.
        --- Sent along for completeness.
        extensions = {
          modify = false,
        },
      },
    },
  },
}

---@type table|nil
local current = nil

--- Returns the active configuration. Without a previous `setup()` these are
--- the defaults, so that a bare `require("neos_fusion")` never fails.
---@return table
function M.get()
  if current == nil then
    current = vim.deepcopy(M.defaults)
  end
  return current
end

---@return boolean
function M.is_configured()
  return current ~= nil
end

--- Merges user options into the defaults.
---@param opts table|nil
---@return table
function M.setup(opts)
  current = util.deep_merge(M.defaults, opts or {})
  return current
end

--- Installation directory for the server managed by the plugin.
---@return string
function M.install_dir()
  local cfg = M.get()
  if cfg.server.install_dir and cfg.server.install_dir ~= "" then
    return vim.fs.normalize(cfg.server.install_dir)
  end
  return util.join(vim.fn.stdpath("data"), "neos-fusion.nvim", "server")
end

return M
