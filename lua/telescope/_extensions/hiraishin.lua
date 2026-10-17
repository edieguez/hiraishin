---:Telescope hiraishin [filter=buffer|all]
---
---  require("telescope").load_extension("hiraishin")
local function pick(opts)
  opts = opts or {}
  require("hiraishin").pick({ filter = opts.filter, backend = "telescope" })
end

return require("telescope").register_extension({
  exports = {
    hiraishin = pick,
    buffer = function(opts)
      pick(vim.tbl_extend("force", opts or {}, { filter = "buffer" }))
    end,
    all = function(opts)
      pick(vim.tbl_extend("force", opts or {}, { filter = "all" }))
    end,
  },
})
