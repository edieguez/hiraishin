if vim.g.loaded_hiraishin then
  return
end
vim.g.loaded_hiraishin = true

vim.api.nvim_create_user_command("Hiraishin", function(cmd)
  require("hiraishin.commands").run(cmd)
end, {
  nargs = "*",
  bang = true,
  desc = "hiraishin.nvim bookmarks",
  complete = function(arg_lead, cmd_line, cursor_pos)
    return require("hiraishin.commands").complete(arg_lead, cmd_line, cursor_pos)
  end,
})
