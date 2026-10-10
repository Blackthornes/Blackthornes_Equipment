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
`QuestInfo_Display` exists.

Checked (2026-10-10, level 20 warlock in Undercity): the quest log calls
behind the panel's Quest log tab (`Logic/QuestLog.lua`). Forever has the
retail ones: `C_QuestLog.GetNumQuestLogEntries`, `GetInfo`,
`GetQuestObjectives`, `GetQuestWatchType`, `AddQuestWatch`,
`RemoveQuestWatch`, `GetQuestTagInfo`, `SetSelectedQuest`,
`IsPushableQuest` and `SetAbandonQuest`, with `GetNumQuestLeaderBoards`,
`GetQuestLogLeaderBoard`, `GetQuestLogSpecialItemInfo`,
`QuestLogPushQuest`, `StaticPopup_Show`, `QuestMapFrame_OpenToQuestDetails`,
`ToggleQuestLog`, `GetQuestDifficultyColor` and `ObjectiveTrackerFrame`.
The classic globals are gone (`GetNumQuestLogEntries`, `GetQuestLogTitle`,
`IsQuestWatched`, `AddQuestWatch`, `RemoveQuestWatch`,
`SelectQuestLogEntry`, `SetAbandonQuest`, `QuestLog_OpenToQuest`,
`QuestWatchFrame`), so the tab reads the C_QuestLog way: "27 lines, 21
quests in 6 headings, 21 tracked, 0 with an item button" (likely none of those
quests has one). Also unchecked: the hunter's armour and weapon rules in `Weights.lua` (mail
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

The other seven classes' layouts were checked later, by the eighth to
fourteenth probes below: all nine are confirmed.

Dual wield: `Compare` asks the client's `CanDualWield` (present, per the
probes below) and otherwise uses classic's trainer levels (warriors and hunters
20, rogues 10, nobody else). `/beq probe` prints a `can dual wield` line.

## 2026-09-30, eighth probe: a level 1 warrior

The warrior's tree matches the split too. One tree (`type 4`, "Warrior",
53 nodes, 0 of 0 spent at level 1), with its columns' top talents:

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Improved Heroic Strike, Deflection, Improved Rend, Improved Overpower | Arms (below 4000) |
| 5020 to 6820 | Improved Cleave, Booming Voice, Cruelty, Boundless Rage | Fury (4000 to 8000) |
| 9080 to 10880 | Improved Bloodrage, Shield Specialization, Anticipation, Improved Thunder Clap | Protection (above 8000) |

So classic's order (Arms, Fury, Protection) and `CLASSIC_COLUMNS` are right
for the warrior. With no points spent it is `judged as arms (default)`.

`CanDualWield` is **present** and answered `false` at level 1, as expected
before 20, so `Compare` uses the client's answer rather than the level table.
The main hand's only stat was `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`. Still to
see on a warrior: armour, defense and block values on higher-level gear.

## 2026-09-30, ninth probe: a level 20 paladin

The paladin's tree matches the split as well. One tree (`type 4`, "Paladin",
50 nodes, 11 of 11 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Healing Light, Divine Strength, Divine Intellect, Unyielding Faith | Holy (below 4000) |
| 5020 to 6820 | Precision, Toughness, Redoubt, Anticipation | Protection (4000 to 8000) |
| 9080 to 10880 | Improved Judgement, Deflection, Benediction, Pursuit of Justice | Retribution (above 8000) |

Points went into Redoubt (5) and Shield Specialization (1) at x6220 and
Anticipation (5) at x6820, so `points per spec` read 0 / 11 / 0 and
`judged as prot (talents)`: classic's order (Holy, Protection, Retribution)
is right.

The shield in the off hand read `RESISTANCE0_NAME=547` (its armour, which
`Weights` reads), `ITEM_MOD_SPELL_POWER_SHORT=5`, and nature resistance twice,
as `ITEM_MOD_NATURE_RESISTANCE_SHORT=5` and `RESISTANCE3_NAME=5`. Resistances
are left unweighted on purpose (they matter for a fight, not for levelling),
so the probe lists them under `not weighted`. No block value was reported on
this shield. `can dual wield` was `false`, right for a paladin.

