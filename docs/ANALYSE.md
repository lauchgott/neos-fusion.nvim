# Analyse der Referenz-Plugins

Stand der Recherche: **19.08.2026**. Alle Befunde sind mit der Quelle und dem
Grad der Verifikation gekennzeichnet:

* **nachgewiesen** – selbst ausgefuehrt oder im Quellcode gelesen
* **plausibel** – aus Metadaten/Dokumentation abgeleitet, nicht selbst ausgefuehrt
* **nicht verifizierbar** – Quelle nicht erreichbar oder nicht oeffentlich

---

## 1. Untersuchte Quellen

| Quelle | URL | Status |
| --- | --- | --- |
| JetBrains „Neos Support“ | <https://plugins.jetbrains.com/plugin/9362-neos-support> | erreichbar |
| Quellcode dazu | <https://github.com/cvette/intellij-neos> | erreichbar, GPL-3.0 |
| VSCode „Neos Fusion & AFX Language Server“ | <https://marketplace.visualstudio.com/items?itemName=SimonSchmidt.vscode-neos-fusion-lsp> | erreichbar |
| Quellcode dazu (Client + Doku) | <https://github.com/sjsone/vscode-neos-fusion-lsp> | erreichbar, AGPL-3.0-or-later |
| Quellcode Language Server | <https://github.com/sjsone/neos-fusion-ls> | erreichbar, AGPL-3.0-or-later |
| npm-Paket Language Server | <https://www.npmjs.com/package/neos-fusion-ls> | erreichbar |
| VSCode „Neos Fusion“ (Syntax) | <https://github.com/networkteam/vscode-neos-fusion> | erreichbar |
| Neos-Doku Editor Support | <https://docs.neos.io/guide/tooling/editor-support> | erreichbar |
| Tree-sitter-Grammatik | <https://gitlab.com/jirgn/tree-sitter-fusion> | ueber npm/nvim-treesitter belegt |

Die Repositories wurden **nicht geklont**, sondern ueber die GitHub-API und
`raw.githubusercontent.com` gezielt gelesen; das npm-Paket wurde installiert
und ausgefuehrt. Grund: es wird kein fremder Quellcode uebernommen, es genuegt
das Lesen der relevanten Dateien.

---

## 2. Zentrale Frage: Gibt es einen standalone Language Server?

**Antwort: Ja — nachgewiesen.**

Der Server liegt als eigenes Repository *und* als eigenes npm-Paket vor:

```
Paket:      neos-fusion-ls
Repository: https://github.com/sjsone/neos-fusion-ls
Lizenz:     AGPL-3.0-or-later
Versionen:  0.0.1, 0.3.16 (stabil), 0.3.17-pre-release (2024-08-25)
bin:        { "neos-fusion-ls": "out/main.js" }
engines:    { "node": "*" }
Build:      esbuild-Bundle (cjs, node), Abhaengigkeiten sind eingebunden
```

`src/main.ts` verwendet `createConnection(ProposedFeatures.all)` aus
`vscode-languageserver/node`. Damit wird der Transport aus `process.argv`
gelesen; `--stdio` ist unterstuetzt.

### Nachgewiesener Handshake

```console
$ npm install neos-fusion-ls@0.3.16
$ node node_modules/neos-fusion-ls/out/main.js --stdio
```

Gegen ein minimales Neos-Projekt (composer.json mit `neos/neos`,
`DistributionPackages/Vendor.Site/…/Root.fusion`) geprueft:

* `initialize` → Antwort mit `hoverProvider`, `definitionProvider`,
  `referencesProvider`, `documentSymbolProvider`, `workspaceSymbolProvider`,
  `completionProvider`, `codeActionProvider`, `codeLensProvider`,
  `renameProvider` (mit `prepareProvider`), `signatureHelpProvider`,
  `inlayHintProvider`, `semanticTokensProvider`
