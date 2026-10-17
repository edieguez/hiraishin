---Sign appearance. The extmarks themselves are owned by hiraishin.tracker.
local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")

local M = {}

-- tracking extmarks (they also draw the sign of live kunai)
M.ns = vim.api.nvim_create_namespace("hiraishin")
-- sign-only extmarks for stale kunai at their last known line
M.stale_ns = vim.api.nvim_create_namespace("hiraishin_stale")

function M.setup_highlights()
  local links = {
    HiraishinSign = "DiagnosticInfo",
    HiraishinSignSlot = "DiagnosticHint",
    HiraishinSignStale = "DiagnosticWarn",
    HiraishinLine = "CursorLine",
    HiraishinVirtText = "Comment",
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

---Sign fields for a kunai, merged into its extmark options.
---@param list hiraishin.List
---@param bm hiraishin.Bookmark
---@param stale? boolean
---@return table
function M.decoration(list, bm, stale)
  local o = config.options.signs
  if not o.enabled then
    return {}
  end
  local text, hl = o.icon, "HiraishinSign"
  local slot = o.show_slot and list_ops.slot_of(list, bm.id) or nil
  if stale then
    text, hl = o.stale_icon, "HiraishinSignStale"
  elseif slot then
    text, hl = slot, "HiraishinSignSlot"
  end
  return {
    sign_text = text,
    sign_hl_group = hl,
    number_hl_group = o.numhl and hl or nil,
    priority = o.priority,
  }
end

return M
