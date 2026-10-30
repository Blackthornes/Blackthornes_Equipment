-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.2.0", lines = {
        "Finder rows take one line and the filters sit on one row. Judge Gear As is a drop-down in the finder header.",
        "Upgrade Hunts has Hunts and Done tabs.",
        "The Upgrade quest panel keeps its tick boxes and Quest level behind one Options button.",
        "Upgrade Hunts and Upgrade Quest can be see-through. Pick it on the General page. It starts Off.",
        "Show the Way also does what Follow did.",
    } },
    { version = "1.1.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the General page.",
        "Show on Map puts a bigger gold marker with the upgrade's name on the spot.",
        "Quest and zone names show in your game's language.",
    } },
    { version = "1.0.1", lines = {
        "The Take reward button has the gold plaque look.",
    } },
}
