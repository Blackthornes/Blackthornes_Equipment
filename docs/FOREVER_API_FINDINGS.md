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
