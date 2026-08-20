--- ftplugin fuer Fusion.
if vim.b.did_ftplugin_neos_fusion then
  return
end
vim.b.did_ftplugin_neos_fusion = true

local ok, config = pcall(require, "neos_fusion.config")
local cfg = ok and config.get() or nil
local editor = cfg and cfg.editor or { commentstring = "// %s", indent = true, shiftwidth = 4, expandtab = true }

vim.bo.commentstring = editor.commentstring or "// %s"
-- Fusion kennt `//`, `#` und `/* */`. `b:` = Blank nach dem Zeichen noetig,
-- damit z.B. `#{...}` nicht als Kommentar gilt.
vim.bo.comments = "s1:/*,mb:*,ex:*/,://,:#"

if editor.indent ~= false then
  vim.bo.shiftwidth = editor.shiftwidth or 4
  vim.bo.softtabstop = editor.shiftwidth or 4
  vim.bo.tabstop = editor.shiftwidth or 4
  vim.bo.expandtab = editor.expandtab ~= false
  vim.bo.autoindent = true
end

vim.bo.suffixesadd = ".fusion"
-- Prototypnamen wie `Neos.Fusion:Component` als ein Wort behandeln.
vim.opt_local.iskeyword:append({ ".", ":", "-" })

vim.b.undo_ftplugin = table.concat({
  "setlocal commentstring< comments< shiftwidth< softtabstop< tabstop<",
  "setlocal expandtab< autoindent< suffixesadd< iskeyword< indentexpr< indentkeys<",
  "unlet! b:did_ftplugin_neos_fusion",
}, " | ")
