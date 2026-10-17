-- Minimal init for headless test runs: `make test`
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/deps/mini.nvim")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

if #vim.api.nvim_list_uis() == 0 then
  require("mini.test").setup()
end
