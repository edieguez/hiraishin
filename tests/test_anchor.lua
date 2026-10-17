-- Pure re-anchoring logic (no child process needed)
local eq = MiniTest.expect.equality
local anchor = require("hiraishin.anchor")

local OPTS = { search_radius = 50, full_scan = true, max_lines = 20000, fuzzy_threshold = 0.8 }

local base = {
  "local M = {}",
  "",
  "function M.refresh(token)",
  "  local ctx = token.ctx",
  "  return ctx",
  "end",
  "",
  "return M",
}

local function bm_for(lines, line)
  return { line = line, anchor = anchor.capture(lines, line) }
end

local function insert(lines, at, new)
  local out = vim.deepcopy(lines)
  for i = #new, 1, -1 do
    table.insert(out, at, new[i])
  end
  return out
end

local T = MiniTest.new_set()

T["capture records text and nearest non-blank neighbours"] = function()
  eq(
    anchor.capture(base, 3),
    { text = "function M.refresh(token)", before = "local M = {}", after = "local ctx = token.ctx" }
  )
  eq(anchor.capture(base, 1), { text = "local M = {}", after = "function M.refresh(token)" })
end

T["unchanged file stays on the same line"] = function()
  eq({ anchor.locate(base, bm_for(base, 3), OPTS) }, { 3, "same" })
end

T["follows lines inserted above"] = function()
  local lines = insert(base, 1, { "-- header", "-- more", "" })
  eq({ anchor.locate(lines, bm_for(base, 3), OPTS) }, { 6, "moved" })
end

T["follows lines removed above"] = function()
  local lines = vim.list_slice(base, 3)
  eq({ anchor.locate(lines, bm_for(base, 3), OPTS) }, { 1, "moved" })
end

T["finds a line moved far away with a full scan"] = function()
  local filler = {}
  for i = 1, 200 do
    filler[i] = "-- filler " .. i
  end
  local lines = insert(base, 1, filler)
  eq({ anchor.locate(lines, bm_for(base, 3), OPTS) }, { 203, "moved" })
  local no_scan = vim.tbl_extend("force", OPTS, { full_scan = false })
  eq(anchor.locate(lines, bm_for(base, 3), no_scan), nil)
end

T["fuzzy-matches a slightly edited line"] = function()
  local lines = vim.deepcopy(base)
  lines[3] = "function M.refresh(tok)"
  eq({ anchor.locate(lines, bm_for(base, 3), OPTS) }, { 3, "fuzzy" })
end

T["ignores whitespace-only changes"] = function()
  local lines = vim.deepcopy(base)
  lines[4] = "\tlocal  ctx = token.ctx"
  eq(anchor.similarity(lines[4], base[4]), 1)
  eq((anchor.locate(lines, bm_for(base, 4), OPTS)), 4)
end

T["gives up when the line is gone"] = function()
  local lines = vim.deepcopy(base)
  table.remove(lines, 3)
  eq(anchor.locate(lines, bm_for(base, 3), OPTS), nil)
end

T["duplicate lines: neighbours decide, then distance"] = function()
  local lines = { "a = 1", "end", "b = 2", "", "c = 3", "end", "d = 4" }
  -- the second "end" (line 6) has neighbours c = 3 / d = 4
  local bm = bm_for(lines, 6)
  local shifted = insert(lines, 1, { "x", "y" })
  eq({ anchor.locate(shifted, bm, OPTS) }, { 8, "moved" })
end

T["trivial lines need a matching neighbour"] = function()
  local lines = { "if a then", "  go()", "end", "", "if b then", "  stop()", "end" }
  local bm = bm_for(lines, 3) -- "end" after go()
  local edited = { "if b then", "  stop()", "end" } -- the first block was deleted
  eq(anchor.locate(edited, bm, OPTS), nil)
end

T["similarity"] = function()
  eq(anchor.similarity("abc", "abc"), 1)
  eq(anchor.similarity("", "abc"), 0)
  eq(anchor.similarity("kitten", "sitting") < 0.8, true)
  eq(anchor.similarity("return value", "return values") > 0.9, true)
end

return T
