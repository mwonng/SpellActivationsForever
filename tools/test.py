"""Offline tests for SpellActivationsForever: the addon runs in Lua 5.1 (lupa) against tools/wow_stub.lua.

    pip install lupa
    python tools/test.py
"""
import os
import unittest

from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(setup):
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, "tools", "wow_stub.lua"), encoding="utf-8") as f:
        stub = lua.execute(f.read())
    setup(stub)
    ns = stub.Load(ROOT.replace("\\", "/"))
    stub.Fire("PLAYER_LOGIN")
    return lua, stub, ns


class Base(unittest.TestCase):
    cls = "WARRIOR"
    known = (11585, 11601, 20662)  # Overpower, Revenge, Execute

    def setUp(self):
        def setup(stub):
            stub["class"] = self.cls
            for sid in self.known:
                stub.known[sid] = True
            self.extra_setup(stub)
        self.lua, self.stub, self.ns = load(setup)
        self.G = self.lua.globals()

    def extra_setup(self, stub):
        pass

    # --- helpers
    def usable(self, name, usable, no_power=False):
        self.stub.usable[name] = self.lua.table(usable, no_power)
        self.stub.Fire("SPELL_UPDATE_USABLE")

    def button(self, i):
        return self.G["ActionButton%d" % i]

    def put_spell(self, slot, spell_id):
        self.stub.actions[slot] = self.lua.table("spell", spell_id)
        self.button(slot).UpdateSpellAlert(self.button(slot))

    def glowing(self, i):
        return bool(self.stub.alerts[self.button(i)])

    def state(self, key):
        return bool(self.ns.state[key])

    def slash(self, msg):
        self.G.SlashCmdList.SPELLACTIVATIONSFOREVER(msg)

    def tracked_keys(self):
        return [d.key for d in self.ns.tracked.values()]


class Resolution(Base):
    def test_tracks_known_spells_only(self):
        self.assertEqual(self.tracked_keys(), ["Overpower", "Revenge", "Execute"])

    def test_unknown_class_tracks_nothing(self):
        self.cls = "MAGE"
        self.setUp()
        self.assertEqual(len(self.ns.tracked), 0)

    def test_spell_found_by_name_when_ids_differ(self):
        # the client's IDs for Overpower differ: not a player spell by ID, but the spell book has the name
        self.known = ()
        self.extra_setup = lambda stub: stub.bookNames.__setitem__("Overpower", True)
        self.setUp()
        self.assertEqual(self.tracked_keys(), ["Overpower"])


class UsableMode(Base):
    def test_glows_when_usable(self):
        self.put_spell(1, 11585)
        self.assertFalse(self.glowing(1))
        self.usable("Overpower", True)
        self.assertTrue(self.state("Overpower"))
        self.assertTrue(self.glowing(1))
        self.usable("Overpower", False)
        self.assertFalse(self.glowing(1))

    def test_no_power_ignored_by_default(self):
        self.put_spell(1, 11585)
        self.usable("Overpower", False, True)
        self.assertFalse(self.glowing(1))
        self.slash("nopower")
        self.assertTrue(self.glowing(1))

    def test_lower_rank_and_macro_buttons_glow(self):
        self.put_spell(1, 7384)                                     # rank 1 Overpower
        self.stub.actions[2] = self.lua.table("macro", 11585, "spell")  # macro whose id is the spell
        self.button(2).UpdateSpellAlert(self.button(2))
        self.stub.actions[3] = self.lua.table("macro", 7)           # macro resolved through GetMacroSpell
        self.stub.macroSpells[7] = 11584
        self.button(3).UpdateSpellAlert(self.button(3))
        self.usable("Overpower", True)
        self.assertTrue(self.glowing(1))
        self.assertTrue(self.glowing(2))
        self.assertTrue(self.glowing(3))

    def test_other_spells_untouched(self):
        self.put_spell(4, 772)  # Rend
        self.usable("Overpower", True)
        self.assertFalse(self.glowing(4))

    def test_secret_usable_value_is_not_an_error(self):
        self.put_spell(1, 11585)
        self.stub.usable["Overpower"] = self.lua.table(self.stub.Secret("usable"), False)
        self.stub.Fire("SPELL_UPDATE_USABLE")
        self.assertFalse(self.glowing(1))


class EventsMode(Base):
    def setUp(self):
        super().setUp()
        self.slash("mode events")
        self.put_spell(1, 11585)   # Overpower
        self.put_spell(2, 11601)   # Revenge

    def test_target_dodge_opens_window(self):
        self.stub.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        self.assertTrue(self.glowing(1))
        self.assertFalse(self.glowing(2))
        self.stub.Advance(5.1)
        self.assertFalse(self.glowing(1))

    def test_player_parry_block_dodge_open_revenge(self):
        for ev, flag in (("PARRY", ""), ("BLOCK", ""), ("DODGE", ""), ("WOUND", "BLOCK")):
            self.stub.Fire("UNIT_COMBAT", "player", ev, flag, 10, 1)
            self.assertTrue(self.glowing(2), ev)
            self.stub.Advance(6)
            self.assertFalse(self.glowing(2), ev)

    def test_player_dodge_does_not_open_overpower(self):
        self.stub.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
        self.assertFalse(self.glowing(1))

    def test_cast_closes_window(self):
        self.stub.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        self.assertTrue(self.glowing(1))
        self.stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 11585)
        self.assertFalse(self.glowing(1))

    def test_secret_cast_id_is_ignored(self):
        self.stub.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        self.stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", self.stub.Secret("spell"))
        self.assertTrue(self.glowing(1))

    def test_usable_flag_does_not_count_in_events_mode(self):
        self.usable("Overpower", True)
        self.assertFalse(self.glowing(1))

    def test_both_mode_takes_either(self):
        self.slash("mode both")
        self.usable("Overpower", True)
        self.assertTrue(self.glowing(1))
        self.usable("Overpower", False)
        self.assertFalse(self.glowing(1))
        self.stub.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        self.assertTrue(self.glowing(1))


