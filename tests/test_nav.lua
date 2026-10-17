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
      -- a second file in proj_a
      child.lua(
        [[vim.fn.writefile({ "alpha", "beta", "gamma", "delta", "epsilon", "zeta" }, T.proj_a .. "/src/other.lua")]]
      )
    end,
    post_once = child.stop,
  },
})

local function main_lua(line)
  child.edit(child.T("proj_a") .. "/src/main.lua", line)
end
local function other_lua(line)
  child.edit(child.T("proj_a") .. "/src/other.lua", line)
end
local function cursor()
  return child.api.nvim_win_get_cursor(0)
end
local function bufname()
  return vim.fs.basename(child.api.nvim_buf_get_name(0))
end
local function place(line, name)
  child.api.nvim_win_set_cursor(0, { line, 0 })
  return child.lua_get("require('hiraishin').add({ name = ... })", { name or vim.NIL })
end

T["seals"] = MiniTest.new_set()

T["seals"]["seal() places a kunai and shows the number as its sign"] = function()
  main_lua(3)
  child.lua([[require("hiraishin").seal(2)]])
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
  eq(child.signs(), { ["3"] = "2" })
  eq(child.lua_get([[require("hiraishin").slot_of(require("hiraishin").at_cursor().id)]]), 2)
end

T["seals"]["a taken seal moves to the new kunai"] = function()
  main_lua()
  local a = place(1, "a")
  local b = place(3, "b")
  child.lua("require('hiraishin').update(..., { slot = 1 })", { a.id })
  child.lua("require('hiraishin').update(..., { slot = 1 })", { b.id })
  eq(child.lua_get("require('hiraishin').slot_of('a')"), vim.NIL)
  eq(child.lua_get("require('hiraishin').slot_of('b')"), 1)
  eq(child.signs(), { ["1"] = "⚡", ["3"] = "1" })
end

T["seals"]["moving a kunai to another seal frees the old one"] = function()
  main_lua()
  place(1, "a")
  child.lua([[require("hiraishin").update("a", { slot = 1 })]])
  child.lua([[require("hiraishin").update("a", { slot = 4 })]])
  local slots =
    child.lua_get([[require("hiraishin.store").get(require("hiraishin.scope").for_buf(0)).lists.default.slots]])
  eq(vim.tbl_keys(slots), { "4" })
  child.lua([[require("hiraishin").update("a", { slot = false })]])
  eq(child.lua_get("require('hiraishin').slot_of('a')"), vim.NIL)
end

T["seals"]["rejects seals outside 1..9"] = function()
  main_lua(1)
  eq(child.lua_get([[select(2, require("hiraishin").seal(0))]]), "seals go from 1 to 9")
  eq(child.lua_get([[select(2, require("hiraishin").seal(10))]]), "seals go from 1 to 9")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["seals"][":Hiraishin seal / seal clear"] = function()
  main_lua(5)
  child.cmd("Hiraishin seal 7")
  eq(child.signs(), { ["5"] = "7" })
  child.cmd("Hiraishin seal clear")
  eq(child.signs(), { ["5"] = "⚡" })
end

T["jump"] = MiniTest.new_set()

T["jump"]["by seal opens the file at the kunai and <C-o> comes back"] = function()
  other_lua(4)
  child.lua([[require("hiraishin").seal(3)]])
  main_lua(2)
  child.lua([[require("hiraishin").jump(3)]])
  eq(bufname(), "other.lua")
  eq(cursor(), { 4, 0 })
  child.type_keys("<C-o>")
  eq(bufname(), "main.lua")
  eq(cursor()[1], 2)
end

T["jump"]["by name, to the live line"] = function()
  other_lua()
  place(2, "beta")
  child.api.nvim_buf_set_lines(0, 0, 0, false, { "new", "lines" })
  main_lua(1)
  child.lua([[require("hiraishin").jump("beta")]])
  eq(bufname(), "other.lua")
  eq(cursor()[1], 4)
end

T["jump"]["reports an empty seal or unknown name"] = function()
  main_lua(1)
  eq(child.lua_get([[select(2, require("hiraishin").jump(5))]]), "seal 5 is empty")
  eq(child.lua_get([[select(2, require("hiraishin").jump("nope"))]]), "no kunai 'nope'")
end

