-- Blackthornes Equipment -- UI/Tooltip.lua
-- One line on a piece of gear's tooltip: an upgrade or not, for the spec the
-- character is judged as, and by how much. Under it, for a weapon the class
-- can learn but the character has not, where its weapon master is.
--
-- Hooked the way Tradeskills' UI/ItemTooltip.lua is. Its measurement on
-- Forever (docs/FOREVER_API_FINDINGS.md there) is that retail's
-- TooltipDataProcessor is what fires; the older OnTooltipSetItem script is
-- installed too, in case, and a guard stops the line going on twice.
--
-- Blizzard's tooltips are appended to, never replaced, and only the game's
-- main tooltip and the one a chat link opens are touched. The comparison
-- tooltips beside them show what is worn, which needs no verdict.

local _, ns = ...
local L = ns.L

local Tooltip = ns.NewModule("Tooltip")

local Compare = ns.Compare
local Items = ns.Items
local WeaponSkills = ns.WeaponSkills

local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

-- Each line's key for Off, Shift or Always (UI/TooltipShift.lua): the
-- verdict and the weapon master under it ("upgrade", tooltipLine), a random
-- roll's name ("suffix", suffixLine), an alt's upgrade ("alt",
-- altTooltipLine), the best enchant ("enchant", enchantTooltip) and the
-- boss that drops it ("drops", dropsTooltip). A line
-- carries its key as `line.key`; the Shift answer is asked as the lines go
-- on the tooltip, never kept with them.
if ns.TooltipShift then
    ns.TooltipShift.KEYS = { "upgrade", "suffix", "alt", "enchant", "drops" }
end

