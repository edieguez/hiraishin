---:checkhealth hiraishin
local M = {}

function M.check()
  local health = vim.health
  local config = require("hiraishin.config")
  local o = config.options

  health.start("hiraishin.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required")
  end

  -- storage
  local dir = o.storage.dir
  if vim.fn.isdirectory(dir) == 0 then
    health.info("storage directory will be created on first save: " .. dir)
  elseif vim.fn.filewritable(dir) == 2 then
    health.ok("storage directory is writable: " .. dir)
  else
    health.error("storage directory is not writable: " .. dir)
  end
  local files = vim.fn.glob(dir .. "/**/*.json", false, true)
  local bad = {}
  for _, f in ipairs(files) do
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), "\n"))
    if not ok or type(data) ~= "table" or type(data.lists) ~= "table" then
      table.insert(bad, f)
    elseif (data.version or 0) > require("hiraishin.store").VERSION then
      table.insert(bad, f .. " (written by a newer hiraishin)")
    end
  end
  if #bad == 0 then
    health.ok(string.format("%d store file%s readable", #files, #files == 1 and "" or "s"))
  else
    for _, f in ipairs(bad) do
      health.error("unreadable store file: " .. f)
    end
  end
  local corrupt = vim.fn.glob(dir .. "/**/*.corrupt-*", false, true)
  if #corrupt > 0 then
    health.warn(
      string.format("%d store file%s set aside as corrupt", #corrupt, #corrupt == 1 and " was" or "s were"),
      corrupt
    )
  end

  local orphans = require("hiraishin.gc").orphans()
  if #orphans > 0 then
    health.info(
      string.format(
        "%d store file%s no longer needed · :Hiraishin gc cleans up",
        #orphans,
        #orphans == 1 and " is" or "s are"
      )
    )
  end

  -- config
  if #config.unknown > 0 then
    health.warn("unknown config keys: " .. table.concat(config.unknown, ", "))
  else
    health.ok("configuration is valid")
  end
  health.info("scope: " .. require("hiraishin.scope").effective_scope())

  -- picker
  local ok_picker, picker = pcall(require, "hiraishin.picker")
  if ok_picker then
    local _, name = picker.backend()
    if o.picker.backend ~= "auto" and name ~= o.picker.backend then
      health.warn(string.format("picker.backend = '%s' is not available; using %s", o.picker.backend, name))
    else
      health.ok("picker: " .. name)
    end
  end

  -- keymaps
  if o.keymaps ~= false then
    local skipped = {}
    for action, def in pairs(require("hiraishin.keymaps").defaults) do
      local lhs = type(o.keymaps) == "table" and o.keymaps[action] or def.lhs
      if lhs and not require("hiraishin.keymaps").is_set(lhs) then
        table.insert(skipped, string.format("%s (%s)", lhs, action))
      end
    end
    if #skipped > 0 then
      health.warn("keymaps not set because something else already uses them: " .. table.concat(skipped, ", "))
    else
      health.ok("keymaps set")
    end
  end

  -- stale kunai in the current scope
  local ok_stale, stale = pcall(require("hiraishin").stale, { all = true })
  if ok_stale and #stale > 0 then
    health.warn(
      string.format("%d stale kunai in this scope", #stale),
      { ":Hiraishin relocate to re-attach one, :Hiraishin prune to remove them" }
    )
  elseif ok_stale then
    health.ok("no stale kunai in this scope")
  end
end

return M