T["jump"]["reuses a window already showing the file"] = function()
  other_lua()
  place(5, "eps")
  child.cmd("vsplit")
  main_lua(1)
  local other_win = child.lua_get([[vim.fn.win_getid(2)]])
  child.lua([[require("hiraishin").jump("eps")]])
  eq(child.api.nvim_get_current_win(), other_win)
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
end

T["jump"]["opens in a split when asked"] = function()
  other_lua()
  place(5, "eps")
  main_lua(1)
  child.cmd("Hiraishin jump eps vsplit")
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  eq(bufname(), "other.lua")
end

T["jump"]["from a sidebar jumps in a normal window"] = function()
  other_lua()
  place(5, "eps")
  main_lua(1)
  child.cmd("topleft vnew")
  child.lua([[vim.bo.buftype = "nofile"]])
  local sidebar = child.api.nvim_get_current_win()
  child.lua([[require("hiraishin").jump("eps")]])
  eq(bufname(), "other.lua")
  eq(child.api.nvim_get_current_win() ~= sidebar, true)
  eq(child.lua_get("vim.bo[vim.api.nvim_win_get_buf(...)].buftype", { sidebar }), "nofile")
end

T["jump"]["warns when jumping to a stale kunai"] = function()
  main_lua()
  place(3, "hello")
  child.type_keys("d", "d")
  child.cmd("write")
  child.lua([[_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end]])
  child.lua([[require("hiraishin").jump("hello")]])
  eq(cursor()[1], 3)
  eq(child.lua_get("_G.msgs[1]"):match("is stale") ~= nil, true)
end

T["jump"]["fires HiraishinJump and records last_jump_at"] = function()
  main_lua()
  place(3, "hello")
  child.lua([[
    _G.jumped = nil
    vim.api.nvim_create_autocmd("User", { pattern = "HiraishinJump", callback = function(ev) _G.jumped = ev.data end })
  ]])
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("hello")]])
  eq(child.lua_get("_G.jumped.bookmark.name"), "hello")
  eq(child.lua_get("_G.jumped.from.line"), 1)
  eq(type(child.lua_get([[require("hiraishin").get("hello").last_jump_at]])), "number")
end

T["next / prev"] = MiniTest.new_set()

T["next / prev"]["walk the buffer by line, wrapping"] = function()
  main_lua()
  place(5)
  place(1)
  place(3)
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua([[require("hiraishin").next()]])
  eq(cursor()[1], 3)
  child.lua([[require("hiraishin").next()]])
  eq(cursor()[1], 5)
  child.lua([[require("hiraishin").next()]])
  eq(cursor()[1], 1)
  child.lua([[require("hiraishin").prev()]])
  eq(cursor()[1], 5)
end

T["next / prev"]["count and no-wrap"] = function()
  main_lua()
  place(1)
  place(3)
  place(5)
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").next({ count = 2 })]])
  eq(cursor()[1], 5)
  eq(child.lua_get([[select(2, require("hiraishin").next({ wrap = false }))]]), "no kunai below")
  eq(cursor()[1], 5)
end

T["next / prev"]["]m and [m take a count"] = function()
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  main_lua()
  place(1)
  place(3)
  place(5)
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("2", "]", "m")
  eq(cursor()[1], 5)
  child.type_keys("[", "m")
  eq(cursor()[1], 3)
end

T["next / prev"]["list order walks across files"] = function()
  main_lua()
  place(3, "m3")
  other_lua()
  place(2, "o2")
  main_lua()
  place(1, "m1")
  -- list order: m3, o2, m1
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua([[require("hiraishin").next({ scope = "list" })]])
  eq({ bufname(), cursor()[1] }, { "other.lua", 2 })
  child.lua([[require("hiraishin").next({ scope = "list" })]])
  eq({ bufname(), cursor()[1] }, { "main.lua", 1 })
  child.lua([[require("hiraishin").next({ scope = "list" })]])
  eq({ bufname(), cursor()[1] }, { "main.lua", 3 })
  child.lua([[require("hiraishin").prev({ scope = "list" })]])
  eq({ bufname(), cursor()[1] }, { "main.lua", 1 })
end

T["next / prev"]["skip stale kunai"] = function()
  main_lua()
  place(1)
  place(3, "gone")
  place(5)
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.type_keys("d", "d")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").next()]])
  eq(cursor()[1], 4) -- the kunai that was on line 5
end

