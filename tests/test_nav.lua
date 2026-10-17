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
  eq(child.lua_get([[select(2, require("hiraishin").seal(0))]]), "Seals go from 1 to 9")
  eq(child.lua_get([[select(2, require("hiraishin").seal(10))]]), "Seals go from 1 to 9")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["seals"][":Hiraishin seal / seal clear"] = function()
  main_lua(5)
  child.cmd("Hiraishin seal 7")
  eq(child.signs(), { ["5"] = "7" })
  child.cmd("Hiraishin seal clear")
  -- the kunai only existed for the seal: it goes too
  eq(child.signs(), {})
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Seal removed, and the kunai it made · <leader>hu to undo")
  child.cmd("Hiraishin undo")
  eq(child.signs(), { ["5"] = "7" })
end

T["seals"]["are quick jumps: a seal-only kunai goes away with its seal"] = function()
  main_lua()
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Hiraishin seal 1")
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Hiraishin seal 1") -- replaces: line 1 is left without a kunai
  eq(child.signs(), { ["3"] = "1" })
  eq(#child.lua_get([[require("hiraishin").list()]]), 1)
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Sealed as 1 · g1 jumps here")
  -- moving a kunai to another seal keeps it
  child.cmd("Hiraishin seal 2")
  eq(child.signs(), { ["3"] = "2" })
end

T["seals"]["kunai placed, named or noted on purpose keep living without a seal"] = function()
  main_lua()
  local a = place(1) -- placed with toggle/add before sealing
  child.lua("require('hiraishin').update(..., { slot = 1 })", { a.id })
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Hiraishin seal 2")
  child.lua([[require("hiraishin").update(require("hiraishin").at_cursor().id, { name = "keep" })]])
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.cmd("Hiraishin seal 3")
  child.cmd("Hiraishin add") -- placing it explicitly adopts it
  child.lua([[require("hiraishin").update("keep", { slot = false })]])
  child.lua("require('hiraishin').update(..., { slot = false })", { a.id })
  child.cmd("Hiraishin seal clear")
  eq(child.signs(), { ["1"] = "⚡", ["3"] = "⚡", ["5"] = "⚡" })
end

T["seals"]["clearing a seal in the manager drops a seal-only kunai"] = function()
  main_lua(2)
  child.cmd("Hiraishin seal 4")
  child.cmd("Hiraishin manager")
  local line = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  child.api.nvim_buf_set_lines(0, 0, 1, false, { (line:gsub("^4", "-")) })
  child.cmd("write")
  eq(#child.lua_get([[require("hiraishin").list()]]), 0)
end

T["seals"]["cycle through seals in order"] = function()
  main_lua()
  for line, n in pairs({ [6] = 1, [2] = 3, [4] = 7 }) do
    child.api.nvim_win_set_cursor(0, { line, 0 })
    child.lua("require('hiraishin').seal(...)", { n })
  end
  other_lua(1)
  local function step(dir)
    child.lua(
      dir > 0 and [[require("hiraishin").next({ scope = "seal" })]] or [[require("hiraishin").prev({ scope = "seal" })]]
    )
    return { bufname(), cursor()[1] }
  end
  eq(step(1), { "main.lua", 6 }) -- seal 1
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Seal 1 of 3")
  eq(step(1), { "main.lua", 2 }) -- seal 3
  eq(step(1), { "main.lua", 4 }) -- seal 7
  eq(step(1), { "main.lua", 6 }) -- wraps to seal 1
  eq(step(-1), { "main.lua", 4 })
  -- off a seal, cycling continues from the last seal jumped to
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(step(-1), { "main.lua", 2 })
  child.cmd("Hiraishin next seal")
  eq(cursor()[1], 4)
end

T["seals"]["cycling with no seals says how to make one"] = function()
  main_lua(1)
  eq(
    child.lua_get([[select(2, require("hiraishin").next({ scope = "seal" }))]]),
    "No seals in this list · m1 seals this line"
  )
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
  eq(child.lua_get([[select(2, require("hiraishin").jump(5))]]), "Seal 5 is empty · m5 seals this line")
  eq(child.lua_get([[select(2, require("hiraishin").jump("nope"))]]), "No kunai 'nope'")
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
  eq(child.lua_get([[select(2, require("hiraishin").next({ wrap = false }))]]), "No kunai below")
  eq(cursor()[1], 5)
end

T["next / prev"]["]k and [k take a count; ]m is left to Vim"] = function()
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  main_lua()
  place(1)
  place(3)
  place(5)
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("2", "]", "k")
  eq(cursor()[1], 5)
  child.type_keys("[", "k")
  eq(cursor()[1], 3)
  eq(child.fn.maparg("]m", "n"), "")
  eq(child.fn.maparg("]K", "n") ~= "", true)
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

local function always()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 },
    signs = { style = "emoji" }, virt_text = { show = "always" } })]])
