---snacks.picker backend.
local M = {}

function M.available()
  local ok, snacks = pcall(require, "snacks")
  return ok and type(snacks) == "table" and snacks.picker ~= nil
end

local function to_items(entries)
  local items = {}
  for i, e in ipairs(entries) do
    items[i] = {
      idx = i,
      score = 0,
      text = e.ordinal,
      file = e.abs,
      pos = { e.line, e.col },
      entry = e,
    }
  end
  return items
end

---@param e hiraishin.Entry
local function format(e)
  local note_icon = require("hiraishin.config").options.virt_text.note_icon
  local ret = {
    { e.slot and ("[" .. e.slot .. "]") or "[ ]", e.slot and "HiraishinSignSlot" or "Comment" },
    { " " },
    { e.bookmark.name or "—", e.bookmark.name and "Title" or "Comment" },
    { "  " },
  }
  if e.icon then
    table.insert(ret, { e.icon .. " ", e.icon_hl or "Normal" })
  end
  if e.list and e.label:find("(" .. e.list .. ")", 1, true) then
    table.insert(ret, { "(" .. e.list .. ")  ", "Special" })
  end
  table.insert(ret, { e.file, "Directory" })
  table.insert(ret, { ":" .. e.line, "LineNr" })
  table.insert(ret, { "  " })
  if e.stale then
    table.insert(ret, { "(stale)", "HiraishinSignStale" })
  else
    table.insert(ret, { vim.trim(e.text), "Normal" })
  end
  if e.bookmark.note and require("hiraishin.config").options.picker.show_notes then
    table.insert(ret, { "  " .. note_icon .. " " .. e.bookmark.note:gsub("\n", " ⏎ "), "HiraishinVirtText" })
  end
  return ret
end

---@param p table see hiraishin.picker.open
function M.open(p)
  local Snacks = require("snacks")
  local core = require("hiraishin.picker")
  local keys = p.keys

  local function close_then(picker, fn)
    picker:close()
    vim.schedule(fn)
  end

  local actions = {
    confirm = function(picker, item)
      if item then
        close_then(picker, function()
          core.actions.jump(p.ctx, item.entry)
        end)
      end
    end,
    hiraishin_delete = function(picker, item)
      if item then
        core.actions.delete(p.ctx, item.entry)
        if #p.refresh() == 0 then
          return picker:close()
        end
        picker:refresh()
      end
    end,
    hiraishin_rename = function(picker, item)
      if item then
        close_then(picker, function()
          core.actions.rename(p.ctx, item.entry, p.reopen)
        end)
      end
    end,
    hiraishin_note = function(picker, item)
      if item then
        close_then(picker, function()
          core.actions.note(p.ctx, item.entry)
        end)
      end
    end,
    hiraishin_quickfix = function(picker)
      local entries = vim.tbl_map(function(it)
        return it.entry
      end, picker:items())
      close_then(picker, function()
        core.actions.quickfix(entries)
      end)
    end,
    hiraishin_list = function(picker)
      close_then(picker, p.switch_list)
    end,
  }
  for _, kind in ipairs({ "vsplit", "split", "tab" }) do
    actions["hiraishin_" .. kind] = function(picker, item)
      if item then
        close_then(picker, function()
          core.actions.jump(p.ctx, item.entry, kind)
        end)
      end
    end
  end

  local win_keys = {}
  local bindings = {
    vsplit = "hiraishin_vsplit",
    split = "hiraishin_split",
    tab = "hiraishin_tab",
    delete = "hiraishin_delete",
    rename = "hiraishin_rename",
    note = "hiraishin_note",
    quickfix = "hiraishin_quickfix",
    list = "hiraishin_list",
  }
  for name, action in pairs(bindings) do
    if keys[name] then
      win_keys[Snacks.util.normkey(keys[name])] = { action, mode = { "n", "i" } }
    end
  end

  return Snacks.picker.pick({
    source = "hiraishin",
    title = p.title,
    finder = function()
      return to_items(p.refresh())
    end,
    format = function(item)
      return format(item.entry)
    end,
    preview = "file",
    -- keep our sort (seals first, then picker.sort) until the user types
    sort = { fields = { "score:desc", "idx" } },
    matcher = { sort_empty = false },
    actions = actions,
    win = {
      input = { keys = win_keys },
      list = { keys = win_keys },
    },
  })
end

return M
