"""Tests for tools/make_item_sets.py. Run: python tools/test_make_item_sets.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_item_sets import build, write  # noqa: E402

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


ITEMS = ",".join("ItemID_%d" % i for i in range(17))
ZEROS = lambda n: ",".join(["0"] * n)  # noqa: E731

folder = tempfile.mkdtemp()
try:
    table(folder, "ItemSet", "ID,Name_lang,SetFlags,RequiredSkill,RequiredSkillRank," + ITEMS, [
        '1,"Wolf Set",0,0,0,10,11,12,' + ZEROS(14),
        '2,"Proc Set",0,0,0,20,21,' + ZEROS(15),
        '3,"Smith Set",0,164,300,30,31,' + ZEROS(15),
        '4,"Lonely Set",0,0,0,40,' + ZEROS(16),
    ])
    table(folder, "ItemSetSpell", "ID,ChrSpecID,SpellID,TraitSubTreeID,Threshold,ItemSetID", [
        "1,0,100,0,2,1",
        "2,0,101,0,3,1",
        "3,0,102,0,2,2",
        "4,0,103,0,2,3",
        "5,0,100,0,2,4",
        "6,71,100,0,2,1",
    ])
    table(folder, "SpellEffect", ("ID,Effect,EffectAura,EffectBasePointsF,EffectItemType,"
                                  "EffectMiscValue_0,EffectTriggerSpell,SpellID"), [
        # 2 pieces: +10 Agility and +20 attack power.
        "1,6,29,10,0,1,0,100",
        "2,6,99,20,0,0,0,100",
        # 3 pieces: +1% spell crit.
        "3,6,57,1,0,0,0,101",
        # A proc: nothing to score.
        "4,6,42,5,0,0,0,102",
        # +200 armor.
        "5,6,22,200,0,1,0,103",
    ])
    sets = build(folder)
    expect("a set with stat bonuses is kept", 1 in sets)
    expect("its items", sets[1]["items"] == [10, 11, 12])
    expect("the 2 piece bonus", sets[1]["b"][2] == {"agility": 10, "attackPower": 20})
    expect("spell crit counts", sets[1]["b"][3] == {"spellCrit": 1})
    expect("a spec only bonus is left out", sets[1]["b"][2].get("agility") == 10)
    expect("a proc only set is left out", 2 not in sets)
    expect("armor counts", sets[3]["b"][2] == {"armor": 200})
    expect("its profession is kept", sets[3]["skill"] == 164 and sets[3]["rank"] == 300)
    expect("a one item set is left out", 4 not in sets)
    text = write(sets, "1.2.3")
    expect("the file names the build", "(build 1.2.3)" in text)
    expect("the file has the bonus", "[2] = { agility = 10, attackPower = 20 }" in text)
    expect("and the skill", "skill = 164, rank = 300" in text)
finally:
    shutil.rmtree(folder)

print("make_item_sets: %d checks, %d failures" % (checks, failures))
sys.exit(1 if failures else 0)
