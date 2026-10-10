# Notes for Claude

Read this before working in this repo. The owner runs one Claude project per
addon: this one (**Blackthornes_Equipment**), **Blackthornes_Tradeskills**
(`Blackthornes/Blackthornes_Tradeskills`) and **Blackthornes_Farmer**
(`Blackthornes/Blackthornes_Farmer`). The projects cannot read each other's
memory, so what one needs to know about another lives in the repos, in this
file and in theirs. Keep them current: when a change here leans on something
new in another addon, or a standing rule from the owner applies to all of them,
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
  `downgrade` in Tradeskills' profit green and loss red. `UI/Theme.lua` and
  `UI/Widgets.lua` are Farmer's (Widgets trimmed to button, checkbox and
  stepper); the minimap button and settings window copy Farmer's too. The
  button starts at 230 degrees, clear of Farmer's at 200, Tradeskills' at
  170 and Pets' at 260.
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

## What Tradeskills calls here

Tradeskills draws the green upgrade arrow on item icons across its windows
(`Logic/Upgrades.lua`, `Theme.SetItemIcon` there). It shows only when this
addon is loaded (`## OptionalDeps: Blackthornes_Equipment` in its TOC) and
calls, inside a pcall:

```lua
_G.BlackthornesEquipment.Compare:IsUpgrade(item)   -- item ID or link; true or false
```

`IsUpgrade` answers exactly what the bag arrow answers (`IsUpgradeNow`: an
upgrade that can be worn now), and by item ID it says false for anything
already worn, so a worn ring is never an upgrade over the other ring. It never
raises. Keep the global, `Compare` and `IsUpgrade(item)` stable; if one has to
change, change Tradeskills' `Logic/Upgrades.lua` too.

The CurseForge project ID is **1720051** (the owner created it 2026-09-30), on the
TOC's `X-Curse-Project-ID` line. The first release is 0.1.0.

## What this addon calls in Tradeskills

When a player changes a stat weight or picks a spec (`Weights:Changed` in
`Logic/Weights.lua`, which the Settings spec stepper and `/beq spec` call
too), Tradeskills' kept upgrade answers are stale, so it calls, inside a
pcall and only when Tradeskills is loaded:

```lua
_G.BlackthornesTS.Upgrades:RedrawSoon()   -- forget kept answers, redraw what shows arrows
```

If Tradeskills renames `Upgrades:RedrawSoon`, its arrows only catch up on
the next gear or talent change; change `Weights:Changed` too.

Crafted upgrades (`Logic/Crafting.lua`) read Tradeskills too, inside a
pcall, read only, and only when it is loaded:

```lua
ts.Recipes:GetAccountWide(true)        -- [recipeID] = { knownBy = { charKey, ... } }; recipe ID = spell ID
ts.Recipes:GetShortCharacterName(key)  -- "Bob", for "Bob can make this"
ts.Config:GetCharacterKey()            -- the character playing
ts.db.characters[key].faction          -- alts of the other faction are left out
ts.Prices:GetValue(itemID)             -- material and auction prices, copper
ts.RecipeBook:GetSkill(recipeID)       -- the skill a recipe needs on Forever, or nil
```

`GetSkill` (2026-10-09): Forever moved some recipes to other skill levels,
and Tradeskills reads the right one from the recipe item's tooltip.
`Crafting:Skill` uses it over `Data/Crafts.lua`'s Classic skill.

Without Tradeskills, crafted gear is still listed, known recipes are read
from the spellbook, and materials are priced at vendor only. If one of these
changes in Tradeskills, change `Logic/Crafting.lua` too.

Queue it (a player asked on Discord, the owner agreeing 2026-10-10): crafted
rows in Where to get upgrades and a crafted upgrade on the Upgrade quest
panel get a **Queue it** button while Tradeskills is loaded with these
calls. `Logic/TradeskillsQueue.lua` calls, inside a pcall:

```lua
ts.Queue:Ensure(recipeID, quantity)         -- at least that many queued; true, or nil and why
ts.Queue:EnsureBuy(itemID, count, forItem)  -- that many on the list to buy for forItem; true, or nil and why
ts.Queue:ForUpgrade(itemID)                 -- "craft", "buy" or nil; the button then reads Queued
ts.Queue:ShowQueue()                        -- a click on Queued opens the Queue tab
```

