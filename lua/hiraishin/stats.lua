---Local usage stats (on by default, `stats = false` turns them off): which
---features you use, how you reach them, and where you get stuck, so you can
---triage the plugin. Only feature names, counts, days and message templates
---are kept, in one JSON file under `storage.dir`. Nothing leaves your machine.
local config = require("hiraishin.config")

local M = {}

M.VERSION = 2
local KEEP_DAYS = 90
-- the same action at the same spot within this many ms counts as a retry
M.REPEAT_MS = 2000

---@class hiraishin.Feature
---@field id string
---@field area string
---@field label string
---@field action? string keymap action whose key reaches it
---@field actions? string[] several keymap actions reach it (first is the main one)
---@field group? string nine-key group ("assign_slot", "jump_slot")
---@field key? fun(): string? key shown when it is not a keymap action
---@field cmd? string
---@field help? string help tag
---@field repeat_ok? boolean pressing it again right away is normal (stepping, undo)

M.AREAS = { "Seals", "Camp", "Placing", "Moving", "Picker", "Manager", "Lists", "Housekeeping" }

local function picker_key(name)
  return function()
    return config.options.picker.keys[name]
  end
end

local function fixed(text)
  return function()
    return text
  end
end

---@type hiraishin.Feature[]
M.CATALOG = {
  -- Seals
  {
    id = "jump",
    area = "Seals",
    label = "Go to seal or name",
    group = "jump_slot",
    cmd = ":Hiraishin jump",
    help = ":Hiraishin-jump",
  },
  {
    id = "seal",
    area = "Seals",
    label = "Seal this line",
    group = "assign_slot",
    cmd = ":Hiraishin seal {1-9}",
    help = ":Hiraishin-seal",
  },
  {
    id = "seal_free",
    area = "Seals",
    label = "Seal, next free number",
    action = "seal_free",
    cmd = ":Hiraishin seal",
    help = ":Hiraishin-seal",
  },
  {
    id = "seals",
    area = "Seals",
    label = "Seal menu",
    action = "seals",
    cmd = ":Hiraishin seals",
    help = ":Hiraishin-seals",
    repeat_ok = true,
  },
  { id = "menu_go", area = "Seals", label = "Go from the seal menu", key = fixed("0-9"), help = ":Hiraishin-seals" },
  {
    id = "menu_clear",
    area = "Seals",
    label = "Clear in the seal menu",
    key = fixed("d0-9"),
    help = ":Hiraishin-seals",
  },
  {
    id = "next_seal",
    area = "Seals",
    label = "Next seal",
    action = "next_seal",
    cmd = ":Hiraishin next seal",
    help = "hiraishin-seals",
    repeat_ok = true,
  },
  {
    id = "prev_seal",
    area = "Seals",
    label = "Previous seal",
    action = "prev_seal",
    cmd = ":Hiraishin prev seal",
    help = "hiraishin-seals",
    repeat_ok = true,
  },
  {
    id = "seal_clear",
    area = "Seals",
    label = "Clear a seal",
    cmd = ":Hiraishin seal clear",
    help = ":Hiraishin-seal",
  },
  -- Camp
  {
    id = "camp",
    area = "Camp",
    label = "Set camp",
    action = "camp",
    cmd = ":Hiraishin camp",
    help = ":Hiraishin-camp",
  },
  {
    id = "go_camp",
    area = "Camp",
    label = "Go to camp",
    actions = { "go_camp", "go_camp_alt" },
    cmd = ":Hiraishin camp go",
    help = ":Hiraishin-camp",
    repeat_ok = true,
  },
  { id = "camp_back", area = "Camp", label = "Back out from camp", help = ":Hiraishin-camp", repeat_ok = true },
  { id = "camp_clear", area = "Camp", label = "Remove camp", cmd = ":Hiraishin camp clear", help = ":Hiraishin-camp" },
  -- Placing
  {
    id = "toggle",
    area = "Placing",
    label = "Place / remove kunai",
    action = "toggle",
    cmd = ":Hiraishin toggle",
    help = ":Hiraishin-toggle",
  },
  {
    id = "add",
    area = "Placing",
    label = "Named kunai",
    action = "add",
    cmd = ":Hiraishin! add",
    help = ":Hiraishin-add",
  },
  {
    id = "note",
    area = "Placing",
    label = "Edit note",
    action = "note",
    cmd = ":Hiraishin note",
    help = ":Hiraishin-note",
  },
  {
    id = "delete",
    area = "Placing",
    label = "Remove kunai",
    action = "delete",
    cmd = ":Hiraishin delete",
    help = ":Hiraishin-delete",
  },
  {
    id = "undo",
    area = "Placing",
    label = "Undo removal",
    action = "undo",
    cmd = ":Hiraishin undo",
    help = ":Hiraishin-undo",
    repeat_ok = true,
  },
  {
    id = "global",
    area = "Placing",
    label = "Global kunai",
    action = "global",
    cmd = ":Hiraishin global",
    help = ":Hiraishin-global",
  },
  -- Moving
  {
    id = "next",
    area = "Moving",
    label = "Next kunai in file",
    action = "next",
    cmd = ":Hiraishin next",
    help = ":Hiraishin-next",
    repeat_ok = true,
  },
  {
    id = "prev",
    area = "Moving",
    label = "Previous kunai in file",
    action = "prev",
    cmd = ":Hiraishin prev",
    help = ":Hiraishin-prev",
    repeat_ok = true,
  },
  {
    id = "next_list",
    area = "Moving",
    label = "Next kunai, any file",
    action = "next_list",
    cmd = ":Hiraishin next list",
    help = ":Hiraishin-next",
    repeat_ok = true,
  },
  {
    id = "prev_list",
    area = "Moving",
    label = "Previous kunai, any file",
    action = "prev_list",
    cmd = ":Hiraishin prev list",
    help = ":Hiraishin-prev",
    repeat_ok = true,
  },
  -- Picker
  {
    id = "pick",
    area = "Picker",
    label = "Find kunai",
    action = "pick",
    cmd = ":Hiraishin pick",
    help = ":Hiraishin-pick",
    repeat_ok = true,
  },
  {
    id = "pick_buffer",
    area = "Picker",
    label = "Find in this file",
    cmd = ":Hiraishin pick buffer",
    help = ":Hiraishin-pick",
    repeat_ok = true,
  },
  {
    id = "pick_all",
    area = "Picker",
    label = "Find in every list",
    action = "pick_all",
    cmd = ":Hiraishin pick all",
    help = ":Hiraishin-pick",
    repeat_ok = true,
  },
  {
    id = "pick_global",
    area = "Picker",
    label = "Find global kunai",
    action = "pick_global",
    cmd = ":Hiraishin pick global",
    help = ":Hiraishin-pick",
    repeat_ok = true,
  },
  {
    id = "picker_jump",
    area = "Picker",
    label = "Jump from the picker",
    key = fixed("<CR>"),
    help = "hiraishin-picker",
  },
  {
    id = "picker_delete",
    area = "Picker",
    label = "Remove in the picker",
    key = picker_key("delete"),
    help = "hiraishin-picker",
    repeat_ok = true,
  },
  {
    id = "picker_rename",
    area = "Picker",
    label = "Rename in the picker",
    key = picker_key("rename"),
    help = "hiraishin-picker",
  },
  {
    id = "picker_note",
    area = "Picker",
    label = "Note in the picker",
    key = picker_key("note"),
    help = "hiraishin-picker",
  },
  {
    id = "picker_quickfix",
    area = "Picker",
    label = "Quickfix from the picker",
    key = picker_key("quickfix"),
    help = "hiraishin-picker",
  },
  {
    id = "picker_list",
    area = "Picker",
    label = "Switch list in the picker",
    key = picker_key("list"),
    help = "hiraishin-picker",
  },
  -- Manager
  {
    id = "manager",
    area = "Manager",
    label = "Manager",
    action = "manager",
    cmd = ":Hiraishin manager",
    help = ":Hiraishin-manager",
    repeat_ok = true,
  },
  {
    id = "manager_global",
    area = "Manager",
    label = "Manager, global kunai",
    cmd = ":Hiraishin manager global",
    help = ":Hiraishin-manager",
    repeat_ok = true,
  },
  {
    id = "manager_apply",
    area = "Manager",
    label = "Apply manager edits",
    key = fixed(":w"),
    help = "hiraishin-manager",
  },
  {
    id = "manager_jump",
    area = "Manager",
    label = "Jump from the manager",
    key = fixed("<CR>"),
    help = "hiraishin-manager",
  },
  -- Lists
  {
    id = "list",
    area = "Lists",
    label = "Switch list",
    action = "list",
    cmd = ":Hiraishin list",
    help = ":Hiraishin-list",
  },
  {
    id = "list_delete",
    area = "Lists",
    label = "Delete a list",
    cmd = ":Hiraishin list delete",
    help = ":Hiraishin-list",
  },
  {
    id = "quickfix",
    area = "Lists",
    label = "Send to quickfix",
    action = "quickfix",
    cmd = ":Hiraishin quickfix",
    help = ":Hiraishin-quickfix",
  },
  {
    id = "loclist",
    area = "Lists",
    label = "Send to location list",
    cmd = ":Hiraishin loclist",
    help = ":Hiraishin-loclist",
  },
  -- Housekeeping
  {
    id = "relocate",
    area = "Housekeeping",
    label = "Relocate a kunai",
    cmd = ":Hiraishin relocate",
    help = ":Hiraishin-relocate",
  },
  {
    id = "prune",
    area = "Housekeeping",
    label = "Prune stale kunai",
    cmd = ":Hiraishin prune",
    help = ":Hiraishin-prune",
  },
  { id = "gc", area = "Housekeeping", label = "Clean up stores", cmd = ":Hiraishin gc", help = ":Hiraishin-gc" },
  { id = "scope", area = "Housekeeping", label = "Change scope", cmd = ":Hiraishin scope", help = ":Hiraishin-scope" },
  {
    id = "import",
    area = "Housekeeping",
    label = "Import Vim marks",
    cmd = ":Hiraishin import marks",
    help = ":Hiraishin-import",
  },
}

