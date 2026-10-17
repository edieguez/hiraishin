local config = require("hiraishin.config")
local events = require("hiraishin.events")
local history = require("hiraishin.history")
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
  scope.set_session_scope(nil)
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
      M.refresh()
    end,
  })
  -- another Neovim may have written the store, or the git branch changed
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if tracker.is_tracked(ev.buf) then
        tracker.cursor_virt(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      if tracker.is_tracked(ev.buf) then
        tracker.render_ranges(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function(ev)
      if config.options.note_hover and tracker.is_tracked(ev.buf) then
        require("hiraishin.note").hover(ev.buf)
      end
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
  -- another Neovim changed the same store: redraw with the merged result
  store.on_merge = function(path)
    vim.schedule(function()
      tracker.reconcile({ store = path })
    end)
  end
  -- Snacks.picker.hiraishin(), when snacks is loaded now or later (lazy.nvim)
  local function register_snacks()
    local snacks = package.loaded["snacks"]
    if type(snacks) == "table" and type(snacks.picker) == "table" then
      rawset(snacks.picker, "hiraishin", function(o)
        M.pick(vim.tbl_extend("force", o or {}, { backend = "snacks" }))
      end)
    end
  end
  vim.schedule(register_snacks)
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == "snacks.nvim" then
        vim.schedule(register_snacks)
      end
    end,
  })

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
local function buf_ctx(bufnr, global)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if global then
    local abs, err = util.buf_path(bufnr)
    if not abs then
      return nil, err
    end
    if not tracker.is_tracked(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      tracker.attach(bufnr)
    end
    return scope.global_ctx(bufnr)
  end
  local ctx, err = scope.for_buf(bufnr)
  if ctx and not tracker.is_tracked(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
    tracker.attach(bufnr)
  end
  return ctx, err
end

---Store context for an operation: the global store with `opts.global`
---(global kunai from any scope), otherwise the buffer's scope.
---@param opts { bufnr?: integer, global?: boolean }
local function resolve(opts)
  if opts.global then
    return scope.global_ctx(opts.bufnr or 0)
  end
  return scope.resolve(opts.bufnr)
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
---@param opts? { name?: string, note?: string, bufnr?: integer, line?: integer, col?: integer, seal_only?: boolean }
---@return hiraishin.Bookmark? bookmark, string? err_or_status
function M.add(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line, col = target(opts)
  local ctx, err = buf_ctx(bufnr, opts.global)
  if not ctx then
    return nil, err
  end
  if line < 1 or line > vim.api.nvim_buf_line_count(bufnr) then
    return nil, "Line out of range"
  end
  local end_line = opts.end_line
  if end_line ~= nil and (end_line <= line or end_line > vim.api.nvim_buf_line_count(bufnr)) then
    return nil, "The range must end after its first line, inside the file"
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local name, note = util.trim(opts.name), util.trim(opts.note)
  local existing = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  local problem = name and list_ops.name_problem(list, name, existing and existing.id)
  if problem then
    return nil, problem
  end

  if existing then
    if name or note or existing.seal_only or end_line then
      existing.name = name or existing.name
      existing.note = note or existing.note
      existing.seal_only = nil -- placed on purpose now: it outlives its seal
      existing.updated_at = os.time()
      if end_line then
        existing.end_line = end_line
        changed(ctx, { [existing.id] = true })
      else
        changed(ctx)
      end
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
    end_line = end_line, -- range kunai: last line of the range
    stale = false,
    -- created by sealing a bare line: it goes away when it loses its seal
    seal_only = opts.seal_only or nil,
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
  local ctx = resolve(opts)
  local list, list_name = list_ops.active(store.get(ctx))
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("No kunai '%s'", key)
  end
  local copy = snapshot(ctx, bm)
  history.record(ctx, { history.item(ctx, list_name, list, bm) }, opts.reason or "api")
  list_ops.delete(list, bm.id)
  changed(ctx)
  events.emit("HiraishinRemove", { bookmark = copy, list = list_name, reason = opts.reason or "api" })
  return copy
end

---Add a bookmark on the line, or remove the one already there.
---@param opts? { bufnr?: integer, line?: integer, end_line?: integer, global?: boolean }
---@return hiraishin.Bookmark? bookmark, "added"|"removed"|nil action, string? err
function M.toggle(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line = target(opts)
  local ctx, err = buf_ctx(bufnr, opts.global)
  if not ctx then
    return nil, nil, err
  end
  local list = list_ops.active(store.get(ctx))
  local existing = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  if existing then
    local removed = M.remove(existing.id, { bufnr = bufnr, reason = "toggle", global = opts.global })
    return removed, "removed"
  end
  local bm, add_err =
    M.add({ bufnr = bufnr, line = line, end_line = opts.end_line, col = opts.col, global = opts.global })
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
---@return hiraishin.Bookmark? bookmark, string? err, hiraishin.Bookmark? displaced kunai that lost the seal
function M.update(key, fields, opts)
  ensure_setup()
  opts = opts or {}
  local ctx = resolve(opts)
  local list, list_name = list_ops.active(store.get(ctx))
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("No kunai '%s'", key)
  end
  local new_slot
  if fields.slot then
    new_slot = slot_key(fields.slot)
    if not new_slot then
      return nil, "Seals go from 1 to 9"
    end
  end
  if fields.name ~= nil then
    local name = fields.name and util.trim(fields.name) or nil
    local problem = name and list_ops.name_problem(list, name, bm.id)
    if problem then
      return nil, problem
    end
    bm.name = name
  end
  if fields.note ~= nil then
    bm.note = fields.note and util.trim(fields.note) or nil
  end
  if bm.name or bm.note then
    bm.seal_only = nil -- a named/noted kunai is kept for its own sake
  end
  local displaced
  local unsealed = {} -- kunai that lost their seal
  if fields.slot ~= nil then
    local current = list_ops.slot_of(list, bm.id)
    if current then
      list.slots[current] = nil
    end
    if new_slot then
      local holder = list.slots[new_slot]
      if holder and holder ~= bm.id and list.bookmarks[holder] then
        displaced = snapshot(ctx, list.bookmarks[holder])
        table.insert(unsealed, { bm = list.bookmarks[holder], slot = new_slot })
      end
      list.slots[new_slot] = bm.id
    elseif current then
      table.insert(unsealed, { bm = bm, slot = current })
    end
  end
  bm.updated_at = os.time()
  -- seals are quick jumps: a kunai that only existed for its seal goes with it
  local dropped = M._drop_unsealed(ctx, list, list_name, unsealed, "seal")
  if displaced and dropped[displaced.id] then
    displaced.removed = true
  end
  changed(ctx)
  if dropped[bm.id] then
    local copy = snapshot(ctx, bm)
    copy.removed = true
    return copy, nil, displaced
  end
  events.emit("HiraishinUpdate", { bookmark = snapshot(ctx, bm), list = list_name })
  return snapshot(ctx, bm), nil, displaced
end

---Delete the seal-only kunai among `items` ({ bm, slot = the seal it had })
---that no longer hold a seal; undo brings them back with that seal when it is
---free. Does not save; the caller does.
---@return table<string, boolean> dropped ids
function M._drop_unsealed(ctx, list, list_name, items, reason)
  local dropped, records = {}, {}
  for _, it in ipairs(items) do
    local bm = it.bm
    if bm.seal_only and not bm.name and not bm.note and not list_ops.slot_of(list, bm.id) then
      table.insert(records, { bm = bm, slot = it.slot, copy = snapshot(ctx, bm) })
    end
  end
  if #records == 0 then
    return dropped
  end
  history.record(
    ctx,
    vim.tbl_map(function(r)
      local item = history.item(ctx, list_name, list, r.bm)
      item.slot = item.slot or r.slot
      return item
    end, records),
    reason
  )
  for _, r in ipairs(records) do
    list_ops.delete(list, r.bm.id)
    dropped[r.bm.id] = true
    events.emit("HiraishinRemove", { bookmark = r.copy, list = list_name, reason = reason })
  end
  return dropped
end

---Seal (slot) number of a bookmark in the active list.
---@param key string id or name
---@param opts? { bufnr?: integer }
---@return integer?
function M.slot_of(key, opts)
  ensure_setup()
  opts = opts or {}
  local list = list_ops.active(store.get(resolve(opts)))
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
    return nil, "Seals go from 1 to 9"
  end
  local bm = M.at_cursor()
  if not bm then
    local err
    bm, err = M.add({ seal_only = true })
    if not bm then
      return nil, err
    end
  end
  return M.update(bm.id, { slot = n })
end

---Resolve a jump target: a seal number (1..9) or an id/name.
---@return hiraishin.Context?, hiraishin.Bookmark?, string? list_name, string? err
local function resolve_target(key, opts)
  local ctx = resolve(opts)
  local list, list_name = list_ops.active(store.get(ctx))
  local slot = slot_key(key)
  local bm
  if slot then
    local id = list.slots[slot]
    bm = id and list.bookmarks[id] or nil
    if not bm then
      return nil,
        nil,
        nil,
        string.format(
          "Seal %s is empty · %s seals this line",
          slot,
          require("hiraishin.ui").hint("assign_slot_" .. slot, ":Hiraishin seal " .. slot)
        )
    end
  else
    bm = list_ops.find(list, tostring(key))
    if not bm then
      return nil, nil, nil, string.format("No kunai '%s'", key)
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
---@param opts? { count?: integer, wrap?: boolean, scope?: "buffer"|"list"|"seal" }
---@return hiraishin.Bookmark? bookmark, string? err
function M.next(opts)
  ensure_setup()
  opts = opts or {}
  local nav = require("hiraishin.nav")
  if opts.scope == "list" then
    return nav.step_list(1, opts)
  elseif opts.scope == "seal" then
    return nav.step_seal(1, opts)
  end
  return nav.step_buffer(1, opts)
end

---Jump to the previous kunai. See next().
---@param opts? { count?: integer, wrap?: boolean, scope?: "buffer"|"list"|"seal" }
---@return hiraishin.Bookmark? bookmark, string? err
function M.prev(opts)
  ensure_setup()
  opts = opts or {}
  local nav = require("hiraishin.nav")
  if opts.scope == "list" then
    return nav.step_list(-1, opts)
  elseif opts.scope == "seal" then
    return nav.step_seal(-1, opts)
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
  local ctx = resolve(opts)
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
  local ctx = resolve(opts)
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
function M.at_cursor(opts)
  ensure_setup()
  opts = opts or {}
  local ctx = buf_ctx(0)
  if not ctx then
    return nil
  end
  local list = list_ops.active(store.get(ctx))
  local bm = list_ops.find_at(list, ctx.file, opts.line or vim.api.nvim_win_get_cursor(0)[1], line_fn(ctx))
  return bm and snapshot(ctx, bm) or nil
end

---Stale bookmarks of the active list (or every list with `all = true`).
---@param opts? { bufnr?: integer, all?: boolean }
---@return { bookmark: hiraishin.Bookmark, list: string }[]
function M.stale(opts)
  ensure_setup()
  opts = opts or {}
  local ctx = resolve(opts)
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
  local ctx = resolve(opts)
  local data = store.get(ctx)
  local removed = M.stale(opts)
  local items = {}
  for _, r in ipairs(removed) do
    local list = data.lists[r.list]
    table.insert(items, history.item(ctx, r.list, list, list.bookmarks[r.bookmark.id]))
  end
  history.record(ctx, items, "prune")
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
  local ctx, err = buf_ctx(bufnr, opts.global)
  if not ctx then
    return nil, err
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local bm = list_ops.find(list, key)
  if not bm then
    return nil, string.format("No kunai '%s'", key)
  end
  local occupant = list_ops.find_at(list, ctx.file, line, line_fn(ctx))
  if occupant and occupant.id ~= bm.id then
    return nil, "Another kunai already marks this line"
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
    from_path = util.abspath(ctx.root, from.file),
    reason = "relocate",
  })
  return vim.deepcopy(bm)
end

---Bring back the most recently deleted kunai (toggle, delete, picker,
---manager or prune). Their seal comes back if it is still free.
---@return integer? restored, string? err_or_notice
function M.undo()
  ensure_setup()
  -- the latest deletion here, or of a global kunai seen from here
  local ctx = scope.resolve(0)
  if ctx.scope ~= "global" and config.options.global_kunai then
    local g = scope.global_ctx()
    local function last_at(c)
      local t = store.get(c).trash or {}
      return t[#t] and t[#t].at or nil
    end
    local ga, pa = last_at(g), last_at(ctx)
    if ga and (not pa or ga > pa) then
      ctx = g
    end
  end
  local entry = history.pop(ctx)
  if not entry then
    return nil, "Nothing to undo"
  end
  local data = store.get(ctx)
  local restored, notes = 0, {}
  -- restore in original order so positions line up
  table.sort(entry.items, function(a, b)
    return a.index < b.index
  end)
  for _, item in ipairs(entry.items) do
    data.lists[item.list] = data.lists[item.list] or store.new_list()
    local list = data.lists[item.list]
    local bm = vim.deepcopy(item.bookmark)
    local occupant = list_ops.find_at(list, bm.file, bm.line, line_fn(ctx))
    if occupant then
      table.insert(notes, string.format("%s:%d already has a kunai", bm.file, bm.line))
    else
      if list.bookmarks[bm.id] then
        bm.id = util.new_id(list.bookmarks)
      end
      if bm.name and list_ops.find_name(list, bm.name) then
        table.insert(notes, string.format("name '%s' is taken; restored without it", bm.name))
        bm.name = nil
      end
      bm.updated_at = os.time()
      list.bookmarks[bm.id] = bm
      table.insert(list.order, math.min(item.index, #list.order + 1), bm.id)
      if item.slot and not list.slots[item.slot] then
        list.slots[item.slot] = bm.id
      end
      restored = restored + 1
      events.emit("HiraishinAdd", { bookmark = vim.deepcopy(bm), list = item.list, reason = "undo" })
    end
  end
  changed(ctx) -- also saves the shorter trash
  return restored, #notes > 0 and table.concat(notes, "; ") or nil
end

---Pick up outside changes: a store written by another Neovim instance, or
---(branch scope) a checkout of another branch. Runs on FocusGained.
function M.refresh()
  if not did_setup then
    return
  end
  local reattach = {}
  local any_branch = false
  for _, ctx in pairs(tracker.tracked()) do
    any_branch = any_branch or ctx.scope == "branch"
  end
  if any_branch or scope.effective_scope() == "branch" then
    scope.invalidate()
    for bufnr, ctx in pairs(tracker.tracked()) do
      local now = scope.for_buf(bufnr)
      if now and now.store ~= ctx.store then
        reattach[bufnr] = true
      end
    end
    if next(reattach) then
      store.flush()
    end
  end
  local reloaded = store.reload_changed()
  for bufnr, ctx in pairs(tracker.tracked()) do
    if reloaded[ctx.store] then
      reattach[bufnr] = true
    end
  end
  for bufnr in pairs(reattach) do
    tracker.attach(bufnr)
  end
  if next(reattach) then
    events.emit("HiraishinListChanged", { reason = "refresh" })
  end
end

---List names of the current scope (sorted) and the active one.
---@param opts? { bufnr?: integer }
---@return string[] names, string active, table<string, integer> counts
function M.lists(opts)
  ensure_setup()
  opts = opts or {}
  local data = store.get(resolve(opts))
  local names, counts = {}, {}
  for name, list in pairs(data.lists) do
    table.insert(names, name)
    counts[name] = #list.order
  end
  table.sort(names)
  return names, data.active_list, counts
end

---Make `name` the active list, creating it when needed.
---@param name string
---@param opts? { bufnr?: integer }
---@return string? name, string? err
function M.set_list(name, opts)
  ensure_setup()
  opts = opts or {}
  name = util.trim(name)
  if not name then
    return nil, "A list needs a name"
  end
  local ctx = resolve(opts)
  local data = store.get(ctx)
  local previous = data.active_list
  local created = data.lists[name] == nil
  data.lists[name] = data.lists[name] or store.new_list()
  data.active_list = name
  changed(ctx)
  events.emit("HiraishinListChanged", { list = name, previous = previous, created = created })
  return name
end

---Delete a list (not "default"). :Hiraishin undo brings its kunai back.
---@param name string
---@param opts? { bufnr?: integer }
---@return boolean? ok, string? err
function M.delete_list(name, opts)
  ensure_setup()
  opts = opts or {}
  if name == "default" then
    return nil, "The default list cannot be deleted"
  end
  local ctx = resolve(opts)
  local data = store.get(ctx)
  local list = data.lists[name]
  if not list then
    return nil, string.format("No list '%s'", name)
  end
  local items = {}
  for _, bm in ipairs(list_ops.items(list)) do
    table.insert(items, history.item(ctx, name, list, bm))
  end
  history.record(ctx, items, "list")
  data.lists[name] = nil
  local previous = data.active_list
  if data.active_list == name then
    data.active_list = "default"
  end
  changed(ctx)
  events.emit("HiraishinListChanged", { list = data.active_list, previous = previous, deleted = name })
  return true
end

---Switch scope for this session: "project", "global" or "branch".
---@param new_scope string
---@return boolean? ok, string? err
function M.set_scope(new_scope)
  ensure_setup()
  if new_scope ~= "project" and new_scope ~= "global" and new_scope ~= "branch" then
    return nil, "Scope must be project, global or branch"
  end
  store.flush()
  scope.set_session_scope(new_scope)
  scope.invalidate()
  tracker.reset()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_file_buf(bufnr) then
      tracker.attach(bufnr)
    end
  end
  events.emit("HiraishinListChanged", { scope = new_scope })
  return true
end

---Statusline text for a buffer: "⚡3" (kunai in it) plus "[list]" when the
---active list is not "default". Empty when there is nothing to say.
---@param bufnr? integer
---@return string
function M.status(bufnr)
  if not did_setup then
    return ""
  end
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local ctx = scope.for_buf(bufnr)
  if not ctx then
    return ""
  end
  local list, name = list_ops.active(store.get(ctx))
  local count = 0
  for _, bm in ipairs(list_ops.items(list, ctx.file)) do
    local line, invalid = tracker.live_line(ctx, bm)
    if line and not invalid then
      count = count + 1
    end
  end
  local parts = {}
  if count > 0 then
    table.insert(parts, (signs.icons()) .. count)
  end
  if name ~= "default" then
    table.insert(parts, "[" .. name .. "]")
  end
  return table.concat(parts, " ")
end

---Turn the global marks A-Z into named kunai ("mark A", ...) in the active
---list of each file's scope. Marks on lines that already have a kunai are skipped.
---@return integer imported
function M.import_marks()
  ensure_setup()
  local anchor = require("hiraishin.anchor")
  local imported, touched = 0, {}
  for code = string.byte("A"), string.byte("Z") do
    local letter = string.char(code)
    local mark = vim.api.nvim_get_mark(letter, {})
    local row, col, name = mark[1], mark[2], mark[4]
    if row > 0 and name ~= "" then
      local abs = util.realpath(vim.fn.fnamemodify(name, ":p"))
      if vim.fn.filereadable(abs) == 1 then
        local ctx = scope.for_path(abs)
        local list, list_name = list_ops.active(store.get(ctx))
        if not list_ops.find_at(list, ctx.file, row, line_fn(ctx)) then
          local lines = vim.fn.readfile(abs)
          local bm_name = "mark " .. letter
          if list_ops.find_name(list, bm_name) then
            bm_name = nil
          end
          local now = os.time()
          local bm = {
            id = util.new_id(list.bookmarks),
            file = ctx.file,
            line = math.min(row, math.max(1, #lines)),
            col = col,
            name = bm_name,
            anchor = anchor.capture(lines, math.min(row, math.max(1, #lines))),
            stale = false,
            created_at = now,
            updated_at = now,
          }
          list_ops.insert(list, bm)
          events.emit("HiraishinAdd", { bookmark = vim.deepcopy(bm), list = list_name, reason = "import" })
          imported = imported + 1
          touched[ctx.store] = ctx
        end
      end
    end
  end
  for _, ctx in pairs(touched) do
    changed(ctx)
  end
  return imported
end

---Open the manager: an editable buffer of the active list.
---@param opts? { list?: string }
function M.manager(opts)
  ensure_setup()
  return require("hiraishin.manager").open(opts)
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
          from_file = old_file, -- relative to the old root, like bookmark.file
          from_path = abs, -- absolute old path
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
