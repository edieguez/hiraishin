-- Every option has an effect: each case sets one away from its default.
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
    end,
    post_once = child.stop,
  },
})

---setup() with the test defaults plus `opts`
local function setup(opts)
  child.lua(
    [[require("hiraishin").setup(vim.tbl_deep_extend("force",
      { storage = { dir = T.storage, debounce_ms = 0 }, signs = { style = "emoji" } }, ...))]],
    { opts }
  )
end
local function main_lua(line)
  child.edit(child.T("proj_a") .. "/src/main.lua", line)
end
local function place(line, name)
  child.api.nvim_win_set_cursor(0, { line, 0 })
  return child.lua_get("require('hiraishin').add({ name = ... })", { name or vim.NIL })
end
local function mark(ns)
  return child.lua_get(
    ([[vim.api.nvim_buf_get_extmarks(0, require("hiraishin.signs").%s, 0, -1, { details = true })[1] ]]):format(
      ns or "ns"
    )
  )
end
local function messages()
  return child.lua_get("_G.notified")
end

T["signs"] = MiniTest.new_set()

T["signs"]["enabled = false draws no sign"] = function()
  setup({ signs = { enabled = false } })
  main_lua()
  place(3)
  eq(mark()[4].sign_text, nil)
end

T["signs"]["priority"] = function()
  setup({ signs = { priority = 42 } })
  main_lua()
  place(3)
  eq(mark()[4].priority, 42)
end

T["signs"]["stale_icon"] = function()
  setup({ signs = { stale_icon = "X" } })
  main_lua()
  place(3, "gone")
  child.lua([[vim.api.nvim_buf_set_lines(0, 2, 3, false, {}); vim.cmd("write")]])
  -- the stale sign shows at the last known line when the file is opened again
  child.cmd("bwipeout")
  main_lua()
  eq(vim.trim(mark("stale_ns")[4].sign_text), "X")
end

T["signs"]["show_slot = false keeps the icon on sealed kunai"] = function()
  setup({ signs = { show_slot = false } })
  main_lua(3)
  child.lua([[require("hiraishin").seal(2)]])
  eq(vim.trim(mark()[4].sign_text), "⚡")
end

T["signs"]["numhl colours the line number"] = function()
  setup({ signs = { numhl = true } })
  main_lua()
  place(3)
  eq(mark()[4].number_hl_group, "HiraishinSign")
end

T["signs"]["global_icon"] = function()
  setup({ signs = { global_icon = "G" } })
  main_lua(3)
  child.lua([[require("hiraishin").add({ global = true })]])
  eq(vim.trim(mark("global_ns")[4].sign_text), "G")
end

T["virt_text"] = MiniTest.new_set()

local function cursor_text()
  local m = mark("cursor_ns")
  if m == vim.NIL then
    return nil
  end
  return table.concat(vim.tbl_map(function(c)
    return c[1]
  end, m[4].virt_text))
end

T["virt_text"]["prefix, note_icon and position"] = function()
  setup({ virt_text = { prefix = ">> ", note_icon = "N", position = "right_align" } })
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { note = "x" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua([[require("hiraishin.tracker").cursor_virt(0)]])
  eq(cursor_text(), ">> hello N")
  eq(mark("cursor_ns")[4].virt_text_pos, "right_align")
end

T["virt_text"]["only_named = false shows unnamed kunai too"] = function()
  setup({ virt_text = { only_named = false } })
  main_lua()
  place(3)
  child.lua([[require("hiraishin.tracker").cursor_virt(0)]])
  eq(cursor_text(), "← function M.hello()")
end

T["virt_text"]["enabled = false shows nothing"] = function()
  setup({ virt_text = { enabled = false } })
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin.tracker").cursor_virt(0)]])
  eq(cursor_text(), nil)
end

T["names"] = MiniTest.new_set()

T["names"]["suggest_from_treesitter"] = function()
  main_lua(4)
  local with = child.lua_get([[require("hiraishin.names").suggest()]])
  if with == vim.NIL then
    MiniTest.skip("no Lua Tree-sitter parser")
  end
  setup({ name = { suggest_from_treesitter = false } })
  eq(child.lua_get([[require("hiraishin.names").suggest()]]), vim.NIL)
end

T["note_hover = false opens no float on CursorHold"] = function()
  setup({ note_hover = false })
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { note = "n" })]])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua([[vim.api.nvim_exec_autocmds("CursorHold", { buffer = 0 })]])
  eq(#child.api.nvim_tabpage_list_wins(0), 1)
  setup({})
  child.lua([[vim.api.nvim_exec_autocmds("CursorHold", { buffer = 0 })]])
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
end

T["jump"] = MiniTest.new_set()

T["jump"]["reuse_window = false opens in the current window"] = function()
  setup({ jump = { reuse_window = false } })
  main_lua()
  place(5, "five")
  child.cmd("vsplit")
  child.cmd("enew")
  child.lua([[require("hiraishin").jump("five")]])
  -- both windows now show main.lua: it did not jump to the other one
  local bufs = child.lua_get(
    [[vim.tbl_map(function(w) return vim.fs.basename(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))) end, vim.api.nvim_tabpage_list_wins(0))]]
  )
  eq(bufs, { "main.lua", "main.lua" })
end

