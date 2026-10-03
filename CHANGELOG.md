# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone. The newest version goes at
the top; a release is refused if its version has no section here.

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
