-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.33.0", lines = {
        "Each tooltip line Equipment adds can be Off, Shift or Always. You pick in Settings.",
    } },
    { version = "0.32.0", lines = {
        "Equipment speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
        "Best Armor Only is under Put On Upgrades on the Gear page of Settings. It stops Equipment from offering lighter armor in a slot once you wear the heavier kind there. It's off until you turn it on.",
    } },
    { version = "0.31.0", lines = {
        "Gear with hit or crit ratings now counts for the percent it really gives, so it doesn't look better than it is.",
        "Casters count hit and crit on their gear.",
        "Hit you don't need past the cap isn't counted.",
        "Racial stat bonuses count when Equipment compares gear.",
        "Gear from recipes you've learned shows under Crafted in the upgrade finder, even the new ones Forever added.",
    } },
}
