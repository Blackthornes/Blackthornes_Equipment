-- A weapon whose skill the character has not learned says "Train" in red
-- wherever an upgrade's gain shows: the finder, the character sheet's list
-- and the upgrade quest panel (a player asked, the owner agreed 2026-10-10).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("trainlabel")

local ITEMS = {
    ["item:1"] = { loc = "INVTYPE_WEAPON", class = 2, subclass = 15, stats = { ITEM_MOD_AGILITY_SHORT = 5 } },   -- dagger
    ["item:3"] = { loc = "INVTYPE_2HWEAPON", class = 2, subclass = 1, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },  -- two-handed axe
    ["item:5"] = { loc = "INVTYPE_CHEST", class = 4, subclass = 2, stats = { ITEM_MOD_AGILITY_SHORT = 3 } },
}

-- A Horde hunter who knows axes and bows, not daggers.
local known = { [196] = true, [197] = true, [264] = true }
local ns = env.Load()
_G.UnitClass = function() return "Hunter", "HUNTER" end
_G.UnitFactionGroup = function() return "Horde" end
local asked = 0
_G.IsPlayerSpell = function(id) asked = asked + 1; return known[id] == true end
env.InstallItems(ITEMS, {})

local skills = ns.WeaponSkills
skills:Forget()
suite.check("an untrained dagger needs training", skills:NeedsTraining("item:1"))
suite.check("a known axe does not", not skills:NeedsTraining("item:3"))
suite.check("armour never does", not skills:NeedsTraining("item:5"))
suite.check("no link never does", not skills:NeedsTraining(nil))

-- The answer is kept, so a long list asks the client once.
asked = 0
for _ = 1, 20 do skills:NeedsTraining("item:1") end
suite.check("kept between rows", asked == 0, asked)

-- Learning daggers: the event forgets, and the label goes.
known[1180] = true
skills:Forget()
suite.check("learned daggers need nothing", not skills:NeedsTraining("item:1"))
known[1180] = nil
skills:Forget()

-- A client that raises means unsure, so no label.
_G.IsPlayerSpell = function() error("secret value") end
skills:Forget()
suite.check("a raising client is not Train", not skills:NeedsTraining("item:1"))
_G.IsPlayerSpell = function(id) return known[id] == true end
skills:Forget()

-- The character sheet's list.
local SU = ns.SlotUpgrades
local dagger = { link = "item:1", result = { percent = 12 } }
local axe = { link = "item:3", result = { percent = 12 } }
suite.check("slot list says Train", SU.Gain(dagger) == "Train: +12%", SU.Gain(dagger))
suite.check("in red", SU.GainKey(dagger) == "loss", SU.GainKey(dagger))
suite.check("a known weapon keeps its gain", SU.Gain(axe) == "+12%", SU.Gain(axe))
suite.check("in green", SU.GainKey(axe) == "good", SU.GainKey(axe))

-- The finder row.
ns.FinderUI:Build()
ns.FinderUI.SourceLine = function() return "a vendor" end   -- where it comes from is not under test
local function Row()
    local row = ns.FinderUI:BuildRow(1)
    local gain = row.gain
    gain.SetText = function(self, t) self.text = t end
    gain.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
    return row
end
local function Line(link, at)
    return { pick = { link = link, itemID = 1, result = { percent = 12 }, at = at },
        sources = { { kind = "vendor", npc = 0, cost = 0 } }, slotName = "Main Hand", first = true }
end
local red = { ns.Theme.Unpack("loss") }
local function IsRed(row) return row.gain.color[1] == red[1] and row.gain.color[2] == red[2] end

local row = Row()
ns.FinderUI:FillRow(row, Line("item:1"))
suite.check("finder says Train", row.gain.text == "Train: +12%", row.gain.text)
suite.check("finder Train is red", IsRed(row))
row = Row()
ns.FinderUI:FillRow(row, Line("item:1", 12))
suite.check("with a level too", row.gain.text == "at 12, Train: +12%", row.gain.text)
suite.check("still red", IsRed(row))
row = Row()
ns.FinderUI:FillRow(row, Line("item:3", 12))
suite.check("a known weapon keeps at 12", row.gain.text == "at 12: +12%", row.gain.text)
suite.check("not red", not IsRed(row))

-- The upgrade quest panel.
local text = ns.QuestPanel.GainText({ link = "item:1", howMuch = "+12%" })
suite.check("quest panel says Train", text:find("Train", 1, true) ~= nil, text)
text = ns.QuestPanel.GainText({ link = "item:3", howMuch = "+12%" })
suite.check("not for a known weapon", text:find("Train", 1, true) == nil, text)

suite.done()
