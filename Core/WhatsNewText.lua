-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "2.1.1", lines = {
        "Off hand damage counts at half when a pair of one-handers is weighed against a two-hander.",
        "Hunters and warriors always keep their best pair of one-handers for the backup set.",
    } },
    { version = "2.1.0", lines = {
        "Backup Weapon Set shows the best one-hander and off hand beside a worn two-hander.",
        "Show My Character puts your character in My Gear and lets you try an upgrade on.",
        "A new Gear Road view shows the best gear each level opens from now to 60.",
        "A Level Up card shows what to wear and train after each level.",
        "One button switches to your Off Spec's gear and back.",
        "Find Upgrades shows auction house gear and says why a piece is better.",
    } },
    { version = "2.0.0", lines = {
        "You can pick an Off Spec as well as your Main Spec. The lists show upgrades for both.",
        "Find Upgrades has a column for each spec, and you can show both or just one.",
        "My Gear marks a slot blue when only your Off Spec has something to get.",
        "Tooltips and arrows show your Off Spec gains in blue.",
    } },
}
