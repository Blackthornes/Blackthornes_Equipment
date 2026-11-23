-- Blackthornes Equipment -- UI/DungeonsTab.lua
-- Dungeons, the Equipment window's fourth tab (rework step 5, the owner
-- approved the mockup 2026-11-22). Dungeon Loot and Dungeon Quests were
-- two tabs that each made the player pick the dungeon again. Here it is
-- picked once.
--
--   The left   every dungeon and raid: its levels, how many of its drops
--              are upgrades, and how many of its quests are done. A
--              heading sorts. One above the character's level reads Later.
--   The right  the dungeon picked: each boss with its drops, the drop
--              chance and the gain, then QUESTS INSIDE with where each
--              starts, its reward and Show the Way.
--
-- What it reads is the old tabs' own: Logic/DungeonLoot.lua for the drops
-- and Logic/DungeonQuests.lua for the quests. Upgrades Only is this page's
-- for the session; Hide Finished Quests writes the old tab's saved
-- `dungeonQuestsHideDone`, and the dungeon picked is the old tab's
-- `dungeonLootPick`. No new saved key.
--
-- The work it does: the count beside each dungeon comes from the finder's
-- last whole scan (nothing is judged for it), and only the dungeon picked
-- has its drops judged, through the finder's kept verdicts, so a second
-- look judges nothing. A click on a dungeon, a heading or a box starts no
-- scan. Nothing runs while the page is hidden.

local _, ns = ...
local L = ns.L

local Dungeons = ns.NewModule("DungeonsTab")

local Theme = ns.Theme
local Widgets = ns.Widgets

-- The page's key in the Equipment window. "dungeons" and "loot" still name
-- the old tabs' windows until step 6 takes them out.
Dungeons.KEY = "instances"
-- It stands in for the old Dungeon Loot and Dungeon Quests tabs: /beq loot
-- and /beq dungeons open it. A suite that tests the old tabs sets
-- env.OLD_PANELS, which clears this.
Dungeons.standsIn = true

local PAD = 18
local WIDTH = 1040
local LEFT_SHARE = 0.40
local ROW = 26
local HEAD = 22
local ICON = 20
local MOST_DUNGEONS = 26
local MOST_LINES = 26
local WHEEL = 3
local FOOT = 22

-- The left list's cells, from the right.
local QUESTS_WIDTH = 64
local UPGRADES_WIDTH = 78
local LEVELS_WIDTH = 60
-- The right list's cells, from the right.
local GAIN_WIDTH = 104
local DROPS_WIDTH = 50
local SLOT_WIDTH = 120
local GAP = 8

local BOSS_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local DONE_ICON = [[Interface\RaidFrame\ReadyCheck-Ready]]

local function Shown(frame)
    if not frame then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

local function TextHeight(label, size, width)
    local text = label:GetText() or ""
    if text == "" then return 0 end
    local ok, height = pcall(label.GetStringHeight, label)
    if ok and type(height) == "number" and height > 0 then return height end
    local lines = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        local plain = part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        lines = lines + math.max(1, math.ceil(Theme.TextWidth(size, plain) / math.max(1, width)))
    end
    return lines * ((Theme.sizes[size] or 10) + 2)
end

