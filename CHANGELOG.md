# Changelog

## 0.3.0 — 2026-11-25

- Action bars no longer break (bars disappearing, missing tooltips, wrong cooldowns): the glow on action
  buttons is now the addon's own frame, like on the Cooldown Manager icons, and the game's alert manager is
  never called from the addon, which tainted the buttons. Thanks to Painwatcher for the patch.
- An ability no longer glows while it is on a cooldown of its own (the global cooldown does not count).
- Victory Rush glows while it is usable.

## 0.2.1 — 2026-10-22

- Icon in the AddOns list (Execute's sword).

## 0.2.0 — 2026-10-21

- The glow also lights the ability's icon in the game's Cooldown Manager (Essential and Utility bars).
  The addon draws its own glow frame on the item instead of using the game's alert manager, so the
  viewer's secure code is not tainted (no "attempt to compare a secret number value" errors).

## 0.1.0 — 2026-10-09

- First version: spell alert glow on the action buttons of Overpower, Revenge, Execute, Riposte,
  Counterattack, Mongoose Bite, Exorcism, Hammer of Wrath and Shadow Bolt (Shadow Trance), driven by the
  server's usable state or by the client's dodge/parry/block events; settings panel and `/saf` commands;
  offline tests.
