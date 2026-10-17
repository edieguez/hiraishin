---Editing a kunai's note in a small floating buffer.
local M = {}

---Write a note straight into the store (any list, any file of the scope).
local function save_direct(target, text)
  local store = require("hiraishin.store")
  local list = store.get(target.ctx).lists[target.list]
  local bm = list and list.bookmarks[target.id]
  if not bm then
    return
  end
  bm.note = text
  bm.updated_at = os.time()
  store.changed(target.ctx)
  require("hiraishin.tracker").reconcile({ store = target.ctx.store })
  require("hiraishin.events").emit("HiraishinUpdate", { bookmark = vim.deepcopy(bm), list = target.list })
end

---Open the note editor. Without `target`: the kunai on the cursor line
---(placing one if needed). :w (or <C-s>) saves, q / <Esc> in normal mode closes.
---@param target? { id: string, list: string, ctx: hiraishin.Context }
function M.edit(target)
  local h = require("hiraishin")
  local bm
  if target then
    local list = require("hiraishin.store").get(target.ctx).lists[target.list]
    bm = list and list.bookmarks[target.id]
    if not bm then
      return
    end
  else
    bm = h.at_cursor()
    if not bm then
      local added, err = h.add()
      if not added then
        return require("hiraishin.util").notify(err or "cannot place a kunai here", vim.log.levels.WARN)
      end
      bm = added
    end
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
      local note = vim.trim(text) ~= "" and vim.trim(text) or nil
      if target then
        save_direct(target, note)
      else
        h.update(id, { note = note or false }, { bufnr = origin_buf })
      end
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
