# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.17.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- **Queue it:** with Blackthornes Tradeskills loaded, crafted upgrades in
  Where to get upgrades and on the Upgrade quest panel get a **Queue it**
  button. If you or an alt can make it, it's queued in Tradeskills; if you
  still have to learn it, its materials go on the shopping list; if nobody on
  your account makes it, the gear itself goes on the list to buy. The button
  then reads **Queued** and opens Tradeskills' Queue tab.

## 0.16.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- **Where to get upgrades:** upgrades showing the same percent sort nearest
  first (your zone first, then the closer one when the game says where you
  stand; it never guesses), and the zone you're in shows in green on every
  row, tooltip and the character sheet's list.
- **Clicking an upgrade says what it does:** the tooltip says it becomes your
  upgrade quest, and once followed, how to drop it.
- **The version number** shows at the bottom of the gear window and in the
  minimap button's tooltip.
- **Bag sort button:** Forever's controller bag button no longer covers the
  combined bags' sort button. Settings > Gear > "Bag sort button: Hide it",
  on by default.
- **New Settings window** like Tradeskills': pages along the top, a tooltip on
  every row (or **Show descriptions**), **Find a setting**, **Text size**, and
  buttons for the commands that had none.
- **Smoother hovering:** a hovered item is judged about once a second instead
  of on every tooltip redraw, and the first hover on a gear slot no longer
  scans everything at once ("Looking for upgrades, hover again in a moment").
- **Less CPU** judging gear and building the upgrade finder.
- **More Forever vendor and trainer spots** in Mulgore and Thunder Bluff,
  learned in game.

## 0.15.0

For WoW: Forever (interface 16001). A file was added, so restart the game
fully after updating (`/reload` is not enough).

- **Weapon types** in the stat weights window: one row per kind of weapon your
  class can hold, all at 1. Set daggers to 1.2 and a dagger's score counts a
  fifth higher; 0 leaves that kind out. **Use the built-in weights** puts them
  back.
- **Where to get upgrades: This zone only.** A tick box in the finder's filter
  row shows only upgrades from the zone you're in (plus gear you can make
  anywhere). It's separate from the upgrade quest panel's box.
- **TomTom:** with TomTom installed, the quest arrow's place goes to TomTom as
  a waypoint and the dial stays hidden. Turn it off with the **Use TomTom**
  tick box in Settings.
- **Crafted upgrades use the skill Forever asks for** when Tradeskills is
  loaded, read from the recipe's own tooltip.
- Fixed: the quest reward choices could show up blank at a quest giver. Item
  requests now wait while the quest giver's window is open, and an item is
  asked about three times at most.
- Fixed: with "This zone only" ticked, the upgrade quest could still send you
  to another zone. A quest that starts from an item now counts as being where
  the item is got, a flight's landing is always noticed, and a login or
  loading screen counts as a new zone.

## 0.14.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- The upgrade quest's steps now say where to go once a quest is in your
  log: they point at its objective (a mob, an object, or where an
  objective item drops), then at whoever takes it back once it is ready.
  The reward quest's Complete and Hand in steps get a place too, and the
  map pin and quest arrow follow. A quest the data knows nothing about
  gets no place rather than its giver's.
- A quest that starts from an item now says where to get that item: the
  zone, the mob, vendor or object that has it (with level, a note for
  rares, and the drop chance), and then to right-click it in your bags.
  The map pin and quest arrow point at the spot. A starter item from a
  dungeon boss sends you to the dungeon's door.
- New **Change on a new zone** tick box under This zone only on the
  upgrade quest panel (also **Zone swap** in Settings > Upgrade hunts).
  Untick it to keep your quests as you travel; a tab with nothing to chase
  still picks from the zone you are in. It is on by default.
- The quest panel's "Other ways" button is now **Change** (or **Pick one**
  on an empty tab), with a tooltip saying it opens Where to get upgrades
  to pick a different upgrade.

## 0.13.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New **quest arrow**: an **Arrow** button beside Show on map on the
  upgrade quest panel brings up a gold dial that turns as you turn and
  points at the next place in the quest's steps (the vendor, quest giver
  or trainer), with the distance in yards and a green check once you are
  there. A step with only a zone points at the middle of that zone and
  says so. Click a step on the panel to aim at it, click the dial for the
  next tab's quest, right-click it for the next place, and close it with
  its red gem. It hides inside dungeons and is off until turned on
  (Settings > Upgrade hunts, or `/beq arrow on|off|next|check|reset`).
- Only one Blackthornes arrow is on screen at a time: with Farmer's goal
  arrow or Pets' beast arrow also showing, the one turned on or aimed most
  recently is drawn and the others wait.
- The upgrade quest now offers reputation gear last: on each tab it picks
  gear from a reputation quartermaster only when nothing else will do.
  You can still follow one yourself from Where to get upgrades.
