-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.25.0", lines = {
        "Equipment speaks Deutsch now if your game is in German.",
    } },
    { version = "0.24.0", lines = {
        "Works on German game clients too.",
        "A short note at login tells you about our other addons, just once.",
    } },
    { version = "0.23.0", lines = {
        "Weapons you can't use yet now offer to show you the trainer, or let you ignore that weapon type.",
        "Learn the skill and the weapon pops up ready to wear.",
    } },
}
