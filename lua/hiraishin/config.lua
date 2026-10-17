---@class hiraishin.Config
local M = {}

M.defaults = {
  -- "project" | "global" | "branch" (project + git branch, forked on first change)
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
    -- "nerd" (Nerd Font bookmark glyphs, recolorable), "ascii" or "emoji"
    style = "nerd",
    icon = false, -- a string overrides the style's icon
    stale_icon = false, -- a string overrides the style's stale icon
    global_icon = false, -- a string overrides the style's icon for global kunai
    show_slot = true,
    numhl = false,
  },
  line_highlight = false,
  virt_text = {
    enabled = true,
    show = "cursorline", -- "cursorline": only on the line you are on; "always"
    only_named = true, -- unnamed kunai only show the note icon (if any)
    position = "eol", -- "eol" | "right_align"
    prefix = "← ",
    note_icon = "✎",
  },
  name = {
    suggest_from_treesitter = true,
  },
  note_hover = true,
  -- draw kunai of the global store in project/branch buffers too
  global_kunai = true, -- show a kunai's note in a float when the cursor rests on it
  jump = {
    reuse_window = true, -- jump to a window already showing the file
    center = true, -- zz after jumping
    open_folds = true, -- zv after jumping
    flash = true, -- briefly highlight the line you land on
    flash_ms = 350,
  },
  picker = {
    backend = "auto", -- "auto" | "snacks" | "telescope" | "fzf-lua" | "mini" | "select"
    sort = "recent", -- after sealed kunai: "recent" | "manual" | "path" | "created"
    show_notes = true,
    icons = true, -- file icons from mini.icons / nvim-web-devicons when installed
    keys = {
      vsplit = "<C-v>",
      split = "<C-s>",
      tab = "<C-t>",
      delete = "<C-d>",
      rename = "<C-e>",
      note = "<C-o>",
      quickfix = "<C-q>",
      list = "<C-l>", -- switch list, then reopen
    },
  },
  manager = {
    width = 0.8, -- fraction of the editor
    height = 0.6,
    border = "rounded",
    confirm_delete = false, -- deletions can be undone (:Hiraishin undo)
  },
  undo_history = 20, -- deletions :Hiraishin undo can bring back
  -- routine feedback: "echo" (command line), "notify" (toasts) or "silent";
  -- warnings and errors always use vim.notify
  messages = "echo",
  -- ask before toggling off a kunai that has a name or a note
  -- (off: removals say how to undo them instead)
  confirm_remove_named = false,
  -- false disables all default keymaps; a table overrides per action
  keymaps = true,
}

M.options = vim.deepcopy(M.defaults)

---Keys present in the user's options that hiraishin does not know about.
---@type string[]
M.unknown = {}

local SCOPES = { project = true, global = true, branch = true }

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
    error(string.format("hiraishin: scope: expected 'project', 'global' or 'branch', got %s", vim.inspect(o.scope)), 0)
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
  check("signs.icon", o.signs.icon, { "string", "boolean" })
  check("signs.stale_icon", o.signs.stale_icon, { "string", "boolean" })
  if o.signs.style ~= "nerd" and o.signs.style ~= "ascii" and o.signs.style ~= "emoji" then
    error("hiraishin: signs.style: expected 'nerd', 'ascii' or 'emoji'", 0)
  end
  if o.virt_text.show ~= "cursorline" and o.virt_text.show ~= "always" then
    error("hiraishin: virt_text.show: expected 'cursorline' or 'always'", 0)
  end
  check("note_hover", o.note_hover, "boolean")
  check("global_kunai", o.global_kunai, "boolean")
  check("signs.global_icon", o.signs.global_icon, { "string", "boolean" })
  check("jump.flash", o.jump.flash, "boolean")
  check("jump.flash_ms", o.jump.flash_ms, "number")
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
  local backends = { auto = true, snacks = true, telescope = true, ["fzf-lua"] = true, mini = true, select = true }
  if not backends[o.picker.backend] then
    error("hiraishin: picker.backend: expected auto, snacks, telescope, fzf-lua, mini or select", 0)
  end
  local sorts = { recent = true, manual = true, path = true, created = true }
  if not sorts[o.picker.sort] then
    error("hiraishin: picker.sort: expected recent, manual, path or created", 0)
  end
  check("picker.show_notes", o.picker.show_notes, "boolean")
  check("picker.icons", o.picker.icons, "boolean")
  for name, key in pairs(o.picker.keys) do
    check("picker.keys." .. name, key, { "string", "boolean" })
  end
  check("manager.width", o.manager.width, "number")
  check("manager.height", o.manager.height, "number")
  check("manager.border", o.manager.border, { "string", "table" })
  check("manager.confirm_delete", o.manager.confirm_delete, "boolean")
  check("undo_history", o.undo_history, "number")
  check("confirm_remove_named", o.confirm_remove_named, "boolean")
  if o.messages ~= "echo" and o.messages ~= "notify" and o.messages ~= "silent" then
    error("hiraishin: messages: expected 'echo', 'notify' or 'silent'", 0)
  end
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
    vim.notify("unknown config keys: " .. table.concat(M.unknown, ", "), vim.log.levels.WARN, { title = "Hiraishin" })
  end
  merged.storage.dir = vim.fs.normalize(merged.storage.dir)
  M.options = merged
end

return M
