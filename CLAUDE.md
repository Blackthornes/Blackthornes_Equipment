# Notes for Claude

Read this before working in this repo. It is one of five Blackthornes addons
(Farmer, Tradeskills, Equipment, Pets, Butler), each in its own repo. What one
needs to know about another lives in the repos, in this file and in theirs.
Keep them current: when a change here leans on something new in a sister, or a
standing rule from the owner applies to all of them, add it to each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## Keep the session small

A session that fills up stops and its work is lost. In this repo:

- Checks, quiet: `python tools/runtests.py -q` (failures and the total
  only; `-q hunts slot` runs just the suites with those words in their
  name) and `python tools/syntaxcheck.py -q`. The plain forms print a line
  for every suite and file (about 20 KB a run); leave those to CI. They
  need `pip install lupa`.
- `grep -n` first, then read 80 to 150 lines. Pipe long output through
  `tail` or `cut -c1-160`. Never `cat` a file from the big files list.
- Commit and push each step, so a new session can pick up from the branch.

## Long notes live in Docs/claude-notes.md

Every feature history, call list and sister note is there (about 135 KB,
never read whole). List its sections with `grep -n '^## ' Docs/claude-notes.md`
and read the one you need. Add new feature notes there, not here. **Before
you change any saved key, global, call between addons or shared file, read
its section first** (`What Tradeskills calls here`, `What Butler calls here`,
`What Farmer calls here`, `What this addon calls in Tradeskills`, `Sending
vendors and quests to Blackthornes`, `The one window`, `The shared minimap
button` and the like): those calls must stay stable and are changed in both
repos together. UI overlap and Settings ideas waiting on the owner are in
`Docs/handoff/ui-cleanup-equipment.md`.

## Checking a change

Before every PR, follow `.claude/skills/verify/SKILL.md`: a bug fix starts
with a test that fails the way the game failed; act the steps out in the
fake game; run `python tools/check_house_rules.py` (player words and dark
glass, lines this change adds) and `python tools/checklist_for_change.py`
(the items in `Docs/change-checklist.md` this change touches). Every PR
body ends with `Checked:` and `Not checked:` lines. After three failed
rounds, stop and ask the owner. A miss a diff could have shown gets a
checklist item in the fix's PR. Details under "Checking a change" in
`Docs/claude-notes.md`.

## Standing rules (short; full words under "Standing rules in full" in Docs/claude-notes.md)

Each is the same in every addon's notes. Read the full text before work
that touches one.

- **One key per character.** A character is its GUID in saved data and in
  every call between addons, never a name. A GUID the client won't read
  means write nothing and offer nothing for an alt. Old records stay
  readable; nothing is deleted. Ask `Alts.PlayerGUID()` for "the one
  playing"; never compare keys or names by hand. Tested in
  `tools/test_alts.lua`.
- **Mute All Sounds.** Every `PlaySound` and `PlaySoundFile` asks
  `ns.Muted()` first, a new one too. Saved as `muteSounds` and
  `muteSoundsAt` (never rename). `/beq mute [on|off]`.