---@type table<string, hiraishin.Feature>
M.by_id = {}
for _, f in ipairs(M.CATALOG) do
  M.by_id[f.id] = f
end

-- keys that take a Vim command away; suggested back when the feature goes unused
local SHADOWS = {
  go_camp = {
    { action = "go_camp", what = "start of the screen line" },
    { action = "go_camp_alt", what = "cursor left" },
  },
  seal_free = { { action = "seal_free", what = "mark m" } },
}

-- which UI an action in it belongs to
local UI_OF_VIA = { picker = "picker", menu = "seal_menu", manager = "manager" }
M.UI_LABELS = { picker = "Picker", seal_menu = "Seal menu", manager = "Manager" }

-- counts since the last flush, added to the file on flush (several Neovim
-- instances can share the file)
local function fresh()
  return { actions = {}, friction = {}, uis = {} }
end
local delta = fresh()
local dirty = false
local timer ---@type uv.uv_timer_t?
-- set while a keymap or command runs, so it is counted once and dead ends
-- are tied to it
local active ---@type { feature: string, via: string }?
-- the last use, to spot retries and to tie a late dead end to its action
local last ---@type { feature: string, t: number, spot: string }?
-- the hiraishin window open now (picker, seal menu, manager)
local open_ui ---@type { name: string, acted: boolean }?

