-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.15.0", lines = {
        "Windows fold into a round button with the Equipment badge.",
    } },
    { version = "1.14.0", lines = {
        "Panels and rows have a warm brown-black look.",
        "Item rows link in chat and try on gear.",
        "Equipment has its own key in Key Bindings.",
    } },
    { version = "1.13.0", lines = {
        "Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.",
        "The Weights window lists Spirit and Health every 5 sec for every class. Both start at 0.",
    } },
}
