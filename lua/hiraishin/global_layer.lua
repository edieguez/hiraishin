---Global kunai inside projects: while a buffer follows its project (or
---branch) store, kunai of the global store on the same file are drawn too,
---follow edits through their own extmarks and are saved on write.
local anchor = require("hiraishin.anchor")
local config = require("hiraishin.config")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local signs = require("hiraishin.signs")
local store = require("hiraishin.store")

local M = {}

local ns = signs.global_ns

---@class hiraishin.GlobalLayer
---@field ctx hiraishin.Context global context for the buffer's file
---@field marks table<string, integer> bookmark id -> extmark id

---@type table<integer, hiraishin.GlobalLayer>
local layers = {}

local function enabled(ctx)
  return config.options.global_kunai and ctx ~= nil and ctx.scope ~= "global"
end

local function active(data)
  return data.lists[data.active_list] or store.new_list()
end

local function decoration(list, bm)
  local deco = signs.decoration(list, bm)
  deco.virt_text, deco.virt_text_pos = nil, nil
  if deco.sign_text and not list_ops.slot_of(list, bm.id) then
    deco.sign_text = signs.global_icon()
  end
  deco.sign_hl_group = deco.sign_text and "HiraishinSignGlobal" or nil
  deco.number_hl_group = deco.number_hl_group and "HiraishinSignGlobal" or nil
  deco.priority = math.max(0, (deco.priority or config.options.signs.priority) - 1)
  deco.line_hl_group = nil
  return deco
end

---@return integer? row0, boolean invalid
local function mark_pos(bufnr, mark_id)
  local m = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark_id, { details = true })
  if not m or #m == 0 then
    return nil, true
  end
  return m[1], m[3] and m[3].invalid or false
end

local function place(bufnr, layer, list, bm, row)
  local opts = vim.tbl_extend("force", { invalidate = true, undo_restore = true }, decoration(list, bm))
  layer.marks[bm.id] = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, opts)
end

---Redraw the global kunai of a buffer from the store, keeping live positions.
---@param bufnr integer
function M.render(bufnr)
  local layer = layers[bufnr]
  if not layer or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local list = active(store.get(layer.ctx))
  local count = vim.api.nvim_buf_line_count(bufnr)
  local old = layer.marks
  layer.marks = {}
  for _, bm in ipairs(list_ops.items(list, layer.ctx.file)) do
    local row, invalid
    if old[bm.id] then
      row, invalid = mark_pos(bufnr, old[bm.id])
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, old[bm.id])
      old[bm.id] = nil
    end
    if not invalid and not bm.stale then
      row = row or (math.min(bm.line, count) - 1)
      place(bufnr, layer, list, bm, row)
    end
  end
  for _, mark_id in pairs(old) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end
end

---Start drawing a buffer's global kunai, re-anchored against its content.
---@param bufnr integer
---@param ctx hiraishin.Context the buffer's own context
function M.attach(bufnr, ctx)
  M.detach(bufnr)
  if not enabled(ctx) then
    return
  end
  local gctx = scope.global_ctx(bufnr)
  local data = store.get(gctx)
  local list = active(data)
  local items = list_ops.items(list, gctx.file)
  layers[bufnr] = { ctx = gctx, marks = {} }
  if #items == 0 then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local trimmed = anchor.trim_all(lines)
  local changed = false
  for _, bm in ipairs(items) do
    local line = anchor.locate(lines, bm, config.options.anchor, trimmed)
    if line then
      if line ~= bm.line or bm.stale then
        bm.line, bm.anchor, bm.stale = line, anchor.capture(lines, line), false
        changed = true
      end
    elseif not bm.stale then
      bm.stale = true
      changed = true
    end
  end
  M.render(bufnr)
  if changed then
    store.changed(gctx)
  end
end

---Write live positions of a buffer's global kunai to the global store (on write).
---@param bufnr integer
function M.sync(bufnr)
  local layer = layers[bufnr]
  if not layer then
    return
  end
  local tracker = require("hiraishin.tracker")
  local data = store.get(layer.ctx)
  local list = active(data)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local trimmed = tracker.lazy_trim(lines)
  local changed = false
  for _, bm in ipairs(list_ops.items(list, layer.ctx.file)) do
    local mark_id = layer.marks[bm.id]
    if mark_id or bm.stale then
      local row, invalid
      if mark_id then
        row, invalid = mark_pos(bufnr, mark_id)
      end
      local c, replace = tracker.sync_one(bm, data.active_list, not invalid and row or nil, lines, trimmed)
      changed = changed or c
      if replace then
        if mark_id then
          pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
        end
        place(bufnr, layer, list, bm, bm.line - 1)
      end
    end
  end
  if changed then
    store.changed(layer.ctx)
  end
end

---@param bufnr integer
function M.detach(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  layers[bufnr] = nil
end

---Live line of a global kunai shown in some buffer.
---@param bm hiraishin.Bookmark
---@return integer? line, boolean? invalid nil when no buffer shows it
function M.live_line(bm)
  for bufnr, layer in pairs(layers) do
    if layer.ctx.file == bm.file and layer.marks[bm.id] then
      local row, invalid = mark_pos(bufnr, layer.marks[bm.id])
      if invalid or not row then
        return nil, true
      end
      return row + 1, false
    end
  end
end

-- the global store changed (added, removed, renamed, sealed...): redraw
store.subscribe(function(path)
  for bufnr, layer in pairs(layers) do
    if layer.ctx.store == path then
      vim.schedule(function()
        M.render(bufnr)
      end)
    end
  end
end)

function M.reset()
  for bufnr in pairs(layers) do
    M.detach(bufnr)
  end
  layers = {}
end

return M