* `textDocument/hover` → ``` prototype(Neos.Fusion:Component) { } ```
* `textDocument/documentSymbol` → `Vendor.Site:Component.Teaser` inkl. Kindern
* `textDocument/publishDiagnostics` → geliefert

Derselbe Ablauf wurde anschliessend **aus Neovim heraus** wiederholt
(`tests/lsp_smoke.lua`, 16/16 bestanden), inkl. Diagnostic
„Tags have to be closed or the `@children` attribute has to be used“.

### Startparameter und Protokoll

| Aspekt | Befund | Status |
| --- | --- | --- |
| Transport | `--stdio` (auch `--node-ipc`, `--socket=`, via `vscode-languageserver`) | nachgewiesen |
| Runtime | Node.js. `engines: { node: "*" }`; getestet mit Node 25.9 | nachgewiesen |
| Aufruf | `node <prefix>/node_modules/neos-fusion-ls/out/main.js --stdio` | nachgewiesen |
| Bin-Symlink | **unbrauchbar**: `out/main.js` hat weder Shebang noch Ausfuehrungsbit → `./node_modules/.bin/neos-fusion-ls` scheitert mit „permission denied“ | nachgewiesen |
| Build noetig? | Nein, das npm-Paket enthaelt das fertige Bundle | nachgewiesen |

---

## 3. Fallstricke, die die Neovim-Anbindung bestimmen

Diese vier Punkte sind der Grund, warum eine naive `vim.lsp.start`-Konfiguration
nicht funktioniert.

### 3.1 `initializationOptions` ist Pflicht

`LanguageServer.onInitialize()` liest ohne Absicherung:

```ts
openClose: params.initializationOptions.textDocumentSync.openClose,
```

Ohne den Wert antwortet der Server (nachgewiesen):

```json
{"code":-32603,"message":"Request initialize failed with message: Cannot read properties of undefined (reading 'textDocumentSync')"}
```

→ Das Plugin sendet `init_options = { textDocumentSync = { openClose = true } }`.
Das entspricht exakt dem, was die VSCode-Extension in
`client/src/Extension.ts` setzt.

### 3.2 Workspaces entstehen nur aus `workspaceFolders`

`onInitialize()` legt fuer jeden Eintrag aus `params.workspaceFolders` einen
`FusionWorkspace` an. Ohne Workspace-Folder liefert **jede** Capability `null`,
weil `getWorkspaceForFileUri()` nichts findet.

→ Das Plugin setzt `root_dir` **und** explizit `workspace_folders` und
kuendigt `workspace.workspaceFolders` in den Capabilities an.

### 3.3 Initialisiert wird erst bei `workspace/didChangeConfiguration`

`FusionWorkspace.init(configuration)` wird ausschliesslich aus
`onDidChangeConfiguration()` aufgerufen. Der Server liest die Konfiguration als
`params.settings.neosFusionLsp` und greift direkt auf verschachtelte Werte zu
(z.B. `configuration.logging.level`, `configuration.folders.packages`) — ohne
Defaults.

→ Das Plugin liefert unter `server.settings.neosFusionLsp` **alle** Zweige
vollstaendig vorbelegt (uebernommen aus `contributes.configuration` der
VSCode-Extension v0.3.16). Neovim sendet `workspace/didChangeConfiguration`
automatisch, weil `settings` gesetzt ist. `:NeosFusionReloadWorkspace` sendet
es erneut und erzwingt damit einen Neuaufbau.

### 3.4 Package-Ordner werden gegen das Arbeitsverzeichnis geprueft

```ts
const packagesRootPaths = configuration.folders.packages
  .filter(path => NodeFs.existsSync(path))
```

Relative Pfade wie `DistributionPackages` werden also gegen `process.cwd()`
aufgeloest, nicht gegen den Workspace. Der nachgelagerte Ignore-Filter
vergleicht dagegen mit `NodePath.join(workspacePath, ignoreFolder)`, erwartet
also absolute Pfade.

