-- Minimal init for headless test runs: `make test`
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/deps/mini.nvim")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

-- Picker plugins for the backend tests. They are fetched here (not in the
-- Makefile) and kept OFF the runtimepath; tests add the one they need.
local PICKERS = {
  ["snacks.nvim"] = "https://github.com/folke/snacks.nvim",
  ["telescope.nvim"] = "https://github.com/nvim-telescope/telescope.nvim",
  ["plenary.nvim"] = "https://github.com/nvim-lua/plenary.nvim",
  ["fzf-lua"] = "https://github.com/ibhagwan/fzf-lua",
}
_G.HIRAISHIN_DEPS = root .. "/deps"
if vim.env.HIRAISHIN_SKIP_PICKERS == nil and #vim.api.nvim_list_uis() == 0 then
  for name, url in pairs(PICKERS) do
    local dir = root .. "/deps/" .. name
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.system({ "git", "clone", "--quiet", "--depth", "1", "--filter=blob:none", url, dir })
    end
  end
end

if #vim.api.nvim_list_uis() == 0 then
  require("mini.test").setup()
end
