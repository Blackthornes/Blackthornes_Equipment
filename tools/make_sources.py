"""Writes Data/Sources.lua: where gear comes from, for the upgrade finder.

Run from the repository root with two Classic 1.12 databases checked out
somewhere:

    python tools/make_sources.py <mangoszero database> <pfQuest>

  github.com/mangoszero/database   World/Setup/FullDB: what each item is
                                   (slot, level, quality, who may use it),
                                   quest rewards, loot tables, and which map
                                   a creature lives on
  github.com/shagu/pfQuest         db/: vendors and their stock, which
                                   quests are really given out, and where
                                   every NPC and object stands, in zone map
                                   coordinates

Nothing in the output is typed by hand except DUNGEONS below. The game
fills in each item's stats when the addon asks, so the file only says where
an item comes from, never what it is worth.

Kept:
  vendors   every white or better piece of gear sold by an NPC who stands
            somewhere in the world (not in an instance)
  quests    every white or better gear reward, choice or fixed, of a quest
            that has a known start, and the quests before it in its chain;
            seasonal event quests are left out
  dungeons  green or better gear that drops from a creature in one of the
            dungeons or raids below at 1% or more, which in practice is the
            bosses and the few trash mobs with their own loot
Gear that needs a reputation carries the faction and standing, so the finder
can check the player's own. Items that need a profession or a PvP rank are
left out: the finder is for gear a player can go and get.
"""

import collections
import re
import sys
from pathlib import Path

from lupa import lua51

# Equippable inventory types, by item_template.InventoryType. Shirts (4),
# bags (18), tabards (19), ammunition (24) and quivers (27) carry nothing
# worth weighing.
EQUIPPABLE = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 20,
              21, 22, 23, 25, 26, 28}

# Classic's race bits: Human, Dwarf, Night Elf, Gnome / Orc, Undead, Tauren,
# Troll.
ALLIANCE_RACES = 1 | 4 | 8 | 64
HORDE_RACES = 2 | 16 | 32 | 128

DROP_CHANCE_MIN = 1.0   # percent

# How far back a quest chain is followed. The longest gear chains in Classic
# run to about a dozen quests.
QUEST_CHAIN_MOST = 20

# The dungeons, by map ID: name, recommended levels, the zone the entrance is
# in, and the faction that can reach it without fighting through a city
# ("" for both). Classic's recommended ranges.
DUNGEONS = {
    389: ("Ragefire Chasm", 13, 18, "Orgrimmar", "H"),
    43: ("Wailing Caverns", 17, 24, "The Barrens", ""),
    36: ("The Deadmines", 17, 26, "Westfall", ""),
    33: ("Shadowfang Keep", 22, 30, "Silverpine Forest", ""),
    48: ("Blackfathom Deeps", 24, 32, "Ashenvale", ""),
    34: ("The Stockade", 24, 32, "Stormwind City", "A"),
    90: ("Gnomeregan", 29, 38, "Dun Morogh", ""),
    47: ("Razorfen Kraul", 29, 38, "The Barrens", ""),
    189: ("Scarlet Monastery", 26, 45, "Tirisfal Glades", ""),
    129: ("Razorfen Downs", 37, 46, "The Barrens", ""),
    70: ("Uldaman", 41, 51, "Badlands", ""),
    209: ("Zul'Farrak", 44, 54, "Tanaris", ""),
    349: ("Maraudon", 46, 55, "Desolace", ""),
    109: ("Sunken Temple", 50, 56, "Swamp of Sorrows", ""),
    230: ("Blackrock Depths", 52, 60, "Blackrock Mountain", ""),
    229: ("Blackrock Spire", 55, 60, "Blackrock Mountain", ""),
    429: ("Dire Maul", 55, 60, "Feralas", ""),
    329: ("Stratholme", 58, 60, "Eastern Plaguelands", ""),
    289: ("Scholomance", 58, 60, "Western Plaguelands", ""),
}

