"""Tests for tools/make_enchants.py. Run: python tools/test_make_enchants.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_enchants import build, read_skills, write  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def table(folder, name, header, lines):
    with open(os.path.join(folder, name + ".csv"), "w", encoding="utf-8") as f:
        f.write(header + "\n" + "\n".join(lines) + "\n")


SPELL_EFFECT = ("ID,Effect,EffectAura,EffectBasePointsF,EffectItemType,"
                "EffectMiscValue_0,EffectTriggerSpell,SpellID")
ENCHANT = ("ID,Name_lang,Effect_0,Effect_1,Effect_2,EffectPointsMin_0,EffectPointsMin_1,"
           "EffectPointsMin_2,EffectArg_0,EffectArg_1,EffectArg_2")

folder = tempfile.mkdtemp()
try:
    table(folder, "SpellName", "ID,Name_lang", [
        '1,"Enchant Chest - Minor Intellect"',
        '2,"Enchant 2H Weapon - Impact"',
        '3,"QAEnchant Cloak +3 Agility"',
        '4,"Light Armor Kit"',
        '5,"Light Armor Kit"',
        '6,"Enchant Cloak - Fire Resistance"',
        '7,"Enchant Weapon - Spell Power"',
        '8,"Enchant Weapon - Crusader"',
        '9,"Crude Scope"',
        '10,"Scope"',
    ])
    table(folder, "SpellEffect", SPELL_EFFECT, [
        "1,53,0,0,0,24,0,1",
        "2,53,0,0,0,805,0,2",
        "3,53,0,0,0,76,0,3",
        "4,24,0,0,2304,0,0,4",
        "5,53,0,0,0,15,0,5",
        "6,53,0,0,0,256,0,6",
        "7,53,0,0,0,2504,0,7",
        "8,53,0,0,0,1900,0,8",
        "9,24,0,0,4405,0,0,9",
        "10,53,0,0,0,30,0,10",
        # Spell Power's equip spell: all schools, and healing.
        "11,6,13,30,0,126,0,500",
        "12,6,135,30,0,0,0,500",
        # Fire resistance's equip spell.
        "13,6,22,10,0,4,0,600",
        # The recipe item teaches spell 1.
        "14,36,0,0,0,0,0,900",
    ])
    table(folder, "SpellItemEnchantment", ENCHANT, [
        '24,"Intellect +2",5,0,0,2,0,0,5,0,0',
        '805,"Weapon Damage +4",2,0,0,4,0,0,0,0,0',
        '76,"+3 Agility",5,0,0,3,0,0,3,0,0',
        '15,"Stamina +$k2 and Armor +$k1",4,5,0,8,1,0,0,7,0',
        '256,"+10 Fire Resistance",3,0,0,0,0,0,600,0,0',
        '2504,"Spell Power",3,0,0,0,0,0,500,0,0',
        '1900,"Crusader",1,0,0,0,0,0,20007,0,0',
        '30,"Scope (+1 Damage)",2,0,0,1,0,0,0,0,0',
    ])
    table(folder, "SpellReagents", "ID,SpellID,Reagent_0,Reagent_1,ReagentCount_0,ReagentCount_1", [
        "1,1,10938,0,1,0",
        "2,2,10940,10978,2,1",
        "3,4,2318,0,1,0",
    ])
    table(folder, "SpellEquippedItems", "ID,SpellID,EquippedItemClass,EquippedItemInvTypes,EquippedItemSubclass", [
        "1,1,4,1048608,-1",
        "2,2,2,0,1378",
        "3,3,2,65536,0",
        "4,5,4,1440,-1",
        "5,6,4,65536,-1",
        "6,7,2,0,189939",
        "7,8,2,0,189939",
        "8,10,2,0,262156",
    ])
    table(folder, "SkillLineAbility",
          "ID,SkillLine,Spell,MinSkillLineRank,TrivialSkillLineRankLow,TrivialSkillLineRankHigh", [
              "1,333,1,1,80,120",
              "2,333,2,1,130,170",
              "3,333,3,1,1,1",
              "4,165,4,1,30,60",
              "5,333,6,1,150,190",
              "6,333,7,1,320,360",
              "7,333,8,1,320,360",
              "8,202,9,1,90,120",
              "9,171,99,1,1,1",
          ])
    table(folder, "ItemEffect", "ID,TriggerType,SpellID", ["1,0,5", "2,6,1", "3,0,10"])
    table(folder, "ItemXItemEffect", "ID,ItemEffectID,ItemID", ["1,1,2304", "2,2,6342", "3,3,4405"])
    table(folder, "Item", "ID,ClassID", ["2304,0", "6342,9", "4405,0", "10938,7"])
    table(folder, "ItemSparse", "ID,Display_lang,RequiredSkill,RequiredSkillRank", [
        '2304,"Light Armor Kit",0,0',
        '6342,"Formula: Enchant Chest - Minor Intellect",333,20',
        '4405,"Crude Scope",0,0',
        '10938,"Lesser Magic Essence",0,0',
    ])
    recipes, effects, names, tables = build(folder, {2: 100})
    text = write(recipes, effects, names, tables, "1.2.3")
finally:
    shutil.rmtree(folder)

chest = recipes.get(1)
expect("an Enchanting recipe is kept", chest is not None)
expect("it goes on the chest, robes too", chest and chest["slots"] == [5])
expect("its stats are read", effects[24][0] == {"intellect": 2})
expect("the recipe item's skill stands in", chest and chest["k"] == 20)
expect("yellow and grey come with it", chest and chest["y"] == 80 and chest["g"] == 120)
expect("the recipe item is listed", chest and chest["r"] == [6342])
expect("materials are listed", chest and chest["m"] == [10938, 1])
expect("material names are kept", names.get(10938) == "Lesser Magic Essence")

impact = recipes.get(2)
expect("a two-hand enchant says so", impact and impact["slots"] == [16] and impact["w"] == 2)
expect("weapon damage is read", effects[805][1] == 4)
expect("Tradeskills' skill wins", impact and impact["k"] == 100)

expect("a test spell is left out", 3 not in recipes)
expect("its enchant is still weighed", 76 in effects)

kit = recipes.get(4)
expect("an armor kit is kept by the recipe that makes it", kit is not None)
expect("its item is named", kit and kit["kit"] == 2304 and kit["name"] == "Light Armor Kit")
expect("it fits chest, legs, feet and hands", kit and kit["slots"] == [5, 7, 8, 10])
expect("armor and a stat both count", effects[15][0] == {"armor": 8, "stamina": 1})

expect("only a resistance is not offered", 6 not in recipes)
expect("a resistance is something else", effects[256][2] is True)

power = recipes.get(7)
expect("an equip spell's stats are read", effects[2504][0] == {"spellPower": 30, "healing": 30})
expect("any melee weapon", power and power["w"] == 1)
expect("a proc alone is not offered", 8 not in recipes)

scope = recipes.get(9)
expect("a scope goes on the ranged slot", scope and scope["slots"] == [18] and scope["w"] == 3)

expect("other professions are left out", 99 not in recipes)
expect("the build is named", "(build 1.2.3)" in text)
expect("names with placeholders are left out", "$k" not in text)
expect("a resistance is marked other", "[256] = { other = 1" in text)
expect("the file never names a site", "wago" not in text.lower() and "wowhead" not in text.lower())

folder = tempfile.mkdtemp()
try:
    path = os.path.join(folder, "LearnSpots.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write("Spots.SKILLS = {\n    [7443] = { 20, 80, 120 },\n    [7745] = { 100, 130, 170 },\n}\n"
                "Spots.TRAINERS = {\n    [1] = { 5, 6 },\n}\n")
    skills = read_skills(path)
finally:
    shutil.rmtree(folder)
expect("Tradeskills' skills are read", skills == {7443: 20, 7745: 100})
expect("no file reads nothing", read_skills(None) == {} and read_skills("/nowhere/at/all.lua") == {})

print("%d checks, %d failed" % (checks, failures))
sys.exit(1 if failures else 0)
