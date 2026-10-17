---lualine component:
---
---  sections = { lualine_x = { require("hiraishin.integrations.lualine") } }
---
---Shows "<icon>3 [list]" (kunai in the buffer, list when not "default").
---Clicking it opens the picker for the current file.
return {
  function()
    return require("hiraishin").status()
  end,
  cond = function()
    return package.loaded["hiraishin"] ~= nil and require("hiraishin").status() ~= ""
  end,
  color = function()
    local hl = vim.api.nvim_get_hl(0, { name = "HiraishinStatus", link = false })
    return hl.fg and { fg = string.format("#%06x", hl.fg) } or nil
  end,
  on_click = function()
    require("hiraishin").pick({ filter = "buffer" })
  end,
}
