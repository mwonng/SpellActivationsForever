-- A small stand-in for the WoW API, enough to load SpellActivationsForever outside the game and drive it
-- from tools/test.py. Returns the stub table; its fields are the knobs the tests turn.
local stub = {
    time = 0,
    class = "WARRIOR",
    locale = "enUS",
    known = {},      -- [spellID] = true (IsPlayerSpell)
    names = {},      -- [spellID] = name (C_Spell.GetSpellName); filled below
    bookNames = {},  -- [name] = true: C_Spell.GetSpellInfo(name) finds it
    usable = {},     -- [name] = { usable, noPower }
    cooldowns = {},  -- [name] = { startTime, duration }
    auras = {},      -- [spellID] = true on the player
    target = nil,    -- { friend, dead, health, healthMax, creature }
    overlayed = {},  -- [spellID] = true: C_SpellActivationOverlay.IsSpellOverlayed
    actions = {},    -- [slot] = { "spell", id } or { "macro", macroID, "spell"|nil }
    macroSpells = {},-- [macroID] = spellID
    printed = {},
    frames = {},
    timers = {},
    alerts = {},     -- [button] = true while ActionButtonSpellAlertManager shows an alert
    alertCalls = {}, -- { "show"/"hide", button, skipBirth }
}

local SPELL_NAMES = {
    [11585] = "Overpower", [11584] = "Overpower", [7887] = "Overpower", [7384] = "Overpower",
    [11601] = "Revenge", [11600] = "Revenge", [7379] = "Revenge", [6574] = "Revenge", [6572] = "Revenge",
    [20662] = "Execute", [20661] = "Execute", [20660] = "Execute", [20658] = "Execute", [5308] = "Execute",
    [14251] = "Riposte",
    [20910] = "Counterattack", [20909] = "Counterattack", [19306] = "Counterattack",
    [14271] = "Mongoose Bite", [14270] = "Mongoose Bite", [14269] = "Mongoose Bite", [1495] = "Mongoose Bite",
    [10314] = "Exorcism", [10313] = "Exorcism", [10312] = "Exorcism", [5615] = "Exorcism", [5614] = "Exorcism", [879] = "Exorcism",
    [24275] = "Hammer of Wrath", [24274] = "Hammer of Wrath", [24239] = "Hammer of Wrath",
    [25307] = "Shadow Bolt", [686] = "Shadow Bolt",
    [17941] = "Shadow Trance",
    [1464] = "Slam", [772] = "Rend", [6673] = "Battle Shout",
}
for id, name in pairs(SPELL_NAMES) do stub.names[id] = name end

---------------------------------------------------------------------------
-- Secret values: a table whose comparisons and arithmetic error, like the game's
---------------------------------------------------------------------------
local secretMeta = {
    __eq = function() error("attempt to compare a secret value") end,
    __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end,
    __add = function() error("attempt to perform arithmetic on a secret value") end,
    __div = function() error("attempt to perform arithmetic on a secret value") end,
    __concat = function() error("attempt to concatenate a secret value") end,
}
function stub.Secret(tag) return setmetatable({ secret = tag }, secretMeta) end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == secretMeta end
function canaccessvalue(v) return not issecretvalue(v) end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local Region = {}
Region.__index = Region
function Region:SetPoint(...) self.point = { ... } end
function Region:ClearAllPoints() self.point = nil end
function Region:SetAllPoints() end
function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetHeight(h) self.h = h end
function Region:SetWidth(w) self.w = w end
function Region:GetSize() return self.w or 0, self.h or 0 end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown ~= false end
function Region:SetShown(v) self.shown = v and true or false end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetJustifyH() end
function Region:SetWordWrap() end
function Region:SetSpacing() end
function Region:GetStringHeight() return 14 end
function Region:GetStringWidth() return (self.text and #self.text or 0) * 6 end
function Region:SetColorTexture() end
function Region:SetChecked(v) self.checked = v end
function Region:GetChecked() return self.checked end

local Frame = setmetatable({}, Region)
Frame.__index = Frame
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:RegisterUnitEvent(e, ...) self.events[e] = { ... } end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Frame:CreateFontString() return setmetatable({}, Region) end
function Frame:CreateTexture() return setmetatable({}, Region) end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetDebugName() return self.name or "frame" end

function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, parent = parent, template = template,
        events = {}, scripts = {}, children = {} }, Frame)
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    if name then _G[name] = f end
    stub.frames[#stub.frames + 1] = f
    return f
end
UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")
function GameTooltip:SetOwner() end
function GameTooltip:AddLine() end
function GameTooltip_Hide() end

function stub.Fire(event, ...)
    local unit = ...
    for _, f in ipairs(stub.frames) do
        local reg = f.events[event]
        if reg and f.scripts.OnEvent then
            local ok = true
            if type(reg) == "table" then
                ok = false
                for _, u in ipairs(reg) do if u == unit then ok = true end end
            end
            if ok then f.scripts.OnEvent(f, event, ...) end
        end
    end
end

---------------------------------------------------------------------------
-- Action buttons and the spell alert manager
---------------------------------------------------------------------------
ActionButtonSpellAlertManager = {}
function ActionButtonSpellAlertManager:ShowAlert(btn, skipBirth)
    if stub.alerts[btn] then return end
    stub.alerts[btn] = true
    stub.alertCalls[#stub.alertCalls + 1] = { "show", btn, skipBirth and true or false }
end
function ActionButtonSpellAlertManager:HideAlert(btn)
    if not stub.alerts[btn] then return end
    stub.alerts[btn] = nil
    stub.alertCalls[#stub.alertCalls + 1] = { "hide", btn, false }
end
function ActionButtonSpellAlertManager:HasAlert(btn) return stub.alerts[btn] == true end

C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return stub.overlayed[id] == true end }

function GetActionInfo(slot)
    local a = stub.actions[slot]
    if not a then return nil end
    return a[1], a[2], a[3]
end
function GetMacroSpell(id) return stub.macroSpells[id] end

-- The game's buttons: UpdateSpellAlert is what the game runs on slot changes (then the addon's hook)
local ButtonMixin = {}
function ButtonMixin:UpdateSpellAlert()
    local kind, id = GetActionInfo(self.action)
    if (kind == "spell" or kind == "macro") and C_SpellActivationOverlay.IsSpellOverlayed(id) then
        ActionButtonSpellAlertManager:ShowAlert(self)
    else
        ActionButtonSpellAlertManager:HideAlert(self)
    end
end
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b.action = i
    b.UpdateSpellAlert = ButtonMixin.UpdateSpellAlert
end
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "MultiBarBottomLeftButton" .. i, UIParent)
    b.action = 60 + i
    b.UpdateSpellAlert = ButtonMixin.UpdateSpellAlert
