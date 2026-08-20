--- ftplugin for Fusion.
if vim.b.did_ftplugin_neos_fusion then
  return
end
vim.b.did_ftplugin_neos_fusion = true

local ok, config = pcall(require, "neos_fusion.config")
local cfg = ok and config.get() or nil
local editor = cfg and cfg.editor or { commentstring = "// %s", indent = true, shiftwidth = 4, expandtab = true }

vim.bo.commentstring = editor.commentstring or "// %s"
-- Fusion knows `//`, `#` and `/* */`. `b:` = a blank after the character is
-- required, so that e.g. `#{...}` does not count as a comment.
vim.bo.comments = "s1:/*,mb:*,ex:*/,://,:#"

if editor.indent ~= false then
  vim.bo.shiftwidth = editor.shiftwidth or 4
  vim.bo.softtabstop = editor.shiftwidth or 4
  vim.bo.tabstop = editor.shiftwidth or 4
  vim.bo.expandtab = editor.expandtab ~= false
  vim.bo.autoindent = true
end

vim.bo.suffixesadd = ".fusion"
-- Treat prototype names such as `Neos.Fusion:Component` as one word.
vim.opt_local.iskeyword:append({ ".", ":", "-" })

vim.b.undo_ftplugin = table.concat({
  "setlocal commentstring< comments< shiftwidth< softtabstop< tabstop<",
  "setlocal expandtab< autoindent< suffixesadd< iskeyword< indentexpr< indentkeys<",
  "unlet! b:did_ftplugin_neos_fusion",
}, " | ")
