local H = dofile("tests/helpers.lua")
local eq = H.eq

local child = H.new_child()
local tmp

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = H.tmpdir()
      child.setup(tmp)
      child.lua([[
        _G.events = {}
        vim.api.nvim_create_autocmd("User", {
          pattern = { "HiraishinMoved", "HiraishinStale", "HiraishinRemove" },
          callback = function(ev)
            table.insert(_G.events, { ev.match, ev.data.reason or ev.data.method })
          end,
        })
      ]])
    end,
    post_once = child.stop,
  },
})

local MAIN = "/src/main.lua"

local function main_lua(line)
  child.edit(child.T("proj_a") .. MAIN, line)
end

local function lines_above(n)
  local new = {}
  for i = 1, n do
    new[i] = "-- inserted " .. i
  end
  child.api.nvim_buf_set_lines(0, 0, 0, false, new)
end

local function kunai(name)
  return child.lua_get("require('hiraishin').get(...)", { name })
end

-- what is persisted (flushes first)
local function stored(name)
  return child.lua_get(
    [[(function(name)
      require("hiraishin.store").flush()
      local ctx = require("hiraishin.scope").for_path(T.proj_a .. "/src/main.lua")
      local data = vim.json.decode(table.concat(vim.fn.readfile(ctx.store), "\n"))
      for _, bm in pairs(data.lists.default.bookmarks) do
        if bm.name == name then return bm end
      end
    end)(...)]],
    { name }
  )
end

local function write_disk(lines)
  child.lua("vim.fn.writefile(..., T.proj_a .. '/src/main.lua')", { lines })
end

local function events()
  return child.lua_get("_G.events")
end

T["while editing"] = MiniTest.new_set()

