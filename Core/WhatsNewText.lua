-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.26.0", lines = {
        "A new What's New window shows what changed after each update.",
        "Gear that Forever changed now uses Forever's own levels and prices.",
        "More lists got the new dark look.",
    } },
    { version = "0.25.0", lines = {
        "Equipment speaks Deutsch now if your game is in German.",
    } },
    { version = "0.24.0", lines = {
        "Works on German game clients too.",
        "A short note at login tells you about our other addons, just once.",
    } },
}
