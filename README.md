# SpellActivationsForever

Lights up the action buttons of reactive abilities with the game's own spell alert glow. An addon for
**WoW: Forever**, after the idea of ClassicSpellActivations by d87.

| Class   | Abilities                                                   |
|---------|-------------------------------------------------------------|
| Warrior | Overpower, Revenge, Execute                                 |
| Rogue   | Riposte                                                     |
| Hunter  | Counterattack, Mongoose Bite                                |
| Paladin | Exorcism (undead or demon target), Hammer of Wrath          |
| Warlock | Shadow Bolt while Shadow Trance (Nightfall) is up           |

## How it detects the moment

Addons cannot read the combat log in WoW: Forever, which is what ClassicSpellActivations used. Instead:

- **Usable state** (default): the server marks a reactive ability usable only while its condition holds
  (that is why the button is dimmed until a dodge happens). The glow follows that flag exactly, and goes off
  when the ability is used. "Glow without enough rage/energy/mana" also lights it when power is the only
  thing missing.
- **Combat events**: the client still reports dodges, parries and blocks for you and your target
  (`UNIT_COMBAT`). Those open a 5 second window like the original addon did; using the ability closes it.
  A dodge of a group member's attack on your target counts as well, since the event does not say whose
  attack it was.
- **Either**: both.

Execute and Hammer of Wrath additionally glow while the target is below 20% health, Exorcism while the
target is undead or demon and the spell is off cooldown, Shadow Bolt while Shadow Trance is on you.

The glow is the game's `ActionButtonSpellAlertManager` animation on the default action bars (including
macros that cast the ability) and on Bartender/Dominos buttons through LibActionButton.

## Settings

`/saf` opens Options → AddOns → SpellActivationsForever: detection mode, glow without power, per-ability
switches, debug messages.

Slash commands: `/saf mode usable|events|both`, `/saf on|off <ability>`, `/saf nopower`, `/saf test`
(every tracked ability glows for a moment), `/saf status` (what each ability currently sees), `/saf debug`.

## Development

The logic runs outside the game against a small WoW API stub:

```bash
pip install lupa
python tools/test.py
```

### Releasing

Bump the CHANGELOG section and the toc version, commit, tag (`git tag v0.1.0 && git push origin master --tags`).
The Release workflow attaches `SpellActivationsForever-0.1.0.zip` (top-level `SpellActivationsForever/`
folder) to the GitHub release, and CurseForge packages the tag through its automatic packaging (`.pkgmeta`)
once the repository has the webhook (`https://www.curseforge.com/api/projects/<projectID>/package?token=<token>`,
repository Settings → Webhooks). `python tools/package.py` builds the same zip locally into `dist/`.