end

T["display"]["named kunai show their name, notes add an icon"] = function()
  always()
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

local function screen_row(n)
  child.cmd("redraw")
  return vim.split(tostring(child.get_screenshot()), "\n")[n + 1]
end

T["display"]["the name is drawn exactly once through place, name, rename, note, seal"] = function()
  main_lua(2)
  child.lua([[vim.ui.input = function(_, cb) cb("Sample name") end]])
  local function once(text)
    local _, n = screen_row(2):gsub(vim.pesc(text), "")
    return n
  end
  child.cmd("Hiraishin toggle")
  child.cmd("Hiraishin! add")
  eq(once("Sample name"), 1)
  child.lua([[require("hiraishin").update("Sample name", { name = "Other" })]])
  eq({ once("Sample name"), once("Other") }, { 0, 1 })
  child.lua([[require("hiraishin").update("Other", { note = "n" })]])
  child.cmd("Hiraishin seal 3")
  child.cmd("Hiraishin seal clear")
  eq(once("Other"), 1)
  eq(#child.lua_get([[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, {})]]), 1)
end

T["display"]["unchanged kunai keep their extmark"] = function()
  always()
  main_lua()
  place(3, "hello")
  local before = child.lua_get([==[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, {})[1][1]]==])
  child.lua([[require("hiraishin.tracker").render(vim.api.nvim_get_current_buf())]])
  local after = child.lua_get([==[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").ns, 0, -1, {})[1][1]]==])
  eq(after, before)
end

T["display"]["virtual text and line highlight are configurable"] = function()
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 },
    line_highlight = true, virt_text = { enabled = false, show = "always" } })]])
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

T["names"]["no suggestion outside a symbol (never the word under the cursor)"] = function()
  child.edit(child.T("loose") .. "/notes.txt", 2)
  eq(child.lua_get([[require("hiraishin.names").suggest()]]), vim.NIL)
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
  child.type_keys("m", "4")
  eq(child.signs(), { ["3"] = "4" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("g", "4")
  eq(cursor()[1], 3)
  for _, lhs in ipairs({ "<leader>hn", "]K", "[K", "m9", "g9", "mm", "m0", "g<Space>" }) do
    eq({ lhs, child.lua_get("require('hiraishin.keymaps').is_set(...)", { lhs }) }, { lhs, true })
  end
  -- seal keys are not on the leader any more; Vim's own marks still work
  eq(child.lua_get([[vim.fn.maparg("<leader>3", "n")]]), "")
  eq(child.lua_get([[vim.fn.maparg("<leader>h3", "n")]]), "")
  child.type_keys("m", "a", "j", "'", "a") -- on line 3
  eq(cursor()[1], 3)
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage }, keymaps = { jump_slot = "<leader>j", assign_slot = false } })]]
  )
  eq(child.lua_get([[vim.fn.maparg("<leader>j3", "n") ~= ""]]), true)
  eq(child.lua_get([[vim.fn.maparg("g3", "n")]]), "")
  eq(child.lua_get([[require("hiraishin.keymaps").is_set("m3")]]), false)
