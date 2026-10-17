# Changelog

## Unreleased

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
