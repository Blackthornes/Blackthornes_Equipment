-- Blackthornes Equipment -- UI/Theme.lua
-- Palette and panel construction.
--
-- Farmer's Theme.lua, which is Tradeskills' palette: the three addons are worn
-- together and should read as one set. Everything is built from plain
-- textures rather than Blizzard backdrops, which keeps the look consistent and
-- avoids depending on BackdropTemplate being present on this client.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window    = { 0.055, 0.063, 0.078 },   -- #0E1014 outermost shell
    panel     = { 0.086, 0.094, 0.114 },   -- #16181D
    header    = { 0.110, 0.122, 0.145 },
    row       = { 0.133, 0.145, 0.172 },   -- #22252C
    rowAlt    = { 0.106, 0.118, 0.141 },
    rowHover  = { 0.180, 0.200, 0.239 },
    rowActive = { 0.220, 0.190, 0.110 },   -- a gold-tinted row, as in Tradeskills

    border    = { 0.204, 0.224, 0.263 },
    borderLit = { 0.302, 0.333, 0.388 },

    accent    = { 0.784, 0.643, 0.302 },   -- #C8A44D
    good      = { 0.310, 0.820, 0.545 },   -- #4FD18B, an upgrade
    warn      = { 0.910, 0.757, 0.353 },
    loss      = { 0.898, 0.376, 0.310 },   -- #E5604F, a downgrade, or a close button under the mouse
    quest     = { 0.400, 0.690, 1.000 },   -- #66B0FF, a quest reward in the upgrade finder
    dungeon   = { 0.722, 0.522, 1.000 },   -- #B885FF, a dungeon drop in the upgrade finder

    text      = { 0.902, 0.910, 0.925 },   -- #E6E8EC
    muted     = { 0.478, 0.502, 0.541 },   -- #7A8089
    dim       = { 0.330, 0.350, 0.390 },
}

local FONT do
    local ok, path = pcall(function() return (GameFontNormal:GetFont()) end)
    FONT = (ok and path) or [[Fonts\FRIZQT__.TTF]]
end

Theme.FONT = FONT

Theme.sizes = {
    tiny = 10,
    small = 11,
    normal = 12,
    large = 14,
    title = 16,
}

function Theme.Unpack(key, alpha)
    local color = Theme.colors[key] or Theme.colors.text
    return color[1], color[2], color[3], alpha or 1
end

--- Flat filled texture covering a frame.
function Theme.Fill(frame, key, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
    return texture
end

--- One-pixel border drawn as four edge textures, so it stays crisp at any size.
function Theme.Border(frame, key, alpha)
    local r, g, b, a = Theme.Unpack(key or "border", alpha)
    local edges = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(r, g, b, a)

        if side == "TOP" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
        elseif side == "BOTTOM" then
            edge:SetPoint("BOTTOMLEFT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetHeight(1)
        elseif side == "LEFT" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("BOTTOMLEFT")
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetWidth(1)
        end

        edges[#edges + 1] = edge
    end

    frame.borderTextures = edges
    return edges
end

--- Recolour a border drawn by Theme.Border.
function Theme.SetBorderColor(frame, key, alpha)
    if not frame.borderTextures then return end

    local r, g, b, a = Theme.Unpack(key, alpha)
    for _, edge in ipairs(frame.borderTextures) do
        edge:SetColorTexture(r, g, b, a)
    end
end

--- A panel: filled background plus a border.
function Theme.CreatePanel(parent, backgroundKey, borderKey)
    local panel = CreateFrame("Frame", nil, parent)
    panel.background = Theme.Fill(panel, backgroundKey or "panel")

    if borderKey ~= false then
        Theme.Border(panel, borderKey or "border")
    end

    return panel
end

--- A text label.
function Theme.CreateLabel(parent, size, colorKey, justify)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, Theme.sizes[size] or size or Theme.sizes.normal, "")
    label:SetTextColor(Theme.Unpack(colorKey or "text"))
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

-- One unanchored, unbounded label per size, for measuring text: a label
-- anchored at both ends reports the width it was given, not the width its
-- text wants.
local measures = {}

--- How wide `text` is in pixels at a label size, as the game draws it.
--
-- The game's font runs wider than any fixed width we could guess, which is
-- how "Loot a corpse and it shows up he..." happened. Measure instead.
function Theme.TextWidth(size, text)
    if type(text) ~= "string" or text == "" then return 0 end

    local label = measures[size]
    if not label then
        label = Theme.CreateLabel(UIParent, size, "text")
        label:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -200)
        label:SetAlpha(0)
        measures[size] = label
    end

    -- Colour codes take no room on screen.
    label:SetText((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))

    -- The unbounded width where the client has it, else the plain one.
    local width
    for _, method in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
        if not width and type(label[method]) == "function" then
            local ok, value = pcall(label[method], label)
            width = ok and tonumber(value) or nil
        end
    end

    return math.ceil(width or 0)
end

function Theme.CreateDivider(parent, key)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Theme.Unpack(key or "border"))
    divider:SetHeight(1)
    return divider
