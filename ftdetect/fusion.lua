-- In addition to vim.filetype.add() in plugin/neos_fusion.lua, so detection
-- also works when the plugin is loaded through `ftdetect` only.
vim.filetype.add({ extension = { fusion = "fusion" } })
