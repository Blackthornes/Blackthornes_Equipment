-- Blackthornes Equipment -- UI/Widgets.lua
-- The controls the settings page needs: a button, a checkbox, a stepper and a
-- search box, with the small tweens that make them feel alive. Farmer's
-- Widgets.lua, trimmed to those, so the pages feel the same under the mouse.

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

local Theme = ns.Theme

--------------------------------------------------------------------------------
-- Motion
--
-- Small tweens for the windows and controls: a button easing into its hover
-- colour, a window fading up as it opens. Off means every tween lands at its
-- end at once.
--
-- One OnUpdate on one small frame, shown only while something is moving, so
-- an idle window costs nothing per frame. A tween that errors is dropped
-- rather than raised: a hover colour must never break a click.
--------------------------------------------------------------------------------

local Motion = {}
ns.Motion = Motion

Motion.tweens = {}

--- The Effects setting: Full, Subtle or Off, from most movement to none.
--- Full until the player picks another, so nobody's windows change.
Motion.LEVELS = { "full", "subtle", "off" }

--- "full", "subtle" or "off", as the player picked it.
function Motion.Level()
    local level = ns.db and ns.db.effectsLevel
    if level == "subtle" or level == "off" then return level end
    return "full"
end

function Motion.SetLevel(level)
    if not ns.db then return end
    ns.db.effectsLevel = (level == "subtle" or level == "off") and level or nil
end

function Motion.EaseOut(p)
    return 1 - (1 - p) ^ 3
end

--- Overshoots a touch and settles, for things that should feel like they
--- landed.
function Motion.EaseOutBack(p)
    local c = 1.4
    return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

function Motion.Lerp(from, to, p)
    return from + (to - from) * p
end

--- Two colours mixed, `p` of the way from `a` to `b`. Each is a palette key
--- or an { r, g, b[, a] } table.
function Motion.Mix(a, b, p, alphaA, alphaB)
    local r1, g1, b1, a1
    if type(a) == "table" then r1, g1, b1, a1 = a[1], a[2], a[3], alphaA or a[4] or 1
    else r1, g1, b1, a1 = Theme.Unpack(a, alphaA) end

    local r2, g2, b2, a2
    if type(b) == "table" then r2, g2, b2, a2 = b[1], b[2], b[3], alphaB or b[4] or 1
    else r2, g2, b2, a2 = Theme.Unpack(b, alphaB) end

    return r1 + (r2 - r1) * p, g1 + (g2 - g1) * p, b1 + (b2 - b1) * p, a1 + (a2 - a1) * p
end

function Motion:Driver()
    if self.driver then return self.driver end

    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) Motion:Step(elapsed) end)
    driver:Hide()

    self.driver = driver
    return driver
end

local function Finish(tween)
    pcall(tween.apply, 1)
    if tween.done then pcall(tween.done) end
end