→ Das Plugin setzt `cmd_cwd = root` **und** loest die Package-Ordner per
Default absolut gegen die Projektwurzel auf
(`server.resolve_package_folders = true`).

Daraus folgt, dass die Projektwurzel exakt stimmen muss. In der Praxis
(Monorepo mit Neos in `<repo>/app` und `.git` im Repo-Wurzelverzeichnis)
zeigte sich: eine einstufige Markerliste zusammen mit `root_outermost`
waehlt das Repo-Wurzelverzeichnis, dort existiert keiner der
`folders.packages`, der Server greift auf `workspaceAsPackageFallback`
zurueck und indexiert nichts Brauchbares — `workspace/symbol` liefert 0,
`documentSymbol` leer, Hover und Definition bleiben stumm. Deshalb ist die
Root-Erkennung zweistufig: starke Neos-Marker schlagen `.git`, unabhaengig
von der Tiefe.

### 3.5 stdout-Logging (Haertungsmassnahme)

Der Server protokolliert ueber `console.log()` (`src/common/Logging.ts`),
also in denselben Stream wie das JSON-RPC-Framing. Roh gemessen:

```
"[   INFO] <2026-…> [LanguageServer] Added FusionWorkspace fake with path /…\nContent-Length: 1017\r\n\r\n{…}"
```

`logInfo()` ist **nicht** an das Log-Level gekoppelt und feuert bereits beim
`initialize`. In VSCode faellt das nicht auf, weil dort `TransportKind.ipc`
verwendet wird (`client/src/Extension.ts`).

* **nachgewiesen:** die Verschmutzung existiert.
* **nachgewiesen:** Neovim 0.12 toleriert sie — `initialize`, Hover,
  documentSymbol funktionieren auch ohne Bereinigung, selbst mit
  `logging.level = "debug"`.
* **nachgewiesen:** ohne Bereinigung gehen die Serverlogs verloren
  (lsp.log 51 Bytes), mit Bereinigung landen sie in `lsp.log` (6456 Bytes).

→ Das Plugin startet den Server per Default ueber
`bin/neos-fusion-ls-stdio.js`. Der Wrapper laedt den Server im selben Prozess
und leitet vorher `console.*` nach stderr um. Nutzen: stdout bleibt strikt
LSP-konform (unabhaengig vom Parser des Clients) und die Serverlogs werden
ueberhaupt erst sichtbar. Abschaltbar ueber `server.sanitize_stdout = false`.

### 3.6 Keine Datei-Watcher

Der Server registriert selbst keine `workspace/didChangeWatchedFiles`; in
VSCode uebernahm das der Client ueber `synchronize.fileEvents` fuer
`**/*.php`, `**/*.fusion`, `**/*.yaml`, `**/*.yml`. Der Handler
`onDidChangeWatchedFiles()` existiert serverseitig und bedient
Fusion-/PHP-/XLF-/YAML-Aenderungen.

→ Das Plugin meldet `BufWritePost` fuer `*.fusion,*.php,*.yaml,*.yml,*.xlf`
innerhalb der Projektwurzel selbst als `workspace/didChangeWatchedFiles`
(`server.watch_files`).

### 3.7 Nicht standardisierte Notifications

Der Server sendet `custom/busy/create`, `custom/busy/dispose`,
`custom/progressNotification/create|update|finish`. Ohne Handler protokolliert
Neovim „unhandled notification“.

→ Das Plugin registriert Handler und haelt den Text fuer
`:NeosFusionServerInfo` vor (`server.progress`).

---

## 4. Erwartete Konfiguration (`neosFusionLsp`)

Vollstaendig aus `contributes.configuration` (vscode-neos-fusion-lsp v0.3.16)
uebernommen; identisch in `lua/neos_fusion/config.lua` abgebildet.

