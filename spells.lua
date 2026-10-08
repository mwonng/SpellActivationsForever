-- Which abilities light up, per class, and how each one is detected.
--
-- Fields of a definition:
--   key      internal name (saved variables, slash commands)
--   name     English spell name; the localized name comes from the first of `ids` the client knows
--   ids      Classic spell IDs, highest rank first (only used to look the name up and to detect the spell)
--   usable   true when the server's "usable" flag of the spell reflects the condition (reactive abilities:
--            the button is dimmed until the condition is met)
--   window   { unit = "player"|"target", events = { DODGE = true, ... }, duration = seconds }:
--            a UNIT_COMBAT event of that kind on that unit opens a window during which the ability glows
--   health   { below = 0.2 }: glows while the target's health is below the fraction
--   aura     spell ID of a buff on the player that makes the ability glow (e.g. Shadow Trance)
--   creature { "Undead", "Demon" }: glows while the target is one of these creature types
local _, ns = ...

ns.SPELLS = {
    WARRIOR = {
        { key = "Overpower", name = "Overpower", ids = { 11585, 11584, 7887, 7384 }, usable = true,
          window = { unit = "target", events = { DODGE = true }, duration = 5 } },
        { key = "Revenge", name = "Revenge", ids = { 11601, 11600, 7379, 6574, 6572 }, usable = true,
          window = { unit = "player", events = { DODGE = true, PARRY = true, BLOCK = true }, duration = 5 } },
        { key = "Execute", name = "Execute", ids = { 20662, 20661, 20660, 20658, 5308 }, usable = true,
          health = { below = 0.2 } },
    },
    ROGUE = {
        { key = "Riposte", name = "Riposte", ids = { 14251 }, usable = true,
          window = { unit = "player", events = { PARRY = true }, duration = 5 } },
    },
    HUNTER = {
        { key = "Counterattack", name = "Counterattack", ids = { 20910, 20909, 19306 }, usable = true,
          window = { unit = "player", events = { PARRY = true }, duration = 5 } },
        { key = "MongooseBite", name = "Mongoose Bite", ids = { 14271, 14270, 14269, 1495 }, usable = true,
          window = { unit = "player", events = { DODGE = true }, duration = 5 } },
    },
    PALADIN = {
        { key = "Exorcism", name = "Exorcism", ids = { 10314, 10313, 10312, 5615, 5614, 879 },
          creature = { "Undead", "Demon" } },
        { key = "HammerOfWrath", name = "Hammer of Wrath", ids = { 24275, 24274, 24239 }, usable = true,
          health = { below = 0.2 } },
    },
    WARLOCK = {
        { key = "ShadowBolt", name = "Shadow Bolt", ids = { 25307, 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686 },
          aura = 17941 }, -- Shadow Trance (Nightfall)
    },
}

-- Localized creature type names (UnitCreatureType returns the client's language), from ClassicSpellActivations.
ns.CREATURE_TYPES = {
    Undead = { enUS = "Undead", deDE = "Untoter", esES = "No-muerto", esMX = "No-muerto", frFR = "Mort-vivant",
               itIT = "Non Morto", ptBR = "Renegado", ruRU = "Нежить", koKR = "언데드", zhCN = "亡灵", zhTW = "不死族" },
    Demon = { enUS = "Demon", deDE = "Dämon", esES = "Demonio", esMX = "Demonio", frFR = "Démon",
              itIT = "Demone", ptBR = "Demônio", ruRU = "Демон", koKR = "악마", zhCN = "恶魔", zhTW = "惡魔" },
}
