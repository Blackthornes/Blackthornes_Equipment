# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

## 0.6.0

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
