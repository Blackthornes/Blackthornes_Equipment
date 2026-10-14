-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.28.0", lines = {
        "You can mark a character, such as a crafting alt, to skip upgrades, so it never gets gear offered or arrows.",
        "Upgrade quests and vendor gear are learned as you play, which helps most in zones the data doesn't cover.",
    } },
    { version = "0.27.0", lines = {
        "This is the largest AddOn update so far across the whole suite of Blackthornes addons.",
        "Equipment can show which class spells you can train, what they cost, and what your other characters can train too.",
        "The upgrade quest is easy to close and bring back, and it can show just the step you're on.",
        "The step you're on shows your quest's goals and counts, like the game's tracker.",
        "The arrow is a compass that lies on the ground now, and it stays out of the way of the XP bar.",
        "Your alts only get armor of the kind they actually wear.",
    } },
    { version = "0.26.0", lines = {
        "The upgrade finder uses Forever's own levels and prices for gear Forever changed.",
    } },
}
