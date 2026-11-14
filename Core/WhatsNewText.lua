-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.10.0", lines = {
        "The upgrade quest panel tells you how your gear is doing and why it picked each upgrade.",
        "You can choose how you like to gear up, like quick and close, or vendors first.",
        "A gold card pops up when you finish an upgrade.",
        "Clicking the upgrade's marker on the map aims your arrow at it.",
        "The quest log shows how much a quest reward would help you.",
    } },
    { version = "1.9.0", lines = {
        "Windows now remember where you drag them, so they come back in the same spot.",
        "A new button on the General page puts every window back where it started.",
    } },
    { version = "1.8.0", lines = {
        "There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.",
        "Gear with both damage and healing now counts for both, so healers and casters get better upgrade picks.",
    } },
}
