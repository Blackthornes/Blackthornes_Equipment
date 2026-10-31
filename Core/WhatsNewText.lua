-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.4.0", lines = {
        "The one window now stays next to the auction house.",
        "Item icons get a soft ring for their quality.",
    } },
    { version = "1.3.0", lines = {
        "All your Blackthornes addons share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.",
    } },
    { version = "1.2.0", lines = {
        "Gear in the finder takes one line, so you see more at once. Judge Gear As is at the top.",
        "Upgrade Hunts has Hunts and Done tabs.",
        "The Upgrade quest panel keeps its options behind one Options button.",
        "You can make Upgrade Hunts and the Upgrade quest see-through on the General page. It starts Off.",
        "Show the Way now does the job Follow did.",
    } },
}
