# Blackthornes Equipment

A WoW: Forever addon that answers one question: **should I wear this?**

It looks at the gear in your bags and the rewards a quest is offering, weighs
each piece for your class and spec against what you have on, and says which
one to equip.

Built for the WoW: Forever client (`## Interface: 16001`), without Ace3 or
LibStub, matching
[Blackthornes Tradeskills](https://github.com/Blackthornes/Blackthornes_Tradeskills)
and [Blackthornes Farmer](https://github.com/Blackthornes/Blackthornes_Farmer).
The three share a palette and a framework on purpose.

So far it judges the gear in your bags: hovering a piece says on its tooltip
whether it beats what you wear and by how much, and an upgrade you can wear
now gets a green arrow on its icon in the bags. When a quest lets you choose a
reward, the biggest upgrade among them gets the same arrow, and chat names it
when you hand the quest in. The gear window lists every slot with what you
wear and the biggest upgrade for it in your bags.

## Install

### Linked to your working copy (recommended while developing)

Run this once, and from then on testing a branch is pulling it and typing
`/reload`:

```powershell
.\tools\link.ps1
```

It junctions `Interface\AddOns\Blackthornes_Equipment` to this folder, so the
client reads your checkout directly. Nothing is copied, so there is no deploy
step to forget.

Two things `/reload` will **not** pick up, because the client only reads them at
startup:

- a file that was **added, removed or renamed**
- any change to **`Blackthornes_Equipment.toc`**

After pulling a branch that did either, restart the client once.

### Copied into the client

```powershell
.\deploy.ps1              # syntax check, lint, then mirror into Interface\AddOns
.\deploy.ps1 -SkipCheck   # skip the checks (not recommended)
```

Both scripts default to `D:\Blizzard\World of Warcraft\_classic_beta_`. Pass
`-GamePath` if the client lives somewhere else.

The addon folder name has to stay `Blackthornes_Equipment`, matching the `.toc`
inside it. If they differ, the client ignores the folder and says nothing.

## Use

```
/beq            open the gear window (so does clicking the minimap button)
/beq help       list every command
/beq spec       show the spec your gear is judged for
/beq spec mm    judge it as Marksmanship instead (bm, mm, sv, or auto to go back)
/beq bags       list every piece of gear in your bags with its verdict
/beq weights    change how much each stat counts (also in the settings window)
/beq probe      check what this client supports; it only reads
/beq settings   open the settings window (so does right-clicking the minimap button)
/beq minimap    show or hide the minimap button
```

The settings window is also under the game's Options > AddOns.

Every classic class has stat weights: warrior, paladin, hunter, rogue,
priest, shaman, mage, warlock and druid, three specs each. On WoW: Forever a
character's spec is the one with the most talent points spent in it (a
class's three specs share one talent tree, side by side). Until level 10
there are none, so gear is judged as the class's levelling default (Arms,
Retribution, Beast Mastery, Combat, Shadow, Enhancement, Frost, Affliction,
Feral) unless you pick otherwise with `/beq spec <name>`. Each class is held
to classic's armour and weapon rules, so a priest is told it can't use
leather and plate waits for level 40.

A weapon your class can learn but you have not trained yet says where to
learn it, under the verdict: "Learn Daggers from the weapon master in
Orgrimmar or Undercity". Only your own faction's cities are listed, from
classic's weapon masters.

Each item gets one score (every stat times what it is worth to your spec)
and is measured against what you wear in its slot. Rings and trinkets are
measured against the weaker of your two, and a two-hander against both hands.
Anything within 1% is called the same. The best quest reward is the one that
adds the most score, so a small gain on an important slot can beat a big
percentage on a minor one. The tooltip line and the arrows can each be
switched off in the settings.

The built-in weights are a starting guess. **Settings > Stat weights >
Change weights** (or `/beq weights`) lists each stat's weight for any class
and spec: type a number or use - and +, and every verdict (tooltips, bag
arrows, the quest reward, the gear window, and Tradeskills' arrows) uses yours
at once. Changed stats are marked in gold; **Use the built-in weights** puts a
spec back. Your weights are kept account wide by class and spec in
`BlackthornesEquipmentDB.customWeights`, only for the stats you changed, so a
later version's tuning still reaches the rest. Updates never clear them.

`/equipment` works too.

## Layout

| Folder | What is in it |
|---|---|
| `Core/` | Namespace, module registry, event dispatch, slash commands, saved variables |
| `Data/` | Everything read from the game: bags, equipped gear, quest rewards, item stats; classic's weapon masters and what each teaches |
| `Logic/` | Stat weights per class and spec (`Weights.lua`), judging an item against what is worn (`Compare.lua`), and which weapon skills are known and where to learn the rest (`WeaponSkills.lua`) |
| `UI/` | Theme, widgets, the minimap button, the gear window, the settings window, the stat weights window, the tooltip lines, the bag arrows and the quest-reward arrow |
| `Probe/` | `/beq probe`, which checks what the running game actually supports instead of guessing |
| `tools/` | Checks, tests and the link script. Not shipped to the client |
| `docs/` | What the Forever client actually does, found with `/beq probe`. Not shipped |

`Blackthornes_Equipment.toc` lists every Lua file in load order. A file that is
not in it does not load, and WoW says nothing about it.

## Development

```bash
python tools/syntaxcheck.py   # parse every Lua file with a real 5.1 parser
python tools/lintcalls.py     # find calls to methods, and constants, never defined
python tools/runtests.py      # run the logic tests outside WoW
```

`tools/` requires `lupa` (`python -m pip install --user lupa`).

The checks exist because WoW silently disables an addon whose first TOC file
fails to compile, and because a call to a method that no longer exists is valid
Lua that fails only when that line runs. `deploy.ps1` runs the first two before
it copies anything, and `.github/workflows/tests.yml` runs all of them on every
push.

The tests load the addon against a stub client (`tools/testenv.lua`), reading
the file list straight from the TOC. A new test is a new `tools/test_*.lua`
file and nothing else.

## Releasing

Releases are cut by pushing a tag like `v0.1.0`.
`.github/workflows/release.yml` then:

1. refuses the tag unless `CHANGELOG.md` opens with a `## 0.1.0` section
   (`tools/check_release.py`);
2. runs the tests;
3. builds the player-facing zip with the
   [BigWigs packager](https://github.com/BigWigsMods/packager), uploading
   nothing;
4. checks that zip is clear to post (`tools/check_package.py`): only the
   addon's own files, and nothing that looks private, such as a Windows path,
   an email address, a saved-variables dump or a token;
5. only then uploads that same zip to each site with a token, and attaches it
   to a GitHub release.

To release from GitHub Desktop: add the new version's section to the top of
`CHANGELOG.md` and merge it to `main`, pull `main`, then **History**, right-click
the newest commit, **Create Tag...**, name it `v0.1.0`, and **Push origin**.

The version is never typed by hand. The TOC says
`## Version: @project-version@` and the packager fills in the tag. Running
straight from a clone there is no packager, and the addon calls itself a
"dev build". The middle number moves for new behaviour, the last for fixes
alone; a tag like `v0.2.0-beta1` is uploaded as a beta.

`.pkgmeta` leaves `tools/`, `docs/`, `deploy.ps1`, `CLAUDE.md` and this README
out of the zip. The CurseForge project is 1720051, on the `X-Curse-Project-ID` line of the TOC.
Uploading also needs a `CF_API_KEY` repository secret in the repository's
settings on github.com. Without both, the workflow
still builds and checks the zip but uploads nothing to CurseForge.
