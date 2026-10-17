---How hiraishin talks: quiet echoes for routine feedback, titled
---notifications for anything you should not miss.
local M = {}

---Recent messages, newest last (also handy for tests).
---@type { msg: string, level: integer }[]
M.history = {}

local function remember(msg, level)
  table.insert(M.history, { msg = msg, level = level })
  if #M.history > 50 then
    table.remove(M.history, 1)
  end
end

---Routine feedback ("Kunai placed"). Shown in the command line, not as a toast.
---@param msg string
function M.info(msg)
  remember(msg, vim.log.levels.INFO)
  local o = require("hiraishin.config").options.messages
  if o == "silent" then
    return
  elseif o == "notify" then
    vim.notify(msg, vim.log.levels.INFO, { title = "Hiraishin" })
    return
  end
  vim.api.nvim_echo({ { "Hiraishin ", "HiraishinTitle" }, { msg } }, false, {})
end

---@param msg string
function M.warn(msg)
  remember(msg, vim.log.levels.WARN)
  vim.notify(msg, vim.log.levels.WARN, { title = "Hiraishin" })
end

---@param msg string
function M.error(msg)
  remember(msg, vim.log.levels.ERROR)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Hiraishin" })
end

---@param msg string
---@param level? integer
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  if level >= vim.log.levels.ERROR then
    M.error(msg)
  elseif level >= vim.log.levels.WARN then
    M.warn(msg)
  else
    M.info(msg)
  end
end

---How to trigger an action: its key when hiraishin mapped one, else the command.
---@param action string keymap action name (e.g. "undo", "toggle")
---@param command string fallback, e.g. ":Hiraishin undo"
---@return string
function M.hint(action, command)
  local lhs = require("hiraishin.keymaps").lhs_of(action)
  return lhs or command
end

---Last message text (tests and debugging).
---@return string?
function M.last()
  local m = M.history[#M.history]
  return m and m.msg or nil
end

return M