# The raids, the same way. All of them open at 60.
RAIDS = {
    309: ("Zul'Gurub", 60, 60, "Stranglethorn Vale", ""),
    409: ("Molten Core", 60, 60, "Blackrock Mountain", ""),
    249: ("Onyxia's Lair", 60, 60, "Dustwallow Marsh", ""),
    469: ("Blackwing Lair", 60, 60, "Blackrock Mountain", ""),
    509: ("Ruins of Ahn'Qiraj", 60, 60, "Silithus", ""),
    531: ("Temple of Ahn'Qiraj", 60, 60, "Silithus", ""),
    533: ("Naxxramas", 60, 60, "Eastern Plaguelands", ""),
}
INSTANCES = {**DUNGEONS, **RAIDS}

# Factions whose standing gear asks for, by Faction.dbc ID. The game names
# them itself when it can; these are for when it cannot.
FACTIONS = {
    21: "Booty Bay", 47: "Ironforge", 54: "Gnomeregan Exiles", 59: "Thorium Brotherhood",
    68: "Undercity", 69: "Darnassus", 72: "Stormwind", 76: "Orgrimmar",
    81: "Thunder Bluff", 87: "Bloodsail Buccaneers", 270: "Zandalar Tribe",
    349: "Ravenholdt", 369: "Gadgetzan", 470: "Ratchet", 509: "League of Arathor",
    510: "The Defilers", 529: "Argent Dawn", 530: "Darkspear Trolls",
    576: "Timbermaw Hold", 577: "Everlook", 589: "Wintersaber Trainers",
    609: "Cenarion Circle", 729: "Frostwolf Clan", 730: "Stormpike Guard",
    749: "Hydraxian Waterlords", 809: "Shen'dralar", 889: "Warsong Outriders",
    890: "Silverwing Sentinels", 909: "Darkmoon Faire", 910: "Brood of Nozdormu",
}

# Scarlet Monastery is four dungeons behind one door, so its bosses carry
# their wing's own levels.
WINGS = {
    "Graveyard": (26, 36, [3983, 4543, 6490, 6488, 6489]),
    "Library": (29, 39, [3974, 6487]),
    "Armory": (32, 42, [3975]),
    "Cathedral": (35, 45, [3976, 3977, 4542]),
}
SM_MAP = 189

# Bosses a script brings in rather than a spawn, so no map says where they
# are: Mutanus, Gahz'rilla, the Avatar of Hakkar, Kirtonos, Rend and Gyth,
SUMMONED = {3654: 43, 7273: 209, 8443: 109, 10506: 289, 10429: 229, 10339: 229,
            # and in raids: Ragnaros, Nefarian, Ouro, Sapphiron, Arlokk,
            # Gahz'ranka and the Edge of Madness bosses.
            11502: 409, 11583: 469, 15517: 531, 15989: 533, 14515: 309, 15114: 309,
            15082: 309, 15083: 309, 15084: 309, 15085: 309}

BAD_TITLE = re.compile(r"UNUSED|DEPRECATED|\bOLD\b|<|\[|TEST|NYI|ZZOLD", re.I)


def parse_row(line):
    """One `(a,'b',c)` row as a list of values, or None when it runs on."""
    values, cur, in_str, quoted = [], [], False, False
    j, n = 1, len(line)
    while j < n:
        ch = line[j]
        if in_str:
            if ch == "\\":
                cur.append(line[j + 1])
                j += 2
                continue
            if ch == "'":
                in_str = False
            else:
                cur.append(ch)
        elif ch == "'":
            in_str, quoted = True, True
        elif ch in ",)":
            text = "".join(cur)
            if quoted:
                values.append(text)
            else:
                text = text.strip()
                try:
                    values.append(int(text))
                except ValueError:
                    try:
                        values.append(float(text))
                    except ValueError:
                        values.append(text)
            cur, quoted = [], False
            if ch == ")":
                return values
        else:
            cur.append(ch)
        j += 1
    return None


def rows(path, table):
    """Every row of a mysqldump INSERT for `table`, as dicts by column."""
    columns, out, pending = None, [], ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if columns is None:
                m = re.match(r"INSERT INTO `%s` \(([^)]*)\) VALUES" % table, line)
                if m:
                    columns = [c.strip(" `") for c in m.group(1).split(",")]
                continue
            if pending:
                line = pending + line
                pending = ""
            if not line.startswith("("):
                continue
            values = parse_row(line)
            if values is None:
                pending = line
                continue
            if len(values) == len(columns):
                out.append(dict(zip(columns, values)))
    if columns is None:
        raise SystemExit(f"no INSERT for {table} in {path}")
    return out


