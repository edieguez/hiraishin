---Finding store files nobody needs any more: projects whose folder is gone,
---branch stores of deleted branches, empty stores and corrupt backups.
local config = require("hiraishin.config")
local scope = require("hiraishin.scope")

local M = {}

---@class hiraishin.Orphan
---@field path string store file
---@field reason string why it can go

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local ok_dec, data = pcall(vim.json.decode, table.concat(lines, "\n"), { luanil = { object = true, array = true } })
  return ok_dec and type(data) == "table" and data or nil
end

local function count_kunai(data)
  local n = 0
  for _, list in pairs(type(data.lists) == "table" and data.lists or {}) do
    if type(list) == "table" and type(list.bookmarks) == "table" then
      n = n + vim.tbl_count(list.bookmarks)
    end
  end
  return n
end

---Store-safe names of a repository's local branches (as used in store file names).
---@param root string
---@return table<string, boolean>? nil when `root` is not a git repository
function M.branch_keys(root)
  local gitdir = scope.git_dir(root)
  if not gitdir then
    return nil
  end
  -- worktrees keep the branches in the main repository
  local common = gitdir
  local ok, cd = pcall(vim.fn.readfile, gitdir .. "/commondir", "", 1)
  if ok and cd[1] then
    common = cd[1]:sub(1, 1) == "/" and cd[1] or vim.fs.normalize(gitdir .. "/" .. cd[1])
  end
  local keys = {}
  local function add(name)
    keys[scope.branch_key(name)] = true
  end
  local heads = common .. "/refs/heads"
  if vim.uv.fs_stat(heads) then
    for name, kind in vim.fs.dir(heads, { depth = 20 }) do
      if kind == "file" then
        add(name)
      end
    end
  end
  local ok_p, packed = pcall(vim.fn.readfile, common .. "/packed-refs")
  if ok_p then
    for _, line in ipairs(packed) do
      local name = line:match("^%x+%s+refs/heads/(.+)$")
      if name then
        add(name)
      end
    end
  end
  return keys
end

---Store files that can be deleted.
---@return hiraishin.Orphan[]
function M.orphans()
  local dir = config.options.storage.dir
  local out = {}
  local loaded = require("hiraishin.store").loaded()
  for _, path in ipairs(vim.fn.glob(dir .. "/**/*.corrupt-*", false, true)) do
    table.insert(out, { path = path, reason = "corrupt file set aside" })
  end
  local branch_cache = {}
  for _, path in ipairs(vim.fn.glob(dir .. "/projects/*.json", false, true)) do
    local data = read_json(path)
    local base = vim.fs.basename(path)
    local branch = base:match("@(.+)%.json$")
    if data and not loaded[path] then
      local root = type(data.root) == "string" and data.root or nil
      if root and not vim.uv.fs_stat(root) then
        table.insert(out, { path = path, reason = "project folder is gone: " .. vim.fn.fnamemodify(root, ":~") })
      elseif root and branch then
        if branch_cache[root] == nil then
          branch_cache[root] = M.branch_keys(root) or false
        end
        local keys = branch_cache[root]
        if keys and not keys[branch] then
          table.insert(out, { path = path, reason = "branch '" .. branch .. "' no longer exists" })
        elseif count_kunai(data) == 0 then
          table.insert(out, { path = path, reason = "no kunai" })
        end
      elseif count_kunai(data) == 0 then
        table.insert(out, { path = path, reason = "no kunai" })
      end
    end
  end
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

---Delete store files.
---@param orphans hiraishin.Orphan[]
---@return integer deleted
function M.delete(orphans)
  local n = 0
  for _, o in ipairs(orphans) do
    if os.remove(o.path) then
      n = n + 1
    end
  end
  return n
end

return M
