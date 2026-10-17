---Fallback backend: vim.ui.select (no preview, jump only).
local M = {}

function M.available()
  return true
end

---@param p table see hiraishin.picker.open
function M.open(p)
  local core = require("hiraishin.picker")
  vim.ui.select(p.entries, {
    prompt = p.title,
    kind = "hiraishin",
    format_item = function(e)
      return e.label
    end,
  }, function(e)
    if e then
      core.actions.jump(p.ctx, e)
    end
  end)
end

return M
