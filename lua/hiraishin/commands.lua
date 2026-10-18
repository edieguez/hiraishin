local ui = require("hiraishin.ui")

local M = {}

local function undo_hint()
  return ui.hint("undo", ":Hiraishin undo") .. " to undo"
end

---"'name'" for a named kunai, "at file:line" otherwise.
local function describe(bm)
  if bm.name then
    return "'" .. bm.name .. "'"
  end
  return string.format("at %s:%d", vim.fs.basename(bm.file), bm.line)
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

---:Hiraishin next [list|seal]
local function step_scope(arg)
  return (arg == "list" or arg == "seal") and arg or "buffer"
end

---Lines of a :'<,'>Hiraishin range, nil without a multi-line range.
---@return { line: integer, end_line: integer }?
local function range_of(cmd)
  if cmd and cmd.range == 2 and cmd.line2 > cmd.line1 then
    return { line = cmd.line1, end_line = cmd.line2 }
  end
end

local function in_file_count()
  return #require("hiraishin").list({ bufnr = 0, include_stale = false })
end

---@type table<string, { run: fun(args: string[], bang: boolean), complete?: fun(): string[] }>
M.subcommands = {
  toggle = {
    run = function(_, _, cmd)
      local h = require("hiraishin")
      local range = range_of(cmd)
      local current = h.at_cursor(range and { line = range.line } or nil)
      if current and (current.name or current.note) and require("hiraishin.config").options.confirm_remove_named then
        if vim.fn.confirm("Remove kunai " .. describe(current) .. "?", "&Yes\n&No", 2) ~= 1 then
          return
        end
      end
      local bm, action, err = h.toggle(range)
      if err then
        return ui.warn(err)
      end
      if action == "removed" then
        ui.info(string.format("Removed kunai %s · %s", describe(bm), undo_hint()))
      elseif bm.end_line then
        ui.info(string.format("Kunai placed on lines %d-%d · %d in this file", bm.line, bm.end_line, in_file_count()))
      else
        ui.info(string.format("Kunai placed · %d in this file", in_file_count()))
      end
    end,
  },
  add = {
    run = function(args, bang, cmd)
      local h = require("hiraishin")
      local range = range_of(cmd) or {}
      local function add(name)
        local bm, status = h.add({ name = name, line = range.line, end_line = range.end_line })
        if not bm then
          return ui.warn(status)
        end
        if status == "exists" then
          ui.info(name and ("Kunai renamed to '" .. bm.name .. "'") or "This line already has a kunai")
        else
          ui.info(
            string.format(
              "Kunai %splaced · %d in this file",
              bm.name and ("'" .. bm.name .. "' ") or "",
              in_file_count()
            )
          )
        end
      end
      if #args > 0 then
        add(table.concat(args, " "))
      elseif bang then
        local current = h.at_cursor(range.line and { line = range.line } or nil)
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
          return ui.warn("No kunai on this line")
        end
        key = bm.id
      end
      local bm, err = h.remove(key, { reason = "command" })
      if not bm then
        return ui.warn(err)
      end
      ui.info(string.format("Removed kunai %s · %s", describe(bm), undo_hint()))
    end,
    complete = bookmark_names,
  },
  jump = {
    -- :Hiraishin jump {name|1-9} [vsplit|split|tab]
    run = function(args)
      if #args == 0 then
        return ui.warn("Usage: :Hiraishin jump {name|1-9} [vsplit|split|tab]")
      end
      local split
      if #args > 1 and vim.tbl_contains({ "vsplit", "split", "tab" }, args[#args]) then
        split = table.remove(args)
      end
      local _, err = require("hiraishin").jump(table.concat(args, " "), { split = split })
      if err then
        ui.warn(err)
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
    -- :Hiraishin next [list|seal]
    run = function(args)
      local _, err = require("hiraishin").next({ scope = step_scope(args[1]) })
      if err then
        ui.info(err)
      end
    end,
    complete = function()
      return { "list", "seal" }
    end,
  },
  prev = {
    run = function(args)
      local _, err = require("hiraishin").prev({ scope = step_scope(args[1]) })
      if err then
        ui.info(err)
      end
    end,
    complete = function()
      return { "list", "seal" }
    end,
  },
  seal = {
    -- :Hiraishin seal [1-9] | :Hiraishin seal clear   (no number: the next free seal)
    run = function(args)
      local h = require("hiraishin")
      if args[1] == "clear" then
        local bm = h.at_cursor()
        if not bm then
          return ui.warn("No kunai on this line")
        end
        local updated = h.update(bm.id, { slot = false })
        if updated and updated.removed then
          return ui.info("Seal removed, and the kunai it made · " .. undo_hint())
        end
        return ui.info("Seal removed")
      end
      if not args[1] then
        return M.seal_free()
      end
      M.seal(tonumber(args[1]))
    end,
    complete = function()
      return { "1", "2", "3", "4", "5", "6", "7", "8", "9", "clear" }
    end,
  },
  stats = {
    -- :Hiraishin stats [reset]   local usage stats
    run = function(args)
      local stats = require("hiraishin.stats")
      if args[1] == "reset" then
        if vim.fn.confirm("Forget all hiraishin usage stats?", "&Forget\n&Cancel", 2) == 1 then
          stats.reset()
          ui.info("Usage stats forgotten")
        end
        return
      end
      stats.show()
    end,
    complete = function()
      return { "reset" }
    end,
  },
  camp = {
    -- :Hiraishin camp [go|clear]   make this line the camp / go there / remove it
    run = function(args)
      local h = require("hiraishin")
      if args[1] == "go" then
        local _, err = h.go_camp()
        if err then
          ui.info(err)
        end
      elseif args[1] == "clear" then
        local old = h.clear_camp()
        if not old then
          return ui.info("No camp to remove")
        end
        ui.info(old.removed and ("Camp removed, and the kunai it made · " .. undo_hint()) or "Camp removed")
      else
        M.set_camp()
      end
    end,
    complete = function()
      return { "go", "clear" }
    end,
  },
  seals = {
    -- :Hiraishin seals   the seal menu
    run = function()
      require("hiraishin.seal_menu").open()
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
      if filter and filter ~= "buffer" and filter ~= "all" and filter ~= "global" then
        return ui.warn("Usage: :Hiraishin pick [buffer|all|global]")
      end
      require("hiraishin").pick({ filter = filter })
    end,
    complete = function()
      return { "buffer", "all", "global" }
    end,
  },
  quickfix = {
    -- :Hiraishin quickfix [all]
    run = function(args)
      if require("hiraishin").to_quickfix({ all = args[1] == "all" }) == 0 then
        ui.info("No kunai to send · " .. ui.hint("toggle", ":Hiraishin toggle") .. " places one")
      end
    end,
    complete = function()
      return { "all" }
    end,
  },
  loclist = {
    run = function(args)
      if require("hiraishin").to_quickfix({ loclist = true, all = args[1] == "all" }) == 0 then
        ui.info("No kunai to send · " .. ui.hint("toggle", ":Hiraishin toggle") .. " places one")
      end
    end,
    complete = function()
      return { "all" }
    end,
  },
  manager = {
    -- :Hiraishin manager [global]
    run = function(args)
      require("hiraishin").manager({ global = args[1] == "global" })
    end,
    complete = function()
      return { "global" }
    end,
  },
  global = {
    -- :Hiraishin global   place or remove a global kunai on this line
    run = function()
      local bm, action, err = require("hiraishin").toggle({ global = true })
      if err then
        return ui.warn(err)
      end
      if action == "removed" then
        ui.info(string.format("Removed global kunai %s · %s", describe(bm), undo_hint()))
      else
        ui.info("Global kunai placed · " .. ui.hint("pick_global", ":Hiraishin pick global") .. " finds it anywhere")
      end
    end,
  },
  undo = {
    run = function()
      local n, msg = require("hiraishin").undo()
      if not n then
        return ui.info("Nothing to undo")
      end
      local text = string.format("Restored %d kunai", n)
      if msg then
        ui.warn(text .. " (" .. msg .. ")")
      else
        ui.info(text)
      end
    end,
  },
  list = {
    -- :Hiraishin list            choose a list (or create one)
    -- :Hiraishin list {name}     switch to it, creating it if needed
    -- :Hiraishin list delete {name}
    run = function(args)
      local h = require("hiraishin")
      if args[1] == "delete" then
        local name = table.concat(vim.list_slice(args, 2), " ")
        if name == "" then
          return ui.warn("Usage: :Hiraishin list delete {name}")
        end
        local _, err = h.delete_list(name)
        if err then
          return ui.warn(err)
        end
        return ui.info(string.format("Deleted list '%s' · %s", name, undo_hint()))
      end
      if #args > 0 then
        local name = h.set_list(table.concat(args, " "))
        return ui.info("List: " .. name)
      end
      M.choose_list()
    end,
    complete = function()
      local names = require("hiraishin").lists()
      table.insert(names, "delete")
      return names
    end,
  },
  scope = {
    -- :Hiraishin scope {project|global|branch}  (this session only)
    run = function(args)
      if not args[1] then
        return ui.info("Scope: " .. require("hiraishin.scope").effective_scope())
      end
      local _, err = require("hiraishin").set_scope(args[1])
      if err then
        return ui.warn(err)
      end
      ui.info("Scope: " .. args[1])
    end,
    complete = function()
      return { "project", "global", "branch" }
    end,
  },
  import = {
    -- :Hiraishin import marks
    run = function(args)
      if args[1] ~= "marks" then
        return ui.warn("Usage: :Hiraishin import marks")
      end
      ui.info(string.format("Imported %d global marks", require("hiraishin").import_marks()))
    end,
    complete = function()
      return { "marks" }
    end,
  },
  relocate = {
    run = function(args)
      local h = require("hiraishin")
      local function relocate(key)
        local bm, err = h.relocate(key)
        if not bm then
          return ui.warn(err)
        end
        ui.info(string.format("Kunai %s moved here", describe(bm)))
      end
      if #args > 0 then
        return relocate(table.concat(args, " "))
      end
      local stale = vim.tbl_map(function(s)
        return s.bookmark
      end, h.stale())
      if #stale == 0 then
        return ui.info("No stale kunai · :Hiraishin relocate {name} moves any kunai here")
      end
      if #stale == 1 then
        return relocate(stale[1].id)
      end
      vim.ui.select(stale, {
        prompt = "Relocate kunai to this line",
        format_item = function(bm)
          return string.format("%s  %s:%d  %s", bm.name or "—", bm.file, bm.line, bm.anchor and bm.anchor.text or "")
        end,
      }, function(choice)
        if choice then
          relocate(choice.id)
        end
      end)
    end,
    complete = bookmark_names,
  },
  gc = {
    -- :Hiraishin gc   list unneeded store files and delete them after asking
    -- :Hiraishin! gc  delete without asking
    run = function(_, bang)
      local gc = require("hiraishin.gc")
      local orphans = gc.orphans()
      if #orphans == 0 then
        return ui.info("No store files to clean up")
      end
      if not bang then
        local dir = require("hiraishin.config").options.storage.dir
        local lines = {}
        for i, o in ipairs(orphans) do
          if i > 15 then
            table.insert(lines, string.format("  … and %d more", #orphans - 15))
            break
          end
          table.insert(lines, string.format("  %s  (%s)", o.path:sub(#dir + 2), o.reason))
        end
        local msg = string.format(
          "Delete %d store file%s? This cannot be undone.\n%s",
          #orphans,
          #orphans == 1 and "" or "s",
          table.concat(lines, "\n")
        )
        if vim.fn.confirm(msg, "&Delete\n&Cancel", 2) ~= 1 then
          return
        end
      end
      local n = gc.delete(orphans)
      ui.info(string.format("Deleted %d store file%s", n, n == 1 and "" or "s"))
    end,
  },
  prune = {
    run = function()
      local removed = require("hiraishin").prune()
      if #removed == 0 then
        return ui.info("No stale kunai")
      end
      ui.info(string.format("Removed %d stale kunai · %s", #removed, undo_hint()))
    end,
  },
}

---Seal the cursor line's kunai and say what happened (also used by m1..m9).
---@param n integer
function M.seal(n)
  local bm, err, displaced = require("hiraishin").seal(n)
  if not bm then
    return ui.warn(err)
  end
  if displaced and not displaced.removed then
    ui.info(string.format("Seal %d moved from %s to %s", n, describe(displaced), describe(bm)))
  else
    ui.info(string.format("Sealed as %d · %s jumps here", n, ui.hint("jump_slot_" .. n, ":Hiraishin jump " .. n)))
  end
end

---Make the cursor line the camp and say so (m0).
function M.set_camp()
  local bm, err, previous, already = require("hiraishin").set_camp()
  if not bm then
    return ui.warn(err)
  end
  local go = ui.hint("go_camp", ":Hiraishin camp go")
  if already then
    ui.info("This is already your camp")
  elseif previous then
    ui.info(string.format("Camp moved here · was %s:%d", vim.fs.basename(previous.file), previous.line))
  else
    ui.info(string.format("Camp set · %s comes back here from anywhere", go))
  end
end

---Seal the cursor line with the next free seal and say which one (mm).
function M.seal_free()
  local bm, n, already = require("hiraishin").seal_free()
  if not bm then
    return ui.warn(n)
  end
  local jump = ui.hint("jump_slot_" .. n, ":Hiraishin jump " .. n)
  if already then
    return ui.info(string.format("Already sealed as %d · %s jumps here", n, jump))
  end
  ui.info(string.format("Sealed as %d · %s jumps here", n, jump))
end

---Choose (or create) a list, showing how many kunai each one has.
---@param on_done? fun(name: string)
function M.choose_list(on_done)
  local h = require("hiraishin")
  local names, active, counts = h.lists()
  local NEW = "+ New list…"
  table.insert(names, NEW)
  vim.ui.select(names, {
    prompt = "Kunai list",
    format_item = function(n)
      if n == NEW then
        return n
      end
      local label = string.format("%s (%d)", n, counts[n] or 0)
      return n == active and (label .. "  ● active") or label
    end,
  }, function(choice)
    local function switch(name)
      h.set_list(name)
      ui.info("List: " .. name)
      if on_done then
        on_done(name)
      end
    end
    if choice == NEW then
      vim.ui.input({ prompt = "New list name: " }, function(name)
        if name and vim.trim(name) ~= "" then
          switch(vim.trim(name))
        end
      end)
    elseif choice then
      switch(choice)
    end
  end)
end

---The feature a command counts as in the stats ("next list" -> next_list).
---@param name string
---@param args string[]
---@return string
function M.feature(name, args)
  local a = args[1]
  if (name == "next" or name == "prev") and (a == "list" or a == "seal") then
    return name .. "_" .. a
  elseif name == "pick" and a then
    return "pick_" .. a
  elseif name == "seal" then
    return a == nil and "seal_free" or a == "clear" and "seal_clear" or "seal"
  elseif name == "camp" then
    return a == "go" and "go_camp" or a == "clear" and "camp_clear" or "camp"
  elseif name == "list" and a == "delete" then
    return "list_delete"
  elseif name == "manager" and a == "global" then
    return "manager_global"
  end
  return name
end

---@param cmd { fargs: string[], bang: boolean, range?: integer, line1?: integer, line2?: integer }
function M.run(cmd)
  local name = cmd.fargs[1]
  if not name then
    -- bare :Hiraishin opens the picker
    return require("hiraishin").pick()
  end
  local sub = M.subcommands[name]
  if not sub then
    return ui.warn("Unknown subcommand: " .. name)
  end
  local args = vim.list_slice(cmd.fargs, 2)
  if name == "stats" then
    return sub.run(args, cmd.bang, cmd)
  end
  -- counted once (a key that runs this command already counted it)
  require("hiraishin.stats").as(M.feature(name, args), "cmd", function()
    sub.run(args, cmd.bang, cmd)
  end)
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