T["jump"]["open_folds = false leaves folds closed"] = function()
  setup({ jump = { open_folds = false } })
  main_lua()
  place(4, "inside")
  child.cmd("3,5fold")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("inside")]])
  eq(child.fn.foldclosed(4), 3)
  setup({})
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("inside")]])
  eq(child.fn.foldclosed(4), -1)
end

T["jump"]["center = false does not recenter"] = function()
  setup({ jump = { center = false } })
  child.lua([[local l = {} for i = 1, 300 do l[i] = "line " .. i end
    vim.fn.writefile(l, T.proj_a .. "/long.txt")]])
  child.edit(child.T("proj_a") .. "/long.txt", 18) -- visible from the top
  child.lua([[require("hiraishin").add({ name = "near" })]])
  child.cmd("normal! gg")
  child.lua([[require("hiraishin").jump("near")]])
  eq(child.fn.line("w0"), 1) -- no scrolling
  setup({})
  child.cmd("normal! gg")
  child.lua([[require("hiraishin").jump("near")]])
  eq(child.fn.line("w0") > 1, true) -- zz
end

T["jump"]["flash = false and flash_ms"] = function()
  setup({ jump = { flash = false } })
  main_lua()
  place(5, "five")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("five")]])
  eq(mark("flash_ns"), vim.NIL)
  setup({ jump = { flash_ms = 50 } })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua([[require("hiraishin").jump("five")]])
  eq(type(mark("flash_ns")), "table")
  vim.loop.sleep(200)
  eq(mark("flash_ns"), vim.NIL)
end

T["picker.show_notes = false hides notes in every backend"] = function()
  setup({ picker = { show_notes = false } })
  main_lua()
  place(3, "hello")
  child.lua([[require("hiraishin").update("hello", { note = "secret" })]])
  local label = child.lua_get([[(require("hiraishin.picker").entries())[1].label]])
  eq(label:find("secret", 1, true), nil)
  local fzf_line = child.lua_get([[require("hiraishin.picker.fzf").lines((require("hiraishin.picker").entries()))[1] ]])
  eq(fzf_line:find("secret", 1, true), nil)
end

T["manager size and border"] = function()
  setup({ manager = { width = 0.5, height = 0.4, border = "single" } })
  main_lua()
  place(3, "hello")
  child.cmd("Hiraishin manager")
  local cfg = child.lua_get("vim.api.nvim_win_get_config(0)")
  eq(cfg.width, math.floor(child.o.columns * 0.5))
  eq(cfg.height, math.floor(child.o.lines * 0.4))
  eq(cfg.border[1], "┌")
end

T["messages"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[_G.notified = {}
        vim.notify = function(m) table.insert(_G.notified, m) end]])
    end,
  },
})

T["messages"]["notify sends routine feedback to vim.notify"] = function()
  setup({ messages = "notify" })
  main_lua(3)
  child.cmd("Hiraishin toggle")
  eq(messages(), { "Kunai placed · 1 in this file" })
end

T["messages"]["silent shows none, warnings still go out"] = function()
  setup({ messages = "silent" })
  main_lua(3)
  child.cmd("Hiraishin toggle")
  child.cmd("Hiraishin jump nope")
  eq(messages(), { "No kunai 'nope'" })
end

T["messages"]["unknown keymap actions are reported"] = function()
  setup({ keymaps = { toogle = "<leader>x" } })
  eq(child.lua_get([[require("hiraishin.config").unknown]]), { "keymaps.toogle" })
end

T["docs"] = MiniTest.new_set()

-- the defaults table printed in a doc, evaluated
local DOC_DEFAULTS = [[(function(path, after)
  local text = table.concat(vim.fn.readfile(path), "\n")
  local from = text:find(after, 1, true)
  local s = text:find('require("hiraishin").setup({', from, true)
  local e = text:find("\n%s*}%)", s)
  local body = text:sub(s + #'require("hiraishin").setup(', e) .. "}"
  body = body:gsub("%*[%w_%-]+%*", "") -- help tags inside the block
  return assert(load("return " .. body))()
end)]]

local function defaults()
  return child.lua_get([[(function()
    local d = vim.deepcopy(require("hiraishin.config").defaults)
    d.root.fn = nil
    return d
  end)()]])
end

T["docs"]["README shows the real defaults"] = function()
  eq(child.lua_get(DOC_DEFAULTS .. "(...)", { vim.fn.getcwd() .. "/README.md", "## Configuration" }), defaults())
end

T["docs"]["the help file shows the real defaults"] = function()
  eq(
    child.lua_get(DOC_DEFAULTS .. "(...)", { vim.fn.getcwd() .. "/doc/hiraishin.txt", "*hiraishin-config*" }),
    defaults()
  )
end

T["docs"]["README lists every keymap action and default key"] = function()
  local readme = table.concat(vim.fn.readfile("README.md"), "\n")
  local actions = child.lua_get([[vim.tbl_keys(require("hiraishin.keymaps").defaults)]])
  local overrides = readme:match("Keymap overrides: single actions %((.-)%)")
  for _, action in ipairs(actions) do
    eq({ action, overrides:find("`" .. action .. "`", 1, true) ~= nil }, { action, true })
    local lhs = child.lua_get(("require('hiraishin.keymaps').defaults[%q].lhs"):format(action))
    eq({ lhs, readme:find("`" .. lhs .. "`", 1, true) ~= nil }, { lhs, true })
  end
end

return T
