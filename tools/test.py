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


class CooldownManager(Base):
    """The Cooldown Manager's Essential/Utility item frames glow like the action buttons."""

    def viewer(self, name="EssentialCooldownViewer"):
        return self.G[name]

    def add_item(self, spell_id, viewer="EssentialCooldownViewer"):
        v = self.viewer(viewer)
        return v.AddItem(v, spell_id)

    def lit(self, item):
        # the addon's own alert frame on the item (the game's manager must never be used on items)
        alert = self.ns.internals.ownAlerts[item]
        return bool(alert) and bool(alert.IsShown(alert))

    def tearDown(self):
        for call in self.stub.alertCalls.values():
            if call[2].RefreshOverlayGlow is not None:  # a Cooldown Manager item
                self.assertTrue(call[4], "ActionButtonSpellAlertManager was called with an item from addon code")

    def test_item_glows_with_the_ability(self):
        item = self.add_item(11585)
        utility = self.add_item(11601, "UtilityCooldownViewer")
        self.assertFalse(self.lit(item))
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))
        self.assertFalse(self.lit(utility))
        self.usable("Revenge", True)
        self.assertTrue(self.lit(utility))
        self.usable("Overpower", False)
        self.assertFalse(self.lit(item))
        self.assertTrue(self.lit(utility))

    def test_item_present_before_login_is_found(self):
        # frames the viewer acquired before PLAYER_LOGIN are picked up from the pool, not only new ones
        self.extra_setup = lambda stub: stub.viewers.EssentialCooldownViewer.AddItem(stub.viewers.EssentialCooldownViewer, 11585)
        self.setUp()
        first = self.lua.eval("function(pool) for item in pool.EnumerateActive() do return item end end")
        item = first(self.viewer().itemFramePool)
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))

    def test_games_refresh_leaves_our_glow(self):
        item = self.add_item(11585)
        self.usable("Overpower", True)
        item.RefreshData(item)  # the game's RefreshData hides its own alert (spell not overlayed); ours stays
        self.assertTrue(self.lit(item))
        alert = self.ns.internals.ownAlerts[item]
        self.assertTrue(alert.ProcLoop.IsPlaying(alert.ProcLoop), "loop animation runs after the birth one")
        self.assertEqual(alert.template, "ActionButtonSpellAlertTemplate")
        self.assertEqual((alert.w, alert.h), (70, 70))

    def test_nothing_is_written_on_the_item(self):
        # writes from addon code taint the item and break the viewer's secure code on secret values
        self.stub.alertCalls = self.lua.table()
        item = self.add_item(11585)
        item.tag = "me"
        keys_before = set(k for k in item.keys() if k != "viewer")
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))
        self.usable("Overpower", False)
        self.assertFalse(self.lit(item))
        self.assertEqual(set(k for k in item.keys() if k != "viewer"), keys_before)
        self.assertEqual(len(self.stub.alertCalls), 0, "the game's alert manager was not used on the item")
        self.assertEqual(self.ns.internals.ownAlerts[item].parent.tag, "me")

    def test_plain_texture_when_the_template_is_missing(self):
        self.extra_setup = lambda stub: stub.viewers.EssentialCooldownViewer.AddItem(stub.viewers.EssentialCooldownViewer, 11585)
        self.setUp()
        broken = self.lua.eval("function(orig) return function(kind, name, parent, template) "
                               "if template == 'ActionButtonSpellAlertTemplate' then error('unknown template') end "
                               "return orig(kind, name, parent, template) end end")
        self.G.CreateFrame = broken(self.G.CreateFrame)
        first = self.lua.eval("function(pool) for item in pool.EnumerateActive() do return item end end")
        item = first(self.viewer().itemFramePool)
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))
        self.assertIsNone(self.ns.internals.ownAlerts[item].ProcStartAnim)

    def test_item_changing_spell_moves_the_glow(self):
        item = self.add_item(11585)
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))
        item.SetCooldownSpell(item, 772)  # the item now shows Rend
        self.assertFalse(self.lit(item))
        item.SetCooldownSpell(item, 7384)  # back to Overpower (rank 1)
        self.assertTrue(self.lit(item))

    def test_pool_reuse_after_layout_refresh(self):
        item = self.add_item(11585)
        item.tag = "first"
        self.usable("Overpower", True)
        self.viewer().itemFramePool.ReleaseAll()
        reused = self.add_item(11601)  # the same frame comes back, now for Revenge
        self.assertEqual(reused.tag, "first")
        self.assertFalse(self.lit(reused))
        self.usable("Revenge", True)
        self.assertTrue(self.lit(reused))

    def test_games_own_glow_is_not_doubled(self):
        self.stub.overlayed[11585] = True
        item = self.add_item(11585)
        self.assertTrue(bool(self.stub.alerts[item]), "the game's glow")
        self.usable("Overpower", True)
        self.assertFalse(self.lit(item), "no second glow on top of the game's")
        self.stub.overlayed[11585] = None
        item.RefreshOverlayGlow(item)  # the game takes its glow away; ours takes over
        self.assertFalse(bool(self.stub.alerts[item]))
        self.assertTrue(self.lit(item))

    def test_secret_spell_id_is_not_an_error(self):
        item = self.add_item(self.stub.Secret("spell"))
        self.usable("Overpower", True)
        self.assertFalse(self.lit(item))

    def test_action_buttons_and_items_glow_together(self):
        self.put_spell(1, 11585)
        item = self.add_item(11585)
        self.slash("test 2")
        self.assertTrue(self.glowing(1) and self.lit(item))
        self.stub.Advance(2.1)
        self.assertFalse(self.glowing(1) or self.lit(item))

    def test_viewer_loading_after_login_is_hooked(self):
        # Blizzard_CooldownViewer is not there at login and loads afterwards
        self.extra_setup = lambda stub: stub.RemoveCooldownViewers()
        self.setUp()
        self.assertIsNone(self.G.EssentialCooldownViewer)
        self.assertFalse(bool(self.ns.viewersHooked))
        self.stub.CreateCooldownViewers()
        self.stub.Fire("ADDON_LOADED", "Blizzard_CooldownViewer")
        self.assertTrue(bool(self.ns.viewersHooked))
        item = self.add_item(11585)
        self.usable("Overpower", True)
        self.assertTrue(self.lit(item))


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
