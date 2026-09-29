# Notes for Claude

Read this before working in this repo. Trent runs one Claude project per
addon: this one (**Blackthornes_Equipment**), **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`) and **Blackthornes_Farmer**
(`Blackthornes/Blackthornes_Farmer`). The projects cannot read each other's
memory, so what one needs to know about another lives in the repos, in this
file and in theirs. Keep them current: when a change here leans on something
new in another addon, or a standing rule from Trent applies to all of them,
add it to each file.

Nothing private goes in this file (no local paths, emails or account names).
It never ships: `.pkgmeta` leaves it out of the zip and
`tools/check_package.py` refuses it.

## How this repo was set up

It copies its sisters on purpose, so check them before inventing a
convention:

- **Layout** `Core/ Data/ Logic/ UI/ tools/`, one module per file through
  `ns.NewModule`, no Ace3 or LibStub. `Core/Init.lua` is Farmer's, renamed.
  The global is `_G.BlackthornesEquipment`, the commands `/beq` and
  `/equipment`, the saved data `BlackthornesEquipmentDB` (account) and
  `BlackthornesEquipmentCharDB` (per character: the picked spec lives there).
- **Palette** is Tradeskills' and Farmer's (`ns.COLORS`), with `upgrade` and
  `downgrade` in Tradeskills' profit green and loss red.
- **Tools** (`syntaxcheck`, `lintcalls`, `runtests`, `check_release`,
  `check_package` and their tests) are Tradeskills' with the names changed.
  If one of them gets a fix in either sister repo, bring it here too.
- **Tests** are `tools/test_*.lua`, found by name. `tools/testenv.lua` loads
  the files the TOC lists, so there is no second list to keep.
- **PRs** follow the sisters' habit: a "Before:" and an "After:" paragraph
  in plain words, then a short "How" naming the functions and tests touched,
  that the checks pass, and whether `/reload` is enough. Release PRs are
  `release/X.Y.Z` branches titled "Changelog for X.Y.Z".
- **Tradeskills' `docs/FOREVER_API_FINDINGS.md`** records what the Forever
  client actually does. Read it before relying on an API.

Nothing here calls the other addons yet, and nothing calls this one. If that
changes, write down the global and the calls in both repos' `CLAUDE.md`, the
way Farmer and Tradeskills do for prices and goals.

There is no CurseForge project yet, so the TOC's `X-Curse-Project-ID` line is
commented out and no release has been made.

## Trent's standing rules (all three addons)

- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without Trent's
  go-ahead. He tags releases himself.
- **Keep his data safe.** Never commit saved variables, tokens or anything
  from his machine; the upload keys are repository secrets he sets himself,
  so never ask him to paste one anywhere.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask Trent what went in. Claude drafts the CHANGELOG section in a PR;
  Trent merges, pulls `main`, tags and pushes.
- **Every reply that ships code ends with the GitHub Desktop steps,** naming
  the branch: merge the PR on github.com (Ready for review, then Merge pull
  request); in GitHub Desktop switch **Current branch** to **main** and click
  **Pull origin**; then say whether the game needs `/reload` or a full restart
  (a full restart when a file is added, removed or renamed, or the TOC
  changes). For a release, add: History, right-click the newest commit,
  Create Tag, `vX.Y.Z`, Push origin. Remind him to pull `main` first, or the
  tag lands on an old commit and nothing runs.
- **CurseForge descriptions are features only.** Leave out privacy notes and
  any explanation of public emotes or their switches. Those belong in the
  README and CHANGELOG.
- **Forever is not retail for classes either.** Trent: "keep in mind this is
  WoW: Forever." Hunters have classic-style talent trees (Beast Mastery,
  Marksmanship, Survival; Survival fights in melee), not a spec picked from a
  menu, so `Logic/Weights.lua` reads the tree with the most points. Never
  assume a retail API or stat exists: check with `/beq probe` and record what
  it finds.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  Registering an event the client does not know raises too, which is why
  `ns.RegisterEvent` wraps it.
