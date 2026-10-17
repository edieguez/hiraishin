local config = require("hiraishin.config")

local M = {}

local function h()
  return require("hiraishin")
end

---Feedback for keymaps: guidance ("No kunai below") is a quiet echo,
---real problems ("File not found") are warnings.
local function report(_, err)
  if not err then
    return
  end
  local ui = require("hiraishin.ui")
  if err:match("^File not found") or err:match("^Not a file") or err:match("^Buffer has no") then
    ui.warn(err)
  else
    ui.info(err)
  end
end

---Single-key actions. `lhs` is the default; override with keymaps = { action = "<lhs>" | false }.
M.defaults = {
  toggle = { lhs = "<leader>hh", desc = "Toggle kunai", rhs = "<cmd>Hiraishin toggle<cr>" },
  add = { lhs = "<leader>ha", desc = "Place / rename named kunai", rhs = "<cmd>Hiraishin! add<cr>" },
  note = { lhs = "<leader>hn", desc = "Edit kunai note", rhs = "<cmd>Hiraishin note<cr>" },
  delete = { lhs = "<leader>hd", desc = "Remove kunai on line", rhs = "<cmd>Hiraishin delete<cr>" },
  pick = { lhs = "<leader>hf", desc = "Find kunai", rhs = "<cmd>Hiraishin pick<cr>" },
  pick_all = { lhs = "<leader>hF", desc = "Find kunai (all lists)", rhs = "<cmd>Hiraishin pick all<cr>" },
  quickfix = { lhs = "<leader>hq", desc = "Kunai to quickfix", rhs = "<cmd>Hiraishin quickfix<cr>" },
  manager = { lhs = "<leader>he", desc = "Edit kunai (manager)", rhs = "<cmd>Hiraishin manager<cr>" },
  list = { lhs = "<leader>hl", desc = "Switch kunai list", rhs = "<cmd>Hiraishin list<cr>" },
  undo = { lhs = "<leader>hu", desc = "Undo kunai deletion", rhs = "<cmd>Hiraishin undo<cr>" },
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
  next_seal = {
    lhs = "<leader>hj",
    desc = "Next seal (1 → 9)",
    rhs = function()
      report(h().next({ count = vim.v.count1, scope = "seal" }))
    end,
  },
  prev_seal = {
    lhs = "<leader>hk",
    desc = "Previous seal (9 → 1)",
    rhs = function()
      report(h().prev({ count = vim.v.count1, scope = "seal" }))
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
        require("hiraishin.commands").seal(n)
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
---@type table<string, string> action -> lhs as configured (for hints)
local by_action = {}

---Key bound to an action by hiraishin, nil when none (for messages).
---@param action string
---@return string?
function M.lhs_of(action)
  return by_action[action]
end

local function clear()
  for _, lhs in ipairs(applied) do
    local map = vim.fn.maparg(lhs, "n", false, true)
    -- only remove mappings that are still ours
    if map.desc and vim.startswith(map.desc, DESC_PREFIX) then
      pcall(vim.keymap.del, "n", lhs)
    end
  end
  applied = {}
  by_action = {}
end

local function set(lhs, rhs, desc, forced, action)
  -- user overrides always win; defaults never clobber an existing mapping
  if forced or vim.fn.maparg(lhs, "n") == "" then
    vim.keymap.set("n", lhs, rhs, { desc = DESC_PREFIX .. desc, silent = true })
    table.insert(applied, vim.fn.maparg(lhs, "n", false, true).lhs or lhs)
    if action then
      by_action[action] = lhs
    end
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
      set(lhs, def.rhs, def.desc, overrides[action] ~= nil, action)
    end
  end
  for group, def in pairs(M.groups) do
    local prefix = def.prefix
    if overrides[group] ~= nil then
      prefix = overrides[group]
    end
    if prefix then
      for n = 1, 9 do
        set(prefix .. n, def.rhs(n), def.desc:format(n), overrides[group] ~= nil, group .. "_" .. n)
      end
    end
  end
  -- label the <leader>h group in which-key (v3 API), when it is installed
  local prefix = overrides.assign_slot
  if prefix == nil then
    prefix = M.groups.assign_slot.prefix
  end
  if prefix then
    vim.schedule(function()
      local ok, wk = pcall(require, "which-key")
      if ok and type(wk) == "table" and wk.add then
        pcall(wk.add, { { prefix, group = "hiraishin", icon = { icon = "⚡", color = "yellow" } } })
      end
    end)
  end
end

return M
