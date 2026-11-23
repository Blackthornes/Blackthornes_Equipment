-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.17.0", lines = {
        "I was not happy with the overall quality of Equipment and did a full rework of the Addon. Feedback is appreciated.",
        "Equipment opens in one new window. My Gear shows your character with a green mark on every slot that has an upgrade. Find Upgrades lists every upgrade in one place. Upgrade Quest, Dungeons and Training have their own tabs.",
        "Your character sheet shows green arrows on slots with an upgrade. Alt-click a slot to see it in My Gear.",
        "Arrows on bags, bank, vendor and loot say how much better the item is, like +14%.",
        "Four dungeons were missing and are in now: Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and The Shaper's Terrace.",
        "This Zone Only keeps dungeon and raid drops in the list when you are not in that zone.",
    } },
    { version = "1.16.0", lines = {
        "Settings has a Forget button for characters you deleted.",
    } },
    { version = "1.15.0", lines = {
        "Windows fold into a round button with the Equipment badge.",
    } },
}