| Schluessel | Default |
| --- | --- |
| `folders.packages` | `DistributionPackages`, `Packages/Application`, `Packages/Framework`, `Packages/Plugins`, `Packages/Sites`, `Packages/Neos`, `Packages/Carbon` |
| `folders.fusion` | `Resources/Private/Fusion`, `…/FusionModule`, `…/FusionModules`, `…/FusionPlugins`, `NodeTypes` |
| `folders.ignore` | `Packages/Libraries` |
| `folders.workspaceAsPackageFallback` | `true` |
| `folders.followSymbolicLinks` | `false` |
| `folders.includeHiddenDirectories` | `false` |
| `logging.level` | `info` (`error`\|`info`\|`verbose`\|`debug`) |
| `diagnostics.enabled` | `true` |
| `diagnostics.enabledDiagnostics` | 14 Schalter, alle `true` |
| `diagnostics.ignoreNodeTypes` | `Neos.Neos:Plugin` |
| `diagnostics.levels.deprecations` | `hint` |
| `diagnostics.ignore.folders` | `Packages/` |
| `diagnostics.alwaysDiagnoseChangedFile` | `false` |
| `inlayHint.depth` | `literal` |
| `code.deprecations.fusion.prototypes` | Array→Join, Collection→Loop, RawCollection→Map, RawArray→DataStructure, UriBuilder→ActionUri |
| `code.actions.createNodeTypeConfiguration.template` | `{nodeTypeName}:\n  properties:` |
| `code.actions.createNodeTypeConfiguration.detectAbstractRegEx` | `(?:A\|a)bstract` |
| `extensions.modify` | `true` (nur VSCode-relevant; das Plugin sendet `false`) |

Die 14 Diagnosen: `FusionProperties`, `ResourceUris`, `TagNames`,
`EelHelperArguments`, `PrototypeNames`, `EmptyEel`, `ActionUri`,
`NodeTypeDefinitions`, `NonParsedFusion`, `RootFusionConfiguration`,
`TranslationShortHand`, `ParserError`, `AfxWithDollarEel`,
`DuplicateStatements`.

Die VSCode-Kommandos `neos-fusion-lsp.reload` und `neos-fusion-lsp.inspect`
sind reine Client-Kommandos: sie stoppen die Clients und starten sie neu
(`inspect` zusaetzlich mit `--inspect-brk`). Es gibt dafuer **keine**
serverseitige `workspace/executeCommand`-Entsprechung.
→ Aequivalent im Plugin: `:NeosFusionRestart`.

---

## 5. Dateitypen und Sprachmerkmale

| Frage | Befund | Status |
| --- | --- | --- |
| Fusion-Dateiendung | ausschliesslich `.fusion` (`FusionFileType.DEFAULT_EXTENSION = "fusion"`, VSCode `contributes.languages[].extensions = [".fusion"]`) | nachgewiesen |
| Gibt es `.afx`-Dateien? | **Nein.** AFX ist eine DSL *innerhalb* von Fusion. IntelliJ injiziert AFX ueber `fusionValueDsl("afx")`, es gibt keinen `.afx`-Dateityp mit Endung | nachgewiesen |
| AFX in PHP? | In keinem der drei Referenzprojekte vorgesehen. Die einzige belegte Einbettung ist AFX-in-Fusion und Eel-in-Fusion | nachgewiesen |
| Weitere relevante Dateien | `NodeTypes.yaml`, `*.xlf` (Uebersetzungen), PHP (Eel-Helper, Controller) — der Server liest sie, ist aber nur fuer Fusion-Dokumente zustaendig | nachgewiesen |
| Grammatiken | IntelliJ: JFlex/BNF (`FusionLexer.flex`, `FusionParser.bnf`, `AfxLexer.flex`, `EelLexer.flex`, `EelParser.bnf`). VSCode: TextMate-Grammatik in `networkteam/vscode-neos-fusion` | nachgewiesen |
| Parser des LSP | `ts-fusion-parser` (TypeScript-Portierung des offiziellen Fusion-Parsers) | nachgewiesen |

