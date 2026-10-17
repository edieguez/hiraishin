# Changelog

Versions are git tags (`git checkout v0.6.0`). Dates are when the version
was tagged.

## v0.7.0 — 2026-10-17

The backlog: housekeeping, persistence and two new kinds of kunai.

- `:Hiraishin gc` deletes store files nobody needs: projects whose folder is
  gone, deleted branches, empty stores and corrupt backups (asks first);
  `:checkhealth` reports them
- Undo history is kept in the store file: it survives restarts, each
  project/scope has its own, and merges with other Neovim instances
- `HiraishinMoved` from renames and relocations carries `from_file` and
  `from_path` (documented and tested)
- Fix: in the manager only `│` separates columns, so names and notes can
  contain `|`; names can't contain `│` or line breaks
- An open manager without unapplied edits redraws when kunai change
  elsewhere, keeping the cursor on its kunai
- Tests drive fzf-lua with a real fzf (skipped when fzf is missing); CI
  installs fzf
- Global kunai inside projects: `:Hiraishin global` / `<leader>hg` places a
  kunai in the global store from any scope; it is drawn (globe sign),
  tracked and saved in project buffers; `pick global` / `<leader>hG` and
  `manager global` reach them anywhere; undo covers them (`global_kunai`)
- Range kunai: `:'<,'>Hiraishin toggle|add` or `<leader>hh` / `<leader>ha`
  in Visual mode mark a block of lines; it follows edits, keeps its length
  when re-anchored, and jumps flash the block (`end_line` in the API)

## v0.6.0 — 2026-10-17

UX and UI pass.

- Seals are quick jumps: sealing a bare line makes a kunai just for the seal,
  and it goes away when the seal is cleared or moved (undoable); kunai placed,
  named or noted on purpose stay
- `<leader>hj` / `<leader>hk` and `:Hiraishin next|prev seal` cycle through
  seals in order
- Signs: `signs.style` = `nerd` (default) | `ascii` | `emoji`
- Names show on the cursor line only (`virt_text.show = "always"` for all)
- Note hover float (`note_hover`), jump flash (`jump.flash`)
- Messages say what happened and the next key to press; removals offer undo
  instead of confirming (`confirm_remove_named`, `manager.confirm_delete` and
  prune default to no prompt); `messages = "echo" | "notify" | "silent"`
- Manager: column header, column highlights, unsaved marker in the title
- Picker: title with list and count, file icons, `<C-l>` switches list
- Integrations: which-key group label, `:Telescope hiraishin`,
  `Snacks.picker.hiraishin()`, clickable lualine component
- Saves merge changes another Neovim made to the same store
- `.hiraishin` can set `scope` and `picker.sort` per project (trusted via
  `vim.secure.read`)
## v0.5.0 — 2026-10-17

Phases 5 and 6.

### Lists, scopes and polish
- Lists: `:Hiraishin list [name]`, `list delete`, `<leader>hl`; seals are per list;
  kunai of other lists keep tracking edits; `HiraishinListChanged` event
- Scopes: `:Hiraishin scope project|global|branch`; branch scope reads
  `.git/HEAD` (worktrees too), forks the project kunai on the first change and
  swaps stores on `FocusGained` after a checkout
- Stores changed by another Neovim are reloaded on `FocusGained`
- `status()` and a lualine component (`hiraishin.integrations.lualine`)
- `:checkhealth hiraishin`
- `:Hiraishin import marks` turns global marks A–Z into kunai
- Vim help: `:h hiraishin`

### Manager and undo
- `:Hiraishin manager` / `<leader>he`: edit seals, names and notes, reorder and
  delete kunai in a buffer; `:w` applies, problems show as diagnostics
- `:Hiraishin undo` / `<leader>hu` brings back deletions from toggle, delete,
  the picker, the manager, prune and deleted lists (`undo_history`)

## v0.4.0 — 2026-10-17

Phase 4: picker.

- snacks.picker, telescope, fzf-lua and mini.pick backends, `vim.ui.select`
  fallback; jump, splits, delete, rename, note and quickfix actions
- `:Hiraishin pick`, `quickfix`, `loclist`

## v0.3.1 — 2026-10-17

- Fix: a named kunai's name was drawn twice at the end of the line

## v0.3.0 — 2026-10-17

Phase 3: seals, names and navigation.

- Seals 1–9, jumps by seal or name, `]m` `[m` `]M` `[M`, notes, virtual text

## v0.2.0 — 2026-10-17

Phase 2: line tracking.

- Extmark tracking, sync on write, re-anchoring after external changes,
  stale kunai, renames, `relocate`, `prune`

## v0.1.1 — 2026-10-17

- Fix: `setup({})` (lazy.nvim's `opts = {}`) wiped the defaults

## v0.1.0 — 2026-10-17

Phase 1: core and storage.

- Per-project JSON stores with atomic writes, toggle/add/delete, signs
