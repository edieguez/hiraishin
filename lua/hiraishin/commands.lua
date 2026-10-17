local util = require("hiraishin.util")

local M = {}

local function warn(msg)
  util.notify(msg, vim.log.levels.WARN)
end

local function bookmark_names()
  local names = {}
  for _, bm in ipairs(require("hiraishin").list()) do
    if bm.name then
      table.insert(names, bm.name)
    end
  end
  table.sort(names)
  return names
end

---@type table<string, { run: fun(args: string[], bang: boolean), complete?: fun(): string[] }>
M.subcommands = {
  toggle = {
    run = function()
      local h = require("hiraishin")
      local current = h.at_cursor()
      if current and (current.name or current.note) and require("hiraishin.config").options.confirm_remove_named then
        local label = current.name and ("'" .. current.name .. "'") or "with a note"
        if vim.fn.confirm("Remove kunai " .. label .. "?", "&Yes\n&No", 2) ~= 1 then
          return
        end
      end
      local _, _, err = h.toggle()
      if err then
        warn(err)
      end
    end,
  },
  add = {
    run = function(args, bang)
      local h = require("hiraishin")
      local function add(name)
        local _, err = h.add({ name = name })
        if err and err ~= "exists" then
          warn(err)
        end
      end
      if #args > 0 then
        add(table.concat(args, " "))
      elseif bang then
        local current = h.at_cursor()
        local default = current and current.name or require("hiraishin.names").suggest() or ""
        vim.ui.input({ prompt = "Kunai name: ", default = default }, function(input)
          if input ~= nil then
            add(input)
          end
        end)
      else
        add(nil)
      end
    end,
  },
  delete = {
    run = function(args)
      local h = require("hiraishin")
      local key = table.concat(args, " ")
      if key == "" then
        local bm = h.at_cursor()
        if not bm then
          return warn("no kunai on this line")
        end
        key = bm.id
      end
      local _, err = h.remove(key, { reason = "command" })
      if err then
        warn(err)
      end
    end,
    complete = bookmark_names,
  },
  jump = {
    -- :Hiraishin jump {name|1-9} [vsplit|split|tab]
    run = function(args)
      if #args == 0 then
        return warn("usage: :Hiraishin jump {name|1-9} [vsplit|split|tab]")
      end
      local split
      if #args > 1 and vim.tbl_contains({ "vsplit", "split", "tab" }, args[#args]) then
        split = table.remove(args)
      end
      local _, err = require("hiraishin").jump(table.concat(args, " "), { split = split })
      if err then
        warn(err)
      end
    end,
    complete = function()
      local out = bookmark_names()
      for i = 1, 9 do
        table.insert(out, tostring(i))
      end
      return out
    end,
  },
  next = {
    -- :Hiraishin next [list]
    run = function(args)
      local _, err = require("hiraishin").next({ scope = args[1] == "list" and "list" or "buffer" })
      if err then
        warn(err)
      end
    end,
    complete = function()
      return { "list" }
    end,
  },
  prev = {
    run = function(args)
      local _, err = require("hiraishin").prev({ scope = args[1] == "list" and "list" or "buffer" })
      if err then
        warn(err)
      end
    end,
    complete = function()
      return { "list" }
    end,
  },
  seal = {
    -- :Hiraishin seal {1-9} | :Hiraishin seal clear
    run = function(args)
      local h = require("hiraishin")
      if args[1] == "clear" then
        local bm = h.at_cursor()
        if not bm then
          return warn("no kunai on this line")
        end
        h.update(bm.id, { slot = false })
        return
      end
      local _, err = h.seal(tonumber(args[1]))
      if err then
        warn(err)
      end
    end,
    complete = function()
      return { "1", "2", "3", "4", "5", "6", "7", "8", "9", "clear" }
    end,
  },
  note = {
    run = function()
      require("hiraishin").note()
    end,
  },
  pick = {
    -- :Hiraishin pick [buffer|all]
    run = function(args)
      local filter = args[1]
      if filter and filter ~= "buffer" and filter ~= "all" then
        return warn("usage: :Hiraishin pick [buffer|all]")
      end
      require("hiraishin").pick({ filter = filter })
    end,
    complete = function()
      return { "buffer", "all" }
    end,
  },
  quickfix = {
    -- :Hiraishin quickfix [all]
    run = function(args)
      if require("hiraishin").to_quickfix({ all = args[1] == "all" }) == 0 then
        util.notify("no kunai to send")
      end
    end,
    complete = function()
      return { "all" }
    end,
  },
  loclist = {
    run = function(args)
      if require("hiraishin").to_quickfix({ loclist = true, all = args[1] == "all" }) == 0 then
        util.notify("no kunai to send")
      end
    end,
    complete = function()
      return { "all" }
    end,
  },
  relocate = {
    run = function(args)
      local h = require("hiraishin")
      local function relocate(bm)
        local _, err = h.relocate(bm.id)
        if err then
          warn(err)
        end
      end
      if #args > 0 then
        local _, err = h.relocate(table.concat(args, " "))
        if err then
          warn(err)
        end
        return
      end
      local stale = vim.tbl_map(function(s)
        return s.bookmark
      end, h.stale())
      if #stale == 0 then
        return warn("no stale kunai; name one to move it here: :Hiraishin relocate {name}")
      end
      if #stale == 1 then
        return relocate(stale[1])
      end
      vim.ui.select(stale, {
        prompt = "Relocate kunai to this line",
        format_item = function(bm)
          return string.format("%s  %s:%d  %s", bm.name or "—", bm.file, bm.line, bm.anchor and bm.anchor.text or "")
        end,
      }, function(choice)
        if choice then
          relocate(choice)
        end
      end)
    end,
    complete = bookmark_names,
  },
  prune = {
    run = function()
      local h = require("hiraishin")
      local stale = h.stale({ all = true })
      if #stale == 0 then
        return util.notify("no stale kunai")
      end
      local lines = {}
      for i, s in ipairs(stale) do
        if i > 10 then
          table.insert(lines, string.format("  … and %d more", #stale - 10))
          break
        end
        local bm = s.bookmark
        table.insert(lines, string.format("  %s  %s:%d [%s]", bm.name or "—", bm.file, bm.line, s.list))
      end
      local msg = string.format("Remove %d stale kunai?\n%s", #stale, table.concat(lines, "\n"))
      if vim.fn.confirm(msg, "&Yes\n&No", 2) == 1 then
        h.prune()
      end
    end,
  },
}

---@param cmd { fargs: string[], bang: boolean }
function M.run(cmd)
  local name = cmd.fargs[1]
  if not name then
    return warn("usage: :Hiraishin {" .. table.concat(vim.tbl_keys(M.subcommands), "|") .. "}")
  end
  local sub = M.subcommands[name]
  if not sub then
    return warn("unknown subcommand: " .. name)
  end
  sub.run(vim.list_slice(cmd.fargs, 2), cmd.bang)
end

---@return string[]
function M.complete(arg_lead, cmd_line, _)
  local args = vim.split(cmd_line, "%s+", { trimempty = false })
  -- args[1] is "Hiraishin" (maybe with !), the last one is being typed
  local candidates
  if #args <= 2 then
    candidates = vim.tbl_keys(M.subcommands)
    table.sort(candidates)
  else
    local sub = M.subcommands[args[2]]
    candidates = sub and sub.complete and sub.complete() or {}
  end
  return vim.tbl_filter(function(c)
    return vim.startswith(c, arg_lead)
  end, candidates)
end

return M
