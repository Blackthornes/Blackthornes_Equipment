-- Blackthornes Equipment -- Logic/Crafting.lua
-- Crafted gear as an upgrade: who on the account can make it, what it takes
-- to learn, and what the materials cost.
--
-- Data/Crafts.lua says how each piece is made (Classic data). The game says
-- which professions this character has and at what skill. Tradeskills, when
-- it is loaded, adds the two things only it knows: which recipes each of the
-- player's characters has learned (it reads them whenever a profession
-- window opens) and auction prices. Everything from Tradeskills is read
-- inside a pcall and never written; without it this still works, it just
-- knows less (no alts, materials priced only where a vendor sells them).
--
-- Bind on pickup gear can only be worn by whoever makes it, so it is only
-- offered to a character who has the profession.

local _, ns = ...

local Crafting = ns.NewModule("Crafting")

local Items = ns.Items

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

--- A plain copy of a client string, or nil. In an instance the client can
--- hand back names that raise when compared, and a kept one would raise
--- forever.
local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    if ok then return copy end
    return nil
end

local function Number(value)
    local ok, copy = pcall(function() return tonumber(value) end)
    if ok then return copy end
    return nil
end

--------------------------------------------------------------------------------
-- This character's professions
--------------------------------------------------------------------------------

--- The profession's skill line ID by its name, "Tailoring" -> 197.
local function LineByName(name)
    for line, professionName in pairs(ns.Crafts.PROFESSIONS) do
        if professionName == name then return line end
    end
    return nil
end

--- Read the professions this character has, { [skill line] = skill }, from
--- whichever calls the client has. Forever lists each profession twice
--- (a modern and a classic ID) with the same skill, which the name folds.
local function ReadProfessions()
    local found = {}

    local trade = _G.C_TradeSkillUI
    local lines = Read(trade and trade.GetAllProfessionTradeSkillLines)
    if type(lines) == "table" then
        for _, skillLineID in ipairs(lines) do
            local info = Read(trade.GetProfessionInfoBySkillLineID, skillLineID)
            if type(info) == "table" then
                local line = LineByName(Plain(info.professionName))
                local rank, most = Number(info.skillLevel), Number(info.maxSkillLevel)
                if line and most and most > 0 then
                    found[line] = math.max(found[line] or 0, rank or 0)
                end
            end
        end
    end

    -- Classic's skill list, where the client has it.
    local count = Number(Read(_G.GetNumSkillLines)) or 0
    for index = 1, count do
        local name, _, _, rank = Read(_G.GetSkillLineInfo, index)
        local line = LineByName(Plain(name))
        rank = Number(rank)
        if line and rank then found[line] = math.max(found[line] or 0, rank) end
    end

    return found
end

--- This character's professions, { [skill line] = skill }. At login the
--- skill levels can read as nothing for a moment, so a read that finds
--- nothing never replaces one that found something.
function Crafting:Professions()
    if self.professions and not self.stale then return self.professions end
    local fresh = ReadProfessions()
    if next(fresh) or not self.professions then self.professions = fresh end
    self.stale = false
    return self.professions
end

--- Forget what was read, so the next ask goes to the client and
--- Tradeskills again. The professions are kept until a read finds some.
function Crafting:Forget()
    self.stale = true
    self.known = nil
end

--------------------------------------------------------------------------------
-- Tradeskills: recipes on every character, and prices
--------------------------------------------------------------------------------

--- Tradeskills' namespace, when it is loaded.
local function Tradeskills()
    local ts = _G.BlackthornesTS
    if type(ts) == "table" then return ts end
    return nil
end

