---The manager: an editable buffer listing the kunai of a list, applied on :w.
---
---Each line is   seal │ name │ path:line │ note /id
---  - edit the seal (1-9 or -), the name (- for none) or the note
---  - reorder lines to reorder the list, delete lines to delete kunai
---  - the path is read-only, the trailing /id ties a line to its kunai
local config = require("hiraishin.config")
local events = require("hiraishin.events")
local history = require("hiraishin.history")
local list_ops = require("hiraishin.list")
local scope = require("hiraishin.scope")
local store = require("hiraishin.store")
local tracker = require("hiraishin.tracker")
local util = require("hiraishin.util")

local M = {}

M.ns = vim.api.nvim_create_namespace("hiraishin_manager")
M.hl_ns = vim.api.nvim_create_namespace("hiraishin_manager_hl")

local SEP = " │ "
local NEWLINE = " ⏎ "

---@class hiraishin.ManagerState
---@field ctx hiraishin.Context
---@field list string
---@field buf integer
---@field win integer
---@field ids table<string, boolean> kunai shown when the buffer was rendered

---@type hiraishin.ManagerState?
local current

local function pad(s, width)
  return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

---Buffer lines for a list.
---@param ctx hiraishin.Context
---@param list hiraishin.List
---@return string[] lines, table<string, boolean> ids, { name: integer, path: integer } widths
function M.render_lines(ctx, list)
  local rows, ids = {}, {}
  local wname, wpath = #"name", #"location"
  for _, bm in ipairs(list_ops.items(list)) do
    local line, invalid = tracker.live_line(ctx, bm)
    local stale = bm.stale or invalid
    local _, end_line = tracker.live_range(ctx, bm)
    local span = (not stale and end_line and line and end_line > line) and ("-" .. end_line) or ""
    local row = {
      slot = list_ops.slot_of(list, bm.id) or "-",
      name = bm.name or "-",
      path = string.format("%s:%d%s%s", bm.file, line or bm.line, span, stale and " !" or ""),
      note = bm.note and bm.note:gsub("\n", NEWLINE) or "",
      id = bm.id,
    }
    wname = math.max(wname, vim.fn.strdisplaywidth(row.name))
    wpath = math.max(wpath, vim.fn.strdisplaywidth(row.path))
    table.insert(rows, row)
    ids[bm.id] = true
  end
  local lines = {}
  for _, r in ipairs(rows) do
    local text = r.slot .. SEP .. pad(r.name, wname) .. SEP .. pad(r.path, wpath) .. SEP .. r.note
    table.insert(lines, (text:gsub("%s+$", "")) .. " /" .. r.id)
  end
  return lines, ids, { name = wname, path = wpath }
end

---Column header matching render_lines' widths (shown in the winbar).
---@param widths { name: integer, path: integer }
---@return string
function M.header(widths)
  return "#" .. SEP .. pad("name", widths.name) .. SEP .. pad("location", widths.path) .. SEP .. "note"
end