- **Window spots.** Windows remember where they were dragged
  (`SharedWindow.KeepSpot(frame, key)`, `windowSpots`,
  `oneWindowDockSpots`; never rename). `UI/SharedWindow.lua` is
  FILE_VERSION 13 (Butler at the vendor, shelves, dock places, All Addons gear, no placing mid-drag; see "Shelves,
  dock places and the All Addons page" in Docs/claude-notes.md) and
  `UI/WhatsNew.lua` FILE_VERSION 7.
- **Writing for players.** Plain, warm, sixth grade. Short sentences. No
  hype, no filler, no em-dashes, no questions to the reader. deDE changes
  with the English, in the "du" voice. `About.NOTE` is the owner's own.
- **Every list is dark glass:** `glass` and `glassAlt` in turn, a 1 px
  `border` line under each, `glassHover` with a gold edge under the mouse,
  `glassActive` with a gold left edge when picked. Fade a gradient through
  `Theme.LightGradient`, never SetAlpha alone.
- **Clear to post.** Nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Keep his data safe.** Never commit saved variables, tokens or anything
  from his machine. Never ask him to paste a key.
- **Changelogs come from git history,** never from asking him. The release
  PR sets `ns.RELEASED_VERSION` in `Core/Init.lua` to the newest CHANGELOG
  version (`tools/check_release.py`).
- **Every reply that ships code says the PR is ready and whether the game
  needs `/reload` or a full restart** (a restart when a file is added,
  removed or renamed, or the TOC changes). Never merge or pull by hand on
  github.com or GitHub Desktop.
- **CurseForge descriptions are features only.**
- **Smooth play first, never at the cost of looks.** Nothing on a timer
  redraws a whole list when one thing moved. Coalesce bag, loot and cast
  events, skip hidden windows, spread big work over frames. Scans run only
  when gear, bags, level, talents or skills really changed
  (`ns.NothingChanged`); `/beq perf` times the big pieces.
- **The client is WoW: Forever** (`## Interface: 16001`, a retail engine,
  classic classes: one trait tree per class, judged by
  `Weights:TraitPoints`). Read client values inside a pcall; register
  events through `ns.RegisterEvent`. Never assume an API or stat exists:
  check with `/beq probe` and note it in `docs/FOREVER_API_FINDINGS.md`.
- **Fold in fresh data at each release,** after Farmer's, as its own step
  and never announced. The tools and their order are in the full text.

## Big files (read these in pieces)

Reading a huge file whole runs the session out of room. Sizes are
from 2026-11-16 and only grow. Find more with `find . -name '*.lua' | xargs wc -lc | sort -n`.

- Never read a file below whole. Use `grep -n` to find the spot, then read
  about 150 lines at a time (Read with `offset` and `limit`).
- Never read data tables or locale files whole. Grep them for one key.
- CLAUDE.md is big too. Grep it for a heading, then read that part only.
- Generated files (`Data/`) are written by their `tools/` script. Never edit
  them by hand, and never open them to see what they hold.

Data tables (generated, grep only): `Data/Sources.lua` 6265 lines, 479 KB; `Data/QuestEnds.lua` 1857 lines, 233 KB; `Data/Crafts.lua` 1675 lines, 127 KB; `Data/ForeverQuests.lua` 664 lines, 106 KB; `Data/ClassSpells.lua` 1538 lines, 84 KB; `Data/ForeverDrops.lua` 943 lines, 72 KB; `Data/ItemSets.lua`, `Data/Enchants.lua` and `Data/DungeonQuests.lua` are 36 to 55 KB. Some lines run past 1000 characters (`Data/ForeverVendors.lua`, `Data/ForeverDrops.lua`, `Data/Sources.lua`): grep them with `-o` or cut the output (`| cut -c1-200`).

Locale (grep one key, never read): `Locale/ruRU` 1206 lines, 99 KB; `frFR`, `deDE`, `esES`, `zhCN` are each about 1207 lines, 73 to 79 KB.

Code:
- `UI/FinderWindow.lua` 2817 lines, 111 KB: the gear window and its tabs.
- `Logic/UpgradeQuest.lua` 2532 lines, 108 KB: the upgrade quest.
- `Logic/Weights.lua` 1667 lines, 69 KB: stat weights.
- `UI/Widgets.lua` 1683 lines, 62 KB: shared widgets.
- `UI/QuestPanel.lua` 1616 lines, 63 KB: quest panel.
- `Logic/Finder.lua` 1572 lines, 64 KB: upgrade finder.
- `UI/Settings.lua` 1357 lines, 57 KB: Settings pages.
- `UI/WhatsNew.lua` 1245 lines, 46 KB: the What's New window.
- `UI/QuestLogTab.lua` 1166 lines, 45 KB: quest log tab.
- `Logic/ClassTraining.lua` 1085 lines, 43 KB: class training.
- `UI/SharedWindow.lua` 1082 lines, 41 KB: the one window.

Over 800 lines or 30 KB, same rule: `UI/SettingsPages.lua`, `Logic/QuestArrow.lua`, `Logic/Travel.lua`, `Logic/Compare.lua`, `Docs/claude-notes.md` (120 KB), `CHANGELOG.md` (1069 lines), `README.md`, `docs/FOREVER_API_FINDINGS.md`.

The same file lives in several addons: `UI/SharedWindow.lua`, `UI/WhatsNew.lua`, `UI/SettingsPages.lua`, `Logic/Travel.lua`, `Logic/ClassTraining.lua`. A fix to one belongs in all.

