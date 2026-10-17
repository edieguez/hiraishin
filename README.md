# hiraishin.nvim

Project-aware bookmarks for Neovim. Place a **kunai** on a line, name it, and
come back to it across edits, restarts and projects.

> Work in progress — phase 1 of 6 (core + storage). Picker, manager, line
> tracking and slots are on the way.

## Requirements

- Neovim 0.10+
- No dependencies

## Install (lazy.nvim)

```lua
{
  "emmanuel/hiraishin.nvim",
  event = "VeryLazy",
  opts = {},
}
```

## Usage

| Key | Command | Action |
| --- | --- | --- |
| `<leader>hh` | `:Hiraishin toggle` | Place or remove a kunai on the current line |
| `<leader>ha` | `:Hiraishin! add` | Place a named kunai (prompts for the name) |
| `<leader>hd` | `:Hiraishin delete [name]` | Remove the kunai on the line, or by name |

Removing a kunai that has a name or note asks for confirmation
(`confirm_remove_named = false` to turn that off).

## Configuration

Defaults:

```lua
require("hiraishin").setup({
  scope = "project",              -- "project" | "global"
  root = {
    markers = { ".git", ".hiraishin" },
    fn = nil,                     -- function(bufnr, path) -> root path
  },
  storage = {
    dir = vim.fn.stdpath("data") .. "/hiraishin",
    debounce_ms = 500,
  },
  signs = {
    enabled = true,
    priority = 15,
    icon = "⚡",
    stale_icon = "!",
    show_slot = true,
    numhl = false,
  },
  confirm_remove_named = true,
  keymaps = true,                 -- false, or { toggle = "<leader>bb", add = false, ... }
})
```

Bookmarks are stored per project root in
`stdpath("data")/hiraishin/projects/<root>__<hash>.json` (or `global.json`),
written atomically.

## Lua API

```lua
local h = require("hiraishin")
h.toggle()                                  --> bookmark, "added"|"removed"
h.add({ name?, note?, bufnr?, line? })      --> bookmark | nil, err
h.remove(id_or_name)
h.update(id_or_name, { name?, note? })      -- false clears a field
h.get(id_or_name)
h.list({ bufnr? })
```

`User` events: `HiraishinAdd`, `HiraishinRemove`, `HiraishinUpdate`.

## Development

```sh
make test          # fetches mini.nvim into deps/ and runs the suite
make test-file FILE=tests/test_store.lua
```
