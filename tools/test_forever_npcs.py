"""Tests for tools/forever_npcs.py. Run: python tools/test_forever_npcs.py"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402
from forever_npcs import from_save, lua_string  # noqa: E402

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


def runtime():
    return lua51.LuaRuntime(unpack_returned_tuples=True, register_eval=False)


def read(text):
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as f:
        f.write(text)
        path = f.name
    try:
        return from_save(runtime(), path)
    finally:
        os.remove(path)


SAVE = """
BlackthornesEquipmentDB = {
    ["npcSpots"] = {
        [3079] = { "Varg Windwhisper", "Mulgore", 45.3, 62.1 },
        [1] = { "Broken" },
    },
    ["minimap"] = { ["angle"] = 230 },
}
BlackthornesEquipmentCharDB = { ["spec"] = "frost" }
"""

spots = read(SAVE)
expect("a save's spots are read", spots.get(3079) == ("Varg Windwhisper", "Mulgore", 45.3, 62.1))
expect("a row missing its place is skipped", 1 not in spots)
expect("nothing else is taken", list(spots) == [3079])

# A save is data. One that tries to do anything gets nowhere.
marker = os.path.join(tempfile.gettempdir(), "forever_npcs_marker.txt")
if os.path.exists(marker):
    os.remove(marker)
for label, text in (
    ("files", f'io.open([[{marker}]], "w"):write("x") BlackthornesEquipmentDB = {{}}'),
    ("the shell", f'os.execute("echo x > {marker}") BlackthornesEquipmentDB = {{}}'),
    ("python", f'python.eval("open(r\\"{marker}\\", \\"w\\")") BlackthornesEquipmentDB = {{}}'),
    ("loading code", f'loadstring("io.open([[{marker}]], [[w]])")()'),
):
    expect(f"a save that reaches for {label} reads as nothing", read(text) == {})
    expect(f"and touches no file ({label})", not os.path.exists(marker))
expect("a compiled file is refused", read("\x1bLua" + SAVE) == {})

# Names are written back as Lua that loads.
lua = runtime()
for name in ('Plain', 'Say "hi"', "Back\\slash", "Two\nlines", "Car\rriage"):
    expect(f"{name!r} survives the trip", lua.eval(lua_string(name)) == name)

print(f"{checks - failures} of {checks} checks passed")
sys.exit(1 if failures else 0)