--- Run `apply(p)` with p going 0 to 1 over `duration` seconds.
--
-- `owner` and `slot` name the tween: a new one for the same owner and slot
-- replaces the old, so hovering on and off quickly never leaves two fighting.
-- opts: delay (seconds before it starts), done (called at the end), ease
-- (a function of p; EaseOut unless given, false for linear).
function Motion:Run(owner, slot, duration, apply, opts)
    opts = opts or {}

    self:Stop(owner, slot)

    local tween = { owner = owner, slot = slot, duration = duration or 0.2,
        apply = apply, done = opts.done, age = -(opts.delay or 0) }

    local ease = opts.ease
    if ease == nil then ease = Motion.EaseOut end
    tween.ease = ease or nil

    if self.Level() == "off" or tween.duration <= 0 then
        Finish(tween)
        return
    end

    -- Drawn at its start now, so nothing flashes at its end for a frame
    -- before the first step.
    pcall(apply, 0)

    self.tweens[#self.tweens + 1] = tween
    self:Driver():Show()
end

--- Stop a running tween where it is. `finish` lands it at its end first.
function Motion:Stop(owner, slot, finish)
    for index = #self.tweens, 1, -1 do
        local tween = self.tweens[index]
        if tween.owner == owner and (slot == nil or tween.slot == slot) then
            table.remove(self.tweens, index)
            if finish then Finish(tween) end
        end
    end
end

--- Whether a tween is running for this owner (and slot, when given).
function Motion:Running(owner, slot)
    for _, tween in ipairs(self.tweens) do
        if tween.owner == owner and (slot == nil or tween.slot == slot) then return true end
    end
    return false
end

--- Land every running tween at its end. For the tests, and for a window
--- being hidden mid-animation.
function Motion:FinishAll()
    local tweens = self.tweens
    self.tweens = {}
    for _, tween in ipairs(tweens) do Finish(tween) end
    if self.driver then self.driver:Hide() end
end

function Motion:Step(elapsed)
    elapsed = tonumber(elapsed) or 0

    local live = {}
    local tweens = self.tweens
    self.tweens = live

    for _, tween in ipairs(tweens) do
        tween.age = tween.age + elapsed

        if tween.age >= 0 then
            local p = math.min(1, tween.age / tween.duration)
            local eased = tween.ease and tween.ease(p) or p
            local ok = pcall(tween.apply, eased)

            if not ok or p >= 1 then
                if ok and tween.done then pcall(tween.done) end
            else
                live[#live + 1] = tween
            end
        else
            live[#live + 1] = tween
        end
    end

    -- Tweens started from inside an apply or done landed in `live` already.
    if #self.tweens == 0 and self.driver then self.driver:Hide() end
end

--- Ease a number kept on `owner` toward `target`, calling `apply(value)` as
--- it goes. Starts from wherever the last one left it, so a hover that is
--- undone halfway turns round smoothly instead of jumping.
function Motion:Blend(owner, slot, target, duration, apply)
    local from = self:Value(owner, slot)
    if from == target and not self:Running(owner, slot) then
        apply(target)
        return
    end

    self:Run(owner, slot, duration, function(p)
        local value = from + (target - from) * p
        self:SetValue(owner, slot, value)
        apply(value)
    end, { ease = false })
end

-- Blended values, kept here rather than as fields on the frames so they never
-- collide with a frame's own keys.
Motion.values = setmetatable({}, { __mode = "k" })

--- Where Blend last left `owner`'s `slot`: 0 until it has moved.
function Motion:Value(owner, slot)
    local values = self.values[owner]
    return values and values[slot] or 0
end

function Motion:SetValue(owner, slot, value)
    local values = self.values[owner]
    if not values then
        values = {}
        self.values[owner] = values
    end
    values[slot] = value
end

--- Fade a window up as it opens: from clear, and a few pixels low.
--
-- Only the alpha and one point's offset move, so the window's saved spot is
-- never touched: the last step puts back exactly the point it started with.
function Motion:Open(frame, rise)
    if not frame then return end

    -- Opened again before the last opening finished: land that one first,
    -- which puts its point back, or the window would start from the
    -- lowered spot and settle a few pixels further down every time.
    self:Stop(frame, "open", true)

    -- A window with the house glow round it flares as it opens.
    local rest = frame.haloTextures and frame.haloRest
    if rest then
        self:Run(frame, "halo", 0.7, function(p)
            Theme.SetHalo(frame, rest * 3.2 + (rest - rest * 3.2) * p)
        end)
    end

    local level = self.Level()
    if level == "off" then
        frame:SetAlpha(1)
        return
    end

    rise = level == "full" and (rise or 8) or 0

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local canMove = rise ~= 0 and point ~= nil and type(x) == "number" and type(y) == "number"

    self:Run(frame, "open", level == "full" and 0.2 or 0.12, function(p)
        frame:SetAlpha(p)
        if canMove then
            frame:SetPoint(point, relativeTo, relativePoint, x, y - rise * (1 - p))
        end
    end)
end

--------------------------------------------------------------------------------
-- Row light (Farmer's)
--------------------------------------------------------------------------------

--- The house hover for a list row: a lighter glass, a gold edge down its
--- left and a soft gold wash from the left, only under the mouse. Unlit
--- until Widgets.SetRowLight lights it.
function Widgets.RowLight(row)
    -- Filled at full strength and hidden with SetAlpha: a texture whose
    -- colour is clear stays clear whatever alpha it is given later.
    row.highlight = Theme.Fill(row, "glassHover", nil, "BORDER")
    row.highlight:SetAlpha(0)

    row.edge = row:CreateTexture(nil, "OVERLAY")
    row.edge:SetPoint("TOPLEFT")
    row.edge:SetPoint("BOTTOMLEFT")
    row.edge:SetWidth(2)
    row.edge:SetColorTexture(Theme.Unpack("accentHi"))
    row.edge:SetAlpha(0)

    -- Both gold lights hide at rest and are lit by Theme.LightGradient:
    -- faded with SetAlpha alone they stayed on every row in game.
    row.lightWash = row:CreateTexture(nil, "BORDER", nil, 1)
    row.lightWash:SetAllPoints(row)
    row.lightWash:Hide()

    row.bleed = row:CreateTexture(nil, "BORDER", nil, 1)
    row.bleed:SetPoint("TOPLEFT", 2, 0)
    row.bleed:SetPoint("BOTTOMLEFT", 2, 0)
    row.bleed:SetWidth(18)
    pcall(row.bleed.SetBlendMode, row.bleed, "ADD")
    row.bleed:Hide()
end

--- How lit a row from Widgets.RowLight is: 0 at rest, 1 under the mouse.
function Widgets.SetRowLight(row, value)
    row.highlight:SetAlpha(value)
    row.edge:SetAlpha(value)
    Theme.LightGradient(row.bleed, "HORIZONTAL", "accent", 0.18, 0, value)
    Theme.LightGradient(row.lightWash, "HORIZONTAL", "accent", 0.10, 0, value)
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

local HOVER_TIME = 0.12

--- A button in the house style.
--
-- opts: width, height; primary (solid gold with dark lettering, for the one
-- button on a screen that does the main thing); danger (lights red under
-- the mouse, for a close button); labelKey (the label's resting colour);
-- baseColor (an explicit { r, g, b, a } resting face, for a button that sits
-- over the game world and keeps to its own look).
function Widgets.CreateButton(parent, text, onClick, opts)
    opts = opts or {}

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(opts.width or 80, opts.height or 22)

    -- Titanforged (2026-10-04): every button is raised metal, a dark face
    -- in a gold edge with a gold label, lit and glowing under the mouse. The
    -- primary action is solid gold with dark lettering, so the one button
    -- that does the main thing on a screen stands out at a glance.
    --
    -- Dark lettering only on a gold face: a primary button given its own
    -- dark face (opts.baseColor) keeps the gold label, or its text would be
    -- dark on dark and the button would read as an empty box.
    -- The Blizzard window style has no gold face: every button wears the
    -- game's red with a gold label (UI/BlizzardLook.lua). A client missing
    -- that art keeps the house face, so the label is picked to suit it.
    local Look = ns.BlizzardLook
    local blizzard = Look and Look.DressesButtons()
    local goldFace = opts.primary and not opts.baseColor and not blizzard
    local baseKey = opts.baseColor or (goldFace and "accent") or "row"
    local hotFill = opts.baseColor and "rowHover" or goldFace and "accentHi"
        or opts.danger and "rowHover" or "rowActive"
    local edgeKey = goldFace and "accentHi" or "metal"
    local hotEdge = (opts.danger and "loss") or "accentHi"
    local labelKey = goldFace and "ink" or opts.labelKey or "gilt"
    local labelHot = goldFace and "ink" or opts.danger and "loss" or { 1, 0.953, 0.784 }

    -- Painted by Light below, from baseKey.
    button.background = Theme.Fill(button, "row")
    Theme.Border(button, edgeKey)
    button.sheen = Theme.TopSheen(button, 0.10)
    if Theme.Bevel then button.bevel = { Theme.Bevel(button) } end
    -- Kept so the Blizzard style leaves a button over the game world alone.
    button.baseColor = opts.baseColor

    -- Every button glows round its edge under the mouse; the primary one
    -- glows a little even at rest. One with its own face keeps to its look.
    local haloRest = goldFace and 0.12 or 0
    if Theme.Halo and not opts.baseColor then
        Theme.Halo(button, 5, haloRest, opts.danger and "loss" or "accent")
    end

    button.label = Theme.CreateLabel(button, "small", labelKey, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(text)

    -- Never narrower than its text: the game's font runs wider than a width
    -- picked by eye.
    local function Fit(value)
        button:SetWidth(math.max(opts.width or 80, Theme.TextWidth("small", value) + 12))
    end
    Fit(text)

    --- How lit the button is: 0 at rest, 1 under the mouse. The face, the
    --- edge, the label and the glow are all drawn from this one number.
    local function Light(p)
        button.background:SetColorTexture(Motion.Mix(baseKey, hotFill, p))

        local r, g, b, a = Motion.Mix(edgeKey, hotEdge, p)
        for _, edge in ipairs(button.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, a)
        end

        -- A dimmed label (a stepper at the end of its range) stays dim.
        if rawget(button, "dimmed") == true then
            button.label:SetTextColor(Theme.Unpack("dim"))
        else
            button.label:SetTextColor(Motion.Mix(labelKey, labelHot, p))
        end
        if rawget(button, "haloTextures") then
            Theme.SetHalo(button, haloRest + (0.4 - haloRest) * p)
        end
    end
    button.Light = Light

    button:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, HOVER_TIME, Light)
    end)

    button:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, HOVER_TIME * 1.5, Light)
    end)

    -- The label dips a pixel while held, so a click feels pressed. Wherever
    -- the label was put (a caller may have moved it beside an icon), it
    -- goes back to exactly there.
    button:SetScript("OnMouseDown", function(self)
        -- Held, for the Blizzard style's pressed art.
        self.held = true
        local point, relativeTo, relativePoint, x, y = self.label:GetPoint(1)
        if not (point and type(x) == "number" and type(y) == "number") then return end

        self.restPoint = { point, relativeTo, relativePoint, x, y }
        self.label:SetPoint(point, relativeTo, relativePoint, x, y - 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self.held = nil
        local rest = rawget(self, "restPoint")
        if not rest then return end

        self.restPoint = nil
        self.label:SetPoint(rest[1], rest[2], rest[3], rest[4], rest[5])
    end)

    if onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            onClick(self, mouseButton)
        end)
    end

    function button:SetText(value)
        self.label:SetText(value)
        Fit(value)
    end

    --- The label's resting colour, for a button whose text means something
    --- (an upgrade in green, say). A gold face keeps its dark lettering.
    function button:SetLabelColor(key)
        if not goldFace then labelKey = key end
        Light(Motion:Value(self, "hover"))
    end

    --- Grey the label out (true) or bring it back, as a stepper's - and +
    --- do at the ends of their range. The button still takes clicks.
    function button:SetDimmed(dimmed)
        self.dimmed = dimmed and true or false
        Light(Motion:Value(self, "hover"))
    end

    Light(0)
    if blizzard then Look.Button(button) end
    return button
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

--- A square toggle with its label beside it. Ported from the tradeskills addon
--- so the two settings pages feel the same under the mouse.
function Widgets.CreateCheckbox(parent, text, onToggle, initial)
    local checkbox = CreateFrame("Button", nil, parent)
    checkbox:SetHeight(18)

    local box = CreateFrame("Frame", nil, checkbox)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    -- A small dark well in a gold edge, glowing when ticked (Titanforged).
    box.background = Theme.Fill(box, "well")
    Theme.Border(box, "metal")
    Theme.Halo(box, 4, 0)

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("CENTER")
    tick:SetSize(8, 8)
    tick:SetColorTexture(Theme.Unpack("accent"))

    local function PaintBox(hovered)
        tick:SetShown(checkbox.checked)
        tick:SetColorTexture(Theme.Unpack(checkbox.checked and "accentHi" or "accent"))
        Theme.SetBorderColor(box, checkbox.checked and "accentHi"
            or hovered and "accent" or "metal")
        if rawget(box, "haloTextures") then
            Theme.SetHalo(box, checkbox.checked and 0.3 or hovered and 0.15 or 0)
        end
    end

    local label = Theme.CreateLabel(checkbox, "small", "text")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(text)

    checkbox.label = label
    checkbox:SetWidth((label:GetStringWidth() or 60) + 24)
    checkbox.checked = initial and true or false
    checkbox.disabled = false
    PaintBox(false)

    function checkbox:SetChecked(value)
        self.checked = value and true or false
        PaintBox(rawget(self, "hovered") == true)
    end

    function checkbox:GetChecked()
        return self.checked
    end

    --- A disabled box keeps showing its state but ignores clicks, for a
    --- setting this client cannot honour.
    function checkbox:SetDisabled(disabled)
        self.disabled = disabled and true or false
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        -- In the Blizzard style the house tick stays out of sight.
        if not rawget(self, "blizzard") then tick:SetAlpha(self.disabled and 0.4 or 1) end
    end

    checkbox:SetScript("OnClick", function(self)
        if self.disabled then return end
        self:SetChecked(not self.checked)

        -- Ticking pops the mark in from small, a touch past size and back.
        if self.checked then
            Motion:Run(self, "tick", 0.22, function(p)
                local size = math.max(1, 8 * p)
                tick:SetSize(size, size)
            end, { ease = Motion.EaseOutBack })
        end

        if onToggle then onToggle(self.checked) end
    end)

    checkbox:SetScript("OnEnter", function(self)
        if not self.disabled then
            self.hovered = true
            label:SetTextColor(Theme.Unpack("accent"))
            PaintBox(true)
        end
    end)

    checkbox:SetScript("OnLeave", function(self)
        self.hovered = false
        label:SetTextColor(Theme.Unpack(self.disabled and "dim" or "text"))
        PaintBox(false)
    end)

    -- The Blizzard window style's box and tick (UI/BlizzardLook.lua).
    if ns.BlizzardLook and ns.BlizzardLook.Checkbox(checkbox, box, tick) then
        checkbox.blizzard = true
    end

    return checkbox
end

--------------------------------------------------------------------------------
-- Stepper
--------------------------------------------------------------------------------

--- [-] value [+], for a number with a small sensible range such as a scale.
--
-- Chosen over a slider: a slider on this client needs a thumb texture and a
-- drag to land on a round number, and a stepper only ever holds values from
-- its own list of steps.
--
-- @param opts
--   min, max, step  the range, in the stored unit
--   format          function(value) -> text shown between the buttons
--   onChange        function(value)
function Widgets.CreateStepper(parent, opts)
    opts = opts or {}

    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(118, 20)

    local minus = Widgets.CreateButton(stepper, "-", nil, { width = 22, height = 20 })
    minus:SetPoint("LEFT")

    local plus = Widgets.CreateButton(stepper, "+", nil, { width = 22, height = 20 })
    plus:SetPoint("RIGHT")

    -- The value sits sunk into the window between the two buttons.
    local well = Theme.CreatePanel(stepper, "panel", "border")
    well:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    well:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    well:SetHeight(20)
    Theme.Recess(well)

    local text = Theme.CreateLabel(well, "small", "text", "CENTER")
    text:SetPoint("CENTER")

    stepper.minus = minus
    stepper.plus = plus
    stepper.text = text

    local step = opts.step or 1
    local low = opts.min or 0
    local high = opts.max or 100

    local function Clamp(value)
        -- Snapped to a whole number of steps, so repeated presses never drift
        -- to 0.8999999 and show a value that is not on the list.
        value = low + math.floor((value - low) / step + 0.5) * step
        return math.max(low, math.min(high, value))
    end

    function stepper:SetValue(value, silent)
        self.value = Clamp(tonumber(value) or low)
        text:SetText(opts.format and opts.format(self.value) or tostring(self.value))

        minus:SetDimmed(self.value <= low)
        plus:SetDimmed(self.value >= high)

        if not silent and opts.onChange then opts.onChange(self.value) end
    end

    function stepper:GetValue()
        return self.value
    end

    local function Nudge(direction)
        local wanted = Clamp((stepper.value or low) + direction * step)
        if wanted ~= stepper.value then stepper:SetValue(wanted) end
    end

    minus:SetScript("OnClick", function() Nudge(-1) end)
    plus:SetScript("OnClick", function() Nudge(1) end)

    stepper:SetValue(opts.value or low, true)
    return stepper
end

--------------------------------------------------------------------------------
-- Search box
--
-- Farmer's (by way of Pets), for Settings' Find a setting.
--------------------------------------------------------------------------------

--- Whether the mouse is on `frame` and the frame is on screen. Read in a
--- pcall, as every client value is; a client that cannot say answers no.
local function UnderMouse(frame)
    local ok, over = pcall(function() return frame:IsVisible() and frame:IsMouseOver() end)
    return ok and over and true or false
end

--- An edit box with placeholder text.
--
-- onChange fires on every keystroke so results follow typing; onAccept fires on
-- Enter. Escape clears focus rather than the text, because losing what you
-- typed on a mis-key is worse than an extra keystroke.
--
-- opts.plain leaves out the magnifier and the clear button, for a small box
-- that is not a search: the room they keep is most of a narrow box.
function Widgets.CreateSearchBox(parent, placeholder, onChange, onAccept, opts)
    opts = opts or {}
    local inset = opts.plain and 6 or 26

    local holder = Theme.CreatePanel(parent, "row", "border")
    holder:SetHeight(24)

    -- Sunk into the window, and glowing gold while it has the keyboard
    -- (Titanforged, as Tradeskills' search box).
    if Theme.Recess then Theme.Recess(holder) end
    if Theme.Halo then Theme.Halo(holder, 6, 0) end

    -- The game's own magnifier, so the box reads as search at a glance.
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture([[Interface\Common\UI-Searchbox-Icon]])
    icon:SetVertexColor(Theme.Unpack("muted"))
    icon:SetShown(not opts.plain)
    holder.icon = icon

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", inset, 0)
    box:SetPoint("BOTTOMRIGHT", -inset, 0)
    box:SetAutoFocus(false)
    box:SetFont(Theme.FONT, Theme.sizes.normal, "")
    box:SetTextColor(Theme.Unpack("text"))
    box:SetMaxLetters(80)

    local hint = Theme.CreateLabel(holder, "normal", "dim")
    hint:SetPoint("LEFT", inset, 0)
    hint:SetText(placeholder or "")

    -- Clears what you typed in one click, and only shows when there is
    -- something to clear.
    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", -3, 0)
    local cross = Theme.CreateLabel(clear, "normal", "muted", "CENTER")
    cross:SetPoint("CENTER", 0, 0)
    cross:SetText("x")
    clear:Hide()
    holder.clear = clear

    local function UpdateHint()
        local empty = box:GetText() == ""
        hint:SetShown(empty)
        clear:SetShown(not empty and not opts.plain)
    end

    --- The edge and the magnifier, from how far the mouse and the keyboard
    --- have each eased in: the edge lifts under the mouse and turns gold
    --- while the box has the keyboard, and the keyboard's gold wins.
    local function Paint()
        local hover = Motion:Value(holder, "hover")
        local focus = Motion:Value(holder, "focus")

        local r1, g1, b1 = Motion.Mix("border", "borderLit", hover)
        local r2, g2, b2 = Theme.Unpack("accent")
        local r, g, b = r1 + (r2 - r1) * focus, g1 + (g2 - g1) * focus, b1 + (b2 - b1) * focus
        for _, edge in ipairs(holder.borderTextures or {}) do
            edge:SetColorTexture(r, g, b, 1 - 0.2 * focus)
        end
        if rawget(holder, "haloTextures") then Theme.SetHalo(holder, 0.3 * focus) end

        icon:SetVertexColor(Motion.Mix("muted", "accent", math.max(focus, hover * 0.4)))
    end

    --- The mouse came onto part of the box or left it. Lit while it is
    --- anywhere on the box: going from the margin onto the text, or onto
    --- the x, is a leave and an enter of their own.
    local function Hover()
        local over = UnderMouse(holder)
        Motion:Blend(holder, "hover", over and 1 or 0, over and 0.12 or 0.18, Paint)
    end

    holder:EnableMouse(true)
    holder:SetScript("OnEnter", Hover)
    holder:SetScript("OnLeave", Hover)
    box:SetScript("OnEnter", Hover)
    box:SetScript("OnLeave", Hover)
    -- The margin answers the mouse now, so a click there (on the
    -- magnifier, say) gives the box the keyboard rather than nothing.
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)

    -- The x lifts to the text colour under the mouse, eased like the rest.
    local function LightCross(p)
        cross:SetTextColor(Motion.Mix("muted", "text", p))
    end
    clear:SetScript("OnEnter", function(self)
        Motion:Blend(self, "hover", 1, 0.12, LightCross)
        Hover()
    end)
    clear:SetScript("OnLeave", function(self)
        Motion:Blend(self, "hover", 0, 0.18, LightCross)
        Hover()
    end)

    -- Hidden under the mouse (its window closing, or the x going with the
    -- text it cleared), no leave may come: let go, or it shows again lit.
    local function LetGo(frame, apply)
        Motion:Stop(frame, "hover")
        Motion:SetValue(frame, "hover", 0)
        apply(0)
    end
    holder:SetScript("OnHide", function() LetGo(holder, Paint) end)
    clear:SetScript("OnHide", function() LetGo(clear, LightCross) end)

    box:SetScript("OnEditFocusGained", function()
        Motion:Blend(holder, "focus", 1, 0.15, Paint)
    end)

    box:SetScript("OnEditFocusLost", function()
        Motion:Blend(holder, "focus", 0, 0.2, Paint)
    end)

    box:SetScript("OnTextChanged", function(self, userInput)
        UpdateHint()
        if userInput and onChange then
            onChange(self:GetText())
        end
    end)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onAccept then onAccept(self:GetText()) end
    end)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    clear:SetScript("OnClick", function()
        box:SetText("")
        UpdateHint()
        if onChange then onChange("") end
        box:SetFocus()
    end)

    holder.editBox = box

    function holder:SetText(value)
        box:SetText(value or "")
        UpdateHint()
    end

    function holder:GetText()
        return box:GetText()
    end

    function holder:SetFocus()
        box:SetFocus()
    end

    function holder:ClearFocus()
        box:ClearFocus()
    end

    UpdateHint()
    return holder
end

--------------------------------------------------------------------------------
-- Size grip
--
-- The house size grip, brought over from Farmer's Widgets.lua (the owner,
-- 2026-10-11: every window gets one): a small square
-- with a gold edge and six gold dots in a stair, hung outside a window's
-- bottom right corner. Drag it and the whole window grows or shrinks from its
-- top left corner, text and all; right-click it for the normal size. Only the
-- window's scale moves while dragging, so nothing is filled or laid out
-- again and no line is cut that was whole before. The size is saved, in
-- percent, when the drag ends.
--------------------------------------------------------------------------------