Gear the character or an alt can make (`known`, `alt`) is queued as a
craft; gear still to learn (`learn`, `skill`) has its `Data/Crafts.lua`
materials put on the list; gear nobody makes (`other`) goes on the list
itself. A craft Tradeskills has not read yet falls back to its materials.
The source is read again on each click (`TradeskillsQueue.Fresh`), since
the upgrade quest keeps one from when it was picked. If these change in
Tradeskills, change `Logic/TradeskillsQueue.lua` too. Nothing else here
calls the other addons, apart from the shared arrow table (see the quest
arrow below).

## Where to get upgrades (the finder)

`Logic/Finder.lua` and `UI/FinderWindow.lua` (`/beq find`, the gear
window's Find upgrades button) list gear from vendors, quest rewards and
dungeon drops that `Compare:Judge` calls an upgrade now. Where gear comes
from is `Data/Sources.lua`, generated by `tools/make_sources.py` from the
mangoszero world database (items, quest rewards, creature maps, loot tables)
and pfQuest's database (vendors, NPC and object positions); never edit it by
hand, rerun the script. The game supplies each item's stats: an item the
client has not seen is asked for (`C_Item.RequestLoadItemDataByID`, 40 per
scan) and the window scans again on `GET_ITEM_INFO_RECEIVED`. Defaults the owner's
project chose (2026-10-03): own faction only, nothing above the player's
level (a dungeon counts from its lowest recommended level). The owner then asked
for raid drops (open at 60) and reputation gear: gear whose standing the
character has not reached is still listed, after the rest, in amber with the
standing it needs (`Finder:Needs`, read through
`C_Reputation.GetFactionDataByID` or `GetFactionInfoByID`). Not yet seen in
game.

Solo quests (a player asked, the owner agreed 2026-10-06): a quest's
11th field in `Sources.QUESTS` says what it needs besides the player
("group", "dungeon", "raid", "battleground", or nothing), worked out by
`make_sources.py` from Classic's quest type, suggested players, and
objectives inside an instance or on an elite. "Solo quests only"
(`soloQuestsOnly`, account wide, off by default; `Finder:SetSoloOnly`) is a
tick box in the finder and a Settings row; `Finder:SourcesFor` leaves out
quests that need others or come after one, and the upgrade quest lets such
a quest go (not skipped) when it is ticked. Asked the same day, the
finder's "Quest level" stepper (`questLevelsAbove`, 0 to 10 levels above
the character, 11 for any, default 4; `Finder:QuestAllowed`) works the same
way. The upgrade quest panel (asked 2026-10-07) shows both under its tabs,
sharing the same saved values, beside "This zone only"
(`upgradeQuestZoneOnly`, account wide, off by default;
`UpgradeQuest:SetZoneOnly`): `Choose` then looks only at sources in the
zone the character is in (`UpgradeQuest.InZone`; a dungeon counts from its
entrance's zone and inside, a craft with no place anywhere), across every
pick (`found.all`, not the finder's top three per slot), and
`ZONE_CHANGED_NEW_AREA` lets go of tabs' quests elsewhere (not on a
flight, which waits for `PLAYER_CONTROL_GAINED` at the landing, and not
inside a dungeon or raid: `UpgradeQuest.Passing`). A quest followed
from the finder (`quest.followed`) stays; quests picked while ticked
(`quest.here`) are let go when it is unticked. A Settings button sits
beside them. "Change on a new zone" (`upgradeQuestZoneSwap`, account wide,
on unless unticked; `UpgradeQuest:ZoneSwap`, the owner asked 2026-10-08) is
a third tick box there and "Zone swap" in Settings: unticked, a zone change
lets nothing go, though an empty tab still picks from the zone it is in.
A player found it stale (2026-10-09), so: a quest that starts from an item
is in the zone where the item is got (`UpgradeQuest.SourceZone`, from
`Sources.STARTS`), and one whose start is not known is in none; a flight's
landing is also caught by the next event or a ticker (`WatchLanding`) in
case `PLAYER_CONTROL_GAINED` never comes; and `PLAYER_ENTERING_WORLD`
(login, reload, loading screen) counts as a new zone.
The finder has its own "This zone only" (a player asked, 2026-10-09;
`finderZoneOnly`, account wide, off by default; `FinderUI:ZoneOnly`), kept
apart from the panel's so ticking it never lets a quest go:
`FinderUI:Lines` then reads `found.all` through `UpgradeQuest.InZone`, keeps
`Finder.PER_SLOT` per slot, and `ZONE_CHANGED_NEW_AREA` refreshes the window.
Asked the same day: picks that show the same whole percent sort nearest
first (`Finder.Nearness`: in the zone, by map distance when
`Finder.Spot` can read where the character stands on that zone's own
map, never a guessed spot), and `FinderUI.MarkZone` names the zone the
character is in green on every row, tooltip and the character sheet's list.
Weapons the character has not trained (a player asked, the owner agreed
2026-10-10) show a red "Train" where the gain shows, in the finder, the
character sheet's list and the upgrade quest panel
(`WeaponSkills:NeedsTraining`, true only when the client says the skill is
unknown). `WeaponSkills:Known` is kept and forgotten on
`SKILL_LINES_CHANGED`, `LEARNED_SPELL_IN_TAB` and `SPELLS_CHANGED`, so a
list asks the client once, not once a row.

Forever's own boss drops: `tools/forever_drops.py` reads Farmer's
`Data/Data_Harvested.lua` (no player names in it) and writes
`Data/ForeverDrops.lua`, rows looted inside a known dungeon or raid by mob
name. The finder tags them [Forever] and prefers their rate. The owner asked
(2026-10-03) for this to be refreshed at least once a week: bring Farmer's
harvest up to date from his saved data first (he attaches it; see Farmer's
`tools/harvest_import.py`), then rerun this. Stats always come from the
game, never from data, so a Forever stat change needs nothing.

Vendor and trainer spots on Forever (the owner asked 2026-10-07, after Varg
Windwhisper turned out to stand elsewhere): `Logic/NPCSpots.lua` keeps,
whenever a merchant or trainer window opens, the NPC ID from
`UnitGUID("npc")`, the map name and the character's spot, account wide in
`BlackthornesEquipmentDB.npcSpots[npcID] = { name, map, x, y }` (never
rename it). `NPCSpots:Place` lays a learned spot, then the shipped
`Data/ForeverNPCs.lua`, over the Classic one wherever the finder and
`Logic/Crafting.lua` make a place from an NPC ID. Before a release, fold
the owner's learned spots in: he attaches his account save
(`Blackthornes_Equipment.lua`), and `tools/forever_npcs.py <save>` reads
only `npcSpots` and rewrites `Data/ForeverNPCs.lua`; never hand-edit it
(`--spot ID "Map" x y` adds one he reads off the map). Quest givers have
no NPC ID in the data, so their spots are not learned. Not yet seen in
game; `/beq probe` shows the target's NPC ID and the spot it would keep.

Vendor prices on Forever (the owner asked 2026-10-08): the same merchant
window keeps the gold price of gear the finder knows a vendor for, account
wide in `BlackthornesEquipmentDB.vendorPrices[itemID]` = copper (never
rename it; token and honor items are skipped). `NPCSpots:Price` beats the
Classic price in `Finder:SourcesFor` and the upgrade quest's Buy step.
When the character's money (`Finder.Short`, `GetMoney`) falls short, the
Buy step's note and the finder row say how much more is needed; it never
changes which upgrade is picked. `PLAYER_MONEY` only redraws (the finder)
or refreshes a shown vendor quest. Not yet seen in game.

Crafted gear and random rolls (the owner asked 2026-10-03 for crafted gear as
upgrades): `Data/Crafts.lua` and
`Data/Rolls.lua` are generated by `tools/make_crafts.py` from the vmangos
world dump (brotalnia/database) and pfQuest; never edit them by hand. The
finder lists crafted gear in four states (you can make it, an alt can, you
can learn it, someone else makes it), never bind on pickup gear from a
profession the player lacks, and judges random-roll gear at its best roll.
The house rule (2026-10-03): never name other addons in this repo, its PRs or
its commits; `tools/check_package.py` refuses a package
that names the one these features were asked to match.

Upgrade hunts, kept per character in `BlackthornesEquipmentCharDB.tracked`
and `.trackedDone` (never rename them): `Logic/Tracking.lua`,
`UI/TrackerPanel.lua`, `UI/MapPins.lua`, `UI/Toast.lua`,
`Logic/Waypoints.lua` (map IDs found by zone name at runtime),
`UI/SlotUpgrades.lua` (character sheet) and `UI/MoreMarks.lua` (vendor and
loot arrows). None of it has been seen in game yet; `/beq probe` reports the
calls they need.

## The upgrade quest

`Logic/UpgradeQuest.lua` and `UI/QuestPanel.lua` (`/beq quest`, a setting
under Upgrade hunts): the owner asked (2026-10-04) for an optional quest for the
next upgrade with a guide to get it. Off by default (`upgradeQuest`). It
picks from `Finder:Scan()` by gain times how easy the source is, keeps that
pick until it is worn, and works out the steps live from the saved source
and the game (zone, quest log, bags). Gear tied to a reputation (`Finder.Rep`,
the item's `r` or the craft's `f`, reached or not; picks carry `rep`)
comes last (the owner asked 2026-10-08): `Choose` takes it only when nothing
else on the tab will do, and looks past the finder's short list in a slot
that reputation gear filled. Gear whose standing is not reached is never
picked; reached gear can still be followed from the finder by hand. Kept per character in
`BlackthornesEquipmentCharDB.upgradeQuest`, `.upgradeQuestTabs`, `.upgradeQuestTab`, `.upgradeQuestSkipped` and
`.upgradeQuestsDone` (never rename them). Completed quests: the finder asks
`C_QuestLog.IsQuestFlaggedCompleted` (unverified on Forever) and also
remembers hand-ins it sees (`QUEST_TURNED_IN`) in `.questsTurnedIn`; an
upgrade quest whose quest was handed in without its reward is dropped and
skipped. Quest chains (the owner asked 2026-10-04): `Sources.QUESTS` also
carries the quests before a reward quest (`p` = the quest before), and
`Finder:Chain` walks back past what is done; the upgrade quest lists them
as steps first and counts each as extra work when it picks. When something
as good or better is worn first, the quest closes with a "You already beat
this one" banner (not counted as done) and the next one is picked. On a level up the quest stays
(the owner asked 2026-10-04): `UpgradeQuest:LookForBetter` rescans for a short
while and, when an upgrade is worth 1.5 times the quest's (gain times
ease), offers it in a box on the panel (Switch, Keep current; kept past
ones are not offered again that session). Not yet seen in
game; `/beq probe` lists the quest log calls it reads. Tabs (asked
2026-10-04): one quest per kind of source (Vendor, Quest, Dungeons and
Raids, Crafted) in `.upgradeQuestTabs[tab]`, the tab shown in
`.upgradeQuestTab`; `.upgradeQuest` is kept as a copy of the shown tab's
quest, and a quest saved there before the tabs is read once onto its tab.
The panel wears the Titanforged plate and close gem (the close gem turns
the quest off). A plain click on a finder row (asked 2026-10-06, a player's
request) follows that upgrade: `UpgradeQuest:Follow` puts it on its source's
tab, shows that tab and turns the quest on; `UpgradeQuest.CanFollow` says why
not for gear that waits on a reputation, a level or another player's craft.
Right-click still tracks and Alt-click still pins. Every `/beq quest` command has a Settings button or control.
Quests that start from an item (the owner asked 2026-10-08: "it starts from
Demon Scarred Cloak" said nothing): `Data/QuestStarts.lua`
(`Sources.STARTS`), generated by `tools/make_quest_starts.py <pfQuest>
[Farmer]` after `make_sources.py`, never by hand, lists for each such
quest the mobs, objects, dungeon bosses or vendors with the item, Farmer's
Forever drops first, each with a real spawn spot; `UpgradeQuest.Starter`
reads it and the steps say "Get X from Mob (level, rare) in Zone (x, y)",
then "Right-click X in your bags". Rerun it with `forever_drops.py`.
Where a quest is done and handed in (the owner asked 2026-10-08, when the
arrow sent him back to The Ravaged Caravan's giver): `Data/QuestEnds.lua`
(`Sources.ENDS`), generated by `tools/make_quest_ends.py <pfQuest>
[Farmer]` the same way and rerun with it, gives each quest's hand-in NPC or
object and one objective place (a mob, an object, or where an objective
item drops, Forever's drops first), real spawns in the quest's own zone
first. `UpgradeQuest.Ender` reads it: a quest in the log points at its
objective, else its hand-in, and the hand-in once it is ready, never at
its giver; with nothing known it has no place.
Ignore (the owner asked 2026-10-08) is the old Skip renamed: the same
`.upgradeQuestSkipped` list, never offered again until restored.
`UI/IgnoredWindow.lua` (Settings > Upgrade quest > Ignored, `/beq quest
ignored`) lists it with Restore on each (`UpgradeQuest:Restore`) and Restore
all (`RestoreAll`, `/beq quest restore`); `skip` and `reset` still work.

The quest arrow (the owner asked 2026-10-08 for Farmer's goal arrow here):
`Logic/QuestArrow.lua` and `UI/QuestArrow.lua` are Farmer's
`Logic/Arrow.lua` and `UI/Arrow.lua` brought over as a copy (no call into
Farmer), and `tools/make_arrow_art.py` is Farmer's tool, drawing the same
`Media/Arrow/*.tga`. It follows the quest on the tab shown and points at
the places its steps carry (`UpgradeQuest:Steps`), from the step to do now
on, a spot beating a zone-only step for the same zone; a zone with no spot
gets its middle, labelled so; it never makes up a coordinate. Off by default
(`questArrow`, account wide; spot `questArrowX`/`questArrowY`); the panel's
Arrow button, a click on a step with a place (`QuestArrow:Aim`), `/beq
arrow` and a Settings row turn it on. A fix to the dial in one addon belongs
in the other. Not yet seen in game; `/beq arrow check` reports the calls it
reads (`GetWorldPosFromMapPos`, `GetMapWorldSize`, `GetPlayerFacing`).
Pets has the same dial (its beast arrow).

TomTom (a player asked, the owner agreed 2026-10-09, then asked for it in
every addon with an arrow): with TomTom installed, each arrow hands its
place to TomTom (`Logic/TomTom.lua` in Farmer, Equipment and Pets, read
through `_G.TomTom:AddWaypoint`/`RemoveWaypoint` inside a pcall, waypoints
never persistent). "Use TomTom" (`useTomTom`, account wide, on unless
unticked; `arrow tomtom` on each addon's command) hides the dial while
TomTom shows the way, and the waypoint goes whenever the dial would hide,
so the one-arrow rule holds. The files are the same apart from names
(Farmer's reads the goal arrow's `x`/`y`, the others `mx`/`my`); a fix to
one belongs in all three.

Only one Blackthornes arrow is on screen at a time (the owner asked
2026-10-08): Farmer's goal arrow, Equipment's quest arrow and Pets' beast
arrow agree through one global table, `_G.BlackthornesArrows`
(`wants[addon]` while that arrow has something to show, `claims[addon]` the
`GetTime()` it was last turned on or aimed). The one wanting to show with
the latest claim is drawn; the others wait hidden. The lines are the same
in each dial's file (`ArrowUI:Claim`, `ArrowUI.Wins`); a change to them
belongs in all three.

## The Quest log tab

The owner asked (2026-10-10) for the game's quest tracker inside the
upgrade quest panel, picked the mockup
(`previews/equipment-quest-log-tab-mockup.png` in the project files) and
the wider panel: `QuestPanel.WIDTH` is 384 (was 340) so a fifth tab fits. `Logic/QuestLog.lua` reads the log
(retail `C_QuestLog` calls first, classic ones after, all in a pcall) and
does the actions: track, share, abandon (only through the game's own
`ABANDON_QUEST` box), open in the log, show on map, aim the arrow
(`QuestArrow:AimAtQuest`, a quest log quest the arrow follows until a step
is aimed at, the dial is clicked for the next tab, or the quest leaves the
log). `UI/QuestLogTab.lua` draws it. The tab is not one of
`UpgradeQuest.TABS`: it shows while the character's `questLogTab` is set,
and `UpgradeQuest:SelectTab` clears it. Folded zones are per character in
`questLogFolded`; "Tracked only" (`questLogTrackedOnly`) and "Hide the
game's quest tracker" (`hideQuestTracker`, hidden only while the panel is
up) are account wide and off by default. Never rename them.

The game's tracker is never moved, re-parented, hidden or shown: while
the setting is on it is made see-through and its lines stop taking the
mouse (`ns.Veil:Cover`, `UI/Veil.lua`), caught again 0.2 s after a burst
of quest events, and put back as it was when the panel closes; a
protected line waits for combat to end. Quest item buttons are secure buttons parented to
UIParent and placed over their row by screen position (Pets' Feed button
does the same), so the panel stays free to move and close in combat; in
combat a button whose row moved fades (alpha 0) until
`PLAYER_REGEN_ENABLED` puts it back; a faded button shows no tooltip but
can still be clicked until the fight ends, since nothing insecure can
hide it then. Quest events only mark the log stale;
it is read once, 0.2 s later, and only while the tab shows, and rows are
filled again only when their key (title, objectives, tracked, item) changed.
The probe (2026-10-10) found the C_QuestLog calls on Forever and none of
the classic globals, so the tab reads the retail way (see
`docs/FOREVER_API_FINDINGS.md`); the tab itself not yet seen in game.

## The controller bag button

Forever's client draws a controller bag button (`GamepadBackpackButton`,
on its `GamepadBagBar`, from Blizzard's own bag bar file) over the combined
backpack's sort button. The owner asked (2026-10-09) to hide it:
`BagIcons:ApplyGamepadBag` makes it see-through and lets clicks through
to the sort button (`ns.Veil:Cover`) while "Bag sort button" in Settings
(`hideGamepadBag`, account wide, on unless unticked) is ticked; unticking
puts it back as it was. A protected button waits for combat to end.

Why never Hide or Show (0.18.0, 2026-10-10): calling them on a game frame
runs the game's OnHide/OnShow code as this addon. The tracker and the bag
bar are Edit Mode frames, so the taint stayed in Edit Mode's layout and its
next update read auras as Equipment: "GetAuraDataByIndex(): Auras cannot
be accessed when secret while tainted by 'Blackthornes_Equipment'". Calling
the game's update functions (`ObjectiveTracker_Update`) does the same. To
put a game frame out of sight, use `ns.Veil`: SetAlpha and the mouse calls
run no game code. The same holds in every addon.

## Players' own stat weights

Kept in `BlackthornesEquipmentDB.customWeights[CLASS][spec][stat]`, account
wide, only for stats the player changed (`Weights:Get` lays them over
`SPECS`). The house rule: saved data is never lost or renamed in an update, so
never rename that key, never reshape it without keeping the old values, and
never delete a value the code cannot read (it is skipped instead).

Weapon types (a player asked, the owner agreed 2026-10-09): one number per
kind of weapon, by class and spec, multiplying that weapon's whole score in
`Compare:ScoreOf` (`Weights:FactorFor`), 1 for no change. Kept apart in
`BlackthornesEquipmentDB.weaponTypeWeights[CLASS][spec][subclassID]` (never
rename it), only for kinds changed, so `customWeights` never holds a table.
The weights window lists the kinds the class can hold (`SPECS.<CLASS>.weapons`)
under its stats; its reset clears both.

## The settings pages (from Tradeskills)

The owner asked (2026-10-09) for Tradeskills' Settings upgrade in Pets,
Equipment and Farmer. `UI/SettingsPages.lua` is the same file in all three
(a fix to it belongs in all three): category pages along the top
(`settingsPage`, the one left on: Gear, Upgrade hunts, Upgrade quest,
General), two columns a page, what a setting does as the row's tooltip
("Show descriptions", `settingsDescriptions`, off by default, puts it back
under the rows), "Find a setting" (`Widgets.CreateSearchBox`, Pets' copy of
Farmer's), and Text size (`textSize` normal/large/larger adds 0/1/2 to
`Theme.sizes`, now a lookup over `Theme.BASE_SIZES`; read once, so it waits
for /reload). The window fits its fullest page, so no page scrolls. Add a
setting with `pages:Row(page, column, label, description)` and
`pages:Section(page, column, "HEADING")` in `UI/Settings.lua`; a row whose
words change (the spec row, the panel size row) calls
`row:SetDescription(text)`. Every `/beq` command has a button there.

## The house frame (Titanforged)

The owner picked this look for all four addons on 2026-10-04 from two mockups
(the other was "Arcane Glass"). It's the game's own window shape with the
light turned up: a gold metal rim with corner gems, a round portrait with
the addon's emblem, the name on a plate across the top edge, a red close
gem, and gold-edged metal buttons. The main action is solid gold with dark
"ink" lettering; a primary button given its own dark face (`baseColor`)
keeps a gold label, so it never reads as an empty box
(`tools/test_titanforged.lua` checks every button's contrast).

`UI/Titanforged.lua` (`Titanforged:Dress(frame, opts)`, `:Opened(frame)`)
and `tools/make_frame_art.py` are Tradeskills' copies; the art is
`Media/Frame/*.tga`, which the tool writes. Equipment's emblem is the
shield (`EMBLEM = "shield"`): a rimmed heater shield with the upgrade arrow
cut out, redrawn here (`heater_shield`, `EMBLEM_RIM`) so it reads at the
36 pixels the portrait shows it at. The Lua differs from Tradeskills' only
where Equipment's differs: `Theme.TextWidth(size, text)`, and optional
pieces read with `rawget`, because this repo's test frames answer any
missing field with a function. A fix to the frame in one addon belongs in
all four.

The gear window and the finder wear the whole frame (portrait, plate,
close gem), with their lists sunk in a well (`Theme.Recess`); settings and
the stat weights get the plate and close gem only, and so does the upgrade
quest panel (asked 2026-10-04; its quest sits in a well too). The other
panels that stay on screen while playing (tracker, toasts, the character
sheet's slot list) keep `Theme.Window` and only share the restyled
buttons. Equipment has no Window effects
setting, so `Motion.Level()` is always full and the glint and the
portrait's light always run; add the setting before anyone asks for them
to stop.

List rows in the gear window and the finder are dark glass (the owner
picked it 2026-10-10 over a gold glow that lit every row; Tradeskills'
lists have the same): `glass`/`glassAlt` bands in the well with a fine
line under each, `glassHover` and the gold wash only under the mouse. A
gradient that fades goes through `Theme.LightGradient`, which hides it at
0; faded with SetAlpha alone it stayed lit on Forever.

## The Blizzard window style

The owner asked (2026-10-10) for a choice of the game's own look beside
Titanforged, in all four addons. "Window style" in Settings (`windowStyle`,
`titanforged` or `blizzard`, Titanforged by default; read once at login,
so a change waits for /reload, as Text size does). `UI/BlizzardLook.lua`
is the same file in all four (a fix to it belongs in all four): picked, it
lays the game's colours over `Theme.colors` (grey metal, the game's gold,
plain rows with a blue bar for the one picked) and puts out the halos;
`Titanforged:Dress` hands the window to `BlizzardLook.Dress` (silver rim,
a title tab where the plate sits, a silver-ringed portrait and the game's
`UIPanelCloseButton`, with the same trim fields); and the widgets call
`BlizzardLook.Button`, `.Checkbox` and `.Thumb` (the finder's scroll
thumb) to wear the game's own texture files. Equipment has no hanging
tabs or dropdown, so `.Tab`/`.SelectTab` go unused here and the setting is
a stepper on the General page beside a Reload button. It never touches a
Blizzard frame. Each file is checked once (`BlizzardLook.HasArt`); a
client without one keeps that widget in the house look, and `/beq probe`
lists what is missing. Not yet seen in game. New widgets should look right
in both styles.

## Reading the probe

The owner asked (2026-10-10) for check results without screenshots, in all
four addons. `ns.KeepCheck(name, fn)` in `Core/Init.lua` runs a check that
prints to chat, keeps every line it prints (colours and links taken out, a
secret value kept as "(secret)") and saves them in the account save as
`lastProbe = { check, at, version, lines }`, replacing the last one; chat
adds "Saved for Claude, /reload to write it." It wraps `/bts probe`
(Tradeskills, saved under `BlackthornesTSDB.global`), `/beq probe` and
`/beq arrow check` (Equipment), `/bpet probe` and `/bpet arrow check`
(Pets), and `/farm arrow check` and `/farm gathering check` (Farmer, which
has no probe). Each has a Settings button. Never rename `lastProbe`; a new
check that players run for a report goes through `ns.KeepCheck` too, and a
fix to it belongs in all four.

When the owner says "read the probe": he has run the check and typed
`/reload` (or logged out). In the thread, connect to his device, ask for
his game's WTF folder (already approved; the path is in the project's
memory) and stage the addon's account save from
`WTF\Account\<account>\SavedVariables\` (`Blackthornes_TS.lua`,
`Blackthornes_Farmer.lua`, `Blackthornes_Equipment.lua` or
`Blackthornes_Pets.lua`), read only. Read its `lastProbe`: `check` says
which one ran and `at` when; one older than his message means the save was
not written yet, so ask him to `/reload`. Use only the probe lines; never
commit the save or copy anything else out of it.

## Discord

The addons share a Discord server, Blackthornes AddOns (public invite
https://discord.gg/f2geDecrw2, set up 2026-10-05). After a release uploads,
`release.yml` runs `tools/announce_discord.py`, which posts the version's
CHANGELOG section to the server's #announcements through a channel webhook
kept in the `DISCORD_WEBHOOK_URL` repository secret. The owner sets that secret
himself; never ask him to paste the webhook address anywhere. Without it the
step does nothing, and a failed post never undoes the upload. The tool is the
same in all four repos; a fix to it belongs in all four.

The owner asked (2026-10-09) for one post in #general per release too,
and (2026-10-10) for it to be short: a few bullets in plain words, a
sixth-grade reading level, warm, in his voice (short, contractions, no
jargon, no file or setting names, never his name), saying what players will
notice. Each release PR writes the new version's section in `NEWS.md`
(`## X.Y.Z`, like CHANGELOG.md; it never ships) next to the CHANGELOG
section: the bullets, then one line of thanks. After the upload
`tools/post_general.py` scans it with `check_package.py`'s PRIVATE list and
posts it through the `DISCORD_GENERAL_WEBHOOK_URL` secret, which the owner
sets himself, under a line with the addon's name and version (so each
addon's bullets are their own group) and "(full list of changes in
#announcements)", so the thanks comes last. It carries no CurseForge link and no card (link previews
are turned off). No section or no secret means no post.
A player's name never goes in a report (the owner, 2026-10-09): no
CHANGELOG, #announcements post, commit or PR text names a player, and
`check_release.py` refuses a CHANGELOG section that credits one
(`names_a_player` in `post_general.py`). The #general post is the one
exception: its last line thanks, by their Discord name, everyone who asked
for or reported the changes, each name once ("Thanks Ana and Bob for the
ideas and reports!"); leave it out when nobody asked. Find who asked from
the project's threads. This tool is also the same in all four repos.
Changes to the Discord bots, the digest or the release posting tools
(like this one) never go in a CHANGELOG, #announcements or #general
section (the owner, 2026-10-10): they are not changes to the addon.

## The owner's standing rules (all three addons)

- **"Always check that it's clear to post."** Anything that goes public (a
  release, a CurseForge page, a post) is checked for private or unexpected
  content first, and nothing is published or uploaded without the owner's
  go-ahead. He tags releases himself.
- **Keep his data safe.** Never commit saved variables, tokens or anything
  from his machine; the upload keys are repository secrets he sets himself,
  so never ask him to paste one anywhere.
- **Changelogs come from git history.** Work out what changed since the last
  tag from the merged PRs and commits (`git log vX.Y.Z..origin/main --merges`);
  never ask the owner what went in. Claude drafts the CHANGELOG section in a PR;
  The owner merges, pulls `main`, tags and pushes.
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
- **Forever is not retail for classes either.** The owner: "keep in mind this is
  WoW: Forever." Hunters have classic-style talent trees (Beast Mastery,
  Marksmanship, Survival; Survival fights in melee), not a spec picked from a
  menu, so `Logic/Weights.lua` judges by the spec with the most points. Never
  assume a retail API or stat exists: check with `/beq probe` and record what
  it finds in `docs/FOREVER_API_FINDINGS.md`. Forever has no classic
  talent-tab calls: each class has one trait tree (`C_ClassTalents`,
  `C_Traits`) holding all its specs side by side, so `Weights:TraitPoints`
  counts ranks by column, split where `SPECS.<CLASS>.columns` says. All nine
  classes' layouts have been probed (2026-09-30): the same split
  (`CLASSIC_COLUMNS`) in classic's tab order.
- **Smooth play comes first, but never at the cost of looks** (the owner,
  2026-10-09, after a hitch while crafting). Nothing on a timer or
  OnUpdate rebuilds or re-places a whole list, map or set of markers when
  only one thing moved: keep what is drawn, and redo only rows or pins
  whose inputs changed (a per-row key, a version number). Bag, loot,
  cast, skill and profession-list events arrive in bursts, several per
  craft or loot: coalesce them, read only what they changed, and skip
  work for windows that are hidden. Work over hundreds of items (recipes,
  sources, saved spots) is spread over frames (a worker with a small
  per-frame budget) rather than done in one frame, and shown when done.
  Clicks and typing still answer at once. The two causes found: Farmer's
  minimap markers gathered, sorted and re-placed every saved spot once a
  second because the clock second was in their redraw key (now only the
  fade moves, `MapMarkers:FadeMinimap`); and on every craft Tradeskills
  re-read every recipe in the profession window and repriced the whole
  craft pane in one frame (now `Recipes:NothingNewMidCraft` skips the
  re-read mid-run and `CraftPanel:RefreshInSlices` spreads the pane over
  frames). Visuals and usability are never traded away for speed. This
  rule is in all four addons' notes; keep them the same.
- **The client is WoW: Forever, a retail engine** (`## Interface: 16001`,
  modern Lua), not 1.12. Instances hand addons secret values that raise when
  compared, concatenated or formatted, so read client values inside a pcall.
  Registering an event the client does not know raises too, which is why
  `ns.RegisterEvent` wraps it.
