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
    trash = {},
  }
end

---@return string? "sec.nsec" of the file, nil when missing
local function mtime_of(path)
  local stat = vim.uv.fs_stat(path)
  return stat and (stat.mtime.sec .. "." .. stat.mtime.nsec) or nil
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

---Bring decoded JSON into shape; returns nil when it is not hiraishin data,
---or nil and "newer" when a newer hiraishin wrote it.
---@return hiraishin.Data?, "newer"?
local function normalize(data, root)
  if type(data) ~= "table" or type(data.lists) ~= "table" or type(data.version) ~= "number" then
    return nil
  end
  if data.version > M.VERSION then
    return nil, "newer"
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
      if type(list.camp) ~= "string" or not list.bookmarks[list.camp] then
        list.camp = nil
      end
    end
  end
  data.lists.default = data.lists.default or M.new_list()
  data.trash = type(data.trash) == "table" and data.trash or {}
  if type(data.active_list) ~= "string" or not data.lists[data.active_list] then
    data.active_list = "default"
  end
  return data
end

---@return hiraishin.Data?, "newer"?
local function decode(content, root)
  local ok, decoded = pcall(vim.json.decode, content or "", { luanil = { object = true, array = true } })
  if not ok then
    return nil
  end
  return normalize(decoded, root)
end

local function warn_newer(path)
  util.notify(
    string.format("%s was written by a newer hiraishin · it is left untouched until you update", path),
    vim.log.levels.WARN
  )
end

---@param path string
---@param root string?
---@return hiraishin.Data data, boolean? readonly the file is from a newer hiraishin: never write it
local function load(path, root)
  local content = read_file(path)
  if not content or content == "" then
    return new_data(root)
  end
  local data, why = decode(content, root)
  if data then
    return data
  end
  if why == "newer" then
    warn_newer(path)
    return new_data(root), true
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
    -- branch scope: until the branch has its own file, start from the project's
    local source = ctx.store
    if ctx.fork_from and not vim.uv.fs_stat(ctx.store) and vim.uv.fs_stat(ctx.fork_from) then
      source = ctx.fork_from
    end
    local data, readonly = load(source, ctx.root)
    entry = { data = data, readonly = readonly, dirty = false, mtime = mtime_of(ctx.store), root = ctx.root }
    cache[ctx.store] = entry
    -- kunai whose file is gone are stale until the file shows up again
    for _, list in pairs(entry.data.lists) do
      for _, bm in pairs(list.bookmarks) do
        if not vim.uv.fs_stat(util.abspath(entry.data.root, bm.file)) then
          bm.stale = true
        end
      end
    end
    entry.base = vim.deepcopy(entry.data)
  end
  return entry.data
end

---Pick one side of a three-way merge: a side that did not change wins over
---one that did; when both changed, the newer `updated_at` wins (ties: ours).
local function pick(base, ours, theirs)
  if vim.deep_equal(ours, theirs) then
    return ours
  end
  if base ~= nil and vim.deep_equal(ours, base) then
    return theirs
  end
  if base ~= nil and vim.deep_equal(theirs, base) then
    return ours
  end
  return ((theirs.updated_at or 0) > (ours.updated_at or 0)) and theirs or ours
end

---@param base hiraishin.List?
---@param ours hiraishin.List
---@param theirs hiraishin.List
---@return hiraishin.List
local function merge_list(base, ours, theirs)
  base = base or M.new_list()
  local out = M.new_list()
  local ids = {}
  for id in pairs(ours.bookmarks) do
    ids[id] = true
  end
  for id in pairs(theirs.bookmarks) do
    ids[id] = true
  end
  for id in pairs(ids) do
    local b, o, t = base.bookmarks[id], ours.bookmarks[id], theirs.bookmarks[id]
    if o and t then
      out.bookmarks[id] = pick(b, o, t)
    elseif not b then
      out.bookmarks[id] = o or t -- added on one side
    end
    -- in base but deleted on one side: the deletion wins
  end
  local seen = {}
  for _, order in ipairs({ ours.order, theirs.order }) do
    for _, id in ipairs(order) do
      if out.bookmarks[id] and not seen[id] then
        seen[id] = true
        table.insert(out.order, id)
      end
    end
  end
  local taken = {}
  for n = 1, 9 do
    local slot = tostring(n)
    local b, o, t = base.slots[slot], ours.slots[slot], theirs.slots[slot]
    local id = (o ~= b) and o or ((t ~= b) and t or b)
    if id and out.bookmarks[id] and not taken[id] then
      out.slots[slot] = id
      taken[id] = true
    end
  end
  -- camp: a side that moved it wins
  local camp = (ours.camp ~= base.camp) and ours.camp or ((theirs.camp ~= base.camp) and theirs.camp or base.camp)
  out.camp = camp and out.bookmarks[camp] and camp or nil
  return out
