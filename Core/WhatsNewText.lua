-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.2.0", lines = {
        "Gear in the finder takes one line, so you see more at once. Judge Gear As is at the top.",
        "Upgrade Hunts has Hunts and Done tabs.",
        "The Upgrade quest panel keeps its options behind one Options button.",
        "You can make Upgrade Hunts and the Upgrade quest see-through on the General page. It starts Off.",
        "Show the Way now does the job Follow did.",
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
