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
local function place(line, name)
  child.api.nvim_win_set_cursor(0, { line, 0 })
  return child.lua_get("require('hiraishin').add({ name = ... })", { name or vim.NIL })
end
local function bufname()
  return vim.fs.basename(child.api.nvim_buf_get_name(0))
end
-- names of picker entries, or of bookmarks from require("hiraishin").list()
local function names(items)
  return vim.tbl_map(function(e)
    local bm = e.bookmark or e
    return bm.name or vim.NIL
  end, items)
end
local function entries(opts)
  return child.lua_get("(require('hiraishin.picker').entries(...))", { opts or vim.empty_dict() })
end

-- three kunai: hello (main:3, seal 2), ret (main:4), beta (other:2, seal 1)
local function fixture()
  main_lua()
  place(3, "hello")
  place(4, "ret")
  child.lua([[require("hiraishin").update("hello", { slot = 2, note = "entry\npoint" })]])
  other_lua()
  place(2, "beta")
  child.lua([[require("hiraishin").update("beta", { slot = 1 })]])
  main_lua(1)
end

T["entries"] = MiniTest.new_set()

T["entries"]["sealed first by seal, then the rest"] = function()
  fixture()
  eq(names(entries()), { "beta", "hello", "ret" })
end

T["entries"]["carry path, live line, line text and a label"] = function()
  fixture()
  child.api.nvim_buf_set_lines(0, 0, 0, false, { "-- inserted" })
  local e = entries()[2]
  eq({ e.file, e.line, e.text, e.slot }, { "src/main.lua", 4, "function M.hello()", 2 })
  eq(e.label, "[2]  hello  src/main.lua:4  function M.hello()  ✎ entry ⏎ point")
end

T["entries"]["sort = recent puts the last jumped-to first"] = function()
  main_lua()
  place(1, "a")
  place(3, "b")
  place(5, "c")
  child.lua([[require("hiraishin").jump("b")]])
  eq(names(entries()), { "b", "a", "c" })
end

T["entries"]["other sort orders"] = function()
  other_lua()
  place(2, "o2")
  main_lua()
  place(5, "m5")
  place(1, "m1")
  local function with(sort)
    child.lua("require('hiraishin.config').options.picker.sort = ...", { sort })
    return names(entries())
  end
  eq(with("manual"), { "o2", "m5", "m1" })
  eq(with("path"), { "m1", "m5", "o2" })
end

T["entries"]["filter = buffer and stale entries"] = function()
  fixture()
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  child.type_keys("d", "d")
  local es = entries({ filter = "buffer" })
  eq(names(es), { "hello", "ret" })
  eq(es[2].stale, true)
  eq(es[2].label:match("%(stale%)") ~= nil, true)
end

T["entries"]["filter = all shows every list with its name"] = function()
  fixture()
  child.lua([==[
    local store = require("hiraishin.store")
    local data = store.get(require("hiraishin.scope").for_buf(0))
    data.lists.bugfix = store.new_list()
    local bm = vim.deepcopy(data.lists.default.bookmarks[data.lists.default.order[1]])
    bm.id = "bbbbbbbb"; bm.name = "in-bugfix"
    require("hiraishin.list").insert(data.lists.bugfix, bm)
  ]==])
  local es = entries({ filter = "all" })
  eq(#es, 4)
  eq(es[3].list, "bugfix")
  eq(es[3].label:match("%(bugfix%)") ~= nil, true)
end

T["quickfix"] = MiniTest.new_set()

T["quickfix"][":Hiraishin quickfix fills and opens the quickfix list"] = function()
  fixture()
  child.cmd("Hiraishin quickfix")
  local qf = child.lua_get([[vim.fn.getqflist({ title = 1, items = 1 })]])
  eq(qf.title, "Hiraishin: default")
  eq(#qf.items, 3)
  eq(qf.items[2].text, "[2] hello: function M.hello()")
  eq(qf.items[2].lnum, 3)
  eq(child.lua_get([[vim.bo.buftype]]), "quickfix")
end

T["quickfix"][":Hiraishin loclist uses the location list"] = function()
  fixture()
  child.cmd("Hiraishin loclist")
  child.cmd("wincmd p")
  eq(#child.lua_get([[vim.fn.getloclist(0)]]), 3)
end

T["backend choice"] = MiniTest.new_set()

T["backend choice"]["falls back to vim.ui.select"] = function()
  eq(child.lua_get([[select(2, require("hiraishin.picker").backend())]]), "select")
end

T["backend choice"]["warns about an unavailable configured backend"] = function()
  child.lua([[_G.msgs = {}; vim.notify = function(m) table.insert(_G.msgs, m) end]])
  eq(child.lua_get([[select(2, require("hiraishin.picker").backend("telescope"))]]), "select")
  eq(child.lua_get("_G.msgs[1]"):match("not available") ~= nil, true)
end

T["backend choice"]["follows vim.g.lazyvim_picker"] = function()
  child.lua([[vim.opt.rtp:append(HIRAISHIN_DEPS .. "/fzf-lua")]])
  child.lua([[vim.g.lazyvim_picker = "fzf"]])
  eq(child.lua_get([[select(2, require("hiraishin.picker").backend())]]), "fzf-lua")
end

T["select backend"] = function()
  fixture()
  child.lua([[vim.ui.select = function(items, opts, cb)
    _G.labels = vim.tbl_map(opts.format_item, items)
    cb(items[3])
  end]])
  child.cmd("Hiraishin pick")
  eq(#child.lua_get("_G.labels"), 3)
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "main.lua", 4 })
end

T["pick with nothing to show"] = function()
  main_lua(1)
  child.cmd("Hiraishin pick")
  eq(child.lua_get([[require("hiraishin.ui").last()]]), "No kunai yet · <leader>hh places one")
end

-- Real pickers ---------------------------------------------------------------

local function wait(cond, ms)
  return child.lua_get(string.format("vim.wait(%d, function() return %s end, 20)", ms or 2000, cond))
end

T["mini.pick"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[require("mini.pick").setup()]])
    end,
  },
})

