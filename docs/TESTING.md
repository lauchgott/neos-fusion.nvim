# Tests und Checkliste

## Automatisierte Tests

```bash
./scripts/test.sh
```

Fuehrt aus:

1. **Lua-Syntaxpruefung** (`scripts/luacheck.sh`) — `loadfile()` mit dem
   LuaJIT von Neovim ueber alle `*.lua` des Plugins.
2. **Node-Syntaxpruefung** — `node --check bin/neos-fusion-ls-stdio.js`.
3. **Neovim-Testsuite** (`tests/run.lua`) — 41 Tests, ohne externe
   Abhaengigkeiten (kein Plenary, kein Busted).
4. **LSP-Smoke-Test** (`tests/lsp_smoke.lua`) — 16 Tests gegen den echten
   Server. Wird uebersprungen, wenn kein Server verfuegbar ist.

Die Tests laufen hermetisch: `XDG_*` zeigt auf ein temporaeres Verzeichnis,
die Nutzerkonfiguration wird nicht geladen (`--clean -n -i NONE`).

Mit Server:

```bash
NEOS_FUSION_LS_MAIN=/pfad/zu/neos-fusion-ls/out/main.js ./scripts/test.sh
```

### Letzter Lauf

Umgebung: macOS 15 (Darwin 25.6.0, x86_64-Shell), **Neovim 0.12.0**,
**Node 25.9.0**, **npm 11.12.1**, `neos-fusion-ls@0.3.16`.

| Suite | Ergebnis |
| --- | --- |
| Lua-Syntaxpruefung | 12/12 ok |
| Node-Syntaxpruefung | ok |
| `tests/run.lua` | **41 bestanden, 0 fehlgeschlagen** |
| `tests/lsp_smoke.lua` | **16 bestanden, 0 fehlgeschlagen** |

---

## Manuelle Checkliste

Legende: `bestanden` / `nicht bestanden` / `nicht verifizierbar`.
Umgebung wie oben, sofern nicht anders vermerkt.

### Editor-Grundfunktionen

