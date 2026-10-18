-- Blackthornes Equipment -- Logic/Enchants.lua
-- The best enchant for each piece you wear, for your spec, and how to get it.
--
-- A player asked (2026-10-15, the owner said build it). Data/Enchants.lua
-- says what every enchant gives and where it goes (from the Forever client's
-- game tables). Each worn piece's own enchant is read from its link. Every
-- enchant that fits is weighed with the same stat weights as gear
-- (Weights:Score), so a spec and the player's own weights count. Who can
-- make it is read the way crafted gear is (Logic/Crafting.lua): you, an alt
-- (Tradeskills' recipes), you can learn it, or someone else.
--
-- Gear upgrades are still judged without enchants: counting the one you'd
-- lose would change verdicts players see today.
--
-- Laid out once per gear, level or weights change and kept: Tradeskills asks
-- ForRecipe for every row of its Level Up tab.

local _, ns = ...
local L = ns.L

local Enchants = ns.NewModule("Enchants")

local Items = ns.Items
local Weights = ns.Weights

-- Under this many percent better, an enchant is not worth offering, as
-- with gear (Compare's SAME_WITHIN).
Enchants.MIN_PERCENT = 1

-- Health and mana count as the stamina and intellect that give them.
Enchants.HEALTH_PER_STAMINA = 10
Enchants.MANA_PER_INTELLECT = 15

-- Weapon damage counts as damage a second at a usual speed for the kind
-- of weapon. The client gives no speed to an addon without reading the
-- tooltip, and these are close enough to rank one enchant over another.
Enchants.SPEED = { two = 3.3, one = 2.4, ranged = 2.8 }

-- The slots an enchant can go on, in the order the list shows them.
Enchants.SLOTS = { 1, 3, 15, 5, 9, 10, 6, 7, 8, 16, 17, 18 }

local SLOT_NAMES = {
    [1] = L["Head"], [3] = L["Shoulder"], [5] = L["Chest"], [6] = L["Waist"],
    [7] = L["Legs"], [8] = L["Feet"], [9] = L["Wrist"], [10] = L["Hands"],
    [15] = L["Back"], [16] = L["Main hand"], [17] = L["Off hand"], [18] = L["Ranged"],
}
Enchants.SLOT_NAMES = SLOT_NAMES

local RANGED_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local ONE_HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true }
-- Bows, guns and crossbows: what a scope goes on.
local SCOPED = { [2] = true, [3] = true, [18] = true }
local WEAPON_CLASS = 2

local function Data()
    return ns.EnchantData or { RECIPES = {}, EFFECTS = {}, MATERIALS = {} }
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

--- The permanent enchant on an item link, or nil for none.
function Enchants.EnchantOf(link)
    if type(link) ~= "string" then return nil end
    local enchant = tonumber(link:match("item:%-?%d+:(%-?%d*)") or "")
    if enchant and enchant > 0 then return enchant end
    return nil
end

--- The weapon speed to count weapon damage at, for an item's equip slot.
local function SpeedFor(equipLoc)
    if RANGED_LOCS[equipLoc] then return Enchants.SPEED.ranged end
    if equipLoc == "INVTYPE_2HWEAPON" then return Enchants.SPEED.two end
    return Enchants.SPEED.one
end

--- What an enchant gives, as stats Weights:Score reads, or nil for an
-- enchant the data does not know. `equipLoc` says the weapon's kind, for
-- weapon damage. The second return is true when it also gives something
-- stats can't weigh (a proc, a resistance).
function Enchants:StatsOf(enchantID, equipLoc)
    local effect = Data().EFFECTS[enchantID]
    if not effect then return nil end
    local stats = {}
    for key, value in pairs(effect.s or {}) do
        if key == "health" then
            stats.stamina = (stats.stamina or 0) + value / Enchants.HEALTH_PER_STAMINA
        elseif key == "mana" then
            stats.intellect = (stats.intellect or 0) + value / Enchants.MANA_PER_INTELLECT
        else
            stats[key] = (stats[key] or 0) + value
        end
    end
    if effect.dmg then
        stats.dps = (stats.dps or 0) + effect.dmg / SpeedFor(equipLoc)
    end
    return stats, effect.other == 1
end

--- How much an enchant is worth with these weights on an item that goes
--- in `equipLoc`, or nil for one the data does not know.
function Enchants:ScoreOf(enchantID, weights, equipLoc)
    local stats, other = self:StatsOf(enchantID, equipLoc)
    if not stats then return nil end
    return Weights:Score(stats, weights, RANGED_LOCS[equipLoc] or false), other
end

--- Does a recipe's enchant go on this worn item in this slot?
function Enchants.Fits(recipe, slot, info)
    if not (recipe and info) then return false end
    local loc = info.equipLoc
    if slot == 17 then
        if loc == "INVTYPE_SHIELD" then
            for _, s in ipairs(recipe.slots) do if s == 17 then return true end end
            return false
        end
        -- An off-hand weapon takes what a one-handed weapon takes.
        return ONE_HAND_LOCS[loc] and recipe.w == 1 or false
    end
    local fits = false
    for _, s in ipairs(recipe.slots) do
        if s == slot then fits = true break end
    end
    if not fits then return false end
    if recipe.w == 2 then return loc == "INVTYPE_2HWEAPON" end
    if recipe.w == 1 then return info.classID == WEAPON_CLASS and not RANGED_LOCS[loc] end
    if recipe.w == 3 then
        return info.classID == WEAPON_CLASS and SCOPED[info.subclassID] == true
    end
    return true
end

--- The recipe's name as this client says it, else the data's (English).
function Enchants:Name(recipeID)
    local recipe = Data().RECIPES[recipeID]
    if not recipe then return nil end
    if recipe.kit then
        local name = Items.Call({ "C_Item.GetItemNameByID" }, recipe.kit)
        if type(name) == "string" and name ~= "" then return name end
    else
        local name = Items.Call({ "C_Spell.GetSpellName", "GetSpellInfo" }, recipeID)
        if type(name) == "string" and name ~= "" then return name end
    end
    return recipe.name
end

--- The name to show: a kit or scope is an item, so it is in its rarity
--- colour; an enchanting recipe is a spell and stays as it is.
function Enchants:ShownName(recipeID)
    local name = self:Name(recipeID)
    local recipe = Data().RECIPES[recipeID]
    if name and recipe and recipe.kit then return Items.ColorName(recipe.kit, name) end
    return name
end

--- An enchant already on gear, in words: its name, else what it gives.
function Enchants:EnchantName(enchantID)
    local effect = Data().EFFECTS[enchantID]
    if not effect then return L["an enchant"] end
    if effect.n then return effect.n end
    local parts = {}
    for key, value in pairs(effect.s or {}) do
        parts[#parts + 1] = ("+%d %s"):format(value, Weights.Label(key))
    end
    table.sort(parts)
    if effect.dmg then parts[#parts + 1] = L.Format("+%d weapon damage", effect.dmg) end
    if #parts == 0 then return L["an enchant"] end
    return table.concat(parts, ", ")
end

--- What a recipe's enchant gives, in words: "+3 Agility".
function Enchants:Gives(recipeID)
    local recipe = Data().RECIPES[recipeID]
    return recipe and self:EnchantName(recipe.e) or nil
end

--- A recipe's materials, in words: "1 Lesser Magic Essence, 2 Rune of
--- Teleportation". The client's names first, then the data's.
function Enchants:MaterialsText(recipeID)
    local recipe = Data().RECIPES[recipeID]
    if not recipe then return "" end
    local parts, list = {}, recipe.m or {}
    for i = 1, #list, 2 do
        local name = Items.Call({ "C_Item.GetItemNameByID" }, list[i])
        if type(name) ~= "string" or name == "" then
            name = Data().MATERIALS and Data().MATERIALS[list[i]] or "?"
        end
        -- Each name in its rarity colour, as the game shows items.
        parts[#parts + 1] = ("%d %s"):format(list[i + 1], name == "?" and name or Items.ColorName(list[i], name))
    end
    return table.concat(parts, ", ")
end

--- The slot's name: "Chest".
function Enchants.SlotName(slot)
    return SLOT_NAMES[slot] or ""
end

--------------------------------------------------------------------------------
-- Who can make it
--------------------------------------------------------------------------------

local PROFESSIONS = {
    [333] = L["Enchanting"], [165] = L["Leatherworking"],
    [202] = L["Engineering"], [164] = L["Blacksmithing"],
}
Enchants.PROFESSIONS = PROFESSIONS

--- What one of each material costs, all told: copper, and whether some
--- have no price.
function Enchants:MaterialCost(recipe)
    local Crafting = ns.Crafting
    local total, missing = 0, false
    local list = recipe.m or {}
    for i = 1, #list, 2 do
        local price = Crafting and Crafting:MaterialPrice(list[i])
        if price then total = total + price * list[i + 1] else missing = true end
    end
    if total == 0 then return nil, missing end
    return total, missing
end

--- How this character can get a recipe's enchant: a table like crafted
--- gear's source (Crafting:SourceFor), with `state` "known", "alt",
--- "learn", "skill" or "other", `profession`, `skill`, `have`, `who`,
--- `cost`, `partial` and, for a kit or scope, `auction`.
function Enchants:Source(recipeID)
    local recipe = Data().RECIPES[recipeID]
    local Crafting = ns.Crafting
    if not (recipe and Crafting) then return nil end
    local professions = Crafting:Professions() or {}
    local have = professions[recipe.line]
    local skill = Crafting:Skill(recipeID, recipe.k)
    local source = {
        kind = "enchant", recipeID = recipeID, line = recipe.line, kit = recipe.kit,
        profession = PROFESSIONS[recipe.line], skill = skill, have = have,
    }
    local knows = have and Crafting:Knows(recipeID)
    local entry = Crafting:Known()[recipeID]
    if have and knows then
        source.state = "known"
    elseif entry and entry.alts and #entry.alts > 0 then
        source.state = "alt"
        source.who = entry.alts
    elseif have and (not skill or have >= skill) then
        source.state = "learn"
    elseif have then
        source.state = "skill"
    else
        source.state = "other"
    end
    source.cost, source.partial = self:MaterialCost(recipe)
    if recipe.kit then source.auction = Crafting:AuctionPrice(recipe.kit) end
    return source
end

--------------------------------------------------------------------------------
-- The plan for each slot
--------------------------------------------------------------------------------

--- A key that moves when anything the plan reads moves: the gear worn and
--- the weights. Weights:Changed makes new weights tables.
local function PlanKey(weights)
    local parts = { tostring(weights) }
    for _, slot in ipairs(Enchants.SLOTS) do
        parts[#parts + 1] = Items:Equipped(slot) or "-"
    end
    return table.concat(parts, "|")
end

--- The best enchant for one worn piece.
-- @return nil for an empty slot or one no enchant goes on, else
--   { slot, link, equipLoc, current (enchant ID), currentScore, unknown
--     (true when the one on it can't be weighed), worn (the piece's own
--     score), picks = { { recipeID, score, gain, percent }, ... } best
--     first, only those worth more than what is on it now }
function Enchants:ForSlot(slot, weights)
    local link = Items:Equipped(slot)
    if not link then return nil end
    local info = Items:Info(link)
    if not info then return nil, true end

    local current = self.EnchantOf(link)
    local currentScore, other = 0, false
    if current then
        currentScore, other = self:ScoreOf(current, weights, info.equipLoc)
    end
    local plan = {
        slot = slot, link = link, equipLoc = info.equipLoc, current = current,
        currentScore = currentScore or 0, unknown = current and (currentScore == nil or other) or false,
        worn = ns.Compare and ns.Compare:ScoreOf(link, weights) or nil, picks = {},
    }
    -- Its stats not in yet: weighed again once they are.
    local waiting = plan.worn == nil

    local fits = false
    for recipeID, recipe in pairs(Data().RECIPES) do
        if self.Fits(recipe, slot, info) then
            fits = true
            local score = self:ScoreOf(recipe.e, weights, info.equipLoc)
            if score and recipe.e ~= current then
                local gain = score - plan.currentScore
                local base = plan.worn and plan.worn > 0 and plan.worn or nil
                local percent = base and gain / base * 100 or nil
                if gain > 0 and (not percent or percent >= Enchants.MIN_PERCENT) then
                    plan.picks[#plan.picks + 1] = {
                        recipeID = recipeID, score = score, gain = gain, percent = percent,
                    }
                end
            end
        end
    end
    if not fits then return nil, waiting end
    table.sort(plan.picks, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.recipeID < b.recipeID
    end)
    -- An enchant on it that stats can't weigh (a proc, a resistance) is
    -- the player's choice: nothing is offered over it.
    if plan.unknown then plan.picks = {} end
    return plan, waiting
end

--- Every enchantable slot's plan for the character playing, kept until the
--- gear or the weights change.
-- @return { [slot] = plan } (see ForSlot), or nil when there are no weights
function Enchants:Plans()
    local weights = Weights:ForPlayer()
    if not weights then return nil end
    -- Tradeskills asks once a row, so the worn gear is looked at again at
    -- most every RECHECK seconds; a gear event says so at once.
    local now = Enchants.Now()
    if self.kept and self.keptWeights == weights and not self.dirty
        and now - (self.checkedAt or 0) < Enchants.RECHECK then
        return self.kept
    end
    self.checkedAt, self.dirty = now, false
    local key = PlanKey(weights)
    if self.kept and self.keptKey == key and not self.missing then return self.kept end
    local plans, missing = {}, false
    for _, slot in ipairs(Enchants.SLOTS) do
        local ok, plan, waiting = pcall(self.ForSlot, self, slot, weights)
        if ok and plan then plans[slot] = plan end
        if not ok or waiting then missing = true end
    end
    self.kept, self.keptKey, self.keptWeights, self.byRecipe = plans, key, weights, nil
    self.missing = missing
    return plans
end

Enchants.RECHECK = 2

--- Seconds, for how old the last look at the gear is.
function Enchants.Now()
    local ok, now = pcall(function() return _G.GetTime and _G.GetTime() end)
    return ok and tonumber(now) or os.time()
end

--- Forget the kept plans (the gear or a setting changed).
function Enchants:Forget()
    self.kept, self.keptKey, self.keptWeights, self.byRecipe = nil, nil, nil, nil
end

--- Something worn may have changed: look again on the next ask.
function Enchants:GearChanged()
    self.dirty = true
end

--- Is a better piece of gear for this slot already waiting in Find
--- Upgrades? Then a big enchant on what is worn now goes to waste.
function Enchants:UpgradeWaits(slot)
    local finder = ns.Finder
    local latest = finder and finder.latest
    local list = latest and latest.slots and latest.slots[slot]
    return list ~= nil and #list > 0
end

--- The cheapest enchant still worth having, of a plan's picks: the
--- materials' cost, else the kit's auction price. Nil when none has a
--- price.
function Enchants:Cheapest(plan)
    local best, bestCost
    for _, pick in ipairs(plan and plan.picks or {}) do
        local source = self:Source(pick.recipeID)
        local cost = source and (source.state == "known" and source.cost
            or math.min(source.cost or math.huge, source.auction or math.huge))
        if cost and cost < math.huge and (not bestCost or cost < bestCost) then
            best, bestCost = pick, cost
        end
    end
    return best
end

--- The line the Enchants view shows for one slot: which enchant to get, and
--- why that one. Nil when there is nothing to offer.
-- @return { slot, plan, pick, source, soon (an upgrade waits, so this is
--   the cheapest worth having) }
function Enchants:Line(slot)
    local plans = self:Plans()
    local plan = plans and plans[slot]
    if not (plan and plan.picks[1]) then return nil end
    local pick, soon = plan.picks[1], false
    if self:UpgradeWaits(slot) then
        local cheap = self:Cheapest(plan)
        if cheap then pick, soon = cheap, true end
    end
    return { slot = slot, plan = plan, pick = pick, source = self:Source(pick.recipeID), soon = soon }
end

--- Every slot's line, in the list's order.
function Enchants:Lines()
    local lines = {}
    for _, slot in ipairs(Enchants.SLOTS) do
        local ok, line = pcall(self.Line, self, slot)
        if ok and line then lines[#lines + 1] = line end
    end
    return lines
end

--------------------------------------------------------------------------------
-- For Tradeskills
--------------------------------------------------------------------------------

--- What one recipe would do for the character playing, for Tradeskills'
--- Level Up tab. Read only, never raises.
-- @return { slot (the slot's name), slotID, gain (a whole percent),
--   current (the name of the enchant it would replace, or nil), best (true
--   when it is the best enchant for that slot) }, or nil when it helps no
--   piece worn
function Enchants:ForRecipe(recipeID)
    local ok, answer = pcall(function()
        recipeID = tonumber(recipeID)
        if not recipeID or not Data().RECIPES[recipeID] then return nil end
        local plans = self:Plans()
        if not plans then return nil end
        local byRecipe = self.byRecipe
        if not byRecipe then
            byRecipe = {}
            for slot, plan in pairs(plans) do
                for i, pick in ipairs(plan.picks) do
                    local held = byRecipe[pick.recipeID]
                    local percent = pick.percent and math.floor(pick.percent + 0.5) or nil
                    if not held or (percent or 0) > (held.gain or 0) then
                        byRecipe[pick.recipeID] = {
                            slot = SLOT_NAMES[slot], slotID = slot, gain = percent,
                            current = plan.current and self:EnchantName(plan.current) or nil,
                            best = i == 1 or nil,
                        }
                    end
                end
            end
            self.byRecipe = byRecipe
        end
        local found = byRecipe[recipeID]
        if not found then return nil end
        -- A fresh table, so a caller can't change the kept one.
        local copy = {}
        for key, value in pairs(found) do copy[key] = value end
        return copy
    end)
    if ok then return answer end
    return nil
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

local function Who(names)
    if #names == 1 then return names[1] end
    if #names == 2 then return L.Format("%s or %s", names[1], names[2]) end
    return L.Format("%s, %s or %d more", names[1], names[2], #names - 2)
end

--- How to get it, in words: "You can make it (Enchanting)".
function Enchants:Describe(source, money)
    if not source then return "" end
    money = money or function() return nil end
    local profession = source.profession or L["a profession"]
    local text
    if source.state == "known" then
        text = L.Format("You can make it (%s)", profession)
    elseif source.state == "alt" then
        text = L.Format("%s can make it (%s)", Who(source.who), profession)
    elseif source.state == "learn" then
        text = source.skill and L.Format("You can learn it (%s %d)", profession, source.skill)
            or L.Format("You can learn it (%s)", profession)
    elseif source.state == "skill" then
        text = L.Format("Needs %s %d, you have %d", profession, source.skill or 0, source.have or 0)
    elseif source.kit then
        text = source.skill and L.Format("Made with %s %d", profession, source.skill)
            or L.Format("Made with %s", profession)
    else
        text = L["Ask an enchanter"]
    end
    local cost = money(source.cost)
    if cost then
        if source.partial then
            text = L.Format("%s  materials over %s", text, cost)
        else
            text = L.Format("%s  materials %s", text, cost)
        end
    end
    local auction = money(source.auction)
    if auction and source.state ~= "known" then
        text = L.Format("%s  or %s at the auction house", text, auction)
    end
    return text
end

--- The gear tooltip's line for a worn piece, or nil: "Best enchant: NAME
--- (+3%)".
function Enchants:TooltipLine(link)
    if not (ns.db and ns.db.enchantTooltip ~= false) then return nil end
    local plainLink = Items.PlainLink(link)
    if not plainLink then return nil end
    local plans = self:Plans()
    if not plans then return nil end
    for slot, plan in pairs(plans) do
        if plan.link == plainLink then
            local line = self:Line(slot)
            if not line then return nil end
            local name = self:Name(line.pick.recipeID) or ""
            local percent = line.pick.percent and math.floor(line.pick.percent + 0.5)
            if percent and percent > 0 then
                return L.Format("Best enchant: %s (+%d%%)", name, percent)
            end
            return L.Format("Best enchant: %s", name)
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Queue it and Show the way
--------------------------------------------------------------------------------

local function TSQueueModule()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end
    local ok, queue = pcall(function() return ts.Queue end)
    if not ok or type(queue) ~= "table" then return nil end
    if type(queue.Ensure) ~= "function" or type(queue.EnsureBuy) ~= "function" then return nil end
    return queue
end

local function LearnNextModule()
    local ts = _G.BlackthornesTS
    if type(ts) ~= "table" then return nil end
    local ok, learn = pcall(function() return ts.LearnNext end)
    if not ok or type(learn) ~= "table" then return nil end
    if type(learn.WhereFor) ~= "function" or type(learn.ShowTheWayFor) ~= "function" then return nil end
    return learn
end

--- Can Queue it do anything?
function Enchants:CanQueue()
    return TSQueueModule() ~= nil
end

--- Where to learn a recipe, from Tradeskills: { kind, name, zone, x, y,
--- price }, or nil.
function Enchants:WhereToLearn(recipeID)
    local learn = LearnNextModule()
    if not learn then return nil end
    local ok, place = pcall(learn.WhereFor, learn, recipeID)
    if ok and type(place) == "table" then return place end
    return nil
end

--- Can Show the way do anything for this recipe?
function Enchants:CanShowTheWay(recipeID)
    return self:WhereToLearn(recipeID) ~= nil
end

--- Pin the trainer or vendor that teaches it, through Tradeskills.
function Enchants:ShowTheWay(recipeID)
    local learn = LearnNextModule()
    if not learn then return false end
    local ok, done = pcall(learn.ShowTheWayFor, learn, recipeID)
    return ok and done == true
end

--- Queue it: the craft when you or an alt knows it, else its materials on
--- the shopping list (a kit nobody makes goes on the list itself). Says in
--- chat what happened.
function Enchants:Queue(recipeID)
    local queue = TSQueueModule()
    local recipe = Data().RECIPES[recipeID]
    if not (queue and recipe) then
        ns.Print(L["Queue it needs Blackthornes Tradeskills."])
        return false
    end
    local name = self:Name(recipeID) or recipe.name
    -- What chat says: a kit's name in its colour. Tradeskills gets it plain.
    local shown = self:ShownName(recipeID) or name
    local source = self:Source(recipeID)
    local done, why

    if source and (source.state == "known" or source.state == "alt") then
        local ok
        ok, done, why = pcall(queue.Ensure, queue, recipeID, 1)
        if not ok then done, why = nil, L["Tradeskills ran into an error"] end
        if done then
            ns.Print(L.Format("Queued %s in Tradeskills. Its materials are on the shopping list.", shown))
            return true
        end
    end

    if recipe.kit and source and source.state == "other" then
        local ok
        ok, done, why = pcall(queue.EnsureBuy, queue, recipe.kit, 1, recipe.kit)
        if not ok then done, why = nil, L["Tradeskills ran into an error"] end
        if done then
            ns.Print(L.Format("Put %s on Tradeskills' shopping list.", shown))
            return true
        end
    else
        local list = recipe.m or {}
        local forRecipe = { recipeID = recipeID, name = name }
        done = #list > 0
        for i = 1, #list, 2 do
            local ok, bought, buyWhy = pcall(queue.EnsureBuy, queue, list[i], list[i + 1], nil, forRecipe)
            if not ok then bought, buyWhy = nil, L["Tradeskills ran into an error"] end
            if not bought then done, why = nil, buyWhy break end
        end
        if done then
            ns.Print(L.Format("Put the materials for %s on Tradeskills' shopping list.", shown))
            return true
        end
    end

    ns.Print(L.Format("Couldn't queue %s: %s.", shown, why or L["Tradeskills said no"]))
    return false
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Enchants:OnRecipesChanged()
    -- Who knows what moved; the scores did not.
    self.byRecipe = nil
end

function Enchants:OnItemInfo()
    if self.missing then self.dirty = true end
end

function Enchants:OnInventory(_, unit)
    if unit == nil or unit == "player" then self.dirty = true end
end

function Enchants:OnEnable()
    for _, event in ipairs({ "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED" }) do
        ns.RegisterEvent(self, event, self.OnRecipesChanged)
    end
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }) do
        ns.RegisterEvent(self, event, self.GearChanged)
    end
    ns.RegisterEvent(self, "UNIT_INVENTORY_CHANGED", self.OnInventory)
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", self.OnItemInfo)
end
