---@class hiraishin.Config
local M = {}

M.defaults = {
  -- "project" | "global"   ("branch" arrives in a later phase)
  scope = "project",
  root = {
    markers = { ".git", ".hiraishin" },
    ---@type fun(bufnr: integer, path: string): string?
    fn = nil,
  },
  storage = {
    dir = vim.fn.stdpath("data") .. "/hiraishin",
    debounce_ms = 500,
  },
  anchor = {
    search_radius = 50, -- lines searched around the stored line
    full_scan = true, -- then search the whole file (exact matches only)
    max_lines = 20000, -- skip the full scan above this size
    fuzzy_threshold = 0.8, -- whitespace-insensitive similarity, 0..1
  },
  signs = {
    enabled = true,
    priority = 15,
    icon = "⚡",
    stale_icon = "!",
    show_slot = true,
    numhl = false,
  },
  line_highlight = false,
  virt_text = {
    enabled = true,
    only_named = true, -- unnamed kunai only show the note icon (if any)
    position = "eol", -- "eol" | "right_align"
    prefix = "← ",
    note_icon = "✎",
  },
  name = {
    suggest_from_treesitter = true,
  },
  jump = {
    reuse_window = true, -- jump to a window already showing the file
    center = true, -- zz after jumping
    open_folds = true, -- zv after jumping
  },
  -- ask before toggling off a kunai that has a name or a note
  confirm_remove_named = true,
  -- false disables all default keymaps; a table overrides per action
  keymaps = true,
}

M.options = vim.deepcopy(M.defaults)

---Keys present in the user's options that hiraishin does not know about.
---@type string[]
M.unknown = {}

local SCOPES = { project = true, global = true }

---Deep merge where lists are replaced wholesale instead of merged by index.
local function merge(base, override)
  if type(base) ~= "table" or type(override) ~= "table" then
    return override
  end
  -- vim.islist({}) is true, so only treat non-empty tables (or list defaults)
  -- as lists; an empty override table must not wipe the defaults
  if (vim.islist(base) and next(base) ~= nil) or (next(override) ~= nil and vim.islist(override)) then
    return override
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(override) do
    out[k] = merge(base[k], v)
  end
  return out
end

local function collect_unknown(defaults, opts, prefix, out)
  for k, v in pairs(opts) do
    local path = prefix .. tostring(k)
    if defaults[k] == nil then
      -- root.fn and keymaps tables are open by design
      if not (path == "root.fn") and not vim.startswith(path, "keymaps.") then
        table.insert(out, path)
      end
    elseif type(defaults[k]) == "table" and type(v) == "table" and not vim.islist(defaults[k]) then
      collect_unknown(defaults[k], v, path .. ".", out)
    end
  end
end

-- vim.validate changed signature in 0.11; a tiny checker works on 0.10+.
local function check(name, value, types, optional)
  if value == nil and optional then
    return
  end
  types = type(types) == "table" and types or { types }
  if not vim.tbl_contains(types, type(value)) then
    error(string.format("hiraishin: %s: expected %s, got %s", name, table.concat(types, "|"), type(value)), 0)
  end
end

local function validate(o)
  if not SCOPES[o.scope] then
    error(string.format("hiraishin: scope: expected 'project' or 'global', got %s", vim.inspect(o.scope)), 0)
  end
  check("root.markers", o.root.markers, "table")
  check("root.fn", o.root.fn, "function", true)
  check("storage.dir", o.storage.dir, "string")
  check("storage.debounce_ms", o.storage.debounce_ms, "number")
  check("anchor.search_radius", o.anchor.search_radius, "number")
  check("anchor.full_scan", o.anchor.full_scan, "boolean")
  check("anchor.max_lines", o.anchor.max_lines, "number")
  check("anchor.fuzzy_threshold", o.anchor.fuzzy_threshold, "number")
  if o.anchor.fuzzy_threshold < 0 or o.anchor.fuzzy_threshold > 1 then
    error("hiraishin: anchor.fuzzy_threshold: expected a number between 0 and 1", 0)
  end
  check("signs.enabled", o.signs.enabled, "boolean")
  check("signs.priority", o.signs.priority, "number")
  check("signs.icon", o.signs.icon, "string")
  check("signs.stale_icon", o.signs.stale_icon, "string")
  check("signs.show_slot", o.signs.show_slot, "boolean")
  check("signs.numhl", o.signs.numhl, "boolean")
  check("line_highlight", o.line_highlight, "boolean")
  check("virt_text.enabled", o.virt_text.enabled, "boolean")
  check("virt_text.only_named", o.virt_text.only_named, "boolean")
  if o.virt_text.position ~= "eol" and o.virt_text.position ~= "right_align" then
    error("hiraishin: virt_text.position: expected 'eol' or 'right_align'", 0)
  end
  check("virt_text.prefix", o.virt_text.prefix, "string")
  check("virt_text.note_icon", o.virt_text.note_icon, "string")
  check("name.suggest_from_treesitter", o.name.suggest_from_treesitter, "boolean")
  check("jump.reuse_window", o.jump.reuse_window, "boolean")
  check("jump.center", o.jump.center, "boolean")
  check("jump.open_folds", o.jump.open_folds, "boolean")
  check("confirm_remove_named", o.confirm_remove_named, "boolean")
  check("keymaps", o.keymaps, { "boolean", "table" })
end

---@param opts? table
function M.setup(opts)
  opts = opts or {}
  local merged = merge(M.defaults, opts)
  validate(merged)
  M.unknown = {}
  collect_unknown(M.defaults, opts, "", M.unknown)
  if #M.unknown > 0 then
    vim.notify("hiraishin: unknown config keys: " .. table.concat(M.unknown, ", "), vim.log.levels.WARN)
  end
  merged.storage.dir = vim.fs.normalize(merged.storage.dir)
  M.options = merged
end

return M
