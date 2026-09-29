-- The /beq routing and the saved data it starts from.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("slash")

local ns = env.Load()

suite.check("the global is the namespace", _G.BlackthornesEquipment == ns)
suite.check("/beq is registered", SLASH_BLACKTHORNESEQUIPMENT1 == "/beq")
suite.check("and routes to the handler",
    SlashCmdList["BLACKTHORNESEQUIPMENT"] == ns.HandleSlash)

suite.check("account settings exist", type(ns.db) == "table")
suite.check("character settings exist", type(ns.charDB) == "table")
suite.check("no spec is picked until the player picks one", ns.charDB.spec == nil)

ns.HandleSlash("")
suite.check("a bare /beq opens the gear window", ns.UI.frame and ns.UI.frame:IsShown())
ns.HandleSlash("")
suite.check("and a second one closes it", not ns.UI.frame:IsShown())

env.chat = {}
ns.HandleSlash("  HELP  ")
suite.check("commands ignore case and spaces",
    env.ChatText():find("Blackthornes Equipment", 1, true), env.ChatText())

env.chat = {}
ns.HandleSlash("nonsense")
suite.check("an unknown command says so",
    env.ChatText():find("unknown command: nonsense", 1, true), env.ChatText())

env.chat = {}
ns.RegisterCommand("boom", "fails on purpose", function() error("kaboom") end)
local ok = pcall(ns.HandleSlash, "boom")
suite.check("a failing command reaches the error handler", not ok)
suite.check("and says so in chat first",
    env.ChatText():find("/beq boom failed", 1, true), env.ChatText())

-- Saved data already on disk is kept; only missing keys are filled in.
_G.BlackthornesEquipmentCharDB = { spec = "Protection" }
_G.BlackthornesEquipmentDB = { x = 120 }
ns.LoadSavedVariables()
suite.check("a picked spec survives a reload", ns.charDB.spec == "Protection")
suite.check("a moved window stays moved", ns.db.x == 120)
suite.check("missing settings get their default", ns.db.debug == false)

suite.done()