local function Field(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function Tooltip:IsEnabled()
    return not (ns.db and ns.db.tooltipLine == false)
end

--- Is this one of the tooltips the line belongs on?
function Tooltip:Wanted(tooltip)
    for _, name in ipairs(TOOLTIP_NAMES) do
        if _G[name] ~= nil and _G[name] == tooltip then return true end
    end
    return false
end

--- The link of the item a tooltip shows, however this client offers it.
function Tooltip:LinkFor(tooltip, data)
    local fromData = Items.PlainLink(Field(data, "hyperlink"))
    if fromData then return fromData end

    local displayed = Field(_G.TooltipUtil, "GetDisplayedItem")
    if type(displayed) == "function" then
        local ok, _, link = pcall(displayed, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    local getItem = Field(tooltip, "GetItem")
    if type(getItem) == "function" then
        local ok, _, link = pcall(getItem, tooltip)
        link = ok and Items.PlainLink(link)
        if link then return link end
    end

    -- Last, the bare id: good enough for the item's base stats.
    local id = Field(data, "id")
    if type(id) == "number" then
        local ok, text = pcall(function() if id > 0 then return "item:" .. id end end)
        if ok and text then return text end
    end
    return nil
end

--- Is the tooltip showing an item from one of the game's bag buttons? Only
--- a button that says its bag (retail) or is named as a bag slot (classic)
--- counts; the character sheet's buttons never do.
function Tooltip:FromBag(tooltip)
    local getOwner = Field(tooltip, "GetOwner")
    if type(getOwner) ~= "function" then return false end
    local ok, owner = pcall(getOwner, tooltip)
    if not ok or type(owner) ~= "table" then return false end

    local getBag = Field(owner, "GetBagID")
    if type(getBag) == "function" then
        local okBag, bag = pcall(getBag, owner)
        if okBag and type(bag) == "number" then return true end
    end
    local getName = Field(owner, "GetName")
    if type(getName) == "function" then
        local okName, name = pcall(getName, owner)
        if okName and type(name) == "string" then
            local okMatch, found = pcall(string.find, name, "^ContainerFrame%d+Item%d+$")
            return okMatch and found ~= nil
        end
    end
    return false
end

--- The bag and slot of the bag button the tooltip belongs to, or nil.
function Tooltip:BagSlot(tooltip)
    local getOwner = Field(tooltip, "GetOwner")
    if type(getOwner) ~= "function" then return nil end
    local ok, owner = pcall(getOwner, tooltip)
    if not ok or type(owner) ~= "table" then return nil end
    local getBag, getID = Field(owner, "GetBagID"), Field(owner, "GetID")
    if type(getBag) ~= "function" or type(getID) ~= "function" then return nil end
    local okBag, bag = pcall(getBag, owner)
    local okSlot, slot = pcall(getID, owner)
    if okBag and okSlot and type(bag) == "number" and type(slot) == "number" then return bag, slot end
    return nil
end

-- Which tooltip already carries the line, for which item and at what length.
-- Cleared when the tooltip is, so the next showing gets it again.
local decorated = setmetatable({}, { __mode = "k" })

function Tooltip.Forget(tooltip)
    decorated[tooltip] = nil
end

local function LineCount(tooltip)
    local numLines = Field(tooltip, "NumLines")
    if type(numLines) ~= "function" then return nil end
    local ok, count = pcall(numLines, tooltip)
    if ok and type(count) == "number" then return count end
    return nil
end

--- The extra lines: a random roll's name
--- and stats, which Forever's own tooltip leaves off ("of the Monkey: +5
--- Agility, +5 Stamina"), and who on the account can make a crafted piece.
function Tooltip:MoreLines(link)
    local lines = {}
    if not (ns.db and ns.db.suffixLine == false) and ns.Rolls and ns.Rolls.RollOf(link) then
        local name, stats = ns.Rolls:Describe(link)
        if stats then
            lines[#lines + 1] = { name and (name .. ": " .. stats) or L.Format("Random roll: %s", stats), "accent",
                key = "suffix", label = name and (name .. ":") or L["Random Roll:"], answer = stats }
        end
    end
    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID and not (ns.db and ns.db.dropsTooltip == false) then
        local drop, boss, where = Tooltip.DropLine(itemID)
        if drop then
            lines[#lines + 1] = { drop, "muted", key = "drops", label = L["Drops From:"],
                answer = L.Format("%s, %s", boss, where) }
        end
    end
    if itemID and ns.Crafting then
        local text, color = ns.Crafting:TooltipLine(itemID)
        if text then lines[#lines + 1] = { text, color, label = L["Crafting:"], answer = text } end
    end
    return lines
end

-- While the pointer rests on a bag slot the game draws its tooltip again
-- several times a second, and each draw used to judge the item from scratch.
-- The last item's lines are kept for a moment instead, and dropped at once
-- when gear, level, talents or weights change.
local LINES_KEPT = 1
local lastLines = nil

local function Now()
    local clock = rawget(_G, "GetTime")
    if type(clock) ~= "function" then return nil end
    local ok, now = pcall(clock)
    if ok and type(now) == "number" then return now end
    return nil
end

function Tooltip.ForgetLines()
    lastLines = nil
end

--- "Upgrade for Ana Smith: +9%" when the item is no upgrade for the
--- character playing but is for another of the player's characters on this
--- realm and side (Alts:BestFor, the same answer Butler mails by), or nil.
function Tooltip:AltLine(link, result, bag, slot)
    if ns.db and ns.db.altTooltipLine == false then return nil end
    if not ns.Alts or type(result) ~= "table" or result.verdict == "upgrade"
        or result.verdict == "equipped" then return nil end
    local alt = ns.Alts:BestFor(link, bag, slot)
    if not alt then return nil end
    local name = ns.Alts:NameOf(alt.key) or L["another of your characters"]
    local how = alt.gain and ("%+d%%"):format(alt.gain) or L["fills an empty slot"]
    local label = L.Format("For %s:", name)
    if alt.level then
        return L.Format("Upgrade for %s at level %d: %s", name, alt.level, how), label,
            L.Format("Upgrade at level %d, %s", alt.level, how)
    end
    return L.Format("Upgrade for %s: %s", name, how), label, L.Format("Upgrade, %s", how)
end

--- "Drops from BOSS in DUNGEON" for gear a dungeon drops, or nil (the
--- owner picked it, 2026-10-22). What Farmer saw drop on Forever comes
--- first, the best rate leading; else Classic's boss with the best chance.
function Tooltip.DropLine(itemID)
    local S = ns.Sources
    if not S then return nil end
    local DQ = ns.DungeonQuests
    local function DungeonName(key)
        local dungeon = DQ and DQ.Dungeon and DQ.Dungeon(key)
        if dungeon then return dungeon.name end
        local row = S.DUNGEONS and S.DUNGEONS[key]
        return type(row) == "table" and row[1] or nil
    end
    local best, bestRate
    for _, drop in ipairs(S.FOREVER and S.FOREVER[itemID] or {}) do
        local where = type(drop) == "table" and DungeonName(drop[2])
        local rate = type(drop) == "table" and tonumber(drop[3]) or 0
        if where and drop[1] and (not best or rate > bestRate) then
            best, bestRate = { drop[1], where }, rate
        end
    end
    if not best then
        local item = S.ITEMS and S.ITEMS[itemID]
        local drops = type(item) == "table" and item.d or {}
        for i = 1, #drops, 2 do
            local boss = S.BOSSES and S.BOSSES[drops[i]]
            local where = boss and DungeonName(boss[2])
            local rate = tonumber(drops[i + 1]) or 0
            if where and (not best or rate > bestRate) then
                best, bestRate = { boss[1], where }, rate
            end
        end
    end
    if not best then return nil end
    return L.Format("Drops from %s in %s", best[1], best[2]), best[1], best[2]
end

--- The lines for one item, worked out afresh.
function Tooltip:WorkOutLines(link, carried, bag, slot)
    local lines = {}
    -- An item shown from a bag slot is a carried copy, so a second copy of a
    -- worn ring is judged against the other ring, as its bag arrow is.
    local judge = carried and Compare.JudgeCarried or Compare.Judge
    local result = judge(Compare, link)
    local text, color = Compare:Describe(result)
    if text then
        local label, answer = Tooltip.VerdictPair(result)
        lines[#lines + 1] = { text, color, key = "upgrade", label = label, answer = answer }
    end
    -- No use to you, but an upgrade for another of your characters.
    local okAlt, altLine, altLabel, altAnswer = pcall(Tooltip.AltLine, Tooltip, link, result, bag, slot)
    if okAlt and altLine then
        lines[#lines + 1] = { altLine, "accent", key = "alt", label = altLabel, answer = altAnswer }
    end
    local okTrainer, trainer, trainerColor = pcall(WeaponSkills.Describe, WeaponSkills, link)
    if okTrainer and trainer then
        local okPair, answer = pcall(Tooltip.TrainerAnswer, link)
        lines[#lines + 1] = { trainer, trainerColor, true, key = "upgrade",
            label = okPair and answer and L["Weapon Master:"] or nil, answer = okPair and answer or nil }
    end
    -- On a piece you wear: the best enchant for it (Logic/Enchants.lua).
    if ns.Enchants then
        local okEnchant, enchantLine = pcall(ns.Enchants.TooltipLine, ns.Enchants, link)
        if okEnchant and enchantLine then
            local answer = enchantLine:match("^[^:]+:%s*(.+)$")
            lines[#lines + 1] = { enchantLine, "accent", key = "enchant",
                label = answer and L["Best Enchant:"] or nil, answer = answer }
        end
    end
    local okMore, more = pcall(Tooltip.MoreLines, Tooltip, link)
    if okMore then
        for _, line in ipairs(more) do lines[#lines + 1] = line end
    end
    return lines
end

--- The lines for one item, kept for LINES_KEPT seconds.
function Tooltip:LinesFor(link, carried, bag, slot)
    local now = Now()
    local generation = ns.Weights and ns.Weights.generation or 0
    local where = bag and slot and (bag .. ":" .. slot) or nil
    local kept = lastLines
    if now and kept and kept.link == link and kept.carried == carried and kept.where == where
        and kept.generation == generation and now >= kept.at and now - kept.at < LINES_KEPT then
        return kept.lines
    end
    local lines = self:WorkOutLines(link, carried, bag, slot)
    lastLines = now and { link = link, carried = carried, where = where, generation = generation,
        at = now, lines = lines } or nil
    return lines
end

--- Put the line on a tooltip.
-- @return "added", "quiet" (nothing to say), "duplicate" or "noitem"
function Tooltip:Decorate(tooltip, data)
    if not self:IsEnabled() then return "quiet" end
    if not self:Wanted(tooltip) then return "quiet" end
    if self.writing then return "duplicate" end

    local link = self:LinkFor(tooltip, data)
    if not link then return "noitem" end

    local mark = decorated[tooltip]
    if mark and mark.link == link then
        local now = LineCount(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    local bag, slot = self:BagSlot(tooltip)
    local lines = self:LinesFor(link, self:FromBag(tooltip), bag, slot)
    if #lines == 0 then return "quiet" end

    local addLine = Field(tooltip, "AddLine")
    if type(addLine) ~= "function" then return "noitem" end

    self.writing = true
    local shift = ns.TooltipShift
    local held = false
    for _, line in ipairs(lines) do
        -- A line on Shift waits while Shift is up.
        if line.key and shift and not shift:Shows(line.key) then
            held = true
        else
            -- The trainer line wraps, so a list of cities folds onto a
            -- second line rather than stretching the tooltip.
            pcall(addLine, tooltip, ("|c%s%s|r"):format(ns.COLORS[line[2]] or ns.COLORS.text, line[1]),
                nil, nil, nil, line[3])
        end
    end
    if held then pcall(shift.Held, shift, tooltip) end

    -- Adding a line needs the tooltip resized, which Show does; on a client
    -- where that re-enters the hook, `writing` is what stops it.
    local show = Field(tooltip, "Show")
    if type(show) == "function" then pcall(show, tooltip) end
    self.writing = false

    decorated[tooltip] = { link = link, lines = LineCount(tooltip) or 0 }
    return "added"
end

--- Every hook comes through here, so one bad item costs its line and never a
--- Lua error on hover.
function Tooltip:OnTooltip(tooltip, data, source)
    local ok, outcome = pcall(self.Decorate, self, tooltip, data)
    if not ok then
        self.writing = false
        return "noitem"
    end
    if outcome == "added" then
        self.fired[source] = (self.fired[source] or 0) + 1
    end
    return outcome
end

function Tooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Item")
    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" or dataType == nil then return false end

    return (pcall(add, dataType, function(tooltip, data)
        Tooltip:OnTooltip(tooltip, data, "TooltipDataProcessor")
    end))
end

function Tooltip:InstallScriptHooks()
    local installed = false
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = _G[name]
        local hook = Field(tooltip, "HookScript")
        if type(hook) == "function" then
            if pcall(hook, tooltip, "OnTooltipSetItem", function(shown)
                Tooltip:OnTooltip(shown, nil, "OnTooltipSetItem")
            end) then
                installed = true
            end
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                Tooltip.Forget(shown)
            end)
        end
    end
    return installed
end

--- An item's details arrived. Forever says so each time a tooltip reads
--- gear it already knows, so the kept lines go only when the item they are
--- for is the one that arrived (or the client names no item).
function Tooltip.OnItemInfo(_, _, itemID)
    local kept = lastLines
    if not kept then return end
    local id = tonumber(itemID)
    local shown = type(kept.link) == "string" and tonumber(kept.link:match("item:(%d+)")) or nil
    if id and shown and id ~= shown then return end
    lastLines = nil
end

--------------------------------------------------------------------------------
-- The shared tooltip block (UI/TooltipBlock.lua, 2026-11-21)
--------------------------------------------------------------------------------

--- The verdict as a name and an answer: "For Fury:" and "Upgrade, +12%".
--- Nil for a verdict with nothing to say, as Compare:Describe.
function Tooltip.VerdictPair(result)
    if type(result) ~= "table" then return nil end
    local verdict = result.verdict
    local who = result.specName or result.className or L["You"]
    local label = L.Format("For %s:", who)
    local percent = result.percent and ("%+d%%"):format(math.floor(result.percent + 0.5)) or nil
    if verdict == "cantuse" and result.ignoredSkill then
        return label, L.Format("Ignored until you train %s", result.ignoredSkill)
    elseif verdict == "cantuse" then
        return label, L["Can't use this"]
    elseif verdict == "upgrade" then
        local how = result.empty and L["fills an empty slot"] or percent or L["better stats"]
        if result.level then return label, L.Format("Upgrade at level %d, %s", result.level, how) end
        if result.train or result.skill then
            return label, L.Format("Upgrade once you train %s, %s", result.train or result.skill, how)
        end
        return label, L.Format("Upgrade, %s", how)
    elseif verdict == "downgrade" then
        return label, L.Format("Worse, %s", percent or "")
    end
    return label, L["About the same"]
end

--- "Learn Maces in Orgrimmar" for the weapon master line, or nil.
function Tooltip.TrainerAnswer(link)
    local name, cities, from = WeaponSkills:TrainerFor(link)
    if not name or type(cities) ~= "table" or #cities == 0 then return nil end
    local list = cities[1]
    if #cities > 1 then
        list = L.Format("%s or %s", table.concat(cities, ", ", 1, #cities - 1), cities[#cities])
    end
    if from then return L.Format("Learn %s at level %d in %s", name, from, list) end
    return L.Format("Learn %s in %s", name, list)
end

-- Line colors the answer keeps; "accent" and "text" lines get white, since
-- the name is the yellow part now.
local function AnswerColor(key)
    if key == nil or key == "accent" or key == "text" then return nil end
    local hex = ns.COLORS[key]
    if type(hex) ~= "string" or #hex < 8 then return nil end
    local function c(i) return (tonumber(hex:sub(i, i + 1), 16) or 255) / 255 end
    return { c(3), c(5), c(7) }
end
Tooltip.AnswerColor = AnswerColor

--- Equipment's lines for one section of the shared block ("source" holds
--- the boss drop, "advice" the rest), and whether one was held back.
function Tooltip:BlockLines(tooltip, data, section)
    if not self:IsEnabled() or not self:Wanted(tooltip) then return nil end
    local link = self:LinkFor(tooltip, data)
    if not link then return nil end
    local bag, slot = self:BagSlot(tooltip)
    local lines = self:LinesFor(link, self:FromBag(tooltip), bag, slot)
    local shift = ns.TooltipShift
    local out, held = {}, false
    for _, line in ipairs(lines) do
        if ((line.key == "drops") and "source" or "advice") == section then
            if line.key and shift and not shift:Shows(line.key) then
                held = true
            elseif line.label and line.answer then
                out[#out + 1] = { line.label, line.answer, rightColor = AnswerColor(line[2]) }
            else
                out[#out + 1] = { line[1], leftColor = AnswerColor(line[2]) or { 1, 1, 1 }, wrap = line[3] and true }
            end
        end
    end
    return out, held
end

function Tooltip:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED",
        "SKILL_LINES_CHANGED" }) do
        ns.RegisterEvent(self, event, Tooltip.ForgetLines)
    end
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", Tooltip.OnItemInfo)
    self.fired = {}
    -- The shared block writes every Blackthornes addon's lines in one go,
    -- in one order; Equipment hands it its lines instead of writing them.
    local block = ns.TooltipBlock
    if block then
        block:Provide("Equipment:source", "source", 2, function(tooltip, data)
            return Tooltip:BlockLines(tooltip, data, "source")
        end)
        block:Provide("Equipment:advice", "advice", 1, function(tooltip, data)
            return Tooltip:BlockLines(tooltip, data, "advice")
        end)
        self.installed = { ["tooltip block"] = block:Install() }
        return
    end
    self.installed = {
        TooltipDataProcessor = self:InstallDataProcessor(),
        OnTooltipSetItem = self:InstallScriptHooks(),
    }
end
