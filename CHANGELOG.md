# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

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