T["while editing"]["kunai follow lines inserted above"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  lines_above(2)
  eq(kunai("hello").line, 5)
  eq(child.signs(), { ["5"] = "⚡" })
end

T["while editing"]["toggle finds a kunai at its live line"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add()]])
  lines_above(2)
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  eq(child.lua_get([[select(2, require("hiraishin").toggle())]]), "removed")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["while editing"]["Enter at column 0 and O keep the kunai on its text"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.type_keys("0", "i", "<CR>", "<Esc>")
  eq(kunai("hello").line, 4)
  child.type_keys("O", "above", "<Esc>")
  eq(kunai("hello").line, 5)
  eq(child.api.nvim_buf_get_lines(0, 4, 5, false)[1], "function M.hello()")
end

T["while editing"]["cc keeps the kunai, dd makes it stale, u restores it"] = function()
  main_lua(4)
  child.lua([[require("hiraishin").add({ name = "ret" })]])
  child.type_keys("c", "c", "return 2", "<Esc>")
  eq(kunai("ret").stale, false)
  eq(kunai("ret").line, 4)
  child.type_keys("d", "d")
  eq(kunai("ret").stale, true)
  eq(child.signs(), {})
  child.type_keys("u")
  eq(kunai("ret").stale, false)
  eq(child.signs(), { ["4"] = "⚡" })
end

T["on write"] = MiniTest.new_set()

T["on write"]["persists live positions and fresh anchors"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  lines_above(2)
  eq(stored("hello").line, 3) -- unsaved edits never reach the store
  child.cmd("write")
  local bm = stored("hello")
  eq(bm.line, 5)
  eq(bm.anchor.before, "local M = {}")
  eq(events(), { { "HiraishinMoved", "edit" } })
end

T["on write"]["a deleted line is saved as stale, with the last known line"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write")
  child.type_keys("d", "d")
  child.cmd("write")
  local bm = stored("hello")
  eq(bm.stale, true)
  eq(bm.line, 3)
  eq(events(), { { "HiraishinStale", nil } })
end

T["on write"]["undo then write clears the stale flag"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.type_keys("d", "d")
  child.cmd("write")
  child.type_keys("u")
  child.cmd("write")
  eq(stored("hello").stale, false)
  eq(stored("hello").line, 3)
end

T["on write"]["a stale kunai comes back when its text is restored"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.type_keys("d", "d")
  child.cmd("write")
  -- type the line back somewhere else
  child.api.nvim_buf_set_lines(0, 5, 5, false, { "function M.hello()" })
  child.cmd("write")
  eq(stored("hello").stale, false)
  eq(stored("hello").line, 6)
  eq(child.signs(), { ["6"] = "⚡" })
end

T[":e! restores the saved positions"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write")
  lines_above(4)
  eq(kunai("hello").line, 7)
  child.cmd("edit!")
  eq(kunai("hello").line, 3)
  eq(child.signs(), { ["3"] = "⚡" })
end

T["external changes"] = MiniTest.new_set()

T["external changes"]["re-anchor when the file is read again"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write")
  write_disk({
    "-- license",
    "-- header",
    "local M = {}",
    "",
    "function M.hello()",
    "  return 1",
    "end",
    "",
    "return M",
  })
  child.cmd("checktime")
  child.cmd("edit")
  eq(kunai("hello").line, 5)
  eq(child.signs(), { ["5"] = "⚡" })
  eq(stored("hello").line, 5)
  eq(events(), { { "HiraishinMoved", "reanchor" } })
end

T["external changes"]["re-anchor when a closed file is opened"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write | bwipeout")
  write_disk({ "-- new header", "", "local M = {}", "", "function M.hello()", "  return 1", "end" })
  main_lua()
  eq(kunai("hello").line, 5)
end

T["external changes"]["missing line marks the kunai stale with a ! sign"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write | bwipeout")
  write_disk({ "local M = {}", "", "-- hello is gone", "", "return M" })
  main_lua()
  local bm = kunai("hello")
  eq(bm.stale, true)
  eq(bm.line, 3)
  eq(child.signs(), { ["3"] = "!" })
  eq(events(), { { "HiraishinStale", nil } })
end

T["external changes"]["git checkout of an edited file puts kunai back"] = function()
  local root = child.T("proj_a")
  local function git(args)
    return child.lua_get("vim.fn.system(...)", { vim.list_extend({ "git", "-C", root }, args) })
  end
  git({ "init", "-q" })
  git({ "-c", "user.email=t@t", "-c", "user.name=t", "add", "." })
  git({ "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init" })

  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write")
  lines_above(3)
  child.cmd("write")
  eq(stored("hello").line, 6)

  git({ "checkout", "--", "src/main.lua" })
  child.cmd("checktime")
  child.cmd("edit")
  eq(kunai("hello").line, 3)
  eq(stored("hello").line, 3)
  eq(child.signs(), { ["3"] = "⚡" })
end

T["external changes"]["a kunai whose file was deleted is stale"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.lua([[require("hiraishin.store").flush()]])
  child.lua([[vim.fn.delete(T.proj_a .. "/src/main.lua")]])
  child.setup(tmp)
  child.lua([[vim.fn.chdir(T.proj_a)]])
  eq(kunai("hello").stale, true)
end

T["renames"] = MiniTest.new_set()

T["renames"][":saveas carries kunai to the new name"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  lines_above(1)
  child.lua([[vim.cmd.saveas(T.proj_a .. "/src/renamed.lua")]])
  local bm = kunai("hello")
  eq(bm.file, "src/renamed.lua")
  eq(bm.line, 4)
  eq(child.signs(), { ["4"] = "⚡" })
end

T["renames"]["rename() moves a whole directory"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write | bwipeout")
  child.lua([[vim.fn.chdir(T.proj_a)]])
  child.lua([[
    vim.uv.fs_rename(T.proj_a .. "/src", T.proj_a .. "/lib")
    require("hiraishin").rename(T.proj_a .. "/src", T.proj_a .. "/lib")
  ]])
  eq(kunai("hello").file, "lib/main.lua")
  eq(kunai("hello").stale, false)
end

T["renames"]["oil.nvim and mini.files events are followed"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write | bwipeout")
  child.lua([[vim.fn.chdir(T.proj_a)]])
  child.lua([[
    vim.uv.fs_rename(T.proj_a .. "/src/main.lua", T.proj_a .. "/src/oil.lua")
    vim.api.nvim_exec_autocmds("User", { pattern = "OilActionsPost", data = { actions = {
      { type = "move", entry_type = "file", src_url = "oil://" .. T.proj_a .. "/src/main.lua", dest_url = "oil://" .. T.proj_a .. "/src/oil.lua" },
    } } })
  ]])
  eq(kunai("hello").file, "src/oil.lua")
  child.lua([[
    vim.uv.fs_rename(T.proj_a .. "/src/oil.lua", T.proj_a .. "/src/mini.lua")
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniFilesActionRename",
      data = { action = "rename", from = T.proj_a .. "/src/oil.lua", to = T.proj_a .. "/src/mini.lua" } })
  ]])
  eq(kunai("hello").file, "src/mini.lua")
end

T["renames"]["moving into another project moves the kunai to its store"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.cmd("write | bwipeout")
  child.lua([[
    vim.uv.fs_rename(T.proj_a .. "/src/main.lua", T.proj_b .. "/main.lua")
    require("hiraishin").rename(T.proj_a .. "/src/main.lua", T.proj_b .. "/main.lua")
    vim.fn.chdir(T.proj_a)
  ]])
  eq(kunai("hello"), vim.NIL) -- gone from proj_a
  child.edit(child.T("proj_b") .. "/main.lua")
  eq(kunai("hello").file, "main.lua")
  eq(child.signs(), { ["3"] = "⚡" })
end

T["relocate and prune"] = MiniTest.new_set()

local function make_stale()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.type_keys("d", "d")
  child.cmd("write")
  eq(kunai("hello").stale, true)
end

T["relocate and prune"][":Hiraishin relocate re-attaches the only stale kunai"] = function()
  make_stale()
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.cmd("Hiraishin relocate")
  local bm = kunai("hello")
  eq({ bm.line, bm.stale }, { 5, false })
  eq(bm.anchor.text, child.api.nvim_buf_get_lines(0, 4, 5, false)[1]:gsub("^%s+", ""))
  eq(child.signs(), { ["5"] = "⚡" })
end

T["relocate and prune"]["relocate by name moves a live kunai too"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "top" })]])
  child.api.nvim_win_set_cursor(0, { 6, 0 })
  child.cmd("Hiraishin relocate top")
  eq(kunai("top").line, 6)
  eq(child.signs(), { ["6"] = "⚡" })
  lines_above(1)
  eq(kunai("top").line, 7) -- tracked at the new line
end

T["relocate and prune"]["relocate refuses an occupied line"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "a" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua([[require("hiraishin").add({ name = "b" })]])
  eq(child.lua_get([[select(2, require("hiraishin").relocate("a"))]]), "Another kunai already marks this line")
end

T["relocate and prune"][":Hiraishin prune removes stale kunai and can be undone"] = function()
  make_stale()
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").add({ name = "keep" })]])
  child.cmd("Hiraishin prune")
  local names = child.lua_get([[vim.tbl_map(function(b) return b.name end, require("hiraishin").list())]])
  eq(names, { "keep" })
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Removed 1 stale kunai · <leader>hu to undo")
  child.cmd("Hiraishin undo")
  eq(#child.lua_get([[require("hiraishin").list()]]), 2)
end

return T
