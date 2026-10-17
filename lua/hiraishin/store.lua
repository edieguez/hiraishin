---JSON persistence: one file per scope, atomic writes, debounced saves.
local config = require("hiraishin.config")
local util = require("hiraishin.util")

local M = {}

M.VERSION = 1

---@class hiraishin.List
---@field order string[]
---@field slots table<string, string>
---@field bookmarks table<string, hiraishin.Bookmark>

---@class hiraishin.Data
---@field version integer
---@field root string?
---@field active_list string
---@field lists table<string, hiraishin.List>

-- store path -> { data = hiraishin.Data, dirty = boolean }
local cache = {}
local timer ---@type uv.uv_timer_t?

---@return hiraishin.List
function M.new_list()
  return { order = {}, slots = {}, bookmarks = {} }
end

---@param root string?
---@return hiraishin.Data
local function new_data(root)
  return {
    version = M.VERSION,
    root = root,
    active_list = "default",
    lists = { default = M.new_list() },
  }
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local content = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
  vim.uv.fs_close(fd)
  return content
end

---Write via a temp file + rename so a crash never leaves half-written JSON.
---@return boolean ok, string? err
local function write_atomic(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = path .. ".tmp"
  local fd, err = vim.uv.fs_open(tmp, "w", 420)
  if not fd then
    return false, err
  end
  local ok, werr = vim.uv.fs_write(fd, content, 0)
  if ok then
    vim.uv.fs_fsync(fd)
  end
  vim.uv.fs_close(fd)
  if not ok then
    vim.uv.fs_unlink(tmp)
    return false, werr
  end
  local renamed, rerr = vim.uv.fs_rename(tmp, path)
  if not renamed then
    vim.uv.fs_unlink(tmp)
    return false, rerr
  end
  return true
end

---Bring decoded JSON into shape; returns nil when it is not hiraishin data.
---@return hiraishin.Data?
local function normalize(data, root)
  if type(data) ~= "table" or type(data.lists) ~= "table" then
    return nil
  end
  if type(data.version) ~= "number" or data.version > M.VERSION then
    return nil
  end
  data.version = M.VERSION
  data.root = data.root or root
  for name, list in pairs(data.lists) do
    if type(list) ~= "table" then
      data.lists[name] = M.new_list()
    else
      list.bookmarks = type(list.bookmarks) == "table" and list.bookmarks or {}
      list.slots = type(list.slots) == "table" and list.slots or {}
      local seen, order = {}, {}
      for _, id in ipairs(type(list.order) == "table" and list.order or {}) do
        if list.bookmarks[id] and not seen[id] then
          seen[id] = true
          table.insert(order, id)
        end
      end
      -- bookmarks missing from order go to the end, oldest first
      local missing = {}
      for id, bm in pairs(list.bookmarks) do
        bm.id = id
        if not seen[id] then
          table.insert(missing, bm)
        end
      end
      table.sort(missing, function(a, b)
        return (a.created_at or 0) < (b.created_at or 0)
      end)
      for _, bm in ipairs(missing) do
        table.insert(order, bm.id)
      end
      list.order = order
      for slot, id in pairs(list.slots) do
        if not list.bookmarks[id] then
          list.slots[slot] = nil
        end
      end
    end
  end
  data.lists.default = data.lists.default or M.new_list()
  if type(data.active_list) ~= "string" or not data.lists[data.active_list] then
    data.active_list = "default"
  end
  return data
end

---@param path string
---@param root string?
---@return hiraishin.Data
local function load(path, root)
  local content = read_file(path)
  if not content or content == "" then
    return new_data(root)
  end
  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  local data = ok and normalize(decoded, root) or nil
  if data then
    return data
  end
  local backup = string.format("%s.corrupt-%d", path, os.time())
  vim.uv.fs_rename(path, backup)
  util.notify(string.format("could not read %s; moved it to %s and started fresh", path, backup), vim.log.levels.WARN)
  return new_data(root)
end

---Data for a context, loading it on first use.
---@param ctx hiraishin.Context
---@return hiraishin.Data
function M.get(ctx)
  local entry = cache[ctx.store]
  if not entry then
    entry = { data = load(ctx.store, ctx.root), dirty = false }
    cache[ctx.store] = entry
    -- kunai whose file is gone are stale until the file shows up again
    for _, list in pairs(entry.data.lists) do
      for _, bm in pairs(list.bookmarks) do
        if not vim.uv.fs_stat(util.abspath(entry.data.root, bm.file)) then
          bm.stale = true
        end
      end
    end
  end
  return entry.data
end

---Persist one store now.
---@param path string
---@return boolean ok
local function save(path)
  local entry = cache[path]
  if not entry or not entry.dirty then
    return true
  end
  local ok, json = pcall(vim.json.encode, entry.data)
  if not ok then
    util.notify("failed to encode bookmarks: " .. tostring(json), vim.log.levels.ERROR)
    return false
  end
  local written, err = write_atomic(path, json)
  if not written then
    util.notify(string.format("failed to write %s: %s", path, err), vim.log.levels.ERROR)
    return false
  end
  entry.dirty = false
  return true
end

---Write every dirty store immediately.
function M.flush()
  if timer then
    timer:stop()
  end
  for path in pairs(cache) do
    save(path)
  end
end

---Mark a store as changed; it is written after the debounce delay.
---@param ctx hiraishin.Context
function M.changed(ctx)
  local entry = cache[ctx.store]
  if not entry then
    return
  end
  entry.dirty = true
  local ms = config.options.storage.debounce_ms
  if ms <= 0 then
    save(ctx.store)
    return
  end
  if not timer then
    timer = vim.uv.new_timer()
  end
  timer:stop()
  timer:start(ms, 0, vim.schedule_wrap(M.flush))
end

---Drop cached data (tests, or after changing the storage directory).
function M.reset()
  M.flush()
  cache = {}
end

return M
