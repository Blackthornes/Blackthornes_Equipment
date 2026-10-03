"""Writes Data/Crafts.lua and Data/Rolls.lua: gear players make, and the
random rolls ("of the Monkey") gear can come with.

Run from the repository root with the vmangos world database dump and
pfQuest checked out somewhere:

    python tools/make_crafts.py <world_full_14_june_2021.sql> <pfQuest>

  github.com/brotalnia/database    world_full_14_june_2021.7z, unpacked: the
                                   vmangos world database, which carries
                                   Classic 1.12's spell table (what a recipe
                                   makes and from what), the skill lines
                                   (which profession, at what skill), the
                                   trainers and what they teach, items, and
                                   the random property chances
  github.com/shagu/pfQuest         db/: where every NPC stands, who sells a
                                   recipe, and who drops one

Nothing in the output is typed by hand except PROFESSIONS below. As with
Sources.lua, the game supplies each item's stats when asked; these files only
say how an item is made and what rolls it can have.

Crafts.lua keeps every piece of equippable gear (weapons and armour, white
or better) that a recipe of the professions below makes, with its
materials, the skill it needs, and how the recipe is learned: from a
trainer (and which ones, for how much), from a recipe item (and who sells
or drops it), or with the profession itself. Rolls.lua keeps, for every
item there or in Data/Sources.lua (so run make_sources.py first) that has
random properties, which rolls it can
come with and how often.
"""

import collections
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from make_sources import (EQUIPPABLE, BAD_TITLE, parse_row, load_pfquest,  # noqa: E402
                          lua_table, place, faction_of, lua_string, num)

# The professions that make gear, by skill line. Cooking and First Aid make
# none, and Alchemy and Enchanting only the odd rod or trinket, which is kept.
PROFESSIONS = {
    164: "Blacksmithing", 165: "Leatherworking", 197: "Tailoring",
    202: "Engineering", 171: "Alchemy", 333: "Enchanting",
}

PATCH = 10       # item_template rows up to patch 1.12
BUILD = 5875     # spell and trainer rows up to client build 5875 (1.12.1)

CREATE_ITEM = 24
LEARN_SPELL = 36

# A recipe dropped by more creatures than this is a world drop, and the
# window says so rather than naming one of them.
NAMED_DROPPERS = 3

INSERT = re.compile(r"INSERT INTO `(\w+)` \(([^)]*)\) VALUES")


def tables(path, wanted):
    """Every row of the tables in `wanted` from one mysqldump file, as dicts."""
    out = {t: [] for t in wanted}
    current, columns = None, None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            m = INSERT.match(line)
            if m:
                current = m.group(1) if m.group(1) in wanted else None
                columns = [c.strip(" `") for c in m.group(2).split(",")]
                continue
            if not line.startswith("("):
                if line:
                    current = None
                continue
            if current is None:
                continue
            values = parse_row(line)
            if values is not None and len(values) == len(columns):
                row = dict(zip(columns, values))
                for k, v in row.items():
                    if isinstance(v, str):
                        row[k] = v.strip()
                out[current].append(row)
    return out


def latest(rows, key, version, highest):
    """One row per `key`: the newest whose `version` is at most `highest`."""
    best = {}
    for r in rows:
        if r[version] > highest:
            continue
        k = r[key]
        if k not in best or r[version] > best[k][version]:
            best[k] = r
    return best


def sources_items():
    """The item IDs Data/Sources.lua lists."""
    text = Path("Data/Sources.lua").read_text(encoding="utf-8")
    section = text.split("Sources.ITEMS = {", 1)[1]
    return {int(i) for i in re.findall(r"^\s*\[(\d+)\] =", section, re.M)}