def load_pfquest(folder):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("pfDB = setmetatable({}, {__index = function(t, k) "
                "local v = {} rawset(t, k, v) return v end})")
    db = folder / "db"
    for name in ["units.lua", "objects.lua", "items.lua", "quests.lua", "zones.lua",
                 "enUS/units.lua", "enUS/objects.lua", "enUS/items.lua",
                 "enUS/quests.lua", "enUS/zones.lua"]:
        lua.execute((db / name).read_text(encoding="utf-8"))
    return lua.eval("pfDB")


def lua_table(t):
    return {k: t[k] for k in t} if t is not None else {}


def place(entry):
    """The zone an NPC or object mostly stands in, and one spot there."""
    coords = entry and entry["coords"]
    if not coords:
        return None
    spots = [coords[i] for i in coords]
    if not spots:
        return None
    zones = collections.Counter(s[3] for s in spots)
    zone = zones.most_common(1)[0][0]
    for s in spots:
        if s[3] == zone:
            return zone, round(float(s[1]), 1), round(float(s[2]), 1)
    return None


def faction_of(entry):
    fac = entry and entry["fac"]
    return fac or ""


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(x):
    if isinstance(x, float) and x == int(x):
        return str(int(x))
    return str(x)


def main():
    mangos = Path(sys.argv[1]) / "World" / "Setup" / "FullDB"
    pfq = load_pfquest(Path(sys.argv[2]))

    # What each item is.
    items = {}
    for r in rows(mangos / "item_template.sql", "item_template"):
        if r["class"] not in (2, 4) or r["InventoryType"] not in EQUIPPABLE:
            continue
        if r["Quality"] < 1 or r["Quality"] > 5:
            continue
        if (r["RequiredSkill"] or r["requiredhonorrank"]
                or r["requiredspell"]):
            continue
        if BAD_TITLE.search(r["name"]) or r["name"].startswith("Monster"):
            continue
        classes = r["AllowableClass"]
        if classes in (-1, 0) or classes & 0x5DF == 0x5DF:
            classes = 0
        items[r["entry"]] = {
            "req": r["RequiredLevel"], "ilvl": r["ItemLevel"], "q": r["Quality"],
            "classes": classes, "races": r["AllowableRace"],
            "price": r["BuyPrice"] // max(1, r["BuyCount"]),
            "rep": r["RequiredReputationFaction"], "repRank": r["RequiredReputationRank"],
        }

    units, objects = pfq["units"]["data"], pfq["objects"]["data"]
    unit_names, object_names = pfq["units"]["enUS"], pfq["objects"]["enUS"]
    item_names, quest_text = pfq["items"]["enUS"], pfq["quests"]["enUS"]
    zone_names = pfq["zones"]["enUS"]

    npcs = {}            # npcID -> (name, zone, x, y, fac)
    used_zones = set()

    def npc(uid):
        if uid in npcs:
            return npcs[uid]
        where = place(units[uid])
        name = unit_names[uid]
        if not where or not name:
            npcs[uid] = None
            return None
        npcs[uid] = (name, where[0], where[1], where[2], faction_of(units[uid]))
        return npcs[uid]

    sources = collections.defaultdict(lambda: {"v": [], "q": [], "d": []})

    # Vendors.
    pf_items = pfq["items"]["data"]
    for itemID in items:
        entry = pf_items[itemID]
        if not entry or not entry["V"]:
            continue
        for uid, stock in lua_table(entry["V"]).items():
            who = npc(uid)
            if not who:
                continue
            used_zones.add(who[1])
            sources[itemID]["v"].append((uid, int(stock or 0)))

    # Quests.
    quest_rows = {r["entry"]: r for r in rows(mangos / "quest_template.sql", "quest_template")}
    pf_quests = pfq["quests"]["data"]
    quests = {}
    for qid, r in quest_rows.items():
        pq = pf_quests[qid]
        if not pq or not pq["start"] or pq["event"]:
            continue
        rewards = [r[f"RewChoiceItemId{i}"] for i in range(1, 7)] + \
                  [r[f"RewItemId{i}"] for i in range(1, 5)]
        rewards = [i for i in rewards if i in items]
        # A quest with no gear is still kept, in case it opens the way to
        # one with gear: the finder walks the chain back through it.
        title = (quest_text[qid] and quest_text[qid]["T"]) or r["Title"]
        if not title or BAD_TITLE.search(title):
            continue

        # Who starts it, and where.
        start = pq["start"]
        giver = None
        if start["U"]:
            for i in start["U"]:
                who = npc(start["U"][i])
                if who:
                    giver = (who[0], who[1], who[2], who[3], who[4])
                    break
        if not giver and start["O"]:
            for i in start["O"]:
                oid = start["O"][i]
                where = place(objects[oid])
                if where and object_names[oid]:
                    giver = (object_names[oid], where[0], where[1], where[2],
                             faction_of(objects[oid]))
                    break
        if not giver and start["I"]:
            iid = start["I"][1]
            if item_names[iid]:
                giver = (item_names[iid], 0, 0, 0, "")
        if not giver:
            continue

        races = r["RequiredRaces"] or 0
        if races & (ALLIANCE_RACES | HORDE_RACES) in (0, ALLIANCE_RACES | HORDE_RACES):
            races = 0
        fac = giver[4]
        if races == 0 and fac in ("A", "H"):
            races = ALLIANCE_RACES if fac == "A" else HORDE_RACES
        prev = r["PrevQuestId"]
        after = ""
        if prev and prev > 0 and quest_text[prev] and quest_text[prev]["T"]:
            after = quest_text[prev]["T"]
        quests[qid] = (title, r["MinLevel"], r["QuestLevel"], races,
                       r["RequiredClasses"] or 0, giver[0], giver[1], giver[2], giver[3],
                       after, {1: "group", 81: "group", 62: "raid"}.get(r["Type"], ""),
                       prev if prev and prev > 0 else 0)
        for itemID in rewards:
            sources[itemID]["q"].append(qid)

    # Dungeon drops.
    where_map = {}
    for r in rows(mangos / "creature.sql", "creature"):
        if r["map"] in INSTANCES:
            where_map.setdefault(r["id"], r["map"])
    for uid, m in SUMMONED.items():
        where_map.setdefault(uid, m)
    templates = {r["Entry"]: r for r in rows(mangos / "creature_template.sql", "creature_template")}
    wing_of = {}
    for wing, (_, _, wing_bosses) in WINGS.items():
        for b in wing_bosses:
            wing_of[b] = wing

    def loot_lists(table):
        """entry -> [(item or -reference, chance %, group, rolls)]"""
        lists = collections.defaultdict(list)
        for r in rows(mangos / f"{table}.sql", table):
            lists[r["entry"]].append((r["item"], float(r["ChanceOrQuestChance"]),
                                      r["groupid"], r["mincountOrRef"], r["maxcount"]))
        return lists

    def chances(entries):
        """Each item's chance in one loot list, sharing out a group's
        remainder among its entries that give no chance of their own."""
        groups = collections.defaultdict(list)
        out = []
        for item, chance, group, mincount, rolls in entries:
            if chance < 0:
                continue   # quest items
            # A reference is rolled on its own whatever group it names, as
            # the server does it.
            if group and mincount > 0:
                groups[group].append((item, chance, mincount, rolls))
            else:
                out.append((item, chance, mincount, rolls))
        for members in groups.values():
            given = sum(c for _, c, _, _ in members if c > 0)
            unset = [m for m in members if m[1] == 0]
            share = max(0.0, 100.0 - given) / len(unset) if unset else 0
            for item, chance, mincount, rolls in members:
                out.append((item, chance if chance > 0 else share, mincount, rolls))
        return out

    creature_loot = loot_lists("creature_loot_template")
    reference_loot = loot_lists("reference_loot_template")

    # Who uses each reference list: a list shared by many creatures, or
    # across dungeons, is world-drop loot, not a boss's own.
    ref_users = collections.defaultdict(set)
    for uid, m in where_map.items():
        loot_id = templates.get(uid, {}).get("LootId")
        for item, _, _, mincount, _ in creature_loot.get(loot_id, []):
            if mincount < 0:
                ref_users[-mincount].add(uid)
    for entries in creature_loot.values():
        for _, _, _, mincount, _ in entries:
            if mincount < 0:
                ref_users[-mincount]   # make sure every reference is known

    bosses = {}   # npcID -> (name, dungeon key, level)
    for uid, m in where_map.items():
        template = templates.get(uid)
        if not template or not template["LootId"]:
            continue
        found = {}
        for item, chance, mincount, rolls in chances(creature_loot.get(template["LootId"], [])):
            if mincount < 0:
                ref = -mincount
                users = ref_users[ref]
                if len(users) > 6 or len({where_map[u] for u in users}) != 1:
                    continue
                for ref_item, ref_chance, _, _ in chances(reference_loot.get(ref, [])):
                    eff = chance / 100 * max(1, rolls) * ref_chance
                    found[ref_item] = max(found.get(ref_item, 0), min(100.0, eff))
            else:
                found[item] = max(found.get(item, 0), chance)
        for itemID, chance in found.items():
            meta = items.get(itemID)
            if not meta or meta["q"] < 2 or chance < DROP_CHANCE_MIN:
                continue
            key = str(m)
            if m == SM_MAP and uid in wing_of:
                key = "189" + wing_of[uid]
            bosses[uid] = (unit_names[uid] or template["Name"], key, template["MaxLevel"],
                           template["Rank"])
            sources[itemID]["d"].append((uid, round(chance, 1)))

    # Write it.
    keep = {i: s for i, s in sources.items() if s["v"] or s["q"] or s["d"]}

    # The quests that give gear, and every quest before them in their
    # chains, so the finder can walk a chain back to its first quest.
    used_quests = set()
    for s in keep.values():
        used_quests.update(s["q"])
    for qid in list(used_quests):
        prev = quests[qid][11]
        for _ in range(QUEST_CHAIN_MOST):
            if not prev or prev not in quests or prev in used_quests:
                break
            used_quests.add(prev)
            prev = quests[prev][11]
    for qid in used_quests:
        if quests[qid][6]:
            used_zones.add(quests[qid][6])
    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/Sources.lua")
    w("-- Where gear comes from: vendors, quest rewards and dungeon drops.")
    w("--")
    w("-- Generated by tools/make_sources.py from Classic 1.12 data, never typed by")
    w("-- hand: the mangoszero world database (items, quest rewards, loot tables,")
    w("-- which map a creature lives on) and pfQuest's database (vendors, where")
    w("-- every NPC stands). Forever may have changed some of it. The game fills in")
    w("-- each item's stats when asked, so nothing here says what an item is worth.")
    w("")
    w("local _, ns = ...")
    w("")
    w("local Sources = {}")
    w("ns.Sources = Sources")
    w("")
    w("Sources.ZONES = {")
    for z in sorted(used_zones):
        if zone_names[z]:
            w(f"    [{z}] = {lua_string(zone_names[z])},")
    w("}")
    w("")
    w("-- Dungeons: name, lowest and highest recommended level, the zone the door")
    w("-- is in, \"A\" or \"H\" when only that faction reaches it safely, and true")
    w("-- for a raid.")
    w("Sources.DUNGEONS = {")
    for m, (name, lo, hi, zone, fac) in sorted(INSTANCES.items()):
        raid = ", true" if m in RAIDS else ""
        w(f"    [\"{m}\"] = {{ {lua_string(name)}, {lo}, {hi}, {lua_string(zone)}, \"{fac}\"{raid} }},")
        if m == SM_MAP:
            for wing, (wlo, whi, _) in WINGS.items():
                w(f"    [\"{m}{wing}\"] = {{ {lua_string(name + ' ' + wing)}, {wlo}, {whi}, "
                  f"{lua_string(zone)}, \"{fac}\" }},")
    w("}")
    w("")
    w("-- NPCs: name, zone, x, y on that zone's map, and the factions it serves")
    w("-- (\"A\", \"H\", \"AH\").")
    w("Sources.NPCS = {")
    used_npcs = set()
    for s in keep.values():
        used_npcs.update(u for u, _ in s["v"])
    for uid in sorted(used_npcs):
        name, zone, x, y, fac = npcs[uid]
        w(f"    [{uid}] = {{ {lua_string(name)}, {zone}, {num(x)}, {num(y)}, \"{fac}\" }},")
    w("}")
    w("")
    w("-- Bosses and the few trash mobs with their own loot: name, dungeon, level.")
    w("Sources.BOSSES = {")
    for uid in sorted(bosses):
        name, key, level, _ = bosses[uid]
        w(f"    [{uid}] = {{ {lua_string(name)}, \"{key}\", {level} }},")
    w("}")
    w("")
    w("-- Quests: title, level you can take it, quest level, races (0 for all),")
    w("-- classes (0 for all), who or what starts it, zone, x, y (0 when it starts")
    w("-- from an item), the quest that comes before it, and \"group\" or \"raid\"")
    w("-- when it needs one; then p = the ID of the quest before it, when that")
    w("-- one is here too. Quests that give no gear are here because they open")
    w("-- the way to one that does.")
    w("Sources.QUESTS = {")
    for qid in sorted(used_quests):
        t, mn, lv, races, classes, giver, zone, x, y, after, group, prev = quests[qid]
        prev = prev if prev in used_quests else 0
        w(f"    [{qid}] = {{ {lua_string(t)}, {mn}, {lv}, {races}, {classes}, "
          f"{lua_string(giver)}, {zone}, {num(x)}, {num(y)}, {lua_string(after)}"
          f"{(', ' + lua_string(group)) if group else ''}"
          f"{(', p = ' + str(prev)) if prev else ''} }},")
    w("}")
    w("")
    w("-- Items: required level, item level, classes (0 for all), races (0 for")
    w("-- all), and the vendor price in copper; then v = { npc, stock (0 for")
    w("-- unlimited), ... }, q = { quest, ... }, d = { npc, drop chance %, ... },")
    w("-- and r = { faction, standing } for gear that needs a reputation (standing")
    w("-- 4 is Friendly, 5 Honored, 6 Revered, 7 Exalted).")
    w("Sources.ITEMS = {")
    used_factions = set()
    for itemID in sorted(keep):
        meta, s = items[itemID], keep[itemID]
        races = meta["races"]
        if races in (-1, 0) or races & 0xFF == 0xFF:
            races = 0
        parts = [str(meta["req"]), str(meta["ilvl"]), str(meta["classes"]), str(races),
                 str(meta["price"] if s["v"] else 0)]
        if s["v"]:
            parts.append("v = { " + ", ".join(f"{u}, {n}" for u, n in sorted(s["v"])) + " }")
        if s["q"]:
            parts.append("q = { " + ", ".join(str(q) for q in sorted(set(s["q"]))) + " }")
        if s["d"]:
            parts.append("d = { " + ", ".join(f"{u}, {num(c)}" for u, c in sorted(s["d"])) + " }")
        if meta["rep"]:
            used_factions.add(meta["rep"])
            parts.append(f"r = {{ {meta['rep']}, {meta['repRank']} }}")
        w(f"    [{itemID}] = {{ {', '.join(parts)} }},")
    w("}")
    w("")

    unknown = used_factions - set(FACTIONS)
    if unknown:
        raise SystemExit(f"name these factions in FACTIONS: {sorted(unknown)}")
    w("-- Factions gear asks for a standing with, in case the game cannot name them.")
    w("Sources.FACTIONS = {")
    for f in sorted(used_factions):
        w(f"    [{f}] = {lua_string(FACTIONS[f])},")
    w("}")
    w("")

    Path("Data/Sources.lua").write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"items {len(keep)}, vendors {len(used_npcs)}, quests {len(used_quests)}, "
          f"bosses {len(bosses)}, zones {len(used_zones)}")


if __name__ == "__main__":
    main()
