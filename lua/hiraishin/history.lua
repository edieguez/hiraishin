---Recently deleted kunai, for :Hiraishin undo. In memory only.
local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")

local M = {}

---@class hiraishin.HistoryItem
---@field list string
---@field bookmark hiraishin.Bookmark copy, line = live line at deletion
---@field slot string?
---@field index integer position in the list order

---@class hiraishin.HistoryEntry
---@field ctx hiraishin.Context
---@field items hiraishin.HistoryItem[]
---@field reason string

---@type hiraishin.HistoryEntry[]
local stack = {}

---Snapshot a kunai that is about to be deleted.
---@param ctx hiraishin.Context
---@param list_name string
---@param list hiraishin.List
---@param bm hiraishin.Bookmark
---@return hiraishin.HistoryItem
function M.item(ctx, list_name, list, bm)
  local copy = vim.deepcopy(bm)
  local line = require("hiraishin.tracker").live_line(ctx, bm)
  if line then
    copy.line = line
  end
  local index = 1
  for i, id in ipairs(list.order) do
    if id == bm.id then
      index = i
      break
    end
  end
  return { list = list_name, bookmark = copy, slot = list_ops.slot_of(list, bm.id), index = index }
end

---Remember one deletion (one entry, any number of kunai).
---@param ctx hiraishin.Context
---@param items hiraishin.HistoryItem[]
---@param reason string
function M.record(ctx, items, reason)
  if #items == 0 or config.options.undo_history <= 0 then
    return
  end
  table.insert(stack, { ctx = ctx, items = items, reason = reason })
  while #stack > config.options.undo_history do
    table.remove(stack, 1)
  end
end

---@return hiraishin.HistoryEntry?
function M.pop()
  return table.remove(stack)
end

---@return integer
function M.size()
  return #stack
end

function M.clear()
  stack = {}
end

return M
