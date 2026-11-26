-- Blackthornes Equipment -- UI/FinderShared.lua
-- What the Equipment window's pages share (UI/MyGear.lua,
-- UI/FindUpgrades.lua, UI/DungeonsTab.lua, UI/UpgradeQuestTab.lua) and the
-- character sheet's slot panel (UI/SlotUpgrades.lua): the source filters
-- and their saved choices, a source as one line, a row's tooltip, its
-- clicks and its right-click menu, and following a pick as the upgrade
-- quest.
--
-- This was the old gear list's window (UI/FinderWindow.lua). Rework step 6
-- (2026-11-23) took the list, the Enchants tab and the hanging tabs out;
-- My Gear and Find Upgrades show what they showed. The module keeps its
-- name, `ns.FinderUI`, and every saved choice keeps its key.
--
-- Nothing here draws a window, listens to an event or runs on a clock.

local _, ns = ...
local L = ns.L

local FinderUI = ns.NewModule("FinderUI")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Finder = ns.Finder
local Weights = ns.Weights

-- Some gear is sold by a dozen vendors; the tooltip lists this many.
local TOOLTIP_SOURCES = 8

-- The tag in front of a source, in its own colour.
local KIND_COLORS = { vendor = "accent", quest = "quest", dungeon = "dungeon", craft = "craft" }
FinderUI.KIND_COLORS = KIND_COLORS

-- A tick box for each kind of source, in this order. Raids are dungeon
-- drops from a raid (FinderUI.SourceKind).
local SOURCE_BOXES = {
    { "vendor", L["Vendor"] }, { "quest", L["Quest"] }, { "dungeon", L["Dungeons"] },
    { "raid", L["Raids"] }, { "craft", L["Crafted"] },
}
FinderUI.SOURCE_BOXES = SOURCE_BOXES

-- The slots down the left, in character sheet order: { slot, name, the
-- second slot }. Both rings are one line, and both trinkets.
local SLOT_GROUPS = {
    { 1, L["Head"] }, { 2, L["Neck"] }, { 3, L["Shoulder"] }, { 15, L["Back"] },
    { 5, L["Chest"] }, { 9, L["Wrist"] }, { 10, L["Hands"] }, { 6, L["Waist"] },
    { 7, L["Legs"] }, { 8, L["Feet"] }, { 11, L["Rings"], 12 }, { 13, L["Trinkets"], 14 },
    { 16, L["Main hand"] }, { 17, L["Off hand"] }, { 18, L["Ranged"] },
}
FinderUI.SLOT_GROUPS = SLOT_GROUPS

-- The line a slot is shown on, by slot.
local GROUP_OF = {}
for _, group in ipairs(SLOT_GROUPS) do
    GROUP_OF[group[1]] = group[1]
    if group[3] then GROUP_OF[group[3]] = group[1] end
end
FinderUI.GROUP_OF = GROUP_OF

-- How many levels ahead the stepper can look.
local MOST_AHEAD = 10

--------------------------------------------------------------------------------
-- Text that fits
--------------------------------------------------------------------------------

