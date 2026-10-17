---Keeps kunai on their lines while a file is open (extmarks), syncs the
---positions to the store on write, and re-anchors them when a file is read.
local anchor = require("hiraishin.anchor")
local config = require("hiraishin.config")
local events = require("hiraishin.events")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local signs = require("hiraishin.signs")
local store = require("hiraishin.store")

local M = {}

local ns = signs.ns

---@class hiraishin.Tracked
---@field ctx hiraishin.Context
---@field marks table<string, integer> bookmark id -> extmark id
---@field looks table<string, string> bookmark id -> signature of its decoration

---@type table<integer, hiraishin.Tracked>
local tracked = {}

---Buffer 0 means "current"; every table here is keyed by the real number.
local function real(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function buf_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Every (list name, list, bookmark) for one file of a store.
---@param data hiraishin.Data
---@param file string
---@return { name: string, list: hiraishin.List, bm: hiraishin.Bookmark }[]
local function entries(data, file)
  local out = {}
  for name, list in pairs(data.lists) do
    for _, bm in ipairs(list_ops.items(list, file)) do
      table.insert(out, { name = name, list = list, bm = bm })
    end
  end
  return out
end

---@return string? list_name, hiraishin.List?, hiraishin.Bookmark?
local function lookup(data, id)
  for name, list in pairs(data.lists) do
    if list.bookmarks[id] then
      return name, list, list.bookmarks[id]
    end
  end
end

---@return integer? row0, boolean invalid
local function mark_pos(bufnr, mark_id)
  local m = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark_id, { details = true })
  if not m or #m == 0 then
    return nil, true
  end
  return m[1], m[3] and m[3].invalid or false
end

local function mark_opts(data, list_name, list, bm)
  local opts = { invalidate = true, undo_restore = true }
  if list_name == data.active_list then
    opts = vim.tbl_extend("force", opts, signs.decoration(list, bm))
  end
  return opts
end

---Stable text form of extmark options, to detect a changed look.
local function signature(opts)
  return vim.inspect(opts)
end

---Redraw signs of every kunai in the buffer without moving any mark.
---@param bufnr integer
function M.render(bufnr)
  bufnr = real(bufnr)
  local t = tracked[bufnr]
  if not t or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local data = store.get(t.ctx)
  local count = vim.api.nvim_buf_line_count(bufnr)
  -- drop any mark in our namespace that no kunai owns (never draw twice)
  local owned = {}
  for _, mark_id in pairs(t.marks) do
    owned[mark_id] = true
  end
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    if not owned[m[1]] then
      vim.api.nvim_buf_del_extmark(bufnr, ns, m[1])
    end
  end
  for id, mark_id in pairs(t.marks) do
    local name, list, bm = lookup(data, id)
    local row, invalid = mark_pos(bufnr, mark_id)
    if not bm or not row then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
      t.marks[id] = nil
      t.looks[id] = nil
    elseif not invalid then
      -- Never update a mark in place: some Neovim versions keep drawing the
      -- old end-of-line text next to the new one. Leave unchanged marks alone,
      -- replace changed ones. (Invalid marks stay hidden until undo revives them.)
      local opts = mark_opts(data, name, list, bm)
      local sig = signature(opts)
      if t.looks[id] ~= sig then
        vim.api.nvim_buf_del_extmark(bufnr, ns, mark_id)
        t.marks[id] = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, opts)
        t.looks[id] = sig
      end
    end
  end
  M.cursor_virt(bufnr)
  -- stale kunai: sign only, at the last known line
  vim.api.nvim_buf_clear_namespace(bufnr, signs.stale_ns, 0, -1)
  local active = data.lists[data.active_list]
  for _, bm in ipairs(list_ops.items(active, t.ctx.file)) do
    if bm.stale and not t.marks[bm.id] and bm.line >= 1 and bm.line <= count then
      local deco = signs.decoration(active, bm, true)
      if deco.sign_text then
        vim.api.nvim_buf_set_extmark(bufnr, signs.stale_ns, bm.line - 1, 0, deco)
      end
    end
  end
end

---@param bufnr integer
---@param data hiraishin.Data
---@param e { name: string, list: hiraishin.List, bm: hiraishin.Bookmark }
local function place(bufnr, data, e)
  local t = tracked[bufnr]
  if t.marks[e.bm.id] then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, t.marks[e.bm.id])
  end
  local row = math.min(e.bm.line, vim.api.nvim_buf_line_count(bufnr)) - 1
  local opts = mark_opts(data, e.name, e.list, e.bm)
  t.marks[e.bm.id] = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, opts)
  t.looks[e.bm.id] = signature(opts)