end

local function cursor_virt()
  return child.lua_get([[(function()
    local out = {}
    local ns = require("hiraishin.signs").cursor_ns
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      out[tostring(m[2] + 1)] = table.concat(vim.tbl_map(function(c) return c[1] end, m[4].virt_text))
    end
    return out
  end)()]])
end

local function move(line)
  child.api.nvim_win_set_cursor(0, { line, 0 })
  child.lua([[require("hiraishin.tracker").cursor_virt(0)]])
end

T["display"]["by default the name shows only on the cursor line"] = function()
  main_lua()
  place(1, "top")
  place(3, "hello")
  eq(virt_texts(), {})
  move(3)
  eq(cursor_virt(), { ["3"] = "← hello" })
  move(1)
  eq(cursor_virt(), { ["1"] = "← top" })
  move(2)
  eq(cursor_virt(), {})
end

T["display"]["the cursor-line name follows CursorMoved"] = function()
  main_lua()
  place(3, "hello")
  child.type_keys("gg")
  eq(cursor_virt(), {})
  child.type_keys("2j")
  eq(cursor_virt(), { ["3"] = "← hello" })
end

T["display"]["sign style presets and explicit icons"] = function()
  local function icons(opts)
    child.lua(
      "require('hiraishin').setup(vim.tbl_deep_extend('force', { storage = { dir = T.storage, debounce_ms = 0 } }, ...))",
      { opts }
    )
    return child.lua_get([[{ require("hiraishin.signs").icons() }]])
  end
  eq(icons({ signs = { style = "ascii" } }), { "*", "?" })
  eq(icons({ signs = { style = "emoji" } }), { "⚡", "!" })
  eq(icons({ signs = { style = "nerd" } }), { "\u{f02e}", "\u{f097}" })
  eq(icons({ signs = { style = "ascii", icon = "B" } }), { "B", "?" })
end

