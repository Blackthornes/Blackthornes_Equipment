"""Tests for tools/forever_quests.py. Run: python tools/test_forever_quests.py"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_quests import from_save, merge, new_to_classic, render  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def read(text):
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
        f.write(text)
        path = f.name
    try:
        return from_save(lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False), path)
    finally:
        os.remove(path)


SAVE = """
BlackthornesEquipmentDB = {
    ["learnedQuests"] = {
        [90001] = { title = "A New Errand", level = 12, min = 10, giver = "Bob", zone = "Elwynn Forest",
            x = 40.5, y = 60,
            rewards = { { 1001, 8, 14, false }, { 1002, 8, 14, true } }, at = 5 },
        [90002] = { level = 3 },
    },
    ["characters"] = { ["Player-1-2"] = { name = "Private" } },
}
"""
found = read(SAVE)
expect("a quest is read", 90001 in found and found[90001]["title"] == "A New Errand")
expect("with its rewards", found[90001]["rewards"] == [(1001, 8, 14, False), (1002, 8, 14, True)])
expect("a row without a title is skipped", 90002 not in found)

quests, items = {5}, {1001: ({90001}, set())}
expect("a quest Classic lacks is new", new_to_classic(90001, found[90001], quests, items))
expect("a Classic quest with every reward linked is not",
       not new_to_classic(5, {"title": "x", "rewards": [(1001, 0, 0, False)]}, quests, {1001: ({5}, set())}))
expect("a Classic quest with a new reward is",
       new_to_classic(5, {"title": "x", "rewards": [(1003, 0, 0, False)]}, quests, items))

merged = merge(found[90001], {"title": "A New Errand", "min": 8, "rewards": [(1001, 8, 14, True)]})
expect("a newer reading lowers the level it opens at", merged["min"] == 8)
expect("and adds that a reward is given outright", (1001, 8, 14, True) in merged["rewards"])

text = render({90001: found[90001]})
expect("the file names the quest", "[90001] = { title = \"A New Errand\"" in text)
expect("and leaves out anything private", "Private" not in text and "Player-1-2" not in text)

print(f"{checks - failures}/{checks} checks passed")
sys.exit(1 if failures else 0)