| # | Pruefung | Ergebnis | Beleg / Anmerkung |
| --- | --- | --- | --- |
| 1 | `.fusion` wird als `fusion` erkannt | **bestanden** | `tests/run.lua`: „.fusion wird als fusion erkannt“; zusaetzlich fuer alle drei Beispieldateien |
| 2 | Fusion-Syntax wird hervorgehoben | **bestanden** | `tests/run.lua`: „Vim-Syntax laedt ohne Fehler“, „Syntax erkennt Prototyp, AFX und Eel“ (`synID()`-Abfrage auf Prototyp, String und AFX-Region) |
| 3 | AFX-Syntax wird hervorgehoben | **bestanden** | s.o., Position innerhalb der `afx\``-Region liefert eine `fusion*`-Gruppe |
| 4 | Tree-sitter-Highlighting | **bestanden** (mit Einschraenkung) | Parser aus `tree-sitter-fusion@1.1.2` selbst uebersetzt; `vim.treesitter.start()` ok, `prototype` wird als `@keyword` erfasst. Zwei Einschraenkungen: AFX-Kommentare `{/* … */}` erzeugen ERROR-Knoten (Grammatiklucke); und nvim-treesitter fuehrt `fusion` nur auf Branch `master` — auf `main` meldet `:TSInstall fusion` `skipping unsupported language` (in der Praxis auf LazyVim bestaetigt) |
| 4b | Verhalten ohne Parser | **bestanden** | `:checkhealth` meldet „Vim-Syntax aktiv" plus Erklaerung statt einer Warnung; Highlighting laeuft ueber `syntax/fusion.vim` |
| 5 | Kommentarverhalten | **bestanden** | `commentstring = "// %s"`, `comments` enthaelt `//`, `#`, `/* */` (`tests/run.lua`) |
| 6 | Einrueckungsverhalten | **bestanden** | `gg=G` auf verschachtelte Fusion-Bloecke und AFX-Tags liefert 4/8 Spalten und korrektes Ausruecken (`tests/run.lua`, zwei Tests) |
| 7 | Snippets vorhanden und gueltig | **bestanden** | 21 Snippets, JSON validiert (`tests/run.lua`) |
| 8 | Snippet-Registrierung (LuaSnip / blink.cmp) | **bestanden** (blink.cmp) | Vom Nutzer bestaetigt, nachdem das Snippetverzeichnis in `search_paths` eingetragen wurde — `:checkhealth` meldet „blink.cmp kennt das Snippetverzeichnis des Plugins". Automatisiert geprueft: `blink_search_paths()`, `in_blink_search_paths()`, `blink_hint()` gegen eine vorgetaeuschte blink-Konfiguration. LuaSnip bleibt **nicht verifizierbar** (nicht installiert) |
| 9 | `:help neos-fusion` funktioniert | **bestanden** | `helptags doc/` erzeugt 37 Tags; `:help neos-fusion` oeffnet die Datei |
| 10 | Import ohne `setup()` bricht nicht ab | **bestanden** | `tests/run.lua`: „require('neos_fusion') ohne setup() wirft nicht“ |
| 11 | Alle Kommandos registriert | **bestanden** | 10 Kommandos geprueft (`tests/run.lua`) |
| 11b | `:NeosFusionDoctor` trennt die Fehlerursachen | **bestanden** | Zusatzprobe gegen den echten Server mit zwei Projektlayouts: bei `DistributionPackages` meldet es `[x]` plus `documentSymbol: 1 Eintraege`; bei einem abweichend benannten Ordner `KEIN Ordner vorhanden` plus `documentSymbol: LEER` |
| 12 | `:checkhealth neos_fusion` laeuft durch | **bestanden** | `tests/run.lua` fuehrt `:checkhealth neos_fusion` real aus |
| 12b | Sonderbuffer loesen keinen Serverstart aus | **bestanden** | `tests/run.lua`: `buf_file_path()` verwirft unbenannte Buffer, `buftype ~= ""` und URI-Schemata (`oil://`, `health://`); `lsp.start()` liefert dafuer `nil` |

### Language Server

