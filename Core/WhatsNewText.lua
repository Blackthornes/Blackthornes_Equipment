-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.30.0", lines = {
        "The upgrade finder has an Enchants view. It shows the best enchant for each piece you wear.",
        "Worn gear's tooltip shows its best enchant.",
    } },
    { version = "0.29.0", lines = {
        "Equipment can put an upgrade on for you as soon as it lands in your bags. It's off until you turn it on in Settings.",
    } },
    { version = "0.28.0", lines = {
        "You can mark a character, such as a crafting alt, to skip upgrades, so it never gets gear offered or arrows.",
        "Upgrade quests and vendor gear are learned as you play, which helps most in zones the data doesn't cover.",
    } },
}
