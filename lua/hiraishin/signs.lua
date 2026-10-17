---Sign column rendering. Phase 2 turns these extmarks into the line trackers.
local config = require("hiraishin.config")
local scope = require("hiraishin.scope")
local store = require("hiraishin.store")
local list_ops = require("hiraishin.list")

local M = {}

M.ns = vim.api.nvim_create_namespace("hiraishin")

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

---@param bufnr integer
function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  local o = config.options.signs
  if not o.enabled then
    return
  end
  local ctx = scope.for_buf(bufnr)
  if not ctx then
    return
  end
  local list = list_ops.active(store.get(ctx))
  local count = vim.api.nvim_buf_line_count(bufnr)
  for _, bm in ipairs(list_ops.items(list, ctx.file)) do
    if bm.line >= 1 and bm.line <= count then
      local text, hl = o.icon, "HiraishinSign"
      local slot = o.show_slot and list_ops.slot_of(list, bm.id) or nil
      if bm.stale then
        text, hl = o.stale_icon, "HiraishinSignStale"
      elseif slot then
        text, hl = slot, "HiraishinSignSlot"
      end
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, bm.line - 1, 0, {
        sign_text = text,
        sign_hl_group = hl,
        number_hl_group = o.numhl and hl or nil,
        priority = o.priority,
      })
    end
  end
end

---Refresh every loaded buffer showing `abs` (or all buffers when nil).
---@param abs? string
function M.refresh_file(abs)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ctx = scope.for_buf(bufnr)
      if ctx and (abs == nil or ctx.abs == abs) then
        M.refresh(bufnr)
      end
    end
  end
end

return M