---Highlight the columns of the buffer: seal, separators, dim path, stale marker.
---@param buf integer
function M.highlight(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.hl_ns, 0, -1)
  for i, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local seps = {}
    local from = 1
    while true do
      local s, e = text:find("│", from, true)
      if not s then
        break
      end
      table.insert(seps, { s - 1, e })
      from = e + 1
    end
    local function hl(s, e, group)
      vim.api.nvim_buf_set_extmark(buf, M.hl_ns, i - 1, s, { end_col = e, hl_group = group })
    end
    for _, sep in ipairs(seps) do
      hl(sep[1], sep[2], "HiraishinManagerSep")
    end
    local slot_s, slot_e = text:find("^%s*[1-9]")
    if slot_s and (not seps[1] or slot_e <= seps[1][1]) then
      hl(slot_e - 1, slot_e, "HiraishinManagerSlot")
    end
    if seps[2] then
      local path_end = seps[3] and seps[3][1] or (text:find("%s*/%x+%s*$") or #text + 1) - 1
      local field = text:sub(seps[2][2] + 1, path_end)
      local bang = field:find("%s!%s*$")
      hl(seps[2][2], seps[2][2] + (bang or #field + 1) - 1, "HiraishinManagerPath")
      if bang then
        local at = seps[2][2] + field:find("!", bang, true) - 1
        hl(at, at + 1, "HiraishinSignStale")
      end
    end
  end
end

local function set_title(state)
  if not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local where = state.ctx.root and vim.fn.fnamemodify(state.ctx.root, ":~") or "global"
  local dirty = vim.api.nvim_buf_is_valid(state.buf) and vim.bo[state.buf].modified
  vim.api.nvim_win_set_config(state.win, {
    title = string.format(" Kunai · %s · %s%s ", state.list, where, dirty and " ●" or ""),
    title_pos = "center",
  })
end

---@class hiraishin.ManagerLine
---@field lnum integer
---@field id string
---@field slot string?
---@field name string?
---@field file string
---@field note string?

---Parse one buffer line. Returns nil for blank/comment lines.
---@return hiraishin.ManagerLine?, string? err
function M.parse_line(text, lnum)
  if text:match("^%s*$") or text:match('^%s*"') then
    return nil
  end
  local body, id = text:match("^(.-)%s*/(%x%x%x%x%x%x%x%x)%s*$")
  if not body then
    return nil, "missing kunai id at the end of the line (lines can be moved or deleted, not added)"
  end
  -- only "│" separates columns: names and notes may contain "|"
  local fields = vim.split(body, "│", { plain = true })
  if #fields < 3 then
    return nil, "expected: seal │ name │ path:line │ note"
  end
  local slot = vim.trim(fields[1])
  if slot == "-" or slot == "" then
    slot = nil
  elseif not slot:match("^[1-9]$") then
    return nil, string.format("seal must be 1-9 or -, got '%s'", slot)
  end
  local name = vim.trim(fields[2])
  if name == "-" or name == "" then
    name = nil
  end
  local path = vim.trim(fields[3]):gsub("%s+!$", ""):gsub(":%d+%-%d+$", ""):gsub(":%d+$", "")
  local note = vim.trim(table.concat(vim.list_slice(fields, 4), "│"))
  note = note ~= "" and note:gsub(vim.pesc(vim.trim(NEWLINE)), "\n"):gsub(" ?\n ?", "\n") or nil
  return { lnum = lnum, id = id, slot = slot, name = name, file = path, note = note }
end

---Validate the whole buffer against the list.
---@return hiraishin.ManagerLine[] rows, vim.Diagnostic[] problems
function M.parse(lines, list)
  local rows, problems = {}, {}
  local seen_id, seen_slot, seen_name = {}, {}, {}
  local function problem(lnum, msg)
    table.insert(problems, { lnum = lnum - 1, col = 0, severity = vim.diagnostic.severity.ERROR, message = msg })
  end
  for lnum, text in ipairs(lines) do
    local row, err = M.parse_line(text, lnum)
    if err then
      problem(lnum, err)
    elseif row then
      local bm = list.bookmarks[row.id]
      if not bm then
        problem(lnum, "unknown kunai id /" .. row.id)
      elseif seen_id[row.id] then
        problem(lnum, "this kunai is listed twice (line " .. seen_id[row.id] .. ")")
      elseif row.file ~= bm.file then
        problem(lnum, string.format("the path is read-only (was %s)", bm.file))
      else
        seen_id[row.id] = lnum
        if row.slot then
          if seen_slot[row.slot] then
            problem(lnum, string.format("seal %s is also on line %d", row.slot, seen_slot[row.slot]))
          end
          seen_slot[row.slot] = lnum
        end
        if row.name then
          if seen_name[row.name] then
            problem(lnum, string.format("name '%s' is also on line %d", row.name, seen_name[row.name]))
          end
          seen_name[row.name] = lnum
        end
        table.insert(rows, row)
      end
    end
  end
  return rows, problems
end

local function render(state)
  local data = store.get(state.ctx)
  local list = data.lists[state.list] or store.new_list()
  local lines, ids, widths = M.render_lines(state.ctx, list)
  state.ids = ids
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modified = false
  vim.diagnostic.reset(M.ns, state.buf)
  M.highlight(state.buf)
  set_title(state)
  if vim.api.nvim_win_is_valid(state.win) then
    if #lines == 0 then
      vim.wo[state.win].winbar = "%#HiraishinManagerPath# No kunai in this list · <Tab> other list · q close"
    else
      vim.wo[state.win].winbar = "%#HiraishinManagerHeader#" .. M.header(widths):gsub("%%", "%%%%")
    end
  end
end

-- keep an open, unedited manager in step with changes made elsewhere
-- (toggles, the picker, another Neovim); edits in progress are never touched
local refresh_pending = false
store.subscribe(function(path)
  if refresh_pending or not current or current.ctx.store ~= path then
    return
  end
  refresh_pending = true
  vim.schedule(function()
    refresh_pending = false
    local state = current
    if not state or not vim.api.nvim_buf_is_valid(state.buf) or vim.bo[state.buf].modified then
      return
    end
    -- stay on the same kunai when lines shift
    local id
    if vim.api.nvim_win_is_valid(state.win) then
      local row = vim.api.nvim_win_get_cursor(state.win)[1]
      local text = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
      id = text:match("/(%x+)%s*$")
    end
    M.refresh(state)
    if id and vim.api.nvim_win_is_valid(state.win) then
      for i, text in ipairs(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
        if text:match("/(%x+)%s*$") == id then
          vim.api.nvim_win_set_cursor(state.win, { i, 0 })
          break
        end
      end
    end
  end)
end)

---Redraw the manager from the store (drops unapplied edits).
---@param state? hiraishin.ManagerState
function M.refresh(state)
  state = state or current
  if state and vim.api.nvim_buf_is_valid(state.buf) then
    render(state)
  end
end

---Apply the buffer to the list. Nothing changes when there are problems.
---@param state hiraishin.ManagerState
---@return boolean applied
function M.apply(state)
  local data = store.get(state.ctx)
  local list = data.lists[state.list]
  if not list then
    util.notify("List '" .. state.list .. "' no longer exists", vim.log.levels.WARN)
    return false
  end
  local rows, problems = M.parse(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), list)
  vim.diagnostic.set(M.ns, state.buf, problems)
  if #problems > 0 then
    util.notify(
      string.format("%d problem%s in the list · nothing applied", #problems, #problems == 1 and "" or "s"),
      vim.log.levels.WARN
    )
    return false
  end

  local kept = {}
  for _, r in ipairs(rows) do
    kept[r.id] = true
  end
  -- only kunai that were on screen can be deleted; ones added meanwhile stay
  local deleted = {}
  for _, id in ipairs(list.order) do
    if state.ids[id] and not kept[id] then
      table.insert(deleted, list.bookmarks[id])
    end
  end
  if #deleted > 0 and config.options.manager.confirm_delete then
    local names = vim.tbl_map(function(bm)
      return "  " .. (bm.name or (bm.file .. ":" .. bm.line))
    end, vim.list_slice(deleted, 1, 10))
    local msg = string.format("Delete %d kunai?\n%s", #deleted, table.concat(names, "\n"))
    if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
      return false
    end
  end

  local now = os.time()
  local items = vim.tbl_map(function(bm)
    return history.item(state.ctx, state.list, list, bm)
  end, deleted)
  history.record(state.ctx, items, "manager")
  for _, bm in ipairs(deleted) do
    list_ops.delete(list, bm.id)
    events.emit("HiraishinRemove", { bookmark = vim.deepcopy(bm), list = state.list, reason = "manager" })
  end

  -- new order: the lines, then anything added since the buffer was rendered
  local order, in_order = {}, {}
  for _, r in ipairs(rows) do
    table.insert(order, r.id)
    in_order[r.id] = true
  end
  for _, id in ipairs(list.order) do
    if not in_order[id] then
      table.insert(order, id)
    end
  end
  list.order = order

  local slots = {}
  for slot, id in pairs(list.slots) do
    if not state.ids[id] and list.bookmarks[id] then
      slots[slot] = id -- seals of kunai not on screen are untouched
    end
  end
  local unsealed = {}
  for _, r in ipairs(rows) do
    local bm = list.bookmarks[r.id]
    local old_slot = list_ops.slot_of(list, r.id)
    if r.slot then
      slots[r.slot] = r.id
    elseif old_slot then
      table.insert(unsealed, { bm = bm, slot = old_slot })
    end
    if bm.name ~= r.name or bm.note ~= r.note or old_slot ~= r.slot then
      bm.name, bm.note, bm.updated_at = r.name, r.note, now
      if bm.name or bm.note then
        bm.seal_only = nil
      end
      events.emit("HiraishinUpdate", { bookmark = vim.deepcopy(bm), list = state.list })
    end
  end
  list.slots = slots
  -- seal-only kunai whose seal was cleared go away with it
  local dropped = vim.tbl_count(require("hiraishin")._drop_unsealed(state.ctx, list, state.list, unsealed, "seal"))

  store.changed(state.ctx)
  tracker.reconcile({ store = state.ctx.store })
  render(state)
  if #deleted + dropped > 0 then
    util.notify(
      string.format(
        "Deleted %d kunai · %s to undo",
        #deleted + dropped,
        require("hiraishin.ui").hint("undo", ":Hiraishin undo")
      )
    )
  else
    util.notify("Kunai list updated")
  end
  return true
end

local HELP = {
  "Manager: seal │ name │ path:line │ note",
  "  edit seal (1-9, -), name (-: none) or note",
  "  reorder lines to reorder · delete lines to delete",
  "  :w apply · u undo edits · :Hiraishin undo after applying",
  "  <CR> jump · <Tab>/<S-Tab> other list · q close",
}

local function close(state, force)
  if not force and vim.api.nvim_buf_is_valid(state.buf) and vim.bo[state.buf].modified then
    if vim.fn.confirm("Discard changes to the kunai list?", "&Discard\n&Cancel", 2) ~= 1 then
      return false
    end
  end
  if vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  if current == state then
    current = nil
  end
  return true
end

local function jump_cursor(state)
  local row = M.parse_line(vim.api.nvim_get_current_line(), 0)
  if not row then
    return
  end
  if vim.bo[state.buf].modified then
    return util.notify("Apply (:w) or discard (q) your edits first", vim.log.levels.WARN)
  end
  local list = store.get(state.ctx).lists[state.list]
  local bm = list and list.bookmarks[row.id]
  if not bm then
    return
  end
  close(state, true)
  local _, err = require("hiraishin.nav").jump(state.ctx, bm, state.list)
  if err then
    util.notify(err, vim.log.levels.WARN)
  end
end

local function cycle_list(state, step)
  if vim.bo[state.buf].modified then
    return util.notify("Apply (:w) or discard (q) your edits first", vim.log.levels.WARN)
  end
  local names = vim.tbl_keys(store.get(state.ctx).lists)
  table.sort(names)
  if #names < 2 then
    return util.notify("Only one list · :Hiraishin list {name} creates another")
  end
  local idx = 1
  for i, n in ipairs(names) do
    if n == state.list then
      idx = i
    end
  end
  state.list = names[((idx - 1 + step) % #names) + 1]
  render(state)
end

---Open the manager for the active list (or `opts.list`).
---@param opts? { list?: string, global?: boolean } global: the global store's kunai
---@return hiraishin.ManagerState
function M.open(opts)
  opts = opts or {}
  if current then
    close(current, true)
  end
  local ctx = opts.global and scope.global_ctx() or scope.resolve(0)
  local data = store.get(ctx)
  local o = config.options.manager

  local buf = vim.api.nvim_create_buf(false, false)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "hiraishin"
  vim.api.nvim_buf_set_name(buf, "hiraishin://manager")

  local width = math.max(40, math.floor(vim.o.columns * o.width))
  local height = math.max(5, math.floor(vim.o.lines * o.height))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = o.border,
    title = " Kunai ",
    title_pos = "center",
    footer = " :w apply · q close · g? help ",
    footer_pos = "center",
  })
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "nvic"
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.api.nvim_win_call(win, function()
    vim.fn.matchadd("Conceal", [[\s/\x\{8}$]], 10, -1, { conceal = "" })
  end)

  local state = { ctx = ctx, list = opts.list or data.active_list, buf = buf, win = win, ids = {} }
  current = state
  render(state)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.apply(state)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      M.highlight(buf)
      set_title(state)
    end,
  })
  -- BufModifiedSet is gone in newer Neovim; TextChanged covers edits there
  if vim.fn.exists("##BufModifiedSet") == 1 then
    vim.api.nvim_create_autocmd("BufModifiedSet", {
      buffer = buf,
      callback = function()
        set_title(state)
      end,
    })
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      -- a float left behind is easy to lose; keep it only while focused
      vim.schedule(function()
        if current == state and vim.api.nvim_get_current_win() ~= state.win and not vim.bo[buf].modified then
          close(state, true)
        end
      end)
    end,
  })
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "hiraishin: " .. desc })
  end
  map("q", function()
    close(state)
  end, "Close manager")
  map("<CR>", function()
    jump_cursor(state)
  end, "Jump to kunai")
  map("<Tab>", function()
    cycle_list(state, 1)
  end, "Next list")
  map("<S-Tab>", function()
    cycle_list(state, -1)
  end, "Previous list")
  map("g?", function()
    util.notify(table.concat(HELP, "\n"))
  end, "Help")
  return state
end

---@return hiraishin.ManagerState?
function M.current()
  return current
end

return M