T["display"] = MiniTest.new_set()

local function virt_texts()
  return child.lua_get([[(function()
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, { details = true })) do
      if m[4].virt_text then
        out[tostring(m[2] + 1)] = table.concat(vim.tbl_map(function(c) return c[1] end, m[4].virt_text))
      end
    end
    return out
  end)()]])
end

T["display"]["named kunai show their name, notes add an icon"] = function()
  main_lua()
  place(1)
  place(3, "hello")
  eq(virt_texts(), { ["3"] = "← hello" })
  child.lua([[require("hiraishin").update("hello", { note = "entry" })]])
  eq(virt_texts(), { ["3"] = "← hello ✎" })
  child.lua([[require("hiraishin").update(require("hiraishin").list()[1].id, { note = "x" })]])
  eq(virt_texts(), { ["1"] = "← ✎", ["3"] = "← hello ✎" })
  child.lua([[require("hiraishin").update("hello", { name = false, note = false })]])
  eq(virt_texts(), { ["1"] = "← ✎" })
end

T["display"]["virtual text and line highlight are configurable"] = function()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 },
    line_highlight = true, virt_text = { enabled = false } })]])
  main_lua()
  place(3, "hello")
  eq(virt_texts(), {})
  local hl = child.lua_get(
    [[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, { details = true })[1][4].line_hl_group]]
  )
  eq(hl, "HiraishinLine")
end

T["names"] = MiniTest.new_set()

T["names"]["suggests the enclosing function via Treesitter"] = function()
  main_lua(4) -- inside function M.hello()
  child.lua([[vim.treesitter.start(0, "lua")]])
  eq(child.lua_get([[require("hiraishin.names").suggest()]]), "M.hello")
end

T["names"]["falls back to the word under the cursor"] = function()
  child.edit(child.T("loose") .. "/notes.txt", 2)
  eq(child.lua_get([[require("hiraishin.names").suggest()]]), "two")
end

T["names"][":Hiraishin! add pre-fills the suggestion"] = function()
  main_lua(4)
  child.lua([[vim.treesitter.start(0, "lua")]])
  child.lua([[vim.ui.input = function(opts, cb) _G.default = opts.default; cb(opts.default) end]])
  child.cmd("Hiraishin! add")
  eq(child.lua_get("_G.default"), "M.hello")
  eq(child.lua_get([[require("hiraishin").get("M.hello").line]]), 4)
end

T["notes"] = MiniTest.new_set()

T["notes"]["edit in a float, :w saves, empty clears"] = function()
  main_lua(3)
  child.cmd("Hiraishin note")
  eq(child.lua_get([[vim.api.nvim_win_get_config(0).relative ~= ""]]), true)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "first line", "second line" })
  child.cmd("write")
  eq(child.lua_get([[vim.api.nvim_win_get_config(0).relative]]), "") -- float closed
  eq(child.lua_get([[require("hiraishin").at_cursor().note]]), "first line\nsecond line")

  child.cmd("Hiraishin note")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "first line", "second line" })
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  child.cmd("write")
  eq(child.lua_get([[require("hiraishin").at_cursor().note]]), vim.NIL)
end

T["notes"]["q closes without saving"] = function()
  main_lua(3)
  child.cmd("Hiraishin note")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })
  child.type_keys("q")
  eq(child.lua_get([[vim.api.nvim_win_get_config(0).relative]]), "")
  eq(child.lua_get([[require("hiraishin").at_cursor().note]]), vim.NIL)
end

T["keymaps"] = function()
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  main_lua(3)
  child.type_keys(" ", "h", "4")
  eq(child.signs(), { ["3"] = "4" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys(" ", "4")
  eq(cursor()[1], 3)
  for _, lhs in ipairs({ "<leader>hn", "]M", "[M", "<leader>h9", "<leader>9" }) do
    eq(child.lua_get("vim.fn.maparg(..., 'n') ~= ''", { lhs }), true)
  end
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage }, keymaps = { jump_slot = "<leader>j", assign_slot = false } })]]
  )
  eq(child.lua_get([[vim.fn.maparg("<leader>j3", "n") ~= ""]]), true)
  eq(child.lua_get([[vim.fn.maparg("<leader>3", "n")]]), "")
  eq(child.lua_get([[vim.fn.maparg("<leader>h3", "n")]]), "")
end

return T