def main():
    vm = tables(sys.argv[1], {
        "item_template", "spell_template", "skill_line_ability", "npc_trainer",
        "npc_trainer_template", "creature_template", "npc_vendor",
        "item_enchantment_template",
    })
    pfq = load_pfquest(Path(sys.argv[2]))
    listed = sources_items()

    items = latest(vm["item_template"], "entry", "patch", PATCH)
    spells = latest(vm["spell_template"], "entry", "build", BUILD)
    templates = latest(vm["creature_template"], "entry", "patch", PATCH)

    # Which profession teaches each spell, and the skill it asks.
    lines = {}
    for r in vm["skill_line_ability"]:
        if r["skill_id"] in PROFESSIONS and r["build"] <= BUILD:
            lines[r["spell_id"]] = r

    # Recipes that make gear.
    crafts = {}    # spell -> item
    for spellID, line in lines.items():
        spell = spells.get(spellID)
        if not spell:
            continue
        for e in (1, 2, 3):
            if spell[f"effect{e}"] != CREATE_ITEM:
                continue
            item = items.get(spell[f"effectItemType{e}"])
            if not item or item["class"] not in (2, 4):
                continue
            if item["inventory_type"] not in EQUIPPABLE or not 1 <= item["quality"] <= 5:
                continue
            if BAD_TITLE.search(item["name"]) or BAD_TITLE.search(spell["name"]):
                continue
            # Two recipes can make the same item; the cheaper skill wins.
            held = crafts.get(item["entry"])
            if held and lines[held]["req_skill_value"] <= line["req_skill_value"]:
                continue
            crafts[item["entry"]] = spellID
    by_spell = {s: i for i, s in crafts.items()}

    # Spells that teach a recipe: trainers and recipe items cast these.
    teaches = {}
    for spellID, spell in spells.items():
        for e in (1, 2, 3):
            if spell[f"effect{e}"] == LEARN_SPELL and spell[f"effectTriggerSpell{e}"] in by_spell:
                teaches[spellID] = spell[f"effectTriggerSpell{e}"]

    # Trainers: who teaches which recipe, for how much and from what skill.
    units, unit_names = pfq["units"]["data"], pfq["units"]["enUS"]
    zone_names = pfq["zones"]["enUS"]
    npcs, used_zones = {}, set()

    def npc(uid):
        if uid in npcs:
            return npcs[uid]
        where = place(units[uid])
        name = unit_names[uid]
        npcs[uid] = (name, where[0], where[1], where[2], faction_of(units[uid])) \
            if where and name else None
        return npcs[uid]

    by_template = collections.defaultdict(list)
    for uid, t in templates.items():
        if t["trainer_id"]:
            by_template[t["trainer_id"]].append(uid)

    trained = collections.defaultdict(dict)    # spell -> {npc: (cost, skill)}
    for r in vm["npc_trainer"] + vm["npc_trainer_template"]:
        if r["build_min"] > BUILD or r["build_max"] < BUILD:
            continue
        spellID = teaches.get(r["spell"], r["spell"])
        if spellID not in by_spell:
            continue
        givers = [r["entry"]] if r["entry"] in templates else by_template.get(r["entry"], [])
        for uid in givers:
            if npc(uid):
                trained[spellID][uid] = (r["spellcost"], r["reqskillvalue"])

    # Recipe items: what they teach, who sells and who drops them.
    pf_items = pfq["items"]["data"]
    recipes = {}     # recipe item -> dict
    taught_by = collections.defaultdict(list)
    for itemID, item in items.items():
        if item["class"] != 9 or BAD_TITLE.search(item["name"]):
            continue
        for n in range(1, 6):
            spellID = teaches.get(item[f"spellid_{n}"], item[f"spellid_{n}"])
            if spellID in by_spell:
                break
        else:
            continue
        entry = pf_items[itemID]
        vendors, droppers = [], {}
        if entry and entry["V"]:
            for uid, stock in lua_table(entry["V"]).items():
                if npc(uid):
                    vendors.append((uid, int(stock or 0)))
        if entry and entry["U"]:
            droppers = {uid: float(c) for uid, c in lua_table(entry["U"]).items()}
        named = []
        if 0 < len(droppers) <= NAMED_DROPPERS:
            for uid, chance in sorted(droppers.items(), key=lambda x: -x[1]):
                if unit_names[uid]:
                    named.append((unit_names[uid], round(chance, 1)))
        recipes[itemID] = {
            "name": item["name"], "spell": spellID, "skill": item["required_skill_rank"],
            "price": item["buy_price"] // max(1, item["buy_count"]),
            "vendors": sorted(vendors), "drops": len(droppers), "named": named,
        }
        taught_by[spellID].append(itemID)

    # Materials, and what a vendor sells them for when one sells them for
    # good (thread, dyes, flux, vials): the price a crafter really pays.
    sold_forever = set()
    vendor_items = collections.defaultdict(set)
    for r in vm["npc_vendor"]:
        vendor_items[r["item"]].add(r["entry"])
        if not r["maxcount"]:
            sold_forever.add(r["item"])
    reagents = {}

    rows = {}
    for itemID, spellID in crafts.items():
        item, spell, line = items[itemID], spells[spellID], lines[spellID]
        materials = []
        for n in range(1, 9):
            rid, count = spell[f"reagent{n}"], spell[f"reagentCount{n}"]
            if rid and count and rid in items:
                materials.append((rid, count))
                r = items[rid]
                reagents[rid] = (r["name"],
                                 r["buy_price"] // max(1, r["buy_count"]) if rid in sold_forever else 0)
        if not materials:
            continue
        teachers = trained.get(spellID, {})
        skill = line["req_skill_value"]
        if teachers:
            skill = max(skill, min(s for _, s in teachers.values()))
        for rid in taught_by.get(spellID, []):
            skill = max(skill, recipes[rid]["skill"])
        classes = item["allowable_class"]
        if classes in (-1, 0) or classes & 0x5DF == 0x5DF:
            classes = 0
        races = item["allowable_race"]
        if races in (-1, 0) or races & 0xFF == 0xFF:
            races = 0
        rows[itemID] = {
            "prof": line["skill_id"], "skill": skill, "spell": spellID,
            "req": item["required_level"], "ilvl": item["item_level"],
            "classes": classes, "races": races, "bop": 1 if item["bonding"] == 1 else 0,
            "materials": materials,
            "trainers": teachers, "recipes": taught_by.get(spellID, []),
            "start": 1 if line["learn_on_get_skill"] else 0,
            "wear": (item["required_skill"], item["required_skill_rank"]) if item["required_skill"] else None,
            "rep": (item["required_reputation_faction"], item["required_reputation_rank"])
            if item["required_reputation_faction"] else None,
        }

    used_npcs = set()
    for r in rows.values():
        used_npcs.update(r["trainers"])
        for rid in r["recipes"]:
            used_npcs.update(u for u, _ in recipes[rid]["vendors"])
    for uid in used_npcs:
        used_zones.add(npcs[uid][1])

    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/Crafts.lua")
    w("-- Gear players make: the profession and skill it needs, its materials, and")
    w("-- how the recipe is learned.")
    w("--")
    w("-- Generated by tools/make_crafts.py from Classic 1.12 data, never typed by")
    w("-- hand: the vmangos world database (recipes, skill lines, trainers, items)")
    w("-- and pfQuest's database (where every NPC stands, who sells or drops a")
    w("-- recipe). Forever may have changed some of it. The game fills in each")
    w("-- item's stats when asked.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Crafts = {}")
    w("ns.Crafts = Crafts")
    w("")
    w("Crafts.PROFESSIONS = {")
    for k in sorted(PROFESSIONS):
        w(f"    [{k}] = {lua_string(PROFESSIONS[k])},")
    w("}")
    w("")
    w("Crafts.ZONES = {")
    for z in sorted(used_zones):
        if zone_names[z]:
            w(f"    [{z}] = {lua_string(zone_names[z])},")
    w("}")
    w("")
    w("-- Trainers and recipe vendors: name, zone, x, y on that zone's map, and the")
    w("-- factions it serves (\"A\", \"H\", \"AH\").")
    w("Crafts.NPCS = {")
    for uid in sorted(used_npcs):
        name, zone, x, y, fac = npcs[uid]
        w(f"    [{uid}] = {{ {lua_string(name)}, {zone}, {num(x)}, {num(y)}, \"{fac}\" }},")
    w("}")
    w("")
    w("-- Materials: name, and the vendor price in copper when a vendor always has")
    w("-- it (0 when none does).")
    w("Crafts.MATERIALS = {")
    for rid in sorted(reagents):
        name, price = reagents[rid]
        w(f"    [{rid}] = {{ {lua_string(name)}, {price} }},")
    w("}")
    w("")
    w("-- Recipe items: name, the skill they ask, the vendor price in copper;")
    w("-- v = { npc, stock (0 for unlimited), ... } who sells it; d = how many")
    w("-- creatures drop it; n = { name, chance %, ... } who, when only a few do.")
    w("Crafts.RECIPES = {")
    used_recipes = sorted({rid for r in rows.values() for rid in r["recipes"]})
    for rid in used_recipes:
        r = recipes[rid]
        parts = [lua_string(r["name"]), str(r["skill"]), str(r["price"] if r["vendors"] else 0)]
        if r["vendors"]:
            parts.append("v = { " + ", ".join(f"{u}, {n}" for u, n in r["vendors"]) + " }")
        if r["drops"]:
            parts.append(f"d = {r['drops']}")
        if r["named"]:
            parts.append("n = { " + ", ".join(f"{lua_string(n)}, {num(c)}" for n, c in r["named"]) + " }")
        w(f"    [{rid}] = {{ {', '.join(parts)} }},")
    w("}")
    w("")
    # Most recipes are taught by every trainer of a rank, so each set of
    # trainers is written once and the gear names it by number.
    sets = {}
    for itemID in sorted(rows):
        if rows[itemID]["trainers"]:
            key = tuple(sorted(rows[itemID]["trainers"]))
            sets.setdefault(key, len(sets) + 1)
    w("-- Sets of trainers who teach the same recipes.")
    w("Crafts.TRAINERS = {")
    for key, index in sorted(sets.items(), key=lambda x: x[1]):
        w(f"    [{index}] = {{ {', '.join(str(u) for u in key)} }},")
    w("}")
    w("")
    w("-- Gear: profession, skill, the recipe's spell, required level, item level,")
    w("-- classes (0 for all), races (0 for all), 1 when it binds on pickup (so only")
    w("-- the crafter can wear it); m = { material, count, ... }; t = { cost,")
    w("-- set } what the trainers in that TRAINERS set charge to teach it;")
    w("-- r = { recipe item, ... }; s = 1 when the profession comes with it;")
    w("-- w = { skill line, rank } a skill the wearer needs; f = { faction,")
    w("-- standing } a reputation it needs.")
    w("Crafts.ITEMS = {")
    for itemID in sorted(rows):
        r = rows[itemID]
        parts = [str(r["prof"]), str(r["skill"]), str(r["spell"]), str(r["req"]), str(r["ilvl"]),
                 str(r["classes"]), str(r["races"]), str(r["bop"])]
        parts.append("m = { " + ", ".join(f"{i}, {c}" for i, c in r["materials"]) + " }")
        if r["trainers"]:
            cost = min(c for c, _ in r["trainers"].values())
            parts.append(f"t = {{ {cost}, {sets[tuple(sorted(r['trainers']))]} }}")
        if r["recipes"]:
            parts.append("r = { " + ", ".join(str(i) for i in sorted(r["recipes"])) + " }")
        if r["start"]:
            parts.append("s = 1")
        if r["wear"]:
            parts.append(f"w = {{ {r['wear'][0]}, {r['wear'][1]} }}")
        if r["rep"]:
            parts.append(f"f = {{ {r['rep'][0]}, {r['rep'][1]} }}")
        w(f"    [{itemID}] = {{ {', '.join(parts)} }},")
    w("}")
    w("")
    Path("Data/Crafts.lua").write_text("\n".join(out), encoding="utf-8", newline="\n")

    # Random rolls, for the gear either file lists.
    groups = collections.defaultdict(list)
    for r in vm["item_enchantment_template"]:
        if r["patch_min"] <= PATCH <= r["patch_max"] and r["chance"] > 0:
            groups[r["entry"]].append((r["ench"], float(r["chance"])))
    rolled = {}
    for itemID in sorted(set(rows) | listed):
        item = items.get(itemID)
        if item and item["random_property"] and groups.get(item["random_property"]):
            rolled[itemID] = item["random_property"]

    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/Rolls.lua")
    w("-- The random rolls (\"of the Monkey\") gear can come with, and how often.")
    w("--")
    w("-- Generated by tools/make_crafts.py from the vmangos world database's")
    w("-- item_enchantment_template (Classic 1.12), never typed by hand. A roll is")
    w("-- an ItemRandomProperties ID: the game says what stats it gives when asked")
    w("-- about a link that carries it.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local RollData = {}")
    w("ns.RollData = RollData")
    w("")
    w("-- Roll groups: { roll, chance %, ... }.")
    w("RollData.GROUPS = {")
    for g in sorted(set(rolled.values())):
        parts = ", ".join(f"{e}, {num(round(c, 2))}" for e, c in sorted(groups[g]))
        w(f"    [{g}] = {{ {parts} }},")
    w("}")
    w("")
    w("-- Which group each item rolls from.")
    w("RollData.ITEMS = {")
    for itemID in sorted(rolled):
        w(f"    [{itemID}] = {rolled[itemID]},")
    w("}")
    w("")
    Path("Data/Rolls.lua").write_text("\n".join(out), encoding="utf-8", newline="\n")

    print(f"crafts {len(rows)}, recipes {len(used_recipes)}, npcs {len(used_npcs)}, "
          f"materials {len(reagents)}, rolled items {len(rolled)}")


if __name__ == "__main__":
    main()