local function start_mini()
  child.lua([[vim.schedule(function() vim.cmd("Hiraishin pick") end)]])
end

T["mini.pick"]["lists, previews and jumps"] = function()
  fixture()
  start_mini()
  eq(wait("MiniPick.is_picker_active()"), true)
  eq(#child.lua_get("MiniPick.get_picker_items()"), 3)
  child.type_keys("<C-n>", "<C-n>", "<CR>")
  eq(wait("not MiniPick.is_picker_active()"), true)
  wait("vim.fs.basename(vim.api.nvim_buf_get_name(0)) == 'main.lua' and vim.fn.line('.') == 4")
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "main.lua", 4 })
end

T["mini.pick"]["<C-d> deletes in place, <C-q> sends to quickfix"] = function()
  fixture()
  start_mini()
  wait("MiniPick.is_picker_active()")
  child.type_keys("<C-d>")
  eq(#child.lua_get("MiniPick.get_picker_items()"), 2)
  eq(names(child.lua_get([[require("hiraishin").list()]])), { "hello", "ret" })
  child.type_keys("<C-q>")
  wait("#vim.fn.getqflist() == 2")
  eq(#child.lua_get("vim.fn.getqflist()"), 2)
end

T["mini.pick"]["<C-v> opens in a vertical split"] = function()
  fixture()
  start_mini()
  wait("MiniPick.is_picker_active()")
  child.type_keys("<C-v>")
  wait("#vim.api.nvim_tabpage_list_wins(0) == 2 and vim.fs.basename(vim.api.nvim_buf_get_name(0)) == 'other.lua'")
  eq(#child.api.nvim_tabpage_list_wins(0), 2)
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "other.lua", 2 })
end

T["snacks"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/snacks.nvim")]])
      child.lua([[require("snacks").setup({ picker = { enabled = true } })]])
    end,
  },
})

T["snacks"]["is chosen automatically and jumps"] = function()
  fixture()
  eq(child.lua_get([[select(2, require("hiraishin.picker").backend())]]), "snacks")
  child.cmd("Hiraishin pick")
  eq(wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 3"), true)
  local texts =
    child.lua_get([[vim.tbl_map(function(i) return i.entry.bookmark.name end, Snacks.picker.get()[1]:items())]])
  eq(texts, { "beta", "hello", "ret" }) -- our order kept
  child.type_keys("<Down>", "<CR>")
  wait("vim.fs.basename(vim.api.nvim_buf_get_name(0)) == 'main.lua' and vim.fn.line('.') == 3")
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "main.lua", 3 })
end

T["snacks"]["<C-d> deletes and refreshes"] = function()
  fixture()
  child.cmd("Hiraishin pick")
  wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 3")
  child.type_keys("<C-d>")
  eq(wait("#Snacks.picker.get()[1]:items() == 2"), true)
  eq(names(child.lua_get([[require("hiraishin").list()]])), { "hello", "ret" })
