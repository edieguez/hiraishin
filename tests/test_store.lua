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

T["config"] = MiniTest.new_set()

T["config"]["setup() and setup({}) keep the defaults"] = function()
  child.lua([[require("hiraishin").setup()]])
  eq(child.lua_get([[require("hiraishin.config").options.scope]]), "project")
  child.lua([[require("hiraishin").setup({})]])
  eq(
    child.lua_get([[require("hiraishin.config").options]]),
    child.lua_get([[(function()
    local d = vim.deepcopy(require("hiraishin.config").defaults)
    d.storage.dir = vim.fs.normalize(d.storage.dir)
    return d
  end)()]])
  )
end

T["config"]["empty nested tables keep the defaults"] = function()
  child.lua([[require("hiraishin").setup({ signs = {}, root = {} })]])
  eq(child.lua_get([[require("hiraishin.config").options.signs.icon]]), "⚡")
  eq(child.lua_get([[require("hiraishin.config").options.root.markers]]), { ".git", ".hiraishin" })
end

T["config"]["works with lazy.nvim style opts = {}"] = function()
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.lua([[require("hiraishin").setup({})]])
  eq(child.lua_get([[vim.fn.exists(":Hiraishin")]]), 2)
  eq(child.lua_get([[vim.fn.maparg("\\hh", "n")]]), "<Cmd>Hiraishin toggle<CR>")
end

T["config"]["replaces lists instead of merging them by index"] = function()
  child.lua([[require("hiraishin").setup({ root = { markers = { ".svn" } }, storage = { dir = T.storage } })]])
  eq(child.lua_get([[require("hiraishin.config").options.root.markers]]), { ".svn" })
end

T["config"]["rejects an invalid scope"] = function()
  expect.error(function()
    child.lua([[require("hiraishin").setup({ scope = "everywhere" })]])
  end, "scope")
end

T["config"]["rejects a wrong type"] = function()
  expect.error(function()
    child.lua([[require("hiraishin").setup({ signs = { priority = "high" } })]])
  end, "signs.priority")
end

T["config"]["records unknown keys"] = function()
  child.lua([[vim.notify = function() end]])
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage }, signz = true })]])
  eq(child.lua_get([[require("hiraishin.config").unknown]]), { "signz" })
end

T["root"] = MiniTest.new_set()

T["root"][".git directory marks the root"] = function()
  local root = child.lua_get([[require("hiraishin.scope").find_root(T.proj_a .. "/src/main.lua")]])
  eq(root, child.T("proj_a"))
end

T["root"][".hiraishin file marks the root"] = function()
  local root = child.lua_get([[require("hiraishin.scope").find_root(T.proj_b .. "/app.go")]])
  eq(root, child.T("proj_b"))
end

T["root"]["falls back to the working directory"] = function()
  child.lua([[vim.fn.chdir(T.loose)]])
  -- the loose dir lives under the temp dir, which has no markers above it
  local root = child.lua_get([[require("hiraishin.scope").find_root(T.loose .. "/notes.txt")]])
  local found = child.lua_get([[vim.fs.root(T.loose, { ".git", ".hiraishin" })]])
  if found == vim.NIL then
    eq(root, child.T("loose"))
  end
end

T["root"]["root.fn overrides markers"] = function()
  child.lua([[require("hiraishin").setup({
    storage = { dir = T.storage },
    root = { fn = function() return T.proj_b end },
  })]])
  eq(child.lua_get([[require("hiraishin.scope").find_root(T.proj_a .. "/src/main.lua")]]), child.T("proj_b"))
end

T["store"] = MiniTest.new_set()

T["store"]["file name is readable and unique per root"] = function()
  local a = child.lua_get([[require("hiraishin.scope").for_path(T.proj_a .. "/src/main.lua").store]])
  local b = child.lua_get([[require("hiraishin.scope").for_path(T.proj_b .. "/app.go").store]])
  expect.no_equality(a, b)
  eq(a:match("/projects/.*proj_a__%x%x%x%x%x%x%x%x%.json$") ~= nil, true)
  eq(b:match("/projects/.*proj_b__%x%x%x%x%x%x%x%x%.json$") ~= nil, true)
end

