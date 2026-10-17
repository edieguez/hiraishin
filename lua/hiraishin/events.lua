local M = {}

---Fire a `User` autocmd, e.g. emit("HiraishinAdd", { bookmark = ..., list = ... }).
---@param pattern string
---@param data table
function M.emit(pattern, data)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern, modeline = false, data = data })
end

return M
