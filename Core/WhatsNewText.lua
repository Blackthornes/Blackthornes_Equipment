-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.34.0", lines = {
        "Where to Get Upgrades now lists your slots down the left. Pick a slot to see every upgrade for it, and tick which sources to show. \"Only what I can get now\" hides what you can't get yet.",
        "Untrained Weapons on the Gear page of Settings is now Show or Hide, set for each character.",
    } },
    { version = "0.33.0", lines = {
        "Each tooltip line Equipment adds can be Off, Shift or Always. You pick in Settings.",
    } },
    { version = "0.32.0", lines = {
        "Equipment speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
        "Best Armor Only is under Put On Upgrades on the Gear page of Settings. It stops Equipment from offering lighter armor in a slot once you wear the heavier kind there. It's off until you turn it on.",
    } },
}
