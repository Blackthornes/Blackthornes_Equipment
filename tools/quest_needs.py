"""Writes Data/QuestNeeds.lua: the quests a quest needs done first, when
Data/Sources.lua does not say them all.

Run from the repository root, after tools/make_sources.py and
tools/forever_quests.py, with the spawn database checked out somewhere and
a quest database's Classic quest file (its classicQuestDB.lua):

    python tools/quest_needs.py <spawn database> <classicQuestDB.lua>

Data/Sources.lua keeps one quest before each quest (`p`), from the world
database. Some quests need more than one: The Hunt Completed opens only
after Sharptalon's Claw, Ursangous's Paw and Shadumbra's Head are handed
in, and each of those after The Ashenvale Hunt. Upgrade Quest sent players
to a quest they could not take yet. The quest database says, for each
quest, the quests that must all be handed in first and the ones of which
any one will do; this keeps what Sources.lua lacks:

  Sources.NEEDS[quest] = { quest, ... }  every quest to hand in first. A
      quest listed for other races or classes only is left out (it is the
      same step for them). Of an "any one of" list, only a lone quest left
      open to the same players is kept.
  Sources.HOLD[quest] = quest  a quest to have in the log, not handed in,
      for the item that starts this one to drop (Tideress drops the
      Befouled Water Globe only while Stonetalon Standstill is in the log).
      No database says these: they come from the "needs" part of
      tools/forever_facts.json, each checked by hand.
  Sources.NEEDED[quest] = { the same shape as Sources.QUESTS }  a quest
      needed first that Sources.QUESTS lacks, with who gives it and where.

A quest that already has a `p` and one other quest before it is left as it
is: the two sources disagree, and Sources.lua's word stands. The spawn
database gives who starts a quest Sources.QUESTS lacks, and where. Both are
read as data (tools/lua_literal.py), never run.

Options:
    --stdout   print the file instead of writing it
"""

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_drops import load_sources  # noqa: E402
from make_quest_starts import spot  # noqa: E402
from make_sources import load_spawn_db, lua_string, num  # noqa: E402
from classic_maps import MARK  # noqa: E402
from lua_literal import Table, load_returned_table  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Data", "QuestNeeds.lua")
FACTS = os.path.join(ROOT, "tools", "forever_facts.json")
DEPTH = 8  # quests needed by quests needed by ..., at most


def covers(wider, narrower):
    """Is every race (or class) in `narrower` also in `wider`? 0 is all."""
    wider, narrower = int(wider or 0), int(narrower or 0)
    if wider == 0:
        return True
    return narrower != 0 and narrower & ~wider == 0


def forever_quests(lua):
    """The quests Data/ForeverQuests.lua adds: ({quest ID: prev or None},
    {quest ID: whether it names who gives it})."""
    path = os.path.join(ROOT, "Data", "ForeverQuests.lua")
    if not os.path.exists(path):
        return {}, {}
    lua.execute("ns = {}")
    chunk = lua.eval("function(path) return assert(loadfile(path)) end")(path)
    chunk("Blackthornes_Equipment", lua.eval("ns"))
    rows = lua.eval("ns.ForeverQuests") or {}
    return ({int(q): (int(rows[q].prev) if rows[q].prev else None) for q in rows},
            {int(q): bool(rows[q].giver and rows[q].zone) for q in rows})


