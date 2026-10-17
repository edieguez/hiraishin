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

---@param root string?
---@return hiraishin.Context
local function make(root, abs)
  local o = config.options
  local ctx = { scope = o.scope }
  if o.scope == "global" then
    ctx.store = o.storage.dir .. "/global.json"
  else
    ctx.root = root
    ctx.store = o.storage.dir .. "/projects/" .. M.store_name(root)
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
  local root = config.options.scope ~= "global" and M.find_root(abs, bufnr) or nil
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
  local root = config.options.scope ~= "global" and M.find_root(cwd) or nil
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