| # | Pruefung | Ergebnis | Beleg / Anmerkung |
| --- | --- | --- | --- |
| 13 | Standalone-Server existiert | **bestanden** | npm `neos-fusion-ls@0.3.16`, `node out/main.js --stdio` |
| 14 | LSP startet im korrekten Projekt-Root | **bestanden** | `tests/run.lua`: Root ueber `composer.json` mit `neos/neos`, Paketmanifest wird verworfen, Monorepo-Layout (`.git` oben, Neos in `app/`) waehlt `app/`, `.git`-Fallback greift nur ohne starke Marker, `root_outermost` wirkt innerhalb der Stufe. Zusatzprobe gegen den echten Server mit dem Monorepo-Layout: Wurzel `<repo>/app`, Index 2 Prototypen, Definition 1 Treffer, Hover liefert Inhalt |
| 14b | Completion-Capabilities ohne Engine vorhanden | **bestanden** | `tests/run.lua`: `textDocument.completion` und `.hover` sind in `client_config()` gesetzt, auch wenn weder blink.cmp noch nvim-cmp vorhanden ist |
| 15 | `initialize` erfolgreich | **bestanden** | `lsp_smoke.lua`: `client.initialized == true`; alle erwarteten Capabilities angekuendigt |
| 16 | Hover | **bestanden** | `lsp_smoke.lua`: Hover auf `Neos.Fusion:Component` liefert ``` prototype(Neos.Fusion:Component) { } ``` |
| 17 | Diagnostics | **bestanden** | `lsp_smoke.lua`: „Tags have to be closed or the `@children` attribute has to be used“ nach Einfuegen eines offenen AFX-Tags |
| 18 | Document Symbols | **bestanden** | `lsp_smoke.lua`: `Vendor.Site:Component.Teaser` inkl. Kindknoten |
| 19 | Workspace Symbols | **bestanden** | Zusatzprobe: `workspace/symbol` mit Query „Teaser“ → 2 Treffer |
| 20 | Goto Definition | **bestanden** | Zusatzprobe: Definition auf einen im Projekt definierten Prototyp liefert einen `LocationLink`. **Hinweis:** auf Framework-Prototypen wie `Neos.Fusion:Component` liefert der Server `[]`, solange die Neos-Packages nicht im Projekt liegen — erwartetes Verhalten |
| 21 | Find References | **bestanden** | Zusatzprobe: 1 Referenz auf den eigenen Prototyp |
| 22 | Completion | **bestanden** | Zusatzprobe, positionsabhaengig: nach `resource://Vendor.Site/Public/` → 1 Vorschlag (`Images`); nach `prototype(Vendor.Site:` → 3 Vorschlaege. An beliebigen Positionen (z.B. `${props.}`) liefert der Server bewusst nichts |
| 23 | Verhalten bei fehlendem Server | **bestanden** | `tests/run.lua`: `resolve_cmd()` liefert `nil` statt zu raten; das Oeffnen der Datei funktioniert weiterhin (Meldung wird ueber `vim.schedule` ausgegeben und bricht das `FileType`-Autocommand nicht ab) |
| 24 | Installation auf frischem Setup | **bestanden** | Realer Lauf mit leerem `XDG_DATA_HOME`: `:NeosFusionInstallServer` installiert 0.3.16, danach `resolve_cmd()` → Quelle „Plugin-Installation“ |
| 25 | stdout-Wrapper | **bestanden** | Ohne Wrapper beginnt stdout mit `[   INFO] …`; mit Wrapper mit `Content-Length:`. Serverlogs erscheinen mit Wrapper in `lsp.log` (6456 B) statt verloren zu gehen (51 B) |
| 26 | Code Actions, CodeLens, Rename, Signature Help, Inlay Hints, Semantic Tokens | **nicht verifizierbar** | Serverseitig in der `initialize`-Antwort angekuendigt und von Neovim unterstuetzt, aber nicht einzeln durchgespielt |
| 27 | `workspace/didChangeWatchedFiles` bewirkt Cache-Aktualisierung | **nicht verifizierbar** | Das Senden ist implementiert und ausgeloest; die Wirkung im Server wurde nicht isoliert nachgewiesen |
| 28 | Verhalten in einem echten Neos-Projekt | **bestanden** | Vom Nutzer in einem Neos-Monorepo bestaetigt (Projekt in `<repo>/app`, mehrere DistributionPackages): Wurzelerkennung, Serverstart, Hover und Goto Definition funktionieren. Der Weg dorthin deckte den Root-Erkennungsfehler auf (siehe Punkt 14) |
| 28b | Verhalten in einer vollstaendigen Neos-Distribution mit `Packages/Framework` | **nicht verifizierbar** | Framework-Packages nur im Nachbau getestet, nicht in einer echten Installation |
| 29 | Windows | **nicht verifizierbar** | Nicht getestet |

---

## Manuell nachstellen

```bash
# 1. Server installieren
nvim -c 'NeosFusionInstallServer' -c 'sleep 30' -c 'NeosFusionServerInfo'

# 2. In einem echten Neos-Projekt
cd /pfad/zum/neos-projekt
nvim DistributionPackages/Vendor.Site/Resources/Private/Fusion/Root.fusion
```

Im Buffer pruefen:

```vim
:echo &filetype                 " -> fusion
:NeosFusionServerInfo           " -> Root, Kommando, Client
:checkhealth neos_fusion
:lua vim.lsp.buf.hover()        " Hover auf einen Prototypnamen
:lua vim.lsp.buf.definition()   " Sprung zur Prototyp-Definition
:lua print(#vim.diagnostic.get(0))
:NeosFusionSetLogLevel debug
:NeosFusionLog
```