end

--------------------------------------------------------------------------------
-- House trim, shared with Blackthornes Tradeskills and Farmer
--
-- The same few touches their Theme.lua draws, so the windows read as one set:
-- a gold stripe down the left of a header and a faint sheen along the top of
-- a raised surface.
--------------------------------------------------------------------------------

--- A gold stripe down the left edge of a header or band.
function Theme.AccentStripe(frame, width, alpha)
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(width or 3)
    stripe:SetColorTexture(Theme.Unpack("accent", alpha))
    return stripe
end

--- A faint lighter line along the top edge, so a flat fill reads as a raised
--- surface rather than a hole.
function Theme.TopSheen(frame, alpha)
    local sheen = frame:CreateTexture(nil, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    sheen:SetColorTexture(1, 1, 1, alpha or 0.05)
    return sheen
end

--- The house header's trim on `header`: the gold stripe down its left, the
--- soft glow and the sheen along its top. Returns the stripe.
function Theme.HouseHeader(header, glowHeight)
    local stripe = Theme.AccentStripe(header, 3)
    Theme.HeaderGlow(header, glowHeight or 16, 0.10)
    Theme.TopSheen(header)
    return stripe
end

--- A soft gold glow fading down from the top of a header, drawn as a
--- gradient where the client has one and left out where it does not.
function Theme.HeaderGlow(frame, height, alpha)
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT")
    glow:SetPoint("TOPRIGHT")
    glow:SetHeight(height or 18)
    glow:SetColorTexture(1, 1, 1, 1)

    local r, g, b = Theme.Unpack("accent")
    local top, bottom = alpha or 0.10, 0

    local ok = false
    if type(CreateColor) == "function" and type(glow.SetGradient) == "function" then
        ok = pcall(glow.SetGradient, glow, "VERTICAL",
            CreateColor(r, g, b, bottom), CreateColor(r, g, b, top))
    end

    if not ok then glow:Hide() end
    return glow
end

--------------------------------------------------------------------------------
-- Glow
--
-- Farmer's neon edge, so the four addons' windows glow the same way.
--------------------------------------------------------------------------------

--- Shade `texture` from one alpha of a palette colour to another, along
--- "VERTICAL" (bottom to top) or "HORIZONTAL" (left to right). Where the
--- client cannot draw a gradient it gets one flat, fainter wash instead.
--- Returns true when the gradient was drawn.
function Theme.SetGradientAlpha(texture, orientation, key, fromAlpha, toAlpha)
    local r, g, b = Theme.Unpack(key or "accent")
    texture:SetColorTexture(1, 1, 1, 1)

    local ok = false
    if type(CreateColor) == "function" and type(texture.SetGradient) == "function" then
        ok = pcall(texture.SetGradient, texture, orientation,
            CreateColor(r, g, b, fromAlpha), CreateColor(r, g, b, toAlpha))
    end

    if not ok then
        texture:SetColorTexture(r, g, b, math.max(fromAlpha, toAlpha) * 0.4)
    end
    return ok
end

--- A soft glow round the outside of a frame, fading out from its edge.
--- Returns the four sides, so a caller can brighten or dim them together
--- with Theme.SetHalo.
function Theme.Halo(frame, spread, alpha, key)
    spread = spread or 6
    local sides = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local halo = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        pcall(halo.SetBlendMode, halo, "ADD")

        if side == "TOP" or side == "BOTTOM" then
            local out = side == "TOP" and 1 or -1
            halo:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, out * spread)
            halo:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, out * spread)
            halo:SetHeight(spread)
        else
            local out = side == "LEFT" and -1 or 1
            halo:SetPoint("TOP" .. side, frame, "TOP" .. side, out * spread, 0)
            halo:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, out * spread, 0)
            halo:SetWidth(spread)
        end

        halo.side = side
        sides[#sides + 1] = halo
    end

    frame.haloTextures = sides
    frame.haloKey = key
    -- Where it settles; Motion:Open flares it from brighter as a window opens.
    frame.haloRest = alpha or 0.12
    Theme.SetHalo(frame, frame.haloRest, key)
    return sides
end

--- Relight a halo drawn by Theme.Halo: `alpha` at the frame's edge, in the
--- palette colour `key` (its own colour, else gold).
function Theme.SetHalo(frame, alpha, key)
    local sides = frame and frame.haloTextures
    if not sides then return end

    key = key or frame.haloKey or "accent"
    alpha = math.max(0, tonumber(alpha) or 0)

    for _, halo in ipairs(sides) do
        -- The bright end sits against the frame.
        if halo.side == "TOP" then
            Theme.SetGradientAlpha(halo, "VERTICAL", key, alpha, 0)
        elseif halo.side == "BOTTOM" then
            Theme.SetGradientAlpha(halo, "VERTICAL", key, 0, alpha)
        elseif halo.side == "LEFT" then
            Theme.SetGradientAlpha(halo, "HORIZONTAL", key, 0, alpha)
        else
            Theme.SetGradientAlpha(halo, "HORIZONTAL", key, alpha, 0)
        end
        halo:SetShown(alpha > 0)
    end
end

--- The house window shell: dark fill, lit border and the gold halo round it.
function Theme.Window(frame)
    Theme.Fill(frame, "window")
    Theme.Border(frame, "borderLit")
    Theme.Halo(frame, 10, 0.14)
end

--------------------------------------------------------------------------------
-- Item icons
--------------------------------------------------------------------------------

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

local function ItemID(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local ok, id = pcall(function() return tonumber(item:match("item:(%d+)")) end)
    return ok and id or nil
end

--- An item's icon texture, or nil while the game has not sent it. Read in a
--- pcall: inside an instance the client can hand back values that raise.
function Theme.ItemIcon(item)
    local id = ItemID(item)
    if not id then return nil end

    local calls = { type(C_Item) == "table" and C_Item.GetItemIconByID or false, _G.GetItemIcon or false }
    for _, fn in ipairs(calls) do
        if type(fn) == "function" then
            local ok, icon = pcall(function()
                local value = fn(id)
                -- A number or a path, copied so a secret value raises here.
                if type(value) == "number" then return value + 0 end
                if type(value) == "string" then return value .. "" end
            end)
            if ok and icon then return icon end
        end
    end
    return nil
end

--- The quality colour of an item (r, g, b), or nil when not known yet.
function Theme.QualityColor(item)
    local id = ItemID(item)
    if not id or not ns.Items then return nil end

    local _, _, quality = ns.Items.Call({ "C_Item.GetItemInfo", "GetItemInfo" }, id)
    local ok, number = pcall(tonumber, quality)
    if not ok or not number then return nil end

    local r, g, b = ns.Items.Call({ "C_Item.GetItemQualityColor", "GetItemQualityColor" }, number)
    local fine = pcall(function() return r + g + b end)
    if fine and type(r) == "number" then return r, g, b end
    return nil
end

--- A square item icon in a thin frame that takes the item's quality colour.
function Theme.CreateItemIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.background = Theme.Fill(holder, "panel")
    Theme.Border(holder, "border")

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    holder.icon = icon

    holder:Hide()
    return holder
end

--- Show an item in an icon made by CreateItemIcon, or hide it for none.
function Theme.SetItemIcon(holder, item)
    if not holder then return end
    if not item then
        holder:Hide()
        return
    end

    holder.icon:SetTexture(Theme.ItemIcon(item) or FALLBACK_ICON)
    local r, g, b = Theme.QualityColor(item)
    if r then
        for _, edge in ipairs(holder.borderTextures or {}) do edge:SetColorTexture(r, g, b, 0.9) end
    else
        Theme.SetBorderColor(holder, "border")
    end
    holder:Show()
end
