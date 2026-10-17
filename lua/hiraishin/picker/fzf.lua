---fzf-lua backend.
local M = {}

function M.available()
  return (pcall(require, "fzf-lua"))
end

---"<C-v>" -> "ctrl-v", "<M-d>" / "<A-d>" -> "alt-d"; nil when fzf has no name for it.
---@param lhs string
---@return string?
function M.fzf_key(lhs)
  local mod, key = lhs:match("^<([CcMmAa])%-(.)>$")
  if not mod then
    return nil
  end
  return (mod:lower() == "c" and "ctrl-" or "alt-") .. key:lower()
end

---Lines in the "path:line:col:text" shape fzf-lua's builtin previewer reads,
---plus a lookup back to the entries.
---@param entries hiraishin.Entry[]
---@return string[] lines, table<string, hiraishin.Entry> lookup
function M.lines(entries)
  local lines, lookup = {}, {}
  for _, e in ipairs(entries) do
    local tag = (e.slot and ("[" .. e.slot .. "]") or "[ ]") .. " " .. (e.bookmark.name or "—")
    local rest = e.stale and "(stale)" or vim.trim(e.text)
    if e.bookmark.note then
      rest = rest .. "  ✎ " .. e.bookmark.note:gsub("\n", " ⏎ ")
    end
    local line = string.format("%s:%d:%d: %s  %s", e.file, e.line, e.col + 1, tag, rest)
    table.insert(lines, line)
    lookup[line] = e
  end
  return lines, lookup
end

---@param p table see hiraishin.picker.open
function M.open(p)
  local fzf = require("fzf-lua")
  local core = require("hiraishin.picker")
  local lookup = {}

  local function contents(cb)
    local lines
    lines, lookup = M.lines(p.refresh())
    for _, l in ipairs(lines) do
      cb(l)
    end
    cb(nil)
  end

  local function entry(selected)
    return selected and selected[1] and lookup[selected[1]] or nil
  end
  local function deferred(fn)
    return function(selected)
      local e = entry(selected)
      if e then
        vim.schedule(function()
          fn(e)
        end)
      end
    end
  end

  local actions = {
    ["enter"] = deferred(function(e)
      core.actions.jump(p.ctx, e)
    end),
  }
  local handlers = {
    vsplit = deferred(function(e)
      core.actions.jump(p.ctx, e, "vsplit")
    end),
    split = deferred(function(e)
      core.actions.jump(p.ctx, e, "split")
    end),
    tab = deferred(function(e)
      core.actions.jump(p.ctx, e, "tab")
    end),
    rename = deferred(function(e)
      core.actions.rename(p.ctx, e, p.reopen)
    end),
    note = deferred(function(e)
      core.actions.note(p.ctx, e)
    end),
    quickfix = function(selected)
      local es = {}
      for _, s in ipairs(selected or {}) do
        if lookup[s] then
          table.insert(es, lookup[s])
        end
      end
      if #es <= 1 then
        es = p.refresh() -- nothing multi-selected: send the whole list
      end
      vim.schedule(function()
        core.actions.quickfix(es)
      end)
    end,
  }
  for name, fn in pairs(handlers) do
    local key = p.keys[name] and M.fzf_key(p.keys[name])
    if key then
      actions[key] = fn
    end
  end
  local del_key = p.keys.delete and M.fzf_key(p.keys.delete)
  if del_key then
    actions[del_key] = {
      fn = function(selected)
        local e = entry(selected)
        if e then
          core.actions.delete(p.ctx, e)
        end
      end,
      reload = true,
    }
  end

  return fzf.fzf_exec(contents, {
    prompt = p.title .. "> ",
    cwd = p.ctx.root,
    previewer = "builtin",
    actions = actions,
    fzf_opts = { ["--multi"] = true },
  })
end

return M
