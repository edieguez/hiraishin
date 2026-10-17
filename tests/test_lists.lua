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
      child.lua([[vim.fn.confirm = function() return 1 end]])
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
local function git(args)
  return child.lua_get("vim.fn.system(...)", { vim.list_extend({ "git", "-C", child.T("proj_a") }, args) })
end
local function git_init()
  git({ "init", "-q", "-b", "main" })
  git({ "-c", "user.email=t@t", "-c", "user.name=t", "add", "." })
  git({ "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init" })
end

T["lists"] = MiniTest.new_set()

T["lists"]["set_list creates and switches; kunai and seals are per list"] = function()
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { slot = 1 })]])
  child.lua([[require("hiraishin").set_list("bug-1234")]])
  eq(names(), {})
  eq(child.signs(), {}) -- the default list's sign is hidden
  place(5, "fix")
  child.lua([[require("hiraishin").seal(1)]])
  eq(child.signs(), { ["5"] = "1" })
  eq(
    child.lua_get([[{ require("hiraishin").lists() }]]),
    { { "bug-1234", "default" }, "bug-1234", { ["bug-1234"] = 1, default = 1 } }
  )
  child.lua([[require("hiraishin").set_list("default")]])
  eq(names(), { "hello" })
  eq(child.signs(), { ["3"] = "1" })
  child.lua([[require("hiraishin").jump(1)]])
  eq(child.api.nvim_win_get_cursor(0)[1], 3)
end

T["lists"]["kunai of other lists keep tracking edits"] = function()
  main_lua()
  child.lua([[require("hiraishin").set_list("other")]])
  place(3, "hello")
  child.lua([[require("hiraishin").set_list("default")]])
  child.api.nvim_buf_set_lines(0, 0, 0, false, { "-- a", "-- b" })
  child.cmd("write")
  child.lua([[require("hiraishin").set_list("other")]])
  eq(child.lua_get([[require("hiraishin").get("hello").line]]), 5)
end

T["lists"]["the active list persists"] = function()
  main_lua()
  child.lua([[require("hiraishin").set_list("feature")]])
  child.lua([[require("hiraishin.store").flush()]])
  child.setup(tmp)
  child.lua([[vim.fn.chdir(T.proj_a)]])
  eq(child.lua_get([[select(2, require("hiraishin").lists())]]), "feature")
end

T["lists"]["delete_list falls back to default and undo brings its kunai back"] = function()
  main_lua()
  child.lua([[require("hiraishin").set_list("temp")]])
  place(3, "hello")
  child.cmd("Hiraishin list delete temp")
  eq(child.lua_get([[{ require("hiraishin").lists() }]]), { { "default" }, "default", { default = 0 } })
  eq(child.lua_get([[select(2, require("hiraishin").delete_list("default"))]]), "The default list cannot be deleted")
  child.cmd("Hiraishin undo")
  child.lua([[require("hiraishin").set_list("temp")]])
  eq(names(), { "hello" })
end

