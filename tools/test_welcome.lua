-- First Time Setup (UI/Welcome.lua, the owner said build it 2026-11-26).
--
-- What must hold:
--   1. A save with nothing in it is a new player: welcomeSeen starts false.
--      A save that already held anything is marked seen, so players who
--      already use the addon never get the card.
--   2. A new player's first open lays the card over the window, with every
--      big feature unticked and the two marks that start on ticked.
--   3. Ticking boxes changes nothing until Done; Done sets the same saved
--      settings Settings does, and the card never comes back by itself.
--   4. Skip changes nothing and closes it for good. Closing the window
--      without either leaves it for the next open.
--   5. /beq welcome opens it again, even once seen.
--   6. Restore Defaults leaves welcomeSeen alone.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("welcome")

-- 1. New and old saves.
_G.BlackthornesEquipmentDB = nil
local ns = env.Load()
-- env.Load marks the card seen for every other suite; read it again fresh.
_G.BlackthornesEquipmentDB = nil
_G.BlackthornesEquipmentCharDB = nil
ns.LoadSavedVariables()
suite.check("a new save has not seen the card", ns.db.welcomeSeen == false, tostring(ns.db.welcomeSeen))

_G.BlackthornesEquipmentDB = { finderScale = 100 }
ns.LoadSavedVariables()
suite.check("an old save is marked seen", ns.db.welcomeSeen == true)
suite.check("an old save keeps what it had", ns.db.finderScale == 100)

_G.BlackthornesEquipmentDB = { welcomeSeen = false, bagArrows = true }
ns.LoadSavedVariables()
suite.check("a new player who closed the window still has the card waiting", ns.db.welcomeSeen == false)

-- A fresh save for the rest.
_G.BlackthornesEquipmentDB = nil
ns.LoadSavedVariables()
ns.db.oneWindow = false

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then pcall(module.OnEnable, module) end
end

local Gear, Welcome = ns.GearWindow, ns.Welcome

-- 2. The first open.
Gear:Open()
suite.check("the card lies over the window on the first open", Welcome:IsShown())
local function Row(key)
    for _, row in ipairs(Welcome.rows) do
        if row.entry.key == key then return row end
    end
end
suite.check("five boxes", #Welcome.rows == 5, #Welcome.rows)
suite.check("Upgrade Quest starts unticked", not Row("upgradeQuest").box:GetChecked())
suite.check("Quest Arrow starts unticked", not Row("questArrow").box:GetChecked())
suite.check("Put On Upgrades starts unticked", not Row("autoEquip").box:GetChecked())
suite.check("Green Arrows starts ticked", Row("bagArrows").box:GetChecked())
suite.check("Tooltip Lines starts ticked", Row("tooltipLine").box:GetChecked())
suite.check("the Main Spec drop-down is there", Welcome.mainChoice ~= nil)
suite.check("the card's words", Welcome.title:GetText() == "Welcome to Equipment")

-- Switching tabs keeps it up until it is answered.
Gear:ShowTab("find")
suite.check("another tab still shows the card", Welcome:IsShown())

-- 4a. Closing the window leaves it for the next open.
Gear:Close()
suite.check("closing the window leaves the card unseen", ns.db.welcomeSeen == false)
Gear:Open()
suite.check("the card is back on the next open", Welcome:IsShown())

-- 3. Ticks wait for Done.
local function Click(frame) frame:GetScript("OnClick")(frame) end
Click(Row("upgradeQuest"))      -- a click on the row ticks its box
Click(Row("autoEquip").box)
Click(Row("tooltipLine").box)   -- unticked
suite.check("the row ticks its box", Row("upgradeQuest").box:GetChecked())
suite.check("nothing changes before Done", ns.db.upgradeQuest == false and ns.db.autoEquip == false
    and ns.db.tooltipLine ~= false)

Click(Welcome.doneButton)
suite.check("Done turns the Upgrade Quest on", ns.db.upgradeQuest == true)
suite.check("Done turns Put On Upgrades on", ns.db.autoEquip == true)
suite.check("Done turns the tooltip line off", ns.db.tooltipLine == false)
suite.check("Done leaves the Quest Arrow off", ns.db.questArrow == false)
suite.check("Done leaves the green arrows on", ns.db.bagArrows == true)
suite.check("Done marks it seen", ns.db.welcomeSeen == true)
suite.check("Done closes the card", not Welcome:IsShown())

Gear:Close()
Gear:Open()
suite.check("the card does not come back by itself", not Welcome:IsShown())

-- 5. /beq welcome, then 4b. Skip.
ns.commands.welcome.fn("")
suite.check("/beq welcome shows it again", Welcome:IsShown())
suite.check("it reads the settings as they stand", Row("upgradeQuest").box:GetChecked()
    and not Row("tooltipLine").box:GetChecked())
Click(Row("questArrow").box)
Click(Welcome.skipButton)
suite.check("Skip changes nothing", ns.db.questArrow == false)
suite.check("Skip closes it", not Welcome:IsShown())
suite.check("Skip keeps it seen", ns.db.welcomeSeen == true)

-- 6. Restore Defaults leaves it alone.
local kept = true
for _, key in ipairs(ns.SettingsUI.SETTING_KEYS) do
    if key == "welcomeSeen" then kept = false end
end
suite.check("Restore Defaults never resets the card", kept)

suite.done()
