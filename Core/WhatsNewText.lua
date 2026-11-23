-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.17.0", lines = {
        "I was not happy with the overall quality of Equipment and did a full rework of the Addon. Feedback is appreciated.",
        "One new window with five tabs: My Gear, Find Upgrades, Upgrade Quest, Dungeons and Training.",
        "Your character sheet shows green arrows on slots with an upgrade. Alt-click a slot to see it in My Gear.",
        "Arrows on bags, bank, vendor and loot show how much better the item is.",
        "Four more dungeons are in, and This Zone Only shows dungeon drops from any zone.",
    } },
    { version = "1.16.0", lines = {
        "Settings has a Forget button for characters you deleted.",
    } },
    { version = "1.15.0", lines = {
        "Windows fold into a round button with the Equipment badge.",
    } },
}
