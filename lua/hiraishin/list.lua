---Pure operations on a single bookmark list.
local M = {}

---@class hiraishin.Bookmark
---@field id string
---@field file string
---@field line integer
---@field col integer
---@field name string?
---@field note string?
---@field anchor { text: string, before: string?, after: string? }
---@field stale boolean
---@field created_at integer
---@field updated_at integer
---@field last_jump_at integer?

---@param data hiraishin.Data
---@return hiraishin.List, string name
function M.active(data)
  return data.lists[data.active_list], data.active_list
end

---@param list hiraishin.List
---@return hiraishin.Bookmark?
function M.find_at(list, file, line)
  for _, id in ipairs(list.order) do
    local bm = list.bookmarks[id]
    if bm.file == file and bm.line == line then
      return bm
    end
  end
end

---Find by id first, then by name.
---@param list hiraishin.List
---@param key string
---@return hiraishin.Bookmark?
function M.find(list, key)
  if list.bookmarks[key] then
    return list.bookmarks[key]
  end
  for _, id in ipairs(list.order) do
    if list.bookmarks[id].name == key then
      return list.bookmarks[id]
    end
  end
end

---@param list hiraishin.List
---@param name string
---@param except_id? string
---@return hiraishin.Bookmark?
function M.find_name(list, name, except_id)
  for _, id in ipairs(list.order) do
    local bm = list.bookmarks[id]
    if bm.name == name and id ~= except_id then
      return bm
    end
  end
end

---Bookmarks in manager order, optionally limited to one file.
---@param list hiraishin.List
---@param file? string
---@return hiraishin.Bookmark[]
function M.items(list, file)
  local out = {}
  for _, id in ipairs(list.order) do
    local bm = list.bookmarks[id]
    if not file or bm.file == file then
      table.insert(out, bm)
    end
  end
  return out
end

---@param list hiraishin.List
---@param id string
---@return string? slot
function M.slot_of(list, id)
  for slot, sid in pairs(list.slots) do
    if sid == id then
      return slot
    end
  end
end

---@param list hiraishin.List
---@param bm hiraishin.Bookmark
function M.insert(list, bm)
  list.bookmarks[bm.id] = bm
  table.insert(list.order, bm.id)
end

---Remove a bookmark and free its slot.
---@param list hiraishin.List
---@param id string
---@return hiraishin.Bookmark?
function M.delete(list, id)
  local bm = list.bookmarks[id]
  if not bm then
    return nil
  end
  list.bookmarks[id] = nil
  for i, oid in ipairs(list.order) do
    if oid == id then
      table.remove(list.order, i)
      break
    end
  end
  local slot = M.slot_of(list, id)
  if slot then
    list.slots[slot] = nil
  end
  return bm
end

return M
