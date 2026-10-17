---Picker front-end: builds entries, sorts them and runs the actions; the
---backends in hiraishin.picker.<name> only display them.
local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local store = require("hiraishin.store")
local tracker = require("hiraishin.tracker")
local util = require("hiraishin.util")

local M = {}

---@class hiraishin.Entry
---@field id string bookmark id
---@field list string list name
---@field bookmark hiraishin.Bookmark copy with live line
---@field slot integer?
---@field file string file key (relative to root when possible)
---@field abs string absolute path
---@field line integer
---@field col integer 0-based
---@field text string current text of the line ("" when unknown)
---@field stale boolean
---@field label string one-line display text
---@field ordinal string text used for fuzzy matching

---@class hiraishin.PickOpts
---@field filter? "buffer"|"all"  default: active list
---@field backend? string
---@field bufnr? integer           context buffer (default: current)

M.BACKENDS = { "snacks", "telescope", "fzf-lua", "mini", "select" }

local function file_lines(abs, line, cache)
  local lines = cache[abs]
  if lines == nil then
    local bufnr = vim.fn.bufnr(abs)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    elseif vim.uv.fs_stat(abs) then
      local ok, read = pcall(vim.fn.readfile, abs, "", line + 200)
      lines = ok and read or false
    else
      lines = false
    end
    cache[abs] = lines
  end
  return lines and lines[line] or nil
end

---@param e hiraishin.Entry
---@param show_list boolean
local function label(e, show_list)
  local o = config.options
  local parts = {}
  table.insert(parts, e.slot and ("[" .. e.slot .. "]") or "[ ]")
  table.insert(parts, e.bookmark.name or "—")
  if show_list then
    table.insert(parts, "(" .. e.list .. ")")
  end
  table.insert(parts, e.file .. ":" .. e.line)
  table.insert(parts, e.stale and "(stale)" or vim.trim(e.text))
  if o.picker.show_notes and e.bookmark.note then
    table.insert(parts, (o.virt_text.note_icon or "✎") .. " " .. e.bookmark.note:gsub("\n", " ⏎ "))
  end
  return table.concat(parts, "  ")
end

local SORTERS = {
  -- jumped-to kunai first (latest jump first), then the rest by last change
  recent = function(a, b)
    local ja, jb = a.bookmark.last_jump_at or 0, b.bookmark.last_jump_at or 0
    if ja ~= jb then
      return ja > jb
    end
    local ua, ub = a.bookmark.updated_at or 0, b.bookmark.updated_at or 0
    if ua ~= ub then
      return ua > ub
    end
    return a.index < b.index
  end,
  manual = function(a, b)
    return a.index < b.index
  end,
  path = function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line < b.line
  end,
  created = function(a, b)
    local ka, kb = a.bookmark.created_at or 0, b.bookmark.created_at or 0
    if ka ~= kb then
      return ka > kb
    end
    return a.index < b.index
  end,
}

---Entries for the picker: sealed kunai first (by seal), then by picker.sort.
---@param opts? hiraishin.PickOpts
---@return hiraishin.Entry[], hiraishin.Context
function M.entries(opts)
  opts = opts or {}
  local ctx = scope.resolve(opts.bufnr)
  local data = store.get(ctx)
  local names = opts.filter == "all" and vim.tbl_keys(data.lists) or { data.active_list }
  table.sort(names)
  local only_file = nil
  if opts.filter == "buffer" then
    only_file = ctx.file or false
  end
  local cache, out = {}, {}
  for _, name in ipairs(names) do
    local list = data.lists[name]
    for index, bm in ipairs(list_ops.items(list)) do
      if only_file == nil or bm.file == only_file then
        local copy = vim.deepcopy(bm)
        local line, invalid = tracker.live_line(ctx, bm)
        copy.line = line or bm.line
        copy.stale = bm.stale or invalid
        local slot = list_ops.slot_of(list, bm.id)
        local abs = util.abspath(ctx.root, bm.file)
        local e = {
          id = bm.id,
          list = name,
          bookmark = copy,
          slot = slot and tonumber(slot) or nil,
          file = bm.file,
          abs = abs,
          line = copy.line,
          col = bm.col or 0,
          text = file_lines(abs, copy.line, cache) or "",
          stale = copy.stale,
          index = index,
        }
        table.insert(out, e)
      end
    end
  end
  local sorter = SORTERS[config.options.picker.sort] or SORTERS.recent
  table.sort(out, function(a, b)
    if (a.slot ~= nil) ~= (b.slot ~= nil) then
      return a.slot ~= nil
    end
    if a.slot and b.slot and a.slot ~= b.slot then
      return a.slot < b.slot
    end
    if a.list ~= b.list then
      return a.list < b.list
    end
    return sorter(a, b)
  end)
  local show_list = opts.filter == "all"
  for _, e in ipairs(out) do
    e.label = label(e, show_list)
    e.ordinal = table.concat({ e.bookmark.name or "", e.file, e.text, e.bookmark.note or "", e.list }, " ")
  end
  return out, ctx
end

---Store object behind an entry (nil if it was deleted meanwhile).
---@param ctx hiraishin.Context
---@param e hiraishin.Entry
local function lookup(ctx, e)
  local list = store.get(ctx).lists[e.list]
  return list and list.bookmarks[e.id] or nil, list
end

M.actions = {}

