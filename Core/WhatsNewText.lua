-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.16.0", lines = {
        "Settings has a Forget button for characters you deleted.",
    } },
    { version = "1.15.0", lines = {
        "Windows fold into a round button with the Equipment badge.",
    } },
    { version = "1.14.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "Item rows link in chat and try on gear.",
        "Equipment has its own key in Key Bindings.",
    } },
}