end

T["snacks"]["<C-e> renames and reopens"] = function()
  fixture()
  child.lua([[vim.ui.input = function(o, cb) vim.schedule(function() cb("renamed") end) end]])
  child.cmd("Hiraishin pick")
  wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 3")
  child.type_keys("<C-e>")
  eq(wait([[require("hiraishin").get("renamed") ~= nil]]), true)
  eq(wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 3"), true)
end

T["telescope"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- telescope's current version needs Neovim 0.11 (vim.hl)
      if child.fn.has("nvim-0.11") == 0 then
        MiniTest.skip("telescope.nvim requires Neovim 0.11+")
      end
      child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/plenary.nvim")]])
      child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/telescope.nvim")]])
      child.lua([[require("telescope").setup({})]])
    end,
  },
})

local TELE_COUNT = [[(function()
  local ok, state = pcall(require, "telescope.actions.state")
  local bufnr = vim.api.nvim_get_current_buf()
  if not ok or vim.bo[bufnr].filetype ~= "TelescopePrompt" then return -1 end
  local p = state.get_current_picker(bufnr)
  return p and p.manager and p.manager:num_results() or -1
end)()]]

T["telescope"]["lists and jumps"] = function()
  fixture()
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, picker = { backend = "telescope" } })]]
  )
  main_lua(1)
  child.cmd("Hiraishin pick")
  eq(wait(TELE_COUNT .. " == 3"), true)
  child.type_keys("<CR>")
  wait("vim.fs.basename(vim.api.nvim_buf_get_name(0)) == 'other.lua'")
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "other.lua", 2 })
end

T["telescope"]["<C-d> deletes and refreshes"] = function()
  fixture()
  child.lua(
    [[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, picker = { backend = "telescope" } })]]
  )
  main_lua(1)
  child.cmd("Hiraishin pick")
  wait(TELE_COUNT .. " == 3")
  child.type_keys("<C-d>")
  eq(wait(TELE_COUNT .. " == 2"), true)
  eq(#child.lua_get([[require("hiraishin").list()]]), 2)
end

T["fzf-lua"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/fzf-lua")]])
      -- fzf itself needs a terminal; capture what we hand to fzf_exec instead
      child.lua([[
        require("fzf-lua").fzf_exec = function(contents, opts)
          _G.fzf = { opts = opts, lines = {} }
          contents(function(l) if l then table.insert(_G.fzf.lines, l) end end)
        end
        require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 }, picker = { backend = "fzf-lua" } })
      ]])
    end,
  },
})

T["fzf-lua"]["feeds path:line:col lines with preview and key actions"] = function()
  fixture()
  child.cmd("Hiraishin pick")
  local lines = child.lua_get("_G.fzf.lines")
  eq(lines[2], "src/main.lua:3:1: [2] hello  function M.hello()  ✎ entry ⏎ point")
  eq(child.lua_get("_G.fzf.opts.previewer"), "builtin")
  eq(child.lua_get("_G.fzf.opts.cwd"), child.T("proj_a"))
  local keys = child.lua_get("vim.tbl_keys(_G.fzf.opts.actions)")
  table.sort(keys)
  eq(keys, { "ctrl-d", "ctrl-e", "ctrl-l", "ctrl-o", "ctrl-q", "ctrl-s", "ctrl-t", "ctrl-v", "enter" })
end

T["fzf-lua"]["enter jumps, ctrl-d deletes with reload"] = function()
  fixture()
  child.cmd("Hiraishin pick")
  child.lua([[_G.fzf.opts.actions["enter"]({ _G.fzf.lines[3] })]])
  wait("vim.fn.line('.') == 4")
  eq({ bufname(), child.api.nvim_win_get_cursor(0)[1] }, { "main.lua", 4 })
  eq(child.lua_get([[_G.fzf.opts.actions["ctrl-d"].reload]]), true)
  child.lua([[_G.fzf.opts.actions["ctrl-d"].fn({ _G.fzf.lines[1] })]])
  eq(names(child.lua_get([[require("hiraishin").list()]])), { "hello", "ret" })
end

T["fzf-lua"]["key names"] = function()
  eq(child.lua_get([[require("hiraishin.picker.fzf").fzf_key("<C-v>")]]), "ctrl-v")
  eq(child.lua_get([[require("hiraishin.picker.fzf").fzf_key("<M-d>")]]), "alt-d")
  eq(child.lua_get([[require("hiraishin.picker.fzf").fzf_key("<leader>x")]]), vim.NIL)
