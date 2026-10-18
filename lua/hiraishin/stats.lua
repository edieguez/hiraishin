---Local usage stats (on by default, `stats = false` turns them off): which features you use, how you
---reach them, and the dead ends you hit, so you can triage the plugin. Only
---feature names, counts, days and message templates are kept, in one JSON
---file under `storage.dir`. Nothing leaves your machine.
local config = require("hiraishin.config")

local M = {}

M.VERSION = 1
local KEEP_DAYS = 90

-- counts since the last flush, added to the file on flush (several Neovim
-- instances can share the file)
local delta = { actions = {}, friction = {} }
local dirty = false
local timer ---@type uv.uv_timer_t?
-- set while a keymap runs, so the command it calls is not counted twice
local active ---@type { feature: string, via: string }?

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

---Count one use of a feature.
---@param feature string e.g. "seal", "go_camp", "pick"
---@param via string how it was reached: "key:<lhs>", "cmd", "picker", "menu", "manager"
function M.record(feature, via)
  if not M.enabled() then
    return
  end
  local a = delta.actions[feature]
  if not a then
    a = { count = 0, via = {}, days = {}, last = 0 }
    delta.actions[feature] = a
  end
  a.count = a.count + 1
  a.via[via] = (a.via[via] or 0) + 1
  local d = today()
  a.days[d] = (a.days[d] or 0) + 1
  a.last = os.time()
  schedule_flush()
end

---A message as a template: quoted names and numbers stripped.
---@param msg string
---@return string
function M.template(msg)
  local t = msg:gsub("'[^']*'", "'…'"):gsub("%d+", "N"):gsub("%s*·.*$", "")
  return t
end

---Count a dead end (a warning, or "nothing to do here" feedback).
---@param msg string
function M.friction(msg)
  if not M.enabled() or type(msg) ~= "string" or msg == "" then
    return
  end
  local key = M.template(msg)
  local f = delta.friction[key] or { count = 0, last = 0 }
  delta.friction[key] = f
  f.count = f.count + 1
  f.last = os.time()
  schedule_flush()
end

---Run `fn` as the use of a keymap action, counting it once.
---@param feature string
---@param via string
---@param fn function
function M.as(feature, via, fn)
  if not M.enabled() then
    return fn()
  end
  M.record(feature, via)
  local outer = active
  active = { feature = feature, via = via }
  local ok, err = pcall(fn)
  active = outer
  if not ok then
    error(err, 0)
  end
end

---Count a command, unless a keymap already counted it.
---@param feature string
function M.command(feature)
  if not active then
    M.record(feature, "cmd")
  end
end

local function empty()
  return { version = M.VERSION, since = os.time(), actions = {}, friction = {} }
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
  return data
end

---The file's counts plus the ones not flushed yet.
---@return table
function M.data()
  local data = read()
  local cutoff = os.date("%Y-%m-%d", os.time() - KEEP_DAYS * 86400)
  for name, a in pairs(delta.actions) do
    local t = data.actions[name] or { count = 0, via = {}, days = {}, last = 0 }
    t.count = (t.count or 0) + a.count
    t.last = math.max(t.last or 0, a.last)
    t.via = t.via or {}
    for k, v in pairs(a.via) do
      t.via[k] = (t.via[k] or 0) + v
    end
    t.days = t.days or {}
    for k, v in pairs(a.days) do
      t.days[k] = (t.days[k] or 0) + v
    end
    data.actions[name] = t
  end
  for _, t in pairs(data.actions) do
    for d in pairs(t.days or {}) do
      if d < cutoff then
        t.days[d] = nil
      end
    end
  end
  for key, f in pairs(delta.friction) do
    local t = data.friction[key] or { count = 0, last = 0 }
    t.count = t.count + f.count
    t.last = math.max(t.last or 0, f.last)
    data.friction[key] = t
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
    delta = { actions = {}, friction = {} }
    dirty = false
  end
end

---Forget everything.
function M.reset()
  delta = { actions = {}, friction = {} }
  dirty = false
  os.remove(M.path())
end

