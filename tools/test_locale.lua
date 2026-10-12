-- The translations: on a German client Equipment's windows and settings
-- speak Deutsch, on any other they speak English, and a word with no German
-- line falls back to its English key. L.Format puts values named by place
-- ("%2$s ... %1$d") in order, which the tests' Lua 5.1 cannot do itself.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("locale")

-- English first.
local ns = env.Load()
local L = ns.L
suite.check("English shows English", L["Find upgrades"] == "Find upgrades")
suite.check("a stat's name in English", ns.Weights.Label("Strength") == "Strength")
suite.check("English formats as before", L.Format("Upgrade for %s: %s", "Ana", "+5%") == "Upgrade for Ana: +5%")

-- A German client.
ns = env.Load("deDE")
L = ns.L
suite.check("a button in Deutsch", L["Find upgrades"] == "Verbesserungen finden", L["Find upgrades"])
suite.check("a stat's name in Deutsch", ns.Weights.Label("Strength") == "Stärke", ns.Weights.Label("Strength"))
suite.check("a German line formats", L.Format("Upgrade for %s: %s", "Ana", "+5%") == "Verbesserung für Ana: +5%")
suite.check("a word with no German line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")
suite.check("and formats in English", L.Format("%d stacks, %s", 3, "grey") == "3 stacks, grey")
suite.check("values named by place go in order", L.Format("%2$s then %1$d", 7, "first") == "first then 7")

-- Another language that has no file shows English.
ns = env.Load("frFR")
suite.check("a client in a language with no file shows English", ns.L["Find upgrades"] == "Find upgrades")

_G.GetLocale = nil
suite.done()