--- What Tradeskills knows about who can make what: { [recipe spell] =
--- { mine = true, alts = { "Bob", ... } } }, or an empty table. A recipe on
--- Forever is the spell that makes it, the same ID Crafts.lua carries.
function Crafting:Known()
    if self.known then return self.known end
    local known = {}
    self.known = known

    local ts = Tradeskills()
    local recipes = ts and ts.Recipes
    if not (recipes and recipes.GetAccountWide) then return known end

    local ok = pcall(function()
        local selfKey = ts.Config and ts.Config.GetCharacterKey and ts.Config:GetCharacterKey()
        local myFaction = Plain(Read(_G.UnitFactionGroup, "player"))
        local characters = ts.db and ts.db.characters or {}
        for recipeID, recipe in pairs(recipes:GetAccountWide(true)) do
            local entry = { alts = {} }
            for _, key in ipairs(recipe.knownBy or {}) do
                if key == selfKey then
                    entry.mine = true
                else
                    -- Gear is mailed, so only a character of the same side
                    -- can make it for this one.
                    local record = characters[key]
                    local faction = type(record) == "table" and record.faction
                    if not faction or not myFaction or faction == myFaction then
                        -- The whole name, first and last: WoW Forever
                        -- characters have a last name, and "Bob" or
                        -- "Bob B." may be more than one of them (asked
                        -- 2026-10-11). The short name is only for an older
                        -- Tradeskills without GetCharacterName.
                        local name = Plain(recipes.GetCharacterName and recipes:GetCharacterName(key))
                        if not name or name == "?" then
                            name = Plain(recipes.GetShortCharacterName and recipes:GetShortCharacterName(key))
                        end
                        entry.alts[#entry.alts + 1] = name or "an alt"
                    end
                end
            end
            if entry.mine or #entry.alts > 0 then known[tonumber(recipeID) or recipeID] = entry end
        end
    end)
    if not ok then self.known = {} end
    return self.known
end

--- Does this character know a recipe? True or false when something can
--- say, nil when nothing can.
function Crafting:Knows(spellID)
    local entry = self:Known()[spellID]
    if entry and entry.mine then return true end
    for _, path in ipairs({ "IsPlayerSpell", "C_SpellBook.IsSpellKnown" }) do
        if Items.Call({ path }, spellID) == true then return true end
    end
    if Tradeskills() and next(self:Known()) then return false end
    return nil
end

--- The skill a recipe needs. Forever moved some from Classic's (Raptor
--- Hide Belt is Leatherworking 140 there, 165 in Crafts.lua); Tradeskills,
--- when loaded, reads the right one from the recipe item's tooltip.
function Crafting:Skill(spellID, classic)
    local ts = Tradeskills()
    local book = ts and ts.RecipeBook
    if book and book.GetSkill then
        local ok, skill = pcall(book.GetSkill, book, spellID)
        skill = ok and Number(skill) or nil
        if skill and skill > 0 then return skill end
    end
    return classic
end

--- An item's auction price in copper, from Tradeskills, or nil.
function Crafting:AuctionPrice(itemID)
    local ts = Tradeskills()
    local prices = ts and ts.Prices
    if not (prices and prices.GetValue) then return nil end
    local ok, value = pcall(prices.GetValue, prices, itemID)
    value = ok and Number(value) or nil
    if value and value > 0 then return math.floor(value) end
    return nil
end

--- What one of a material costs: a vendor's price when a vendor always has
--- it (the house rule), else the auction price. Nil when neither is known.
function Crafting:MaterialPrice(itemID)
    local material = ns.Crafts.MATERIALS[itemID]
    if material and material[2] > 0 then return material[2] end
    return self:AuctionPrice(itemID)
end

--- What a recipe's materials cost: the total in copper, and whether some
--- of them have no price (so the total is only part of it).
function Crafting:MaterialCost(itemID)
    local craft = ns.Crafts.ITEMS[itemID]
    if not craft then return nil end
    local total, missing = 0, false
    local list = craft.m or {}
    for i = 1, #list, 2 do
        local price = self:MaterialPrice(list[i])
        if price then total = total + price * list[i + 1] else missing = true end
    end
    if total == 0 then return nil, missing end
    return total, missing
end