-- features the report lists even when never used
M.FEATURES = {
  "toggle",
  "add",
  "note",
  "delete",
  "undo",
  "seal",
  "seal_free",
  "seal_clear",
  "jump",
  "seals",
  "next_seal",
  "prev_seal",
  "camp",
  "go_camp",
  "camp_back",
  "camp_clear",
  "next",
  "prev",
  "next_list",
  "prev_list",
  "pick",
  "pick_buffer",
  "pick_all",
  "pick_global",
  "global",
  "manager",
  "manager_apply",
  "list",
  "quickfix",
  "loclist",
  "relocate",
  "prune",
  "gc",
  "scope",
  "import",
  "picker_jump",
  "picker_delete",
  "picker_rename",
  "picker_note",
  "picker_quickfix",
  "picker_list",
  "menu_go",
  "menu_clear",
}

local function ago(ts)
  if not ts or ts == 0 then
    return "never"
  end
  local days = math.floor((os.time() - ts) / 86400)
  if days == 0 then
    return "today"
  elseif days == 1 then
    return "yesterday"
  end
  return days .. " days ago"
end

---Report lines: features by use (last 30 days and all time), how they were
---reached, features never used, and the most common dead ends.
---@return string[]
function M.report()
  local data = M.data()
  local cutoff = os.date("%Y-%m-%d", os.time() - 30 * 86400)
  local rows, total = {}, 0
  for name, a in pairs(data.actions) do
    local recent = 0
    for d, n in pairs(a.days or {}) do
      if d >= cutoff then
        recent = recent + n
      end
    end
    local vias = {}
    for via, n in pairs(a.via or {}) do
      table.insert(vias, { via, n })
    end
    table.sort(vias, function(x, y)
      return x[2] > y[2]
    end)
    local how = table.concat(
      vim.tbl_map(function(v)
        return v[1]:gsub("^key:", "") .. " " .. v[2]
      end, vim.list_slice(vias, 1, 3)),
      " · "
    )
    table.insert(rows, { name = name, recent = recent, count = a.count or 0, last = a.last, how = how })
    total = total + (a.count or 0)
  end
  table.sort(rows, function(a, b)
    if a.recent ~= b.recent then
      return a.recent > b.recent
    end
    return a.count > b.count
  end)
  local lines = {
    "Hiraishin usage since " .. os.date("%Y-%m-%d", data.since or os.time()) .. " · " .. total .. " uses",
    "Kept locally in " .. vim.fn.fnamemodify(M.path(), ":~") .. " · :Hiraishin stats reset forgets it",
    "",
  }
  if not M.enabled() then
    table.insert(lines, 3, "Stats are off (stats = false in your config): nothing new is counted")
  end
  local fmt = "%-16s %8s %9s  %-11s %s"
  table.insert(lines, fmt:format("Feature", "30 days", "All time", "Last used", "Reached with"))
  for _, r in ipairs(rows) do
    table.insert(lines, fmt:format(r.name, r.recent, r.count, ago(r.last), r.how))
  end
  local unused = {}
  for _, f in ipairs(M.FEATURES) do
    if not data.actions[f] then
      table.insert(unused, f)
    end
  end
  if #unused > 0 then
    table.insert(lines, "")
    table.insert(lines, "Never used:")
    local line = " "
    for _, f in ipairs(unused) do
      if #line + #f > 76 then
        table.insert(lines, line)
        line = " "
      end
      line = line .. " " .. f
    end
    table.insert(lines, line)
  end
  local friction = {}
  for msg, f in pairs(data.friction or {}) do
    table.insert(friction, { msg = msg, count = f.count, last = f.last })
  end
  table.sort(friction, function(a, b)
    return a.count > b.count
  end)
  if #friction > 0 then
    table.insert(lines, "")
    table.insert(lines, "Dead ends (warnings and nothing-to-do messages):")
    for _, f in ipairs(vim.list_slice(friction, 1, 15)) do
      table.insert(lines, ("%6d  %s  (%s)"):format(f.count, f.msg, ago(f.last)))
    end
  end
  return lines
end

---Show the report in a float (q closes).
function M.show()
  local lines = M.report()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "hiraishin_stats"
  local width = math.min(vim.o.columns - 4, 90)
  local height = math.min(vim.o.lines - 6, #lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = config.options.manager.border,
    title = " Hiraishin stats ",
    title_pos = "center",
  })
  local ns = vim.api.nvim_create_namespace("hiraishin_stats")
  for i, l in ipairs(lines) do
    local group = i == 1 and "Title"
      or ((l:match("^Feature ") or l:match("^Never used") or l:match("^Dead ends")) and "HiraishinManagerHeader")
      or nil
    if group then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #l, hl_group = group })
    end
  end
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true })
  end
  return win
end

return M
