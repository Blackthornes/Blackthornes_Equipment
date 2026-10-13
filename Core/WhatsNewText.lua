-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.26.0", lines = {
        "The upgrade finder uses Forever's own levels and prices for gear Forever changed.",
    } },
    { version = "0.25.0", lines = {
        "Equipment is in Deutsch on a German client.",
    } },
    { version = "0.24.0", lines = {
        "One line at login names the Blackthornes addons you don't have yet. It says it once.",
    } },
}
