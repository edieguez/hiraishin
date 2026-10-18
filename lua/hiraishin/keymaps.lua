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
  toggle = {
    lhs = "<leader>hh",
    desc = "Toggle kunai",
    rhs = "<cmd>Hiraishin toggle<cr>",
    -- in visual mode: a range kunai over the selected lines
    xrhs = ":Hiraishin toggle<cr>",
  },
  add = {
    lhs = "<leader>ha",
    desc = "Place / rename named kunai",
    rhs = "<cmd>Hiraishin! add<cr>",
    xrhs = ":Hiraishin! add<cr>",
  },
  note = { lhs = "<leader>hn", desc = "Edit kunai note", rhs = "<cmd>Hiraishin note<cr>" },
  delete = { lhs = "<leader>hd", desc = "Remove kunai on line", rhs = "<cmd>Hiraishin delete<cr>" },
  pick = { lhs = "<leader>hf", desc = "Find kunai", rhs = "<cmd>Hiraishin pick<cr>" },
  pick_all = { lhs = "<leader>hF", desc = "Find kunai (all lists)", rhs = "<cmd>Hiraishin pick all<cr>" },
  global = { lhs = "<leader>hg", desc = "Toggle global kunai", rhs = "<cmd>Hiraishin global<cr>" },
  pick_global = { lhs = "<leader>hG", desc = "Find global kunai", rhs = "<cmd>Hiraishin pick global<cr>" },
  quickfix = { lhs = "<leader>hq", desc = "Kunai to quickfix", rhs = "<cmd>Hiraishin quickfix<cr>" },
  manager = { lhs = "<leader>he", desc = "Edit kunai (manager)", rhs = "<cmd>Hiraishin manager<cr>" },
  list = { lhs = "<leader>hl", desc = "Switch kunai list", rhs = "<cmd>Hiraishin list<cr>" },
  undo = { lhs = "<leader>hu", desc = "Undo kunai deletion", rhs = "<cmd>Hiraishin undo<cr>" },
  seal_free = {
    lhs = "mm",
    desc = "Seal with the next free number",
    rhs = function()
      require("hiraishin.commands").seal_free()
    end,
  },
  camp = {
    lhs = "m0",
    desc = "Make this line the camp",
    rhs = function()
      require("hiraishin.commands").set_camp()
    end,
  },
  go_camp = {
    lhs = "g0",
    desc = "Go to camp (at camp: back out)",
    rhs = function()
      report(h().go_camp())
    end,
  },
  go_camp_alt = {
    lhs = "<BS>",
    desc = "Go to camp (at camp: back out)",
    rhs = function()
      report(h().go_camp())
    end,
  },
  seals = {
    lhs = "g<Space>",
    desc = "Seal menu",
    rhs = function()
      require("hiraishin.seal_menu").open()
    end,
  },
  next = {
    lhs = "]k",
    desc = "Next kunai in buffer",
    rhs = function()
      report(h().next({ count = vim.v.count1 }))
    end,
  },
  prev = {
    lhs = "[k",
    desc = "Previous kunai in buffer",
    rhs = function()
      report(h().prev({ count = vim.v.count1 }))
    end,
  },
  next_list = {
    lhs = "]K",
    desc = "Next kunai in list",
    rhs = function()
      report(h().next({ count = vim.v.count1, scope = "list" }))
    end,
  },
  prev_list = {
    lhs = "[K",
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
    prefix = "m",
    desc = "Seal kunai as %d",
    rhs = function(n)
      return function()
        require("hiraishin.commands").seal(n)
      end
    end,
  },
  jump_slot = {
    prefix = "g",
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

---Global mapping of `lhs`, ignoring buffer-local ones (setup runs in whatever
---buffer is current: a dashboard's keys must not keep hiraishin's from being set).
---@return table maparg dict, empty when none
local function global_map(lhs, mode)
  local buf = vim.api.nvim_create_buf(false, true)
  local map = {}
  vim.api.nvim_buf_call(buf, function()
    map = vim.fn.maparg(lhs, mode, false, true)
  end)
  vim.api.nvim_buf_delete(buf, { force = true })
  return map
end

local function is_free(lhs, mode)
  return vim.tbl_isempty(global_map(lhs, mode))
end

-- m{char} keys (m1..m9, mm, m0) are served by one `m` mapping that waits for
-- the next key as long as it takes: separate m{char} mappings would fall back
-- to Vim's own `m` after 'timeoutlen'. Any other key still sets a Vim mark.
---@type table<string, { rhs: string|function, desc: string }>
local m_keys = {}

local function m_dispatch()
  local ok, ch = pcall(vim.fn.getcharstr)
  if not ok or ch == "" or ch == "\27" then
    return
  end
  local own = m_keys[ch]
  if own then
    if type(own.rhs) == "function" then
      return own.rhs()
    end
    return vim.api.nvim_feedkeys(vim.keycode(own.rhs), "m", false)
  end
  -- another mapping starting with m, or Vim's own mark
  local other = vim.fn.maparg("m" .. ch, "n", false, true)
  if other.callback then
    return other.callback()
  elseif other.rhs and other.rhs ~= "" then
    return vim.api.nvim_feedkeys(vim.keycode(other.rhs), other.noremap == 1 and "n" or "m", false)
  end
  vim.api.nvim_feedkeys("m" .. ch, "n", false)
end

---True when `lhs` is served by hiraishin (directly or through the m key).
---@param lhs string
---@return boolean
function M.is_set(lhs)
  if lhs:match("^m.$") and m_keys[lhs:sub(2)] then
    return true
  end
  local map = global_map(lhs, "n")
  return map.desc ~= nil and vim.startswith(map.desc, "hiraishin: ")
end

local function clear()
  for _, a in ipairs(applied) do
    local map = vim.fn.maparg(a.lhs, a.mode, false, true)
    -- only remove mappings that are still ours
    if map.desc and vim.startswith(map.desc, DESC_PREFIX) then
      pcall(vim.keymap.del, a.mode, a.lhs)
    end
  end
  applied = {}
  by_action = {}
  m_keys = {}
end

-- the feature a keymap action counts as in the stats
local FEATURE = { go_camp_alt = "go_camp" }
local function feature_of(action)
  if not action then
    return "other"
  end
  if action:match("^assign_slot_") then
    return "seal"
  elseif action:match("^jump_slot_") then
    return "jump"
  end
  return FEATURE[action] or action
end

---With stats on, a mapping counts its use (and the key that was pressed).
local function counted(rhs, action, lhs)
  local stats = require("hiraishin.stats")
  if not stats.enabled() then
    return rhs
  end
  local run = rhs
  if type(rhs) == "string" then
    local cmd = rhs:match("^<[Cc][Mm][Dd]>(.*)<[Cc][Rr]>$")
    run = cmd and function()
      vim.cmd(cmd)
    end or function()
      vim.api.nvim_feedkeys(vim.keycode(rhs), "m", false)
    end
  end
  return function()
    stats.as(feature_of(action), "key:" .. lhs, run)
  end
end

local function set(lhs, rhs, desc, forced, action, mode)
  mode = mode or "n"
  if mode == "n" then
    rhs = counted(rhs, action, lhs)
  end
  if mode == "n" and lhs:match("^m.$") then
    -- served by the waiting `m` key (see m_dispatch)
    if forced or is_free(lhs, mode) then
      m_keys[lhs:sub(2)] = { rhs = rhs, desc = desc }
      if action then
        by_action[action] = lhs
      end
    end
    return
  end
  -- user overrides always win; defaults never clobber an existing mapping
  if forced or is_free(lhs, mode) then
    vim.keymap.set(mode, lhs, rhs, { desc = DESC_PREFIX .. desc, silent = true })
    table.insert(applied, { mode = mode, lhs = global_map(lhs, mode).lhs or lhs })
    if action and mode == "n" then
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
      if def.xrhs then
        set(lhs, def.xrhs, def.desc .. " (range)", overrides[action] ~= nil, action, "x")
      end
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
  if next(m_keys) then
    local cur = global_map("m", "n")
    if vim.tbl_isempty(cur) or (cur.desc or ""):find("which-key-trigger", 1, true) then
      vim.keymap.set(
        "n",
        "m",
        m_dispatch,
        { desc = DESC_PREFIX .. "Seal (m1-m9, mm), camp (m0) or Vim mark", nowait = true }
      )
      table.insert(applied, { mode = "n", lhs = "m" })
    else
      -- something else owns `m`: fall back to plain m{char} mappings
      for ch, k in pairs(m_keys) do
        vim.keymap.set("n", "m" .. ch, k.rhs, { desc = DESC_PREFIX .. k.desc, silent = true })
        table.insert(applied, { mode = "n", lhs = "m" .. ch })
      end
    end
  end
  -- label the <leader>h group in which-key (v3 API), when it is installed
  -- (the group of the toggle key: <leader>hh -> <leader>h)
  local toggle = by_action.toggle
  local prefix = toggle and #toggle > 1 and toggle:sub(1, -2) or nil
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
