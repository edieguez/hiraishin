---Keep kunai attached when files are renamed by file managers.
---Renames through :saveas / :file are handled by the BufFilePost autocmd.
local M = {}

local function rename(from, to)
  if type(from) == "string" and type(to) == "string" and from ~= "" and to ~= "" then
    require("hiraishin").rename(from, to)
  end
end

local function strip_oil(url)
  return url and url:match("^oil://(.*)$")
end

local subscribed = {}

---neo-tree and nvim-tree publish renames through their own event APIs; only
---hook them once they are loaded (never force-load them).
local function hook_loaded_trees()
  if not subscribed.neotree and package.loaded["neo-tree"] then
    local ok, ev = pcall(require, "neo-tree.events")
    if ok and ev.subscribe then
      local function handler(args)
        rename(args.source, args.destination)
      end
      ev.subscribe({ event = ev.FILE_RENAMED, handler = handler, id = "hiraishin_renamed" })
      ev.subscribe({ event = ev.FILE_MOVED, handler = handler, id = "hiraishin_moved" })
      subscribed.neotree = true
    end
  end
  if not subscribed.nvimtree and package.loaded["nvim-tree"] then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api.events then
      api.events.subscribe(api.events.Event.NodeRenamed, function(data)
        rename(data.old_name, data.new_name)
      end)
      subscribed.nvimtree = true
    end
  end
end

---@param group integer augroup
function M.setup(group)
  -- oil.nvim
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "OilActionsPost",
    callback = function(ev)
      if not ev.data or ev.data.err then
        return
      end
      for _, action in ipairs(ev.data.actions or {}) do
        if action.type == "move" then
          rename(strip_oil(action.src_url), strip_oil(action.dest_url))
        end
      end
    end,
  })
  -- mini.files
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "MiniFilesActionRename", "MiniFilesActionMove" },
    callback = function(ev)
      if ev.data then
        rename(ev.data.from, ev.data.to)
      end
    end,
  })
  -- neo-tree / nvim-tree, now or whenever lazy.nvim loads them
  hook_loaded_trees()
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = hook_loaded_trees,
  })
end

return M