**Konsequenz fuer das Plugin:** `.fusion` ist der einzige Default.
`filetypes.afx` existiert als Opt-in, ist aber aus gutem Grund aus. Fuer PHP
gibt es nur eine bewusst enge, additive Tree-sitter-Injection fuer Heredocs
mit dem Bezeichner `FUSION`/`AFX` (`after/queries/php/injections.scm`) — sie
ist eine Bequemlichkeit fuer selbstgeschriebene Fixtures, kein belegtes
Neos-Muster.

---

## 6. Tree-sitter

| Aspekt | Befund | Status |
| --- | --- | --- |
| Grammatik | `tree-sitter-fusion`, Autor Juergen Messner, <https://gitlab.com/jirgn/tree-sitter-fusion> | nachgewiesen |
| Lizenz | MIT | nachgewiesen |
| npm | `tree-sitter-fusion@1.1.2` (29.12.2021) | nachgewiesen |
| nvim-treesitter `master` | als Parser `fusion` registriert (`lua/nvim-treesitter/parsers.lua`), Maintainer `@jirgn`, `files = { src/parser.c, src/scanner.c }`; `queries/fusion/` vorhanden (HTTP 200) | nachgewiesen |
| nvim-treesitter `main` | **entfernt**. Kein `fusion`-Treffer in `lua/nvim-treesitter/parsers.lua` (73.900 Bytes); `queries/fusion/highlights.scm` → HTTP 404. `:TSInstall fusion` meldet `skipping unsupported language: fusion` (in der Praxis auf LazyVim beobachtet) | nachgewiesen |
| Queries | `queries/fusion/` enthaelt `highlights.scm`, `indents.scm`, `folds.scm`, `injections.scm`, `locals.scm` | nachgewiesen |
| Aktualitaet | letzte npm-Veroeffentlichung 2021 | nachgewiesen |

### Gemessene Abdeckung

Parser aus `tree-sitter-fusion@1.1.2` selbst uebersetzt
(`cc -shared parser.c scanner.c`) und in Neovim gegen Einzelkonstrukte
geprueft (`has_error()`):

| Konstrukt | Ergebnis |
| --- | --- |
| Prototyp, Pfade, Eel (`${q(node).property('title')}`) | ok |
| AFX einzeiliges Tag | ok |
| AFX mehrzeiliges Tag (Attribute auf mehreren Zeilen) | ok |
| Ausdruck im Attribut (`class={'a' + props.b}`) | ok |
| Spread (`{...props}`) | ok |
| Meta-Attribut (`@if.x={props.y}`) | ok |
| Verschachtelte Komponenten (`<Vendor.Site:Foo>`) | ok |
| **AFX-Kommentar `{/* … */}`** | **Parserfehler** |

Damit ist genau eine Luecke belegt: AFX-Kommentare. `examples/afx.fusion`
enthaelt einen solchen Kommentar und erzeugt deshalb ERROR-Knoten;
`examples/component.fusion` und `examples/package-layout.fusion` parsen
fehlerfrei. Die mitgelieferte `syntax/fusion.vim` deckt AFX-Kommentare ab.

**Konsequenz:** Der Standardweg fuer das Highlighting ist
`syntax/fusion.vim`. Tree-sitter ist nur noch fuer Setups mit
nvim-treesitter auf `master` erreichbar; dort greift das Plugin automatisch
darauf zu (`vim.treesitter.start()` per `pcall`). Eigene Queries liefert das
Plugin nicht: auf `master` sind die vorhandenen vollstaendiger, und auf `main`
gaebe es ohne Parser nichts, worauf sie anwendbar waeren.

