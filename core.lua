-- SpellActivationsForever: lights up the action buttons of reactive abilities, the way the game's own
-- spell alerts do, for WoW Forever. Written from scratch for this client, where addons cannot read the
-- combat log; the idea is the one ClassicSpellActivations (d87) implements on Classic Era.
local ADDON, ns = ...

local f = CreateFrame("Frame")
ns.frame = f

local DEFAULTS = {
    mode = "usable",   -- "usable": the server's usable flag; "events": UNIT_COMBAT windows and checks; "both": either
    noPower = false,   -- also glow when the only thing missing is rage/mana/energy
    debug = false,
    spells = {},       -- [key] = false to disable an ability
}
local db

local tracked = {}  -- definitions of the abilities the player knows, in class order
local byName = {}   -- localized spell name -> definition
local sources = {}  -- key -> { usable = bool, window = expiry time, aura = bool, health = bool, creature = bool }
local state = {}    -- key -> true while the ability glows
local forced = nil  -- expiry time of /saf test

local GetTime = GetTime
local issecretvalue = issecretvalue or function() return false end

local function Plain(v)
    if v == nil or issecretvalue(v) then return nil end
    return v
end

local function Debug(...)
    if db and db.debug then print("|cff7fd5ffSAF|r", ...) end
end

---------------------------------------------------------------------------
-- Spell resolution
---------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function SpellKnown(def)
    for _, id in ipairs(def.ids) do
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
    end
    -- the IDs may differ in this client: a lookup by name finds the spell when it is in the spell book
    if C_Spell and C_Spell.GetSpellInfo then
        return C_Spell.GetSpellInfo(def.localName) ~= nil
    end
    return false
end

