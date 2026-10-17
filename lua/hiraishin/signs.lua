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

---@param bm hiraishin.Bookmark
---@return table? virt_text chunks
local function virt_text(bm)
  local v = config.options.virt_text
  if not v.enabled then
    return nil
  end
  local note = bm.note and v.note_icon or nil
  local text
  if bm.name then
    text = v.prefix .. bm.name .. (note and (" " .. note) or "")
  elseif note and v.only_named then
    text = v.prefix .. note
  elseif not v.only_named then
    text = v.prefix .. (bm.anchor and bm.anchor.text or "") .. (note and (" " .. note) or "")
  end
  return text and { { text, "HiraishinVirtText" } } or nil
end

---Decoration fields for a kunai, merged into its extmark options:
---sign, line highlight and virtual text.
---@param list hiraishin.List
---@param bm hiraishin.Bookmark
---@param stale? boolean
---@return table
function M.decoration(list, bm, stale)
  local o = config.options.signs
  local out = {}
  if o.enabled then
    local text, hl = o.icon, "HiraishinSign"
    local slot = o.show_slot and list_ops.slot_of(list, bm.id) or nil
    if stale then
      text, hl = o.stale_icon, "HiraishinSignStale"
    elseif slot then
      text, hl = slot, "HiraishinSignSlot"
    end
    out.sign_text = text
    out.sign_hl_group = hl
    out.number_hl_group = o.numhl and hl or nil
    out.priority = o.priority
  end
  if not stale then
    if config.options.line_highlight then
      out.line_hl_group = "HiraishinLine"
    end
    local vt = virt_text(bm)
    if vt then
      out.virt_text = vt
      out.virt_text_pos = config.options.virt_text.position
    end
  end
  return out
end

return M
