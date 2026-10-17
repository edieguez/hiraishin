---Jumping to kunai and walking between them.
local config = require("hiraishin.config")
local events = require("hiraishin.events")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local store = require("hiraishin.store")
local tracker = require("hiraishin.tracker")
local util = require("hiraishin.util")

local M = {}

---A window that can show a file: the current one unless it is a sidebar,
---quickfix, terminal and the like.
---@return integer win
local function normal_win()
  local cur = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(cur)].buftype == "" then
    return cur
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev ~= 0 and vim.bo[vim.api.nvim_win_get_buf(prev)].buftype == "" then
    return prev
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      return win
    end
  end
  return cur
end

---@param abs string
---@return integer? win showing it in the current tab
local function win_showing(abs)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and util.buf_path(buf) == abs then
      return win
    end
  end
end

---Open `abs` according to `split` and return the window.
---@param abs string
---@param split? "vsplit"|"split"|"tab"
---@return integer? win, string? err
local function open(abs, split)
  local cmds = { vsplit = "vsplit", split = "split", tab = "tabedit" }
  if not split and config.options.jump.reuse_window then
    local win = win_showing(abs)
    if win then
      vim.api.nvim_set_current_win(win)
      return win
    end
  end
  if not split then
    vim.api.nvim_set_current_win(normal_win())
  end
  if not split and util.buf_path(0) == abs then
    return vim.api.nvim_get_current_win()
  end
  local ok, err = pcall(vim.cmd, (cmds[split] or "edit") .. " " .. vim.fn.fnameescape(abs))
  if not ok then
    return nil, tostring(err):gsub("^Vim:", "")
  end
  return vim.api.nvim_get_current_win()
end

---@param ctx hiraishin.Context store context the bookmark belongs to
---@param bm hiraishin.Bookmark
---@param list_name string
---@param opts? { split?: "vsplit"|"split"|"tab" }
---@return hiraishin.Bookmark? bookmark, string? err
function M.jump(ctx, bm, list_name, opts)
  opts = opts or {}
  local abs = util.abspath(ctx.root, bm.file)
  if not vim.uv.fs_stat(abs) and vim.fn.bufexists(abs) == 0 then
    return nil, string.format("file not found: %s", bm.file)
  end
  local from = { file = util.buf_path(0), line = vim.api.nvim_win_get_cursor(0)[1] }
  events.emit("HiraishinJump", { bookmark = vim.deepcopy(bm), list = list_name, from = from })

  -- remember where we were, so <C-o> comes back
  vim.cmd("normal! m'")
  local win, err = open(abs, opts.split)
  if not win then
    return nil, err
  end
  -- the file may just have been read and re-anchored: ask for the live line
  local bufnr = vim.api.nvim_win_get_buf(win)
  local live_ctx = scope.for_buf(bufnr) or ctx
  local line, invalid = tracker.live_line(live_ctx, bm)
  local stale = bm.stale or invalid or not line
  line = line or bm.line
  line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(bufnr)))
  local col = math.min(bm.col or 0, math.max(0, #(vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or "")))
  vim.api.nvim_win_set_cursor(win, { line, col })
  local j = config.options.jump
  if j.open_folds then
    vim.cmd("normal! zv")
  end
  if j.center then
    vim.cmd("normal! zz")
  end
  if stale then
    util.notify(
      string.format(
        "kunai '%s' is stale (its line was not found); :Hiraishin relocate to re-attach it",
        bm.name or bm.anchor.text
      ),
      vim.log.levels.WARN
    )
  end
  bm.last_jump_at = os.time()
  store.changed(ctx)
  return vim.deepcopy(bm)
end

---Live, non-stale kunai of a list with their positions.
---@return { bm: hiraishin.Bookmark, line: integer }[]
local function live_items(ctx, list, file)
  local out = {}
  for _, bm in ipairs(list_ops.items(list, file)) do
    local line, invalid = tracker.live_line(ctx, bm)
    if line and not invalid and not bm.stale then
      table.insert(out, { bm = bm, line = line })
    end
  end
  return out
end

---Next/previous kunai in the current buffer, by line.
---@param dir 1|-1
---@param opts { count?: integer, wrap?: boolean }
---@return hiraishin.Bookmark? bookmark, string? err
function M.step_buffer(dir, opts)
  local ctx = scope.for_buf(0)
  if not ctx then
    return nil, "not a file buffer"
  end
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local items = live_items(ctx, list, ctx.file)
  if #items == 0 then
    return nil, "no kunai in this buffer"
  end
  table.sort(items, function(a, b)
    return a.line < b.line
  end)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local wrap = opts.wrap ~= false
  local target = nil
  local pos = cur
  for _ = 1, opts.count or 1 do
    local found
    if dir > 0 then
      for _, it in ipairs(items) do
        if it.line > pos then
          found = it
          break
        end
      end
      found = found or (wrap and items[1] or nil)
    else
      for i = #items, 1, -1 do
        if items[i].line < pos then
          found = items[i]
          break
        end
      end
      found = found or (wrap and items[#items] or nil)
    end
    if not found then
      break
    end
    target, pos = found, found.line
  end
  if not target then
    return nil, dir > 0 and "no kunai below" or "no kunai above"
  end
  return M.jump(ctx, target.bm, list_name)
end

---Next/previous kunai across files, in list (manager) order.
---@param dir 1|-1
---@param opts { count?: integer, wrap?: boolean }
---@return hiraishin.Bookmark? bookmark, string? err
function M.step_list(dir, opts)
  local ctx = scope.resolve(0)
  local data = store.get(ctx)
  local list, list_name = list_ops.active(data)
  local items = live_items(ctx, list)
  if #items == 0 then
    return nil, "no kunai in this list"
  end
  local file = ctx.file
  local cur = file and vim.api.nvim_win_get_cursor(0)[1] or nil
  -- where are we in the list? on a kunai: its index; otherwise just before the
  -- first kunai that comes after the cursor in this file (or at the edges)
  local index
  for i, it in ipairs(items) do
    if it.bm.file == file and it.line == cur then
      index = i
      break
    end
  end
  if not index then
    if dir > 0 then
      index = 0
      for i, it in ipairs(items) do
        if it.bm.file == file and it.line > cur then
          index = i - 1
          break
        end
      end
    else
      index = #items + 1
      for i = #items, 1, -1 do
        local it = items[i]
        if it.bm.file == file and it.line < cur then
          index = i + 1
          break
        end
      end
    end
  end
  local n = #items
  local target = index + dir * (opts.count or 1)
  if opts.wrap ~= false then
    target = ((target - 1) % n) + 1
  elseif target < 1 or target > n then
    return nil, dir > 0 and "last kunai in the list" or "first kunai in the list"
  end
  return M.jump(ctx, items[target].bm, list_name)
end

return M
