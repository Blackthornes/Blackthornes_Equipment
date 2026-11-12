-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.9.0", lines = {
        "Windows now remember where you drag them, so they come back in the same spot.",
        "A new button on the General page puts every window back where it started.",
    } },
    { version = "1.8.0", lines = {
        "There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.",
        "Gear with both damage and healing now counts for both, so healers and casters get better upgrade picks.",
    } },
    { version = "1.7.0", lines = {
        "Set bonuses now count. If a piece is part of a set you're wearing, Equipment thinks about the bonus before it tells you to swap it out.",
    } },
}