## 2026-09-30, tenth probe: a level 16 rogue

The rogue's tree matches the split. One tree (`type 4`, "Rogue", 53 nodes,
7 of 7 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Improved Gouge, Remorseless Attacks, Malice, Improved Slice and Dice | Assassination (below 4000) |
| 5020 to 6820 | Improved Eviscerate, Improved Sinister Strike, Lightning Reflexes, Improved Sprint | Combat (4000 to 8000) |
| 9080 to 10880 | Camouflage, Master of Deception, Opportunity, Improved Ambush | Subtlety (above 8000) |

Forever has moved a couple of talents (Improved Gouge sits with
Assassination and Improved Eviscerate with Combat, the other way round from
classic), but each column is still one spec. Points in Camouflage (3),
Opportunity (2) and Master of Deception (2) read 0 / 0 / 7 and
`judged as sub (talents)`.

`can dual wield` was `true` at 16, matching the level 10 fallback. The
weapons read `ITEM_MOD_AGILITY_SHORT`, `ITEM_MOD_STAMINA_SHORT`,
`ITEM_MOD_STRENGTH_SHORT`, `ITEM_MOD_ATTACK_POWER_SHORT` and
`ITEM_MOD_DAMAGE_PER_SECOND_SHORT` (the ranged slot too), all weighted, with
nothing under `not weighted`.

## 2026-09-30, eleventh probe: a level 1 priest

The priest's tree matches the split. One tree (`type 4`, "Priest", 54 nodes,
0 of 0 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Power in Light, Wand Specialization, Twin Disciplines, Martyrdom | Discipline (below 4000) |
| 5020 to 6820 | Twilight Focus, Improved Renew, Holy Specialization, Inspiration | Holy (4000 to 8000) |
| 9080 to 10880 | Shadow Focus, Blackout, Spirit Tap, Shadow Reach | Shadow (above 8000) |

One odd node: a single talent named Holy Specialization sits at x9280, in
the Shadow part, besides the one heading the x6220 column. If a priest can
buy it, its points count toward Shadow. Worth a look on a priest with points
spent; if it matters, `Weights:TraitPoints` can place it by name instead.

`judged as shadow (default)` with no points, `can dual wield` `false`. The
main hand read only `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.

## 2026-09-30, twelfth probe: a level 1 shaman

The shaman's tree matches the split. One tree (`type 4`, "Shaman", 50 nodes,
0 of 0 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Elemental Warding, Convection, Concussion, Elemental Devastation | Elemental (below 4000) |
| 5020 to 6820 | Earth's Grasp, Thundering Strikes, Ancestral Knowledge, Improved Lightning Shield | Enhancement (4000 to 8000) |
| 9080 to 10880 | Mindfulness, Improved Healing Wave, Totemic Focus, Improved Reincarnation | Restoration (above 8000) |

`judged as enhancement (default)` with no points, `can dual wield` `false`
(a classic shaman never dual wields). The main hand read only
`ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.

## 2026-09-30, thirteenth probe: a level 1 mage

The mage's tree matches the split. One tree (`type 4`, "Mage", 54 nodes,
0 of 0 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Wand Specialization, Arcane Focus, Improved Channeling, Arcane Resilience | Arcane (below 4000) |
| 5020 to 6820 | Wake of Fire, Incineration, Improved Fireball, Master of Elements | Fire (4000 to 8000) |
| 9080 to 10880 | Frost Warding, Improved Frostbolt, Elemental Precision, Frostbite | Frost (above 8000) |