- Vendor prices seen on Forever: once a merchant window has shown an item,
  the upgrade quest's Buy step and Where to get upgrades use that price
  instead of Classic's. When the character is short, the Buy step says
  "Not enough money: you have X and need Y more", and the finder row adds
  "need Y more" in red.
- The upgrade quest's Skip button is now **Ignore**, and says the upgrade
  won't be offered again on this character. Settings > Upgrade hunts has an
  **Ignored** button with the count that opens a list of every ignored
  upgrade, with a **Restore** button on each row and **Restore all**.
  Items skipped before this update show up as ignored.

## 0.12.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The upgrade quest panel can now be resized, text and all, from 50% to
  150%. Drag the gold grip below its bottom right corner (right-click it
  for Normal), use the Small, Normal and Large buttons under **Panel size**
  in Settings > Upgrade hunts, or type
  `/beq quest size small|normal|large|<percent>`. It never grows past the
  screen.
- With **This zone only** ticked, a flight no longer swaps the quests in
  every zone it crosses and pops "New upgrade quest" toasts mid-flight.
  The tabs pick again when you land. Inside a dungeon or raid the tabs now
  keep their quests instead of dropping them and picking them again on the
  way out.

## 0.11.0

For WoW: Forever (interface 16001). Files were added, so restart the game
fully after updating (`/reload` is not enough).

- New **This zone only** tick box on the upgrade quest panel, off by
  default. When it's ticked, each tab picks only from the zone you're in (a
  vendor, a quest giver or a dungeon entrance there) and picks again as you
  travel. An upgrade you chose yourself in Where to get upgrades is kept
  wherever you go.
- The upgrade quest panel now has the **Solo quests only** tick box and the
  **Quest level** stepper too, shared with Where to get upgrades, and a
  **Settings** button.
- Vendors and trainers that Forever moved now show in the right place in
  Where to get upgrades, on the map pin and in the upgrade quest. Varg in
  Bloodhoof Village, for example, is at Mulgore 45.3, 62.1. Whenever you
  open a merchant or trainer window, the addon also remembers where that
  NPC stands and uses that spot from then on.

## 0.10.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Left-click a row in Where to get upgrades to make it the upgrade quest on
  its tab. The quest panel opens on that tab, and rows you follow are
  marked **Quest**. The tooltip says what a click does, or why an item
  can't be followed yet. Right-click still tracks and Alt-click still pins
  on the map.
- New quest filters under the source buttons. **Quest level** sets how far
  above your level a quest may be ("Up to my level", +1 to +10, or "Any";
  +4 by default). **Solo quests only** (also in Settings) leaves out
  quests that need a group, dungeon, raid or battleground. The upgrade
  quest follows both, and quest lines now say "dungeon", "raid" or
  "battleground" instead of "group".
- Spell damage for one school ("Increases damage done by Frost spells...",
  and Fire, Arcane, Shadow, Nature and Holy) now counts for the specs that
  cast that school. The six schools are new weights in the stat weights
  window.
- The minimap button now sits on the minimap's ring beside other addons'
  buttons, instead of floating just outside it.

## 0.9.5

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- A new banner no longer fades away when it arrives while the last one is
  fading out.
- After changing a stat weight or spec, Where to get upgrades and the
  character sheet's slot upgrades show the new picks straight away.
- Unticking **Upgrade arrows** now also clears them from an open vendor or
  loot window.
- Bag arrows redraw after training a new weapon skill such as Dual Wield.
- "Show on map" no longer gets stuck on "map not found" for a zone after
  trying it during a loading screen or on a flight.
- The weapon master line says when a skill opens, for example "Learn
  Polearms at level 20 from the weapon master in ...".
- A late "better upgrade" offer no longer pops up after a level-up when
  there was no quest to compare it with.

## 0.9.4

For WoW: Forever (interface 16001). Nothing in the addon itself changed, so
`/reload` is enough after updating.

- New versions are now announced in the Blackthornes Discord, in the
  #announcements channel.

## 0.9.3

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Feral druids now get main-hand and two-hand upgrades. On Forever, cat and
  bear attacks use the weapon's damage, so weapon damage now counts for
  Feral Combat.
- Druids can use polearms on Forever (trained from level 20), and polearms
  now show as druid gear instead of "Druids can't use this".
- Druids, paladins and shamans are never offered a wand, bow, gun or thrown
  weapon. Their idols, librams and totems still show in that slot.
- A weapon whose type the game hasn't reported is no longer called an
  upgrade.

## 0.9.2

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Fixed the game freezing for a split second now and then. Equipment
  remembers how it judged each piece of gear until your gear, level,
  talents or stat weights change, instead of judging everything again on
  every search.