Widgets.SIZE_MIN, Widgets.SIZE_MAX = 50, 150
Widgets.SIZE_GRIP = 20

--- A size in percent, kept within bounds and whole; 100 for nothing.
function Widgets.ClampSize(value, low, high)
    value = tonumber(value)
    if not value or value ~= value then return 100 end
    low, high = low or Widgets.SIZE_MIN, high or Widgets.SIZE_MAX
    return math.floor(math.max(low, math.min(high, value)) + 0.5)
end

function Widgets.SizeText(percent)
    return ("%d%%"):format(math.floor((tonumber(percent) or 100) + 0.5))
end

--- A frame's own scale, or 1 when it cannot say.
local function ScaleOf(frame)
    local ok, scale = pcall(function() return frame:GetScale() end)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

--- The largest size, in percent, at which `frame` (its trim and the grip
--- included) fits on the screen. Never under 100: a window that was taller
--- than the screen at its normal size is still drawn that way.
function Widgets.FitSize(frame, high)
    high = high or Widgets.SIZE_MAX
    local ok, width, height, wide, tall = pcall(function()
        return UIParent:GetWidth(), UIParent:GetHeight(), frame:GetWidth(), frame:GetHeight()
    end)
    if not (ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0
        and type(wide) == "number" and wide > 0 and type(tall) == "number" and tall > 0) then
        return high
    end
    local fit = math.min(width / (wide + 40), height / (tall + 60))
    return math.max(100, math.min(high, math.floor(fit * 100)))