---@return boolean
function M.enabled()
  return config.options.stats == true
end

---@return string
function M.path()
  return config.options.storage.dir .. "/stats.json"
end

local function today()
  return os.date("%Y-%m-%d")
end

local function now_ms()
  return vim.uv.hrtime() / 1e6
end

local function spot()
  local ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
  return vim.api.nvim_get_current_buf() .. ":" .. (ok and pos[1] or 0)
end

local function schedule_flush()
  dirty = true
  if not timer then
    timer = vim.uv.new_timer()
    timer:start(
      300000,
      300000,
      vim.schedule_wrap(function()
        if dirty then
          M.flush()
        end
      end)
    )
    timer:unref()
  end
end

local function action_entry(feature)
  local a = delta.actions[feature]
  if not a then
    a = { count = 0, via = {}, days = {}, last = 0, repeats = 0 }
    delta.actions[feature] = a
  end
  return a
end

local function ui_entry(name)
  local u = delta.uis[name]
  if not u then
    u = { opened = 0, acted = 0 }
    delta.uis[name] = u
  end
  return u
end

---Count one use of a feature.
---@param feature string e.g. "seal", "go_camp", "pick"
---@param via string how it was reached: "key:<lhs>", "cmd", "picker", "menu", "manager"
function M.record(feature, via)
  if not M.enabled() then
    return
  end
  local a = action_entry(feature)
  a.count = a.count + 1
  a.via[via] = (a.via[via] or 0) + 1
  local d = today()
  a.days[d] = (a.days[d] or 0) + 1
  a.last = os.time()
  -- the same thing again at the same spot, right away: the first try likely
  -- did not do what was expected
  local t, here = now_ms(), spot()
  local f = M.by_id[feature]
  if
    last
    and last.feature == feature
    and last.spot == here
    and t - last.t <= M.REPEAT_MS
    and not (f and f.repeat_ok)
  then
    a.repeats = a.repeats + 1
  end
  last = { feature = feature, t = t, spot = here }
  -- something done inside a hiraishin window: it was not opened in vain
  local ui = UI_OF_VIA[via]
  if ui and open_ui and open_ui.name == ui and not open_ui.acted then
    open_ui.acted = true
    ui_entry(ui).acted = ui_entry(ui).acted + 1
  end
  schedule_flush()
end

---A hiraishin window (picker, seal menu, manager) was opened.
---@param name "picker"|"seal_menu"|"manager"
function M.ui_open(name)
  if not M.enabled() then
    return
  end
  open_ui = { name = name, acted = false }
  ui_entry(name).opened = ui_entry(name).opened + 1
  schedule_flush()
end

---A message as a template: what follows "·" or ":", paths, quoted names and
---numbers are dropped, so no file or kunai name is ever kept.
---@param msg string
---@return string
function M.template(msg)
  local t = msg:gsub("%s*·.*$", "")
    :gsub(": .*$", ": …")
    :gsub("^[~/][^%s;,]*", "…")
    :gsub("(%s)[~/][^%s;,]*", "%1…")
    :gsub("'[^']*'", "'…'")
    :gsub("%d+", "N")
  return t
end

local function key(action, fallback)
  local lhs = require("hiraishin.keymaps").lhs_of(action)
  return "`" .. (lhs or fallback) .. "`"
end

local function seal_keys()
  local km = require("hiraishin.keymaps")
  local a, b = km.lhs_of("assign_slot_1"), km.lhs_of("assign_slot_9")
  return "`" .. ((a and b) and (a .. "…" .. b) or ":Hiraishin seal {1-9}") .. "`"
end

