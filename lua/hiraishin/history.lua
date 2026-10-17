---Recently deleted kunai, for :Hiraishin undo. Kept in the store file
---(`trash`), so undo works across restarts and is per project/scope.
local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")

local M = {}

---@class hiraishin.HistoryItem
---@field list string
---@field bookmark hiraishin.Bookmark copy, line = live line at deletion
---@field slot string?
---@field camp boolean? it was the list's camp
---@field index integer position in the list order

---@class hiraishin.HistoryEntry
---@field id string
---@field at integer os.time() of the deletion
---@field items hiraishin.HistoryItem[]
---@field reason string

local function trash(ctx)
  local data = require("hiraishin.store").get(ctx)
  data.trash = data.trash or {}
  return data.trash
end

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
  return {
    list = list_name,
    bookmark = copy,
    slot = list_ops.slot_of(list, bm.id),
    camp = list.camp == bm.id or nil,
    index = index,
  }
end

---Remember one deletion (one entry, any number of kunai) in the store of `ctx`.
---The caller saves the store.
---@param ctx hiraishin.Context
---@param items hiraishin.HistoryItem[]
---@param reason string
function M.record(ctx, items, reason)
  if #items == 0 or config.options.undo_history <= 0 then
    return
  end
  local t = trash(ctx)
  local ids = {}
  for _, e in ipairs(t) do
    ids[e.id] = true
  end
  table.insert(t, { id = require("hiraishin.util").new_id(ids), at = os.time(), items = items, reason = reason })
  while #t > config.options.undo_history do
    table.remove(t, 1)
  end
end

---Take the latest deletion of a store.
---@param ctx hiraishin.Context
---@return hiraishin.HistoryEntry?
function M.pop(ctx)
  return table.remove(trash(ctx))
end

---@param ctx hiraishin.Context
---@return integer
function M.size(ctx)
  return #trash(ctx)
end

return M
