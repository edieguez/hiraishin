---The seal menu (g<Space>): the camp (0) and seals 1-9 of the active list at
---a glance. A digit jumps there, d + digit (or dd on a line) clears it.
local M = {}

local ui = require("hiraishin.ui")

---@class hiraishin.SealMenu
---@field buf integer
---@field win integer
---@field origin integer buffer the menu was opened from
---@field rows table<integer, hiraishin.Entry?> seal -> entry

---@type hiraishin.SealMenu?
local current

local function entries(origin)
  local picker = require("hiraishin.picker")
  local list, ctx = picker.entries({ bufnr = origin })
  local rows = {}
  for _, e in ipairs(list) do
    if e.slot then
      rows[e.slot] = e
    end
    if e.camp then
      rows[0] = e -- the camp is row 0
    end
  end
  return rows, ctx
end

local function render(menu)
  local rows, ctx = entries(menu.origin)
  menu.rows, menu.ctx = rows, ctx
  local wname, wloc = 1, 1
  for n = 0, 9 do
    local e = rows[n]
    if e then
      wname = math.max(wname, vim.fn.strdisplaywidth(e.bookmark.name or "—"))
      wloc = math.max(wloc, vim.fn.strdisplaywidth(e.file .. ":" .. e.line))
    end
  end
  local lines, marks = {}, {}
  for n = 0, 9 do
    local e = rows[n]
    if e then
      local name = e.bookmark.name or "—"
      local loc = e.file .. ":" .. e.line
      local text = e.stale and "(stale)" or vim.trim(e.text)
      local line = string.format(
        " %d  %s%s  %s%s  %s",
        n,
        name,
        string.rep(" ", wname - vim.fn.strdisplaywidth(name)),
        loc,
        string.rep(" ", wloc - vim.fn.strdisplaywidth(loc)),
        text
      )
      table.insert(lines, line)
      table.insert(marks, { n, #name, #loc, e.stale })
    else
      table.insert(lines, n == 0 and " 0  · no camp (m0)" or string.format(" %d  ·", n))
      table.insert(marks, { n })
    end
  end
  vim.bo[menu.buf].modifiable = true
  vim.api.nvim_buf_set_lines(menu.buf, 0, -1, false, lines)
  vim.bo[menu.buf].modifiable = false
  local ns = require("hiraishin.signs").menu_ns
  vim.api.nvim_buf_clear_namespace(menu.buf, ns, 0, -1)
  for i, m in ipairs(marks) do
    local row = i - 1
    vim.api.nvim_buf_set_extmark(menu.buf, ns, row, 1, { end_col = 2, hl_group = "HiraishinSignSlot" })
    if m[2] then
      vim.api.nvim_buf_set_extmark(menu.buf, ns, row, 4, { end_col = 4 + m[2], hl_group = "Title" })
      local loc_col = 4 + m[2] + (wname - m[2]) + 2
      vim.api.nvim_buf_set_extmark(menu.buf, ns, row, loc_col, {
        end_col = loc_col + m[3],
        hl_group = m[4] and "HiraishinSignStale" or "HiraishinManagerPath",
      })
    else
      vim.api.nvim_buf_set_extmark(menu.buf, ns, row, 4, { end_col = #lines[i], hl_group = "NonText" })
    end
  end
end

local function close(menu)
  if vim.api.nvim_win_is_valid(menu.win) then
    vim.api.nvim_win_close(menu.win, true)
  end
  if current == menu then
    current = nil
  end
end

local function go(menu, n)
  require("hiraishin.stats").record("menu_go", "menu")
  local e = menu.rows[n]
  if not e then
    return ui.info(n == 0 and "No camp yet" or string.format("Seal %d is empty", n))
  end
  close(menu)
  local list = require("hiraishin.store").get(menu.ctx).lists[e.list]
  local bm = list and list.bookmarks[e.id]
  if bm then
    local _, err = require("hiraishin.nav").jump(menu.ctx, bm, e.list)
    if err then
      ui.warn(err)
    end
  end
end

local function clear(menu, n)
  require("hiraishin.stats").record("menu_clear", "menu")
  local e = menu.rows[n]
  if not e then
    return
  end
  if n == 0 then
    local old = require("hiraishin").clear_camp({ bufnr = menu.origin })
    ui.info(old and old.removed and "Camp removed, and the kunai it made" or "Camp removed")
    return render(menu)
  end
  local updated = require("hiraishin").update(e.id, { slot = false }, { bufnr = menu.origin })
  if updated and updated.removed then
    ui.info(
      string.format("Seal %d removed, and the kunai it made · %s to undo", n, ui.hint("undo", ":Hiraishin undo"))
    )
  else
    ui.info(string.format("Seal %d removed", n))
  end
  render(menu)
end

---Open the seal menu for the current buffer's scope.
---@return hiraishin.SealMenu
function M.open()
  if current then
    close(current)
  end
  local origin = vim.api.nvim_get_current_buf()
  require("hiraishin.stats").ui_open("seal_menu")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hiraishin_seals"
  local width = math.min(vim.o.columns - 4, math.max(40, math.floor(vim.o.columns * 0.6)))
  local list = require("hiraishin.store").get(require("hiraishin.scope").resolve(origin)).active_list
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - 12) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 10,
    style = "minimal",
    border = require("hiraishin.config").options.manager.border,
    title = " Seals · " .. list .. " ",
    title_pos = "center",
    footer = " 0-9 go · d0-9 clear · q close ",
    footer_pos = "center",
  })
  vim.wo[win].cursorline = true
  local menu = { buf = buf, win = win, origin = origin, rows = {} }
  current = menu
  render(menu)

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "hiraishin: " .. desc })
  end
  for n = 0, 9 do
    map(tostring(n), function()
      go(menu, n)
    end, n == 0 and "Go to camp" or ("Go to seal " .. n))
    map("d" .. n, function()
      clear(menu, n)
    end, n == 0 and "Remove the camp" or ("Clear seal " .. n))
  end
  map("<CR>", function()
    go(menu, vim.api.nvim_win_get_cursor(menu.win)[1] - 1)
  end, "Go to the seal on this line")
  map("dd", function()
    clear(menu, vim.api.nvim_win_get_cursor(menu.win)[1] - 1)
  end, "Clear the seal on this line")
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    map(lhs, function()
      close(menu)
    end, "Close")
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(menu)
      end)
    end,
  })
  return menu
end

---@return hiraishin.SealMenu?
function M.current()
  return current
end

return M
