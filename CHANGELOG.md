# Changelog

Versions are git tags (`git checkout v0.6.0`). Dates are when the version
was tagged.

## Unreleased

Fixes from a repo audit.

- Two Neovims opening a new project (or a new branch in branch scope) no
  longer lose each other's kunai: the first save of a new store now merges
  with what the other one wrote
- A store written by a newer hiraishin is left untouched (not moved aside
  as corrupt, not overwritten) until you update
- A file rename made while another Neovim edits the same kunai keeps the new
  path after the merge
- Names 1-9 are refused (also in the manager): `jump 3` always means seal 3
- Global kunai drawn in a project come back on write when their text is
  restored, and fire `HiraishinMoved` / `HiraishinStale`, like project kunai
- Stats templates drop paths, so a warning that names a file keeps no path
- `:Hiraishin quickfix` with no kunai no longer opens an empty quickfix window

## v0.12.0 — 2026-10-18

The stats report now does the triage for you.

- Features grouped by area, with readable names, their key, a usage bar and
  a 14-day sparkline; the never-used ones grouped by area with their keys
- Suggestions: a key for a command you keep typing, an unused second key
  (`<BS>` vs `g0`), the way out of your most common dead end, a window you
  keep closing without acting, an action you keep retrying
- New signals: dead ends tied to the action that hit them, retries (same
  action at the same spot within 2 s), and the picker, seal menu and manager
  opened and left without acting
- Interactive: `<CR>` opens the help for the feature, `t` 30 days / all
  time, `u` folds the never-used list
- Message templates never keep what follows a colon, so a "File not found"
  path is not stored
- `HiraishinStatsBar`, `HiraishinStatsSpark`, `HiraishinStatsKey` highlights

## v0.11.0 — 2026-10-17

- Local usage stats: which features you use, how you reach them and the dead
  ends you hit; `:Hiraishin stats` shows the report, `:Hiraishin stats reset`
  forgets it, `stats = false` turns counting off. Kept in `stats.json` next
  to the stores; nothing identifying, nothing sent anywhere

## v0.10.1 — 2026-10-17

- Fix: `m0`, `mm` and `m1`…`m9` only worked when typed faster than
  'timeoutlen'; one `m` mapping now waits for the next key as long as it
  takes (other keys still set Vim's marks, `<Esc>` cancels)
- Fix: a key mapped only in the buffer that was current while hiraishin
  loaded (a dashboard, say) kept the default mapping from being set
  everywhere, e.g. `<BS>` for camp

## v0.10.0 — 2026-10-17

- **Camp**: `m0` (`:Hiraishin camp`) makes a line the place you keep coming
  back to while exploring; `g0` / `<BS>` (`:Hiraishin camp go`) go there from
  any detour, and at camp go back out to where you were. One per list, not a
  seal (`mm` never picks it), its own sign (`HiraishinSignCamp`,
  `signs.camp_icon`); shown as `0` in the seal menu, statusline and manager

## v0.9.0 — 2026-10-17

One keymap layout: anything with a number has no leader, everything else
lives under `<leader>h`.

- **Breaking:** seals moved from `<leader>h1`…`9` / `<leader>1`…`9` to
  `m1`…`m9` (seal) and `g1`…`g9` (go). No modifiers or dead keys, so they
  work the same on any keyboard layout, on macOS and Linux
- `mm` (`:Hiraishin seal`) seals the line with the next free number
- `g<Space>` (`:Hiraishin seals`): the seal menu, to see, jump to and clear seals
- The statusline lists the seals in use (`· #1 2 4`); `require("hiraishin").seals()`
  gives them as data

## v0.8.0 — 2026-10-17

- **Breaking:** next / previous kunai moved from `]m` `[m` `]M` `[M` to
  `]k` `[k` `]K` `[K`, so Vim's "next method" motions work again. To keep the
  old keys: `keymaps = { next = "]m", prev = "[m", next_list = "]M", prev_list = "[M" }`

## v0.7.1 — 2026-10-17

- Fix: the fzf-lua picker ignored `picker.show_notes` and `virt_text.note_icon`
- Unknown `keymaps` actions (typos) are reported like other unknown keys
- `Snacks.picker.hiraishin()` is registered when snacks is lazy-loaded later
- Tests check every option has an effect, and that the defaults printed in
  README and `:h hiraishin-config` match the code

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
