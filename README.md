# hiraishin.nvim

Bookmarks for Neovim that stay on their line. Place a **kunai** on a line, give
it a name or a note, and come back to it later: after edits, restarts,
`git pull`, renames, and in every project you work on.

Put a **seal** (1–9) on the places you visit all the time and jump to them with
one key, the way Minato jumps to his marked kunai.

- **Kunai follow your code.** Extmarks track edits while a file is open. After
  changes made outside Neovim, each kunai finds its line again from the text it
  remembers. A kunai that can't be found is marked stale, never dropped.
- **Seals 1–9 for quick jumps.** `<leader>h3` seals a line, `<leader>3` jumps
  back to it, and `<leader>hj` / `<leader>hk` cycle through your seals.
- **Per project, per branch, or global.** One store per git root by default.
- **Fits your setup.** Uses the picker you already have (snacks, telescope,
  fzf-lua, mini.pick), labels its which-key group and has a lualine component.
- **Edit everything as text.** A manager buffer for seals, names, notes, order
  and deletions. `:w` applies your changes, and everything can be undone.

`:h hiraishin` has the full manual.

## Requirements

- Neovim **0.10+**
- Optional: a [Nerd Font](https://www.nerdfonts.com) for the default sign glyphs
  (or use `signs = { style = "ascii" }`), and a picker plugin.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim) / LazyVim:

```lua
{
  "edieguez/hiraishin",
  version = "*", -- the latest release tag; drop it to follow the main branch
  event = "VeryLazy",
  opts = {},
}
```

Releases are git tags (`v0.7.0`, …); [CHANGELOG.md](CHANGELOG.md) lists what
each one brought.

Call `require("hiraishin").setup({})` with any other plugin manager. In LazyVim
the picker follows your `vim.g.lazyvim_picker`.

## Quick start

1. `<leader>hh` places a kunai on the current line (press it again to remove it).
2. `<leader>ha` places a **named** kunai. It suggests the enclosing function.
3. `<leader>h1` seals the line as **1**. From anywhere in the project,
   `<leader>1` jumps back to it and `<C-o>` returns you.
4. `<leader>hf` finds kunai in a picker with preview.
5. `<leader>he` opens the manager to rename, reorder or delete kunai in bulk.

Removed something by accident? `<leader>hu` brings it back, even after a
restart: each project keeps its last 20 deletions.

## Keymaps