T["lists"][":Hiraishin list shows a chooser with a new-list entry"] = function()
  main_lua(1)
  child.lua([[
    vim.ui.select = function(items, opts, cb)
      _G.items = vim.tbl_map(opts.format_item, items)
      cb(items[#items])
    end
    vim.ui.input = function(_, cb) cb("fresh") end
  ]])
  child.cmd("Hiraishin list")
  eq(child.lua_get("_G.items"), { "default (0)  ● active", "+ New list…" })
  eq(child.lua_get([[select(2, require("hiraishin").lists())]]), "fresh")
end

T["lists"]["HiraishinListChanged fires"] = function()
  main_lua(1)
  child.lua([[
    _G.ev = nil
    vim.api.nvim_create_autocmd("User", { pattern = "HiraishinListChanged", callback = function(e) _G.ev = e.data end })
    require("hiraishin").set_list("x")
  ]])
  eq(child.lua_get("_G.ev.list"), "x")
  eq(child.lua_get("_G.ev.previous"), "default")
end

T["scope"] = MiniTest.new_set()

T["scope"][":Hiraishin scope switches stores for the session"] = function()
  main_lua()
  place(3, "project-one")
  child.cmd("Hiraishin scope global")
  eq(names(), {})
  place(4, "global-one")
  eq(child.lua_get([[require("hiraishin").get("global-one").file]]), child.T("proj_a") .. "/src/main.lua")
  child.cmd("Hiraishin scope project")
  eq(names(), { "project-one" })
end

T["scope"]["branch scope forks the project kunai on the first change"] = function()
  git_init()
  main_lua()
  place(3, "shared")
  child.lua([[require("hiraishin.store").flush()]])
  child.cmd("Hiraishin scope branch")
  eq(names(), { "shared" }) -- read from the project file until a change
  local store = child.lua_get([[require("hiraishin.scope").for_buf(0).store]])
  eq(store:match("@main%.json$") ~= nil, true)
  eq(child.lua_get("vim.uv.fs_stat(...) == nil", { store }), true)
  place(5, "on-main")
  child.lua([[require("hiraishin.store").flush()]])
  eq(child.lua_get("vim.uv.fs_stat(...) ~= nil", { store }), true)
  child.cmd("Hiraishin scope project")
  eq(names(), { "shared" }) -- the project file is untouched
end

T["scope"]["switching branches swaps the kunai on focus"] = function()
  git_init()
  child.lua(
    [[require("hiraishin").setup({ scope = "branch", storage = { dir = T.storage, debounce_ms = 0 }, signs = { style = "emoji" } })]]
  )
  main_lua()
  place(3, "on-main")
  git({ "checkout", "-q", "-b", "feature" })
  child.lua([[vim.api.nvim_exec_autocmds("FocusGained", {})]])
  eq(child.lua_get([[require("hiraishin.scope").for_buf(0).branch]]), "feature")
  -- a new branch starts from the project file (empty here: on-main lives in @main)
  eq(names(), {})
  place(5, "on-feature")
  git({ "checkout", "-q", "main" })
  child.lua([[vim.api.nvim_exec_autocmds("FocusGained", {})]])
  eq(names(), { "on-main" })
  eq(child.signs(), { ["3"] = "⚡" })
end

T["scope"]["git_branch reads HEAD, worktrees and detached heads"] = function()
  git_init()
  eq(child.lua_get([[require("hiraishin.scope").git_branch(T.proj_a)]]), "main")
  git({ "checkout", "-q", "--detach" })
  eq(child.lua_get([[require("hiraishin.scope").git_branch(T.proj_a)]]), vim.NIL)
  git({ "checkout", "-q", "main" })
  git({ "worktree", "add", "-q", "-b", "wt", child.T("tmp") .. "/wt" })
  eq(child.lua_get([[require("hiraishin.scope").git_branch(T.tmp .. "/wt")]]), "wt")
end

T["refresh"] = function()
  main_lua()
  place(3, "mine")
  child.lua([[require("hiraishin.store").flush()]])
  -- another Neovim adds a kunai to the same store
  child.lua([[
    local path = require("hiraishin.scope").for_buf(0).store
    local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    data.lists.default.bookmarks.ffffffff = { file = "src/main.lua", line = 5, col = 0, name = "theirs",
      anchor = { text = "end" }, created_at = 1, updated_at = 1 }
    table.insert(data.lists.default.order, "ffffffff")
    vim.wait(20)
    vim.fn.writefile({ vim.json.encode(data) }, path)
  ]])
  child.lua([[vim.api.nvim_exec_autocmds("FocusGained", {})]])
  eq(names(), { "mine", "theirs" })
  eq(child.signs(), { ["3"] = "⚡", ["5"] = "⚡" })
end

T["status"] = MiniTest.new_set()

T["status"]["counts kunai in the buffer and names a non-default list"] = function()
  main_lua()
  eq(child.lua_get([[require("hiraishin").status()]]), "")
  place(1)
  place(3)
  eq(child.lua_get([[require("hiraishin").status()]]), "⚡2")
  child.lua([[require("hiraishin").set_list("bugs")]])
  eq(child.lua_get([[require("hiraishin").status()]]), "[bugs]")
end

T["status"]["lualine component"] = function()
  main_lua()
  place(1)
  local c = child.lua_get([[(function()
    local comp = require("hiraishin.integrations.lualine")
    return { comp[1](), comp.cond(), type(comp.color()) }
  end)()]])
  eq(c, { "⚡1", true, "table" })
end

T["import marks"] = function()
  main_lua()
  child.lua([[
    vim.api.nvim_buf_set_mark(0, "A", 3, 0, {})
    vim.api.nvim_buf_set_mark(0, "B", 5, 2, {})
  ]])
  place(5, "already")
  child.cmd("Hiraishin import marks")
  eq(names(), { "already", "mark A" })
  eq(child.lua_get([[require("hiraishin").get("mark A").anchor.text]]), "function M.hello()")
end

T["checkhealth"] = function()
  main_lua(1)
  child.cmd("checkhealth hiraishin")
  local text = table.concat(child.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  eq(text:match("hiraishin%.nvim") ~= nil, true)
  eq(text:match("storage directory") ~= nil, true)
  eq(text:match("picker: select") ~= nil, true)
  eq(text:match("ERROR") == nil, true)
end

T["keymaps"] = function()
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage } })]])
  eq(child.lua_get([[vim.fn.maparg("<leader>he", "n")]]), "<Cmd>Hiraishin manager<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>hl", "n")]]), "<Cmd>Hiraishin list<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>hu", "n")]]), "<Cmd>Hiraishin undo<CR>")
end

T["help file builds tags for every command"] = function()
  child.lua([[
    local dir = T.tmp .. "/doc"
    vim.fn.mkdir(dir, "p")
    local repo = HIRAISHIN_DEPS:gsub("/deps$", "")
    vim.fn.writefile(vim.fn.readfile(repo .. "/doc/hiraishin.txt"), dir .. "/hiraishin.txt")
  ]])
  child.cmd("helptags " .. child.T("tmp") .. "/doc")
  local tags = table.concat(child.lua_get([[vim.fn.readfile(T.tmp .. "/doc/tags")]]), "\n")
  for _, sub in ipairs(child.lua_get([[vim.tbl_keys(require("hiraishin.commands").subcommands)]])) do
    eq({ sub, tags:match(":Hiraishin%-" .. sub .. "\t") ~= nil }, { sub, true })
  end
end

return T