end

T["keymaps"] = function()
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage } })]])
  eq(child.lua_get([[vim.fn.maparg("<leader>hf", "n")]]), "<Cmd>Hiraishin pick<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>hF", "n")]]), "<Cmd>Hiraishin pick all<CR>")
  eq(child.lua_get([[vim.fn.maparg("<leader>hq", "n")]]), "<Cmd>Hiraishin quickfix<CR>")
end

T["polish"] = MiniTest.new_set()

T["polish"]["titles say what is listed and how many"] = function()
  fixture()
  child.lua([[vim.ui.select = function(items, opts) _G.prompt = opts.prompt end]])
  child.cmd("Hiraishin pick")
  eq(child.lua_get("_G.prompt"), "Kunai · default (3)")
  child.cmd("Hiraishin pick buffer")
  eq(child.lua_get("_G.prompt"), "Kunai · this file (2)")
  child.cmd("Hiraishin pick all")
  eq(child.lua_get("_G.prompt"), "Kunai · all lists (3)")
end

T["polish"]["file icons come from nvim-web-devicons or mini.icons when present"] = function()
  fixture()
  eq(entries()[1].icon, nil)
  child.lua([[package.preload["nvim-web-devicons"] = function()
    return { get_icon = function(name, ext) return ext == "lua" and "L" or "?", "DevIconLua" end }
  end]])
  local e = entries()[1]
  eq({ e.icon, e.icon_hl }, { "L", "DevIconLua" })
  child.lua([[require("mini.icons").setup()]])
  eq(type(entries()[1].icon), "string")
  child.lua([[require("hiraishin.config").options.picker.icons = false]])
  eq(entries()[1].icon, nil)
end

T["polish"]["the list key switches lists and reopens the picker"] = function()
  child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/snacks.nvim")]])
  child.lua([[require("snacks").setup({ picker = { enabled = true } })]])
  fixture()
  child.lua([[require("hiraishin").set_list("bugs")]])
  place(6, "bug")
  child.lua([[require("hiraishin").set_list("default")]])
  child.cmd("Hiraishin pick")
  wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 3")
  child.lua([[vim.ui.select = function(items, opts, cb) vim.schedule(function() cb("bugs") end) end]])
  child.type_keys("<C-l>")
  eq(wait([[require("hiraishin").lists() and select(2, require("hiraishin").lists()) == "bugs"]]), true)
  eq(wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 1"), true)
end

T["integrations"] = MiniTest.new_set()

T["integrations"]["Snacks.picker.hiraishin() opens the snacks picker"] = function()
  child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/snacks.nvim")]])
  child.lua([[require("snacks").setup({ picker = { enabled = true } })]])
  child.lua([[require("hiraishin").setup({ storage = { dir = T.storage, debounce_ms = 0 } })]])
  fixture()
  wait("Snacks.picker.hiraishin ~= nil")
  child.lua([[Snacks.picker.hiraishin({ filter = "buffer" })]])
  eq(wait("Snacks.picker.get()[1] ~= nil and #Snacks.picker.get()[1]:items() == 2"), true)
end

T["integrations"][":Telescope hiraishin"] = function()
  if child.fn.has("nvim-0.11") == 0 then
    MiniTest.skip("telescope.nvim requires Neovim 0.11+")
  end
  child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/plenary.nvim")]])
  child.lua([[vim.opt.rtp:prepend(HIRAISHIN_DEPS .. "/telescope.nvim")]])
  child.lua([[require("telescope").setup({}); require("telescope").load_extension("hiraishin")]])
  fixture()
  child.lua([[require("telescope").extensions.hiraishin.all()]])
  eq(wait(TELE_COUNT .. " == 3"), true)
end

T["integrations"]["which-key gets a group label"] = function()
  child.lua([[package.loaded["which-key"] = { add = function(spec) _G.wk = spec end }]])
  child.lua([[vim.g.mapleader = " "; require("hiraishin").setup({ storage = { dir = T.storage } })]])
  eq(wait("_G.wk ~= nil"), true)
  eq(child.lua_get("{ _G.wk[1][1], _G.wk[1].group }"), { "<leader>h", "hiraishin" })
end

T["integrations"]["the lualine component opens the picker on click"] = function()
  fixture()
  child.lua([[vim.ui.select = function(items, opts) _G.prompt = opts.prompt end]])
  child.lua([[require("hiraishin.integrations.lualine").on_click()]])
  eq(child.lua_get("_G.prompt"), "Kunai · this file (2)")
end

return T
