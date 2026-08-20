#!/usr/bin/env node
'use strict'

/*
 * neos-fusion-ls-stdio.js — stdio wrapper for the Neos Fusion language server.
 *
 * Why this wrapper exists
 * -----------------------
 * `neos-fusion-ls` logs through `console.log()`. In the official VSCode
 * extension the server runs over `TransportKind.ipc`, where those lines end up
 * harmlessly in the extension host console.
 *
 * Over stdio (the only transport Neovim speaks) `console.log()` writes into the
 * same stream as the JSON-RPC framing. During `initialize` alone the server
 * emits at least one line
 *
 *     [   INFO] <...> [LanguageServer] Added FusionWorkspace ...\n
 *
 * before the first `Content-Length:` header. Neovim 0.12 was measured to
 * tolerate this, but the log lines are swallowed instead of reaching the LSP
 * log, and a client that parses the headers strictly would break on them.
 *
 * The wrapper loads the server in the same process and redirects all console
 * methods to stderr beforehand. The JSON-RPC framing itself is written by
 * `vscode-languageserver` directly through `process.stdout.write()` and is not
 * affected.
 *
 * Usage:
 *   node neos-fusion-ls-stdio.js <path/to/neos-fusion-ls/out/main.js> --stdio
 *
 * The server path can alternatively be set through NEOS_FUSION_LS_MAIN.
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
    // stderr may be closed — logging must never terminate the server.
  }
}

for (const method of ['log', 'info', 'warn', 'error', 'debug', 'trace', 'dir']) {
  console[method] = (...args) => writeErr(args)
}

const positional = process.argv.slice(2).filter((arg) => !arg.startsWith('-'))
const serverMain = process.env.NEOS_FUSION_LS_MAIN || positional[0]

if (!serverMain) {
  process.stderr.write(
    'neos-fusion-ls-stdio: no server path given.\n' +
      'Usage: node neos-fusion-ls-stdio.js <path/to/out/main.js> --stdio\n'
  )
  process.exit(2)
}

const resolved = path.resolve(serverMain)

// `vscode-languageserver` reads the transport from process.argv. Make sure
// `--stdio` is set, even when the caller forgot it.
if (!process.argv.includes('--stdio')) {
  process.argv.push('--stdio')
}

try {
  require(resolved)
} catch (error) {
  process.stderr.write(
    'neos-fusion-ls-stdio: could not load the server: ' + resolved + '\n' + (error && error.stack) + '\n'
  )
  process.exit(1)
}
