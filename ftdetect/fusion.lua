-- Zusaetzlich zu vim.filetype.add() in plugin/neos_fusion.lua, damit die
-- Erkennung auch greift, wenn das Plugin nur ueber `ftdetect` geladen wird.
vim.filetype.add({ extension = { fusion = "fusion" } })