Keymaps are only set where nothing else is mapped. Each one can be changed or
turned off (see [Configuration](#configuration)).

**Placing**

| Key | Command | Action |
| --- | --- | --- |
| `<leader>hh` | `:Hiraishin toggle` | Place or remove a kunai on this line |
| `<leader>ha` | `:Hiraishin! add` | Place or rename a named kunai |
| `<leader>hn` | `:Hiraishin note` | Edit the kunai's note in a float (`:w` saves, `q` closes) |
| `<leader>hd` | `:Hiraishin delete [name]` | Remove the kunai on this line, or one by name |
| `<leader>hh` (Visual) | `:'<,'>Hiraishin toggle` | Place a **range** kunai over the selected lines |
| `<leader>hu` | `:Hiraishin undo` | Bring back the last removal |

**Seals: quick jumps**

| Key | Command | Action |
| --- | --- | --- |
| `<leader>h1`…`9` | `:Hiraishin seal {1-9}` | Seal this line with that number |
| `<leader>1`…`9` | `:Hiraishin jump {1-9}` | Jump to that seal |
| `<leader>hj` / `<leader>hk` | `:Hiraishin next seal` / `prev seal` | Cycle through seals in order (1 → 9) |
| | `:Hiraishin seal clear` | Remove the seal from this line |

**Moving around**

| Key | Command | Action |
| --- | --- | --- |
| `]m` / `[m` | `:Hiraishin next` / `prev` | Next / previous kunai in this buffer (takes a count) |
| `]M` / `[M` | `:Hiraishin next list` / `prev list` | Next / previous kunai across files, in list order |
| | `:Hiraishin jump {name} [vsplit\|split\|tab]` | Jump by name |

**Finding and editing**

| Key | Command | Action |
| --- | --- | --- |
| `<leader>hf` | `:Hiraishin pick [buffer]` | Find a kunai (`buffer`: only this file) |
| `<leader>hF` | `:Hiraishin pick all` | Find across every list |
| `<leader>hg` | `:Hiraishin global` | Place or remove a **global** kunai on this line |
| `<leader>hG` | `:Hiraishin pick global` | Find global kunai from any project |
| `<leader>he` | `:Hiraishin manager` | Edit the list as a buffer |
| `<leader>hq` | `:Hiraishin quickfix [all]` | Send the kunai to the quickfix list (`:Hiraishin loclist` for the location list) |
| `<leader>hl` | `:Hiraishin list [name]` | Switch list, or create one; `list delete {name}` |

**Other commands:** `:Hiraishin scope project|global|branch` (for this
session), `:Hiraishin relocate [name]` (move a kunai to the cursor; with no
name, pick among stale ones), `:Hiraishin prune` (remove stale kunai), `:Hiraishin gc` (delete store files
of deleted projects and branches, and empty ones, after asking) and
`:Hiraishin import marks` (turn global marks A–Z into kunai). A bare
`:Hiraishin` opens the picker.

> `]m` / `[m` replace Vim's "next method start" motions. To keep those, set
> `keymaps = { next = false, prev = false }`.

## Seals

Seals are quick jumps, like harpoon's slots, numbered 1–9 within each list:

- Sealing a line with no kunai creates one just for the seal. When that seal
  is cleared or moved to another line, that kunai goes with it, so no
  leftover bookmark stays behind.
- A kunai you placed yourself, named or gave a note to keeps living without
  its seal.
- Using a number that is already taken moves the seal to the new line.
- `<leader>hj` / `<leader>hk` step through the seals in number order. When the
  cursor isn't on a seal, they continue from the last seal you jumped to.
- The sign column shows the seal number instead of the bookmark icon.

Jumps go to the jumplist (`<C-o>` returns) and reuse a window that already
shows the file. The line you land on flashes briefly.

## Picker

The picker uses whichever one you have: **snacks.picker**, **telescope**,
**fzf-lua** or **mini.pick**. Without any of those it falls back to
`vim.ui.select`. Sealed kunai come first in seal order, followed by the rest,
sorted by `picker.sort`. The title shows the list and the count, for example
`Kunai · default (5)`, and files get icons from mini.icons or
nvim-web-devicons.

| Key | Action |
| --- | --- |
| `<CR>` | Jump |
| `<C-v>` / `<C-s>` / `<C-t>` | Open in a vertical split / split / tab |
| `<C-d>` | Remove the kunai (the list refreshes in place) |
| `<C-e>` | Rename |
| `<C-o>` | Edit the note |
| `<C-q>` | Send the results to the quickfix list |
| `<C-l>` | Switch to another list and reopen |

The keys can be changed under `picker.keys`. `vim.ui.select` can only jump,
and mini.pick opens splits with its own keys.

## Manager

`<leader>he` opens the active list as a buffer, one line per kunai, under a
column header:

```
# │ name       │ location                    │ note
1 │ auth-entry │ internal/auth/handler.go:42 │ Token refresh starts here
- │ -          │ cmd/server/main.go:17 !     │
```

You can change a seal (`1`–`9`, or `-` for none), a name (`-` for none) or a
note. Move lines to reorder, delete lines to remove kunai, then `:w`. Problems
such as two kunai with one seal, a duplicate name or an edited path appear as
diagnostics, and nothing is applied until they are fixed. A `●` in the title
means unsaved edits, and `!` marks a stale kunai. Without unsaved edits, the
manager redraws when kunai change elsewhere. `<CR>` jumps, `<Tab>` shows
the next list, `q` closes and `g?` shows help.

## Lists and scopes

**Lists** group kunai, for example one per task: `:Hiraishin list bug-1234`
creates the list and switches to it. Seals belong to the list, so `<leader>1`
follows the list you are in.

**Scopes** decide where lists live:

- `project` (default): one store per project root (`.git` or `.hiraishin`).
- `branch`: one store per git branch. A new branch starts from the project's
  kunai and gets its own file on the first change. After a checkout, the
  kunai swap when Neovim regains focus.
- `global`: one store for everything, with absolute paths.

**Global kunai** are for places you visit from every project, like a
dotfile or a notes file. `<leader>hg` places one from any project. It shows
there with a globe sign, follows your edits like any other kunai, and
`<leader>hG` (or `:Hiraishin manager global`) reaches it from anywhere. Set
`global_kunai = false` to stop drawing them inside projects.

### Per-project settings

An empty `.hiraishin` file only marks a project root. It can also return a
table to set the scope and the picker sort for that project:

```lua
-- .hiraishin
return { scope = "branch", picker = { sort = "path" } }
```

The file is read through `vim.secure.read`, so Neovim asks before trusting it.
Only these two settings are read from it. `:Hiraishin scope` still takes
precedence for the current session.

## Looks

- **Signs:** `signs.style` sets the glyphs: `"nerd"` (a Nerd Font bookmark,
  the default), `"ascii"` (`*` and `?`) or `"emoji"` (`⚡` and `!`).
  `signs.icon` / `signs.stale_icon` override them.
- **Names:** a kunai's name and note icon appear at the end of the line you
  are on (`virt_text.show = "always"` shows them on every line).
- **Notes:** rest the cursor on a kunai with a note to see it in a float
  (`note_hover`).
- **Messages:** routine feedback goes to the command line, starts with
  `Hiraishin` and tells you the next key to press, for example
  `Removed kunai 'auth' · <leader>hu to undo`. Use `messages = "notify"` for
  toasts or `"silent"` for none. Warnings always use `vim.notify`.

Highlight groups, each linked to a default you can override:
`HiraishinSign`, `HiraishinSignSlot`, `HiraishinSignStale`,
`HiraishinSignGlobal`, `HiraishinSignRange`, `HiraishinLine`,
`HiraishinVirtText`, `HiraishinFlash`, `HiraishinStatus`,
`HiraishinManagerSlot`, `HiraishinManagerPath`, `HiraishinManagerSep` and
`HiraishinManagerHeader`.

## Integrations

```lua
-- lualine: "<icon>3 [bug-1234]"; click it to pick from this file's kunai
sections = { lualine_x = { require("hiraishin.integrations.lualine") } }
```

- **which-key:** `<leader>h` is labelled `hiraishin`.
- **telescope:** `require("telescope").load_extension("hiraishin")`, then
  `:Telescope hiraishin` (also `hiraishin buffer` and `hiraishin all`).
- **snacks:** `Snacks.picker.hiraishin({ filter = "all" })`.
- **File managers:** renames in oil.nvim, mini.files, neo-tree and nvim-tree
  are followed. Anything else can call
  `require("hiraishin").rename(from, to)` for files or directories.

`:checkhealth hiraishin` checks storage, config, picker and keymaps, and
reports stale kunai.

## How kunai stay on their line

- While a file is open, kunai follow your edits, and their new positions are
  saved when you write the file. `:e!` brings back the saved positions.
- A **range kunai** (select lines, `<leader>hh`) grows and shrinks with edits
  inside it, keeps its length when found again, and jumps flash the whole
  block. The picker, manager and quickfix show `file:12-18`.
- Deleting a kunai's line makes it **stale**. `u` brings it back, and so does
  typing or pasting that line again before the next write.
- When a file changes outside Neovim (`git pull`, a formatter), each kunai is
  found again from its line's text and the lines around it. The search looks
  near the old line first, then in the whole file, then for a fuzzy match to
  catch slightly edited lines.
- Two Neovim instances can share a project. Each save merges the other
  instance's changes (additions, removals, renames, seals) instead of
  overwriting them.

Stores live in `stdpath("data")/hiraishin/` and are written atomically:
`projects/<root>__<hash>.json` for each project (`…@<branch>.json` in branch
scope), or `global.json`.

## Configuration

These are the defaults. Pass only what you want to change.

```lua
require("hiraishin").setup({
  scope = "project",              -- "project" | "global" | "branch"
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
    style = "nerd",               -- "nerd" | "ascii" | "emoji"
    icon = false,                 -- a string overrides the style's icon
    stale_icon = false,
    global_icon = false,          -- sign of a global kunai inside a project
    show_slot = true,             -- the seal number replaces the icon
    numhl = false,
  },
  line_highlight = false,
  virt_text = {
    enabled = true,
    show = "cursorline",          -- "cursorline" | "always"
    only_named = true,            -- unnamed kunai only show the note icon
    position = "eol",             -- "eol" | "right_align"
    prefix = "← ",
    note_icon = "✎",
  },
  name = { suggest_from_treesitter = true },
  note_hover = true,
  global_kunai = true,            -- draw global kunai in project buffers
  jump = {
    reuse_window = true,
    center = true,                -- zz
    open_folds = true,            -- zv
    flash = true,                 -- highlight the line you land on
    flash_ms = 350,
  },
  picker = {
    backend = "auto",             -- "snacks" | "telescope" | "fzf-lua" | "mini" | "select"
    sort = "recent",              -- after sealed kunai: "recent" | "manual" | "path" | "created"
    show_notes = true,
    icons = true,
    keys = {
      vsplit = "<C-v>", split = "<C-s>", tab = "<C-t>", delete = "<C-d>",
      rename = "<C-e>", note = "<C-o>", quickfix = "<C-q>", list = "<C-l>",
    },
  },
  manager = { width = 0.8, height = 0.6, border = "rounded", confirm_delete = false },
  undo_history = 20,
  messages = "echo",              -- "echo" | "notify" | "silent"
  confirm_remove_named = false,   -- removals can be undone instead
  keymaps = true,                 -- false disables all, or override per action
})
```

Keymap overrides: single actions (`toggle`, `add`, `note`, `delete`, `undo`,
`next`, `prev`, `next_list`, `prev_list`, `next_seal`, `prev_seal`, `pick`,
`pick_all`, `global`, `pick_global`, `quickfix`, `manager`, `list`) take a key
or `false`. The nine-key groups `assign_slot` and `jump_slot` take a prefix or
`false`:

```lua
keymaps = {
  toggle = "<leader>bb",
  jump_slot = "<leader>j",        -- <leader>j1 … <leader>j9
  next_seal = "<leader>]",
  assign_slot = false,
}
```

## Lua API

```lua
local h = require("hiraishin")
h.toggle()                                  --> bookmark, "added"|"removed"
h.add({ name?, note?, bufnr?, line?, end_line? }) --> bookmark | nil, err
h.remove(id_or_name)
h.update(id_or_name, { name?, note?, slot? }) -- false clears a field
h.seal(n)                                   -- seal the cursor line
h.slot_of(id_or_name)
h.jump(name_or_seal, { split? })
h.next({ count?, wrap?, scope? = "buffer"|"list"|"seal" })
h.prev({ ... })
h.note()
h.pick({ filter? = "buffer"|"all"|"global", backend? })
h.to_quickfix({ loclist?, all? })
h.get(id_or_name)
h.list({ bufnr?, include_stale? })          -- with live line numbers
h.at_cursor()
h.relocate(id_or_name, { bufnr?, line? })
h.stale({ all? })                           --> { { bookmark, list }, ... }
h.prune()
h.rename(from, to)
h.manager({ global? })                       -- add/toggle/remove/update/jump take global = true too
h.undo()
h.lists()                                   --> names, active, counts
h.set_list(name)
h.delete_list(name)
h.set_scope("project"|"global"|"branch")
h.import_marks()
h.status()
```

`User` autocmd events: `HiraishinAdd`, `HiraishinRemove`, `HiraishinUpdate`,
`HiraishinMoved` (`data.reason`: edit, reanchor, rename or relocate;
renames and relocations add `data.from_file` / `data.from_path`),
`HiraishinStale`, `HiraishinJump` (fired before a jump; `data.from` is where
you were) and `HiraishinListChanged`.

## Development

```sh
make test                                 # fetches mini.nvim and the pickers into deps/, runs the suite
                                          # (the fzf-lua tests need fzf on PATH)
make test-file FILE=tests/test_store.lua
```