def held():
    """The "needs" part of tools/forever_facts.json: {quest: quest to hold}."""
    if not os.path.exists(FACTS):
        return {}
    with open(FACTS, encoding="utf-8") as f:
        raw = (json.load(f) or {}).get("needs") or {}
    out = {}
    for quest_id, rec in raw.items():
        if isinstance(rec, dict) and isinstance(rec.get("hold"), int):
            out[int(quest_id)] = rec["hold"]
    return out


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) < 2:
        raise SystemExit(__doc__)
    spawn = load_spawn_db(Path(args[0]))
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    sources = load_sources(lua)
    zones = sources.ZONES
    ours = {}
    for qid in sources.QUESTS:
        row = sources.QUESTS[qid]
        ours[int(qid)] = {"title": row[1], "races": int(row[4] or 0), "classes": int(row[5] or 0),
                          "p": int(row.p) if row.p else None}
    forever, forever_giver = forever_quests(lua)
    quest_db = load_returned_table(args[1])

    pf_quests, pf_titles = spawn["quests"]["data"], spawn["quests"]["enUS"]
    units, objects = spawn["units"]["data"], spawn["objects"]["data"]
    unit_names, object_names = spawn["units"]["enUS"], spawn["objects"]["enUS"]
    item_names = spawn["items"]["enUS"]

    def title(qid):
        text = pf_titles[qid] and pf_titles[qid]["T"]
        return text or None

    def open_to(r, races, classes):
        pr = pf_quests[r]
        return bool(pr and title(r)) and covers(pr["race"], races) and covers(pr["class"], classes)

    def before(qid):
        """The quests the quest database says to hand in before `qid`: every
        one of its group, or the one of its "any of" list that is open to
        the same races and classes (several left means any one will do, and
        nothing is said)."""
        row = quest_db[qid]
        if not row:
            return []
        known = ours.get(qid)
        pq = pf_quests[qid] or Table()
        races = known["races"] if known else int(row[6] or pq["race"] or 0)
        classes = known["classes"] if known else int(row[7] or pq["class"] or 0)
        group = [abs(int(row[12][i])) for i in sorted(row[12] or {})]
        group = [r for r in group if r != qid and open_to(r, races, classes)]
        single = [abs(int(row[13][i])) for i in sorted(row[13] or {})]
        single = [r for r in single if r != qid and open_to(r, races, classes)]
        if len(single) == 1 and single[0] not in group:
            group.append(single[0])
        return group

    def known_p(qid):
        if qid in ours:
            return ours[qid]["p"] or forever.get(qid)
        return forever.get(qid)

    def giver(qid):
        """Who or what starts a quest the data lacks: (name, zone, x, y)."""
        start = pf_quests[qid]["start"] or Table()
        for kind, table, names in (("U", units, unit_names), ("O", objects, object_names)):
            for i in sorted(start[kind] or {}):
                uid = start[kind][i]
                name, where = names[uid], spot(table[uid])
                if name and where and zones[where[0]]:
                    return name, where[0], where[1], where[2]
        for i in sorted(start["I"] or {}):
            name = item_names[start["I"][i]]
            if name:
                return name, 0, 0, 0
        return None

    needs, needed = {}, {}
    todo = [(q, 0) for q in sorted(ours)]
    seen = set()
    while todo:
        qid, depth = todo.pop(0)
        if qid in seen or depth > DEPTH:
            continue
        seen.add(qid)
        kept = before(qid)
        p = known_p(qid)
        if not kept or kept == [p]:
            continue
        if p and len(kept) == 1:
            continue  # the two disagree; Sources.lua's word stands
        needs[qid] = kept
        for r in kept:
            if r not in ours and not forever_giver.get(r) and r not in needed:
                pq = pf_quests[r]
                start = giver(r)
                if not start:
                    continue
                pre = before(r)
                needed[r] = {
                    "title": title(r), "min": int(pq["min"] or pq["lvl"] or 1), "lvl": int(pq["lvl"] or 1),
                    "races": int(pq["race"] or 0), "classes": int(pq["class"] or 0),
                    "giver": start[0], "zone": start[1], "x": start[2], "y": start[3],
                    "p": pre[0] if len(pre) == 1 else None,
                }
            todo.append((r, depth + 1))

    # A needed quest the data lacks is only useful with where to get it.
    for qid in list(needs):
        needs[qid] = [r for r in needs[qid] if r in ours or r in forever or r in needed]
        if not needs[qid]:
            del needs[qid]

    holds = held()

    out = []
    w = out.append
    w("-- Blackthornes Equipment -- Data/QuestNeeds.lua")
    w("-- The quests a quest needs done first, when Data/Sources.lua does not")
    w("-- say them all.")
    w("--")
    w("-- Generated by tools/quest_needs.py, never typed by hand: the spawn")
    w("-- database's quests before each quest, and the \"needs\" part of")
    w("-- tools/forever_facts.json.")
    w("")
    w(MARK)
    w("")
    w("local _, ns = ...")
    w("")
    w("local Sources = ns.Sources")
    w("")
    w("-- [quest] = { every quest to hand in before it }")
    w("Sources.NEEDS = {")
    for qid in sorted(needs):
        w(f"    [{qid}] = {{ {', '.join(str(r) for r in needs[qid])} }},")
    w("}")
    w("")
    w("-- [quest] = the quest to have in the log (not handed in) for the item")
    w("-- that starts it to drop")
    w("Sources.HOLD = {")
    for qid in sorted(holds):
        w(f"    [{qid}] = {holds[qid]},")
    w("}")
    w("")
    w("-- Quests needed first that Sources.QUESTS lacks, in its shape: title,")
    w("-- level you can take it, quest level, races, classes, who or what starts")
    w("-- it, zone, x, y (0 when it starts from an item), \"\"; p = the quest")
    w("-- before it.")
    w("Sources.NEEDED = {")
    for qid in sorted(needed):
        n = needed[qid]
        w(f"    [{qid}] = {{ {lua_string(n['title'])}, {n['min']}, {n['lvl']}, {n['races']}, "
          f"{n['classes']}, {lua_string(n['giver'])}, {n['zone']}, {num(n['x'])}, {num(n['y'])}, \"\""
          f"{(', p = ' + str(n['p'])) if n['p'] else ''} }},")
    w("}")
    text = "\n".join(out) + "\n"
    if "--stdout" in argv:
        sys.stdout.write(text)
        return
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {OUTPUT}: {len(needs)} quests with quests to do first, "
          f"{len(needed)} quests added, {len(holds)} held")


if __name__ == "__main__":
    main(sys.argv[1:])