---Messages that mean "that didn't work", with the way out.
---@type { pattern: string, exit?: fun(): string }[]
M.DEAD_ENDS = {
  {
    pattern = "^Seal N is empty",
    exit = function()
      return key("seals", ":Hiraishin seals") .. " shows which seals are set"
    end,
  },
  {
    pattern = "^No seals in this list",
    exit = function()
      return seal_keys() .. " or " .. key("seal_free", ":Hiraishin seal") .. " seals a line"
    end,
  },
  {
    pattern = "^No camp yet",
    exit = function()
      return key("camp", ":Hiraishin camp") .. " makes this line your camp"
    end,
  },
  {
    pattern = "^You are at camp",
    exit = function()
      return "after a detour, "
        .. key("go_camp", ":Hiraishin camp go")
        .. " takes you back out; "
        .. key("camp", ":Hiraishin camp")
        .. " moves the camp"
    end,
  },
  {
    pattern = "^No kunai below",
    exit = function()
      return key("next_list", ":Hiraishin next list") .. " continues in the next file"
    end,
  },
  {
    pattern = "^No kunai above",
    exit = function()
      return key("prev_list", ":Hiraishin prev list") .. " continues in the previous file"
    end,
  },
  {
    pattern = "^No kunai in this file",
    exit = function()
      return key("pick", ":Hiraishin pick") .. " finds kunai in any file"
    end,
  },
  {
    pattern = "^No kunai in this list",
    exit = function()
      return key("list", ":Hiraishin list") .. " switches list"
    end,
  },
  {
    pattern = "^No kunai on this line",
    exit = function()
      return key("toggle", ":Hiraishin toggle") .. " places one"
    end,
  },
  {
    pattern = "^No kunai yet",
    exit = function()
      return key("toggle", ":Hiraishin toggle") .. " places one"
    end,
  },
  {
    pattern = "^No kunai '…'",
    exit = function()
      return key("pick", ":Hiraishin pick") .. " finds kunai by name"
    end,
  },
  {
    pattern = "^All nine seals are taken",
    exit = function()
      return key("seals", ":Hiraishin seals") .. ", then d + digit, frees one"
    end,
  },
  {
    pattern = "^File not found",
    exit = function()
      return "`:Hiraishin relocate` moves the kunai to the cursor; `:Hiraishin prune` drops stale ones"
    end,
  },
  {
    pattern = "^No list '…'",
    exit = function()
      return key("list", ":Hiraishin list") .. " shows your lists"
    end,
  },
  { pattern = "^No kunai to send" },
  { pattern = "^Nothing to undo" },
}

---@param template string
---@return { pattern: string, exit?: fun(): string }?
function M.dead_end(template)
  for _, d in ipairs(M.DEAD_ENDS) do
    if template:find(d.pattern) then
      return d
    end
  end
end

---Count a dead end, tied to the action that hit it.
---@param msg string
---@param only_known? boolean count it only when it is a known dead end (routine messages)
function M.friction(msg, only_known)
  if not M.enabled() or type(msg) ~= "string" or msg == "" then
    return
  end
  local tpl = M.template(msg)
  if only_known and not M.dead_end(tpl) then
    return
  end
  local feature = active and active.feature or (last and now_ms() - last.t < 1000 and last.feature) or "other"
  local f = delta.friction[tpl] or { count = 0, last = 0, by = {} }
  delta.friction[tpl] = f
  f.count = f.count + 1
  f.last = os.time()
  f.by[feature] = (f.by[feature] or 0) + 1
  schedule_flush()
end

---Run `fn` as one use of `feature`, counting it once even when it calls a
---command that would count too.
---@param feature string
---@param via string
---@param fn function
function M.as(feature, via, fn)
  if not M.enabled() or active then
    return fn()
  end
  M.record(feature, via)
  active = { feature = feature, via = via }
  local ok, err = pcall(fn)
  active = nil
  if not ok then
    error(err, 0)
  end
end

local function empty()
  return { version = M.VERSION, since = os.time(), actions = {}, friction = {}, uis = {} }
end

local function read()
  local ok, lines = pcall(vim.fn.readfile, M.path())
  if not ok then
    return empty()
  end
  local ok_dec, data = pcall(vim.json.decode, table.concat(lines, "\n"), { luanil = { object = true, array = true } })
  if not ok_dec or type(data) ~= "table" or type(data.actions) ~= "table" then
    return empty()
  end
  data.friction = type(data.friction) == "table" and data.friction or {}
  data.uis = type(data.uis) == "table" and data.uis or {}
  data.since = data.since or os.time()
  data.version = M.VERSION
  return data
end

local function add_map(into, from)
  for k, v in pairs(from or {}) do
    into[k] = (into[k] or 0) + v
  end
end

---The file's counts plus the ones not flushed yet.
---@return table
function M.data()
  local data = read()
  local cutoff = os.date("%Y-%m-%d", os.time() - KEEP_DAYS * 86400)
  for name, a in pairs(delta.actions) do
    local t = data.actions[name] or {}
    t.count = (t.count or 0) + a.count
    t.repeats = (t.repeats or 0) + a.repeats
    t.last = math.max(t.last or 0, a.last)
    t.via = t.via or {}
    add_map(t.via, a.via)
    t.days = t.days or {}
    add_map(t.days, a.days)
    data.actions[name] = t
  end
  for _, t in pairs(data.actions) do
    t.days = t.days or {}
    t.via = t.via or {}
    t.repeats = t.repeats or 0
    for d in pairs(t.days) do
      if d < cutoff then
        t.days[d] = nil
      end
    end
  end
  for tpl, f in pairs(delta.friction) do
    local t = data.friction[tpl] or { count = 0, last = 0 }
    t.count = t.count + f.count
    t.last = math.max(t.last or 0, f.last)
    t.by = t.by or {}
    add_map(t.by, f.by)
    data.friction[tpl] = t
  end
  for name, u in pairs(delta.uis) do
    local t = data.uis[name] or { opened = 0, acted = 0 }
    t.opened = t.opened + u.opened
    t.acted = t.acted + u.acted
    data.uis[name] = t
  end
  return data
end

---Write the pending counts to the file.
function M.flush()
  if not dirty then
    return
  end
  local data = M.data()
  vim.fn.mkdir(config.options.storage.dir, "p")
  local tmp = M.path() .. ".tmp"
  if vim.fn.writefile({ vim.json.encode(data) }, tmp) == 0 and vim.uv.fs_rename(tmp, M.path()) then
    delta = fresh()
    dirty = false
  end
