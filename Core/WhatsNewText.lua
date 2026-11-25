-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "2.0.0", lines = {
        "You can pick an Off Spec as well as your Main Spec. The lists show upgrades for both.",
        "Find Upgrades has a column for each spec, and you can show both or just one.",
        "My Gear marks a slot blue when only your Off Spec has something to get.",
        "Tooltips and arrows show your Off Spec gains in blue.",
    } },
    { version = "1.23.0", lines = {
        "The Upgrade Quest for Warsong Boots lists the Deadly Blunderbuss that Pixel asks for.",
    } },
    { version = "1.22.0", lines = {
        "Your Way There is now a small see-through box with only your current step and a dial that points the way. It hangs under the small panel.",
    } },
}
