-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.13.0", lines = {
        "Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.",
        "The Weights window lists Spirit and Health every 5 sec for every class. Both start at 0.",
    } },
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
}
