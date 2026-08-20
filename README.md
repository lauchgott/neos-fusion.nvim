# neos-fusion.nvim

Neovim-Unterstuetzung fuer **Neos CMS**, **Neos.Fusion** und **AFX**:
Dateityperkennung, Syntax-Highlighting (Tree-sitter mit Vim-Syntax-Fallback),
Einrueckung, Snippets und die Anbindung des Language Servers
[`neos-fusion-ls`](https://github.com/sjsone/neos-fusion-ls).

---

## Funktionsumfang

| Bereich | Umfang |
| --- | --- |
| Dateityp | `.fusion` → Filetype `fusion`; optional `.afx`; Tree-sitter-Injection fuer Fusion in PHP-Heredocs (`<<<FUSION`) |
| Syntax | Tree-sitter (`fusion`), sonst mitgelieferte `syntax/fusion.vim` mit Fusion, Eel (`${…}`), AFX-Tags, Attributen, Kommentaren, Prototypen |
| Einrueckung | `indent/fusion.vim` fuer Bloecke (`{}`), AFX-Tags und `afx\`` |
| Kommentare | `commentstring = "// %s"`, `comments` fuer `//`, `#`, `/* */` |
| LSP | Hover, Goto Definition, Find References, Document-/Workspace-Symbols, Completion, Code Actions, CodeLens, Rename, Signature Help, Inlay Hints, Semantic Tokens, Diagnostics |
| Serverinstallation | `:NeosFusionInstallServer` (npm, versionierbar, kein Netzzugriff beim Start) |
| Snippets | 21 Fusion-/AFX-Snippets im VSCode-Format, Autoregistrierung fuer LuaSnip und blink.cmp |
| Diagnose | `:checkhealth neos_fusion`, `:NeosFusionServerInfo`, `:NeosFusionLog` |

---

## Voraussetzungen

* **Neovim 0.10 oder neuer** (entwickelt und getestet mit 0.12)
* **Node.js** — fuer den Language Server (getestet mit Node 25.9; das Paket
  deklariert `engines: { node: "*" }`)
* **npm** — nur fuer `:NeosFusionInstallServer`
* optional **nvim-treesitter** fuer den Parser `fusion`
* optional eine Snippet-Engine: **LuaSnip** oder **blink.cmp**
* optional eine Completion-Engine: **blink.cmp** oder **nvim-cmp**
  (`cmp_nvim_lsp`) — beide werden automatisch erkannt

`nvim-lspconfig` wird **nicht** benoetigt: upstream existiert keine
`fusion`-Serverdefinition, das Plugin startet den Server selbst ueber
`vim.lsp.start`.

---

## Installation mit lazy.nvim

Das Repository-Wurzelverzeichnis **ist** das Plugin-Wurzelverzeichnis
(`lua/`, `plugin/`, `ftdetect/` liegen direkt darunter). Damit funktioniert
sowohl die GitHub-Kurzform als auch ein lokaler Pfad.

### Lokales Verzeichnis

```lua
{
  dir = "~/src/neos-fusion.nvim",   -- Pfad zum Repository selbst
  -- `name` sorgt dafuer, dass lazy.nvim das Plugin unabhaengig vom
  -- Verzeichnisnamen konsistent benennt.
  name = "neos-fusion.nvim",
  ft = { "fusion" },
  -- Keine Pflicht-Dependencies. Beide Eintraege sind optional:
  --   nvim-treesitter -> besseres Highlighting (Parser `fusion`)
  --   LuaSnip         -> Snippets
  dependencies = {
    { "nvim-treesitter/nvim-treesitter", optional = true },
    { "L3MON4D3/LuaSnip", optional = true },
  },
  opts = {},
}
```

### LazyVim

Unter LazyVim gehoert die Spec nach `~/.config/nvim/lua/plugins/neos-fusion.lua`;
`lua/config/lazy.lua` importiert `plugins/*.lua` automatisch. blink.cmp und
nvim-treesitter sind dort bereits vorhanden, es genuegt:

```lua
return {
  {
    dir = vim.fn.expand("~/src/neos-fusion.nvim"),
    name = "neos-fusion.nvim",
    ft = { "fusion" },
    cmd = { "NeosFusionInstallServer", "NeosFusionServerInfo" },
    opts = {},
  },
}
```

`ft` bzw. `cmd` halten das Plugin lazy, auch wenn LazyVim global
`defaults = { lazy = false }` setzt.

`ensure_installed = { "fusion" }` fuer nvim-treesitter lohnt sich **nicht**:
LazyVim nutzt den Branch `main`, der die Grammatik nicht mehr fuehrt (siehe
unten). Es greift die mitgelieferte Vim-Syntax.

### Aus einem GitHub-Repository

Statt `dir` den Repository-Namen angeben; sonst bleibt die Spec gleich:

```lua
{
  "<owner>/neos-fusion.nvim",
  ft = { "fusion" },
  opts = {},
}
```

> **Hinweis zu `ft`:** Mit `ft = { "fusion" }` laedt lazy.nvim das Plugin erst
> beim Oeffnen einer Fusion-Datei. Das genuegt, weil die Erkennung von
> `.fusion` ueber `ftdetect/` bereits vorher greift. Wer die Kommandos
> (`:NeosFusionInstallServer` …) auch ohne offene Fusion-Datei braucht, ergaenzt
> `cmd = { "NeosFusionInstallServer", "NeosFusionServerInfo" }` oder laedt das
> Plugin per `lazy = false`.

### Serverinstallation aktivieren bzw. deaktivieren

Der Server wird **nie** automatisch heruntergeladen. Drei Wege:

```lua
-- 1. Vom Plugin verwaltet (empfohlen): einmalig :NeosFusionInstallServer
opts = { server = { version = "0.3.16" } }

-- 2. Projektlokale Installation bevorzugen
--    (npm install --save-dev neos-fusion-ls im Projekt)
opts = { server = { prefer_local = true } }

-- 3. Selbst gebaut oder global installiert: Kommando fest vorgeben
opts = {
  server = {
    cmd = { "node", "/pfad/zu/neos-fusion-ls/out/main.js", "--stdio" },
  },
}

-- LSP ganz abschalten (Syntax, Indent, Snippets bleiben aktiv)
opts = { server = { enable = false } }
```

---

## `setup()` — vollstaendiges Beispiel

Alle Werte entsprechen den Defaults; `setup({})` genuegt fuer den Normalfall.
Das Plugin laesst sich auch ohne `setup()` laden, dann gelten dieselben Defaults.

```lua
require("neos_fusion").setup({
  filetypes = {
    fusion = true,                  -- *.fusion  -> filetype `fusion`
    afx = false,                    -- *.afx     -> filetype `fusion` (in Neos unueblich)
  },

  syntax = true,                    -- mitgelieferte Vim-Syntax laden

  treesitter = {
    enable = true,                  -- vim.treesitter.start(), falls Parser da
    notify_missing = false,         -- einmalig warnen, wenn Parser fehlt
  },

  editor = {
    commentstring = "// %s",        -- alternativ "# %s"
    indent = true,
    shiftwidth = 4,
    expandtab = true,
  },

  snippets = {
    -- Registrierung bei LuaSnip bzw. blink.cmp. `true` warnt, wenn keine
    -- Engine gefunden wird. Schluesselname historisch `luasnip`.
    luasnip = "auto",               -- "auto" | true | false
  },

  server = {
    enable = true,
    autostart = true,
    cmd = nil,                      -- explizites Kommando schlaegt alles andere
    node = "node",
    npm = "npm",
    version = "0.3.16",             -- fuer :NeosFusionInstallServer
    install_dir = nil,              -- default: stdpath("data")/neos-fusion.nvim/server
    prefer_local = true,            -- <root>/node_modules/neos-fusion-ls bevorzugen
    sanitize_stdout = true,         -- stdout-Wrapper verwenden (siehe unten)
    filetypes = { "fusion" },

    -- starke Marker; `.git` ist bewusst NICHT dabei
    root_markers = {
      "flow", "flow.bat", "composer.json",
      "DistributionPackages", "Packages",
      "Configuration/Settings.yaml",
    },
    -- schwache Marker, nur wenn kein starker gefunden wurde
    root_fallback_markers = { ".git" },
    root_outermost = true,
    root_fallback_to_file_dir = true,
    resolve_package_folders = true, -- folders.packages absolut aufloesen

    watch_files = true,
    watch_patterns = { "*.fusion", "*.php", "*.yaml", "*.yml", "*.xlf" },

    progress = { handle = true, notify = false },

    on_attach = function(client, bufnr)
      local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
      end
      map("gd", vim.lsp.buf.definition, "Definition")
      map("gr", vim.lsp.buf.references, "Referenzen")
      map("K", vim.lsp.buf.hover, "Hover")
      map("<leader>rn", vim.lsp.buf.rename, "Umbenennen")
      map("<leader>ca", vim.lsp.buf.code_action, "Code Action")
    end,
    capabilities = nil,             -- wird mit den Defaults gemerged

    -- Muss gesetzt bleiben: ohne diesen Wert schlaegt `initialize` fehl.
    init_options = { textDocumentSync = { openClose = true } },

    -- Server-Konfiguration (Auszug; alle Zweige sind vorbelegt)
    settings = {
      neosFusionLsp = {
        -- Achtung: Listen werden ersetzt, nicht gemischt. Wer hier etwas
        -- angibt, muss die vollstaendige Liste angeben.
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
        },
        logging = { level = "info" },        -- error|info|verbose|debug
        diagnostics = { enabled = true },
        inlayHint = { depth = "literal" },   -- disabled|literal|always
      },
    },
  },
})
```

---

## Kommandos

| Kommando | Wirkung |
| --- | --- |
| `:NeosFusionInstallServer [version]` | Installiert `neos-fusion-ls` per npm |
| `:NeosFusionUpdateServer [version]` | Installiert die (neue) Version darueber |
| `:NeosFusionServerInfo` | Pfade, installierte Version, aufgeloestes Kommando, laufende Clients |
| `:NeosFusionStart` / `:NeosFusionStop` / `:NeosFusionRestart` | Client steuern |
| `:NeosFusionReloadWorkspace` | Sendet die Konfiguration erneut → Server baut die Fusion-Workspaces neu auf |
| `:NeosFusionSetLogLevel {level}` | `error`, `info`, `verbose`, `debug` zur Laufzeit |
| `:NeosFusionLog` | Oeffnet die LSP-Logdatei |
| `:NeosFusionDoctor` | Diagnose fuer den aktuellen Buffer: welche Package-Ordner existieren, liegt die Datei in einem Fusion-Ordner, wie viele Prototypen sind indexiert, kennt der Server die Datei |
| `:checkhealth neos_fusion` | Vollstaendige Diagnose |

---

## Root-Erkennung

Zweistufig, aufwaerts ab der geoeffneten Datei:

1. **starke Marker** (`server.root_markers`): `flow`, `flow.bat`,
   `composer.json`, `DistributionPackages`, `Packages`,
   `Configuration/Settings.yaml`
2. **schwache Marker** (`server.root_fallback_markers`): `.git` — nur wenn
   Stufe 1 nichts gefunden hat

Eine `composer.json` zaehlt nur dann, wenn sie `neos/neos`, `neos/flow`,
`neos/fusion` oder `typo3/flow` erwaehnt. Damit wird die `composer.json` eines
einzelnen Packages (`DistributionPackages/Vendor.Site/composer.json`) nicht
faelschlich zur Projektwurzel.

Innerhalb einer Stufe gewinnt per Default der **aeusserste** Treffer
(`root_outermost = true`) — analog zu `getOuterMostWorkspaceFolder` der
VSCode-Extension.

### Warum zwei Stufen

Bei Monorepos liegt das Neos-Projekt oft in einem Unterordner, `.git` aber im
Repo-Wurzelverzeichnis:

```text
repo/
├── .git/                     <- nur schwacher Marker
├── ci/  deployment/  docs/
└── app/                      <- starke Marker: composer.json, flow, Packages
    ├── composer.json
    ├── flow
    ├── DistributionPackages/
    └── Packages/
```

Eine einstufige Liste zusammen mit `root_outermost` waehlt hier `repo/` —
dort existiert keiner der `folders.packages`, der Server indexiert nichts und
Hover wie Goto Definition bleiben leer. Mit der zweistufigen Regel gewinnt
`app/`. Prueflauf: `:NeosFusionDoctor`.

Der Server braucht die Projektwurzel, weil er von dort aus
`folders.packages` durchsucht.

---

## Tree-sitter und Fallback-Syntax

### Stand der Grammatik

Die Grammatik [`jirgn/tree-sitter-fusion`](https://gitlab.com/jirgn/tree-sitter-fusion)
(MIT, letzte Veroeffentlichung 2021) existiert, wird von nvim-treesitter aber
nur noch auf dem alten Branch `master` gefuehrt:

| nvim-treesitter | Parser `fusion` | `queries/fusion/` |
| --- | --- | --- |
| `master` (alt) | vorhanden, Maintainer `@jirgn` | vorhanden |
| `main` (aktuell, u.a. LazyVim) | **entfernt** | **entfernt** |

Auf `main` meldet `:TSInstall fusion` deshalb
`skipping unsupported language: fusion`. Das ist erwartet und kein Fehler.

**Konsequenz:** Standardweg fuer das Highlighting ist die mitgelieferte
`syntax/fusion.vim`. Wer Tree-sitter will, braucht nvim-treesitter auf
`master` — dann greift das Plugin automatisch darauf zu
(`treesitter.enable = true`) und nutzt die dortigen Queries. Eigene
Fusion-Queries liefert das Plugin nicht.

Mitgeliefert wird lediglich `after/queries/php/injections.scm` (additiv ueber
`;; extends`, immer aktiv): es injiziert Fusion in PHP-Heredocs mit dem
Bezeichner `FUSION` oder `AFX`. Die Regel ist bewusst eng — sie greift nur bei
genau diesen Bezeichnern und nur, wenn der Parser `fusion` installiert ist.
Ein belegtes Neos-Muster ist das nicht; AFX lebt in `.fusion`-Dateien.

`syntax/fusion.vim` ist eigenstaendig entwickelt und
deckt Prototypen, Pfade, Operatoren (`=`, `<`, `>`), Meta-Eigenschaften (`@if`,
`@process`, …), Eel-Ausdruecke, AFX-Tags samt Attributen, Strings, Zahlen,
Booleans, `null` sowie `//`-, `#`- und `/* */`-Kommentare ab. Strings, Eel und
AFX sind Regionen, damit Kommentarmuster nicht in Literale hineinlaufen.

**Gemessene Grenze der Grammatik:** Der Parser wurde selbst uebersetzt und
gegen Einzelkonstrukte geprueft. Mehrzeilige AFX-Tags, Attributausdruecke,
Spread, Meta-Attribute, verschachtelte Komponenten und Eel parsen fehlerfrei;
**AFX-Kommentare `{/* … */}` erzeugen einen Parserfehler**. Die Vim-Syntax
deckt diesen Fall ab. Details: [`docs/ANALYSE.md`](docs/ANALYSE.md).

---

## Snippets

`snippets/fusion.json` im VSCode-Format, u.a.:

| Prefix | Inhalt |
| --- | --- |
| `component` | `Neos.Fusion:Component` mit AFX-Renderer |
| `contentcomponent` | `Neos.Neos:ContentComponent` |
| `prototype`, `extend` | Prototyp definieren bzw. erweitern |
| `renderer`, `eel` | AFX-Renderer, Eel-Ausdruck |
| `join`, `loop`, `map`, `datastructure`, `case`, `tag`, `value` | Fusion-Objekte (aktuelle Namen, keine deprecated Varianten) |
| `@if`, `@process`, `@context`, `@apply` | Meta-Eigenschaften |
| `resource`, `translate` | Resource-URI, Uebersetzung |
| `ignore`, `ignoreblock` | `@fusion-ignore` fuer Server-Diagnosen |

**LuaSnip**: wird automatisch registriert.
**blink.cmp**: findet das Verzeichnis selbst ueber die runtimepath-Suche nach
`snippets/package.json` — es ist nichts zu konfigurieren.

Andere Engines koennen das Verzeichnis direkt einbinden:

```lua
require("luasnip.loaders.from_vscode").lazy_load({
  paths = { require("neos_fusion.snippets").snippets_dir() },
})
```

---

## Textobjects

Das Plugin liefert **keine** eigenen Textobjects. Ohne Tree-sitter waeren
Textobjects fuer Prototypen-Bloecke und AFX-Elemente zu fragil (verschachtelte
Backticks, mehrzeilige Tags, Eel in Attributen), und mit Tree-sitter gibt es
mit `nvim-treesitter-textobjects` bereits eine bessere Loesung:

```lua
require("nvim-treesitter.configs").setup({
  textobjects = {
    select = {
      enable = true,
      keymaps = { ["af"] = "@block.outer", ["if"] = "@block.inner" },
    },
  },
})
```

---

## Troubleshooting

**Erster Schritt:** `:checkhealth neos_fusion` fuer die Installation,
`:NeosFusionDoctor` fuer ein konkretes Projekt.

Der Server antwortet nur auf bestimmte Ziele: Prototypnamen,
Fusion-Properties, Eel-Helper, Resource-URIs, Controller/Action-Angaben.
`K` mit "no information available" auf einem Stringliteral oder einem
beliebigen Wort ist daher normal, kein Fehler.

| Symptom | Ursache / Loesung |
| --- | --- |
| „Kein Neos-Fusion-Language-Server gefunden“ | `:NeosFusionInstallServer` ausfuehren oder `server.cmd` setzen |
| Server startet, aber Hover/Definition liefern nichts | **Erst `:NeosFusionDoctor`.** Es unterscheidet: (a) `workspace/symbol` = 0 und kein `folders.packages`-Ordner vorhanden → falsche Projektwurzel oder abweichende Ordnernamen, (b) Ordner vorhanden, Datei aber ausserhalb der `folders.fusion`, (c) Index gefuellt → der Cursor stand auf keinem unterstuetzten Ziel |
| „No Packages found“ | Das Projekt nutzt andere Ordnernamen. `settings.neosFusionLsp.folders.packages` ergaenzen |
| Keine Diagnostics in `Packages/` | Beabsichtigt: `diagnostics.ignore.folders` steht per Default auf `Packages/`. Mit `alwaysDiagnoseChangedFile = true` werden geaenderte Dateien trotzdem geprueft |
| Aenderungen an NodeTypes.yaml oder PHP wirken nicht | `server.watch_files` prueft nur `BufWritePost` in Neovim. Aenderungen von aussen: `:NeosFusionReloadWorkspace` |
| Server haengt nach grossen Umbauten | `:NeosFusionRestart` |
| Nichts im Log | `:NeosFusionSetLogLevel debug`, dann `:NeosFusionLog`. Die Serverlogs erscheinen nur, wenn `server.sanitize_stdout = true` ist |
| `./node_modules/.bin/neos-fusion-ls: permission denied` | Erwartet — die Bin-Datei hat keinen Shebang. Immer `node …/out/main.js --stdio` verwenden (macht das Plugin automatisch) |
| Highlighting bricht in langen Dateien ab | `:syntax sync fromstart` oder Tree-sitter installieren |

### Zum stdout-Wrapper

`neos-fusion-ls` protokolliert ueber `console.log()` und schreibt damit in
denselben Stream wie das LSP-Framing (in VSCode faellt das nicht auf, weil
dort IPC statt stdio verwendet wird). Neovim 0.12 toleriert das gemessen zwar,
aber die Serverlogs gehen dabei verloren.

Deshalb startet das Plugin den Server per Default ueber
`bin/neos-fusion-ls-stdio.js`: der Wrapper laedt den Server im selben Prozess
und leitet vorher `console.*` nach stderr um. Ergebnis: stdout bleibt strikt
LSP-konform und die Serverlogs landen in `:NeosFusionLog`.
Abschaltbar mit `server.sanitize_stdout = false`.

---

## Tests

```bash
./scripts/test.sh
```

Fuehrt Lua- und Node-Syntaxpruefung sowie die Neovim-Testsuite aus. Der
End-to-End-Test gegen den echten Server laeuft mit:

```bash
NEOS_FUSION_LS_MAIN=/pfad/zu/neos-fusion-ls/out/main.js ./scripts/test.sh
```

Die manuelle Checkliste steht in [`docs/TESTING.md`](docs/TESTING.md).

---

## Lizenz und Referenzen

Dieses Plugin: **MIT** (siehe [`LICENSE`](LICENSE)).

Es enthaelt **keinen** Quellcode aus den Referenzprojekten. Uebernommen wurden
nur die Schnittstellenwerte, die ein LSP-Client kennen muss (Konfigurationsname
`neosFusionLsp`, dokumentierte Defaults, `initializationOptions`). Details und
Belege: [`docs/ANALYSE.md`](docs/ANALYSE.md).

| Projekt | Lizenz | Rolle |
| --- | --- | --- |
| [sjsone/neos-fusion-ls](https://github.com/sjsone/neos-fusion-ls) | AGPL-3.0-or-later | Language Server, zur Laufzeit per npm bezogen, **nicht** mitgeliefert |
| [sjsone/vscode-neos-fusion-lsp](https://github.com/sjsone/vscode-neos-fusion-lsp) | AGPL-3.0-or-later | Referenz fuer Konfiguration und Client-Verhalten |
| [cvette/intellij-neos](https://github.com/cvette/intellij-neos) | GPL-3.0-or-later | Referenz fuer Sprachmerkmale (kein Code uebernommen) |
| [networkteam/vscode-neos-fusion](https://github.com/networkteam/vscode-neos-fusion) | siehe Repository | TextMate-Grammatik, nicht uebernommen |
| [jirgn/tree-sitter-fusion](https://gitlab.com/jirgn/tree-sitter-fusion) | MIT | Tree-sitter-Grammatik, ueber nvim-treesitter installierbar |
