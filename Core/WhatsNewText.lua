-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.6.0", lines = {
        "Druids have a new Bear Tank spec, so tanks and cats get the right gear.",
        "Haste and expertise on gear now count when Equipment looks for upgrades.",
        "Destruction, Retribution and Shadow get new stat weights, and the spell hit cap is fixed.",
    } },
    { version = "1.5.0", lines = {
        "You can drag the upgrade popup where you want it. Right-click puts it back.",
    } },
    { version = "1.4.0", lines = {
        "The one window now stays next to the auction house.",
        "Item icons get a soft ring for their quality.",
    } },
}
