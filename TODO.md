# Status und offene Aufgaben

Stand: 19.08.2026 — getestet mit Neovim 0.12.0, Node 25.9.0,
`neos-fusion-ls@0.3.16` auf macOS.

---

## 1. Was tatsaechlich funktioniert

**Nachgewiesen** (automatisiert getestet, 57 Tests gruen):

* Dateityperkennung `.fusion` → `fusion`, auch ohne `setup()`
* Vim-Fallback-Syntax fuer Fusion, Eel, AFX, Prototypen, Meta-Eigenschaften,
  Kommentare (`//`, `#`, `/* */`)
* Einrueckung fuer `{}`-Bloecke, AFX-Tags und `afx\``
* `commentstring` und `comments`
* 21 Snippets im VSCode-Format, JSON validiert
* Root-Erkennung inkl. Sonderfall „Package-composer.json ist keine Wurzel“
* Kommando-Aufloesung mit vier Quellen und Wrapper-Einbindung
* Installer: `:NeosFusionInstallServer` gegen npm, real durchgefuehrt
* LSP end-to-end aus Neovim: `initialize`, Hover, Document Symbols,
  Workspace Symbols, Goto Definition, Find References, Completion,
  Diagnostics
* stdout-Wrapper: stdout bleibt LSP-konform, Serverlogs landen in `lsp.log`
* 10 Nutzerkommandos, `:checkhealth neos_fusion`, `:NeosFusionDoctor`,
  `:help neos-fusion` (37 Tags)
* Sonderbuffer (Terminal, `oil://`, `health://`, unbenannt) loesen keinen
  Serverstart aus

**Belegt, aber nicht einzeln durchgespielt:** Code Actions, CodeLens, Rename,
Signature Help, Inlay Hints, Semantic Tokens — vom Server in der
`initialize`-Antwort angekuendigt, von Neovim nativ unterstuetzt.

---

## 2. Status der LSP-Standalone-Frage

**Beantwortet: ja.**