end

---Forget everything.
function M.reset()
  delta = fresh()
  dirty = false
  last, open_ui = nil, nil
  os.remove(M.path())
end

-- report -------------------------------------------------------------------

---Key that reaches a feature, as shown in the report ("g1…g9", "g0 <BS>").
---@param f hiraishin.Feature
---@return string?
function M.key_of(f)
  local km = require("hiraishin.keymaps")
  if f.key then
    return f.key()
  elseif f.group then
    local a, b = km.lhs_of(f.group .. "_1"), km.lhs_of(f.group .. "_9")
    return (a and b) and (a .. "…" .. b) or a
  elseif f.actions then
    local keys = {}
    for _, action in ipairs(f.actions) do
      table.insert(keys, km.lhs_of(action))
    end
    return #keys > 0 and table.concat(keys, " ") or nil
  elseif f.action then
    return km.lhs_of(f.action)
  elseif f.id == "camp_back" then
    return M.key_of(M.by_id.go_camp)
  end
end

local function ago(ts)
  if not ts or ts == 0 then
    return "never"
  end
  local days = math.floor((os.time() - ts) / 86400)
  if days <= 0 then
    return "today"
  elseif days == 1 then
    return "yesterday"
  end
  return days .. " days ago"
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

local function fit(s, w)
  if width(s) > w then
    s = vim.fn.strcharpart(s, 0, w - 1) .. "…"
    while width(s) > w do
      s = vim.fn.strcharpart(s, 0, vim.fn.strchars(s) - 2) .. "…"
    end
  end
  return s .. string.rep(" ", w - width(s))
end

local function rfit(s, w)
  return string.rep(" ", math.max(0, w - width(s))) .. s
end

local EIGHTHS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }

---A horizontal bar of `cells` cells for `v` out of `max`.
function M.bar(v, max, cells)
  if v <= 0 or max <= 0 then
    return string.rep(" ", cells)
  end
  local exact = v / max * cells
  local full = math.floor(exact)
  local frac = math.floor((exact - full) * 8)
  local s = string.rep("█", full)
  local used = full
  if frac > 0 and full < cells then
    s = s .. EIGHTHS[frac]
    used = used + 1
  elseif full == 0 then
    s, used = "▏", 1
  end
  return s .. string.rep(" ", cells - used)
end

local LEVELS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

---Daily uses over the last `n` days, oldest first, as a sparkline ("·" = none).
function M.spark(days, n)
  local counts, max = {}, 0
  for i = n - 1, 0, -1 do
    local c = days[os.date("%Y-%m-%d", os.time() - i * 86400)] or 0
    table.insert(counts, c)
    max = math.max(max, c)
  end
  local out = {}
  for _, c in ipairs(counts) do
    if c == 0 then
      table.insert(out, "·")
    else
      table.insert(out, LEVELS[math.max(1, math.ceil(c / max * 8))])
    end
  end
  return table.concat(out)
end

local function uses_in(a, range)
  if range == "all" then
    return a.count or 0
  end
  local cutoff = os.date("%Y-%m-%d", os.time() - 29 * 86400)
  local n = 0
  for d, c in pairs(a.days or {}) do
    if d >= cutoff then
      n = n + c
    end
  end
  return n
end

local function label_of(id)
  local f = M.by_id[id]
  return f and f.label or id
end

