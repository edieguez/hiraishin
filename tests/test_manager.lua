local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local tmp

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = H.tmpdir()
      child.setup(tmp)
      child.lua([[vim.fn.chdir(T.proj_a)]])
      child.lua([[vim.fn.writefile({ "alpha", "beta", "gamma" }, T.proj_a .. "/src/other.lua")]])
      child.lua([[vim.fn.confirm = function() return 1 end]]) -- say yes unless a test says otherwise
    end,
    post_once = child.stop,
  },
})

local function main_lua(line)
  child.edit(child.T("proj_a") .. "/src/main.lua", line)
end
local function place(line, name)
  child.api.nvim_win_set_cursor(0, { line, 0 })
  return child.lua_get("require('hiraishin').add({ name = ... })", { name or vim.NIL })
end
local function names()
  return child.lua_get([[vim.tbl_map(function(b) return b.name or "-" end, require("hiraishin").list())]])
end
local function slot(name)
  return child.lua_get("require('hiraishin').slot_of(...)", { name })
end
-- manager buffer lines without the concealed ids
local function shown()
  return vim.tbl_map(function(l)
    return (l:gsub("%s*/%x+$", ""))
  end, child.api.nvim_buf_get_lines(0, 0, -1, false))
end
local function set_lines(lines)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end
local function lines()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function problems()
  return child.lua_get(
    [[vim.tbl_map(function(d) return { d.lnum + 1, d.message } end, vim.diagnostic.get(0, { namespace = require("hiraishin.manager").ns }))]]
  )
end

-- hello (main:3, seal 1), ret (main:4), unnamed (main:7)
local function fixture()
  main_lua()
  place(3, "hello")
  place(4, "ret")
  place(7)
  child.lua([[require("hiraishin").update("hello", { slot = 1, note = "first\nsecond" })]])
end

T["render"] = MiniTest.new_set()

T["render"]["one aligned line per kunai, in list order"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  eq(child.lua_get("vim.bo.filetype"), "hiraishin")
  eq(child.lua_get("vim.api.nvim_win_get_config(0).relative"), "editor")
  eq(shown(), {
    "1 │ hello │ src/main.lua:3 │ first ⏎ second",
    "- │ ret   │ src/main.lua:4 │",
    "- │ -     │ src/main.lua:7 │",
  })
  eq(lines()[1]:match("/%x%x%x%x%x%x%x%x$") ~= nil, true)
end

T["render"]["shows live lines and stale kunai"] = function()
  fixture()
  child.api.nvim_buf_set_lines(0, 0, 0, false, { "-- new" })
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.type_keys("d", "d") -- ret's line
  child.cmd("Hiraishin manager")
  eq(shown()[1], "1 │ hello │ src/main.lua:4   │ first ⏎ second")
  eq(shown()[2], "- │ ret   │ src/main.lua:4 ! │")
end

T["apply"] = MiniTest.new_set()

T["apply"]["rename, clear names, set notes and seals"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  local l = lines()
  set_lines({
    (l[1]:gsub("1 │ hello", "- │ greet")),
    (l[2]:gsub(vim.pesc("- │ ret  "), "2 │ -    "):gsub("src/main.lua:4 │", "src/main.lua:4 │ check this")),
    (l[3]:gsub(vim.pesc("- │ -    "), "1 │ seven")),
  })
  child.cmd("write")
  eq(problems(), {})
  eq(child.lua_get("vim.bo.modified"), false)
  eq(names(), { "greet", "-", "seven" })
  eq(child.lua_get([[require("hiraishin").get("greet").note]]), "first\nsecond")
  eq(child.lua_get([[require("hiraishin").list()[2].note]]), "check this")
  eq(slot("seven"), 1)
  eq(slot("greet"), vim.NIL)
  eq(child.lua_get([[require("hiraishin").slot_of(require("hiraishin").list()[2].id)]]), 2)
end

T["apply"]["reordering lines reorders the list"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  child.type_keys("d", "d", "p") -- move hello below ret
  child.cmd("write")
  eq(names(), { "ret", "hello", "-" })
end

T["apply"]["deleting lines deletes kunai and :Hiraishin undo restores them"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  child.type_keys("d", "d")
  child.cmd("write")
  eq(names(), { "ret", "-" })
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Deleted 1 kunai · <leader>hu to undo")
  child.cmd("close")
  child.cmd("Hiraishin undo")
  eq(names(), { "hello", "ret", "-" })
  eq(slot("hello"), 1)
  eq(child.lua_get([[require("hiraishin").get("hello").note]]), "first\nsecond")
end

T["apply"]["manager.confirm_delete = true asks first"] = function()
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, manager = { confirm_delete = true } })]]
  )
  fixture()
  child.cmd("Hiraishin manager")
  child.lua([[_G.asked = nil; vim.fn.confirm = function(msg) _G.asked = msg; return 1 end]])
  child.type_keys("d", "d")
  child.cmd("write")
  eq(child.lua_get("_G.asked"):match("Delete 1 kunai") ~= nil, true)
  eq(names(), { "ret", "-" })
  child.cmd("close")
  child.cmd("Hiraishin undo")
  eq(names(), { "hello", "ret", "-" })
  eq(slot("hello"), 1)
  eq(child.lua_get([[require("hiraishin").get("hello").note]]), "first\nsecond")
