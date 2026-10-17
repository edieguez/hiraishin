local config = require("hiraishin.config")
local events = require("hiraishin.events")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local signs = require("hiraishin.signs")
local store = require("hiraishin.store")
local tracker = require("hiraishin.tracker")
local util = require("hiraishin.util")

local M = {}

local did_setup = false

local function is_file_buf(bufnr)
  return vim.api.nvim_buf_is_loaded(bufnr) and util.buf_path(bufnr) ~= nil
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  store.reset()
  tracker.reset()
  scope.invalidate()
  signs.setup_highlights()

  local group = vim.api.nvim_create_augroup("hiraishin", { clear = true })
  -- BufReadPost also fires on :e! and when a changed file is reloaded
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(ev)
      scope.invalidate(ev.buf)
      tracker.attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      tracker.sync(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufFilePre", {
    group = group,
    callback = function(ev)
      -- :saveas also renames a hidden, unloaded alternate buffer to the old
      -- name; only loaded buffers are real renames
      if vim.api.nvim_buf_is_loaded(ev.buf) then
        vim.b[ev.buf].hiraishin_old_name = util.buf_path(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = group,
    callback = function(ev)
      if not vim.api.nvim_buf_is_loaded(ev.buf) then
        return
      end
      local old = vim.b[ev.buf].hiraishin_old_name
      vim.b[ev.buf].hiraishin_old_name = nil
      local new = util.buf_path(ev.buf)
      if old and new and old ~= new then
        M.rename(old, new)
      end
      if tracker.is_tracked(ev.buf) then
        tracker.retarget(ev.buf)
      else
        scope.invalidate(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      tracker.detach(ev.buf)
      scope.invalidate(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      scope.invalidate()
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = signs.setup_highlights,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = store.flush,
  })
  require("hiraishin.integrations.rename").setup(group)

  require("hiraishin.keymaps").setup()
  did_setup = true
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_file_buf(bufnr) then
      tracker.attach(bufnr)
    end
  end
end

local function ensure_setup()
  if not did_setup then
    M.setup()
  end
end

---Buffer and 1-based line the operation targets.
---@return integer bufnr, integer line, integer col
local function target(opts)
  local bufnr = opts.bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if opts.line then
    return bufnr, opts.line, opts.col or 0
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    error("hiraishin: opts.line is required for a buffer not shown in a window", 2)
  end
  local pos = vim.api.nvim_win_get_cursor(win)
  return bufnr, pos[1], pos[2]
end

---Context of a file buffer, making sure the tracker follows it.
---@return hiraishin.Context?, string?
local function buf_ctx(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local ctx, err = scope.for_buf(bufnr)
  if ctx and not tracker.is_tracked(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
    tracker.attach(bufnr)
  end
  return ctx, err
end

---@param ctx hiraishin.Context
local function line_fn(ctx)
  return function(bm)
    return (tracker.live_line(ctx, bm))
  end
end

---Copy of a bookmark with its live line (and stale when its line was deleted).
---@param ctx hiraishin.Context
---@param bm hiraishin.Bookmark
local function snapshot(ctx, bm)
  local copy = vim.deepcopy(bm)
  local line, invalid = tracker.live_line(ctx, bm)
  if line then
    copy.line = line
  end
  copy.stale = bm.stale or invalid
  return copy
end

---@param ctx hiraishin.Context
local function changed(ctx, replace)
  store.changed(ctx)
  tracker.reconcile({ store = ctx.store }, replace)
end

---Add a bookmark on a line. On a line that already has one, its name/note are
---updated instead and the existing bookmark is returned.
---@param opts? { name?: string, note?: string, bufnr?: integer, line?: integer, col?: integer }
---@return hiraishin.Bookmark? bookmark, string? err_or_status
function M.add(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line, col = target(opts)
  local ctx, err = buf_ctx(bufnr)
  if not ctx then
    return nil, err
  end
  if line < 1 or line > vim.api.nvim_buf_line_count(bufnr) then
    return nil, "line out of range"
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local name, note = util.trim(opts.name), util.trim(opts.note)
  local existing = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  if name and list_ops.find_name(list, name, existing and existing.id) then
    return nil, string.format("a kunai named '%s' already exists", name)
  end

  if existing then
    if name or note then
      existing.name = name or existing.name
      existing.note = note or existing.note
      existing.updated_at = os.time()
      changed(ctx)
      events.emit("HiraishinUpdate", { bookmark = snapshot(ctx, existing), list = list_name })
    end
    return snapshot(ctx, existing), "exists"
  end

  local now = os.time()
  local bm = {
    id = util.new_id(list.bookmarks),
    file = ctx.file,
    line = line,
    col = col,
    name = name,
    note = note,
    anchor = util.anchor(bufnr, line),
    stale = false,
    created_at = now,
    updated_at = now,
  }
  list_ops.insert(list, bm)
  changed(ctx)
  events.emit("HiraishinAdd", { bookmark = vim.deepcopy(bm), list = list_name })
  return vim.deepcopy(bm)
end

---Remove a bookmark by id or name, in the scope of `opts.bufnr` (default: current).
---@param key string
---@param opts? { bufnr?: integer, reason?: string }
---@return hiraishin.Bookmark? removed, string? err
function M.remove(key, opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local list, list_name = list_ops.active(store.get(ctx))
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("no kunai '%s'", key)
  end
  local copy = snapshot(ctx, bm)
  list_ops.delete(list, bm.id)
  changed(ctx)
  events.emit("HiraishinRemove", { bookmark = copy, list = list_name, reason = opts.reason or "api" })
  return copy
end

---Add a bookmark on the line, or remove the one already there.
---@param opts? { bufnr?: integer, line?: integer }
---@return hiraishin.Bookmark? bookmark, "added"|"removed"|nil action, string? err
function M.toggle(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line = target(opts)
  local ctx, err = buf_ctx(bufnr)
  if not ctx then
    return nil, nil, err
  end
  local list = list_ops.active(store.get(ctx))
  local existing = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  if existing then
    local removed = M.remove(existing.id, { bufnr = bufnr, reason = "toggle" })
    return removed, "removed"
  end
  local bm, add_err = M.add({ bufnr = bufnr, line = line, col = opts.col })
  return bm, bm and "added" or nil, add_err
end

---@param slot any
---@return string? slot key "1".."9"
local function slot_key(slot)
  local n = tonumber(slot)
  if n and n >= 1 and n <= 9 and n == math.floor(n) then
    return tostring(n)
  end
end

---Change a bookmark's name, note or seal (slot). Pass `false` to clear a field.
---Giving a seal that another kunai holds moves the seal to this one.
---@param key string id or name
---@param fields { name?: string|false, note?: string|false, slot?: integer|false }
---@param opts? { bufnr?: integer }
---@return hiraishin.Bookmark? bookmark, string? err
function M.update(key, fields, opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local list, list_name = list_ops.active(store.get(ctx))
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("no kunai '%s'", key)
  end
  local new_slot
  if fields.slot then
    new_slot = slot_key(fields.slot)
    if not new_slot then
      return nil, "seals go from 1 to 9"
    end
  end
  if fields.name ~= nil then
    local name = fields.name and util.trim(fields.name) or nil
    if name and list_ops.find_name(list, name, bm.id) then
      return nil, string.format("a kunai named '%s' already exists", name)
    end
    bm.name = name
  end
  if fields.note ~= nil then
    bm.note = fields.note and util.trim(fields.note) or nil
  end
  if fields.slot ~= nil then
    local current = list_ops.slot_of(list, bm.id)
    if current then
      list.slots[current] = nil
    end
    if new_slot then
      list.slots[new_slot] = bm.id
    end
  end
  bm.updated_at = os.time()
  changed(ctx)
  events.emit("HiraishinUpdate", { bookmark = snapshot(ctx, bm), list = list_name })
  return snapshot(ctx, bm)
end

---Seal (slot) number of a bookmark in the active list.
---@param key string id or name
---@param opts? { bufnr?: integer }
---@return integer?
function M.slot_of(key, opts)
  ensure_setup()
  opts = opts or {}
  local list = list_ops.active(store.get(scope.resolve(opts.bufnr)))
  local bm = list_ops.find(list, key)
  local slot = bm and list_ops.slot_of(list, bm.id)
  return slot and tonumber(slot) or nil
end

---Put seal `n` on the kunai of the cursor line, placing one if needed.
---@param n integer 1..9
---@return hiraishin.Bookmark? bookmark, string? err
function M.seal(n)
  ensure_setup()
  if not slot_key(n) then
    return nil, "seals go from 1 to 9"
  end
  local bm = M.at_cursor()
  if not bm then
    local err
    bm, err = M.add()
    if not bm then
      return nil, err
    end
  end
  return M.update(bm.id, { slot = n })
end

---Resolve a jump target: a seal number (1..9) or an id/name.
---@return hiraishin.Context?, hiraishin.Bookmark?, string? list_name, string? err
local function resolve_target(key, opts)
  local ctx = scope.resolve(opts.bufnr)
  local list, list_name = list_ops.active(store.get(ctx))
  local slot = slot_key(key)
  local bm
  if slot then
    local id = list.slots[slot]
    bm = id and list.bookmarks[id] or nil
    if not bm then
      return nil, nil, nil, string.format("seal %s is empty", slot)
    end
  else
    bm = list_ops.find(list, tostring(key))
    if not bm then
      return nil, nil, nil, string.format("no kunai '%s'", key)
    end
  end
  return ctx, bm, list_name
end

---Jump to a kunai by seal number or name/id.
---@param key integer|string
---@param opts? { split?: "vsplit"|"split"|"tab", bufnr?: integer }
---@return hiraishin.Bookmark? bookmark, string? err
function M.jump(key, opts)
  ensure_setup()
  opts = opts or {}
  local ctx, bm, list_name, err = resolve_target(key, opts)
  if not ctx then
    return nil, err
  end
  return require("hiraishin.nav").jump(ctx, bm, list_name, opts)
end

---Jump to the next kunai: in this buffer by line (default), or across files
---in list order with `scope = "list"`.
---@param opts? { count?: integer, wrap?: boolean, scope?: "buffer"|"list" }
---@return hiraishin.Bookmark? bookmark, string? err
function M.next(opts)
  ensure_setup()
  opts = opts or {}
  local nav = require("hiraishin.nav")
  if opts.scope == "list" then
    return nav.step_list(1, opts)
  end
  return nav.step_buffer(1, opts)
end

---Jump to the previous kunai. See next().
---@param opts? { count?: integer, wrap?: boolean, scope?: "buffer"|"list" }
---@return hiraishin.Bookmark? bookmark, string? err
function M.prev(opts)
  ensure_setup()
  opts = opts or {}
  local nav = require("hiraishin.nav")
  if opts.scope == "list" then
    return nav.step_list(-1, opts)
  end
  return nav.step_buffer(-1, opts)
end

---Open the picker.
---@param opts? { filter?: "buffer"|"all", backend?: string }
function M.pick(opts)
  ensure_setup()
  return require("hiraishin.picker").open(opts)
end

---Send the active list (or every list with `all`) to the quickfix/location list.
---@param opts? { loclist?: boolean, all?: boolean, open?: boolean }
---@return integer count
function M.to_quickfix(opts)
  ensure_setup()
  opts = opts or {}
  local picker = require("hiraishin.picker")
  local entries, ctx = picker.entries({ filter = opts.all and "all" or nil })
  local data = store.get(ctx)
  picker.actions.quickfix(entries, {
    loclist = opts.loclist,
    open = opts.open,
    title = "Hiraishin: " .. (opts.all and "all lists" or data.active_list),
  })
  return #entries
end

---Edit the note of the cursor line's kunai in a floating window.
function M.note()
  ensure_setup()
  return require("hiraishin.note").edit()
end

---@param key string id or name
---@param opts? { bufnr?: integer }
---@return hiraishin.Bookmark?
function M.get(key, opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local list = list_ops.active(store.get(ctx))
  local bm = list_ops.find(list, key)
  return bm and snapshot(ctx, bm) or nil
end

---Bookmarks of the active list (copies with live lines). `bufnr` limits to
---that buffer's file.
---@param opts? { bufnr?: integer, include_stale?: boolean }
---@return hiraishin.Bookmark[]
function M.list(opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local list = list_ops.active(store.get(ctx))
  local file = opts.bufnr and ctx.file or nil
  local out = {}
  for _, bm in ipairs(list_ops.items(list, file)) do
    local copy = snapshot(ctx, bm)
    if opts.include_stale ~= false or not copy.stale then
      table.insert(out, copy)
    end
  end
  return out
end

---Bookmark on the cursor line of the current buffer, if any.
---@return hiraishin.Bookmark?
function M.at_cursor()
  ensure_setup()
  local ctx = buf_ctx(0)
  if not ctx then
    return nil
  end
  local list = list_ops.active(store.get(ctx))
  local bm = list_ops.find_at(list, ctx.file, vim.api.nvim_win_get_cursor(0)[1], line_fn(ctx))
  return bm and snapshot(ctx, bm) or nil
end

---Stale bookmarks of the active list (or every list with `all = true`).
---@param opts? { bufnr?: integer, all?: boolean }
---@return { bookmark: hiraishin.Bookmark, list: string }[]
function M.stale(opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local data = store.get(ctx)
  local out = {}
  local names = opts.all and vim.tbl_keys(data.lists) or { data.active_list }
  table.sort(names)
  for _, name in ipairs(names) do
    for _, bm in ipairs(list_ops.items(data.lists[name])) do
      local copy = snapshot(ctx, bm)
      if copy.stale then
        table.insert(out, { bookmark = copy, list = name })
      end
    end
  end
  return out
end

---Delete stale bookmarks (every list by default).
---@param opts? { bufnr?: integer, all?: boolean }
---@return { bookmark: hiraishin.Bookmark, list: string }[] removed
function M.prune(opts)
  ensure_setup()
  opts = vim.tbl_extend("force", { all = true }, opts or {})
  local ctx = scope.resolve(opts.bufnr)
  local data = store.get(ctx)
  local removed = M.stale(opts)
  for _, r in ipairs(removed) do
    list_ops.delete(data.lists[r.list], r.bookmark.id)
    events.emit("HiraishinRemove", { bookmark = r.bookmark, list = r.list, reason = "prune" })
  end
  if #removed > 0 then
    changed(ctx)
  end
  return removed
end

---Re-attach a bookmark (stale or not) to a line, by default the cursor line.
---@param key string id or name
---@param opts? { bufnr?: integer, line?: integer }
---@return hiraishin.Bookmark? bookmark, string? err
function M.relocate(key, opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line = target(opts)
  local ctx, err = buf_ctx(bufnr)
  if not ctx then
    return nil, err
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("no kunai '%s'", key)
  end
  local occupant = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  if occupant and occupant.id ~= bm.id then
    return nil, "another kunai already marks this line"
  end
  local from = { file = bm.file, line = bm.line }
  bm.file = ctx.file
  bm.line = line
  bm.anchor = util.anchor(bufnr, line)
  bm.stale = false
  bm.updated_at = os.time()
  changed(ctx, { [bm.id] = true })
  events.emit("HiraishinMoved", {
    bookmark = vim.deepcopy(bm),
    list = list_name,
    from = from.line,
    from_file = from.file,
    reason = "relocate",
  })
  return vim.deepcopy(bm)
end

---Move bookmarks after a file or directory was renamed outside the usual
---autocmds (file managers call this through hiraishin.integrations.rename).
---@param from string absolute old path (file or directory)
---@param to string absolute new path
---@return integer moved number of bookmarks updated
function M.rename(from, to)
  ensure_setup()
  from = util.realpath(from)
  to = util.realpath(to)
  if from == to then
    return 0
  end
  local src = scope.for_path(from)
  local data = store.get(src)
  local moved = 0
  for list_name, list in pairs(data.lists) do
    for _, bm in ipairs(list_ops.items(list)) do
      local abs = util.abspath(src.root, bm.file)
      local new_abs
      if abs == from then
        new_abs = to
      elseif vim.startswith(abs, from .. "/") then
        new_abs = to .. abs:sub(#from + 1)
      end
      if new_abs then
        local old_file = bm.file
        local dst = scope.for_path(new_abs)
        if dst.store == src.store then
          bm.file = dst.file
        else
          -- moved into another project: carry it over to the same list name
          list_ops.delete(list, bm.id)
          local ddata = store.get(dst)
          ddata.lists[list_name] = ddata.lists[list_name] or store.new_list()
          local dlist = ddata.lists[list_name]
          if dlist.bookmarks[bm.id] then
            bm.id = util.new_id(dlist.bookmarks)
          end
          bm.file = dst.file
          list_ops.insert(dlist, bm)
          store.changed(dst)
          tracker.reconcile({ store = dst.store })
        end
        moved = moved + 1
        events.emit("HiraishinMoved", {
          bookmark = vim.deepcopy(bm),
          list = list_name,
          from = bm.line,
          from_file = old_file,
          reason = "rename",
        })
      end
    end
  end
  if moved > 0 then
    store.changed(src)
    -- buffers already showing the new path pick their kunai up
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local abs = vim.api.nvim_buf_is_loaded(bufnr) and util.buf_path(bufnr) or nil
      if abs and (abs == to or vim.startswith(abs, to .. "/")) then
        if tracker.is_tracked(bufnr) then
          tracker.retarget(bufnr)
        else
          scope.invalidate(bufnr)
          tracker.attach(bufnr)
        end
      end
    end
    tracker.reconcile({ store = src.store })
  end
  return moved
end

return M