---What the numbers suggest doing, most important first.
---@param data table from M.data()
---@return { text: string, feature?: string, weight: number }[]
function M.suggestions(data)
  local out = {}
  local function add(weight, feature, text)
    table.insert(out, { weight = weight, feature = feature, text = text })
  end
  local km = require("hiraishin.keymaps")
  local span_days = math.floor((os.time() - (data.since or os.time())) / 86400)

  for _, f in ipairs(M.CATALOG) do
    local a = data.actions[f.id]
    local count = a and a.count or 0
    -- a key for something you keep typing as a command
    local cmd = a and a.via.cmd or 0
    if f.cmd and cmd >= 3 and cmd / count >= 0.5 then
      local k = M.key_of(f)
      if k then
        add(cmd, f.id, string.format("You ran `%s` %d times by command; `%s` does the same.", f.cmd, cmd, k))
      elseif f.action or f.actions then
        add(
          cmd / 2,
          f.id,
          string.format(
            'You ran `%s` %d times by command; a key would be quicker: `keymaps = { %s = "<key>" }`.',
            f.cmd,
            cmd,
            f.action or f.actions[1]
          )
        )
      end
    end
    -- one of two keys for the same thing never used
    if f.actions and count >= 10 then
      local parts, unused = {}, {}
      for _, action in ipairs(f.actions) do
        local lhs = km.lhs_of(action)
        if lhs then
          local n = a.via["key:" .. lhs] or 0
          table.insert(parts, lhs .. " " .. n)
          if n == 0 then
            table.insert(unused, { action = action, lhs = lhs })
          end
        end
      end
      if #unused > 0 and #unused < #parts then
        local u = unused[1]
        add(
          count / 2,
          f.id,
          string.format(
            "%s: %s. `keymaps = { %s = false }` gives `%s` back to Vim.",
            f.label,
            table.concat(parts, ", "),
            u.action,
            u.lhs
          )
        )
      end
    end
    -- a key that takes a Vim command away, for a feature you don't use
    if SHADOWS[f.id] and count == 0 and span_days >= 14 then
      local keys, offs = {}, {}
      for _, s in ipairs(SHADOWS[f.id]) do
        local lhs = km.lhs_of(s.action)
        if lhs then
          table.insert(keys, string.format("`%s` (%s)", lhs, s.what))
          table.insert(offs, s.action .. " = false")
        end
      end
      if #keys > 0 then
        add(
          2,
          f.id,
          string.format(
            "%s went unused for %d days; `keymaps = { %s }` gives Vim back %s.",
            f.label,
            span_days,
            table.concat(offs, ", "),
            table.concat(keys, " and ")
          )
        )
      end
    end
    -- the same action again right away, at the same spot
    local repeats = a and a.repeats or 0
    if repeats >= 3 and repeats / count >= 0.2 then
      add(
        repeats,
        f.id,
        string.format(
          "%s ran again at the same spot within 2 s %d of %d times: the first try often didn't do what you expected. `:messages` shows what it said.",
          f.label,
          repeats,
          count
        )
      )
    end
  end

  -- dead ends with a way out
  for tpl, fr in pairs(data.friction or {}) do
    local d = M.dead_end(tpl)
    if d and d.exit and fr.count >= 3 then
      local top, top_n = nil, 0
      for feature, n in pairs(fr.by or {}) do
        if n > top_n and feature ~= "other" then
          top, top_n = feature, n
        end
      end
      local from = ""
      if top then
        local k = M.by_id[top] and M.key_of(M.by_id[top])
        from = string.format(", mostly from %s%s", label_of(top), k and (" (`" .. k .. "`)") or "")
      end
      add(
        fr.count,
        top,
        string.format('"%s" %d times%s. %s.', tpl, fr.count, from, (d.exit():gsub("^%l", string.upper)))
      )
    end
  end

  -- windows opened and left without doing anything
  local ui_advice = {
    picker = function()
      return "If you were only checking what's there, "
        .. key("seals", ":Hiraishin seals")
        .. " is lighter; if it was the wrong list, `"
        .. config.options.picker.keys.list
        .. "` switches it."
    end,
    seal_menu = function()
      return "If you only look, the statusline lists your seals (`#1 2 4`) without opening anything."
    end,
    manager = function()
      return "To browse rather than edit, " .. key("pick", ":Hiraishin pick") .. " shows kunai with a preview."
    end,
  }
  local ui_feature = { picker = "pick", seal_menu = "seals", manager = "manager" }
  for name, u in pairs(data.uis or {}) do
    local left = u.opened - u.acted
    if u.opened >= 5 and left / u.opened >= 0.4 then
      add(
        left,
        ui_feature[name],
        string.format(
          "You left the %s without doing anything %d of %d times. %s",
          (M.UI_LABELS[name] or name):lower(),
          left,
          u.opened,
          ui_advice[name] and ui_advice[name]() or ""
        )
      )
    end
  end

  table.sort(out, function(x, y)
    return x.weight > y.weight
  end)
  return out
end

---@class hiraishin.StatsView
---@field lines string[]
---@field hls { [1]: integer, [2]: integer, [3]: integer, [4]: string }[] row, start col, end col, group (0-based)
---@field rows table<integer, { feature?: string, items?: { s: integer, e: integer, feature: string }[] }> 1-based

