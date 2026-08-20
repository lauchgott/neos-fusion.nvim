-- Minimale Neovim-Konfiguration fuer die Tests. Bindet ausschliesslich dieses
-- Plugin ein, damit die Ergebnisse nicht von der Nutzerkonfiguration abhaengen.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local root = vim.fs.dirname(here)

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/after")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.g.mapleader = " "

_G.NEOS_FUSION_TEST_ROOT = root
