local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local signs = require("hiraishin.signs")
local store = require("hiraishin.store")
local util = require("hiraishin.util")

local M = {}

local did_setup = false

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  store.reset()
  scope.invalidate()
  signs.setup_highlights()

  local group = vim.api.nvim_create_augroup("hiraishin", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(ev)
      signs.refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufFilePost", "BufWipeout" }, {
    group = group,
    callback = function(ev)
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

  require("hiraishin.keymaps").setup()
  did_setup = true
  signs.refresh_file()
end

local function ensure_setup()
  if not did_setup then
    M.setup()
  end
end

local function emit(pattern, data)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern, modeline = false, data = data })
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

---@param ctx hiraishin.Context
local function changed(ctx)
  store.changed(ctx)
  if ctx.abs then
    signs.refresh_file(ctx.abs)
  else
    signs.refresh_file()
  end
end

---Add a bookmark on a line. On a line that already has one, its name/note are
---updated instead and the existing bookmark is returned.
---@param opts? { name?: string, note?: string, bufnr?: integer, line?: integer, col?: integer }
---@return hiraishin.Bookmark? bookmark, string? err_or_status
function M.add(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line, col = target(opts)
  local ctx, err = scope.for_buf(bufnr)
  if not ctx then
    return nil, err
  end
  if line < 1 or line > vim.api.nvim_buf_line_count(bufnr) then
    return nil, "line out of range"
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local name, note = util.trim(opts.name), util.trim(opts.note)
  local existing = list_ops.find_at(list, ctx.file, line)
  if name and list_ops.find_name(list, name, existing and existing.id) then
    return nil, string.format("a kunai named '%s' already exists", name)
  end

  if existing then
    if name or note then
      existing.name = name or existing.name
      existing.note = note or existing.note
      existing.updated_at = os.time()
      changed(ctx)
      emit("HiraishinUpdate", { bookmark = vim.deepcopy(existing), list = list_name })
    end
    return existing, "exists"
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
  emit("HiraishinAdd", { bookmark = vim.deepcopy(bm), list = list_name })
  return bm
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
  list_ops.delete(list, bm.id)
  changed(ctx)
  emit("HiraishinRemove", { bookmark = vim.deepcopy(bm), list = list_name, reason = opts.reason or "api" })
  return bm
end

---Add a bookmark on the line, or remove the one already there.
---@param opts? { bufnr?: integer, line?: integer }
---@return hiraishin.Bookmark? bookmark, "added"|"removed"|nil action, string? err
function M.toggle(opts)
  ensure_setup()
  opts = opts or {}
  local bufnr, line = target(opts)
  local ctx, err = scope.for_buf(bufnr)
  if not ctx then
    return nil, nil, err
  end
  local list = list_ops.active(store.get(ctx))
  local existing = list_ops.find_at(list, ctx.file, line)
  if existing then
    M.remove(existing.id, { bufnr = bufnr, reason = "toggle" })
    return existing, "removed"
  end
  local bm, add_err = M.add({ bufnr = bufnr, line = line, col = opts.col })
  return bm, bm and "added" or nil, add_err
end

---Change a bookmark's name or note. Pass `false` to clear a field.
---@param key string id or name
---@param fields { name?: string|false, note?: string|false }
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
  bm.updated_at = os.time()
  changed(ctx)
  emit("HiraishinUpdate", { bookmark = vim.deepcopy(bm), list = list_name })
  return bm
end

---@param key string id or name
---@param opts? { bufnr?: integer }
---@return hiraishin.Bookmark?
function M.get(key, opts)
  ensure_setup()
  opts = opts or {}
  local list = list_ops.active(store.get(scope.resolve(opts.bufnr)))
  local bm = list_ops.find(list, key)
  return bm and vim.deepcopy(bm) or nil
end

---Bookmarks of the active list (copies). `bufnr` limits to that buffer's file.
---@param opts? { bufnr?: integer }
---@return hiraishin.Bookmark[]
function M.list(opts)
  ensure_setup()
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local list = list_ops.active(store.get(ctx))
  local file = opts.bufnr and ctx.file or nil
  return vim.deepcopy(list_ops.items(list, file))
end

---Bookmark on the cursor line of the current buffer, if any.
---@return hiraishin.Bookmark?
function M.at_cursor()
  ensure_setup()
  local ctx = scope.for_buf(0)
  if not ctx then
    return nil
  end
  local list = list_ops.active(store.get(ctx))
  local bm = list_ops.find_at(list, ctx.file, vim.api.nvim_win_get_cursor(0)[1])
  return bm and vim.deepcopy(bm) or nil
end

return M
