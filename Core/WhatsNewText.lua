-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.22.0", lines = {
        "Your Way There is now a small see-through box with only your current step and a dial that points the way. It hangs under the small panel.",
    } },
    { version = "1.21.0", lines = {
        "My Gear follows the filters on Find Upgrades.",
    } },
    { version = "1.20.0", lines = {
        "The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.",
    } },
}