T["store"]["writes JSON with relative paths and anchors"] = function()
  child.edit(child.T("proj_a") .. "/src/main.lua", 3)
  child.lua([[require("hiraishin").add({ name = "hello" })]])
  local data = child.lua_get([[(function()
    local ctx = require("hiraishin.scope").for_buf(0)
    return vim.json.decode(table.concat(vim.fn.readfile(ctx.store), "\n"))
  end)()]])
  eq(data.version, 1)
  eq(data.root, child.T("proj_a"))
  eq(data.active_list, "default")
  local id = data.lists.default.order[1]
  local bm = data.lists.default.bookmarks[id]
  eq(bm.file, "src/main.lua")
  eq(bm.line, 3)
  eq(bm.name, "hello")
  eq(bm.anchor, { text = "function M.hello()", before = "local M = {}", after = "return 1" })
end

T["store"]["leaves no temp file behind"] = function()
  child.edit(child.T("proj_a") .. "/src/main.lua", 1)
  child.lua([[require("hiraishin").toggle()]])
  local files = child.lua_get([[vim.fn.readdir(T.storage .. "/projects")]])
  eq(#files, 1)
  eq(files[1]:match("%.tmp$"), nil)
end

T["store"]["debounces writes until flush"] = function()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 60000 } })]])
  child.edit(child.T("proj_a") .. "/src/main.lua", 1)
  child.lua([[require("hiraishin").toggle()]])
  eq(child.lua_get([[vim.fn.isdirectory(T.storage .. "/projects")]]), 0)
  child.lua([[require("hiraishin.store").flush()]])
  eq(#child.lua_get([[vim.fn.readdir(T.storage .. "/projects")]]), 1)
end

T["store"]["moves a corrupt file aside and starts fresh"] = function()
  child.lua([[
    _G.warnings = {}
    vim.notify = function(msg, level) table.insert(_G.warnings, { msg, level }) end
    local ctx = require("hiraishin.scope").for_path(T.proj_a .. "/src/main.lua")
    vim.fn.mkdir(vim.fs.dirname(ctx.store), "p")
    vim.fn.writefile({ "{ not json" }, ctx.store)
  ]])
  child.edit(child.T("proj_a") .. "/src/main.lua", 1)
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
  local files = child.lua_get([[vim.fn.readdir(T.storage .. "/projects")]])
  eq(#files, 1)
  eq(files[1]:match("%.corrupt%-%d+$") ~= nil, true)
  local warnings = child.lua_get("_G.warnings")
  eq(#warnings, 1)
  eq(warnings[1][1]:match("could not read") ~= nil, true)
end

T["store"]["repairs order and drops dangling slots on load"] = function()
  child.lua([[
    local ctx = require("hiraishin.scope").for_path(T.proj_a .. "/src/main.lua")
    vim.fn.mkdir(vim.fs.dirname(ctx.store), "p")
    vim.fn.writefile({ vim.json.encode({
      version = 1,
      lists = { default = {
        order = { "aaaaaaaa", "gone0000" },
        slots = { ["1"] = "gone0000", ["2"] = "bbbbbbbb" },
        bookmarks = {
          aaaaaaaa = { file = "src/main.lua", line = 1, col = 0, anchor = { text = "" }, created_at = 1 },
          bbbbbbbb = { file = "src/main.lua", line = 3, col = 0, anchor = { text = "" }, created_at = 2 },
        },
      } },
    }) }, ctx.store)
  ]])
  child.edit(child.T("proj_a") .. "/src/main.lua", 1)
  local ids = child.lua_get([[vim.tbl_map(function(b) return b.id end, require("hiraishin").list())]])
  eq(ids, { "aaaaaaaa", "bbbbbbbb" })
  eq(
    child.lua_get([[require("hiraishin.store").get(require("hiraishin.scope").for_buf(0)).lists.default.slots]]),
    { ["2"] = "bbbbbbbb" }
  )
end

T["store"]["global scope uses one file with absolute paths"] = function()
  child.lua([[require("hiraishin").setup({ scope = "global", storage = { dir = T.storage } })]])
  child.edit(child.T("proj_a") .. "/src/main.lua", 1)
  child.lua([[require("hiraishin").toggle()]])
  child.edit(child.T("proj_b") .. "/app.go", 1)
  child.lua([[require("hiraishin").toggle()]])
  child.lua([[require("hiraishin.store").flush()]])
  local data = child.lua_get([[vim.json.decode(table.concat(vim.fn.readfile(T.storage .. "/global.json"), "\n"))]])
  local files = {}
  for _, bm in pairs(data.lists.default.bookmarks) do
    table.insert(files, bm.file)
  end
  table.sort(files)
  eq(files, { child.T("proj_a") .. "/src/main.lua", child.T("proj_b") .. "/app.go" })
end

return T
