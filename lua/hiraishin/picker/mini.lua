---mini.pick backend. Splits use mini.pick's own keys (<C-s>, <C-v>, <C-t>).
local M = {}

function M.available()
  if _G.MiniPick == nil then
    pcall(require, "mini.pick")
  end
  return _G.MiniPick ~= nil
end

local function to_items(entries)
  local items = {}
  for i, e in ipairs(entries) do
    local text = e.icon and (e.icon .. " " .. e.label) or e.label
    items[i] = { text = text, path = e.abs, lnum = e.line, col = e.col + 1, entry = e }
  end
  return items
end

---@param p table see hiraishin.picker.open
function M.open(p)
  local MiniPick = _G.MiniPick
  local core = require("hiraishin.picker")

  local function current()
    local m = MiniPick.get_picker_matches()
    return m and m.current and m.current.entry or nil
  end
  local function then_stop(fn)
    return function()
      local e = current()
      if e then
        vim.schedule(function()
          fn(e)
        end)
      end
      return true
    end
  end

  local mappings = {}
  local custom = {
    hiraishin_delete = {
      key = p.keys.delete,
      func = function()
        local e = current()
        if not e then
          return
        end
        core.actions.delete(p.ctx, e)
        local fresh = p.refresh()
        if #fresh == 0 then
          return true
        end
        MiniPick.set_picker_items(to_items(fresh))
      end,
    },
    hiraishin_rename = {
      key = p.keys.rename,
      func = then_stop(function(e)
        core.actions.rename(p.ctx, e, p.reopen)
      end),
    },
    hiraishin_note = {
      key = p.keys.note,
      func = then_stop(function(e)
        core.actions.note(p.ctx, e)
      end),
    },
    hiraishin_quickfix = {
      key = p.keys.quickfix,
      func = function()
        local m = MiniPick.get_picker_matches() or {}
        local entries = vim.tbl_map(function(it)
          return it.entry
        end, m.all or {})
        vim.schedule(function()
          core.actions.quickfix(entries)
        end)
        return true
      end,
    },
    hiraishin_list = {
      key = p.keys.list,
      func = function()
        vim.schedule(p.switch_list)
        return true
      end,
    },
  }
  for name, def in pairs(custom) do
    if def.key then
      mappings[name] = { char = def.key, func = def.func }
    end
  end

  return MiniPick.start({
    source = {
      name = p.title,
      items = to_items(p.entries),
      choose = function(item)
        -- picker still open here; the target window may be a fresh split
        local target = MiniPick.get_picker_state().windows.target
        vim.schedule(function()
          core.actions.jump(p.ctx, item.entry, nil, target)
        end)
      end,
    },
    mappings = mappings,
  })
end

return M