`judged as frost (default)` with no points, `can dual wield` `false`. The
main hand read only `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.

## 2026-09-30, fourteenth probe: a level 1 druid

The druid's tree matches the split, which makes all nine classes. One tree
(`type 4`, "Druid", 51 nodes, 0 of 0 spent):

| x | Talents | Column |
|---|---|---|
| 1020 to 2820 | Moonglow, Improved Wrath, Genesis, Nature's Reach | Balance (below 4000) |
| 5020 to 6820 | Feral Swiftness, Ferocity, Heart of the Wild, Thick Hide | Feral Combat (4000 to 8000) |
| 9080 to 10880 | Naturalist, Nature's Focus, Furor, Gift of the Earthmother | Restoration (above 8000) |

`judged as feral (default)` with no points, `can dual wield` `false`. The
main hand read only `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`.

So every class's tree on Forever is one trait tree with its three specs
side by side, split at 4000 and 8000, in classic's order. What is still
unseen is gear stats past the starting levels: block value, defense, dodge,
healing and mp5 on real items, and the resistances above.

## Not yet checked: weapon skills and faction

The weapon master line (`Logic/WeaponSkills.lua`) reads which weapon skills
the character knows from the spell each skill gives (196 One-Handed Axes,
1180 Daggers and so on, through `C_SpellBook.IsSpellKnown`, `IsPlayerSpell`
or `IsSpellKnown`) and from classic's `GetSkillLineInfo`, and the faction
from `UnitFactionGroup`. None of these has been seen on Forever yet.
`/beq probe` prints a `faction` line and a `weapon skills` line listing what
it read; if that line says none were read, the tooltip stays quiet rather
than guess. The trainer list itself is classic's (`Data/WeaponTrainers.lua`).

## Not yet checked: professions, random rolls and map pins

The upgrade finder's crafted gear, random rolls and upgrade hunts lean on
calls no probe has seen on Forever yet. `/beq probe` prints a line for each:

- `professions`: read from `C_TradeSkillUI.GetAllProfessionTradeSkillLines`
  and `GetProfessionInfoBySkillLineID`, else classic's `GetSkillLineInfo`.
  Whether a recipe is known comes from Tradeskills' saved recipes when it is
  loaded, else `IsPlayerSpell` / `C_SpellBook.IsSpellKnown` on the recipe's
  spell. If neither reads anything, crafted gear is still listed, as made by
  someone else.
- `Tradeskills recipes`: how many recipes Tradeskills has seen across
  characters (it records them when a profession window opens).
- `random roll stats`: whether `C_Item.GetItemStats` answers for a link
  carrying a roll (`item:id::::::suffix`). If not, rolled gear is judged
  plain and the tooltip has no roll line.
- `map pin`: whether `C_Map.SetUserWaypoint` and `UiMapPoint` exist. Zone
  map IDs are looked up by name under the top map
  (`C_Map.GetMapChildrenInfo`), never typed in.

The merchant and loot arrows read `C_MerchantFrame.GetItemLink` or
`GetMerchantItemLink`, and `GetLootSlotLink`, on the game's
`MerchantItemNItemButton` and `LootButtonN` frames. A client that builds
those windows differently simply gets no arrows there.

## 2026-10-05: feral druids and weapons (from guides, not a probe)

Forever's druid guides agree that, unlike classic, cat and bear attacks
scale with the weapon's damage (Cat Form gives 12 attack power of its own
instead of 40), and that druids can train polearms from level 20 (Woo Ping
in Stormwind, Archibald in Undercity). So feral weighs `meleeDps` like a
rogue does, and the druid's weapon list has polearms. Not yet seen in game.

## 2026-10-06, a player's Frost mage (from their screenshot, not a probe)

| Question | Answer | What it means here |
|---|---|---|
| School spell damage ("Increases damage done by Frost spells and effects by up to 10") | The game's own comparison lists it as "Frost Damage", but nothing here counted it, so Azure Silk Pants scored as Intellect alone | `Items:SchoolDamage` reads the Equip: line off `C_TooltipInfo.GetHyperlink` (by item ID if that is missing), and `Weights:Normalize` also takes any stat key naming a school. Not yet seen in game: `/beq probe` prints a `school damage` line under each worn slot that has some, and any school key `C_Item.GetItemStats` hands over. |
