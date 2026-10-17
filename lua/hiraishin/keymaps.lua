local config = require("hiraishin.config")

local M = {}

-- Phase 1 actions; more arrive with navigation, picker and manager.
M.defaults = {
  toggle = { lhs = "<leader>hh", desc = "Toggle kunai", rhs = "<cmd>Hiraishin toggle<cr>" },
  add = { lhs = "<leader>ha", desc = "Place named kunai", rhs = "<cmd>Hiraishin! add<cr>" },
  delete = { lhs = "<leader>hd", desc = "Remove kunai on line", rhs = "<cmd>Hiraishin delete<cr>" },
}

local DESC_PREFIX = "hiraishin: "

---@type string[] expanded lhs (leader resolved) of maps hiraishin set
local applied = {}

local function clear()
  for _, lhs in ipairs(applied) do
    local map = vim.fn.maparg(lhs, "n", false, true)
    -- only remove mappings that are still ours
    if map.desc and vim.startswith(map.desc, DESC_PREFIX) then
      pcall(vim.keymap.del, "n", lhs)
    end
  end
  applied = {}
end

function M.setup()
  clear()
  local opt = config.options.keymaps
  if opt == false then
    return
  end
  local overrides = type(opt) == "table" and opt or {}
  for action, def in pairs(M.defaults) do
    local lhs = def.lhs
    if overrides[action] ~= nil then
      lhs = overrides[action]
    end
    -- user overrides always win; defaults never clobber an existing mapping
    if lhs and (overrides[action] or vim.fn.maparg(lhs, "n") == "") then
      vim.keymap.set("n", lhs, def.rhs, { desc = DESC_PREFIX .. def.desc, silent = true })
      table.insert(applied, vim.fn.maparg(lhs, "n", false, true).lhs or lhs)
    end
  end
end

return M
