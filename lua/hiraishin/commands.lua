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
        vim.ui.input({ prompt = "Kunai name: ", default = current and current.name or "" }, function(input)
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
