-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.20.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
    { version = "1.19.0", lines = {
        "The small Upgrade Quest panel has a Search Again magnifying glass.",
        "The panel's Options menu is shorter: Current Zone Only, Update on Zone Change, Solo Quests Only and Open Equipment.",
        "Worn gear names show in their rarity color on My Gear.",
    } },
    { version = "1.18.0", lines = {
        "A new Biggest Upgrade First box on the Upgrade Quest page of Settings makes each tab pick the biggest gain first. It starts off.",
    } },
}
