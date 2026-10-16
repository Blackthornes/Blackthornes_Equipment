"""Writes Data/Enchants.lua: the enchants players make for their own gear,
what each one gives, where it goes and what it takes.

Run from the repository root:

    python tools/make_enchants.py <tables folder> [--build 1.60.1.70338]
        [--skills <Tradeskills' Data/LearnSpots.lua>] [--stdout]

The tables folder holds the Forever client's game tables as CSV, one file
per table. Read: SkillLineAbility, SpellEffect, SpellName, SpellReagents,
SpellEquippedItems, SpellItemEnchantment, ItemEffect, ItemXItemEffect, Item
and ItemSparse (only ID, Display_lang, RequiredSkill and RequiredSkillRank).
The tables are never copied into the repository.

What goes in:
  * every Enchanting recipe that puts an enchant on gear, and every
    Engineering scope and Leatherworking or Blacksmithing kit (an item
    made by a recipe that, used, puts an enchant on gear). A kit is keyed
    by the recipe that makes it, since that is what a player learns.
  * what each enchant any of those (or any other spell that enchants
    gear) gives, so the enchant already on a worn piece can be weighed.

The skill to learn a recipe is Tradeskills' (its Data/LearnSpots.lua, read
from the sister repository beside this one unless --skills names it), else
the recipe item's, else left out. Test and placeholder spells are left out.
Rerun it whenever the client tables are pulled again.

Options:
    --build    the client build, written in the file's header
    --skills   Tradeskills' Data/LearnSpots.lua
    --stdout   print the file instead of writing it
"""

import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "Enchants.lua")
SISTER_SKILLS = os.path.join(os.path.dirname(ROOT), "Blackthornes_Tradeskills", "Data", "LearnSpots.lua")

ENCHANTING, LEATHERWORKING, ENGINEERING, BLACKSMITHING = 333, 165, 202, 164
LINES = (ENCHANTING, LEATHERWORKING, ENGINEERING, BLACKSMITHING)

# Spell effects.
ENCHANT_ITEM, CREATE_ITEM, APPLY_AURA = 53, 24, 6
# Item effect trigger: the spell a recipe item teaches.
TEACHES = 6
RECIPE_CLASS = 9

# Names that mark a test or unused spell.
JUNK = re.compile(r"\bQA|\bTest\b|\[PH\]|^zz|Deprecated|\bOLD\b|UNUSED|\bDND\b", re.I)

# Where each inventory type is worn, as the game's equipment slot.
INV_SLOT = {
    1: 1, 3: 3, 5: 5, 20: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 16: 15,
}
SHIELD_INV = 14
# Weapon subclasses: two-handed ones and ranged ones.
TWO_HANDED = (1, 5, 6, 8, 10)
RANGED = (2, 3, 18)
SHIELD_SUB = 6

# Stat-type enchant effects (ItemModType) and the stat they give.
MOD_TYPE = {
    0: "mana", 1: "health", 3: "agility", 4: "strength", 5: "intellect",
    6: "spirit", 7: "stamina", 12: "defense", 13: "dodge", 14: "parry",
    15: "block", 31: "hit", 32: "crit", 38: "attackPower",
    39: "rangedAttackPower", 41: "healing", 42: "spellPower", 43: "mp5",
    45: "spellPower", 48: "blockValue",
}
STAT_MISC = {0: "strength", 1: "agility", 2: "stamina", 3: "intellect", 4: "spirit"}
SCHOOL = {2: "holyDamage", 4: "fireDamage", 8: "natureDamage", 16: "frostDamage",
          32: "shadowDamage", 64: "arcaneDamage"}
ALL_SCHOOLS = 126
# Aura types on an enchant's equip spell and the stat each gives.
AURA = {
    85: "mp5", 99: "attackPower", 124: "rangedAttackPower", 135: "healing",
    34: "health", 35: "mana", 52: "crit", 71: "spellCrit", 54: "hit",
    55: "spellHit", 49: "dodge", 47: "parry", 51: "block", 158: "blockValue",
}
AURA_STAT, AURA_RESIST, AURA_SPELL_DAMAGE, AURA_SKILL = 29, 22, 13, 30
DEFENSE_SKILL = 95
ARMOR_MASK = 1

