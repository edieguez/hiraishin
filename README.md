# hiraishin.nvim

Project-aware bookmarks for Neovim. Place a **kunai** on a line, name it, and
come back to it across edits, restarts and projects.

> Work in progress — phase 2 of 6 (core, storage, line tracking). Seals,
> picker and manager are on the way.

## Requirements

- Neovim 0.10+
- No dependencies

## Install (lazy.nvim)

```lua
{
  "edieguez/hiraishin",
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

| Command | Action |
| --- | --- |
| `:Hiraishin relocate [name]` | Move a kunai to the cursor line (no name: pick among stale ones) |
| `:Hiraishin prune` | Remove stale kunai after confirming |

### Kunai stay on their line

- While a file is open, kunai follow your edits. Their new positions are saved
  when you write the file; `:e!` brings back the saved ones.
- Deleting a kunai's line makes it **stale** (`!` sign); `u` brings it back,
  and so does typing or pasting that line again before the next write.
- When a file changed outside Neovim (`git pull`, `git checkout`, a formatter),
  kunai are found again from the line text they remember and its neighbours:
  first near the old line, then in the whole file, then by a fuzzy match for
  slightly edited lines. Kunai that can't be found are kept as stale, never
  dropped silently.
- Renames follow along with `:saveas`, `:file`, oil.nvim, mini.files,
  neo-tree and nvim-tree. Anything else can call
  `require("hiraishin").rename(from, to)` (files or directories).

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
  anchor = {
    search_radius = 50,           -- lines searched around the old position
    full_scan = true,             -- then the whole file (exact matches)
    max_lines = 20000,            -- no full scan above this size
    fuzzy_threshold = 0.8,        -- similarity for slightly edited lines
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
h.list({ bufnr?, include_stale? })           -- live line numbers
h.at_cursor()
h.relocate(id_or_name, { bufnr?, line? })
h.stale({ all? })                           --> { { bookmark, list }, ... }
h.prune()
h.rename(from, to)
```

`User` events: `HiraishinAdd`, `HiraishinRemove`, `HiraishinUpdate`,
`HiraishinMoved` (`data.reason`: edit, reanchor, rename, relocate),
`HiraishinStale`.

## Development

```sh
make test          # fetches mini.nvim into deps/ and runs the suite
make test-file FILE=tests/test_store.lua
```
