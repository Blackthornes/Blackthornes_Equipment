-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.1.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the General page.",
        "Show on Map puts a bigger gold marker with the upgrade's name on the spot.",
        "Quest and zone names show in your game's language.",
    } },
    { version = "1.0.1", lines = {
        "The Take reward button has the gold plaque look.",
    } },
    { version = "1.0.0", lines = {
        "Arrow Size picks 50%, 75% or 100% for the guide arrow.",
        "A small gem beside the close button folds a window down to its title.",
        "Mail and plate show as upgrades for later only from level 38.",
    } },
}
