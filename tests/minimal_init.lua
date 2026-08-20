-- Minimal Neovim configuration for the tests. Loads this plugin only, so the
-- results do not depend on the user configuration.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local root = vim.fs.dirname(here)

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/after")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.g.mapleader = " "

_G.NEOS_FUSION_TEST_ROOT = root
