# hiraishin.nvim

Project-aware bookmarks for Neovim. Place a **kunai** on a line, name it, and
come back to it across edits, restarts and projects.

> Work in progress — phase 4 of 6 (core, storage, line tracking, seals,
> navigation and picker). The manager and lists are on the way.

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
| `<leader>ha` | `:Hiraishin! add` | Place or rename a named kunai (suggests the enclosing function, if any) |
| `<leader>hn` | `:Hiraishin note` | Edit the kunai's note in a float (`:w` saves, `q` closes) |
| `<leader>hd` | `:Hiraishin delete [name]` | Remove the kunai on the line, or by name |
| `<leader>h1`…`9` | `:Hiraishin seal {1-9}` | Put seal 1–9 on this line's kunai (`seal clear` removes it) |
| `<leader>1`…`9` | `:Hiraishin jump {1-9}` | Jump to the kunai with that seal |
| | `:Hiraishin jump {name} [vsplit\|split\|tab]` | Jump by name |
| `]m` / `[m` | `:Hiraishin next` / `prev` | Next / previous kunai in this buffer (takes a count) |
| `]M` / `[M` | `:Hiraishin next list` / `prev list` | Next / previous kunai across files, in list order |
| `<leader>hf` | `:Hiraishin pick` | Find a kunai, with preview (`pick buffer` for this file only) |
| `<leader>hF` | `:Hiraishin pick all` | Find across every list |
| `<leader>hq` | `:Hiraishin quickfix [all]` | Send kunai to the quickfix list (`:Hiraishin loclist` for the location list) |

**Seals** are numbered slots: a kunai can hold one, and putting a seal that is
already taken on another kunai moves it there. The sign column shows the seal
number instead of ⚡. Jumps add to the jumplist, so `<C-o>` takes you back,
and they reuse a window that already shows the file.

### Picker

The picker uses whichever one you have: **snacks.picker**, **telescope**,
**fzf-lua** or **mini.pick** (in LazyVim it follows your `vim.g.lazyvim_picker`),
falling back to `vim.ui.select`. Sealed kunai come first, by seal number, then
the rest by `picker.sort`. Inside the picker:

| Key | Action |
| --- | --- |
| `<CR>` | Jump |
| `<C-v>` / `<C-s>` / `<C-t>` | Open in a vertical split / split / tab |
| `<C-d>` | Remove the kunai (the list refreshes in place) |
| `<C-e>` | Rename |
| `<C-o>` | Edit the note |
| `<C-q>` | Send the results to the quickfix list |

All of these are configurable under `picker.keys`. `vim.ui.select` can only
jump, and mini.pick splits with its own `<C-s>` / `<C-v>` / `<C-t>`.

`]m` / `[m` replace Vim's "next method start" motions; set
`keymaps = { next = false, prev = false }` to keep those.

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
    show_slot = true,             -- seal number replaces the icon
    numhl = false,
  },
  line_highlight = false,
  virt_text = {
    enabled = true,
    only_named = true,            -- unnamed kunai only show the note icon
    position = "eol",             -- "eol" | "right_align"
    prefix = "← ",
    note_icon = "✎",
  },
  name = { suggest_from_treesitter = true },
  picker = {
    backend = "auto",             -- "snacks" | "telescope" | "fzf-lua" | "mini" | "select"
    sort = "recent",              -- after sealed kunai: "recent" | "manual" | "path" | "created"
    show_notes = true,
    keys = { vsplit = "<C-v>", split = "<C-s>", tab = "<C-t>", delete = "<C-d>",
             rename = "<C-e>", note = "<C-o>", quickfix = "<C-q>" },
  },
  jump = {
    reuse_window = true,
    center = true,                -- zz
    open_folds = true,            -- zv
  },
  confirm_remove_named = true,
  keymaps = true,                 -- false disables all, or override per action:
})
```

Keymap overrides: single actions (`toggle`, `add`, `note`, `delete`, `next`,
`prev`, `next_list`, `prev_list`, `pick`, `pick_all`, `quickfix`) take a key or `false`; the nine-key groups
`assign_slot` and `jump_slot` take a prefix or `false`:

```lua
keymaps = {
  toggle = "<leader>bb",
  jump_slot = "<leader>j",        -- <leader>j1 … <leader>j9
  assign_slot = false,
}
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
h.update(id_or_name, { name?, note?, slot? }) -- false clears a field
h.seal(n)                                   -- seal the cursor line's kunai
h.slot_of(id_or_name)
h.jump(name_or_seal, { split? })
h.next({ count?, wrap?, scope? = "buffer"|"list" })
h.prev({ ... })
h.note()
h.pick({ filter? = "buffer"|"all", backend? })
h.to_quickfix({ loclist?, all? })
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
`HiraishinStale`, `HiraishinJump` (before a jump; `data.from` is where you were).

## Development

```sh
make test          # fetches mini.nvim (and the picker plugins) into deps/ and runs the suite
make test-file FILE=tests/test_store.lua
```
