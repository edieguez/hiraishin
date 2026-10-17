local M = {}

---Resolve symlinks when the path exists, otherwise just normalize it.
---@param path string
---@return string
function M.realpath(path)
  path = vim.fs.normalize(path)
  local real = vim.uv.fs_realpath(path)
  if real then
    return vim.fs.normalize(real)
  end
  -- file not on disk yet: resolve its directory so roots still line up
  local dir, base = vim.fs.dirname(path), vim.fs.basename(path)
  local real_dir = vim.uv.fs_realpath(dir)
  if real_dir then
    return vim.fs.normalize(real_dir .. "/" .. base)
  end
  return path
end

---Absolute path of a normal file buffer, or nil with a reason.
---@param bufnr integer
---@return string?, string?
function M.buf_path(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "invalid buffer"
  end
  if vim.bo[bufnr].buftype ~= "" then
    return nil, "not a file buffer"
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil, "buffer has no file name"
  end
  return M.realpath(vim.fn.fnamemodify(name, ":p"))
end

---Path relative to root when inside it, otherwise the absolute path.
---@param root string?
---@param path string
---@return string
function M.relpath(root, path)
  if root and root ~= "" then
    local prefix = root:sub(-1) == "/" and root or (root .. "/")
    if vim.startswith(path, prefix) then
      return path:sub(#prefix + 1)
    end
  end
  return path
end

---@param root string?
---@param file string
---@return string
function M.abspath(root, file)
  if file:sub(1, 1) == "/" or file:match("^%a:[/\\]") or not root then
    return file
  end
  return vim.fs.normalize(root .. "/" .. file)
end

---Random 8-char hex id not present in `taken`.
---@param taken table<string, any>
---@return string
function M.new_id(taken)
  for _ = 1, 100 do
    local ok, bytes = pcall(vim.uv.random, 4)
    local id
    if ok and type(bytes) == "string" then
      id = bytes:gsub(".", function(c)
        return string.format("%02x", c:byte())
      end)
    else
      id = string.format("%08x", math.random(0, 0x7fffffff))
    end
    if not taken[id] then
      return id
    end
  end
  error("hiraishin: could not generate a unique id")
end

---@param s string?
---@return string?
function M.trim(s)
  if s == nil then
    return nil
  end
  s = vim.trim(s)
  return s ~= "" and s or nil
end

local CONTEXT_SCAN = 20

---Anchor for a 1-based line: its trimmed text and nearest non-blank neighbours.
---@param bufnr integer
---@param line integer
---@return { text: string, before: string?, after: string? }
function M.anchor(bufnr, line)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local first = math.max(1, line - CONTEXT_SCAN)
  local last = math.min(count, line + CONTEXT_SCAN)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  local function at(l)
    return lines[l - first + 1]
  end
  local anchor = { text = vim.trim(at(line) or "") }
  for l = line - 1, first, -1 do
    local t = M.trim(at(l))
    if t then
      anchor.before = t
      break
    end
  end
  for l = line + 1, last do
    local t = M.trim(at(l))
    if t then
      anchor.after = t
      break
    end
  end
  return anchor
end

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify("hiraishin: " .. msg, level or vim.log.levels.INFO)
end

return M