--- The materials in words: "8 Light Leather, 4 Coarse Thread".
function Crafting:MaterialsText(itemID)
    local craft = ns.Crafts.ITEMS[itemID]
    if not craft then return "" end
    local parts, list = {}, craft.m or {}
    for i = 1, #list, 2 do
        local material = ns.Crafts.MATERIALS[list[i]]
        parts[#parts + 1] = ("%d %s"):format(list[i + 1], material and material[1] or "?")
    end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Where to learn it
--------------------------------------------------------------------------------

--- An NPC from Crafts.lua as a place, when it serves this faction.
local function NPCPlace(npcID, faction)
    local npc = ns.Crafts.NPCS[npcID]
    if not npc or not npc[5]:find(faction, 1, true) then return nil end
    local name, zone, x, y = npc[1], ns.Crafts.ZONES[npc[2]], npc[3], npc[4]
    if ns.NPCSpots then name, zone, x, y = ns.NPCSpots:Place(npcID, name, zone, x, y) end
    return { name = name, zone = zone, x = x, y = y }
end

--- The best of a list of places: one in the zone the character is in, else
--- the first.
local function Nearest(places, zone)
    for _, place in ipairs(places) do
        if zone and place.zone == zone then return place end
    end
    return places[1]
end

--- How this character can learn a recipe: { how = "trainer", cost, name,
--- zone, x, y }, { how = "recipe", recipe, name, zone, x, y, price }, { how
--- = "drop", recipe, drops, named }, { how = "start" }, or nil when
--- nothing is known.
function Crafting:LearnFrom(itemID, player)
    local craft = ns.Crafts.ITEMS[itemID]
    if not craft then return nil end
    if craft.s then return { how = "start" } end

    if craft.t then
        local places = {}
        for _, npcID in ipairs(ns.Crafts.TRAINERS[craft.t[2]] or {}) do
            places[#places + 1] = NPCPlace(npcID, player.faction)
        end
        local place = Nearest(places, player.zone)
        if place then
            place.how, place.cost = "trainer", craft.t[1]
            return place
        end
    end

    local dropped
    for _, recipeID in ipairs(craft.r or {}) do
        local recipe = ns.Crafts.RECIPES[recipeID]
        if recipe then
            local places = {}
            local vendors = recipe.v or {}
            for i = 1, #vendors, 2 do
                local place = NPCPlace(vendors[i], player.faction)
                if place then
                    place.limited = vendors[i + 1] > 0
                    places[#places + 1] = place
                end
            end
            local place = Nearest(places, player.zone)
            if place then
                place.how, place.recipe, place.price = "recipe", recipe[1], recipe[3]
                return place
            end
            if (recipe.d or 0) > 0 and not dropped then
                dropped = { how = "drop", recipe = recipe[1], drops = recipe.d, named = recipe.n }
            end
        end
    end
    return dropped
end

--------------------------------------------------------------------------------
-- As a source of an upgrade
--------------------------------------------------------------------------------

local function Allows(mask, flag, band)
    return mask == 0 or flag == 0 or band(mask, flag) ~= 0
end

--- How this character can get a crafted item, as a finder source, or nil
--- when it cannot (bind on pickup from a profession it does not have, a
--- class or race it is not, a skill it lacks to wear it).
--
-- The source's `state`:
--   known   this character knows the recipe and has the skill
--   learn   it has the profession and the skill, and can learn the recipe
--   skill   it has the profession, but not the skill yet
--   alt     another of the player's characters knows it (bind on equip)
--   other   nobody on the account makes it; a crafter or the auction house
function Crafting:SourceFor(itemID, player, band)
    local craft = ns.Crafts.ITEMS[itemID]
    if not craft then return nil end
    if craft[4] > player.level then return nil end
    if not Allows(craft[6], player.classBit, band) or not Allows(craft[7], player.raceBit, band) then
        return nil
    end

    local professions = self:Professions()
    if craft.w and (professions[craft.w[1]] or 0) < craft.w[2] then return nil end

    local line, spellID = craft[1], craft[3]
    local skill = self:Skill(spellID, craft[2])
    local have = professions[line]
    local profession = ns.Crafts.PROFESSIONS[line]
    local source = {
        kind = "craft", itemID = itemID, profession = profession, skill = skill, have = have,
        bop = craft[8] == 1,
    }

    local knows = have and self:Knows(spellID)
    local entry = self:Known()[spellID]
    if have and knows and have >= skill then
        source.state = "known"
    elseif have and have >= skill and not knows then
        source.state = "learn"
        source.learn = self:LearnFrom(itemID, player)
    elseif have then
        source.state = "skill"
        source.learn = self:LearnFrom(itemID, player)
    elseif source.bop then
        return nil
    elseif entry and #entry.alts > 0 then
        source.state = "alt"
        source.who = entry.alts
    else
        source.state = "other"
    end

    -- Somewhere to go, for "Show on map": the trainer or vendor to learn
    -- it from.
    local learn = source.learn
    if learn and learn.zone then
        source.name, source.zone, source.x, source.y = learn.name, learn.zone, learn.x, learn.y
    end

    source.cost, source.partial = self:MaterialCost(itemID)
    if not source.bop then source.auction = self:AuctionPrice(itemID) end
    return source
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local function Who(names)
    if #names == 1 then return names[1] end
    if #names == 2 then return names[1] .. " or " .. names[2] end
    return ("%s, %s or %d more"):format(names[1], names[2], #names - 2)
end

local function Place(place)
    if not place.zone then return "" end
    if place.x and place.y then return (" in %s (%s, %s)"):format(place.zone, place.x, place.y) end
    return " in " .. place.zone
end

--- How to learn it, in words: "learn it from Darianna in Darnassus (64,
--- 21) for 50s".
function Crafting:LearnText(learn, money)
    if not learn then return nil end
    if learn.how == "start" then return "comes with the profession" end
    if learn.how == "trainer" then
        local text = "learn it from " .. learn.name .. Place(learn)
        local cost = money(learn.cost)
        if cost then text = text .. " for " .. cost end
        return text
    end
    if learn.how == "recipe" then
        local text = learn.recipe .. ", sold by " .. learn.name .. Place(learn)
        local price = money(learn.price)
        if price then text = text .. " for " .. price end
        if learn.limited then text = text .. " (limited stock)" end
        return text
    end
    if learn.how == "drop" then
        local named = learn.named
        if named and #named > 0 and learn.drops <= 3 then
            return ("%s, dropped by %s"):format(learn.recipe, named[1])
        end
        return learn.recipe .. ", a world drop"
    end
    return nil
end

--- One crafted source in words, without its "Crafted" tag. `money` turns
--- copper into coloured coins (Finder.Money).
function Crafting:Describe(source, money)
    local text
    local profession = source.profession or "a profession"
    if source.state == "known" then
        text = ("You can make it (%s)"):format(profession)
    elseif source.state == "learn" then
        text = ("%s %d: "):format(profession, source.skill) .. (self:LearnText(source.learn, money)
            or "you can learn it")
    elseif source.state == "skill" then
        text = ("Needs %s %d, you have %d"):format(profession, source.skill, source.have or 0)
        local how = self:LearnText(source.learn, money)
        if how then text = text .. "; then " .. how end
    elseif source.state == "alt" then
        text = ("%s can make it (%s)"):format(Who(source.who), profession)
    else
        text = ("Made with %s %d"):format(profession, source.skill)
    end

    local cost = money(source.cost)
    if cost then
        text = text .. ("  materials %s%s"):format(source.partial and "over " or "", cost)
    end
    local auction = money(source.auction)
    if auction and source.state ~= "known" then
        text = text .. "  or " .. auction .. " at the auction house"
    end
    return text
end

--- A short line for a crafted item's tooltip, and its colour key, or nil:
--- "You can make this", "Bob can make this", "Made with Tailoring 150".
function Crafting:TooltipLine(itemID)
    if not (ns.Crafts.ITEMS[itemID] and ns.Finder) then return nil end
    local player = ns.Finder:Player()
    if not player then return nil end
    -- Asked as if at 60, so a piece for later still says who makes it.
    local plan = {}
    for key, value in pairs(player) do plan[key] = value end
    plan.level = 60
    local source = self:SourceFor(itemID, plan, ns.Finder.Band)
    if not source then return nil end
    local profession = source.profession or "a profession"
    if source.state == "known" then return "You can make this", "upgrade" end
    if source.state == "alt" then return ("%s can make this"):format(Who(source.who)), "upgrade" end
    if source.state == "learn" then
        return ("You can learn to make this (%s %d)"):format(profession, source.skill), "accent"
    end
    if source.state == "skill" then
        return ("Made with %s %d, you have %d"):format(profession, source.skill, source.have or 0), "muted"
    end
    return ("Made with %s %d"):format(profession, source.skill), "muted"
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Crafting:OnEvent()
    self:Forget()
end

--- A skill point or a craft: the skill levels are read again, but who
--- knows which recipe stays. Reading that walks every recipe of every
--- character in Tradeskills, and the profession window says its list
--- changed after every craft (a hitch on finished crafts, 2026-10-11).
function Crafting:OnSkillPoint()
    self.stale = true
end

function Crafting:OnEnable()
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED",
        "PLAYER_ENTERING_WORLD" }) do
        ns.RegisterEvent(self, event, self.OnEvent)
    end
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE" }) do
        ns.RegisterEvent(self, event, self.OnSkillPoint)
    end
end