end

---Re-anchor the file's kunai against the buffer content and start tracking.
---Runs when a file is read (also on :e! and external reloads).
---@param bufnr integer
function M.attach(bufnr)
  bufnr = real(bufnr)
  M.detach(bufnr)
  local ctx = scope.for_buf(bufnr)
  if not ctx or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  tracked[bufnr] = { ctx = ctx, marks = {}, looks = {} }
  require("hiraishin.global_layer").attach(bufnr, ctx)
  local data = store.get(ctx)
  local items = entries(data, ctx.file)
  if #items == 0 then
    return
  end

  local lines = buf_lines(bufnr)
  local trimmed = anchor.trim_all(lines)
  local opts = config.options.anchor
  local changed = false
  for _, e in ipairs(items) do
    local bm = e.bm
    local line, method = anchor.locate(lines, bm, opts, trimmed)
    if line then
      if method ~= "same" or bm.stale then
        local from = bm.line
        bm.line = line
        bm.anchor = anchor.capture(lines, line)
        bm.stale = false
        changed = true
        if from ~= line then
          events.emit("HiraishinMoved", {
            bookmark = vim.deepcopy(bm),
            list = e.name,
            from = from,
            method = method,
            reason = "reanchor",
          })
        end
      end
      place(bufnr, data, e)
    elseif not bm.stale then
      bm.stale = true
      changed = true
      events.emit("HiraishinStale", { bookmark = vim.deepcopy(bm), list = e.name })
    end
  end
  if changed then
    store.changed(ctx)
  end
  M.render(bufnr)
end

---@param bufnr integer
function M.detach(bufnr)
  bufnr = real(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, signs.stale_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, signs.cursor_ns, 0, -1)
  end
  require("hiraishin.global_layer").detach(bufnr)
  tracked[bufnr] = nil
end

---Write live positions back to the store. Runs on BufWritePost.
---@param bufnr integer
function M.sync(bufnr)
  bufnr = real(bufnr)
  local t = tracked[bufnr]
  if not t then
    return M.attach(bufnr)
  end
  local data = store.get(t.ctx)
  local lines = buf_lines(bufnr)
  local trimmed ---@type string[]?
  local function trim_once()
    trimmed = trimmed or anchor.trim_all(lines)
    return trimmed
  end
  local changed = false
  for _, e in ipairs(entries(data, t.ctx.file)) do
    local bm, mark_id = e.bm, t.marks[e.bm.id]
    if mark_id then
      local row, invalid = mark_pos(bufnr, mark_id)
      if invalid or not row then
        -- the line is gone; its text may have been typed or pasted elsewhere
        local line = anchor.locate(lines, bm, config.options.anchor, trim_once())
        if line then
          pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
          t.marks[bm.id] = nil
          local from = bm.line
          bm.line, bm.anchor, bm.stale = line, anchor.capture(lines, line), false
          changed = true
          place(bufnr, data, e)
          if from ~= line then
            events.emit("HiraishinMoved", {
              bookmark = vim.deepcopy(bm),
              list = e.name,
              from = from,
              method = "reanchor",
              reason = "edit",
            })
          end
        elseif not bm.stale then
          bm.stale = true
          changed = true
          events.emit("HiraishinStale", { bookmark = vim.deepcopy(bm), list = e.name })
        end
      else
        local line = row + 1
        local fresh = anchor.capture(lines, line)
        if line ~= bm.line or bm.stale or not vim.deep_equal(fresh, bm.anchor) then
          local from = bm.line
          bm.line, bm.anchor, bm.stale = line, fresh, false
          changed = true
          if from ~= line then
            events.emit("HiraishinMoved", {
              bookmark = vim.deepcopy(bm),
              list = e.name,
              from = from,
              method = "edit",
              reason = "edit",
            })
          end
        end
      end
    elseif bm.stale then
      -- the text may be back (typed again, pasted, restored from git)
      local line = anchor.locate(lines, bm, config.options.anchor, trim_once())
      if line then
        bm.line, bm.anchor, bm.stale = line, anchor.capture(lines, line), false
        changed = true
        place(bufnr, data, e)
      end
    end
  end
  if changed then
    store.changed(t.ctx)
  end
  M.render(bufnr)
  require("hiraishin.global_layer").sync(bufnr)
end

---Tracked buffers showing a context's file (or every tracked buffer of the store).
---@param ctx hiraishin.Context
---@return integer[]
function M.buffers_for(ctx)
  local out = {}
  for bufnr, t in pairs(tracked) do
    if t.ctx.store == ctx.store and (ctx.file == nil or t.ctx.file == ctx.file) then
      table.insert(out, bufnr)
    end
  end
  return out
