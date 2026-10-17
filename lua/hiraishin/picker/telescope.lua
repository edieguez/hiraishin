---telescope.nvim backend.
local M = {}

function M.available()
  return (pcall(require, "telescope.pickers"))
end

---@param p table see hiraishin.picker.open
function M.open(p)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local core = require("hiraishin.picker")

  local function finder(entries)
    return finders.new_table({
      results = entries,
      entry_maker = function(e)
        return {
          value = e,
          display = e.label,
          ordinal = e.ordinal,
          filename = e.abs,
          lnum = e.line,
          col = e.col + 1,
        }
      end,
    })
  end

  local picker = pickers.new({}, {
    prompt_title = p.title,
    finder = finder(p.entries),
    sorter = conf.generic_sorter({}),
    previewer = conf.qflist_previewer({}),
    attach_mappings = function(prompt_bufnr, map)
      local function selected()
        local sel = state.get_selected_entry()
        return sel and sel.value
      end
      local function close_then(fn)
        local e = selected()
        actions.close(prompt_bufnr)
        if e then
          vim.schedule(function()
            fn(e)
          end)
        end
      end

      actions.select_default:replace(function()
        close_then(function(e)
          core.actions.jump(p.ctx, e)
        end)
      end)

      local handlers = {
        delete = function()
          local e = selected()
          if not e then
            return
          end
          core.actions.delete(p.ctx, e)
          local fresh = p.refresh()
          if #fresh == 0 then
            return actions.close(prompt_bufnr)
          end
          state.get_current_picker(prompt_bufnr):refresh(finder(fresh), { reset_prompt = false })
        end,
        rename = function()
          close_then(function(e)
            core.actions.rename(p.ctx, e, p.reopen)
          end)
        end,
        note = function()
          close_then(function(e)
            core.actions.note(p.ctx, e)
          end)
        end,
        quickfix = function()
          local entries = {}
          for entry in state.get_current_picker(prompt_bufnr).manager:iter() do
            table.insert(entries, entry.value)
          end
          actions.close(prompt_bufnr)
          vim.schedule(function()
            core.actions.quickfix(entries)
          end)
        end,
      }
      for _, kind in ipairs({ "vsplit", "split", "tab" }) do
        handlers[kind] = function()
          close_then(function(e)
            core.actions.jump(p.ctx, e, kind)
          end)
        end
      end
      for name, fn in pairs(handlers) do
        if p.keys[name] then
          map("i", p.keys[name], fn)
          map("n", p.keys[name], fn)
        end
      end
      return true
    end,
  })
  picker:find()
  return picker
end

return M
