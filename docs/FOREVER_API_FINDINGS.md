# What the WoW: Forever client actually does

Found with `/beq probe` in the game, not taken from documentation. Tradeskills
keeps a longer file like this one for the auction house and professions; read
it too before relying on any API.

## 2026-09-29, level 7 hunter in Durotar

| Question | Answer | What it means here |
|---|---|---|
| Classic talent tabs (`GetNumTalentTabs`, `GetTalentTabInfo`) | **Absent** | `Weights:TreePoints` finds nothing, so the spec is the picked one or the class default. |
| `GetSpecialization` | **Absent** | No retail spec to read either. |
| Item stats | **`C_Item.GetItemStats` yes**, the old global `GetItemStats` no | Read stats through `C_Item`. |
| Stat names | Modern `ITEM_MOD_*_SHORT` keys, e.g. `ITEM_MOD_DAMAGE_PER_SECOND_SHORT=2.0588` | Matches `Weights.STAT_KEYS`. DPS comes as an unrounded decimal. |
| Equipment slots | 16 main hand and **18 ranged both answer**; 17 was empty | Forever keeps a separate ranged slot, so bows and guns are compared on their own. |
| Quest rewards | `GetNumQuestChoices` and `GetQuestItemLink` present | Step 3 can read quest reward choices. |
| Talent points at level 7 | None to read | Expected; hunters get points from level 10. |

## 2026-09-29, second probe, same character

| Question | Answer | What it means here |
|---|---|---|
| Newer talent calls | **`C_ClassTalents.GetActiveConfigID` and `C_Traits.GetConfigInfo` present** | Forever's talents are the modern trait system, not classic tabs. The spec has to be read from the trait config. |

## 2026-09-29, third probe, same character

| Question | Answer | What it means here |
|---|---|---|
| Classic and older talent calls | `GetNumTalentTabs`, `GetTalentTabInfo`, `GetNumTalents`, `GetTalentInfo`, `GetSpecialization` all **absent** | None of the old ways to read talents work. |
| Active talent config | `C_ClassTalents.GetActiveConfigID` gives an id; `C_Traits.GetConfigInfo` says type 4, name "Hunter", **one tree** | Forever puts all three hunter specs in **one trait tree**, not three tabs. |
| That tree | 52 nodes; `GetTreeCurrencyInfo` says spent 0 of 0 at level 7 | The spec has to come from *which* nodes have points, not from a per-tree total. |
| `C_SpecializationInfo.GetSpecialization` | Not in the missing list, so present; value not seen yet | The probe now prints what it returns. |

The probe now also groups the tree's nodes into columns by position, names
each column's top talent, and lists every talent with points in it. That shows
which part of the tree is Beast Mastery, Marksmanship and Survival, so
`Weights` can count points per spec.

## 2026-09-29, fourth probe: the hunter tree's layout

`C_SpecializationInfo.GetSpecialization` answers **1** with no points spent,
so it says nothing about the talents; it is not used.

The 52 nodes sit in columns by `posX`, each named here by its top talent:

| Columns (posX) | Top talents | Spec |
|---|---|---|
| 1020, 1620, 2220, 2820 (16 nodes) | Focused Fire, Deadly Aspects, Endurance Training, Improved Revive Pet | Beast Mastery |
| 5020, 5620, 6220, 6820 (17 nodes) | Hawk Eye, Improved Concussive Shot, Lethal Attacks, Lone Wolf | Marksmanship |
| 9080, 9680, 10280, 10880 (18 nodes) | Entrapment, Improved Tracking, Deflection, Improved Wing Clip | Survival |
| 102800 (1 node) | Lightning Reflexes | Survival, sitting far out on its own |

So `Weights` splits at 4000 and 8000 (`SPECS.HUNTER.columns`) and counts the
ranks bought in each part. Re-check this if Forever reshapes the tree.

## 2026-09-29, fifth probe: bags and tooltips

| Question | Answer | What it means here |
|---|---|---|
| Bag windows | **Retail's**: `ContainerFrameCombinedBags` and `ContainerFrame1`-`7`, buttons listed through `EnumerateValidItems`; `ContainerFrame_Update` and `GetContainerItemLink` are **absent** | `UI/BagIcons.lua` hooks each window's `UpdateItems`. The classic path stays as a fallback. |
| Bag slots | `C_Container.GetContainerItemLink` present | Bag items are read through `C_Container`. |
| Upgrade arrow | Seen in game on a bought Stiletto in the combined backpack | The arrow is drawn and placed right. |
| Tooltip line | "Upgrade for Beast Mastery: +62%" on a vendor's Stiletto, through `TooltipDataProcessor` | Matches Tradeskills' finding. |
| Item info | `C_Item.GetItemInfo` and `C_Item.GetItemInfoInstant` present, the old `GetItemInfo` global absent | `Data/Items.lua` asks `C_Item` first. |

## 2026-09-29, sixth probe: the client's classes

`C_CreatureInfo.GetClassInfo` lists exactly the classic nine: WARRIOR,
PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID. No death
knight, monk or other later class, and every one has weights here.

Still unchecked: the other eight classes' talent trees (the warlock's is
checked by the seventh probe below). `Weights.lua` gives each the
hunter's column split (4000 and 8000) and classic's tab order (Arms, Fury,
Protection and so on), and classic's armour and weapon rules. `/beq probe`
on a character of the class prints its columns and top talents, and a
`classes` line listing every class the client knows, marking any without
weights.

Also unchecked: the quest window. `UI/QuestRewards.lua` hooks
`QuestInfo_Display` and finds the choice buttons through
`QuestInfoRewardsFrame.RewardButtons`, falling back to classic's named
`QuestInfoRewardsFrameQuestInfoItem<n>`; `/beq probe` lists whether
`QuestInfo_Display` exists. Also unchecked: the hunter's armour and weapon rules in `Weights.lua` (mail
from 40, no shields, maces or wands) are classic's.

## 2026-09-29, seventh probe: a level 20 warlock

The first class other than the hunter, and its layout matches the split
exactly. The probe's `columns` line puts the talents it sampled at:

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Improved Life Tap, Suppression, Improved Corruption, Pandemic | Affliction (below 4000) |
| 5020 to 6820 | Improved Health Funnel, Improved Imp, Demonic Embrace, Unholy Power | Demonology (4000 to 8000) |
| 9080 to 10280 | Destructive Reach, Improved Shadow Bolt, Bane | Destruction (above 8000) |

The tree is one tree (`type 4`, 52 nodes, 11 of 11 spent). `points per spec`
read 11 / 0 / 0 and `judged as affliction (talents)`, so the tab order and
`CLASSIC_COLUMNS` are right for the warlock.

The same probe read the main hand's stats as `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`,
`ITEM_MOD_INTELLECT_SHORT`, `ITEM_MOD_MANA_REGENERATION_SHORT`,
`ITEM_MOD_SPELL_POWER_SHORT` and `ITEM_MOD_SPIRIT_SHORT`, and a wand's as
`ITEM_MOD_DAMAGE_PER_SECOND_SHORT` and `ITEM_MOD_SPELL_POWER_SHORT`. So caster
items carry spell power and mp5 under the retail keys `Weights.lua` already
reads.

Still unchecked: the other seven classes' layouts.
