---Name suggestions for new kunai.
local M = {}

-- node types whose `name` field names the enclosing symbol
local SYMBOL_PATTERNS = {
  "function",
  "method",
  "class",
  "struct",
  "interface",
  "enum",
  "trait",
  "impl",
  "module",
  "type_spec",
  "type_declaration",
  "constructor",
}

local function is_symbol(node_type)
  for _, p in ipairs(SYMBOL_PATTERNS) do
    if node_type:find(p, 1, true) then
      return true
    end
  end
  return false
end

---Name of the symbol enclosing the cursor, via Treesitter.
---@param bufnr integer
---@return string?
local function enclosing_symbol(bufnr)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, ignore_injections = false })
  if not ok or not node then
    return nil
  end
  while node do
    if is_symbol(node:type()) then
      local name_nodes = node:field("name")
      local name = name_nodes and name_nodes[1]
      if name then
        local text = vim.treesitter.get_node_text(name, bufnr)
        if text and text ~= "" and not text:find("\n") then
          return text
        end
      end
    end
    node = node:parent()
  end
end

---Suggested name for a kunai on the cursor line: the enclosing function,
---method or class. No guess otherwise; a random word pre-filled in the
---prompt gets in the way of typing a name.
---@param bufnr? integer
---@return string?
function M.suggest(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if require("hiraishin.config").options.name.suggest_from_treesitter then
    return enclosing_symbol(bufnr)
  end
end

return M
