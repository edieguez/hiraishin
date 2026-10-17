---Editing a kunai's note in a small floating buffer.
local M = {}

---Open the note editor for the kunai on the cursor line (placing one if
---needed). :w (or <C-s>) saves, q / <Esc> in normal mode closes.
function M.edit()
  local h = require("hiraishin")
  local bm = h.at_cursor()
  if not bm then
    local added, err = h.add()
    if not added then
      return require("hiraishin.util").notify(err or "cannot place a kunai here", vim.log.levels.WARN)
    end
    bm = added
  end
  local id = bm.id
  local origin_buf = vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(buf, "hiraishin://note/" .. id)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(bm.note or "", "\n"))
  vim.bo[buf].modified = false

  local width = math.min(70, math.max(30, math.floor(vim.o.columns * 0.5)))
  local height = math.min(12, math.max(3, vim.api.nvim_buf_line_count(buf) + 1))
  local title = " Kunai note: " .. (bm.name or bm.anchor.text):sub(1, width - 16) .. " "
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "left",
  })
  vim.wo[win].wrap = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      h.update(id, { note = vim.trim(text) ~= "" and text or false }, { bufnr = origin_buf })
      vim.bo[buf].modified = false
      close()
    end,
  })
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close, { buffer = buf, nowait = true, desc = "Close kunai note" })
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", "<cmd>write<cr>", { buffer = buf, desc = "Save kunai note" })
  return buf, win
end

return M
