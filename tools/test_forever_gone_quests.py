"""Tests for tools/forever_gone_quests.py. Run: python tools/test_forever_gone_quests.py"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_gone_quests as tool  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


folder = tempfile.mkdtemp()
try:
    with open(os.path.join(folder, "QuestV2.csv"), "w", encoding="utf-8") as f:
        f.write("ID,UniqueBitFlag,UiQuestDetailsThemeID\n1,5,0\n3,6,0\nbad,1,0\n")
    client = tool.read_client(folder)
    with open(os.path.join(folder, "Sources.lua"), "w", encoding="utf-8") as f:
        f.write('Sources.QUESTS = {\n    [1] = { "A", 1, 1 },\n    [2] = { "B", 60, 60, p = 1 },\n'
                '    [3] = { "C", 5, 5 },\n}\nSources.ITEMS = {\n    [2] = { 1, 1 },\n    [7] = { 1, 1 },\n}\n')
    quests = tool.read_quests(os.path.join(folder, "Sources.lua"))
finally:
    shutil.rmtree(folder)

expect("client quests are read, a broken row skipped", client == {1, 3})
expect("only Sources.QUESTS is read", quests == {1, 2, 3})

tool.FEWEST_CLIENT_QUESTS = 2
expect("the quests the client lacks", tool.gone(client, quests) == [2])
tool.FEWEST_CLIENT_QUESTS = 1000
try:
    tool.gone(client, quests)
    expect("a client table with almost no quests is refused", False)
except SystemExit:
    expect("a client table with almost no quests is refused", True)

text = tool.render([2, 9054], "1.60.1.70338")
expect("the file lists the IDs", "[2] = true, [9054] = true," in text)
expect("the header names the build", "(build 1.60.1.70338)" in text)
for word in ("http", "www.", ".tools", ".com"):
    expect("the file names no site (" + word + ")", word not in text)

print(f"{checks} checks, {failures} failed")
sys.exit(1 if failures else 0)