local function Resolve()
    local _, class = UnitClass("player")
    wipe(tracked)
    wipe(byName)
    for _, def in ipairs(ns.SPELLS[class] or {}) do
        local name
        for _, id in ipairs(def.ids) do
            name = SpellName(id)
            if name and name ~= "" then break end
        end
        def.localName = name or def.name
        def.known = SpellKnown(def)
        if def.known then
            tracked[#tracked + 1] = def
            byName[def.localName] = def
            sources[def.key] = sources[def.key] or {}
        end
    end
end

local function Enabled(def)
    return db.spells[def.key] ~= false
end

---------------------------------------------------------------------------
-- Activation state
---------------------------------------------------------------------------
local function EventsActive(s)
    if s.window and s.window > GetTime() then return true end
    return s.aura or s.health or s.creature or false
end

local function IsActive(def)
    if not Enabled(def) then return false end
    if forced and forced > GetTime() then return true end
    local s = sources[def.key]
    if not s then return false end
    local hasEvents = def.window or def.health or def.aura or def.creature
    if not def.usable then return EventsActive(s) end
    if not hasEvents then return s.usable or false end
    if db.mode == "events" then return EventsActive(s) end
    if db.mode == "both" then return (s.usable or false) or EventsActive(s) end
    return s.usable or false
end

local RefreshButtons -- forward

local function Evaluate(def)
    local new = IsActive(def)
    if state[def.key] ~= new then
        state[def.key] = new
        local s = sources[def.key] or {}
        Debug(def.localName, new and "on" or "off",
            "usable=" .. tostring(s.usable), "window=" .. tostring(s.window ~= nil and s.window > GetTime()),
            "aura=" .. tostring(s.aura), "health=" .. tostring(s.health), "creature=" .. tostring(s.creature))
        RefreshButtons()
    end
end

local function EvaluateAll()
    for _, def in ipairs(tracked) do Evaluate(def) end
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local function CheckUsable()
    for _, def in ipairs(tracked) do
        if def.usable then
            local usable, noPower
            if C_Spell and C_Spell.IsSpellUsable then
                usable, noPower = C_Spell.IsSpellUsable(def.localName)
            elseif IsUsableSpell then
                usable, noPower = IsUsableSpell(def.localName)
            end
            usable, noPower = Plain(usable), Plain(noPower)
            sources[def.key].usable = (usable == true) or (db.noPower and noPower == true) or false
            Evaluate(def)
        end
    end
end

local function OpenWindow(def, duration)
    local s = sources[def.key]
    s.window = GetTime() + duration
    Evaluate(def)
    C_Timer.After(duration + 0.05, function() Evaluate(def) end)
end

local function CloseWindow(def)
    local s = sources[def.key]
    if s and s.window then
        s.window = nil
        Evaluate(def)
    end
end

-- UNIT_COMBAT: unit, event ("DODGE", "PARRY", "BLOCK", "WOUND", ...), flagText, amount, school
local function OnUnitCombat(unit, event, flagText)
    event, flagText = Plain(event), Plain(flagText)
    if not event then return end
    if event == "WOUND" and flagText and flagText:find("BLOCK") then event = "BLOCK" end
    for _, def in ipairs(tracked) do
        local w = def.window
        if w and w.unit == unit and w.events[event] then
            Debug("UNIT_COMBAT", unit, event, "->", def.localName)
            OpenWindow(def, w.duration)
        end
    end
end

local function OnSpellCastSucceeded(unit, _, spellID)
    spellID = Plain(spellID)
    if not spellID then return end
    local name = SpellName(spellID)
    local def = name and byName[name]
    if def and def.window then CloseWindow(def) end
end

local function CheckHealth()
    local exists = UnitExists("target") and not UnitIsFriend("player", "target") and not UnitIsDead("target")
    local fraction
    if exists then
        local h, m = Plain(UnitHealth("target")), Plain(UnitHealthMax("target"))
        if h and m and m > 0 then fraction = h / m end
    end
    for _, def in ipairs(tracked) do
        if def.health then
            sources[def.key].health = (fraction ~= nil and fraction > 0 and fraction < def.health.below) or false
            Evaluate(def)
        end
    end
end

local creatureNames
local function CheckCreature()
    if not creatureNames then
        creatureNames = {}
        local locale = GetLocale()
        for kind, names in pairs(ns.CREATURE_TYPES) do
            creatureNames[kind] = names[locale] or names.enUS
        end
    end
    local ctype = UnitExists("target") and not UnitIsDead("target") and Plain(UnitCreatureType("target")) or nil
    for _, def in ipairs(tracked) do
        if def.creature then
            local match = false
            if ctype then
                for _, kind in ipairs(def.creature) do
                    if creatureNames[kind] == ctype then match = true end
                end
            end
            if match and C_Spell and C_Spell.GetSpellCooldown then
                -- no glow while the spell is on a cooldown longer than the global one, when that is readable
                local cd = C_Spell.GetSpellCooldown(def.localName)
                local start, duration = cd and Plain(cd.startTime), cd and Plain(cd.duration)
                if start and duration and duration > 1.5 and start + duration > GetTime() then match = false end
            end
            sources[def.key].creature = match
            Evaluate(def)
        end
    end
end

local function HasPlayerAura(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
    end
    if AuraUtil and AuraUtil.ForEachAura then
        local found = false
        AuraUtil.ForEachAura("player", "HELPFUL", nil, function(_, _, _, _, _, _, _, _, _, id)
            if id == spellID then found = true return true end
        end)
        return found
    end
    return false
end

local function CheckAuras()
    for _, def in ipairs(tracked) do
        if def.aura then
            sources[def.key].aura = HasPlayerAura(def.aura)
            Evaluate(def)
        end
    end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
               "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local buttons = {} -- button -> true
local glowing = {} -- button -> key this addon lit it for
local Manager = ActionButtonSpellAlertManager

local function SpellIDOfButton(btn)
    if btn.GetSpellId then return btn:GetSpellId() end -- LibActionButton (Bartender, Dominos)
    local action = btn.action
    if not action then return end
    local kind, id, sub = GetActionInfo(action)
    if kind == "spell" then return id end
    if kind == "macro" then
        if sub == "spell" then return id end
        if GetMacroSpell then return GetMacroSpell(id) end
    end
end

local function KeyForButton(btn)
    local id = Plain(SpellIDOfButton(btn))
    if not id then return end
    local name = SpellName(id)
    local def = name and byName[name]
    return def and def.key
end

local function BlizzardWantsGlow(btn)
    local id = Plain(SpellIDOfButton(btn))
    return id and C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        and C_SpellActivationOverlay.IsSpellOverlayed(id) or false
end

local function UpdateButton(btn)
    if not Manager then return end
    local key = KeyForButton(btn)
    local want = key and state[key] or false
    if want then
        if glowing[btn] ~= key then
            glowing[btn] = key
            Manager:ShowAlert(btn)
        else
            Manager:ShowAlert(btn, true) -- re-apply after the game's own update hid it; no birth animation
        end
    elseif glowing[btn] then
        glowing[btn] = nil
        if not BlizzardWantsGlow(btn) then Manager:HideAlert(btn) end
    end
end

RefreshButtons = function()
    for btn in pairs(buttons) do UpdateButton(btn) end
end

local function Register(btn)
    if not btn or buttons[btn] then return end
    buttons[btn] = true
    if btn.UpdateSpellAlert then
        hooksecurefunc(btn, "UpdateSpellAlert", UpdateButton) -- the game decides, then this addon adds its glow
    end
end

local function SetupButtons()
    for _, bar in ipairs(BARS) do
        for i = 1, 12 do Register(_G[bar .. i]) end
    end
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB then
        if LAB.GetAllButtons then
            for btn in pairs(LAB:GetAllButtons()) do Register(btn) end
        end
        LAB:RegisterCallback("OnButtonUpdate", function(_, btn) Register(btn) UpdateButton(btn) end)
    end
    if Manager and not ns.hookedManager then
        ns.hookedManager = true
        -- the game hides an alert on SPELL_ACTIVATION_OVERLAY_GLOW_HIDE without going through UpdateSpellAlert
        hooksecurefunc(Manager, "HideAlert", function(_, btn)
            local key = glowing[btn]
            if key and state[key] then Manager:ShowAlert(btn, true) end
        end)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Setup()
    Resolve()
    f:UnregisterAllEvents()
    f:RegisterEvent("SPELLS_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    local wantUsable, wantCombat, wantHealth, wantAura, wantCreature = false, false, false, false, false
    for _, def in ipairs(tracked) do
        wantUsable = wantUsable or def.usable or false
        wantCombat = wantCombat or def.window ~= nil
        wantHealth = wantHealth or def.health ~= nil
        wantAura = wantAura or def.aura ~= nil
        wantCreature = wantCreature or def.creature ~= nil
    end
    if wantUsable then
        f:RegisterEvent("SPELL_UPDATE_USABLE")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    if wantCombat then
        f:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    if wantHealth or wantCreature then
        f:RegisterUnitEvent("UNIT_HEALTH", "target")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    if wantCreature then f:RegisterEvent("SPELL_UPDATE_COOLDOWN") end
    if wantAura then f:RegisterUnitEvent("UNIT_AURA", "player") end
    if wantUsable then CheckUsable() end
    if wantHealth then CheckHealth() end
    if wantCreature then CheckCreature() end
    if wantAura then CheckAuras() end
    EvaluateAll()
    Debug("tracking", #tracked, "abilities")
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        SpellActivationsForeverDB = SpellActivationsForeverDB or {}
        db = SpellActivationsForeverDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = type(v) == "table" and {} or v end
        end
        ns.db = db
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_LOGIN" then
        SetupButtons()
        Setup()
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        Setup()
    elseif event == "SPELL_UPDATE_USABLE" then
        CheckUsable()
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUsable()
        CheckHealth()
        CheckCreature()
    elseif event == "UNIT_HEALTH" then
        CheckHealth()
        CheckCreature()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        CheckCreature()
    elseif event == "UNIT_AURA" then
        CheckAuras()
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCastSucceeded(...)
    end
end)
f:RegisterEvent("ADDON_LOADED")

---------------------------------------------------------------------------
-- Shared with options.lua and the tests
---------------------------------------------------------------------------
ns.tracked = tracked
ns.sources = sources
ns.state = state
ns.Setup = Setup
ns.EvaluateAll = EvaluateAll
ns.RefreshButtons = RefreshButtons
ns.IsActive = IsActive
ns.Enabled = Enabled

function ns.Test(seconds)
    forced = GetTime() + (seconds or 4)
    EvaluateAll()
    C_Timer.After((seconds or 4) + 0.05, EvaluateAll)
end

function ns.Status()
    print("|cff7fd5ffSpellActivationsForever|r mode: " .. db.mode .. (db.noPower and ", glow without power" or ""))
    if #tracked == 0 then print("  no reactive abilities known for this class") end
    for _, def in ipairs(tracked) do
        local s = sources[def.key] or {}
        local how = {}
        if def.usable then how[#how + 1] = "usable=" .. tostring(s.usable) end
        if def.window then
            local left = s.window and s.window - GetTime() or 0
            how[#how + 1] = "window=" .. (left > 0 and ("%.1fs"):format(left) or "no")
        end
        if def.health then how[#how + 1] = "health=" .. tostring(s.health) end
        if def.aura then how[#how + 1] = "aura=" .. tostring(s.aura) end
        if def.creature then how[#how + 1] = "creature=" .. tostring(s.creature) end
        print(("  %s%s: %s (%s)"):format(def.localName, Enabled(def) and "" or " [off]",
            state[def.key] and "|cff40ff40glowing|r" or "dark", table.concat(how, ", ")))
    end
end

ns.internals = {
    db = function() return db end,
    buttons = buttons,
    glowing = glowing,
    byName = byName,
    KeyForButton = KeyForButton,
    CheckUsable = CheckUsable,
}