--- `text` cut back to the last whole word that fits in `width` pixels at
-- `size`, with no "..." (the row's tooltip has the whole line).
-- Measured, never guessed: the game's font runs wider than it looks.
-- Colour codes take no room and are kept whole, so a cut line keeps its
-- green zone, its source colour and its tags; a colour left open by the
-- cut is closed.
function FinderUI.Fit(size, text, width)
    if Theme.TextWidth(size, text) <= width then return text end

    -- The text as pieces: a colour code, a colour end, or one character.
    local pieces, chars = {}, {}
    local index = 1
    while index <= #text do
        local code = text:match("^|c%x%x%x%x%x%x%x%x", index)
        if code then
            pieces[#pieces + 1] = { code, open = true }
            index = index + #code
        elseif text:sub(index, index + 1) == "|r" then
            pieces[#pieces + 1] = { "|r", close = true }
            index = index + 2
        else
            -- A whole character, never half of one ("Zul'Farrak" is plain,
            -- but a name with an accent is two bytes).
            local char = text:match("^[\194-\244][\128-\191]*", index) or text:sub(index, index)
            pieces[#pieces + 1] = { char, char = true }
            chars[#chars + 1] = char
            index = index + #char
        end
    end

    -- The first `count` characters, with every code before them, trailing
    -- spaces and commas taken off and an open colour closed.
    local function Line(count)
        local out, seen, open = {}, 0, false
        for _, piece in ipairs(pieces) do
            if piece.char then
                if seen >= count then break end
                seen = seen + 1
            elseif piece.open then
                open = true
            elseif piece.close then
                open = false
            end
            out[#out + 1] = piece[1]
        end
        local cut = table.concat(out)
        local trimmed
        repeat
            trimmed = cut
            cut = cut:gsub("[%s,;:]+$", ""):gsub("[%s,;:]+(|r)$", "%1")
        until cut == trimmed
        return cut .. (open and "|r" or "")
    end

    local low, high = 0, #chars
    while low < high do
        local mid = math.ceil((low + high) / 2)
        if Theme.TextWidth(size, Line(mid)) <= width then
            low = mid
        else
            high = mid - 1
        end
    end
    -- Back to the last word that ends whole, unless the cut already ends
    -- one or no word fits whole.
    if low < #chars and not chars[low + 1]:match("[%s,;:]") then
        local back = low
        while back > 0 and not chars[back]:match("%s") do back = back - 1 end
        if back > 0 then low = back end
    end
    return Line(low)
end

local function Colored(key, text)
    local r, g, b = Theme.Unpack(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

--- The zone the character is in, named in green wherever `text` names it
--- as a whole word (a player asked, 2026-10-09: easier to spot what is
--- nearby).
local function MarkName(text, zone)
    local pattern = "%f[%w]" .. zone:gsub("[%%%^%$%(%)%.%[%]%*%+%-%?]", "%%%0") .. "%f[%W]"
    return (text:gsub(pattern, function(found) return Colored("good", found) end))
end

--- `zone` is the data's English name; the text may show it in the
--- client's language, so that name is marked too.
function FinderUI.MarkZone(text, zone)
    if not (zone and text) or zone == "" then return text end
    local shown = Finder.ShownZone and Finder.ShownZone(zone) or zone
    if shown ~= zone and shown ~= "" then text = MarkName(text, shown) end
    return MarkName(text, zone)
end

--- A source as one line: the coloured kind, then where, the zone the
--- character is in shown in green.
function FinderUI.SourceLine(source, zone)
    zone = zone or (ns.UpgradeQuest and ns.UpgradeQuest.Zone())
    local line = Colored(KIND_COLORS[source.kind] or "text", Finder.Label(source))
        .. "  " .. FinderUI.MarkZone(Finder:Describe(source), zone)
    -- Seen on Forever, the way Farmer marks what it has confirmed.
    if source.forever then line = line .. "  " .. Colored("good", "[Forever]") end
    return line
end

--------------------------------------------------------------------------------
-- A row's tooltip and clicks
--------------------------------------------------------------------------------

local function ShowEnchantTooltip(row, line)
    local Enchants = ns.Enchants
    local pick, source = line.pick, line.source
    local r, g, b = Theme.Unpack("text")
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Enchants:ShownName(pick.recipeID) or "", Theme.Unpack("accent"))
    GameTooltip:AddLine(L.Format("For your %s", line.plan.link or Enchants.SlotName(line.slot)), r, g, b, true)
    GameTooltip:AddLine(L.Format("Gives %s", Enchants:Gives(pick.recipeID) or ""), Theme.Unpack("good"))
    if line.plan.current then
        GameTooltip:AddLine(L.Format("Now: %s", Enchants:EnchantName(line.plan.current)), r, g, b, true)
    else
        GameTooltip:AddLine(L["Nothing on it now"], r, g, b)
    end
    if pick.percent then
        GameTooltip:AddLine(L.Format("%d%% better for your spec", math.floor(pick.percent + 0.5)), Theme.Unpack("good"))
    end
    if line.soon then
        local wr, wg, wb = Theme.Unpack("warn")
        GameTooltip:AddLine(L["A better piece for this slot is in your upgrade list. This is the cheapest enchant still worth having until then."],
            wr, wg, wb, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["How to get it"], Theme.Unpack("accent"))
    GameTooltip:AddLine(Enchants:Describe(source, Finder.Money), r, g, b, true)
    local materials = Enchants:MaterialsText(pick.recipeID)
    if materials ~= "" then
        GameTooltip:AddLine(L.Format("Materials: %s", materials), r, g, b, true)
    end
    local place = (source and (source.state == "learn" or source.state == "skill"))
        and Enchants:WhereToLearn(pick.recipeID)
    if place and place.name then
        local where = place.zone and L.Format("Learn it from %s in %s", place.name, Finder.ShownZone(place.zone))
            or L.Format("Learn it from %s", place.name)
        GameTooltip:AddLine(where, r, g, b, true)
    end
    if #FinderUI.EnchantMenu(line) > 0 then
        GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    end
    GameTooltip:Show()
end

--- Gear you own that beats what you wear: its tooltip, and where it is.
local function ShowOwnedTooltip(row, owned)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, owned.link)
    GameTooltip:AddLine(" ")
    if FinderUI.CanPutOn(owned) then
        GameTooltip:AddLine(L["Click to put it on"], Theme.Unpack("good"))
        GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    elseif owned.where ~= "bags" and ns.UI then
        GameTooltip:AddLine(ns.UI.WhereText(owned.where), Theme.Unpack("accent"))
    end
    GameTooltip:Show()
end

local function ShowTooltip(row)
    if rawget(row, "heading") then return end
    local owned = rawget(row, "owned")
    if owned then return ShowOwnedTooltip(row, owned) end
    local enchant = rawget(row, "enchant")
    if enchant then return ShowEnchantTooltip(row, enchant) end
    local pick = row.pick
    if not pick then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, pick.link)
    GameTooltip:AddLine(" ")
    if pick.needs then
        GameTooltip:AddLine(Finder.NeedsText(pick.needs), Theme.Unpack("warn"))
    end
    if pick.at then
        GameTooltip:AddLine(L.Format("You can wear it from level %d", pick.at), Theme.Unpack("warn"))
    end
    local roll = Finder.RollText(pick)
    if roll then
        local r, g, b = Theme.Unpack("good")
        GameTooltip:AddLine(roll, r, g, b, true)
    end
    GameTooltip:AddLine(L["Where to get it"], Theme.Unpack("accent"))
    for index, source in ipairs(pick.sources) do
        if index > TOOLTIP_SOURCES then
            GameTooltip:AddLine(L.Format("and %d more", #pick.sources - TOOLTIP_SOURCES),
                Theme.Unpack("muted"))
            break
        end
        GameTooltip:AddLine(FinderUI.SourceLine(source), Theme.Unpack("text"))
        if source.after then
            GameTooltip:AddLine(L.Format("    after %s", source.after), Theme.Unpack("muted"))
        end
        if source.kind == "craft" and ns.Crafting then
            -- Light, so it reads on the tooltip's dark background.
            local r, g, b = Theme.Unpack("text")
            GameTooltip:AddLine(L.Format("    Materials: %s", ns.Crafting:MaterialsText(pick.itemID)), r, g, b, true)
        end
    end
    GameTooltip:AddLine(" ")
    local quest = ns.UpgradeQuest
    if quest then
        local _, why = quest.CanFollow(pick)
        -- What a click does, said plainly: players took the green Quest
        -- tag it leaves for a mistake (2026-10-09).
        local r, g, b = Theme.Unpack("text")
        if quest:IsFollowing(pick.itemID) then
            GameTooltip:AddLine(L["Your upgrade quest: click to show it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["The green Quest tag marks it. To drop it, click Ignore on the quest panel."], r, g, b, true)
        elseif why then
            local wr, wg, wb = Theme.Unpack("warn")
            GameTooltip:AddLine(L.Format("Not a quest yet: %s", why), wr, wg, wb, true)
        else
            GameTooltip:AddLine(L["Click to follow it on the quest panel"], Theme.Unpack("good"))
            GameTooltip:AddLine(L["It becomes your upgrade quest, with steps to get it. A green Quest tag marks it here."], r, g, b, true)
        end
    end
    if FinderUI.Place(pick) then
        GameTooltip:AddLine(L["Alt-click to pin it on your map"], Theme.Unpack("dim"))
    end
    GameTooltip:AddLine(L["Right-click for more."], Theme.Unpack("dim"))
    GameTooltip:Show()
end

FinderUI.ShowRowTooltip = ShowTooltip

--- A click on a list row, here or on My Gear (UI/MyGear.lua): `self` is
--- the row, with its `pick`, `owned` or `enchant`.
function FinderUI.RowClicked(self, button)
    if rawget(self, "heading") then return end
    -- A right-click opens the row's menu (UI/RowMenu.lua), the same in
    -- every Blackthornes list.
    if button == "RightButton" then
        FinderUI:OpenRowMenu(self)
        return
    end
    -- Gear you own: Shift-click links it, a click puts on one in your bags.
    local owned = rawget(self, "owned")
    if owned then
        -- Ctrl-click tries it on, as the game's bags do.
        if Widgets.ItemTryOn(nil, owned.link) then return end
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                pcall(ChatEdit_InsertLink, owned.link)
                return
            end
        end
        if button ~= "RightButton" and FinderUI.CanPutOn(owned) and ns.Wear then ns.Wear:PutOn(owned.link) end
        return
    end
    -- An enchant row's buttons do its work; Shift-click links its recipe.
    local enchant = rawget(self, "enchant")
    if enchant then
        if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
            local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
            if ok and chatLink then
                local okLink, link = pcall(function()
                    local spell = _G.C_Spell and _G.C_Spell.GetSpellLink
                    return spell and spell(enchant.pick.recipeID) or nil
                end)
                if okLink and link then pcall(ChatEdit_InsertLink, link) end
            end
        end
        return
    end
    local pick = self.pick
    if not pick then return end
    local okAlt, alt = pcall(function() return IsAltKeyDown() == true end)
    if okAlt and alt then
        local place = FinderUI.Place(pick)
        if place and ns.Waypoints then ns.Waypoints:Show(place, place.name, Theme.ItemIcon(pick.link)) end
        return
    end
    if Widgets.ItemTryOn(nil, pick.link) then return end
    if type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
        local ok, chatLink = pcall(IsModifiedClick, "CHATLINK")
        if ok and chatLink then
            pcall(ChatEdit_InsertLink, pick.link)
            return
        end
    end
    -- A plain click follows it on the upgrade quest panel (asked 2026-10-06).
    FinderUI:Follow(pick)
    if rawget(self, "over") == true then ShowTooltip(self) end
end

--- A menu line changed what a row shows (tracked, queued): the page up
--- draws again. It judges nothing.
function FinderUI.PagesChanged()
    local Gear = ns.GearWindow
    if Gear and Gear.Refresh then pcall(Gear.Refresh, Gear) end
end

--- The menu lines of an enchant row: Queue It and Show the Way.
function FinderUI.EnchantMenu(line)
    local Enchants = ns.Enchants
    local lines = {}
    if not (Enchants and line) then return lines end
    if Enchants:CanQueue() then
        lines[#lines + 1] = { text = L["Queue It"], run = function() Enchants:Queue(line.pick.recipeID) end }
    end
    local state = line.source and line.source.state
    if (state == "learn" or state == "skill") and Enchants:CanShowTheWay(line.pick.recipeID) then
        lines[#lines + 1] = { text = L["Show the Way"], run = function()
            if not Enchants:ShowTheWay(line.pick.recipeID) then
                ns.Print(L["Couldn't find where to learn it."])
            end
        end }
    end
    return lines
end

--- The menu lines of a gear row: Follow, Track or Stop Tracking, Show on
--- Map and Queue It, the plain click's first.
function FinderUI.PickMenu(pick, sources)
    local lines = {}
    local quest = ns.UpgradeQuest
    if quest then
        local can = quest.CanFollow(pick)
        lines[#lines + 1] = { text = L["Follow"], disabled = not can,
            checked = quest:IsFollowing(pick.itemID), run = function() FinderUI:Follow(pick) end }
    end
    if ns.Tracking then
        local tracked = ns.Tracking:IsTracked(pick.itemID)
        lines[#lines + 1] = { text = tracked and L["Stop Tracking"] or L["Track"], run = function()
            ns.Tracking:Toggle(pick)
            FinderUI.PagesChanged()
        end }
    end
    local place = FinderUI.Place(pick)
    if place and ns.Waypoints then
        lines[#lines + 1] = { text = L["Show on Map"], run = function()
            ns.Waypoints:Show(place, place.name, Theme.ItemIcon(pick.link))
        end }
    end
    local craft = ns.TradeskillsQueue and ns.TradeskillsQueue:Available()
        and ns.TradeskillsQueue.CraftSource(sources or pick.sources) or nil
    if craft then
        lines[#lines + 1] = { text = L["Queue It"], run = function()
            ns.TradeskillsQueue:Queue(craft)
            FinderUI.PagesChanged()
        end }
    end
    return lines
end

--- A right-click on a row: its menu, titled with the item's name.
function FinderUI:OpenRowMenu(row)
    if not ns.RowMenu then return end
    local lines, title
    local owned, enchant, pick = rawget(row, "owned"), rawget(row, "enchant"), rawget(row, "pick")
    if owned then
        lines = {}
        if FinderUI.CanPutOn(owned) and ns.Wear then
            lines[1] = { text = L["Put It On"], run = function() ns.Wear:PutOn(owned.link) end }
        end
        title = owned.link
    elseif enchant then
        lines = FinderUI.EnchantMenu(enchant)
        title = ns.Enchants and ns.Enchants:ShownName(enchant.pick.recipeID)
    elseif pick then
        lines = FinderUI.PickMenu(pick)
        title = pick.link
    end
    if not lines or #lines == 0 then return end
    if type(title) == "string" then title = title:match("%[(.-)%]") or title end
    GameTooltip:Hide()
    ns.RowMenu:Open(lines, { title = title })
end

--------------------------------------------------------------------------------
-- The choices every page shares
--------------------------------------------------------------------------------

--- The spec keys this character can pick from, "auto" first (Settings'
--- list, so both drop-downs match).
function FinderUI.SpecChoices()
    if ns.SettingsUI and ns.SettingsUI.SpecChoices then return ns.SettingsUI:SpecChoices() end
    return { "auto" }, nil
end

--- A spec choice's words: "Auto (Retribution)", or the spec's name.
function FinderUI.SpecText(index)
    local choices, specs = FinderUI.SpecChoices()
    local key = choices[index]
    if key == "auto" or not key or not specs or not specs[key] then
        local auto = Weights.AutoSpec and Weights:AutoSpec()
        local name = auto and specs and specs[auto] and Weights.Label(specs[auto].name)
        return name and (L["Auto"] .. " (" .. name .. ")") or L["Auto"]
    end
    return Weights.Label(specs[key].name)
end

--- The Off Spec keys, "none" first (Settings' list).
function FinderUI.OffSpecChoices()
    if ns.SettingsUI and ns.SettingsUI.OffSpecChoices then return ns.SettingsUI:OffSpecChoices() end
    return { "none" }, nil
end

--- An Off Spec choice's words: "None", or the spec's name.
function FinderUI.OffSpecText(index)
    local choices, specs = FinderUI.OffSpecChoices()
    local key = choices[index]
    if key == "none" or not key or not specs or not specs[key] then return L["None"] end
    return Weights.Label(specs[key].name)
end

--- The Main Spec drop-down every page shows (the same pick as Settings).
function FinderUI.MainSpecChoice(parent, width)
    return Widgets.CreateChoice(parent, {
        min = 1, max = math.max(1, #FinderUI.SpecChoices()), step = 1, value = 1, width = width or 150,
        format = function(index) return FinderUI.SpecText(index) end,
        onChange = function(index)
            local choices = FinderUI.SpecChoices()
            if ns.SettingsUI and ns.SettingsUI.SetSpec then ns.SettingsUI:SetSpec(choices[index] or "auto") end
        end,
    })
end

--- The Off Spec drop-down every page shows beside it.
function FinderUI.OffSpecChoice(parent, width)
    return Widgets.CreateChoice(parent, {
        min = 1, max = math.max(1, #FinderUI.OffSpecChoices()), step = 1, value = 1, width = width or 130,
        format = function(index) return FinderUI.OffSpecText(index) end,
        onChange = function(index)
            local choices = FinderUI.OffSpecChoices()
            if ns.SettingsUI and ns.SettingsUI.SetOffSpec then
                ns.SettingsUI:SetOffSpec(choices[index] or "none")
            end
        end,
    })
end

local function SyncChoice(choice, choices, text, picked, fallback)
    if not choice then return end
    local options = rawget(choice, "options")
    if type(options) == "table" then
        for index = #options, 1, -1 do options[index] = nil end
        for index = 1, #choices do options[index] = { text = text(index), value = index } end
    end
    local index = fallback
    for i, key in ipairs(choices) do
        if key == picked then index = i end
    end
    choice:SetValue(index, true)
end

--- Put both drop-downs in step with the saved picks.
function FinderUI.SyncSpecChoices(main, off)
    SyncChoice(main, (FinderUI.SpecChoices()), FinderUI.SpecText, ns.charDB and ns.charDB.spec, 1)
    SyncChoice(off, (FinderUI.OffSpecChoices()), FinderUI.OffSpecText, ns.charDB and ns.charDB.offSpec, 1)
end

--- Is "Only what I can get now" ticked? Saved account wide as
--- `finderGetNow`, off unless ticked.
function FinderUI:GetNowOnly()
    return ns.db ~= nil and ns.db.finderGetNow == true
end

function FinderUI:SetGetNowOnly(on)
    if not ns.db then return end
    ns.db.finderGetNow = on and true or false
    self.TellQuest()
end

--- The upgrade quest picks only what this window's filters let through,
--- so it hears when one changes.
function FinderUI.TellQuest()
    local quest = ns.UpgradeQuest
    if quest and quest.WindowFiltersChanged then pcall(quest.WindowFiltersChanged, quest) end
end

--- Can this source be used now? Not for gear that waits on a reputation
--- not reached, nor a craft that you or your other characters can't make
--- yet (one still to learn, or someone else's).
function FinderUI.GetsNow(source, pick)
    if pick.needs then return false end
    if source.kind == "craft" then return source.state == "known" or source.state == "alt" end
    return true
end

--- The tick box a source counts under: "raid" for a raid's drop, else its
--- kind.
function FinderUI.SourceKind(source)
    if source.kind == "dungeon" and source.raid then return "raid" end
    return source.kind
end

--- Is this kind of source ticked? Every kind is until unticked.
function FinderUI:SourceOn(kind)
    local off = ns.db and ns.db.finderSourcesOff
    return not (type(off) == "table" and off[kind] == true)
end

function FinderUI:SetSource(kind, on)
    if not ns.db then return end
    if type(ns.db.finderSourcesOff) ~= "table" then ns.db.finderSourcesOff = {} end
    ns.db.finderSourcesOff[kind] = (not on) or nil
    self.TellQuest()
end

--- Is "This zone only" ticked? Saved account wide as `finderZoneOnly`,
--- off unless ticked.
function FinderUI:ZoneOnly()
    return ns.db ~= nil and ns.db.finderZoneOnly == true
end

function FinderUI:SetZoneOnly(on)
    if not ns.db then return end
    ns.db.finderZoneOnly = on and true or false
    self.TellQuest()
end

--- The zone the list keeps to, or nil for anywhere.
function FinderUI:Here(found)
    if not self:ZoneOnly() then return nil end
    local quest = ns.UpgradeQuest
    return quest and quest.Zone() or (found and found.player and found.player.zone) or nil
end

--- The quest level stepper's place: 0 to 10 levels up, or 11 for any.
function FinderUI:QuestLevelsValue()
    return Finder:QuestLevelsAbove() or Finder.QUEST_LEVELS_ANY
end

--- Its words: "Up to my level", "Up to +4" or "Any".
function FinderUI.QuestLevelsText(value)
    if (value or 0) >= Finder.QUEST_LEVELS_ANY then return L["Any"] end
    if (value or 0) <= 0 then return L["Up to my level"] end
    return L.Format("Up to +%d", value)
end

--- How many levels ahead the window looks (0 for now).
function FinderUI:Ahead()
    local value = tonumber(ns.db and ns.db.finderAhead) or 0
    return math.max(0, math.min(MOST_AHEAD, math.floor(value)))
end

--- The stepper's words: "Now", or "Level 27".
function FinderUI.AheadText(value)
    if (value or 0) <= 0 then return L["Now"] end
    local level = ns.Items and ns.Items:PlayerLevel()
    if not level then return L.Format("+%d levels", value) end
    return L.Format("Level %d", math.min(60, level + value))
end

--- Where a pick's first source with an exact spot is, for the map.
function FinderUI.Place(pick)
    for _, source in ipairs(pick and pick.sources or {}) do
        if source.zone and source.x and source.y then return source end
    end
    return nil
end

--- Each slot's lines, by the key of its line on the left (SLOT_GROUPS):
--- `{ lines, total }`, `total` every upgrade found for it and `lines` those
--- with a source the tick boxes, "Only what I can get now" and "This zone
--- only" let through, best first. Every pick, not only the few best: the
--- list for one slot runs as long as it needs.
--- The window's filters as one test (the source boxes, "Only what I can
--- get now" and "This zone only"): the function it gives takes a pick and
--- answers the sources of it that pass, in order, a fresh list each time.
--- The window's slot lists and the character sheet's tooltip both use it,
--- so they always agree.
function FinderUI:SourceFilter(found)
    local here = self:Here(found)
    local inZone = ns.UpgradeQuest and ns.UpgradeQuest.InZone
    local getNow = self:GetNowOnly()
    local on = {}
    for _, entry in ipairs(SOURCE_BOXES) do on[entry[1]] = self:SourceOn(entry[1]) end
    return function(pick)
        local sources = {}
        for _, source in ipairs(pick.sources or {}) do
            local kind = FinderUI.SourceKind(source)
            if on[kind] ~= false and (not getNow or FinderUI.GetsNow(source, pick))
                and (not here or not inZone or inZone(source, here)) then
                sources[#sources + 1] = source
            end
        end
        return sources
    end
end

--- The From boxes alone, for My Gear's Gear Road (UI/GearRoad.lua): it
--- shows gear for later on purpose, so Only What I Can Get Now and This
--- Zone Only don't apply there.
function FinderUI:KindFilter()
    local on = {}
    for _, entry in ipairs(SOURCE_BOXES) do on[entry[1]] = self:SourceOn(entry[1]) end
    return function(pick)
        local sources = {}
        for _, source in ipairs(pick.sources or {}) do
            if on[FinderUI.SourceKind(source)] ~= false then sources[#sources + 1] = source end
        end
        return sources
    end
end

--- An item's name in its rarity colour, from its link: plain text, so it
--- can be cut to fit. Forever writes the colour by name ("|cnIQ2:"), not
--- as "|cff1eff00": then the colour comes from the item's quality, and if
--- the client can't say yet, from the link's own named colour.
function FinderUI.ItemText(link)
    if type(link) ~= "string" then return "" end
    local name = link:match("%[(.-)%]") or link
    local color = link:match("|c(%x%x%x%x%x%x%x%x)")
    if color then return "|c" .. color .. name .. "|r" end
    local Items = ns.Items
    if Items and Items.ColorName then
        local shown = Items.ColorName(link, name)
        if shown ~= name then return shown end
    end
    local named = link:match("|cn[%w_]+:")
    return named and (named .. name .. "|r") or name
end

--- Can a click put this owned piece on? Only one in the bags, and never
--- a weapon whose skill is not trained yet.
function FinderUI.CanPutOn(owned)
    return type(owned) == "table" and owned.where == "bags"
        and not (owned.result and owned.result.skill)
end

--- The level a pick can be worn from: the level it waits for, else the
--- client's, else the data's. Nil when it asks for none.
function FinderUI.LevelOf(pick)
    if pick.at then return pick.at end
    local info = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if type(info) == "function" then
        local ok, _, _, _, _, level = pcall(info, pick.link or pick.itemID)
        if ok and tonumber(level) and level > 0 then return level end
    end
    local item = ns.Sources and ns.Sources.ITEMS and ns.Sources.ITEMS[pick.itemID]
    if item and tonumber(item[1]) and item[1] > 0 then return item[1] end
    local craft = ns.Crafts and ns.Crafts.ITEMS and ns.Crafts.ITEMS[pick.itemID]
    if craft and tonumber(craft[4]) and craft[4] > 0 then return craft[4] end
    return nil
end

--- Where a line's first source is: the dungeon for a drop, the profession
--- for a craft, else the zone. Nil when it has no place.
function FinderUI.WhereOf(line)
    local source = line.sources and line.sources[1]
    if not source then return nil end
    if source.kind == "dungeon" then return Finder.ShownZone(source.dungeon or source.zone) end
    if source.kind == "craft" then return source.profession end
    return Finder.ShownZone(source.zone)
end

--- A pick's name, for sorting.
function FinderUI.ItemName(pick)
    local name = type(pick.link) == "string" and pick.link:match("%[(.-)%]")
    if not name then
        local info = (_G.C_Item and _G.C_Item.GetItemNameByID) or nil
        local ok, found = pcall(function() return info and info(pick.itemID) end)
        name = ok and found or nil
    end
    return name or tostring(pick.link or pick.itemID or "")
end

--- Follow a row's pick on the upgrade quest panel, or say why it cannot be.
function FinderUI:Follow(pick)
    local logic = ns.UpgradeQuest
    if not logic then return nil end
    local quest, why = logic:Follow(pick)
    if quest then
        ns.Print(L.Format("following %s on the upgrade quest panel.", ns.Items.ShowLink(pick.link or quest.link)))
    else
        ns.Print(L.Format("%s can't be an upgrade quest yet: %s.", pick.link and ns.Items.ShowLink(pick.link) or L["that"], why or L["unknown"]))
    end
    return quest
end

--- Open Find Upgrades (UI/FindUpgrades.lua), for everything that used to
--- open the old gear list: the upgrade banner, the small panel's Change,
--- the slot panel's All Upgrades.
function FinderUI.OpenFind()
    local Gear = ns.GearWindow
    if Gear then Gear:Open("find") end
end

-- A round button kept from the old list's window ("Finder" in
-- `foldedWindows`, UI/FoldWindow.lua) opens Find Upgrades.
if ns.FoldWindow and ns.FoldWindow.Opener then
    ns.FoldWindow:Opener("Finder", { open = function() FinderUI.OpenFind() end })
end
