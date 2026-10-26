-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.0.0", lines = {
        "Arrow Size picks 50%, 75% or 100% for the guide arrow.",
        "A small gem beside the close button folds a window down to its title.",
        "Mail and plate show as upgrades for later only from level 38.",
    } },
    { version = "0.35.0", lines = {
        "Dungeon Quests lists quests known to the addon done inside dungeons or raids, and which ones you've done.",
        "Dungeon Loot shows what each dungeon's bosses drop, with the upgrades for you marked.",
        "The gear window has tabs now: Upgrades, Enchants, Dungeon Quests, Dungeon Loot and Settings.",
        "An item's tooltip can say which boss drops it. You pick under Boss Drops on the Gear page of Settings.",
        "Every window has a size grip, and the General page has an Effects choice.",
    } },
    { version = "0.34.0", lines = {
        "Where to Get Upgrades now lists your slots down the left. Pick a slot to see every upgrade for it, and tick which sources to show. \"Only what I can get now\" hides what you can't get yet.",
        "Untrained Weapons on the Gear page of Settings is now Show or Hide, set for each character.",
    } },
}