class Execute(Base):
    def test_health_source_in_events_mode(self):
        self.slash("mode events")
        self.put_spell(3, 20662)
        self.stub.target = self.lua.table(health=50, healthMax=100)
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertFalse(self.glowing(3))
        self.stub.target.health = 15
        self.stub.Fire("UNIT_HEALTH", "target")
        self.assertTrue(self.glowing(3))
        self.stub.target = None
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertFalse(self.glowing(3))

    def test_secret_health_means_no_glow_rather_than_error(self):
        self.slash("mode events")
        self.put_spell(3, 20662)
        self.stub.target = self.lua.table(health=self.stub.Secret("hp"), healthMax=100)
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertFalse(self.glowing(3))

    def test_friendly_target_never_glows(self):
        self.slash("mode events")
        self.put_spell(3, 20662)
        self.stub.target = self.lua.table(health=5, healthMax=100, friend=True)
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertFalse(self.glowing(3))


class Buttons(Base):
    def test_slot_change_moves_the_glow(self):
        self.put_spell(1, 11585)
        self.usable("Overpower", True)
        self.assertTrue(self.glowing(1))
        self.put_spell(1, 772)   # Rend dragged onto the slot: the game's UpdateSpellAlert runs
        self.assertFalse(self.glowing(1))
        self.put_spell(5, 11585)
        self.assertTrue(self.glowing(5))

    def test_games_own_hide_is_reapplied(self):
        self.put_spell(1, 11585)
        self.usable("Overpower", True)
        self.G.ActionButtonSpellAlertManager.HideAlert(self.G.ActionButtonSpellAlertManager, self.button(1))
        self.assertTrue(self.glowing(1))
        calls = list(self.stub.alertCalls.values())
        self.assertEqual([c[1] for c in calls], ["show", "hide", "show"])
        self.assertTrue(calls[-1][3], "re-apply skips the birth animation")

    def test_games_own_glow_is_kept_when_ours_ends(self):
        self.put_spell(1, 11585)
        self.stub.overlayed[11585] = True
        self.button(1).UpdateSpellAlert(self.button(1))
        self.usable("Overpower", True)
        self.usable("Overpower", False)
        self.assertTrue(self.glowing(1))

    def test_disabled_ability_does_not_glow(self):
        self.put_spell(1, 11585)
        self.slash("off overpower")
        self.usable("Overpower", True)
        self.assertFalse(self.glowing(1))
        self.slash("on Overpower")
        self.assertTrue(self.glowing(1))

    def test_test_command_lights_everything_for_a_moment(self):
        self.put_spell(1, 11585)
        self.put_spell(2, 11601)
        self.slash("test 2")
        self.assertTrue(self.glowing(1) and self.glowing(2))
        self.stub.Advance(2.1)
        self.assertFalse(self.glowing(1) or self.glowing(2))

    def test_status_lists_abilities(self):
        self.slash("status")
        text = "\n".join(self.stub.printed.values())
        self.assertIn("Overpower", text)
        self.assertIn("Revenge", text)
        self.assertIn("Execute", text)


class Paladin(Base):
    cls = "PALADIN"
    known = (10314, 24275)

    def test_exorcism_follows_creature_type(self):
        self.put_spell(1, 10314)
        self.stub.target = self.lua.table(health=100, healthMax=100, creature="Undead")
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertTrue(self.glowing(1))
        self.stub.target.creature = "Beast"
        self.stub.Fire("UNIT_HEALTH", "target")
        self.assertFalse(self.glowing(1))

    def test_exorcism_dark_on_cooldown(self):
        self.put_spell(1, 10314)
        self.stub.target = self.lua.table(health=100, healthMax=100, creature="Demon")
        self.stub.cooldowns["Exorcism"] = self.lua.table(0, 15)
        self.stub.Fire("PLAYER_TARGET_CHANGED")
        self.assertFalse(self.glowing(1))
        self.stub.Advance(15.1)
        self.stub.Fire("SPELL_UPDATE_COOLDOWN")
        self.assertTrue(self.glowing(1))

    def test_hammer_of_wrath_usable(self):
        self.put_spell(2, 24275)
        self.usable("Hammer of Wrath", True)
        self.assertTrue(self.glowing(2))


class Warlock(Base):
    cls = "WARLOCK"
    known = (25307,)

    def test_shadow_trance_lights_shadow_bolt(self):
        self.put_spell(1, 686)
        self.assertFalse(self.glowing(1))
        self.stub.auras[17941] = True
        self.stub.Fire("UNIT_AURA", "player")
        self.assertTrue(self.glowing(1))
        self.stub.auras[17941] = None
        self.stub.Fire("UNIT_AURA", "player")
        self.assertFalse(self.glowing(1))

    def test_usable_mode_does_not_light_shadow_bolt(self):
        self.put_spell(1, 686)
        self.usable("Shadow Bolt", True)
        self.assertFalse(self.glowing(1))


if __name__ == "__main__":
    unittest.main(verbosity=1)
