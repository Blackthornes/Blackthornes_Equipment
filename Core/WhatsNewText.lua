-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.31.0", lines = {
        "Gear with hit or crit ratings now counts for the percent it really gives, so it doesn't look better than it is.",
        "Casters count hit and crit on their gear.",
        "Hit you don't need past the cap isn't counted.",
        "Racial stat bonuses count when Equipment compares gear.",
        "Gear from recipes you've learned shows under Crafted in the upgrade finder, even the new ones Forever added.",
    } },
    { version = "0.30.0", lines = {
        "The upgrade finder has an Enchants view. It shows the best enchant for each piece you wear.",
        "Worn gear's tooltip shows its best enchant.",
    } },
    { version = "0.29.0", lines = {
        "Equipment can put an upgrade on for you as soon as it lands in your bags. It's off until you turn it on in Settings.",
    } },
}