end

function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end
end

---------------------------------------------------------------------------
-- Spells, units, auras
---------------------------------------------------------------------------
C_Spell = {
    GetSpellName = function(id) return stub.names[id] end,
    GetSpellInfo = function(idOrName)
        if type(idOrName) == "string" then
            if stub.bookNames[idOrName] then return { name = idOrName } end
            return nil
        end
        local n = stub.names[idOrName]
        return n and { name = n, spellID = idOrName } or nil
    end,
    IsSpellUsable = function(name)
        local u = stub.usable[name]
        if not u then return false, false end
        return u[1], u[2]
    end,
    GetSpellCooldown = function(name)
        local cd = stub.cooldowns[name]
        return { startTime = cd and cd[1] or 0, duration = cd and cd[2] or 0, isEnabled = true }
    end,
}
function IsPlayerSpell(id) return stub.known[id] == true end
function UnitClass() return stub.class, stub.class end
function GetLocale() return stub.locale end
function GetTime() return stub.time end
function UnitExists(unit) return unit == "player" or (unit == "target" and stub.target ~= nil) end
function UnitIsFriend(_, unit) return unit == "target" and stub.target and stub.target.friend or false end
function UnitIsDead(unit) return unit == "target" and stub.target and stub.target.dead or false end
function UnitHealth(unit) return unit == "target" and stub.target and stub.target.health or 0 end
function UnitHealthMax(unit) return unit == "target" and stub.target and stub.target.healthMax or 0 end
function UnitCreatureType(unit) return unit == "target" and stub.target and stub.target.creature or nil end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return stub.auras[id] and { spellId = id } or nil end }

C_Timer = {
    After = function(delay, fn) stub.timers[#stub.timers + 1] = { at = stub.time + delay, fn = fn } end,
}
-- Advance the clock and run the timers that are due
function stub.Advance(seconds)
    stub.time = stub.time + seconds
    local due = {}
    for i = #stub.timers, 1, -1 do
        local t = stub.timers[i]
        if t.at <= stub.time then due[#due + 1] = t table.remove(stub.timers, i) end
    end
    for i = #due, 1, -1 do due[i].fn() end
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    stub.printed[#stub.printed + 1] = table.concat(parts, " ")
end
SlashCmdList = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { GetID = function() return name end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() stub.panelOpened = true end,
}

-- Load the addon's files with the (addonName, ns) vararg the game passes
function stub.Load(root)
    local ns = {}
    for _, file in ipairs({ "spells.lua", "core.lua", "options.lua" }) do
        local chunk, err = loadfile(root .. "/" .. file)
        if not chunk then error(err) end
        chunk("SpellActivationsForever", ns)
    end
    stub.Fire("ADDON_LOADED", "SpellActivationsForever")
    return ns
end

return stub
