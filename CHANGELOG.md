# Changelog

## Unreleased

### Backlog
- `:Hiraishin gc` deletes store files nobody needs: projects whose folder is
  gone, deleted branches, empty stores and corrupt backups (asks first);
  `:checkhealth` reports them
- Undo history is kept in the store file: it survives restarts, each
  project/scope has its own, and merges with other Neovim instances

### UX and UI pass
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
- Fix: a named kunai's name could be drawn twice

### Phase 6 — lists, scopes and polish
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

### Phase 5 — manager and undo
- `:Hiraishin manager` / `<leader>he`: edit seals, names and notes, reorder and
  delete kunai in a buffer; `:w` applies, problems show as diagnostics
- `:Hiraishin undo` / `<leader>hu` brings back deletions from toggle, delete,
  the picker, the manager, prune and deleted lists (`undo_history`)

### Phase 4 — picker
- snacks.picker, telescope, fzf-lua and mini.pick backends, `vim.ui.select`
  fallback; jump, splits, delete, rename, note and quickfix actions
- `:Hiraishin pick`, `quickfix`, `loclist`

### Phase 3 — seals, names and navigation
- Seals 1–9, jumps by seal or name, `]m` `[m` `]M` `[M`, notes, virtual text

### Phase 2 — line tracking
- Extmark tracking, sync on write, re-anchoring after external changes,
  stale kunai, renames, `relocate`, `prune`

### Phase 1 — core and storage
- Per-project JSON stores with atomic writes, toggle/add/delete, signs