`neos-fusion-ls` ist ein eigenstaendiges npm-Paket
(<https://github.com/sjsone/neos-fusion-ls>, AGPL-3.0-or-later) mit
esbuild-Bundle, das ueber `--stdio` ansprechbar ist. Kein Build noetig, kein
VSCode noetig. Belege in `docs/ANALYSE.md`, Abschnitt 2.

Fuenf Eigenheiten, die eine naive Anbindung scheitern lassen, sind im Plugin
abgefangen:

1. `initializationOptions.textDocumentSync.openClose` ist Pflicht.
2. Workspaces entstehen nur aus `workspaceFolders`.
3. Initialisiert wird erst bei `workspace/didChangeConfiguration` — die
   Settings muessen vollstaendig sein.
4. `folders.packages` wird gegen das Arbeitsverzeichnis geprueft.
5. Der Server registriert keine Datei-Watcher.

---

## 3. Nicht vollstaendig verifiziert

| Punkt | Grund |
| --- | --- |
| Vollstaendige Neos-Distribution | Ein echtes Neos-Monorepo ist bestaetigt (Wurzelerkennung, Hover, Goto Definition). Nicht geprueft: eine Installation mit komplett gefuellten `Packages/Framework`, Eel-Helper-Navigation, NodeType-CodeLens, Verhalten bei sehr vielen Packages |
| Snippet-Registrierung mit LuaSnip | Nicht installiert, Pfad per `pcall` abgesichert. blink.cmp ist in der Praxis bestaetigt (mit Suchpfad-Eintrag) |
| Wirkung von `workspace/didChangeWatchedFiles` | Senden implementiert und ausgeloest, Serverseite nicht isoliert nachgewiesen |
| Code Actions, CodeLens, Rename, Signature Help, Inlay Hints, Semantic Tokens | Angekuendigt, nicht einzeln durchgespielt |
| Windows | Nicht getestet. `vim.fs`/`vim.system` sollten portabel sein; `root_markers` enthaelt `flow.bat` |
| `filetypes.afx = true` | Opt-in, in keinem Referenzprojekt belegt und deshalb nicht praktisch erprobt |

---

## 4. Bekannte Einschraenkungen

**Tree-sitter ist praktisch nicht mehr erreichbar**
nvim-treesitter fuehrt `fusion` nur auf dem alten Branch `master`. Auf dem
aktuellen `main` (u.a. LazyVim) sind Parser und Queries entfernt;
`:TSInstall fusion` meldet `skipping unsupported language: fusion`.
Standardweg ist damit `syntax/fusion.vim`.

**Tree-sitter-Grammatik selbst (`tree-sitter-fusion@1.1.2`, MIT, Stand 2021)**
AFX-Kommentare `{/* … */}` erzeugen Parserfehler. Gemessen; alle uebrigen
geprueften Konstrukte (mehrzeilige Tags, Attributausdruecke, Spread,
Meta-Attribute, verschachtelte Komponenten, Eel) parsen fehlerfrei. Die
mitgelieferte Vim-Syntax deckt AFX-Kommentare ab.

**Fallback-Syntax**
Regexbasiert und damit prinzipiell ungenauer als Tree-sitter. Bewusst
konservativ gehalten (`syn sync minlines=100`); in sehr langen Dateien kann
`:syntax sync fromstart` noetig werden.

**Datei-Watcher**
Nur `BufWritePost` innerhalb der Projektwurzel. Aenderungen ausserhalb von
Neovim (Git-Checkout, Composer, anderer Editor) erreichen den Server nicht →
`:NeosFusionReloadWorkspace`.

**Completion ist positionsabhaengig**
Der Server liefert Vorschlaege fuer Resource-Pfade und Prototypnamen; an
anderen Positionen bewusst nichts. Kein Plugin-Fehler.

**AFX in PHP**
Es gibt kein belegtes Neos-Muster dafuer. Die mitgelieferte Injection greift
nur bei PHP-Heredocs mit dem Bezeichner `FUSION`/`AFX` und ist eine
Bequemlichkeit, kein Feature der Plattform.

**Serverversion**
`0.3.16` ist die letzte stabile Version (`0.3.17-pre-release` vom 25.08.2024
ist als Vorabversion markiert). Das Projekt ist laut eigener Aussage „WIP“.

**blink.cmp braucht einen Eintrag**
blink durchsucht den runtimepath nicht, sondern nur
`stdpath("config")/snippets` und friendly-snippets. Das Snippetverzeichnis
muss deshalb in `search_paths` stehen. Automatisieren laesst sich das nicht:
blink baut die Registry einmalig beim Setup, bevor ein `ft`-lazy Plugin
existiert.

**Kein `mason.nvim`-Paket**
Der Server ist nicht in der Mason-Registry. Ein eigener Registry-Eintrag
wurde bewusst nicht angelegt, weil der Plugin-Installer denselben Zweck ohne
Zusatzabhaengigkeit erfuellt.

---

## 5. Offene Aufgaben (priorisiert)

### Hoch

1. **Breite in echten Projekten** — ein Neos-Monorepo laeuft bestaetigt.
   Offen: Eel-Helper-Navigation, NodeType-CodeLens, Performance bei sehr
   vielen Packages, Projekte mit abweichenden Package-Ordnernamen.
2. **Tree-sitter-Weg entscheiden.** Drei Varianten, bewusst offen gelassen:
   * eigener Parser-Installer im Plugin (Grammatik per npm holen, mit `cc`
     uebersetzen — das Uebersetzen wurde erfolgreich getestet) plus eigene
     `queries/fusion/*.scm`;
   * Wiederaufnahme von `fusion` in nvim-treesitter `main` anstossen;
   * bei der Vim-Syntax bleiben.
3. **AFX-Kommentare in der Tree-sitter-Grammatik** — Issue bzw. Merge Request
   bei <https://gitlab.com/jirgn/tree-sitter-fusion> einreichen.

### Mittel

4. **Upstream-Anbindung an nvim-lspconfig** — eine `lsp/fusion_ls.lua`
   beisteuern, sobald die Konfigurationsanforderungen (Pflicht-`init_options`,
   vollstaendige `settings`) dort abbildbar sind.
5. **Datei-Watcher ueber `vim.uv.fs_event`** statt nur `BufWritePost`, damit
   auch externe Aenderungen erkannt werden.
6. **Statusanzeige** — die `custom/progressNotification/*`-Daten werden
   bereits vorgehalten, aber nur in `:NeosFusionServerInfo` gezeigt. Eine
   `lualine`-Komponente waere naheliegend.
7. **Code Actions durchspielen** — der Server bietet u.a. „NodeType-Datei
   anlegen“ und „deprecated Prototyp ersetzen“; eine Bedienhilfe dafuer waere
   nuetzlich.

### Niedrig

8. **Formatter** — `prettier-plugin-fusion` bzw. `prettier-plugin-neos-fusion`
   existieren auf npm (beide 0.2.0). Nicht geprueft, daher bewusst nicht
   eingebunden. Ein Opt-in ueber `conform.nvim` waere der saubere Weg.
9. **Textobjects** — derzeit Opt-in und leer; sinnvoll umsetzbar erst mit
   Tree-sitter-Queries fuer Prototypen-Bloecke und AFX-Elemente.
10. **XLIFF- und NodeTypes.yaml-Komfort** — der Server liest beides; eigene
   Sprungziele oder Vorschauen waeren denkbar.
11. **Windows-Verifikation** inkl. `npm.cmd`-Erkennung.
12. **CI** — GitHub-Action, die `scripts/test.sh` gegen mehrere
    Neovim-Versionen (0.10, 0.11, stable, nightly) faehrt.
