---Resolves where a bookmark lives: which store file, which root, which file key.
local config = require("hiraishin.config")
local util = require("hiraishin.util")

local M = {}

---@class hiraishin.Context
---@field store string   absolute path of the JSON store file
---@field root string?   project root (nil for the global scope)
---@field scope string
---@field file string?   bookmark file key (relative to root when possible)
---@field abs string?    absolute file path
---@field branch string? git branch (branch scope only)
---@field fork_from string? store to read until the branch store exists

---Project root for a file path.
---@param path string absolute path (a file or a directory)
---@param bufnr? integer
---@return string
function M.find_root(path, bufnr)
  local opts = config.options.root
  if opts.fn then
    local ok, root = pcall(opts.fn, bufnr or 0, path)
    if ok and type(root) == "string" and root ~= "" then
      return util.realpath(root)
    end
  end
  local root = vim.fs.root(path, opts.markers)
  if root then
    return util.realpath(root)
  end
  return util.realpath(vim.uv.cwd())
end

---Readable, collision-free store file name for a root.
---@param root string
---@return string
function M.store_name(root)
  local slug = root:gsub("[^%w%-_.]", "_"):gsub("^_+", "")
  if #slug > 60 then
    slug = slug:sub(-60)
  end
  return string.format("%s__%s.json", slug, vim.fn.sha256(root):sub(1, 8))
end

---Current git branch of a root, read from .git/HEAD (no git process).
---Handles worktrees (.git file with "gitdir:"). nil when detached or no repo.
---@param root string
---@return string?
function M.git_branch(root)
  local dotgit = root .. "/.git"
  local stat = vim.uv.fs_stat(dotgit)
  if not stat then
    return nil
  end
  local gitdir = dotgit
  if stat.type == "file" then
    local first = (vim.fn.readfile(dotgit, "", 1)[1] or ""):match("^gitdir:%s*(.-)%s*$")
    if not first then
      return nil
    end
    gitdir = first:sub(1, 1) == "/" and first or (root .. "/" .. first)
  end
  local ok, head = pcall(vim.fn.readfile, gitdir .. "/HEAD", "", 1)
  local ref = ok and head[1] and head[1]:match("^ref:%s*refs/heads/(.-)%s*$") or nil
  return ref ~= "" and ref or nil
end

-- :Hiraishin scope for this session; wins over project and config
local session_scope ---@type string?

---@param s string?
function M.set_session_scope(s)
  session_scope = s
end

-- root -> { key = "mtime", value = overrides }
local overrides_cache = {}
local ALLOWED_SCOPES = { project = true, global = true, branch = true }
local ALLOWED_SORTS = { recent = true, manual = true, path = true, created = true }

---Per-project settings from a `.hiraishin` file at the root, e.g.
---  return { scope = "branch", picker = { sort = "manual" } }
---Read through vim.secure.read (asks once whether to trust the file) and
---evaluated with no access to Neovim. An empty file only marks the root.
---@param root string?
---@return { scope?: string, sort?: string }
function M.project_overrides(root)
  if not root then
    return {}
  end
  local path = root .. "/.hiraishin"
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" or stat.size == 0 then
    return {}
  end
  local key = stat.mtime.sec .. "." .. stat.mtime.nsec
  local cached = overrides_cache[root]
  if cached and cached.key == key then
    return cached.value
  end
  local value = {}
  local ok_read, content = pcall(vim.secure.read, path)
  if ok_read and type(content) == "string" then
    local chunk = load(content, "@" .. path, "t", {})
    local ok, t = pcall(chunk or error)
    if ok and type(t) == "table" then
      if ALLOWED_SCOPES[t.scope] then
        value.scope = t.scope
      end
      if type(t.picker) == "table" and ALLOWED_SORTS[t.picker.sort] then
        value.sort = t.picker.sort
      end
    else
      require("hiraishin.util").notify(path .. ' should return a table, e.g. { scope = "branch" }', vim.log.levels.WARN)
    end
  end
  overrides_cache[root] = { key = key, value = value }
  return value
end

---Scope in effect for a root: session > project .hiraishin > config.
---@param root? string
---@return string
function M.effective_scope(root)
  if session_scope then
    return session_scope
  end
  root = root or M.find_root(require("hiraishin.util").realpath(vim.uv.cwd()))
  return M.project_overrides(root).scope or config.options.scope
end

---@param root string?
---@return hiraishin.Context
local function make(root, abs)
  local o = config.options
  local scope_name = M.effective_scope(root)
  local ctx = { scope = scope_name }
  if scope_name == "global" then
    ctx.store = o.storage.dir .. "/global.json"
  else
    ctx.root = root
    ctx.store = o.storage.dir .. "/projects/" .. M.store_name(root)
    if scope_name == "branch" then
      local branch = M.git_branch(root)
      if branch then
        ctx.branch = branch
        ctx.fork_from = ctx.store
        ctx.store = ctx.store:gsub("%.json$", "") .. "@" .. branch:gsub("[^%w%-_.]", "_") .. ".json"
      end
    end
  end
  if abs then
    ctx.abs = abs
    ctx.file = util.relpath(ctx.root, abs)
  end
  return ctx
end

---Context for an absolute file path.
---@param abs string
---@param bufnr? integer
---@return hiraishin.Context
function M.for_path(abs, bufnr)
  local root = M.find_root(abs, bufnr)
  return make(root, abs)
end

-- bufnr -> { name = string, ctx = hiraishin.Context }
local buf_cache = {}

---Context for a file buffer (cached per buffer name).
---@param bufnr integer
---@return hiraishin.Context?, string?
function M.for_buf(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local abs, err = util.buf_path(bufnr)
  if not abs then
    return nil, err
  end
  local cached = buf_cache[bufnr]
  if cached and cached.name == abs then
    return cached.ctx
  end
  local ctx = M.for_path(abs, bufnr)
  buf_cache[bufnr] = { name = abs, ctx = ctx }
  return ctx
end

---Context of the working directory (used when no file buffer is involved).
---@return hiraishin.Context
function M.for_cwd()
  local cwd = util.realpath(vim.uv.cwd())
  local root = M.find_root(cwd)
  return make(root)
end

---Buffer context when it is a file, otherwise the working directory's.
---@param bufnr? integer
---@return hiraishin.Context
function M.resolve(bufnr)
  return M.for_buf(bufnr or 0) or M.for_cwd()
end

---@param bufnr? integer nil clears everything
function M.invalidate(bufnr)
  if bufnr then
    buf_cache[bufnr] = nil
  else
    buf_cache = {}
  end
end

return M