local function Tip(frame, title, words)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, Theme.Unpack("accent"))
        if words then GameTooltip:AddLine(words, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------------------------------------
-- What it shows
--------------------------------------------------------------------------------

--- A wing's dungeon: "189Library" shares the quests of "189".
function Dungeons.BaseKey(key)
    return type(key) == "string" and key:match("^(%d+)%a") or nil
end

--- "25-35", "60", or "" when the data gives no levels.
function Dungeons.Levels(dungeon)
    local low, high = dungeon.low, dungeon.high
    if not low then return "" end
    if not high or high == low then return tostring(low) end
    return ("%d-%d"):format(low, high)
end

--- Is the dungeon above the character's level for now?
function Dungeons.IsLater(dungeon, level)
    return (dungeon.low or 0) > (level or 0)
end

--- How many upgrades each dungeon holds, by its key, read from a whole
--- scan of the finder: every upgrade to wear now whose places name a boss
--- there. Nothing is judged here.
function Dungeons.Counts(found)
    local counts = {}
    if type(found) ~= "table" or type(found.all) ~= "table" then return counts end
    local S = ns.Sources
    local keyOf = {}
    for key, row in pairs(S and S.DUNGEONS or {}) do
        if type(row) == "table" and type(row[1]) == "string" then keyOf[row[1]] = key end
    end
    local seen = {}
    for _, list in pairs(found.all) do
        for _, pick in ipairs(list) do
            if not pick.mainToo and ns.Compare.WearableUpgrade(pick.result) then
                for _, source in ipairs(pick.sources or {}) do
                    local key = source.kind == "dungeon" and keyOf[source.dungeon]
                    if key and not seen[key .. ":" .. pick.itemID] then
                        seen[key .. ":" .. pick.itemID] = true
                        counts[key] = (counts[key] or 0) + 1
                    end
                end
            end
        end
    end
    return counts
end

--- The finder's line for an item, when its last scan holds one: what the
--- row's menu acts on (track it, make it the quest).
function Dungeons.PickFor(itemID)
    local found = ns.Finder and ns.Finder.latest
    if not (itemID and type(found) == "table" and type(found.all) == "table") then return nil end
    for _, list in pairs(found.all) do
        for _, pick in ipairs(list) do
            if pick.itemID == itemID and not pick.mainToo then return pick end
        end
    end
    return nil
end

--- Every dungeon and raid for this character's side: the ones with drops
--- and the ones with quests, each { key, name, low, high, door, raid,
--- forever, later, upgrades, done, all, quests }.
function Dungeons:Read(found)
    local Finder, DL, DQ = ns.Finder, ns.DungeonLoot, ns.DungeonQuests
    local player = Finder and Finder:Player()
    local level = player and player.level or 0
    local counts = Dungeons.Counts(found)
    local quests = {}
    local okQuests, built = pcall(DQ.Build, DQ, true)
    for _, dungeon in ipairs(okQuests and built.dungeons or {}) do quests[dungeon.key] = dungeon end

    local list, have = {}, {}
    local okLoot, loot = pcall(DL.Dungeons, DL, player)
    for _, dungeon in ipairs(okLoot and loot or {}) do
        have[dungeon.key] = true
        local base = Dungeons.BaseKey(dungeon.key)
        if base then have[base] = true end
        list[#list + 1] = dungeon
    end
    -- A dungeon with quests and no drops seen still gets its line.
    for key, dungeon in pairs(quests) do
        if not have[key] then
            list[#list + 1] = { key = key, name = dungeon.name, low = dungeon.low, high = dungeon.high,
                door = dungeon.door, raid = dungeon.raid, forever = dungeon.forever, count = 0 }
        end
    end
    for order, dungeon in ipairs(list) do
        local own = quests[dungeon.key] or quests[Dungeons.BaseKey(dungeon.key) or ""]
        dungeon.order = order
        dungeon.quests = own and own.quests or {}
        dungeon.done, dungeon.all = own and own.done or 0, own and own.all or 0
        if dungeon.forever and not dungeon.low and own then dungeon.low, dungeon.high = own.low, own.high end
        dungeon.later = Dungeons.IsLater(dungeon, level)
        dungeon.upgrades = counts[dungeon.key] or 0
    end
    -- Classic's by their levels, raids after, Forever's own last, as the
    -- old tabs had them; the quest-only ones were added out of order.
    table.sort(list, function(a, b)
        if (a.forever or false) ~= (b.forever or false) then return not a.forever end
        if (a.raid or false) ~= (b.raid or false) then return not a.raid end
        if (a.low or 0) ~= (b.low or 0) then return (a.low or 0) < (b.low or 0) end
        return a.name < b.name
    end)
    for order, dungeon in ipairs(list) do dungeon.order = order end
    return list, level
end

--- The list in the order a heading asks for. No key: the order read.
function Dungeons.Sorted(list, key, flip)
    local sorted = {}
    for index, dungeon in ipairs(list) do sorted[index] = dungeon end
    if not key then return sorted end
    local function Value(dungeon)
        if key == "name" then return dungeon.name end
        if key == "levels" then return dungeon.low or 999 end
        if key == "upgrades" then return dungeon.later and -1 or -(dungeon.upgrades or 0) - 1 end
        if key == "quests" then return -((dungeon.all or 0) - (dungeon.done or 0)) end
    end
    table.sort(sorted, function(a, b)
        local x, y = Value(a), Value(b)
        if key == "upgrades" then
            -- Later ones go last either way round.
            if a.later ~= b.later then return b.later end
        end
        if x ~= y then
            if flip then return x > y end
            return x < y
        end
        return a.order < b.order
    end)
    return sorted
end

--- What the gain cell says for a drop: the words and their colour.
function Dungeons.GainText(row)
    local result = row.result
    if row.upgrade then
        if row.gain then return ("%+d%%"):format(row.gain), "good" end
        return L["empty slot"], "good"
    end
    if type(result) ~= "table" then return "", "muted" end
    if result.verdict == "upgrade" and result.level then
        return L.Format("Level %d", result.level), "warn"
    end
    if result.verdict == "upgrade" and (result.train or result.skill) then
        local percent = ns.Finder.Shown(result)
        return percent and ("%+d%%"):format(percent) or L["empty slot"], "warn"
    end
    if result.verdict == "cantuse" then
        local who = result.specName
        if type(who) ~= "string" or who == "" then return "", "muted" end
        return L.Format("Not for %s", who), "dim"
    end
    return "", "muted"
end

--- "24%", "Under 1%", or "" when nobody has counted.
function Dungeons.ChanceText(chance)
    chance = tonumber(chance) or 0
    if chance <= 0 then return "" end
    if chance < 1 then return L["Under 1%"] end
    return ("%d%%"):format(math.floor(chance + 0.5))
end

--- The lines of the right side for a dungeon, top to bottom: a boss's
--- heading then its drops, bosses nobody has seen drop gear, then QUESTS
--- INSIDE and its quests. Returns the lines, the upgrades among the drops
--- and how many items the client has yet to send.
function Dungeons:Lines(dungeon)
    local lines = {}
    if not dungeon then return lines, 0, 0 end
    local DL, DQ, Finder = ns.DungeonLoot, ns.DungeonQuests, ns.Finder
    local ok, data = pcall(DL.Rows, DL, dungeon.key, nil, nil, self.upgradesOnly)
    if not ok or type(data) ~= "table" then data = { rows = {}, upgrades = 0, waiting = 0 } end

    -- Bosses in the game's order where it gives one, else as their best
    -- drop comes (the rows are best first).
    local order, byBoss = {}, {}
    local function Boss(name)
        local key = DL.BossKey(name) or ""
        local boss = byBoss[key]
        if not boss then
            boss = { name = name, rows = {} }
            byBoss[key] = boss
            order[#order + 1] = boss
        end
        return boss
    end
    if not self.upgradesOnly then
        for _, name in ipairs(DL:Bosses(dungeon.key)) do Boss(name) end
    end
    for _, row in ipairs(data.rows) do
        local boss = Boss(row.boss)
        if not row.bossOnly then boss.rows[#boss.rows + 1] = row end
    end
    for _, boss in ipairs(order) do
        lines[#lines + 1] = { kind = "boss", text = boss.name }
        if #boss.rows == 0 then
            lines[#lines + 1] = { kind = "unseen" }
        end
        for _, row in ipairs(boss.rows) do
            local gain, color = Dungeons.GainText(row)
            lines[#lines + 1] = { kind = "drop", itemID = row.itemID, link = row.link,
                name = row.name ~= "" and row.name or DL.NameOf(row.itemID), slot = row.slot,
                chance = Dungeons.ChanceText(row.chance), gain = gain, gainColor = color, upgrade = row.upgrade }
        end
    end
    if #order == 0 then
        lines[#lines + 1] = { kind = "note", text = self.upgradesOnly
            and (data.waiting > 0 and L["Reading the drops. This takes a moment the first time."]
                or L["No drop here is an upgrade for you right now."])
            or L["No drops seen here yet."] }
    end

    if #dungeon.quests > 0 or dungeon.all > 0 then
        lines[#lines + 1] = { kind = "boss", text = L["QUESTS INSIDE"] }
        if #dungeon.quests == 0 then
            lines[#lines + 1] = { kind = "note", text = L["Every quest here is done."] }
        end
        local judged = Finder and Finder:Judged()
        for _, quest in ipairs(dungeon.quests) do
            local parts = {}
            if (quest.level or 0) > 0 then parts[#parts + 1] = L.Format("Level %d.", quest.level) end
            if quest.zone and quest.zone ~= "" then
                parts[#parts + 1] = L.Format("Starts in %s.", Finder.ShownZone(quest.zone))
            end
            local reward = (quest.reward or 0) > 0 and quest.reward or nil
            if reward then
                local name = DL.NameOf(reward)
                if name ~= "" then
                    local link = ("item:%d"):format(reward)
                    local r, g, b = Theme.QualityColor(link)
                    if r then
                        name = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
                            math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
                    end
                    -- Its gain, when the client holds the item already.
                    if judged and Finder:IsCached(reward) then
                        local _, okJudge, result = Finder:JudgeOnce(judged, reward)
                        if okJudge and ns.Compare.WearableUpgrade(result) then
                            local percent = Finder.Shown(result)
                            name = ("%s |c%s%s|r"):format(name, ns.COLORS.upgrade,
                                percent and ("%+d%%"):format(percent) or L["empty slot"])
                        end
                    end
                    parts[#parts + 1] = L.Format("Reward: %s", name)
                elseif Finder then
                    Finder:Request(reward)
                end
            end
            lines[#lines + 1] = { kind = "quest", quest = quest, status = quest.status,
                name = DQ:TitleOf(quest), sub = table.concat(parts, " "), reward = reward,
                way = quest.status ~= "done" and DQ.Place(quest) ~= nil }
        end
    end
    return lines, data.upgrades or 0, data.waiting or 0
end

--- The foot's left line: "Scarlet Monastery: 7 upgrades for you, 3 quests
--- left."
function Dungeons.FootText(dungeon, upgrades)
    if not dungeon then return "" end
    local ups
    if dungeon.later then
        ups = L["its gear is for later"]
    elseif upgrades == 0 then
        ups = L["no upgrades for you"]
    elseif upgrades == 1 then
        ups = L["1 upgrade for you"]
    else
        ups = L.Format("%d upgrades for you", upgrades)
    end
    local left = (dungeon.all or 0) - (dungeon.done or 0)
    if (dungeon.all or 0) == 0 then return L.Format("%s: %s.", dungeon.name, ups) end
    local quests = left == 0 and L["every quest done"] or left == 1 and L["1 quest left"]
        or L.Format("%d quests left", left)
    return L.Format("%s: %s, %s.", dungeon.name, ups, quests)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Glass(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    row.background = Theme.Fill(row, row.restKey)
    local under = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
    under:SetColorTexture(Theme.Unpack("border", 0.6))
    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(3)
    edge:Hide()
    row.edge = edge
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    return row
end

local function Paint(row)
    local picked = rawget(row, "picked") == true
    local over = rawget(row, "over") == true and rawget(row, "plain") ~= true
    row.background:SetColorTexture(Theme.Unpack(rawget(row, "headed") and "header"
        or picked and "glassActive" or over and "glassHover" or row.restKey))
    row.edge:SetShown(picked or over)
    row.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
end

local function Arrow(parent, size)
    local arrow = parent:CreateTexture(nil, "OVERLAY")
    if ns.Titanforged then arrow:SetTexture(ns.Titanforged.MEDIA .. "SortArrow") end
    arrow:SetSize(size, size)
    return arrow
end

function Dungeons:BuildBar(page)
    local FinderUI = ns.FinderUI
    local judge = Theme.CreateLabel(page, "small", "muted")
    judge:SetPoint("TOPLEFT", PAD, -14)
    judge:SetText(L["Judge Gear As:"])
    local spec = Widgets.CreateChoice(page, {
        min = 1, max = math.max(1, #FinderUI.SpecChoices()), step = 1, value = 1, width = 150,
        format = function(index) return FinderUI.SpecText(index) end,
        onChange = function(index)
            local choices = FinderUI.SpecChoices()
            if ns.SettingsUI and ns.SettingsUI.SetSpec then ns.SettingsUI:SetSpec(choices[index] or "auto") end
        end,
    })
    spec:SetPoint("LEFT", judge, "RIGHT", 8, 0)
    self.specChoice = spec

    local hide = Widgets.CreateCheckbox(page, L["Hide Finished Quests"], function(checked)
        ns.DungeonQuests:SetHideDone(checked)
    end, ns.DungeonQuests.HideDone())
    hide:SetPoint("TOPRIGHT", -PAD - Theme.TextWidth("small", L["Hide Finished Quests"]) - 8, -12)
    self.hideBox = hide

    local only = Widgets.CreateCheckbox(page, L["Upgrades Only"], function(checked)
        Dungeons.upgradesOnly = checked == true
        Dungeons.offset = 0
        Dungeons:Draw()
    end, false)
    only:SetPoint("RIGHT", hide, "LEFT", -Theme.TextWidth("small", L["Upgrades Only"]) - 30, 0)
    Tip(only, L["Upgrades Only"], L["Shows only the drops that are better than what you wear."])
    self.onlyBox = only

    local rule = Theme.CreateDivider(page, "border")
    rule:SetPoint("TOPLEFT", PAD, -44)
    rule:SetPoint("TOPRIGHT", -PAD, -44)
    return 52
end

function Dungeons:SyncSpec()
    local FinderUI = ns.FinderUI
    local choice = self.specChoice
    if not (choice and FinderUI) then return end
    local choices = FinderUI.SpecChoices()
    local options = rawget(choice, "options")
    if type(options) == "table" and #options ~= #choices then
        for index = #options, 1, -1 do options[index] = nil end
        for index = 1, #choices do options[index] = { text = FinderUI.SpecText(index), value = index } end
    end
    local picked = ns.charDB and ns.charDB.spec
    local index = 1
    for i, key in ipairs(choices) do
        if key == picked then index = i end
    end
    choice:SetValue(index, true)
end

local function Heads(parent, heads, onClick)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(HEAD)
    Theme.Fill(bar, "header")
    local made = {}
    for _, head in ipairs(heads) do
        local button = CreateFrame("Button", nil, bar)
        button:SetHeight(HEAD)
        if head.left then
            button:SetPoint("LEFT", head.left, 0)
            button:SetWidth(head.width or 160)
        else
            button:SetPoint("RIGHT", -head.right, 0)
            button:SetWidth(head.width)
        end
        local label = Theme.CreateLabel(button, "tiny", "heading", head.justify)
        local arrow = Arrow(button, 8)
        if head.justify == "RIGHT" then
            label:SetPoint("RIGHT", 0, 0)
            arrow:SetPoint("RIGHT", label, "LEFT", -4, 0)
        else
            label:SetPoint("LEFT", 0, 0)
            arrow:SetPoint("LEFT", label, "RIGHT", 4, 0)
        end
        label:SetText(head.text)
        arrow:Hide()
        button.label, button.arrow, button.key = label, arrow, head.key
        if onClick then
            button:SetScript("OnClick", function(self) onClick(self.key) end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(L["Click a heading to sort. Click it again to flip the order, and a third time for best first."], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        made[#made + 1] = button
    end
    return bar, made
end

function Dungeons:BuildLeft(body, width)
    local left = Theme.CreatePanel(body, "well", "border")
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, FOOT)
    left:SetWidth(width)
    self.left = left
    local questsRight = 8
    local upgradesRight = questsRight + QUESTS_WIDTH + GAP
    local levelsRight = upgradesRight + UPGRADES_WIDTH + GAP
    self.leftColumns = { quests = questsRight, upgrades = upgradesRight, levels = levelsRight,
        name = width - levelsRight - LEVELS_WIDTH - GAP - 12 }
    local _, heads = Heads(left, {
        { key = "name", text = L["DUNGEON OR RAID"], left = 12, width = self.leftColumns.name },
        { key = "levels", text = L["LEVELS"], right = levelsRight, width = LEVELS_WIDTH },
        { key = "upgrades", text = L["UPGRADES"], right = upgradesRight, width = UPGRADES_WIDTH, justify = "RIGHT" },
        { key = "quests", text = L["QUESTS"], right = questsRight, width = QUESTS_WIDTH, justify = "RIGHT" },
    }, function(key) Dungeons:SortBy(key) end)
    self.leftHeads = heads

    local list = CreateFrame("Frame", nil, left)
    list:SetPoint("TOPLEFT", 1, -HEAD)
    list:SetPoint("BOTTOMRIGHT", -1, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Dungeons:ScrollDungeons(-delta * WHEEL) end)
    self.dungeonList = list
    self.dungeonRows = {}
    local columns = self.leftColumns
    for index = 1, MOST_DUNGEONS do
        local row = Glass(list, index)
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", 11, -6)
        row.name:SetWidth(columns.name)
        row.name:SetWordWrap(true)
        row.levels = Theme.CreateLabel(row, "small", "muted")
        row.levels:SetPoint("TOPRIGHT", -columns.levels, -7)
        row.levels:SetWidth(LEVELS_WIDTH)
        row.upgrades = Theme.CreateLabel(row, "normal", "good", "RIGHT")
        row.upgrades:SetPoint("TOPRIGHT", -columns.upgrades, -6)
        row.upgrades:SetWidth(UPGRADES_WIDTH)
        row.quests = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        row.quests:SetPoint("TOPRIGHT", -columns.quests, -7)
        row.quests:SetWidth(QUESTS_WIDTH)
        row:SetScript("OnEnter", function(self)
            self.over = true
            Paint(self)
        end)
        row:SetScript("OnLeave", function(self)
            self.over = false
            Paint(self)
        end)
        row:SetScript("OnClick", function(self)
            local dungeon = rawget(self, "dungeon")
            if dungeon then Dungeons:Pick(dungeon.key) end
        end)
        row:Hide()
        self.dungeonRows[index] = row
    end
end

function Dungeons:BuildRight(body, left)
    local right = Theme.CreatePanel(body, "well", "border")
    right:SetPoint("TOPLEFT", left + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, FOOT)
    self.right = right
    local width = WIDTH - PAD * 2 - left - 8
    self.rightWidth = width

    -- The dungeon picked: its name, where its door is, and the way there.
    local top = CreateFrame("Frame", nil, right)
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(44)
    Theme.Fill(top, "panel")
    local way = Widgets.CreateButton(top, L["Show the Way"], function()
        local dungeon = Dungeons:Picked()
        if not dungeon then return end
        ns.DungeonLoot:ShowTheWay(dungeon)
        ns.DungeonLoot:Follow(dungeon)
    end, { width = math.max(80, Theme.TextWidth("small", L["Show the Way"]) + 24), height = 22 })
    way:SetPoint("RIGHT", -10, 0)
    Tip(way, L["Show the Way"], L["Points the arrow at the dungeon's door and marks it on your map."])
    self.wayButton = way
    local name = Theme.CreateLabel(top, "large", "accentHi")
    name:SetPoint("TOPLEFT", 12, -6)
    self.dungeonName = name
    local where = Theme.CreateLabel(top, "small", "muted")
    where:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    where:SetWidth(width - 160)
    self.dungeonWhere = where

    local gainRight = 10
    local dropsRight = gainRight + GAIN_WIDTH + GAP
    local slotRight = dropsRight + DROPS_WIDTH + GAP
    self.rightColumns = { gain = gainRight, drops = dropsRight, slot = slotRight,
        name = width - slotRight - SLOT_WIDTH - GAP - (ICON + 18) }
    local heads = Heads(right, {
        { key = "item", text = L["ITEM"], left = ICON + 18, width = 120 },
        { key = "slot", text = L["SLOT"], right = slotRight, width = SLOT_WIDTH },
        { key = "drops", text = L["DROPS"], right = dropsRight, width = DROPS_WIDTH, justify = "RIGHT" },
        { key = "gain", text = L["GAIN"], right = gainRight, width = GAIN_WIDTH, justify = "RIGHT" },
    })
    heads:ClearAllPoints()
    heads:SetPoint("TOPLEFT", 1, -45)
    heads:SetPoint("TOPRIGHT", -1, -45)

    local list = CreateFrame("Frame", nil, right)
    list:SetPoint("TOPLEFT", 1, -45 - HEAD)
    list:SetPoint("BOTTOMRIGHT", -1, 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Dungeons:Scroll(-delta * WHEEL) end)
    self.list = list
    self.rows = {}
    local columns = self.rightColumns
    local wayWidth = math.max(80, Theme.TextWidth("small", L["Show the Way"]) + 24)
    self.wayWidth = wayWidth
    for index = 1, MOST_LINES do
        local row = Glass(list, index)
        row.icon = Theme.CreateItemIcon(row, ICON)
        row.icon:SetPoint("TOPLEFT", 8, -3)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetSize(14, 14)
        row.mark:SetPoint("TOPLEFT", 11, -6)
        row.mark:SetTexture(DONE_ICON)
        -- A quest still to do: a small dim square where the tick will go.
        row.ring = row:CreateTexture(nil, "ARTWORK")
        row.ring:SetSize(6, 6)
        row.ring:SetPoint("TOPLEFT", 15, -10)
        row.ring:SetColorTexture(Theme.Unpack("dim"))
        row.name = Theme.CreateLabel(row, "normal", "text")
        row.name:SetPoint("TOPLEFT", ICON + 18, -6)
        row.name:SetWordWrap(true)
        row.sub = Theme.CreateLabel(row, "small", "muted")
        row.sub:SetWordWrap(true)
        row.slot = Theme.CreateLabel(row, "small", "muted")
        row.slot:SetPoint("TOPRIGHT", -columns.slot, -7)
        row.slot:SetWidth(SLOT_WIDTH)
        row.slot:SetWordWrap(true)
        row.drops = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        row.drops:SetPoint("TOPRIGHT", -columns.drops, -7)
        row.drops:SetWidth(DROPS_WIDTH)
        row.gain = Theme.CreateLabel(row, "normal", "good", "RIGHT")
        row.gain:SetPoint("TOPRIGHT", -columns.gain, -6)
        row.gain:SetWidth(GAIN_WIDTH)
        row.gain:SetWordWrap(true)
        row.way = Widgets.CreateButton(row, L["Show the Way"], function()
            local line = rawget(row, "line")
            local quest = line and line.quest
            if not quest then return end
            ns.DungeonQuests:ShowTheWay(quest)
            ns.DungeonQuests:Follow(quest)
        end, { width = wayWidth, height = 20 })
        row.way:SetPoint("TOPRIGHT", -8, -4)
        row:SetScript("OnEnter", function(self)
            self.over = true
            Paint(self)
            local line = rawget(self, "line")
            if not line then return end
            if line.kind == "drop" then
                Widgets.ItemTooltip(self, line.itemID, line.link, "ANCHOR_RIGHT")
            elseif line.kind == "quest" and line.reward then
                Widgets.ItemTooltip(self, line.reward, ("item:%d"):format(line.reward), "ANCHOR_RIGHT")
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.over = false
            Paint(self)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self) Dungeons:ClickLine(rawget(self, "line")) end)
        row:Hide()
        self.rows[index] = row
    end
end

function Dungeons:Build(area)
    if self.page then return self.page end
    if not (area and ns.DungeonLoot and ns.DungeonQuests and ns.FinderUI) then return nil end

    local page = CreateFrame("Frame", nil, area)
    page:SetAllPoints(area)
    Theme.Fill(page, "window")
    page:Hide()
    self.page = page

    local top = self:BuildBar(page)
    local body = CreateFrame("Frame", nil, page)
    body:SetPoint("TOPLEFT", PAD, -top)
    body:SetPoint("BOTTOMRIGHT", -PAD, 12)
    self.body, self.bodyTop = body, top
    local left = math.floor((WIDTH - PAD * 2) * LEFT_SHARE)
    self:BuildLeft(body, left)
    self:BuildRight(body, left)

    local foot = Theme.CreateLabel(body, "small", "muted")
    foot:SetPoint("BOTTOMLEFT", 2, 3)
    self.foot = foot
    local hint = Theme.CreateLabel(body, "small", "muted", "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -2, 3)
    hint:SetText(L["Click a drop to track it or make it your quest."])
    self.hint = hint
    return page
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Room(self, taken)
    local ok, height = pcall(self.page.GetHeight, self.page)
    if not (ok and type(height) == "number" and height > 200) then height = 620 end
    return height - self.bodyTop - 12 - FOOT - taken
end

function Dungeons:Picked()
    local key = ns.db and ns.db.dungeonLootPick
    for _, dungeon in ipairs(self.dungeons or {}) do
        if dungeon.key == key then return dungeon end
    end
    return nil
end

function Dungeons:PaintHeads()
    local key, flip = self.sortKey, self.sortFlip == true
    for _, head in ipairs(self.leftHeads) do
        local sorted = head.key == key
        head.label:SetTextColor(Theme.Unpack(sorted and "text" or "heading"))
        head.arrow:SetShown(sorted)
        if sorted then
            -- Upgrades and quests start with the most; the rest at the top.
            local down = (key == "upgrades" or key == "quests") ~= flip
            pcall(head.arrow.SetTexCoord, head.arrow, 0, 1, down and 0 or 1, down and 1 or 0)
        end
    end
end

function Dungeons:PaintDungeons()
    local list = Dungeons.Sorted(self.dungeons or {}, self.sortKey, self.sortFlip)
    self.sorted = list
    local picked = self:Picked()
    local room = Room(self, HEAD + 2)
    local offset = math.max(0, math.min(self.dungeonOffset or 0, math.max(0, #list - 1)))
    self.dungeonOffset = offset
    local y, shown = 0, 0
    for index, row in ipairs(self.dungeonRows) do
        local dungeon = list[index + offset]
        row:Hide()
        row.dungeon = nil
        if dungeon and shown == index - 1 then
            row.name:SetText(dungeon.name)
            row.levels:SetText(Dungeons.Levels(dungeon))
            if dungeon.later then
                row.upgrades:SetText(L["Later"])
                row.upgrades:SetTextColor(Theme.Unpack("dim"))
            elseif dungeon.upgrades > 0 then
                row.upgrades:SetText(tostring(dungeon.upgrades))
                row.upgrades:SetTextColor(Theme.Unpack("good"))
            else
                row.upgrades:SetText(L["None"])
                row.upgrades:SetTextColor(Theme.Unpack("dim"))
            end
            row.quests:SetText(dungeon.all > 0 and L.Format("%d of %d", dungeon.done, dungeon.all) or "")
            local on = picked ~= nil and picked.key == dungeon.key
            row.name:SetTextColor(Theme.Unpack(on and "accentHi" or dungeon.later and "dim" or "text"))
            local height = math.max(ROW, 6 + TextHeight(row.name, "normal", self.leftColumns.name) + 6)
            if index == 1 or y + height <= room then
                row.dungeon = dungeon
                row.picked = on
                row.restKey = index % 2 == 0 and "glassAlt" or "glass"
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(height)
                Paint(row)
                row:Show()
                y = y + height
                shown = index
            end
        end
    end
    self.dungeonsShown = shown
    self:PaintHeads()
end

--- Lay one line into a row and say how tall it stands.
function Dungeons:PaintLine(row, line, index)
    local columns = self.rightColumns
    row.line = line
    row.headed = line.kind == "boss"
    row.plain = line.kind ~= "drop" and line.kind ~= "quest"
    row.picked = false
    row.restKey = index % 2 == 0 and "glassAlt" or "glass"
    local drop, quest = line.kind == "drop", line.kind == "quest"
    row.icon:SetShown(drop or line.kind == "unseen")
    row.mark:SetShown(quest and line.status == "done")
    row.ring:SetShown(quest and line.status ~= "done")
    row.slot:SetText(drop and line.slot or "")
    row.drops:SetText(drop and line.chance or "")
    row.gain:SetText("")
    row.sub:SetText("")
    row.way:SetShown(quest and line.way == true)
    row.name:ClearAllPoints()
    row.icon:SetAlpha(1)
    if line.kind == "boss" then
        row.name:SetPoint("TOPLEFT", 12, -5)
        row.name:SetWidth(self.rightWidth - 24)
        row.name:SetFont(Theme.FONT, Theme.sizes.tiny, "")
        row.name:SetTextColor(Theme.Unpack("accent"))
        row.name:SetText(line.text:upper())
        return HEAD
    end
    row.name:SetFont(Theme.FONT, Theme.sizes.normal, "")
    if line.kind == "note" or line.kind == "unseen" then
        local unseen = line.kind == "unseen"
        if unseen then
            row.icon.icon:SetTexture(BOSS_ICON)
            Theme.SetBorderColor(row.icon, "border")
            row.icon:SetAlpha(0.55)
        end
        row.name:SetPoint("TOPLEFT", unseen and ICON + 18 or 12, -6)
        row.name:SetWidth(self.rightWidth - (unseen and ICON + 30 or 24))
        row.name:SetTextColor(Theme.Unpack("muted"))
        row.name:SetText(unseen and L["Loot not seen yet"] or line.text)
        return math.max(ROW, 6 + TextHeight(row.name, "normal", self.rightWidth - 24) + 6)
    end
    row.name:SetPoint("TOPLEFT", ICON + 18, -6)
    if drop then
        Theme.SetItemIcon(row.icon, line.link)
        row.name:SetWidth(columns.name)
        local r, g, b = Theme.QualityColor(line.link)
        if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(Theme.Unpack("text")) end
        row.name:SetText(line.name ~= "" and line.name or ns.Items.ShowLink(line.link) or "?")
        row.gain:SetPoint("TOPRIGHT", -columns.gain, -6)
        row.gain:SetText(line.gain)
        row.gain:SetTextColor(Theme.Unpack(line.gainColor or "good"))
        return math.max(ROW, 6 + math.max(TextHeight(row.name, "normal", columns.name),
            TextHeight(row.gain, "normal", GAIN_WIDTH), TextHeight(row.slot, "small", SLOT_WIDTH)) + 6)
    end
    -- A quest: its name, then where it starts and what it gives.
    local done = line.status == "done"
    local room = self.rightWidth - (ICON + 18) - 16 - (line.way and self.wayWidth + 8 or GAIN_WIDTH)
    row.name:SetWidth(room)
    row.name:SetTextColor(Theme.Unpack(done and "muted" or "text"))
    row.name:SetText(line.name)
    if not line.way then
        row.gain:SetPoint("TOPRIGHT", -columns.gain, -6)
        row.gain:SetText(done and L["Done"] or line.status == "log" and L["In Log"] or "")
        row.gain:SetTextColor(Theme.Unpack(done and "muted" or "accentHi"))
    end
    local nameHeight = TextHeight(row.name, "normal", room)
    local height = 6 + nameHeight + 6
    if not done and line.sub ~= "" then
        row.sub:ClearAllPoints()
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.sub:SetWidth(room)
        row.sub:SetText(line.sub)
        height = height + 2 + TextHeight(row.sub, "small", room)
    end
    return math.max(ROW, height)
end

--- Draw the right side. With `keep` (the wheel) the lines read last are
--- laid out again from a new place and nothing is read.
function Dungeons:PaintLines(keep)
    local dungeon = self:Picked()
    local lines, upgrades, waiting = self.lines, self.lineUpgrades, self.waiting
    if not (keep and lines) then
        lines, upgrades, waiting = self:Lines(dungeon)
        self.lines, self.lineUpgrades, self.waiting = lines, upgrades, waiting
    end
    -- The dungeon looked at shows what its own list counts.
    if dungeon and not dungeon.later and waiting == 0 then
        dungeon.upgrades = upgrades
    end
    self.dungeonName:SetText(dungeon and dungeon.name or "")
    local where = ""
    if dungeon and dungeon.door then
        where = L.Format("Door in %s.", ns.Finder.ShownZone(dungeon.door))
    end
    self.dungeonWhere:SetText(where)
    local door = dungeon and ns.DungeonLoot.Door(dungeon)
    self.wayButton:SetShown(door ~= nil)

    local room = Room(self, 46 + HEAD + 2)
    local offset = math.max(0, math.min(self.offset or 0, math.max(0, #lines - 1)))
    self.offset = offset
    local y, shown = 0, 0
    for index, row in ipairs(self.rows) do
        local line = lines[index + offset]
        row:Hide()
        if line and shown == index - 1 then
            local height = self:PaintLine(row, line, index)
            if index == 1 or y + height <= room then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(height)
                Paint(row)
                row:Show()
                y = y + height
                shown = index
            else
                row.line = nil
            end
        else
            row.line = nil
        end
    end
    self.linesShown = shown
    local foot = Dungeons.FootText(dungeon, dungeon and dungeon.upgrades or 0)
    if #lines > shown and shown > 0 then
        foot = foot .. " " .. L.Format("%d to %d of %d. Scroll for more.", offset + 1, offset + shown, #lines)
    end
    self.foot:SetText(foot)
end

--- Draw from what was read: a box, a pick or a heading changed, no gear.
function Dungeons:Draw()
    if not self.page then return end
    if self.onlyBox.SetChecked then self.onlyBox:SetChecked(self.upgradesOnly == true) end
    if self.hideBox.SetChecked then self.hideBox:SetChecked(ns.DungeonQuests.HideDone()) end
    self:PaintLines()
    self:PaintDungeons()
end

--- Read the dungeons with a scan's counts and draw them.
function Dungeons:Present(found)
    local ok, list, level = pcall(self.Read, self, found)
    self.dungeons, self.level = ok and list or {}, ok and level or 0
    if not ok and ns.Debug then ns.Debug("dungeons:", tostring(list)) end
    if not self:Picked() and self.dungeons[1] then
        -- The first one at or past the character's level, else the first.
        local pick
        for _, dungeon in ipairs(self.dungeons) do
            if (dungeon.high or 0) >= self.level and not dungeon.raid and not dungeon.forever then
                pick = dungeon
                break
            end
        end
        pick = pick or self.dungeons[1]
        if ns.db then ns.db.dungeonLootPick = pick.key end
    end
    self.read = true
    self:SyncSpec()
    self:Draw()
end

--------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------

function Dungeons:Pick(key)
    if ns.db then ns.db.dungeonLootPick = key end
    self.offset = 0
    self:Draw()
end

--- A heading: sort by it, flip on a second click, back to the levels on a
--- third.
function Dungeons:SortBy(key)
    if self.sortKey ~= key then
        self.sortKey, self.sortFlip = key, false
    elseif not self.sortFlip then
        self.sortFlip = true
    else
        self.sortKey, self.sortFlip = nil, false
    end
    self.dungeonOffset = 0
    self:PaintDungeons()
end

function Dungeons:ScrollDungeons(steps)
    local total = self.sorted and #self.sorted or 0
    local before = self.dungeonOffset or 0
    self.dungeonOffset = math.max(0, math.min(before + steps, math.max(0, total - 1)))
    if self.dungeonOffset ~= before then self:PaintDungeons() end
end

function Dungeons:Scroll(steps)
    local total = self.lines and #self.lines or 0
    local before = self.offset or 0
    self.offset = math.max(0, math.min(before + steps, math.max(0, total - 1)))
    if self.offset ~= before then self:PaintLines(true) end
end

--- A click on a drop: the game's own Shift and Ctrl clicks first, else
--- the menu the upgrade lists give it (make it the quest, track it). A
--- drop the finder holds no line for has nothing to offer.
function Dungeons:ClickLine(line)
    if not line or line.kind ~= "drop" then return end
    if Widgets.ItemClick(line.itemID, line.link) then return end
    local pick = Dungeons.PickFor(line.itemID)
    local FinderUI = ns.FinderUI
    if not (pick and ns.RowMenu and FinderUI and FinderUI.PickMenu) then return end
    local lines = FinderUI.PickMenu(pick)
    if #lines == 0 then return end
    GameTooltip:Hide()
    local title = line.name ~= "" and line.name or nil
    return ns.RowMenu:Open(lines, { title = title })
end

--------------------------------------------------------------------------------
-- Looking
--------------------------------------------------------------------------------

function Dungeons:IsShown()
    local page = self.page
    if not Shown(page) then return false end
    local ok, visible = pcall(page.IsVisible, page)
    if ok and type(visible) == "boolean" then return visible end
    return true
end

--- Take the finder's scan when it is up to date, else ask for the shared
--- one (it rests in a fight) and draw what there is meanwhile.
function Dungeons:Refresh()
    if not self:IsShown() then return nil end
    local Finder = ns.Finder
    local found = Finder:Fresh()
    if found then
        self:Present(found)
        return true
    end
    self:Present(Finder.latest)
    Finder:ScanInBackground(function(scan)
        if not Dungeons:IsShown() then return end
        Dungeons:Present(scan)
        if Finder.stale and not Finder.background then Dungeons:RefreshSoon() end
    end)
    return false
end

--- Once for a burst of events, and only while the page shows.
function Dungeons:RefreshSoon()
    if not self:IsShown() or self.pending then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then return self:Refresh() end
    self.pending = true
    after(0.5, function()
        Dungeons.pending = false
        Dungeons:Refresh()
    end)
end

--- Items the client sent, a quest's name, a tracked mark: draw again, with
--- nothing read anew but the dungeon picked.
function Dungeons:RedrawSoon()
    if not self:IsShown() or self.redraw or not self.read then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then return self:Draw() end
    self.redraw = true
    after(0.3, function()
        Dungeons.redraw = false
        if Dungeons:IsShown() then Dungeons:Draw() end
    end)
end

--- Quests done, taken or hidden changed (Logic/DungeonQuests.lua).
function Dungeons:OnDungeonQuestsChanged()
    if not self:IsShown() then return end
    self:Present(ns.Finder.latest)
end

function Dungeons:OnTrackingChanged() self:RedrawSoon() end
function Dungeons:OnUpgradeQuestChanged() self:RedrawSoon() end

function Dungeons:Show()
    if not self.page then return end
    self.page:Show()
    self:Refresh()
end

function Dungeons:Hide()
    if self.page then self.page:Hide() end
end

--- Open the Equipment window on this tab.
function Dungeons:Open()
    if ns.GearWindow then ns.GearWindow:Open(Dungeons.KEY) end
end

function Dungeons:OnEnable()
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN" }) do
        ns.RegisterEvent(self, event, function() Dungeons:RefreshSoon() end)
    end
    ns.RegisterEvent(self, "GET_ITEM_INFO_RECEIVED", function() Dungeons:RedrawSoon() end)
end

if ns.GearWindow then ns.GearWindow:AddPage(Dungeons.KEY, Dungeons) end