Ein eigener Parser-Installer (Grammatik per npm holen, mit `cc` uebersetzen)
waere technisch machbar — im Rahmen dieser Analyse wurde das Uebersetzen
erfolgreich durchgefuehrt — ist aber bewusst nicht Teil des Plugins.

---

## 7. Lizenzlage und Konsequenzen

| Projekt | Lizenz | Umgang |
| --- | --- | --- |
| `cvette/intellij-neos` | GPL-3.0-or-later | **Kein Code uebernommen.** Nur die Erkenntnis gelesen, dass `.fusion` die einzige Endung ist und AFX per DSL-Injection eingebettet wird. Die Lexer (`*.flex`) wurden nicht als Vorlage fuer `syntax/fusion.vim` verwendet. |
| `sjsone/vscode-neos-fusion-lsp` | AGPL-3.0-or-later | **Kein Code uebernommen.** Uebernommen wurden ausschliesslich die *Schnittstellenwerte*, die ein Client zwingend kennen muss: der Konfigurationsname `neosFusionLsp`, die dokumentierten Default-Werte aus `contributes.configuration` und die Struktur der `initializationOptions`. Das sind Interoperabilitaetsdaten, kein Werkcode. |
| `sjsone/neos-fusion-ls` | AGPL-3.0-or-later | **Nicht mitgeliefert.** Der Server wird zur Laufzeit ueber npm bezogen und als separater Prozess gestartet. Der Wrapper `bin/neos-fusion-ls-stdio.js` ist eigener Code und enthaelt keine Serverlogik. |
| `networkteam/vscode-neos-fusion` | siehe Repository | TextMate-Grammatik **nicht** uebernommen; `syntax/fusion.vim` ist eigenstaendig anhand der Fusion-Dokumentation entstanden. |
| `jirgn/tree-sitter-fusion` | MIT | Nur referenziert (`:TSInstall fusion`), nicht mitgeliefert. |

Die AGPL des Servers wirkt sich auf dieses Plugin nicht aus: es wird kein
Servercode kopiert, gelinkt oder verteilt. Wer den Server selbst weitergibt
oder ueber ein Netzwerk anbietet, muss die AGPL-Pflichten beachten.

---

## 8. Nicht verifizierbare Punkte

* **Marketplace-Versionsseite JetBrains** (`/versions/stable`): der konkrete
  Versionsverlauf wurde nicht abgerufen; der Funktionsumfang stammt aus der
  Plugin-Beschreibung und dem Repository.
* **Abdeckungsgrad von `tree-sitter-fusion`** fuer aktuelle AFX-Syntax: nicht
  systematisch getestet.
* **Verhalten des Servers in grossen Projekten** (Neos-Distribution mit
  vollstaendigen `Packages/`): nur gegen ein Minimalprojekt getestet.
  Insbesondere `Goto Definition` auf `Neos.Fusion:Component` lieferte im
  Minimalprojekt `[]`, weil die Neos-Framework-Packages fehlten — das ist
  erwartetes Verhalten, aber die Positivprobe steht aus.
* **Windows**: nicht getestet. Der Installer und die Pfadlogik nutzen
  `vim.fs`/`vim.system` und sollten portabel sein.

---

## 9. Zusammenfassung fuer die Neovim-Implementierung

1. Server ueber npm beziehen (`neos-fusion-ls`), **nicht** ueber den Bin-Symlink starten.
2. `node … out/main.js --stdio`, optional durch den stdout-Wrapper.
3. `init_options.textDocumentSync.openClose = true` ist zwingend.
4. `workspace_folders` + `root_dir` setzen.
5. Vollstaendige `settings.neosFusionLsp` senden, sonst bleibt der Workspace leer.
6. `cmd_cwd = root` und Package-Ordner absolut aufloesen.
7. Datei-Watcher selbst nachruesten.
8. Handler fuer `custom/*` registrieren.
9. Tree-sitter aus nvim-treesitter nutzen, Vim-Syntax als Fallback.