---@param ctx hiraishin.Context
---@param e hiraishin.Entry
---@param split? "vsplit"|"split"|"tab"
---@param win? integer open in this window (backends with a target window)
function M.actions.jump(ctx, e, split, win)
  local bm = lookup(ctx, e)
  if not bm then
    return util.notify("kunai no longer exists", vim.log.levels.WARN)
  end
  if win and vim.api.nvim_win_is_valid(win) and not split then
    vim.api.nvim_set_current_win(win)
  end
  local _, err = require("hiraishin.nav").jump(ctx, bm, e.list, { split = split, here = win ~= nil })
  if err then
    util.notify(err, vim.log.levels.WARN)
  end
end

function M.actions.delete(ctx, e)
  local bm, list = lookup(ctx, e)
  if not bm then
    return
  end
  local history = require("hiraishin.history")
  history.record(ctx, { history.item(ctx, e.list, list, bm) }, "picker")
  list_ops.delete(list, bm.id)
  store.changed(ctx)
  tracker.reconcile({ store = ctx.store })
  require("hiraishin.events").emit("HiraishinRemove", { bookmark = e.bookmark, list = e.list, reason = "picker" })
end

---@param done? fun() called after the name was changed (or the prompt cancelled)
function M.actions.rename(ctx, e, done)
  local bm, list = lookup(ctx, e)
  if not bm then
    return done and done()
  end
  vim.ui.input({ prompt = "Kunai name: ", default = bm.name or "" }, function(input)
    if input ~= nil then
      local name = util.trim(input)
      if name and list_ops.find_name(list, name, bm.id) then
        util.notify(string.format("a kunai named '%s' already exists", name), vim.log.levels.WARN)
      else
        bm.name = name
        bm.updated_at = os.time()
        store.changed(ctx)
        tracker.reconcile({ store = ctx.store })
      end
    end
    if done then
      done()
    end
  end)
end

function M.actions.note(ctx, e)
  local bm = lookup(ctx, e)
  if bm then
    require("hiraishin.note").edit({ id = bm.id, list = e.list, ctx = ctx })
  end
end

---@param entries hiraishin.Entry[]
---@param opts? { loclist?: boolean, title?: string, open?: boolean }
function M.actions.quickfix(entries, opts)
  opts = opts or {}
  local items = {}
  for _, e in ipairs(entries) do
    local prefix = (e.slot and ("[" .. e.slot .. "] ") or "") .. (e.bookmark.name and (e.bookmark.name .. ": ") or "")
    table.insert(items, {
      filename = e.abs,
      lnum = e.line,
      col = e.col + 1,
      text = prefix .. (e.stale and "(stale) " or "") .. vim.trim(e.text),
      type = e.stale and "W" or nil,
    })
  end
  local what = { title = opts.title or "Hiraishin", items = items }
  if opts.loclist then
    vim.fn.setloclist(0, {}, " ", what)
    if opts.open ~= false then
      vim.cmd("lopen")
    end
  else
    vim.fn.setqflist({}, " ", what)
    if opts.open ~= false then
      vim.cmd("copen")
    end
  end
end

local MODULES = { snacks = "snacks", telescope = "telescope", ["fzf-lua"] = "fzf", mini = "mini", select = "select" }
-- LazyVim records the picker the user chose in vim.g.lazyvim_picker
local LAZYVIM = { snacks = "snacks", telescope = "telescope", fzf = "fzf-lua" }

---@param name string
local function load_backend(name)
  if not MODULES[name] then
    return nil
  end
  local ok, backend = pcall(require, "hiraishin.picker." .. MODULES[name])
  if ok and backend.available() then
    return backend
  end
end

---Backend to use: the configured one, else LazyVim's choice, else the first available.
---@param wanted? string
---@return table backend, string name
function M.backend(wanted)
  wanted = wanted or config.options.picker.backend
  if wanted == "auto" and type(vim.g.lazyvim_picker) == "string" then
    local name = LAZYVIM[vim.g.lazyvim_picker]
    local b = name and load_backend(name)
    if b then
      return b, name
    end
  end
  if wanted and wanted ~= "auto" then
    local b = load_backend(wanted)
    if b then
      return b, wanted
    end
    util.notify(string.format("picker backend '%s' is not available; using another", wanted), vim.log.levels.WARN)
  end
  for _, name in ipairs(M.BACKENDS) do
    local b = load_backend(name)
    if b then
      return b, name
    end
  end
  return require("hiraishin.picker.select"), "select"
end

---Open the picker.
---@param opts? hiraishin.PickOpts
function M.open(opts)
  opts = opts or {}
  local entries, ctx = M.entries(opts)
  if #entries == 0 then
    return util.notify(opts.filter == "buffer" and "no kunai in this buffer" or "no kunai yet")
  end
  local backend = M.backend(opts.backend)
  local title = "Kunai"
  if opts.filter == "all" then
    title = "Kunai (all lists)"
  elseif opts.filter == "buffer" then
    title = "Kunai (buffer)"
  else
    local active = store.get(ctx).active_list
    if active ~= "default" then
      title = "Kunai [" .. active .. "]"
    end
  end
  backend.open({
    entries = entries,
    ctx = ctx,
    title = title,
    keys = config.options.picker.keys,
    -- fresh entries after a change (delete/rename) for backends that refresh
    refresh = function()
      return (M.entries(opts))
    end,
    reopen = function()
      M.open(opts)
    end,
  })
end

return M