end

---Three-way merge of a store: `base` is what this Neovim last read or wrote,
---`ours` its current data, `theirs` what another Neovim wrote meanwhile.
---@param base hiraishin.Data
---@param ours hiraishin.Data
---@param theirs hiraishin.Data
---@return hiraishin.Data
function M.merge(base, ours, theirs)
  local out = { version = M.VERSION, root = ours.root or theirs.root, lists = {} }
  local names = {}
  for name in pairs(ours.lists) do
    names[name] = true
  end
  for name in pairs(theirs.lists) do
    names[name] = true
  end
  for name in pairs(names) do
    local b, o, t = base.lists[name], ours.lists[name], theirs.lists[name]
    if o and t then
      out.lists[name] = merge_list(b, o, t)
    elseif not b then
      out.lists[name] = vim.deepcopy(o or t)
    end
  end
  out.lists.default = out.lists.default or M.new_list()
  -- undo entries: union by id, minus those undone on either side
  out.trash = {}
  local seen, base_ids = {}, {}
  for _, e in ipairs(base.trash or {}) do
    base_ids[e.id or ""] = true
  end
  local function has(t, id)
    for _, e in ipairs(t or {}) do
      if e.id == id then
        return true
      end
    end
  end
  for _, side in ipairs({ ours.trash or {}, theirs.trash or {} }) do
    for _, e in ipairs(side) do
      local undone = base_ids[e.id] and not (has(ours.trash, e.id) and has(theirs.trash, e.id))
      if e.id and not seen[e.id] and not undone then
        seen[e.id] = true
        table.insert(out.trash, e)
      end
    end
  end
  table.sort(out.trash, function(a, b)
    return (a.at or 0) < (b.at or 0)
  end)
  out.active_list = out.lists[ours.active_list] and ours.active_list or "default"
  return out
end

---Listeners told (with the store path) whenever a store's data changed:
---an API change, a merge with another Neovim, or a reload from disk.
---@type fun(path: string)[]
local listeners = {}

---@param fn fun(path: string)
function M.subscribe(fn)
  table.insert(listeners, fn)
end

local function notify(path)
  for _, fn in ipairs(listeners) do
    pcall(fn, path)
  end
end

---Called with the store path after a save merged changes from disk.
---@type fun(path: string)?
M.on_merge = nil

---Persist one store now. When another Neovim wrote the file since we read
---it, the two versions are merged first.
---@param path string
---@return boolean ok
local function save(path)
  local entry = cache[path]
  if not entry or not entry.dirty then
    return true
  end
  if entry.readonly then
    entry.dirty = false
    return true
  end
  local merged = false
  local disk = mtime_of(path)
  -- no mtime: the file did not exist when we read it, so anything there now
  -- was written by another Neovim (merged against our empty start)
  if disk and disk ~= entry.mtime and entry.base then
    local theirs, why = decode(read_file(path), entry.root)
    if why == "newer" then
      entry.readonly, entry.dirty = true, false
      warn_newer(path)
      return true
    end
    if theirs then
      local result = M.merge(entry.base, entry.data, theirs)
      -- update in place: callers hold on to entry.data
      for k in pairs(entry.data) do
        entry.data[k] = nil
      end
      for k, v in pairs(result) do
        entry.data[k] = v
      end
      merged = true
    end
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
  entry.mtime = mtime_of(path)
  entry.base = vim.json.decode(json, { luanil = { object = true, array = true } })
  if merged then
    if M.on_merge then
      M.on_merge(path)
    end
    notify(path)
  end
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
  notify(ctx.store)
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

---Reload stores whose file changed on disk (another Neovim wrote it) and
---that have no unsaved changes here.
---@return table<string, boolean> reloaded store paths
function M.reload_changed()
  local reloaded = {}
  for path, entry in pairs(cache) do
    local now = mtime_of(path)
    if now and now ~= entry.mtime and not entry.dirty then
      local data, readonly = load(path, entry.root)
      entry.data, entry.readonly = data, readonly
      entry.base = vim.deepcopy(data)
      entry.mtime = now
      reloaded[path] = true
      notify(path)
    end
  end
  return reloaded
end

---Store files currently loaded in this Neovim.
---@return table<string, boolean>
function M.loaded()
  local out = {}
  for path in pairs(cache) do
    out[path] = true
  end
  return out
end

---Drop cached data (tests, or after changing the storage directory).
function M.reset()
  M.flush()
  cache = {}
end

return M
