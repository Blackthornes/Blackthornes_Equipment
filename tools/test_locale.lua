-- The translations: on a German client Equipment's windows and settings
-- speak Deutsch, on any other they speak English, and a word with no German
-- line falls back to its English key. L.Format puts values named by place
-- ("%2$s ... %1$d") in order, which the tests' Lua 5.1 cannot do itself.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("locale")

-- English first.
local ns = env.Load()
local L = ns.L
suite.check("English shows English", L["Upgrades"] == "Upgrades")
suite.check("a stat's name in English", ns.Weights.Label("Strength") == "Strength")
suite.check("English formats as before", L.Format("Upgrade for %s: %s", "Ana", "+5%") == "Upgrade for Ana: +5%")

-- A German client.
ns = env.Load("deDE")
L = ns.L
suite.check("a button in Deutsch", L["Upgrades"] == "Verbesserungen", L["Upgrades"])
suite.check("a stat's name in Deutsch", ns.Weights.Label("Strength") == "Stärke", ns.Weights.Label("Strength"))
suite.check("a German line formats", L.Format("Upgrade for %s: %s", "Ana", "+5%") == "Verbesserung für Ana: +5%")
suite.check("a word with no German line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")
suite.check("and formats in English", L.Format("%d stacks, %s", 3, "grey") == "3 stacks, grey")
suite.check("values named by place go in order", L.Format("%2$s then %1$d", 7, "first") == "first then 7")

-- A zhCN client.
ns = env.Load("zhCN")
L = ns.L
suite.check("zhCN: a button translated", L["Upgrades"] == "升级", L["Upgrades"])
suite.check("zhCN: a stat's name translated", ns.Weights.Label("Strength") == "力量", ns.Weights.Label("Strength"))
suite.check("zhCN: a word with no line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A frFR client.
ns = env.Load("frFR")
L = ns.L
suite.check("frFR: a button translated", L["Upgrades"] == "Améliorations", L["Upgrades"])
suite.check("frFR: a stat's name translated", ns.Weights.Label("Strength") == "Force", ns.Weights.Label("Strength"))
suite.check("frFR: a word with no line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A esES client.
ns = env.Load("esES")
L = ns.L
suite.check("esES: a button translated", L["Upgrades"] == "Mejoras", L["Upgrades"])
suite.check("esES: a stat's name translated", ns.Weights.Label("Strength") == "Fuerza", ns.Weights.Label("Strength"))
suite.check("esES: a word with no line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A esMX client.
ns = env.Load("esMX")
L = ns.L
suite.check("esMX: a button translated", L["Upgrades"] == "Mejoras", L["Upgrades"])
suite.check("esMX: a stat's name translated", ns.Weights.Label("Strength") == "Fuerza", ns.Weights.Label("Strength"))
suite.check("esMX: a word with no line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A ruRU client.
ns = env.Load("ruRU")
L = ns.L
suite.check("ruRU: a button translated", L["Upgrades"] == "Улучшения", L["Upgrades"])
suite.check("ruRU: a stat's name translated", ns.Weights.Label("Strength") == "Сила", ns.Weights.Label("Strength"))
suite.check("ruRU: a word with no line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- Another language that has no file shows English.
ns = env.Load("itIT")
suite.check("a client in a language with no file shows English", ns.L["Upgrades"] == "Upgrades")

_G.GetLocale = nil
suite.done()
