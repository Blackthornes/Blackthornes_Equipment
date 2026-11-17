-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.12.0", lines = {
        "A one-handed weapon that beats your main hand now shows under Main hand too.",
        "Spell power scores fairer for casters.",
        "The Drowned City is in Dungeon Loot.",
        "Settings pages sit in the same order in every Blackthornes addon.",
        "Various bug fixes for Equipment.",
    } },
    { version = "1.11.0", lines = {
        "Settings has one grid for what shows on screen, and an All Addons page.",
        "You can scroll the Upgrade Tracker past eight hunts.",
        "The window can dock in more places and you can resize it by hand.",
    } },
    { version = "1.10.0", lines = {
        "The upgrade quest panel tells you how your gear is doing and why it picked each upgrade.",
        "You can choose how you like to gear up, like quick and close, or vendors first.",
        "A gold card pops up when you finish an upgrade.",
        "Clicking the upgrade's marker on the map aims your arrow at it.",
        "The quest log shows how much a quest reward would help you.",
    } },
}
