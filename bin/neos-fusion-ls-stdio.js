#!/usr/bin/env node
'use strict'

/*
 * neos-fusion-ls-stdio.js — stdio-Wrapper fuer den Neos Fusion Language Server.
 *
 * Warum es diesen Wrapper gibt
 * ----------------------------
 * `neos-fusion-ls` protokolliert ueber `console.log()`. Bei der offiziellen
 * VSCode-Extension laeuft der Server ueber `TransportKind.ipc`; dort landen
 * diese Zeilen harmlos in der Extension-Host-Konsole.
 *
 * Ueber stdio (der einzige Transport, den Neovim spricht) schreibt
 * `console.log()` jedoch in denselben Stream wie das JSON-RPC-Framing. Schon
 * beim `initialize` gibt der Server mindestens eine Zeile
 *
 *     [   INFO] <...> [LanguageServer] Added FusionWorkspace ...\n
 *
 * vor dem ersten `Content-Length:`-Header aus. Ein LSP-Client, der die Header
 * strikt parst, bricht daran ab.
 *
 * Der Wrapper laedt den Server im selben Prozess und leitet vorher alle
 * console-Methoden auf stderr um. Das JSON-RPC-Framing selbst schreibt
 * `vscode-languageserver` direkt ueber `process.stdout.write()` und ist davon
 * nicht betroffen.
 *
 * Aufruf:
 *   node neos-fusion-ls-stdio.js <pfad/zu/neos-fusion-ls/out/main.js> --stdio
 *
 * Der Server-Pfad kann alternativ ueber NEOS_FUSION_LS_MAIN gesetzt werden.
 */

const path = require('path')
const util = require('util')

function writeErr(args) {
  let line
  try {
    line = util.format(...args)
  } catch (error) {
    line = String(args)
  }
  try {
    process.stderr.write(line + '\n')
  } catch (error) {
    // stderr kann geschlossen sein — Logging darf den Server nie beenden.
  }
}

for (const method of ['log', 'info', 'warn', 'error', 'debug', 'trace', 'dir']) {
  console[method] = (...args) => writeErr(args)
}

const positional = process.argv.slice(2).filter((arg) => !arg.startsWith('-'))
const serverMain = process.env.NEOS_FUSION_LS_MAIN || positional[0]

if (!serverMain) {
  process.stderr.write(
    'neos-fusion-ls-stdio: kein Server-Pfad angegeben.\n' +
      'Aufruf: node neos-fusion-ls-stdio.js <pfad/zu/out/main.js> --stdio\n'
  )
  process.exit(2)
}

const resolved = path.resolve(serverMain)

// `vscode-languageserver` liest den Transport aus process.argv. Sicherstellen,
// dass `--stdio` gesetzt ist, auch wenn der Aufrufer es vergessen hat.
if (!process.argv.includes('--stdio')) {
  process.argv.push('--stdio')
}

try {
  require(resolved)
} catch (error) {
  process.stderr.write(
    'neos-fusion-ls-stdio: Server konnte nicht geladen werden: ' + resolved + '\n' + (error && error.stack) + '\n'
  )
  process.exit(1)
}