# Enchant effect types.
EFFECT_PROC, EFFECT_DAMAGE, EFFECT_SPELL, EFFECT_RESIST, EFFECT_STAT = 1, 2, 3, 4, 5


def rows(folder, name):
    path = os.path.join(folder, name + ".csv")
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def num(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        try:
            return int(round(float(value)))
        except (TypeError, ValueError):
            return default


def read_skills(path):
    """{ recipe ID: skill to learn } from Tradeskills' LearnSpots.lua."""
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        text = f.read()
    start = text.find("Spots.SKILLS = {")
    if start < 0:
        return out
    end = text.find("\n}", start)
    for match in re.finditer(r"\[(\d+)\] = \{ (\d+),", text[start:end]):
        out[int(match.group(1))] = int(match.group(2))
    return out


class Tables:
    def __init__(self, folder):
        self.names = {num(r["ID"]): r["Name_lang"] for r in rows(folder, "SpellName")}
        self.effects = {}
        for r in rows(folder, "SpellEffect"):
            self.effects.setdefault(num(r["SpellID"]), []).append(r)
        self.reagents = {num(r["SpellID"]): r for r in rows(folder, "SpellReagents")}
        self.equipped = {num(r["SpellID"]): r for r in rows(folder, "SpellEquippedItems")}
        self.enchants = {num(r["ID"]): r for r in rows(folder, "SpellItemEnchantment")}
        self.abilities = [r for r in rows(folder, "SkillLineAbility") if num(r["SkillLine"]) in LINES]
        item_effects = {num(r["ID"]): r for r in rows(folder, "ItemEffect")}
        self.item_class = {num(r["ID"]): num(r["ClassID"]) for r in rows(folder, "Item")}
        self.sparse = {}
        for r in rows(folder, "ItemSparse"):
            self.sparse[num(r["ID"])] = (r.get("Display_lang", ""), num(r.get("RequiredSkillRank")))
        self.use_spell = {}   # item ID: the spell it casts when used
        self.taught_by = {}   # spell ID: recipe items that teach it
        for r in rows(folder, "ItemXItemEffect"):
            effect = item_effects.get(num(r["ItemEffectID"]))
            if not effect:
                continue
            item, spell, trigger = num(r["ItemID"]), num(effect["SpellID"]), num(effect["TriggerType"])
            if trigger == TEACHES and self.item_class.get(item) == RECIPE_CLASS:
                self.taught_by.setdefault(spell, []).append(item)
            elif trigger == 0 and spell:
                self.use_spell.setdefault(item, spell)

    def enchant_of(self, spell):
        for e in self.effects.get(spell, ()):
            if num(e["Effect"]) == ENCHANT_ITEM and num(e["EffectMiscValue_0"]) > 0:
                return num(e["EffectMiscValue_0"])
        return None

    def made_item(self, spell):
        for e in self.effects.get(spell, ()):
            if num(e["Effect"]) == CREATE_ITEM and num(e["EffectItemType"]) > 0:
                return num(e["EffectItemType"])
        return None

    def materials(self, spell):
        r = self.reagents.get(spell)
        out = []
        if not r:
            return out
        for i in range(8):
            item, count = num(r.get("Reagent_%d" % i)), num(r.get("ReagentCount_%d" % i))
            if item > 0 and count > 0:
                out += [item, count]
        return out

    def slots(self, spell):
        """(slots, weapon kind) the enchant spell fits, or None.

        Weapon kind: 1 any melee weapon, 2 two-handed only, 3 ranged."""
        r = self.equipped.get(spell)
        if not r:
            return None
        cls, inv, sub = num(r["EquippedItemClass"]), num(r["EquippedItemInvTypes"]), num(r["EquippedItemSubclass"])
        slots = sorted({slot for t, slot in INV_SLOT.items() if inv & (1 << t)})
        if slots:
            return slots, None
        if cls == 4:
            if inv & (1 << SHIELD_INV) or sub & (1 << SHIELD_SUB):
                return [17], None
            return None
        if cls == 2:
            if sub and all(sub & (1 << s) == 0 for s in range(32) if s not in RANGED) :
                return [18], 3
            if sub and all(sub & (1 << s) == 0 for s in range(32) if s not in TWO_HANDED):
                return [16], 2
            return [16], 1
        return None

    def gives(self, enchant):
        """{ stats }, weapon damage, and whether it gives anything else: a proc,
    a resistance or anything else stats can't weigh."""
        r = self.enchants.get(enchant)
        stats, damage, proc = {}, 0, False
        if not r:
            return stats, damage, proc

        def add(key, value):
            if key and value:
                stats[key] = stats.get(key, 0) + value

        for i in range(3):
            kind, points, arg = num(r["Effect_%d" % i]), num(r["EffectPointsMin_%d" % i]), num(r["EffectArg_%d" % i])
            if kind == EFFECT_PROC:
                proc = True
            elif kind == EFFECT_RESIST and arg != 0:
                proc = True
            elif kind == EFFECT_DAMAGE:
                damage += points
            elif kind == EFFECT_RESIST:
                if arg == 0:
                    add("armor", points)
            elif kind == EFFECT_STAT:
                if arg in MOD_TYPE:
                    add(MOD_TYPE[arg], points)
                else:
                    proc = True
            elif kind == EFFECT_SPELL:
                before = dict(stats)
                for e in self.effects.get(arg, ()):
                    if num(e["Effect"]) != APPLY_AURA:
                        continue
                    aura, misc, value = num(e["EffectAura"]), num(e["EffectMiscValue_0"]), num(e["EffectBasePointsF"])
                    if aura == AURA_STAT:
                        for k in (STAT_MISC.values() if misc == -1 else [STAT_MISC.get(misc)]):
                            add(k, value)
                    elif aura == AURA_RESIST:
                        if misc & ARMOR_MASK:
                            add("armor", value)
                        else:
                            proc = True
                    elif aura == AURA_SPELL_DAMAGE:
                        if misc & ALL_SCHOOLS == ALL_SCHOOLS:
                            add("spellPower", value)
                        else:
                            for bit, k in SCHOOL.items():
                                if misc & bit:
                                    add(k, value)
                    elif aura == AURA_SKILL:
                        if misc == DEFENSE_SKILL:
                            add("defense", value)
                    else:
                        add(AURA.get(aura), value)
                if stats == before:
                    proc = True
        return stats, damage, proc


def junk(name):
    return not name or bool(JUNK.search(name))


def build(folder, skills=None):
    t = Tables(folder)
    skills = skills or {}
    recipes, effects, materials = {}, {}, set()

    # What every enchant on gear gives, for the one already worn.
    for spell, effs in t.effects.items():
        for e in effs:
            if num(e["Effect"]) == ENCHANT_ITEM and num(e["EffectMiscValue_0"]) > 0:
                enchant = num(e["EffectMiscValue_0"])
                if enchant not in effects and enchant in t.enchants:
                    effects[enchant] = t.gives(enchant)

    for a in t.abilities:
        line, spell = num(a["SkillLine"]), num(a["Spell"])
        name = t.names.get(spell, "")
        if junk(name) or spell in recipes:
            continue
        enchant, apply, kit = t.enchant_of(spell), spell, None
        if not enchant:
            made = t.made_item(spell)
            use = made and t.use_spell.get(made)
            enchant = use and t.enchant_of(use)
            if not enchant:
                continue
            apply, kit = use, made
            name = t.sparse.get(made, ("",))[0] or name
            if junk(name):
                continue
        elif line != ENCHANTING and line != ENGINEERING:
            continue
        fits = t.slots(apply)
        if not fits or enchant not in effects:
            continue
        stats, damage, proc = effects[enchant]
        if not stats and not damage:
            continue
        taught = sorted(t.taught_by.get(spell, []))
        learn = skills.get(spell)
        if learn is None:
            ranks = [t.sparse.get(i, ("", 0))[1] for i in taught]
            ranks = [r for r in ranks if r > 0]
            learn = min(ranks) if ranks else None
        mats = t.materials(spell)
        materials.update(mats[0::2])
        recipes[spell] = {
            "name": name, "e": enchant, "line": line, "slots": fits[0], "w": fits[1],
            "k": learn, "y": num(a["TrivialSkillLineRankLow"]) or None,
            "g": num(a["TrivialSkillLineRankHigh"]) or None,
            "m": mats, "r": taught, "kit": kit,
        }

    names = {}
    for item in sorted(materials):
        n = t.sparse.get(item, ("",))[0]
        if n:
            names[item] = n
    return recipes, effects, names, t


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_list(values):
    return "{ " + ", ".join(str(v) for v in values) + " }"


def write(recipes, effects, names, t, build_name):
    out = []
    out.append("-- Blackthornes Equipment -- Data/Enchants.lua")
    out.append("-- The enchants players make for their own gear: what each gives, where it")
    out.append("-- goes, the profession and skill it needs and its materials.")
    out.append("--")
    out.append("-- Generated by tools/make_enchants.py from the Forever client's game tables"
               + (" (build %s)" % build_name if build_name else "") + ", never")
    out.append("-- typed by hand.")
    out.append("")
    out.append("local _, ns = ...")
    out.append("")
    out.append("local EnchantData = {}")
    out.append("ns.EnchantData = EnchantData")
    out.append("")
    out.append("-- [recipe ID] = { e = enchant, line = profession, slots = { equipment slot },")
    out.append("--   w = weapon kind (1 any melee, 2 two-handed, 3 ranged), k = skill to learn,")
    out.append("--   y = yellow from, g = grey from, m = { material, count, ... },")
    out.append("--   r = { recipe item }, kit = the item made, used on the gear, name }")
    out.append("EnchantData.RECIPES = {")
    for spell in sorted(recipes):
        r = recipes[spell]
        parts = ["e = %d" % r["e"], "line = %d" % r["line"], "slots = " + lua_list(r["slots"])]
        if r["w"]:
            parts.append("w = %d" % r["w"])
        for key in ("k", "y", "g"):
            if r[key]:
                parts.append("%s = %d" % (key, r[key]))
        if r["m"]:
            parts.append("m = " + lua_list(r["m"]))
        if r["r"]:
            parts.append("r = " + lua_list(r["r"]))
        if r["kit"]:
            parts.append("kit = %d" % r["kit"])
        parts.append("name = " + lua_string(r["name"]))
        out.append("    [%d] = { %s }," % (spell, ", ".join(parts)))
    out.append("}")
    out.append("")
    out.append("-- [enchant ID] = { s = { stat = value }, dmg = weapon damage, n = name,")
    out.append("--   other = 1 when it also gives something stats can't weigh (a proc, a")
    out.append("--   resistance, absorbing damage) }")
    out.append("EnchantData.EFFECTS = {")
    for enchant in sorted(effects):
        stats, damage, proc = effects[enchant]
        parts = []
        if stats:
            parts.append("s = { " + ", ".join("%s = %d" % (k, v) for k, v in sorted(stats.items())) + " }")
        if damage:
            parts.append("dmg = %d" % damage)
        if proc:
            parts.append("other = 1")
        n = t.enchants[enchant]["Name_lang"]
        if n and "$" not in n:
            parts.append("n = " + lua_string(n))
        out.append("    [%d] = { %s }," % (enchant, ", ".join(parts)))
    out.append("}")
    out.append("")
    out.append("-- [item ID] = name, for materials the client has not loaded yet.")
    out.append("EnchantData.MATERIALS = {")
    for item in sorted(names):
        out.append("    [%d] = %s," % (item, lua_string(names[item])))
    out.append("}")
    out.append("")
    return "\n".join(out)


def main(argv):
    args = list(argv)
    build_name, skills_path, to_stdout = None, SISTER_SKILLS, False
    folder = None
    while args:
        a = args.pop(0)
        if a == "--build":
            build_name = args.pop(0)
        elif a == "--skills":
            skills_path = args.pop(0)
        elif a == "--stdout":
            to_stdout = True
        elif folder is None:
            folder = a
        else:
            raise SystemExit(__doc__)
    if not folder:
        raise SystemExit(__doc__)
    recipes, effects, names, t = build(folder, read_skills(skills_path))
    text = write(recipes, effects, names, t, build_name)
    if to_stdout:
        sys.stdout.write(text)
    else:
        with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("Wrote %s: %d recipes, %d enchants." % (os.path.relpath(OUTPUT, ROOT), len(recipes), len(effects)))


if __name__ == "__main__":
    main(sys.argv[1:])