- The full search for upgrades after you change gear or level now runs a
  little at a time, so it no longer freezes the game. The upgrade quest
  panel says "Looking for your next upgrade" until it is done.
- Items the game loads for chat links or other addons no longer make
  Equipment search for upgrades again.
- New speed check: `/beq perf`, or Settings > Speed check > Show, lists in
  chat what Equipment spent longest on since you logged in. Clear starts
  the count again. If the game ever hitches, this shows why.

## 0.9.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Fixed the game hanging for a moment after every arrow or bullet shot.
  A change in ammo count no longer makes Equipment recheck your gear.
- Fixed a small hitch when looting. An upgrade quest tab with nothing to
  chase no longer searches again on every loot, zone change or quest log
  update; it looks again when your gear, level, talents or recipes change.
- The upgrade quest's Vendor, Quest, Dungeons and Raids and Crafted tabs
  sit on the panel again, instead of floating in the top left corner of
  the screen.

## 0.9.0

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- The upgrade quest panel wears the gold frame too: a gold rim, "Upgrade
  quest" on a plate, a red close gem, and the quest in a sunk well.
- The upgrade quest now has four tabs: Vendor, Quest, Dungeons and Raids,
  and Crafted. Each keeps its own upgrade from that kind of source, and you
  can flip between them freely. A tab with nothing on it is dimmed, and
  hovering a tab names its upgrade. The first time, the tab most worth the
  trip is shown.
- Pick a tab with `/beq quest vendor` (or `quest`, `dungeon`, `crafted`),
  or with the new Quest tab setting under Upgrade hunts.
- The close gem turns the upgrade quest off and keeps its quests. A quest
  you were already following moves onto its own tab, so nothing is lost.

## 0.8.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- New look: the gear window and the finder wear a gold metal frame with
  corner gems, a round portrait holding a gold shield with an upgrade arrow,
  a title plate across the top and a red gem to close it. Their lists sit in
  a sunk well and rows light gold under the mouse. Settings and Stat weights
  get the plate and close gem. Buttons are raised gold-edged metal and the
  main action is solid gold. A light runs round the portrait as a window
  opens and a glint slides along the rim. The upgrade quest panel, tracker,
  banners, slot list and the bag, loot and map marks keep their own look.
- The finder opens a little further from the gear window.

## 0.7.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- **Upgrade quest** (off by default; turn it on in Settings > Upgrade hunts
  or with `/beq quest`). Equipment picks your best next upgrade, weighing
  how much better it is against how easy it is to get, and walks you there
  on a panel styled like the quest tracker: the item, how much better it
  is, a progress bar and steps such as "Travel to Elwynn Forest", "Buy it
  for 1g 20s 50c" and "Put it on". The current step is lit gold and done
  steps get a green tick. **Show on map** pins the next place to go,
  **Skip** moves on to the next best upgrade, and **Other ways** opens the
  finder. Put the item on and a banner says the quest is complete, then the
  next one is picked.
- Quest chains: a reward at the end of a chain starts from the first quest
  you haven't done, with who gives it and where, and each step drops off as
  you hand it in. Where to get upgrades says "after 3 earlier quests". A
  long chain counts as more work when the next upgrade is picked.
- Equipment remembers every quest it sees you hand in, so finished quests
  stay out of the finder. If you take a different reward, the upgrade quest
  moves on to the next upgrade.
- If you put on something as good or better, or already have the item in
  your bags, the quest closes with "You already beat this one".
- When a level up opens a much better upgrade, a gold "New upgrade unlocked
  at level N" box offers **Switch** or **Keep current** (`/beq quest switch`
  does the same).
- Settings > Upgrade hunts has buttons for the upgrade quest: Skip, Switch,
  Open and Bring back.

## 0.6.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Where to get upgrades: the line under each item wraps onto a second line
  instead of being cut off, and the window is wider, so the whole source
  shows. The slot upgrades panel and the upgrade tracker wrap the same way.
- The finder opens beside the gear window until you drag it somewhere else,
  and Reset window positions puts it back there.
- Crafted gear's materials line is in the normal light text colour instead
  of a hard-to-read dark red, and the best-roll line is green as intended.

## 0.6.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- Where to get upgrades: the gear window's new Find upgrades button (or
  `/beq find`) lists, for every slot, the best gear you can go and get from
  vendors (with the map spot and price), quests (with their level and quest
  giver) and dungeon and raid bosses (with the drop chance). Hover a row for
  every place to get it, the zone you're in first. Boss drops measured on
  Forever are marked [Forever]. Reputation gear you can't wear yet is listed
  last, in amber, with the standing it needs.
- Crafted upgrades: a Crafted filter in the same window shows gear you can
  make, gear an alt can make (with Blackthornes Tradeskills loaded), gear you
  could learn to make and where, and gear a crafter could make for you, each
  with the cost of its materials.
