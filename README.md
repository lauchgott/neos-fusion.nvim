# neos-fusion.nvim

Neovim support for **Neos CMS**, **Neos.Fusion** and **AFX**: filetype
detection, syntax highlighting (Tree-sitter with a Vim-syntax fallback),
indentation, snippets and integration of the
[`neos-fusion-ls`](https://github.com/sjsone/neos-fusion-ls) language server.

---

## Features

| Area | Scope |
| --- | --- |
| Filetype | `.fusion` → filetype `fusion`; optionally `.afx`; Tree-sitter injection for Fusion inside PHP heredocs (`<<<FUSION`) |
| Syntax | Tree-sitter (`fusion`), otherwise the bundled `syntax/fusion.vim` covering Fusion, Eel (`${…}`), AFX tags, attributes, comments, prototypes |
| Indentation | `indent/fusion.vim` for blocks (`{}`), AFX tags and `afx\`` |
| Comments | `commentstring = "// %s"`, `comments` for `//`, `#`, `/* */` |
| LSP | Hover, goto definition, find references, document/workspace symbols, completion, code actions, CodeLens, rename, signature help, inlay hints, semantic tokens, diagnostics |
| Server installation | `:NeosFusionInstallServer` (npm, pinned version, no network access at startup) |
| Snippets | 21 Fusion/AFX snippets in VSCode format; LuaSnip automatically, blink.cmp via a search-path entry |
| Diagnostics | `:checkhealth neos_fusion`, `:NeosFusionServerInfo`, `:NeosFusionLog` |

---

## Requirements

* **Neovim 0.10 or newer** (developed and tested with 0.12)
* **Node.js** — for the language server (tested with Node 25.9; the package
  declares `engines: { node: "*" }`)
* **npm** — only for `:NeosFusionInstallServer`
* optional **nvim-treesitter** for the `fusion` parser
* optional a snippet engine: **LuaSnip** (automatic) or **blink.cmp**
  (one entry in `search_paths`, see below)
* optional a completion engine: **blink.cmp** or **nvim-cmp**
  (`cmp_nvim_lsp`) — both are detected automatically

`nvim-lspconfig` is **not** required: upstream has no `fusion` server
definition, so the plugin starts the server itself via `vim.lsp.start`.

---

## Installation with lazy.nvim

The repository root **is** the plugin root (`lua/`, `plugin/`, `ftdetect/` sit
directly below it). Both the GitHub shorthand and a local path therefore work.

### Local directory

```lua
{
  dir = "~/src/neos-fusion.nvim",   -- path to the repository itself
  -- `name` makes lazy.nvim name the plugin consistently, regardless of the
  -- directory name.
  name = "neos-fusion.nvim",
  ft = { "fusion" },
  -- No mandatory dependencies. Both entries are optional:
  --   nvim-treesitter -> better highlighting (parser `fusion`)
  --   LuaSnip         -> snippets
  dependencies = {
    { "nvim-treesitter/nvim-treesitter", optional = true },
    { "L3MON4D3/LuaSnip", optional = true },
  },
  opts = {},
}
```

### LazyVim

Under LazyVim the spec belongs in `~/.config/nvim/lua/plugins/neos-fusion.lua`;
`lua/config/lazy.lua` imports `plugins/*.lua` automatically. blink.cmp and
nvim-treesitter are already present there, so this is enough:

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

`ft` and `cmd` keep the plugin lazy even when LazyVim sets
`defaults = { lazy = false }` globally.

`ensure_installed = { "fusion" }` for nvim-treesitter is **not** worth it:
LazyVim uses the `main` branch, which no longer carries the grammar (see
below). The bundled Vim syntax takes over.

### From a GitHub repository

Use the repository name instead of `dir`; the rest of the spec stays the same:

```lua
{
  "<owner>/neos-fusion.nvim",
  ft = { "fusion" },
  opts = {},
}
```

> **Note on `ft`:** With `ft = { "fusion" }` lazy.nvim loads the plugin only
> when a Fusion file is opened. That is sufficient because detection of
> `.fusion` already happens earlier through `ftdetect/`. If you need the
> commands (`:NeosFusionInstallServer` …) without an open Fusion file, add
> `cmd = { "NeosFusionInstallServer", "NeosFusionServerInfo" }` or load the
> plugin with `lazy = false`.

### Enabling or disabling server installation

The server is **never** downloaded automatically. Three ways:

```lua
-- 1. Managed by the plugin (recommended): run :NeosFusionInstallServer once
opts = { server = { version = "0.3.16" } }

-- 2. Prefer a project-local installation
--    (npm install --save-dev neos-fusion-ls inside the project)
opts = { server = { prefer_local = true } }

-- 3. Self-built or globally installed: pin the command explicitly
opts = {
  server = {
    cmd = { "node", "/path/to/neos-fusion-ls/out/main.js", "--stdio" },
  },
}

-- Disable the LSP entirely (syntax, indent, snippets stay active)
opts = { server = { enable = false } }
```

---

## `setup()` — complete example

All values match the defaults; `setup({})` is enough for the common case. The
plugin also loads without `setup()`, in which case the same defaults apply.

```lua
require("neos_fusion").setup({
  filetypes = {
    fusion = true,                  -- *.fusion  -> filetype `fusion`
    afx = false,                    -- *.afx     -> filetype `fusion` (uncommon in Neos)
  },

  syntax = true,                    -- load the bundled Vim syntax

  treesitter = {
    enable = true,                  -- vim.treesitter.start(), if the parser exists
    notify_missing = false,         -- warn once when the parser is missing
  },

  editor = {
    commentstring = "// %s",        -- alternatively "# %s"
    indent = true,
    shiftwidth = 4,
    expandtab = true,
  },

  snippets = {
    -- Registration with LuaSnip or blink.cmp. `true` warns when no engine is
    -- found. The key name `luasnip` is historical.
    luasnip = "auto",               -- "auto" | true | false
  },

  server = {
    enable = true,
    autostart = true,
    cmd = nil,                      -- an explicit command overrides everything else
    node = "node",
    npm = "npm",
    version = "0.3.16",             -- used by :NeosFusionInstallServer
    install_dir = nil,              -- default: stdpath("data")/neos-fusion.nvim/server
    prefer_local = true,            -- prefer <root>/node_modules/neos-fusion-ls
    sanitize_stdout = true,         -- use the stdout wrapper (see below)
    filetypes = { "fusion" },

    -- strong markers; `.git` is deliberately NOT among them
    root_markers = {
      "flow", "flow.bat", "composer.json",
      "DistributionPackages", "Packages",
      "Configuration/Settings.yaml",
    },
    -- weak markers, only used when no strong one was found
    root_fallback_markers = { ".git" },
    root_outermost = true,
    root_fallback_to_file_dir = true,
    resolve_package_folders = true, -- resolve folders.packages to absolute paths

    watch_files = true,
    watch_patterns = { "*.fusion", "*.php", "*.yaml", "*.yml", "*.xlf" },

    progress = { handle = true, notify = false },

    on_attach = function(client, bufnr)
      local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
      end
      map("gd", vim.lsp.buf.definition, "Definition")
      map("gr", vim.lsp.buf.references, "References")
      map("K", vim.lsp.buf.hover, "Hover")
      map("<leader>rn", vim.lsp.buf.rename, "Rename")
      map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    end,
    capabilities = nil,             -- merged with the defaults

    -- Must stay set: without this value `initialize` fails.
    init_options = { textDocumentSync = { openClose = true } },

    -- Server configuration (excerpt; every branch is pre-populated)
    settings = {
      neosFusionLsp = {
        -- Careful: lists are replaced, not merged. If you set anything here,
        -- provide the complete list.
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

## Commands

| Command | Effect |
| --- | --- |
| `:NeosFusionInstallServer [version]` | Installs `neos-fusion-ls` via npm |
| `:NeosFusionUpdateServer [version]` | Installs the (new) version on top |
| `:NeosFusionServerInfo` | Paths, installed version, resolved command, running clients |
| `:NeosFusionStart` / `:NeosFusionStop` / `:NeosFusionRestart` | Control the client |
| `:NeosFusionReloadWorkspace` | Re-sends the configuration → the server rebuilds its Fusion workspaces |
| `:NeosFusionSetLogLevel {level}` | `error`, `info`, `verbose`, `debug` at runtime |
| `:NeosFusionLog` | Opens the LSP log file |
| `:NeosFusionDoctor` | Diagnostics for the current buffer: which package folders exist, whether the file lives in a Fusion folder, how many prototypes are indexed, whether the server knows the file |
| `:checkhealth neos_fusion` | Full diagnostics |

---

## Root detection

Two-tier, walking upwards from the opened file:

1. **strong markers** (`server.root_markers`): `flow`, `flow.bat`,
   `composer.json`, `DistributionPackages`, `Packages`,
   `Configuration/Settings.yaml`
2. **weak markers** (`server.root_fallback_markers`): `.git` — only when
   tier 1 found nothing

A `composer.json` only counts if it mentions `neos/neos`, `neos/flow`,
`neos/fusion` or `typo3/flow`. That keeps the `composer.json` of a single
package (`DistributionPackages/Vendor.Site/composer.json`) from being mistaken
for the project root.

Within a tier the **outermost** match wins by default
(`root_outermost = true`) — analogous to `getOuterMostWorkspaceFolder` in the
VSCode extension.

### Why two tiers

In monorepos the Neos project often lives in a subdirectory while `.git` sits
at the repository root:

```text
repo/
├── .git/                     <- weak marker only
├── ci/  deployment/  docs/
└── app/                      <- strong markers: composer.json, flow, Packages
    ├── composer.json
    ├── flow
    ├── DistributionPackages/
    └── Packages/
```

A single-tier list combined with `root_outermost` would pick `repo/` here —
none of the `folders.packages` exist there, the server indexes nothing, and
hover as well as goto definition stay empty. With the two-tier rule `app/`
wins. Verify with `:NeosFusionDoctor`.

The server needs the project root because it searches `folders.packages`
relative to it.

---

## Tree-sitter and fallback syntax

### State of the grammar

The grammar [`jirgn/tree-sitter-fusion`](https://gitlab.com/jirgn/tree-sitter-fusion)
(MIT, last release 2021) exists, but nvim-treesitter only carries it on the old
`master` branch:

| nvim-treesitter | parser `fusion` | `queries/fusion/` |
| --- | --- | --- |
| `master` (old) | present, maintainer `@jirgn` | present |
| `main` (current, used by LazyVim among others) | **removed** | **removed** |

On `main`, `:TSInstall fusion` therefore reports
`skipping unsupported language: fusion`. That is expected and not an error.

**Consequence:** the default path for highlighting is the bundled
`syntax/fusion.vim`. If you want Tree-sitter, you need nvim-treesitter on
`master` — the plugin then picks it up automatically
(`treesitter.enable = true`) and uses the queries shipped there. The plugin
does not provide Fusion queries of its own.

The only query file shipped is `after/queries/php/injections.scm` (additive via
`;; extends`, always active): it injects Fusion into PHP heredocs with the
identifier `FUSION` or `AFX`. The rule is deliberately narrow — it only
triggers on exactly those identifiers and only when the `fusion` parser is
installed. This is not an established Neos pattern; AFX lives in `.fusion`
files.

`syntax/fusion.vim` was developed from scratch and covers prototypes, paths,
operators (`=`, `<`, `>`), meta properties (`@if`, `@process`, …), Eel
expressions, AFX tags including attributes, strings, numbers, booleans, `null`
as well as `//`, `#` and `/* */` comments. Strings, Eel and AFX are regions so
that comment patterns cannot bleed into literals.

**Measured limit of the grammar:** the parser was compiled locally and checked
against individual constructs. Multi-line AFX tags, attribute expressions,
spread, meta attributes, nested components and Eel all parse cleanly;
**AFX comments `{/* … */}` produce a parser error**. The Vim syntax handles
that case. Details: [`docs/ANALYSE.md`](docs/ANALYSE.md).

---

## Snippets

`snippets/fusion.json` in VSCode format, among others:

| Prefix | Content |
| --- | --- |
| `component` | `Neos.Fusion:Component` with an AFX renderer |
| `contentcomponent` | `Neos.Neos:ContentComponent` |
| `prototype`, `extend` | Define or extend a prototype |
| `renderer`, `eel` | AFX renderer, Eel expression |
| `join`, `loop`, `map`, `datastructure`, `case`, `tag`, `value` | Fusion objects (current names, no deprecated variants) |
| `@if`, `@process`, `@context`, `@apply` | Meta properties |
| `resource`, `translate` | Resource URI, translation |
| `ignore`, `ignoreblock` | `@fusion-ignore` for server diagnostics |

**LuaSnip**: registered automatically, nothing to do.

**blink.cmp**: needs configuration. blink does **not** scan the runtimepath —
according to `blink/cmp/sources/snippets/default/registry.lua` it uses
`search_paths = { stdpath("config") .. "/snippets" }` plus runtimepath entries
whose path matches `friendly.snippets`. A plugin directory is therefore never
found automatically, and the plugin cannot fix that after the fact: blink
builds its snippet registry once at setup time, i.e. before an `ft`-lazy plugin
even exists.

So add this to the blink spec:

```lua
{
  "saghen/blink.cmp",
  opts = function(_, opts)
    local dir = require("neos_fusion.snippets").snippets_dir()
    opts.sources = opts.sources or {}
    opts.sources.providers = opts.sources.providers or {}
    local provider = opts.sources.providers.snippets or {}
    provider.opts = provider.opts or {}
    local paths = provider.opts.search_paths
      or { vim.fn.stdpath("config") .. "/snippets" }
    if not vim.tbl_contains(paths, dir) then
      table.insert(paths, dir)
    end
    provider.opts.search_paths = paths
    opts.sources.providers.snippets = provider
  end,
}
```

Then **restart** Neovim — `:Lazy reload` is not enough, because the registry is
only built at setup. `:checkhealth neos_fusion` confirms the entry; otherwise
it shows the search paths that are actually set. The `require` loads the plugin
at startup; if you want to avoid that, hardcode the path instead.

Other engines can pull in the directory directly:

```lua
require("luasnip.loaders.from_vscode").lazy_load({
  paths = { require("neos_fusion.snippets").snippets_dir() },
})
```

---

## Textobjects

The plugin ships **no** textobjects of its own. Without Tree-sitter,
textobjects for prototype blocks and AFX elements would be too fragile (nested
backticks, multi-line tags, Eel inside attributes), and with Tree-sitter
`nvim-treesitter-textobjects` already provides a better solution:

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

**First step:** `:checkhealth neos_fusion` for the installation,
`:NeosFusionDoctor` for a specific project.

The server only answers for certain targets: prototype names, Fusion
properties, Eel helpers, resource URIs, controller/action references. So `K`
showing "no information available" on a string literal or an arbitrary word is
normal, not a bug.

| Symptom | Cause / fix |
| --- | --- |
| "No Neos Fusion language server found" | Run `:NeosFusionInstallServer` or set `server.cmd` |
| Server starts, but hover/definition return nothing | **Run `:NeosFusionDoctor` first.** It distinguishes: (a) `workspace/symbol` = 0 and no `folders.packages` directory present → wrong project root or different folder names, (b) folders present but the file is outside `folders.fusion`, (c) index populated → the cursor was not on a supported target |
| "No Packages found" | The project uses different folder names. Extend `settings.neosFusionLsp.folders.packages` |
| No diagnostics in `Packages/` | Intended: `diagnostics.ignore.folders` defaults to `Packages/`. With `alwaysDiagnoseChangedFile = true` changed files are checked anyway |
| Changes to NodeTypes.yaml or PHP have no effect | `server.watch_files` only watches `BufWritePost` in Neovim. For external changes: `:NeosFusionReloadWorkspace` |
| Server hangs after large refactorings | `:NeosFusionRestart` |
| Nothing in the log | `:NeosFusionSetLogLevel debug`, then `:NeosFusionLog`. Server logs only appear when `server.sanitize_stdout = true` |
| `./node_modules/.bin/neos-fusion-ls: permission denied` | Expected — the bin file has no shebang. Always use `node …/out/main.js --stdio` (the plugin does this automatically) |
| Highlighting breaks in long files | `:syntax sync fromstart` or install Tree-sitter |

### About the stdout wrapper

`neos-fusion-ls` logs via `console.log()` and thereby writes into the same
stream as the LSP framing (this goes unnoticed in VSCode, which uses IPC
instead of stdio). Neovim 0.12 was measured to tolerate it, but the server logs
are lost in the process.

That is why the plugin starts the server through
`bin/neos-fusion-ls-stdio.js` by default: the wrapper loads the server in the
same process and redirects `console.*` to stderr beforehand. Result: stdout
stays strictly LSP-conformant and the server logs end up in `:NeosFusionLog`.
Can be turned off with `server.sanitize_stdout = false`.

---

## Tests

```bash
./scripts/test.sh
```

Runs Lua and Node syntax checks plus the Neovim test suite. The end-to-end test
against the real server runs with:

```bash
NEOS_FUSION_LS_MAIN=/path/to/neos-fusion-ls/out/main.js ./scripts/test.sh
```

The manual checklist lives in [`docs/TESTING.md`](docs/TESTING.md).

---

## License and references

This plugin: **MIT** (see [`LICENSE`](LICENSE)).

It contains **no** source code from the reference projects. Only the interface
values a LSP client has to know were adopted (the configuration name
`neosFusionLsp`, documented defaults, `initializationOptions`). Details and
evidence: [`docs/ANALYSE.md`](docs/ANALYSE.md).

| Project | License | Role |
| --- | --- | --- |
| [sjsone/neos-fusion-ls](https://github.com/sjsone/neos-fusion-ls) | AGPL-3.0-or-later | Language server, fetched at runtime via npm, **not** bundled |
| [sjsone/vscode-neos-fusion-lsp](https://github.com/sjsone/vscode-neos-fusion-lsp) | AGPL-3.0-or-later | Reference for configuration and client behaviour |
| [cvette/intellij-neos](https://github.com/cvette/intellij-neos) | GPL-3.0-or-later | Reference for language features (no code adopted) |
| [networkteam/vscode-neos-fusion](https://github.com/networkteam/vscode-neos-fusion) | see repository | TextMate grammar, not adopted |
| [jirgn/tree-sitter-fusion](https://gitlab.com/jirgn/tree-sitter-fusion) | MIT | Tree-sitter grammar, installable through nvim-treesitter |
