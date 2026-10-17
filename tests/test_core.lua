local H = dofile("tests/helpers.lua")
local eq, expect = H.eq, H.expect

local child = H.new_child()
local tmp

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = H.tmpdir()
      child.setup(tmp)
    end,
    post_once = child.stop,
  },
})

local function main_lua(line)
  child.edit(child.T("proj_a") .. "/src/main.lua", line)
end

T["toggle"] = MiniTest.new_set()

T["toggle"]["adds then removes a bookmark on the cursor line"] = function()
  main_lua(3)
  eq(child.lua_get([[select(2, require("hiraishin").toggle())]]), "added")
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
  eq(child.signs(), { ["3"] = "⚡" })

  eq(child.lua_get([[select(2, require("hiraishin").toggle())]]), "removed")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
  eq(child.signs(), {})
end

T["toggle"]["refuses non-file buffers"] = function()
  child.cmd("enew")
  child.lua([[vim.bo.buftype = "nofile"]])
  eq(child.lua_get([[select(3, require("hiraishin").toggle())]]), "Not a file buffer")
end

T["add"] = MiniTest.new_set()

T["add"]["stores name, note and position"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = " hello ", note = "entry point" })]])
  local bm = child.lua_get([[require("hiraishin").get("hello")]])
  eq(bm.name, "hello")
  eq(bm.note, "entry point")
  eq(bm.file, "src/main.lua")
  eq(bm.line, 3)
  eq(bm.stale, false)
  eq(#bm.id, 8)
end

T["add"]["rejects a duplicate name"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "dup" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  local res = child.lua_get([[{ require("hiraishin").add({ name = "dup" }) }]])
  eq(res[1], vim.NIL)
  eq(res[2], "A kunai named 'dup' already exists")
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
end

T["add"]["on an occupied line names the existing bookmark"] = function()
  main_lua(3)
  local first = child.lua_get([[require("hiraishin").add().id]])
  local res = child.lua_get([[{ require("hiraishin").add({ name = "later" }) }]])
  eq(res[1].id, first)
  eq(res[1].name, "later")
  eq(res[2], "exists")
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
end

T["add"]["works on a buffer in another window via bufnr + line"] = function()
  main_lua(1)
  local buf = child.api.nvim_get_current_buf()
  child.cmd("enew")
  child.lua([[require("hiraishin").add({ bufnr = ..., line = 5 })]], { buf })
  eq(child.lua_get([[require("hiraishin").list({ bufnr = ... })[1].line]], { buf }), 5)
end

T["add"]["rejects a line out of range"] = function()
  main_lua(1)
  eq(child.lua_get([[select(2, require("hiraishin").add({ bufnr = 0, line = 99 }))]]), "Line out of range")
end

T["remove / update"] = MiniTest.new_set()

T["remove / update"]["removes by name and by id"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "one" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  local id = child.lua_get([[require("hiraishin").add().id]])
  child.lua([[require("hiraishin").remove("one")]])
  child.lua([[require("hiraishin").remove(...)]], { id })
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
  eq(child.lua_get([[select(2, require("hiraishin").remove("one"))]]), "No kunai 'one'")
end

T["remove / update"]["frees the slot of a removed bookmark"] = function()
  main_lua(1)
  local id = child.lua_get([[require("hiraishin").add().id]])
  child.lua(
    [[local s = require("hiraishin.store").get(require("hiraishin.scope").for_buf(0))
      s.lists.default.slots["1"] = ...
      require("hiraishin.tracker").render(0 + vim.api.nvim_get_current_buf())]],
    { id }
  )
  eq(child.signs(), { ["1"] = "1" })
  child.lua([[require("hiraishin").toggle()]])
  eq(child.lua_get([[require("hiraishin.store").get(require("hiraishin.scope").for_buf(0)).lists.default.slots]]), {})
end

T["remove / update"]["renames, clears and protects names"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "a" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua([[require("hiraishin").add({ name = "b", note = "n" })]])
  eq(child.lua_get([[select(2, require("hiraishin").update("a", { name = "b" }))]]), "A kunai named 'b' already exists")
  child.lua([[require("hiraishin").update("a", { name = "c" })]])
  child.lua([[require("hiraishin").update("b", { note = false })]])
  eq(child.lua_get([[require("hiraishin").get("c").line]]), 1)
  eq(child.lua_get([[require("hiraishin").get("b").note]]), vim.NIL)
end

T["events"] = function()
  child.lua([[
    _G.events = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = { "HiraishinAdd", "HiraishinRemove", "HiraishinUpdate" },
      callback = function(ev) table.insert(_G.events, { ev.match, ev.data.list, ev.data.reason }) end,
    })
  ]])
  main_lua(1)
  child.lua([[require("hiraishin").toggle()]])
  child.lua([[require("hiraishin").add({ name = "x" })]])
  child.lua([[require("hiraishin").toggle()]])
  eq(child.lua_get("_G.events"), {
    { "HiraishinAdd", "default" },
    { "HiraishinUpdate", "default" },
    { "HiraishinRemove", "default", "toggle" },
  })
end

T["persistence"] = MiniTest.new_set()

T["persistence"]["survives restarts in two separate projects"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  child.edit(child.T("proj_b") .. "/app.go", 3)
  child.lua([[require("hiraishin").add({ name = "main" })]])
  child.lua([[require("hiraishin.store").flush()]])

  child.setup(tmp)

  child.edit(child.T("proj_a") .. "/src/main.lua")
  local a = child.lua_get([[require("hiraishin").list()]])
  eq(#a, 1)
  eq({ a[1].name, a[1].file, a[1].line }, { "hello", "src/main.lua", 3 })
  eq(child.signs(), { ["3"] = "⚡" })

  child.edit(child.T("proj_b") .. "/app.go")
  local b = child.lua_get([[require("hiraishin").list()]])
  eq(#b, 1)
  eq({ b[1].name, b[1].file, b[1].line }, { "main", "app.go", 3 })
end

T["persistence"]["flushes debounced writes on exit"] = function()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 60000 } })]])
  main_lua(2)
  child.lua([[require("hiraishin").toggle()]])
  child.lua([[vim.api.nvim_exec_autocmds("VimLeavePre", {})]])
  child.setup(tmp)
  main_lua()
  eq(child.lua_get([[require("hiraishin").list()[1].line]]), 2)
