--- Konfiguration von neos-fusion.nvim.
---
--- `M.defaults.server.settings.neosFusionLsp` bildet exakt die Defaults der
--- VSCode-Extension `SimonSchmidt.vscode-neos-fusion-lsp` (v0.3.16) nach.
--- Der Language Server liest die Konfiguration ausschliesslich in
--- `workspace/didChangeConfiguration` und initialisiert erst dort seine
--- Workspaces; fehlende Schluessel fuehren serverseitig zu Laufzeitfehlern.
--- Deshalb sind alle Zweige vollstaendig vorbelegt.
local util = require("neos_fusion.util")

local M = {}

--- Standardwerte.
M.defaults = {
  --- Dateityp-Erkennung.
  filetypes = {
    --- `*.fusion` als Filetype `fusion` erkennen.
    fusion = true,
    --- Zusaetzlich `*.afx` als `fusion` erkennen. Standardmaessig aus:
    --- die Endung ist in Neos nicht gebraeuchlich (siehe docs/ANALYSE.md).
    afx = false,
  },

  --- Mitgelieferte Vim-Syntax laden.
  ---   true  — immer (Tree-sitter hat trotzdem Vorrang, sobald es laeuft)
  ---   false — nie; dann greift ausschliesslich Tree-sitter
  syntax = true,

  --- Tree-sitter-Anbindung.
  treesitter = {
    --- Beim Oeffnen einer Fusion-Datei pruefen, ob der Parser `fusion`
    --- vorhanden ist, und `vim.treesitter.start()` aufrufen.
    enable = true,
    --- Einmalig pro Session warnen, wenn der Parser fehlt.
    notify_missing = false,
  },

  --- ftplugin-Verhalten.
  editor = {
    --- commentstring fuer Fusion. "//" oder "#".
    commentstring = "// %s",
    --- Einrueckung setzen (shiftwidth/expandtab/indentexpr).
    indent = true,
    shiftwidth = 4,
    expandtab = true,
  },

  --- Snippets.
  snippets = {
    --- Snippets bei der vorhandenen Engine registrieren (LuaSnip oder
    --- blink.cmp). `true` warnt zusaetzlich, wenn keine Engine gefunden wird.
    --- Der Schluesselname ist aus Kompatibilitaetsgruenden `luasnip`.
    --- "auto" | true | false
    luasnip = "auto",
  },

  --- Language-Server-Anbindung.
  server = {
    --- LSP ueberhaupt starten.
    enable = true,

    --- Explizites Kommando. Wenn gesetzt, entfaellt jede Autoerkennung.
    --- Beispiel: { "node", "/pfad/zu/out/main.js", "--stdio" }
    cmd = nil,

    --- Node-Binary fuer die Autoerkennung.
    node = "node",

    --- Server-Version fuer `:NeosFusionInstallServer`.
    --- Wird als `neos-fusion-ls@<version>` installiert.
    version = "0.3.16",

    --- npm-Binary fuer den Installer.
    npm = "npm",

    --- Installationsverzeichnis. Default: stdpath("data")/neos-fusion.nvim/server
    install_dir = nil,

    --- Nach einer im Projekt installierten Server-Kopie suchen
    --- (`<root>/node_modules/neos-fusion-ls/out/main.js`).
    prefer_local = true,

    --- stdout des Servers bereinigen.
    --- Der Server loggt mit `console.log` auf stdout und zerstoert damit das
    --- LSP-Framing (die VSCode-Extension nutzt IPC statt stdio, dort faellt
    --- das nicht auf). Der mitgelieferte Wrapper `bin/neos-fusion-ls-stdio.js`
    --- leitet console.* nach stderr um. Abschalten nur zu Debugzwecken.
    sanitize_stdout = true,

    --- Automatisch beim Oeffnen einer Fusion-Datei starten.
    autostart = true,

    --- Wird an `vim.lsp.start` durchgereicht.
    on_attach = nil,
    capabilities = nil,

    --- Zusaetzliche Dateiendungen, fuer die der Client attachen soll.
    --- Der Server versteht nur Fusion-Dokumente.
    filetypes = { "fusion" },

    --- Root-Erkennung, zweistufig.
    ---
    --- `root_markers` sind starke Marker: sie belegen ein Neos-/Flow-Projekt.
    --- Nur wenn keiner davon gefunden wird, greifen die schwachen Marker aus
    --- `root_fallback_markers`.
    ---
    --- Der Unterschied ist bei Monorepos entscheidend. Liegt das Neos-Projekt
    --- in einem Unterordner (z.B. `<repo>/app/`), das `.git` aber im
    --- Repo-Wurzelverzeichnis, wuerde eine einstufige Liste zusammen mit
    --- `root_outermost` das Repo-Wurzelverzeichnis waehlen — dort findet der
    --- Server dann keine Packages.
    root_markers = {
      "flow",
      "flow.bat",
      "composer.json",
      "DistributionPackages",
      "Packages",
      "Configuration/Settings.yaml",
    },
    --- Schwache Marker: nur wenn kein starker Marker gefunden wurde.
    root_fallback_markers = { ".git" },
    --- Bei mehreren Kandidaten derselben Stufe das aeusserste Verzeichnis
    --- waehlen. Entspricht `getOuterMostWorkspaceFolder` der VSCode-Extension.
    root_outermost = true,
    --- Fallback, wenn kein Marker gefunden wird: Verzeichnis der Datei.
    root_fallback_to_file_dir = true,

    --- Relative Pfade in `settings.neosFusionLsp.folders.packages` beim Start
    --- gegen die Projektwurzel aufloesen.
    --- Notwendig, weil der Server sie mit `fs.existsSync()` gegen das
    --- Arbeitsverzeichnis des Prozesses prueft und der Ignore-Filter
    --- absolute Pfade erwartet.
    resolve_package_folders = true,

    --- Datei-Aenderungen als `workspace/didChangeWatchedFiles` melden.
    --- Der Server registriert selbst keine Watcher (das erledigte in VSCode
    --- der Client), braucht die Events aber, um Caches zu aktualisieren.
    watch_files = true,
    watch_patterns = { "*.fusion", "*.php", "*.yaml", "*.yml", "*.xlf" },

    --- Fortschritts-/Busy-Notifications des Servers anzeigen.
    --- Der Server sendet nicht standardisierte `custom/...`-Notifications.
    progress = {
      --- Handler registrieren, damit Neovim keine "unhandled notification"
      --- Warnungen protokolliert.
      handle = true,
      --- Zusaetzlich via `vim.notify` ausgeben.
      notify = false,
    },

    --- Muss gesetzt bleiben: der Server liest
    --- `params.initializationOptions.textDocumentSync.openClose` ohne
    --- Absicherung und schlaegt sonst beim `initialize` fehl.
    init_options = {
      textDocumentSync = {
        openClose = true,
      },
    },

    --- Server-Konfiguration, 1:1 die Struktur, die der Server unter
    --- `settings.neosFusionLsp` erwartet.
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
        --- Nur fuer die VSCode-Extension relevant; der Server ignoriert es.
        --- Wird der Vollstaendigkeit halber mitgesendet.
        extensions = {
          modify = false,
        },
      },
    },
  },
}

---@type table|nil
local current = nil

--- Liefert die aktive Konfiguration. Ohne vorheriges `setup()` sind es die
--- Defaults, damit ein blosses `require("neos_fusion")` nie fehlschlaegt.
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

--- Mischt Nutzeroptionen in die Defaults.
---@param opts table|nil
---@return table
function M.setup(opts)
  current = util.deep_merge(M.defaults, opts or {})
  return current
end

--- Installationsverzeichnis fuer den vom Plugin verwalteten Server.
---@return string
function M.install_dir()
  local cfg = M.get()
  if cfg.server.install_dir and cfg.server.install_dir ~= "" then
    return vim.fs.normalize(cfg.server.install_dir)
  end
  return util.join(vim.fn.stdpath("data"), "neos-fusion.nvim", "server")
end

return M