T["display"]["jumping flashes the target line"] = function()
  main_lua()
  place(5, "there")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("there")]])
  local marks =
    child.lua_get([[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").flash_ns, 0, -1, { details = true })]])
  eq(#marks, 1)
  eq({ marks[1][2], marks[1][4].hl_group }, { 4, "HiraishinFlash" })
  vim.loop.sleep(600)
  eq(#child.lua_get([[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").flash_ns, 0, -1, {})]]), 0)
end

T["display"]["notes appear in a hover float"] = function()
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { note = "remember **this**" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  local win = child.lua_get([[require("hiraishin.note").hover()]])
  eq(type(win), "number")
  local text = child.lua_get(
    [[table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(...), 0, -1, false), " ")]],
    { win }
  )
  eq(text:find("remember", 1, true) ~= nil, true)
  child.lua("vim.api.nvim_win_close(..., true)", { win })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(child.lua_get([[require("hiraishin.note").hover()]]), vim.NIL)
end

T["quick seals"] = MiniTest.new_set()

T["quick seals"]["mm seals with the lowest free number"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").seal(1)]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.cmd("Hiraishin seal") -- what mm runs
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Sealed as 2 · g2 jumps here")
  child.cmd("Hiraishin seal")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Already sealed as 2 · g2 jumps here")
  eq(child.signs(), { ["1"] = "1", ["3"] = "2" })
end

T["quick seals"]["mm says when all nine are taken"] = function()
  child.lua([[local l = {} for i = 1, 12 do l[i] = "line " .. i end
    vim.fn.writefile(l, T.proj_a .. "/many.txt")]])
  child.edit(child.T("proj_a") .. "/many.txt", 1)
  for n = 1, 9 do
    child.api.nvim_win_set_cursor(0, { n, 0 })
    child.lua("require('hiraishin').seal(...)", { n })
  end
  child.api.nvim_win_set_cursor(0, { 11, 0 })
  child.lua([[_G.warned = nil; vim.notify = function(m) _G.warned = m end]])
  child.cmd("Hiraishin seal")
  eq(child.lua_get("_G.warned"), "All nine seals are taken · g<Space> to free one")
end

T["quick seals"]["the menu lists seals, jumps and clears"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").seal(1)]])
  other_lua(3)
  child.lua([[require("hiraishin").add({ name = "gamma" }); require("hiraishin").seal(3)]])
  main_lua(7)
  child.cmd("Hiraishin seals")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(#lines, 10) -- the camp, then seals 1-9
  eq(lines[1], " 0  · no camp (m0)")
  eq(lines[2]:match("^ 1  —%s+src/main.lua:1%s+local M = {}") ~= nil, true)
  eq(lines[3], " 2  ·")
  eq(lines[4]:match("^ 3  gamma%s+src/other.lua:3%s+gamma") ~= nil, true)
  child.type_keys("d", "1") -- clears seal 1 (and the kunai it made)
  eq(child.api.nvim_buf_get_lines(0, 1, 2, false)[1], " 1  ·")
  child.type_keys("3")
  eq({ bufname(), cursor()[1] }, { "other.lua", 3 })
  eq(child.lua_get([[require("hiraishin.seal_menu").current()]]), vim.NIL)
  main_lua(1)
  eq(child.signs(), {})
end

T["quick seals"]["the statusline lists the seals"] = function()
  main_lua(1)
  child.lua([[require("hiraishin").seal(2)]])
  other_lua(1)
  child.lua([[require("hiraishin").seal(5)]])
  eq(child.lua_get([[require("hiraishin").status()]]), "⚡1 · #2 5")
  local seals = child.lua_get([[require("hiraishin").seals()]])
  eq({ seals[1].seal, seals[1].here, seals[2].seal, seals[2].here }, { 2, false, 5, true })
end

T["camp"] = MiniTest.new_set()

local function camp_sign()
  return child.signs()
end

T["camp"]["m0 sets it, g0 goes there and back out"] = function()
  child.lua(
    [[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, signs = { style = "emoji" } })]]
  )
  main_lua(3)
  child.type_keys("m", "0")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Camp set · g0 comes back here from anywhere")
  eq(camp_sign(), { ["3"] = "⛺" })
  -- a detour to another file
  other_lua(5)
  child.type_keys("g", "0")
  eq({ bufname(), cursor()[1] }, { "main.lua", 3 })
  -- at camp: the same key goes back out to the detour
  child.type_keys("g", "0")
  eq({ bufname(), cursor()[1] }, { "other.lua", 5 })
  -- <BS> does the same
  child.type_keys("<BS>")
  eq({ bufname(), cursor()[1] }, { "main.lua", 3 })
  child.type_keys("<BS>")
  eq({ bufname(), cursor()[1] }, { "other.lua", 5 })
  -- walked to camp by hand: nowhere to go back to
  main_lua(3)
  child.type_keys("g", "0")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "You are at camp")
end

T["camp"]["moving camp leaves no kunai behind; placed ones stay"] = function()
  main_lua(3)
  child.cmd("Hiraishin camp")
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.cmd("Hiraishin camp")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Camp moved here · was main.lua:3")
  eq(camp_sign(), { ["5"] = "⛺" })
  -- a kunai placed on purpose survives losing the camp
  place(1, "kept")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.cmd("Hiraishin camp")
  child.api.nvim_win_set_cursor(0, { 7, 0 })
  child.cmd("Hiraishin camp")
  eq(camp_sign(), { ["1"] = "⚡", ["7"] = "⛺" })
  child.cmd("Hiraishin camp clear")
  eq(camp_sign(), { ["1"] = "⚡" })
  child.cmd("Hiraishin undo")
  eq(camp_sign(), { ["1"] = "⚡", ["7"] = "⛺" })
end

T["camp"]["is not a seal: mm skips it, the menu and statusline show it as 0"] = function()
  main_lua(3)
  child.cmd("Hiraishin camp")
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.cmd("Hiraishin seal")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "Sealed as 1 · g1 jumps here")
  eq(child.lua_get([[require("hiraishin").status()]]), "⚡2 · #0 1")
  child.cmd("Hiraishin seals")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(#lines, 10)
  eq(lines[1]:match("^ 0  —%s+src/main.lua:3") ~= nil, true)
  eq(lines[2]:match("^ 1  —%s+src/main.lua:5") ~= nil, true)
  child.type_keys("0")
  eq({ bufname(), cursor()[1] }, { "main.lua", 3 })
  child.cmd("Hiraishin seals")
  child.type_keys("d", "0")
  eq(child.api.nvim_buf_get_lines(0, 0, 1, false)[1], " 0  · no camp (m0)")
end

T["camp"]["the manager shows it as 0 and can move it"] = function()
  main_lua(3)
  child.cmd("Hiraishin camp")
  place(5, "five")
  child.cmd("Hiraishin manager")
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(lines[1]:match("^0 │") ~= nil, true)
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    (lines[1]:gsub("^0", "-")),
    (lines[2]:gsub("^%-", "0")),
  })
  child.cmd("write")
  child.cmd("q")
  eq(camp_sign(), { ["5"] = "⛺" }) -- the camp-only kunai on line 3 is gone
  eq(child.lua_get([[require("hiraishin").camp().name]]), "five")
end

T["camp"]["survives a restart"] = function()
  main_lua(3)
  child.cmd("Hiraishin camp")
  child.lua([[require("hiraishin.store").reset(); require("hiraishin.tracker").reset()]])
  child.cmd("edit!")
  eq(camp_sign(), { ["3"] = "⛺" })
end

T["the m key waits"] = function()
  child.lua([[vim.o.timeoutlen = 100]])
  main_lua(3)
  -- far slower than 'timeoutlen'
  child.type_keys("m")
  vim.loop.sleep(400)
  child.type_keys("0")
  eq(child.lua_get([[require("hiraishin").camp() ~= nil]]), true)
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.type_keys("m")
  vim.loop.sleep(400)
  child.type_keys("4")
  eq(child.lua_get([[require("hiraishin").slot_of(require("hiraishin").at_cursor().id)]]), 4)
  -- other keys are Vim's marks, also when typed slowly
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("m")
  vim.loop.sleep(400)
  child.type_keys("q")
  eq(child.fn.line("'q"), 1)
  child.type_keys("m", "<Esc>") -- cancels
  eq(child.api.nvim_get_mode().mode, "n")
end

T["another plugin's m mapping is left alone"] = function()
  child.lua([[vim.keymap.set("n", "m", "<Nop>", { desc = "someone else" })]])
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  eq(child.lua_get([[vim.fn.maparg("m", "n", false, true).desc]]), "someone else")
  eq(child.lua_get([[vim.fn.maparg("m3", "n") ~= ""]]), true) -- plain m{char} mappings instead
end

T["keys taken only in the current buffer don't block the defaults"] = function()
  -- e.g. a dashboard that maps <BS> for itself while hiraishin loads
  child.lua([[vim.keymap.set("n", "<BS>", "<Nop>", { buffer = 0 })
    vim.keymap.set("n", "m", "<Nop>", { buffer = 0 })
    require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  child.cmd("enew")
  eq(child.lua_get([[require("hiraishin.keymaps").is_set("<BS>")]]), true)
  eq(child.lua_get([[require("hiraishin.keymaps").is_set("m0")]]), true)
  eq(child.lua_get([[vim.fn.maparg("m", "n", false, true).desc]]):match("^hiraishin") ~= nil, true)
end

return T