end

--- Draw `frame` at a saved size, kept on the screen.
function Widgets.ApplySize(frame, percent, low, high)
    if not frame then return end
    local size = math.min(Widgets.ClampSize(percent, low, high), Widgets.FitSize(frame, high))
    pcall(frame.SetScale, frame, size / 100)
end

--- The grip. `opts`:
---   get()            the saved size in percent (nil means 100)
---   save(percent)    keep a new size, account wide
---   min, max         bounds in percent (50 and 150 unless given)
---   below            how far the window's trim hangs under its bottom edge
---   beside           hang to the right of the corner instead of under it
---   onStart()        before a drag (hide what sits outside the window)
---   done(percent)    after a drag or a right-click: save the window's spot,
---                    put back what was hidden, dock it again
---   name             "window" or "panel", for the tooltip
-- The grip's tooltip, whole for each window kind so a translation can put
-- its own article and word order round the noun.
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
local GRIP_TIPS = {
    window = L["Drag to make the window bigger or smaller."],
    panel = L["Drag to make the panel bigger or smaller."],
}

function Widgets.CreateSizeGrip(frame, opts)
    opts = opts or {}
    local low, high = opts.min or Widgets.SIZE_MIN, opts.max or Widgets.SIZE_MAX
    local name = opts.name or "window"

    local grip = Theme.CreatePanel(frame, "panel", "borderLit")
    grip:SetSize(Widgets.SIZE_GRIP, Widgets.SIZE_GRIP)
    if opts.beside then
        grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 3, 0)
    else
        grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -6, -((opts.below or 0) + 3))
    end
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:EnableMouse(true)
    if Theme.TopSheen then Theme.TopSheen(grip) end

    -- Six gold dots in a stair down to the bottom right corner, the shape
    -- every resizable window in the game wears, drawn from plain colour.
    local dots = {}
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
            dots[#dots + 1] = dot
        end
    end
    grip.dots = dots

    local function Light(on)
        Theme.SetBorderColor(grip, on and "accent" or "borderLit")
        for _, dot in ipairs(dots) do
            dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent"))
        end
    end

    local function Saved()
        return Widgets.ClampSize(opts.get and opts.get() or 100, low, high)
    end

    --- Put the window at `percent` with its top left corner where it is.
    local function Resize(percent)
        local old = ScaleOf(frame)
        local scale = percent / 100
        local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
        frame:SetScale(scale)
        if ok and type(left) == "number" and type(top) == "number" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        end
    end

    local function Track(self)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (cx and cy and type(uiScale) == "number" and uiScale > 0) then return end
        cx, cy = cx / uiScale, cy / uiScale

        -- The size that keeps the cursor where it took hold of the grip:
        -- the width's and the height's answers averaged, so a drag off the
        -- diagonal still feels right. Only the scale moves, and only when
        -- it moved a whole percent.
        local width = cx - self.grabX - self.anchorLeft
        local height = self.anchorTop - (cy + self.grabY)
        local percent = Widgets.ClampSize((width / self.wide + height / self.tall) / 2 * 100, low, high)
        percent = math.min(percent, self.fit)
        local scale = percent / 100
        if math.abs(scale - ScaleOf(frame)) < 0.005 then return end

        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.anchorLeft / scale, self.anchorTop / scale)

        if GameTooltip:IsOwned(self) then
            GameTooltip:SetText(Widgets.SizeText(percent), Theme.Unpack("accentHi"))
            GameTooltip:Show()
        end
    end

    local function StopSizing(self)
        if not self.sizing then return end
        self.sizing = false
        self:SetScript("OnUpdate", nil)
        local percent = Widgets.ClampSize(ScaleOf(frame) * 100, low, high)
        if opts.save then opts.save(percent) end
        if opts.done then opts.done(percent) end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            Resize(100)
            if opts.save then opts.save(100) end
            if opts.done then opts.done(100) end
            return
        end
        if button ~= "LeftButton" then return end

        if ns.Motion and ns.Motion.Stop then pcall(ns.Motion.Stop, ns.Motion, frame, "open", true) end

        local scale = ScaleOf(frame)
        local ok, left, top, wide, tall = pcall(function()
            return frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight()
        end)
        local cx, cy = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        if not (ok and type(left) == "number" and type(top) == "number"
            and type(wide) == "number" and wide > 0 and type(tall) == "number" and tall > 0
            and cx and cy and type(uiScale) == "number" and uiScale > 0) then
            return
        end

        -- All in the screen's units, which do not change with the window's.
        self.wide, self.tall = wide, tall
        self.anchorLeft, self.anchorTop = left * scale, top * scale
        self.grabX = cx / uiScale - (self.anchorLeft + wide * scale)
        self.grabY = (self.anchorTop - tall * scale) - cy / uiScale
        self.fit = Widgets.FitSize(frame, high)

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

        if opts.onStart then opts.onStart() end
        self.sizing = true
        self:SetScript("OnUpdate", Track)
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)

    grip:SetScript("OnEnter", function(self)
        Light(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Widgets.SizeText(ScaleOf(frame) * 100), Theme.Unpack("accentHi"))
        GameTooltip:AddLine(GRIP_TIPS[name] or GRIP_TIPS.window, 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to go back to normal size."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        Light(false)
        GameTooltip:Hide()
    end)

    grip.Saved = Saved
    return grip
end

--- The grip on a window dressed in the house frame, its size saved in
--- `ns.db[key]` and drawn at that size now. `done` runs after a drag or a
--- right-click, to save where the window now stands.
function Widgets.WindowGrip(frame, key, done)
    Widgets.ApplySize(frame, ns.db and ns.db[key])
    local trim = rawget(frame, "titan")
    local below = 0
    if trim and ns.Titanforged and ns.Titanforged.Reach then
        local _, _, _, bottom = ns.Titanforged.Reach(trim)
        if type(bottom) == "number" then below = bottom end
    end
    return Widgets.CreateSizeGrip(frame, {
        below = below,
        get = function() return ns.db and ns.db[key] end,
        save = function(percent) if ns.db then ns.db[key] = percent end end,
        done = done,
    })
end