end

---Bring marks in line with the store after an API change (add, remove,
---rename, relocate, slot or list changes). Existing marks never move unless
---their id is in `replace`.
---@param ctx hiraishin.Context
---@param replace? table<string, boolean>
function M.reconcile(ctx, replace)
  for _, bufnr in ipairs(M.buffers_for(ctx)) do
    local t = tracked[bufnr]
    local data = store.get(t.ctx)
    local wanted = {}
    for _, e in ipairs(entries(data, t.ctx.file)) do
      wanted[e.bm.id] = true
      if replace and replace[e.bm.id] and t.marks[e.bm.id] then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, t.marks[e.bm.id])
        t.marks[e.bm.id] = nil
      end
      if not t.marks[e.bm.id] and not e.bm.stale then
        place(bufnr, data, e)
      end
    end
    for id, mark_id in pairs(t.marks) do
      if not wanted[id] then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
        t.marks[id] = nil
      end
    end
    M.render(bufnr)
  end
end

---Point a tracked buffer at its (possibly renamed) file, keeping live marks.
---@param bufnr integer
function M.retarget(bufnr)
  bufnr = real(bufnr)
  local t = tracked[bufnr]
  if not t then
    return
  end
  scope.invalidate(bufnr)
  local ctx = scope.for_buf(bufnr)
  if not ctx then
    return M.detach(bufnr)
  end
  t.ctx = ctx
  M.reconcile(ctx)
end

---Live 1-based line of a kunai: nil when its line was deleted (or it is stale).
---Falls back to the stored line when its file is not open.
---@param ctx hiraishin.Context store context
---@param bm hiraishin.Bookmark
---@return integer? line, boolean invalid
function M.live_line(ctx, bm)
  for bufnr, t in pairs(tracked) do
    if t.ctx.store == ctx.store and t.ctx.file == bm.file then
      local mark_id = t.marks[bm.id]
      if mark_id then
        local row, invalid = mark_pos(bufnr, mark_id)
        if invalid or not row then
          return nil, true
        end
        return row + 1, false
      end
      break
    end
  end
  if ctx.scope == "global" then
    -- a global kunai drawn in a project buffer
    local line, invalid = require("hiraishin.global_layer").live_line(bm)
    if invalid ~= nil then
      return line, invalid
    end
  end
  if bm.stale then
    return nil, false
  end
  return bm.line, false
end

---Show the name/note of the kunai under the cursor (virt_text.show = "cursorline").
---@param bufnr? integer
function M.cursor_virt(bufnr)
  bufnr = real(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, signs.cursor_ns, 0, -1)
  local t = tracked[bufnr]
  if not t or config.options.virt_text.show ~= "cursorline" then
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local here = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, { details = true })) do
    if not (m[4] and m[4].invalid) then
      here[m[1]] = true
    end
  end
  if next(here) == nil then
    return
  end
  local data = store.get(t.ctx)
  local active = data.lists[data.active_list]
  for id, mark_id in pairs(t.marks) do
    if here[mark_id] and active and active.bookmarks[id] then
      local vt = signs.virt_text(active.bookmarks[id])
      if vt then
        vim.api.nvim_buf_set_extmark(bufnr, signs.cursor_ns, row, 0, {
          virt_text = vt,
          virt_text_pos = config.options.virt_text.position,
        })
      end
      return
    end
  end
end

---Kunai (active list) on the cursor line of a tracked buffer, from the live marks.
---@param bufnr? integer
---@return hiraishin.Bookmark?
function M.at_cursor(bufnr)
  bufnr = real(bufnr)
  local t = tracked[bufnr]
  local win = vim.fn.bufwinid(bufnr)
  if not t or win == -1 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local data = store.get(t.ctx)
  local active = data.lists[data.active_list]
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, { details = true })) do
    if not (m[4] and m[4].invalid) then
      for id, mark_id in pairs(t.marks) do
        if mark_id == m[1] and active and active.bookmarks[id] then
          return active.bookmarks[id]
        end
      end
    end
  end
end

---Tracked buffers and the store context each one follows.
---@return table<integer, hiraishin.Context>
function M.tracked()
  local out = {}
  for bufnr, t in pairs(tracked) do
    out[bufnr] = t.ctx
  end
  return out
end

---@param bufnr integer
---@return boolean
function M.is_tracked(bufnr)
  bufnr = real(bufnr)
  return tracked[bufnr] ~= nil
end

function M.reset()
  for bufnr in pairs(tracked) do
    M.detach(bufnr)
  end
  tracked = {}
end

return M
