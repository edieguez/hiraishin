---Re-locating a bookmark from its stored anchor (line text + neighbours).
local M = {}

local CONTEXT_SCAN = 20
-- anchors shorter than this (ignoring whitespace) need a matching neighbour,
-- otherwise a lone "}" or "end" would latch onto any other one
local TRIVIAL_LEN = 4

local function squash(s)
  return (s:gsub("%s+", ""))
end

---Normalized similarity in [0, 1], whitespace-insensitive (Levenshtein).
---@param a string
---@param b string
---@return number
function M.similarity(a, b)
  a, b = squash(a), squash(b)
  if a == b then
    return 1
  end
  local la, lb = #a, #b
  if la == 0 or lb == 0 then
    return 0
  end
  local longest = math.max(la, lb)
  -- cheap reject: the length gap alone already caps the score
  if math.min(la, lb) / longest < 0.5 then
    return 0
  end
  local prev, cur = {}, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    cur[0] = i
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = ca == b:byte(j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev, cur = cur, prev
  end
  return 1 - prev[lb] / longest
end

---@param lines string[]
---@param i integer
---@param step integer -1 (above) or 1 (below)
---@return string?
local function neighbour(lines, i, step, trimmed)
  local j, n = i + step, 0
  while j >= 1 and j <= #lines and n < CONTEXT_SCAN do
    local t = trimmed and trimmed[j] or vim.trim(lines[j])
    if t ~= "" then
      return t
    end
    j, n = j + step, n + 1
  end
end

---How many of the anchor's neighbours match around line i (0..2).
local function context_score(lines, i, anchor, trimmed)
  local s = 0
  if anchor.before and neighbour(lines, i, -1, trimmed) == anchor.before then
    s = s + 1
  end
  if anchor.after and neighbour(lines, i, 1, trimmed) == anchor.after then
    s = s + 1
  end
  return s
end

---Fresh anchor for line i of `lines`.
---@param lines string[]
---@param i integer
function M.capture(lines, i)
  return {
    text = vim.trim(lines[i] or ""),
    before = neighbour(lines, i, -1),
    after = neighbour(lines, i, 1),
  }
end

---@alias hiraishin.LocateMethod "same"|"moved"|"fuzzy"

---Trimmed copy of every line; pass it to locate() when locating many kunai
---in the same file so the work is done once.
---@param lines string[]
---@return string[]
function M.trim_all(lines)
  -- lazy: lines are trimmed on first access, so an unchanged file costs ~nothing
  return setmetatable({}, {
    __index = function(t, i)
      local l = lines[i]
      if l == nil then
        return nil
      end
      local v = vim.trim(l)
      rawset(t, i, v)
      return v
    end,
  })
end

---Find where a bookmark's line is now.
---@param lines string[] current file content
---@param bm { line: integer, anchor: { text: string, before: string?, after: string? }? }
---@param opts { search_radius: integer, full_scan: boolean, max_lines: integer, fuzzy_threshold: number }
---@param trimmed? string[] result of trim_all(lines)
---@return integer? line, hiraishin.LocateMethod? method
function M.locate(lines, bm, opts, trimmed)
  trimmed = trimmed or M.trim_all(lines)
  local count = #lines
  if count == 0 then
    return nil
  end
  local a = bm.anchor or { text = "" }
  local text = a.text or ""
  local origin = bm.line
  local wanted_ctx = (a.before and 1 or 0) + (a.after and 1 or 0)

  -- Fast path: the stored line still holds the same text and neighbours.
  if origin >= 1 and origin <= count and trimmed[origin] == text then
    if context_score(lines, origin, a, trimmed) == wanted_ctx then
      return origin, "same"
    end
  end

  local trivial = #squash(text) < TRIVIAL_LEN
  local best, best_score, best_dist
  local function consider(i, score)
    local dist = math.abs(i - origin)
    if not best or score > best_score or (score == best_score and dist < best_dist) then
      best, best_score, best_dist = i, score, dist
    end
  end
  local function scan_exact(from, to, skip_lo, skip_hi)
    for i = from, to do
      if not (skip_lo and i >= skip_lo and i <= skip_hi) and trimmed[i] == text then
        local ctx = context_score(lines, i, a, trimmed)
        if not trivial or ctx > 0 or wanted_ctx == 0 then
          consider(i, 2 + ctx)
        end
      end
    end
  end

  local lo = math.max(1, origin - opts.search_radius)
  local hi = math.min(count, origin + opts.search_radius)

  scan_exact(lo, hi)
  if not best and opts.full_scan and count <= opts.max_lines then
    scan_exact(1, count, lo, hi)
  end
  if best then
    return best, best == origin and "same" or "moved"
  end

  -- Fuzzy fallback, limited to the search window (it is the expensive part).
  if not trivial then
    for i = lo, hi do
      local sim = M.similarity(trimmed[i], text)
      if sim >= opts.fuzzy_threshold then
        consider(i, sim + context_score(lines, i, a, trimmed))
      end
    end
    if best then
      return best, "fuzzy"
    end
  end
  return nil
end

return M
