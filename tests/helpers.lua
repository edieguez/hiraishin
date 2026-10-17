local Helpers = {}

Helpers.expect = vim.deepcopy(MiniTest.expect)
Helpers.eq = MiniTest.expect.equality

---Child Neovim with hiraishin on the runtimepath and a throwaway workspace.
---Sets `_G.T` in the child: { tmp, storage, proj_a, proj_b, loose }.
function Helpers.new_child()
  local child = MiniTest.new_child_neovim()

  ---(Re)start the child; keeps the same temp workspace across restarts.
  function child.setup(tmp, opts)
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.lua(
      [[
      local tmp, opts = ...
      local function write(path, lines)
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        vim.fn.writefile(lines, path)
      end
      _G.T = {
        tmp = tmp,
        storage = tmp .. "/storage",
        proj_a = tmp .. "/proj_a",   -- root marked by .git directory
        proj_b = tmp .. "/proj_b",   -- root marked by .hiraishin file
        loose = tmp .. "/loose",     -- no marker
      }
      if vim.fn.isdirectory(T.proj_a) == 0 then
        vim.fn.mkdir(T.proj_a .. "/.git", "p")
        write(T.proj_a .. "/src/main.lua", { "local M = {}", "", "function M.hello()", "  return 1", "end", "", "return M" })
        write(T.proj_b .. "/.hiraishin", {})
        write(T.proj_b .. "/app.go", { "package main", "", "func main() {", "}" })
        write(T.loose .. "/notes.txt", { "one", "two", "three" })
      end
      opts = vim.tbl_deep_extend("force", { storage = { dir = T.storage, debounce_ms = 0 } }, opts or {})
      require("hiraishin").setup(opts)
    ]],
      { tmp, opts or vim.empty_dict() }
    )
    -- Paths as the plugin sees them (resolves /tmp symlinks on macOS)
    child.lua([[for k, v in pairs(T) do T[k] = require("hiraishin.util").realpath(v) end]])
  end

  function child.edit(path, line)
    child.cmd("edit " .. vim.fn.fnameescape(path))
    if line then
      child.api.nvim_win_set_cursor(0, { line, 0 })
    end
  end

  function child.T(key)
    return child.lua_get("T." .. key)
  end

  ---Sign texts placed by hiraishin in the current buffer: { [line] = text }
  function child.signs()
    return child.lua_get([[(function()
      local ns = require("hiraishin.signs").ns
      local out = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
        out[tostring(m[2] + 1)] = vim.trim(m[4].sign_text or "")
      end
      return out
    end)()]])
  end

  return child
end

function Helpers.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

return Helpers