end

T["persistence"]["shows signs for a file opened after startup"] = function()
  main_lua(5)
  child.lua([[require("hiraishin").toggle()]])
  child.cmd("bwipeout")
  main_lua()
  eq(child.signs(), { ["5"] = "⚡" })
end

T["commands"] = MiniTest.new_set()

T["commands"][":Hiraishin toggle / add / delete"] = function()
  main_lua(1)
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Hiraishin add my mark")
  eq(child.lua_get([[require("hiraishin").get("my mark").line]]), 3)
  child.cmd("Hiraishin delete my mark")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Hiraishin delete")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["commands"][":Hiraishin! add prompts for a name"] = function()
  main_lua(3)
  child.lua([[vim.ui.input = function(_, cb) cb("prompted") end]])
  child.cmd("Hiraishin! add")
  eq(child.lua_get([[require("hiraishin").get("prompted").line]]), 3)
end

T["commands"]["completes subcommands and names"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").add({ name = "alpha" })]])
  eq(child.lua_get([[vim.fn.getcompletion("Hiraishin ", "cmdline")]]), {
    "add",
    "delete",
    "gc",
    "global",
    "import",
    "jump",
    "list",
    "loclist",
    "manager",
    "next",
    "note",
    "pick",
    "prev",
    "prune",
    "quickfix",
    "relocate",
    "scope",
    "seal",
    "seals",
    "toggle",
    "undo",
  })
  eq(child.lua_get([[vim.fn.getcompletion("Hiraishin delete a", "cmdline")]]), { "alpha" })
end

T["keymaps"] = MiniTest.new_set()

T["commands"]["toggle removes a named kunai at once and says how to undo"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "keep" })]])
  child.lua([[vim.fn.confirm = function() error("should not ask") end]])
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Removed kunai 'keep' · <leader>hu to undo")
  child.cmd("Hiraishin toggle")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Kunai placed · 1 in this file")
end

T["commands"]["confirm_remove_named = true asks before removing a named kunai"] = function()
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, confirm_remove_named = true })]]
  )
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "keep" })]])
  child.lua([[_G.answer = 2; vim.fn.confirm = function() return _G.answer end]])
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
  child.lua([[_G.answer = 1]])
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["commands"]["toggle removes unnamed kunai without asking"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add()]])
  child.lua([[vim.fn.confirm = function() error("should not ask") end]])
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["commands"]["confirm_remove_named = false (default) skips the prompt"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").add({ name = "x" })]])
  child.lua([[vim.fn.confirm = function() error("should not ask") end]])
  child.cmd("Hiraishin toggle")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["keymaps"]["sets defaults without clobbering existing maps"] = function()
  child.lua([[
    vim.g.mapleader = " "
    vim.keymap.set("n", "<leader>hd", "<cmd>echo 'mine'<cr>")
    require("hiraishin").setup({ storage = { dir = T.storage } })
  ]])
  eq(child.lua_get([[vim.fn.maparg("<leader>hh", "n")]]), "<Cmd>Hiraishin toggle<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>ha", "n")]]), "<Cmd>Hiraishin! add<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>hd", "n")]]), "<Cmd>echo 'mine'<CR>")
end

T["keymaps"]["re-running setup never deletes the user's own maps"] = function()
  child.lua([[
    vim.g.mapleader = " "
    require("hiraishin").setup({ storage = { dir = T.storage } })
    vim.keymap.set("n", "<leader>hh", "<cmd>echo 'mine'<cr>")
    require("hiraishin").setup({ storage = { dir = T.storage }, keymaps = false })
  ]])
  eq(child.lua_get([[vim.fn.maparg("<leader>hh", "n")]]), "<Cmd>echo 'mine'<CR>")
end

T["keymaps"]["can be overridden or disabled"] = function()
  child.lua([[
    vim.g.mapleader = " "
    require("hiraishin").setup({ storage = { dir = T.storage }, keymaps = { toggle = "<leader>bb", add = false } })
  ]])
  eq(child.lua_get([[vim.fn.maparg("<leader>bb", "n")]]), "<Cmd>Hiraishin toggle<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>ha", "n")]]), "")
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage }, keymaps = false })]])
  eq(child.lua_get([[vim.fn.maparg("<leader>bb", "n")]]), "")
  eq(child.lua_get([[vim.fn.maparg("<leader>hh", "n")]]), "")
end

T["regressions"] = MiniTest.new_set()

T["regressions"]["naming a placed kunai draws its name once (bufnr 0 was tracked twice)"] = function()
  main_lua(3)
  child.lua([[vim.ui.input = function(_, cb) cb("Sample name") end]])
  child.cmd("Hiraishin toggle")
  child.cmd("Hiraishin! add")
  child.cmd("Hiraishin seal 2")
  local marks =
    child.lua_get([[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, { details = true })]])
  eq(#marks, 1)
  eq(marks[1][4].sign_text, "2 ")
  child.cmd("redraw")
  local _, n = vim.split(tostring(child.get_screenshot()), "\n")[4]:gsub("Sample name", "")
  eq(n, 1)
end

return T
