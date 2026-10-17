local config = require("hiraishin.config")

local M = {}

local function h()
  return require("hiraishin")
end

local function report(_, err)
  if err then
    require("hiraishin.util").notify(err, vim.log.levels.WARN)
  end
end

---Single-key actions. `lhs` is the default; override with keymaps = { action = "<lhs>" | false }.
M.defaults = {
  toggle = { lhs = "<leader>hh", desc = "Toggle kunai", rhs = "<cmd>Hiraishin toggle<cr>" },
  add = { lhs = "<leader>ha", desc = "Place / rename named kunai", rhs = "<cmd>Hiraishin! add<cr>" },
  note = { lhs = "<leader>hn", desc = "Edit kunai note", rhs = "<cmd>Hiraishin note<cr>" },
  delete = { lhs = "<leader>hd", desc = "Remove kunai on line", rhs = "<cmd>Hiraishin delete<cr>" },
  next = {
    lhs = "]m",
    desc = "Next kunai in buffer",
    rhs = function()
      report(h().next({ count = vim.v.count1 }))
    end,
  },
  prev = {
    lhs = "[m",
    desc = "Previous kunai in buffer",
    rhs = function()
      report(h().prev({ count = vim.v.count1 }))
    end,
  },
  next_list = {
    lhs = "]M",
    desc = "Next kunai in list",
    rhs = function()
      report(h().next({ count = vim.v.count1, scope = "list" }))
    end,
  },
  prev_list = {
    lhs = "[M",
    desc = "Previous kunai in list",
    rhs = function()
      report(h().prev({ count = vim.v.count1, scope = "list" }))
    end,
  },
}

---Nine-key groups. Override with a prefix ("<leader>j" → <leader>j1..9) or false.
M.groups = {
  assign_slot = {
    prefix = "<leader>h",
    desc = "Seal kunai as %d",
    rhs = function(n)
      return function()
        report(h().seal(n))
      end
    end,
  },
  jump_slot = {
    prefix = "<leader>",
    desc = "Jump to seal %d",
    rhs = function(n)
      return function()
        report(h().jump(n))
      end
    end,
  },
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

local function set(lhs, rhs, desc, forced)
  -- user overrides always win; defaults never clobber an existing mapping
  if forced or vim.fn.maparg(lhs, "n") == "" then
    vim.keymap.set("n", lhs, rhs, { desc = DESC_PREFIX .. desc, silent = true })
    table.insert(applied, vim.fn.maparg(lhs, "n", false, true).lhs or lhs)
  end
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
    if lhs then
      set(lhs, def.rhs, def.desc, overrides[action] ~= nil)
    end
  end
  for group, def in pairs(M.groups) do
    local prefix = def.prefix
    if overrides[group] ~= nil then
      prefix = overrides[group]
    end
    if prefix then
      for n = 1, 9 do
        set(prefix .. n, def.rhs(n), def.desc:format(n), overrides[group] ~= nil)
      end
    end
  end
end

return M
