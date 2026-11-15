# In-game checks: the target macro (Target.lua)

None of this has been run in the game client. It is built against the documented classic and
retail rules for macros; what the Forever client allows for targeting and raid markers is the
open question of issue #12, and only the game can answer it. Tick each off in the game.

## The calls

For each, the check is that it exists, does what is said, and raises no "action blocked"
message when the addon calls it out of combat.

- [ ] No error on login, with and without the macro made.
- [ ] `/lvl macro` out of combat: `GetMacroIndexByName("LvlTarget")` is 0 the first time,
      `CreateMacro("LvlTarget", "INV_MISC_QUESTIONMARK", text)` makes a general (account-wide)
      macro, and `PickupMacro("LvlTarget")` puts it on the cursor, ready to drop on a bar.
- [ ] The icon name is accepted without a path, and the button shows the question mark.
- [ ] `GetNumMacros()` returns the number of general macros first, and the limit is
      `MAX_ACCOUNT_MACROS` (120 assumed where the client has no such global). With every
      general slot used, `/lvl macro` says so and makes nothing.
- [ ] `EditMacro("LvlTarget", nil, nil, text)` changes the text and keeps name and icon; the
      button on the bar keeps working after an edit, without being dropped again.
- [ ] `GetMacroBody("LvlTarget")` returns the text as written (the addon compares it to avoid
      writing the same text twice).
- [ ] A macro holds 255 characters. Find a loot step with many droppers (`/lvl verbose` prints
      "target macro: N names did not fit") and check the macro is whole, ending in `/tm 8`.
      If the client counts bytes differently for names with accents, note it.

## The macro's own commands

- [ ] `/cleartarget` clears the target.
- [ ] `/targetexact Name` targets a nearby unit of exactly that name, and with several such
      lines the macro ends on one of the step's creatures when any is near. If the client has
      no `/targetexact`, report it: `/target` is the fallback, which also matches the start of
      longer names.
- [ ] Whether `/targetexact` prefers a living creature over a corpse of the same name. If it
      picks corpses, report it.
- [ ] `/tm 8` puts the skull on the target, alone and in a party, and pressing the key again on
      the same target leaves the skull on (some clients toggle it off). In a raid without
      assist it does nothing and prints no error.
- [ ] With nothing of the step near, pressing the key clears the target, marks nothing, and
      prints no error.
- [ ] A step whose name is not a creature (a quest started from a board or an item): the key
      does nothing harmful.

## Following the step

- [ ] The macro's text changes when the current step changes (accept, turn-in, kill, loot),
      and is empty on a "go" step and at the end of the route. Open the macro window to look.
- [ ] A step change in combat: no "action blocked" message, the text is the old one during the
      fight and the new one right after it (`PLAYER_REGEN_ENABLED`; `InCombatLockdown()` is
      already false when that event arrives).
- [ ] `/lvl macro` in combat only prints that it cannot be done.
- [ ] After `/reload` and after logging in on another character the macro follows that
      character's step.

## Leaving the player's macros alone

- [ ] Before `/lvl macro` has ever been used, no macro appears, on any character.
- [ ] With a macro of your own named `LvlTarget` and none made by the addon, `/lvl macro` says
      so and changes nothing.
- [ ] Delete the addon's macro in the macro window: it does not come back until `/lvl macro`.