end

T["apply"]["declining the delete applies nothing"] = function()
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, manager = { confirm_delete = true } })]]
  )
  fixture()
  child.cmd("Hiraishin manager")
  child.lua([[vim.fn.confirm = function() return 2 end]])
  child.type_keys("d", "d")
  child.cmd("write")
  eq(names(), { "hello", "ret", "-" })
  eq(child.lua_get("vim.bo.modified"), true)
end

T["apply"]["problems are shown as diagnostics and nothing is applied"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  child.lua([[vim.notify = function() end]])
  local l = lines()
  set_lines({
    (l[1]:gsub("hello", "dup")),
    (l[2]:gsub("ret  ", "dup  "):gsub("^%-", "1")),
    (l[3]:gsub("src/main.lua:7", "src/other.lua:7")),
    "a brand new line",
  })
  child.cmd("write")
  local p = problems()
  eq(#p, 4)
  eq(p[1][1], 2)
  eq(p[1][2]:match("seal 1 is also on line 1") ~= nil or p[2][2]:match("seal 1") ~= nil, true)
  local msgs = table.concat(
    vim.tbl_map(function(x)
      return x[2]
    end, p),
    "\n"
  )
  eq(msgs:match("name 'dup' is also on line 1") ~= nil, true)
  eq(msgs:match("path is read%-only") ~= nil, true)
  eq(msgs:match("missing kunai id") ~= nil, true)
  eq(names(), { "hello", "ret", "-" })
end

T["apply"]["kunai added while the manager is open are kept"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  child.lua([[
    local h = require("hiraishin")
    local buf = vim.fn.bufnr(T.proj_a .. "/src/main.lua")
    h.add({ bufnr = buf, line = 1, name = "late" })
  ]])
  child.type_keys("d", "d") -- delete hello
  child.cmd("write")
  eq(names(), { "ret", "-", "late" })
end

T["keys"] = MiniTest.new_set()

T["keys"]["<CR> jumps to the kunai under the cursor"] = function()
  fixture()
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Hiraishin manager")
  child.type_keys("j", "<CR>")
  eq(child.lua_get("vim.api.nvim_win_get_config(0).relative"), "")
  eq(child.api.nvim_win_get_cursor(0)[1], 4)
end

T["keys"]["q asks before discarding edits"] = function()
  fixture()
  child.cmd("Hiraishin manager")
  child.type_keys("d", "d")
  child.lua([[vim.fn.confirm = function() return 2 end]])
  child.type_keys("q")
  eq(child.lua_get("vim.bo.filetype"), "hiraishin")
  child.lua([[vim.fn.confirm = function() return 1 end]])
  child.type_keys("q")
  eq(child.lua_get("vim.bo.filetype"), "lua")
  eq(#child.lua_get([[require("hiraishin").list()]]), 3)
end

T["keys"]["<Tab> shows the next list"] = function()
  fixture()
  child.lua([[require("hiraishin").set_list("bugs")]])
  main_lua()
  place(1, "in-bugs")
  child.lua([[require("hiraishin").set_list("default")]])
  child.cmd("Hiraishin manager")
  eq(#lines(), 3)
  child.type_keys("<Tab>")
  eq(shown(), { "- │ in-bugs │ src/main.lua:1 │" })
  eq(child.lua_get("vim.api.nvim_win_get_config(0).title[1][1]"):match("bugs") ~= nil, true)
end

T["apply"]["names and notes may contain | (only │ separates columns)"] = function()
  main_lua()
  place(3, "a|b")
  child.lua([[require("hiraishin").update("a|b", { note = "x | y │ z" })]])
  child.cmd("Hiraishin manager")
  eq(shown(), { "- │ a|b  │ src/main.lua:3 │ x | y │ z" })
  local id = lines()[1]:match("/(%x+)$")
  set_lines({ "- │ c|d │ src/main.lua:3 │ p|q /" .. id })
  child.cmd("write")
  eq(problems(), {})
  eq(child.lua_get([[require("hiraishin").get("c|d").note]]), "p|q")
end

T["apply"]["names can't contain │"] = function()
  main_lua()
  eq(
    child.lua_get([[select(2, require("hiraishin").add({ name = "a│b" }))]]),
    "Kunai names can't contain │ or line breaks"
  )
  place(3, "ok")
  eq(
    child.lua_get([[select(2, require("hiraishin").update("ok", { name = "x│y" }))]]),
    "Kunai names can't contain │ or line breaks"
  )
end

T["apply"]["names can't be seal numbers"] = function()
  main_lua()
  place(3, "ok")
  child.cmd("Hiraishin manager")
  local id = lines()[1]:match("/(%x+)$")
  set_lines({ "- │ 3 │ src/main.lua:3 │ /" .. id })
  child.cmd("write")
  eq(problems(), { { 1, "name '3' is a seal number; names 1-9 are not allowed" } })
  eq(child.lua_get([[require("hiraishin").get("ok").line]]), 3)
end

T["live"] = MiniTest.new_set()

T["live"]["an open manager shows changes made elsewhere"] = function()
  main_lua()
  place(1, "one")
  place(5, "five")
  child.cmd("Hiraishin manager")
  child.api.nvim_win_set_cursor(0, { 2, 0 }) -- on "five"
  -- a kunai placed in the file behind the float
  child.lua([[require("hiraishin").add({ bufnr = vim.fn.bufnr("main.lua"), line = 3, name = "three" })]])
  child.lua([[vim.wait(50)]])
  eq(#lines(), 3)
  eq(shown()[3]:match("three") ~= nil, true)
  eq(child.api.nvim_get_current_line():match("five") ~= nil, true) -- cursor stayed on its kunai
end

T["live"]["edits in progress are never overwritten"] = function()
  main_lua()
  place(1, "one")
  child.cmd("Hiraishin manager")
  set_lines({ (lines()[1]:gsub("one", "edited")) })
  child.lua([[require("hiraishin").add({ bufnr = vim.fn.bufnr("main.lua"), line = 3, name = "three" })]])
  child.lua([[vim.wait(50)]])
  eq(#lines(), 1)
  eq(shown()[1]:match("edited") ~= nil, true)
end

T["undo"] = MiniTest.new_set()

T["undo"]["brings back toggle, delete, picker and prune removals in order"] = function()
  fixture()
  child.lua([[vim.fn.confirm = function() return 1 end]])
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.cmd("Hiraishin toggle") -- ret
  child.cmd("Hiraishin delete hello")
  eq(names(), { "-" })
  child.cmd("Hiraishin undo")
  eq(names(), { "hello", "-" })
  child.cmd("Hiraishin undo")
  eq(names(), { "hello", "ret", "-" })
  child.cmd("Hiraishin undo")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Nothing to undo")
end

T["undo"]["skips a line that has a kunai again and frees a taken seal"] = function()
  fixture()
  child.cmd("Hiraishin delete hello")
  place(3, "newcomer")
  child.lua([[vim.notify = function() end]])
  child.cmd("Hiraishin undo")
  eq(child.lua_get([[require("hiraishin.ui").last()]]):match("Restored 0 kunai") ~= nil, true)
  eq(child.lua_get([[require("hiraishin.ui").last()]]):match("already has a kunai") ~= nil, true)
end

T["undo"]["is limited to undo_history entries"] = function()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, undo_history = 2 })]])
  main_lua()
  for _, l in ipairs({ 1, 3, 5 }) do
    place(l)
    child.cmd("Hiraishin toggle")
  end
  eq(child.lua_get([[require("hiraishin.history").size(require("hiraishin.scope").resolve(0))]]), 2)
end

T["undo"]["survives a restart (kept in the store file)"] = function()
  main_lua()
  place(3, "keep")
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
  -- a fresh Neovim: nothing cached, the store is read from disk again
  child.lua([[require("hiraishin.store").reset(); require("hiraishin.tracker").reset()]])
  child.lua([[require("hiraishin.tracker").attach(0)]])
  child.cmd("Hiraishin undo")
  eq(child.lua_get([[require("hiraishin").get("keep").line]]), 3)
  child.lua([[require("hiraishin.store").flush()]])
  local trash = child.lua_get([[(function()
    local ctx = require("hiraishin.scope").resolve(0)
    return vim.json.decode(table.concat(vim.fn.readfile(ctx.store), "\n")).trash
  end)()]])
  eq(#trash, 0) -- undone entries leave the file
end

T["undo"]["is per project"] = function()
  main_lua()
  place(3, "a")
  child.cmd("Hiraishin toggle")
  child.edit(child.T("proj_b") .. "/app.go", 1)
  child.cmd("Hiraishin undo")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Nothing to undo")
end

T["look"] = MiniTest.new_set()

T["look"]["a winbar header lines up with the columns"] = function()
  main_lua()
  place(3, "hello")
  child.cmd("Hiraishin manager")
  local bar = child.lua_get("vim.wo.winbar"):gsub("^%%#[%w]+#", "")
  local line = lines()[1]
  eq(bar:find("│", 1, true), line:find("│", 1, true))
  local _, second = line:find("│", line:find("│", 1, true) + 1, true)
  local _, bar_second = bar:find("│", bar:find("│", 1, true) + 1, true)
  eq(bar_second, second)
  eq(vim.startswith(bar, "# │ name "), true)
end

T["look"]["columns are highlighted, stale kunai marked"] = function()
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { slot = 2 })]])
  child.cmd("Hiraishin manager")
  local groups = child.lua_get([[vim.tbl_map(function(m) return m[4].hl_group end,
    vim.api.nvim_buf_get_extmarks(0, require("hiraishin.manager").hl_ns, 0, -1, { details = true }))]])
  table.sort(groups)
  eq(groups, {
    "HiraishinManagerPath",
    "HiraishinManagerSep",
    "HiraishinManagerSep",
    "HiraishinManagerSep",
    "HiraishinManagerSlot",
  })
  -- edits are re-highlighted
  set_lines({ "- │ x │ src/main.lua:3 ! │ /" .. lines()[1]:match("/(%x+)$") })
  child.lua([[vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })]])
  groups = child.lua_get([[vim.tbl_map(function(m) return m[4].hl_group end,
    vim.api.nvim_buf_get_extmarks(0, require("hiraishin.manager").hl_ns, 0, -1, { details = true }))]])
  eq(vim.tbl_contains(groups, "HiraishinSignStale"), true)
end

T["look"]["the title shows unsaved edits"] = function()
  main_lua()
  place(3, "hello")
  child.cmd("Hiraishin manager")
  local function title()
    return child.lua_get("vim.api.nvim_win_get_config(0).title[1][1]")
  end
  eq(title():find("●", 1, true), nil)
  child.type_keys("dd")
  eq(title():find("●", 1, true) ~= nil, true)
  child.cmd("write")
  eq(title():find("●", 1, true), nil)
end

T["look"]["an empty list says so in the winbar"] = function()
  main_lua()
  child.cmd("Hiraishin manager")
  eq(child.lua_get("vim.wo.winbar"):find("No kunai in this list", 1, true) ~= nil, true)
end

return T
