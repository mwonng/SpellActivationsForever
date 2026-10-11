-- Settings panel (Options -> AddOns -> SpellActivationsForever) and the /saf slash command.
local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "SpellActivationsForever"
local category
local refreshers = {}
local PAD = 16
local cursorY = -16

local function db() return ns.db end

local function Label(text, template, width)
    local fs = panel:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", PAD, cursorY)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    return fs
end

local function Header(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD, cursorY - 6)
    line:SetPoint("TOPRIGHT", -PAD, cursorY - 6)
    cursorY = cursorY - 14
    Label(text, "GameFontNormalLarge")
    cursorY = cursorY - 26
end

local function Paragraph(text)
    local fs = Label(text, "GameFontHighlight", 600)
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    cursorY = cursorY - fs:GetStringHeight() - 12
end

-- A row of check buttons. get(key) -> checked; set(key, checked). Returns the buttons.
local function CheckRow(items, get, set)
    local x = PAD
    local made = {}
    for _, item in ipairs(items) do
        local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        c:SetSize(26, 26)
        c:SetPoint("TOPLEFT", x, cursorY + 2)
        local l = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", c, "RIGHT", 2, 0)
        l:SetText(item.text)
        c.label = l
        c:SetScript("OnClick", function(self)
            set(item.key, self:GetChecked() and true or false)
            panel.Refresh()
        end)
        if item.tip then
            c:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(item.text)
                GameTooltip:AddLine(item.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", GameTooltip_Hide)
        end
        c.refresh = function() c:SetChecked(get(item.key)) end
        refreshers[#refreshers + 1] = c.refresh
        made[#made + 1] = c
        x = x + 30 + l:GetStringWidth() + 24
    end
    cursorY = cursorY - 32
    return made
end

local function RadioRow(items, key)
    CheckRow(items, function(v) return db()[key] == v end, function(v, on) if on then db()[key] = v ns.EvaluateAll() end end)
end

Label("SpellActivationsForever", "GameFontHighlightLarge")
cursorY = cursorY - 30
Paragraph("Lights up the action buttons of reactive abilities with the game's own spell alert glow:"
    .. " Overpower, Revenge and Execute (warrior), Riposte (rogue), Counterattack and Mongoose Bite (hunter),"
    .. " Exorcism and Hammer of Wrath (paladin), Shadow Bolt with Shadow Trance (warlock)."
    .. " Addons cannot read the combat log in WoW Forever, so the glow follows the server's usable state of"
    .. " the ability, or the dodge/parry/block events the client reports, as chosen below.")

Header("Detection of reactive abilities")
RadioRow({
    { key = "usable", text = "Usable state", tip = "The server marks Overpower, Revenge and the like usable only while their condition holds (the button is dimmed otherwise). Exact, no guessing; the glow goes off when the ability is used." },
    { key = "events", text = "Combat events", tip = "A dodge, parry or block reported for you or your target opens a 5 second window, the way combat-log based addons do on Classic Era. Also counts dodges of your group members' attacks." },
    { key = "both", text = "Either", tip = "Glow when either source says so." },
}, "mode")
CheckRow({
    { key = "noPower", text = "Glow without enough rage/energy/mana", tip = "With the usable state: also glow when the only reason the ability is unusable is missing power." },
    { key = "debug", text = "Debug messages", tip = "Print every state change and combat event to the chat frame." },
}, function(k) return db()[k] end, function(k, on) db()[k] = on ns.EvaluateAll() end)

Header("Abilities")
local spellRowsTop = cursorY
local spellRows = {} -- key -> check button
local noSpells = Label("No reactive abilities known for this class.", "GameFontDisable")

local function BuildSpellRows()
    cursorY = spellRowsTop
    noSpells:SetShown(#ns.tracked == 0)
    for _, c in pairs(spellRows) do c:Hide() c.label:Hide() end
    for _, def in ipairs(ns.tracked) do
        local how = {}
        if def.usable then how[#how + 1] = "usable state" end
        if def.window then how[#how + 1] = (def.window.unit == "target" and "target dodges" or "you dodge/parry/block") end
        if def.health then how[#how + 1] = ("target below %d%% health"):format(def.health.below * 100) end
        if def.aura then how[#how + 1] = "buff on you" end
        if def.creature then how[#how + 1] = "target is " .. table.concat(def.creature, " or ") end
        local text = def.localName .. "  |cff9d9d9d(" .. table.concat(how, ", ") .. ")|r"
        local c = spellRows[def.key]
        if not c then
            c = CheckRow({ { key = def.key, text = text } },
                function(k) return db().spells[k] ~= false end,
                function(k, on) if on then db().spells[k] = nil else db().spells[k] = false end ns.EvaluateAll() end)[1]
            spellRows[def.key] = c
        else
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", PAD, cursorY + 2)
            c.label:SetText(text)
            cursorY = cursorY - 32
        end
        c:Show()
        c.label:Show()
    end
end

function panel.Refresh()
    if not db() then return end
    BuildSpellRows()
    for _, fn in ipairs(refreshers) do fn() end
end
panel:SetScript("OnShow", panel.Refresh)

if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

local function OpenPanel()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

SLASH_SPELLACTIVATIONSFOREVER1 = "/saf"
SLASH_SPELLACTIVATIONSFOREVER2 = "/spellactivations"
SlashCmdList.SPELLACTIVATIONSFOREVER = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local d = db()
    if cmd == "" then
        OpenPanel()
    elseif cmd == "mode" and (arg == "usable" or arg == "events" or arg == "both") then
        d.mode = arg
        ns.EvaluateAll()
        print("SpellActivationsForever: detection = " .. arg)
    elseif cmd == "debug" then
        d.debug = not d.debug
        print("SpellActivationsForever: debug " .. (d.debug and "on" or "off"))
    elseif cmd == "nopower" then
        d.noPower = not d.noPower
        ns.internals.CheckUsable()
        print("SpellActivationsForever: glow without power " .. (d.noPower and "on" or "off"))
    elseif cmd == "test" then
        ns.Test(tonumber(arg) or 4)
        print("SpellActivationsForever: every tracked ability glows for a moment")
    elseif cmd == "status" then
        ns.Status()
    elseif cmd == "on" or cmd == "off" then
        local found
        for _, def in ipairs(ns.tracked) do
            if def.key:lower() == arg:lower() or def.localName:lower() == arg:lower() then
                if cmd == "on" then d.spells[def.key] = nil else d.spells[def.key] = false end
                found = def
            end
        end
        if found then
            ns.EvaluateAll()
            print("SpellActivationsForever: " .. found.localName .. " " .. cmd)
        else
            print("SpellActivationsForever: unknown ability '" .. arg .. "'; see /saf status")
        end
    else
        print("SpellActivationsForever: /saf  |  mode usable|events|both  |  on|off <ability>  |  nopower  |  test  |  status  |  debug")
    end
end
