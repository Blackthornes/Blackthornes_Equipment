-- Every list row lights under the mouse (the owner, 2026-10-12: the hover
-- "doesn't appear" on a dark glass list). The character sheet's upgrade
-- list, the hunts panel and the Ignored window wear the house row light: a
-- lighter glass, a gold edge and a gold wash, only on the row under the
-- mouse, the wash shown and hidden rather than faded.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("listlight")

local ns = env.Load()
local Motion = ns.Motion

local function Check(name, row, other)
    row.pick, row.hunt, row.entry = false, false, false   -- an empty row: no tooltip
    local alpha = {}
    for _, key in ipairs({ "highlight", "edge" }) do
        row[key].SetAlpha = function(self, a) alpha[key] = a end
    end
    row:GetScript("OnEnter")(row)
    Motion:FinishAll()
    suite.check(name .. ": under the mouse it lights, gold edge and wash",
        alpha.highlight == 1 and alpha.edge == 1 and row.lightWash:IsShown() and row.bleed:IsShown())
    suite.check(name .. ": the row beside it stays dark", not other.lightWash:IsShown())
    row:GetScript("OnLeave")(row)
    Motion:FinishAll()
    suite.check(name .. ": leaving, it goes dark, the wash hidden",
        alpha.highlight == 0 and alpha.edge == 0 and not row.lightWash:IsShown() and not row.bleed:IsShown())
end

Check("slot upgrades", ns.SlotUpgrades:BuildRow(1), ns.SlotUpgrades:BuildRow(2))
Check("hunts panel", ns.TrackerPanel:BuildRow(1), ns.TrackerPanel:BuildRow(2))
ns.IgnoredUI:Build()
Check("ignored window", ns.IgnoredUI.rows[1], ns.IgnoredUI.rows[2])

suite.done()