---The report, laid out.
---@param opts? { range?: "30d"|"all", unused?: boolean, width?: integer }
---@return hiraishin.StatsView
function M.render(opts)
  opts = opts or {}
  local range = opts.range or "30d"
  local show_unused = opts.unused ~= false
  local W = opts.width or 92
  local data = M.data()
  local view = { lines = {}, hls = {}, rows = {} }

  local function line(segs, meta)
    local text = ""
    for _, s in ipairs(segs) do
      if s[2] and #s[1] > 0 then
        table.insert(view.hls, { #view.lines, #text, #text + #s[1], s[2] })
      end
      text = text .. s[1]
    end
    table.insert(view.lines, text)
    if meta then
      view.rows[#view.lines] = meta
    end
  end
  local function blank()
    line({ { "" } })
  end
  ---Wrapped paragraph after a fixed prefix.
  local function para(prefix, prefix_hl, text, meta)
    local avail = W - width(prefix)
    local words, cur, first = vim.split(text, " ", { plain = true }), "", true
    local function emit()
      line({ { first and prefix or string.rep(" ", width(prefix)), first and prefix_hl or nil }, { cur } }, meta)
      first, cur = false, ""
    end
    for _, w in ipairs(words) do
      if cur ~= "" and width(cur) + 1 + width(w) > avail then
        emit()
      end
      cur = cur == "" and w or (cur .. " " .. w)
    end
    emit()
  end

  local total = 0
  for _, a in pairs(data.actions) do
    total = total + uses_in(a, range)
  end
  local range_label = range == "all" and ("since " .. os.date("%Y-%m-%d", data.since)) or "last 30 days"
  line({ { "Hiraishin usage · " .. range_label .. " · " .. total .. (total == 1 and " use" or " uses"), "Title" } })
  line({ { "Kept only on this machine: " .. vim.fn.fnamemodify(M.path(), ":~"), "Comment" } })
  if not M.enabled() then
    line({ { "Counting is off (stats = false): nothing new is added", "DiagnosticWarn" } })
  end

  -- used features, by area
  local areas, area_total, max = {}, {}, 0
  for id, a in pairs(data.actions) do
    local f = M.by_id[id]
    local area = f and f.area or "Other"
    local n = uses_in(a, range)
    areas[area] = areas[area] or {}
    table.insert(areas[area], { id = id, a = a, n = n, f = f })
    area_total[area] = (area_total[area] or 0) + n
    max = math.max(max, n)
  end
  local order = vim.list_extend(vim.deepcopy(M.AREAS), { "Other" })
  table.sort(order, function(x, y)
    local tx, ty = area_total[x] or -1, area_total[y] or -1
    if tx ~= ty then
      return tx > ty
    end
    return vim.fn.index(M.AREAS, x) < vim.fn.index(M.AREAS, y)
  end)

  blank()
  if vim.tbl_isempty(data.actions) then
    line({ { "Nothing counted yet. Use hiraishin for a while, then come back.", "Comment" } })
  else
    local count_head = range == "all" and "All time" or "30 days"
    line({
      {
        fit("", 26)
          .. fit("Key", 13)
          .. fit("", 13)
          .. rfit(count_head, 8)
          .. "  "
          .. fit("Last 14 days", 16)
          .. "Ways",
        "Comment",
      },
    })
    for _, area in ipairs(order) do
      local rows = areas[area]
      if rows then
        table.sort(rows, function(x, y)
          if x.n ~= y.n then
            return x.n > y.n
          end
          return (x.a.count or 0) > (y.a.count or 0)
        end)
        line({ { area, "HiraishinManagerHeader" } })
        for _, r in ipairs(rows) do
          local f = r.f
          local k = f and M.key_of(f) or ""
          local ways = {}
          local via, group_n = {}, 0
          local km = require("hiraishin.keymaps")
          for w, n in pairs(r.a.via) do
            local lhs = w:gsub("^key:", "")
            local in_group = false
            if f and f.group then
              for d = 1, 9 do
                if km.lhs_of(f.group .. "_" .. d) == lhs then
                  in_group = true
                end
              end
            end
            if in_group then
              group_n = group_n + n
            else
              table.insert(via, { lhs, n })
            end
          end
          if group_n > 0 then
            table.insert(via, { k, group_n })
          end
          if #via > 1 then
            table.sort(via, function(x, y)
              return x[2] > y[2]
            end)
            for i = 1, math.min(3, #via) do
              table.insert(ways, via[i][1] .. " " .. via[i][2])
            end
          end
          line({
            { "  " .. fit(f and f.label or r.id, 24) },
            { fit(k or "", 13), "HiraishinStatsKey" },
            { M.bar(r.n, max, 12) .. " ", "HiraishinStatsBar" },
            { rfit(tostring(r.n), 8), r.n == 0 and "Comment" or nil },
            { "  " },
            { M.spark(r.a.days, 14), "HiraishinStatsSpark" },
            { "  " .. table.concat(ways, " · "), "Comment" },
          }, { feature = r.id })
        end
      end
    end
  end

  -- never used
  local unused, n_unused = {}, 0
  for _, f in ipairs(M.CATALOG) do
    if not data.actions[f.id] then
      unused[f.area] = unused[f.area] or {}
      table.insert(unused[f.area], f)
      n_unused = n_unused + 1
    end
  end
  if n_unused > 0 then
    blank()
    if not show_unused then
      line({
        { "Never used: " .. n_unused .. " features", "HiraishinManagerHeader" },
        { "  · u shows them", "Comment" },
      })
    else
      line({ { "Never used", "HiraishinManagerHeader" } })
      for _, area in ipairs(M.AREAS) do
        local list = unused[area]
        if list then
          local prefix = "  " .. fit(area, 14)
          local segs, items, cur_w = { { prefix, "Comment" } }, {}, width(prefix)
          local function flush_line()
            line(segs, { items = items })
            segs, items, cur_w = { { string.rep(" ", width(prefix)) } }, {}, width(prefix)
          end
          for _, f in ipairs(list) do
            local k = M.key_of(f)
            local text = f.label .. (k and (" " .. k) or "")
            local sep = #items > 0 and " · " or ""
            if #items > 0 and cur_w + width(sep) + width(text) > W then
              flush_line()
              sep = ""
            end
            table.insert(segs, { sep, "Comment" })
            local s = 0
            for _, seg in ipairs(segs) do
              s = s + #seg[1]
            end
            table.insert(segs, { f.label })
            if k then
              table.insert(segs, { " " .. k, "HiraishinStatsKey" })
            end
            table.insert(items, { s = s, e = s + #text, feature = f.id })
            cur_w = cur_w + width(sep) + width(text)
          end
          flush_line()
        end
      end
    end
  end

  -- suggestions
  local sugg = M.suggestions(data)
  if #sugg > 0 then
    blank()
    line({ { "Suggestions", "HiraishinManagerHeader" } })
    for i = 1, math.min(6, #sugg) do
      para("  • ", "DiagnosticOk", sugg[i].text, { feature = sugg[i].feature })
    end
  end

  -- dead ends
  local fr = {}
  for tpl, f in pairs(data.friction or {}) do
    table.insert(fr, { tpl = tpl, f = f })
  end
  table.sort(fr, function(x, y)
    return x.f.count > y.f.count
  end)
  if #fr > 0 then
    blank()
    line({ { "Dead ends", "HiraishinManagerHeader" }, { "  messages that meant it didn't work", "Comment" } })
    for i = 1, math.min(12, #fr) do
      local e = fr[i]
      local by = {}
      for feature, n in pairs(e.f.by or {}) do
        table.insert(by, { feature, n })
      end
      table.sort(by, function(x, y)
        return x[2] > y[2]
      end)
      local from = {}
      for j = 1, math.min(2, #by) do
        table.insert(from, label_of(by[j][1]) .. " " .. by[j][2])
      end
      local top = by[1] and by[1][1]
      line({
        { rfit(tostring(e.f.count), 6) .. "  ", "DiagnosticWarn" },
        { fit(e.tpl, 32) .. " " },
        { fit(#from > 0 and ("from " .. table.concat(from, " · ")) or "", 36) .. " ", "Comment" },
        { ago(e.f.last), "Comment" },
      }, { feature = top ~= "other" and top or nil })
    end
  end

  -- retries and windows left without acting
  local retries = {}
  for id, a in pairs(data.actions) do
    if (a.repeats or 0) > 0 then
      table.insert(retries, { id = id, a = a })
    end
  end
  local left = {}
  for name, u in pairs(data.uis or {}) do
    if u.opened > 0 then
      table.insert(left, { name = name, u = u })
    end
  end
  if #retries > 0 or #left > 0 then
    blank()
    line({ { "Hesitation", "HiraishinManagerHeader" }, { "  ran again right away, or opened and left", "Comment" } })
    table.sort(retries, function(x, y)
      return x.a.repeats > y.a.repeats
    end)
    for i, r in ipairs(retries) do
      if i > 6 then
        break
      end
      line({
        { "  " .. fit(label_of(r.id), 24) },
        { string.format("ran again at the same spot %d of %d times", r.a.repeats, r.a.count), "Comment" },
      }, { feature = r.id })
    end
    table.sort(left, function(x, y)
      return x.name < y.name
    end)
    local feature_of_ui = { picker = "pick", seal_menu = "seals", manager = "manager" }
    for _, l in ipairs(left) do
      local gone = l.u.opened - l.u.acted
      line({
        { "  " .. fit(M.UI_LABELS[l.name] or l.name, 24) },
        {
          string.format(
            "opened %d · left without acting %d (%d%%)",
            l.u.opened,
            gone,
            math.floor(gone / l.u.opened * 100 + 0.5)
          ),
          gone / l.u.opened >= 0.4 and "DiagnosticWarn" or "Comment",
        },
      }, { feature = feature_of_ui[l.name] })
    end
  end

  blank()
  line({
    {
      string.format(
        "<CR> help · t %s · u %s never used · q close",
        range == "all" and "last 30 days" or "all time",
        show_unused and "hide" or "show"
      ),
      "Comment",
    },
  })
  return view
end

---The report as plain lines.
---@param opts? { range?: "30d"|"all", unused?: boolean, width?: integer }
---@return string[]
function M.report(opts)
  return M.render(opts).lines
end

---@type { buf: integer, win: integer, range: string, unused: boolean }?
local shown

---Show the report in a float: <CR> opens help for the feature under the
---cursor, t switches between 30 days and all time, u folds the unused
---features, q closes.
---@param opts? { range?: "30d"|"all", unused?: boolean }
---@return integer win
function M.show(opts)
  opts = opts or {}
  if shown and vim.api.nvim_win_is_valid(shown.win) then
    vim.api.nvim_win_close(shown.win, true)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hiraishin_stats"
  local W = math.min(vim.o.columns - 4, 96)
  local state = { buf = buf, range = opts.range or "30d", unused = opts.unused ~= false }
  shown = state
  local ns = vim.api.nvim_create_namespace("hiraishin_stats")
  local view

  local function draw()
    view = M.render({ range = state.range, unused = state.unused, width = W - 2 })
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, view.lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(view.hls) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
    end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local height = math.min(vim.o.lines - 6, #view.lines)
      vim.api.nvim_win_set_config(state.win, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - W) / 2),
        width = W,
        height = height,
      })
      local cur = vim.api.nvim_win_get_cursor(state.win)
      vim.api.nvim_win_set_cursor(state.win, { math.min(cur[1], #view.lines), 0 })
    end
  end

  draw()
  local height = math.min(vim.o.lines - 6, #view.lines)
  state.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - W) / 2),
    width = W,
    height = height,
    style = "minimal",
    border = config.options.manager.border,
    title = " Hiraishin stats ",
    title_pos = "center",
  })
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = true

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  local function close()
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    if shown == state then
      shown = nil
    end
  end
  map("q", close)
  map("<Esc>", close)
  map("t", function()
    state.range = state.range == "all" and "30d" or "all"
    draw()
  end)
  map("u", function()
    state.unused = not state.unused
    draw()
  end)
  map("<CR>", function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local meta = view.rows[pos[1]]
    if not meta then
      return
    end
    local feature = meta.feature
    if meta.items then
      for _, it in ipairs(meta.items) do
        if pos[2] >= it.s and pos[2] < it.e then
          feature = it.feature
        end
      end
      feature = feature or (meta.items[1] and meta.items[1].feature)
    end
    local f = feature and M.by_id[feature]
    close()
    local ok = pcall(vim.cmd.help, f and f.help or ":Hiraishin-stats")
    if not ok then
      pcall(vim.cmd.help, "hiraishin")
    end
  end)
  return state.win
end

return M