- Plan ahead: a stepper in the window looks up to 10 levels ahead, so you
  can see what's coming.
- Random-roll gear ("of the Monkey") is judged at its best roll, with how
  often that roll drops, and its tooltip names the roll and the stats it
  adds.
- Upgrade hunts: right-click an upgrade to track it. Tracked upgrades get a
  tracker panel, a pin on the world map, a banner when the item lands in
  your bags and another when you put it on. `/beq tracked` lists them. The
  switches are in Settings under Upgrade hunts.
- Hover a gear slot on your character sheet for its best upgrades and where
  they come from. Alt-click it for a panel with Track and Map buttons.
- The green upgrade arrow now also shows on vendor pages and in the loot
  window.
- A new look: Equipment's windows glow gold and flare as they open, item
  rows show icons framed in their quality colour, and slots with an upgrade
  waiting light up green. The minimap tooltip counts the upgrades in your
  bags, and shift-click puts an item's link in chat.
- Both ring slots and both trinket slots now fill from your bags, and a
  second copy of a worn ring is judged against your other ring.
- An off-hand weapon for a class that hasn't trained Dual Wield says "once
  you train Dual Wield" instead of getting the arrow.
- Handing in a quest whose rewards hadn't loaded yet no longer says none of
  them beats what you wear, and the quest log no longer shows an arrow left
  over from the last quest giver.

## 0.5.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- Gear up for a group loot roll (the Need and Greed window) gets the same
  green upgrade arrow as in your bags, with how much better it is under the
  icon. Gear you can't wear yet, or that isn't better, gets nothing. The
  Upgrade arrows setting covers it.

## 0.4.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- When an upgrade you can wear now lands in your bags (looted, bought, mailed
  or traded), chat says so once, with how much better it is. Gear you move
  between bags or just took off isn't mentioned. Turn it off in Settings
  under Upgrade in chat.

## 0.3.0

For WoW: Forever (interface 16001). This version adds files, so fully
restart the game after updating; `/reload` is not enough.

- A weapon your class can learn but you haven't trained yet says where to
  learn it on its tooltip, under the verdict: "Learn Daggers from the weapon
  master in Orgrimmar or Undercity". Only your own faction's cities are
  listed. The tooltip switch in Settings covers this line too.

## 0.2.1

For WoW: Forever (interface 16001). No files were added, so `/reload` is
enough after updating.

- Picking a spec, in Settings or with `/beq spec`, redraws every verdict: the
  bag arrows, the gear window, quest rewards and Blackthornes Tradeskills'
  upgrade arrows. `/beq spec` used to redraw nothing until the next gear or
  talent change.

## 0.2.0

For WoW: Forever (interface 16001). This version adds a file, so fully
restart the game after updating; `/reload` is not enough.

- Change the stat weights yourself: Settings > Stat weights > Change weights,
  or `/beq weights`, lists how much each stat counts for any class and spec.
  Type a number or use - and +, and the tooltips, bag arrows, quest reward,
  gear window and Tradeskills' arrows all use your weights at once. Changed
  stats show in gold, and "Use the built-in weights" puts a spec back.
- Your weights are kept for every character on the account, and only for
  the stats you changed, so later tuning of the built-in weights still
  reaches the rest. Updates never clear them.

## 0.1.0

The first release, for WoW: Forever (interface 16001). A new addon, so the
game needs a full restart after installing it.

- Hover any piece of gear and its tooltip says whether it beats what you
  wear in that slot for your class and spec, and by how much.
- An upgrade you can wear now gets a green arrow on its icon in your bags.
- When a quest lets you pick a reward, the biggest upgrade among them gets
  the same arrow, and chat names it when you hand the quest in.
- The gear window (`/beq`, or click the minimap button) lists every slot with
  what you wear and the biggest upgrade for it in your bags.
- Stat weights for all nine classes, three specs each. Your spec is the tree
  with the most talent points; before level 10 gear is judged for the
  class's levelling spec. `/beq spec` shows it, and `/beq spec <name>` picks
  another (`auto` goes back).
- Classic's armour and weapon rules per class: a priest is told it can't use
  leather, plate waits for level 40, and off-hand weapons are only offered to
  classes that can dual wield.
- Rings and trinkets are measured against the weaker of your two, and a
  two-hander against both hands. Anything within 1% is called the same.
- `/beq bags` lists every piece of gear in your bags with its verdict.
- Blackthornes Tradeskills can ask it whether an item is an upgrade, to mark
  it with the same green arrow in its own windows.
- Settings window (`/beq settings`, right-click the minimap button, or the
  game's Options > AddOns) to switch off the tooltip line, the arrows or the
  minimap button.
