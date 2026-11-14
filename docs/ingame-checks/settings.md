# In-game checks: every setting applies at once (#24)

None of this has been run in the game client yet. Tick each off in the game. The page itself
(that it opens, its first eight controls, the sliders) is in `window.md`; this list is about
what #24 added: every feature's setting on the page, and each one taking effect with no
`/reload`.

## The page

- [ ] After the Reset position button the page shows, in this order: Drowning alarm, Sell
      junk, Party version check, Announce level-ups, Share quests, Verbose output, Quest item
      hint, Accept quests automatically, Hand in quests automatically, Mark quest rewards,
      Quest item button; then whatever later features added.
- [ ] "Announce level-ups" is a dropdown offering Off, Party and Guild
      (`Settings.CreateDropdown(category, setting, optionsFunction, tooltip)` with
      `Settings.CreateControlTextContainer()`, `:Add(value, label)`, `:GetData()`). If the
      whole page is missing since this change, that call differs in this client: note the
      error. If only the dropdown is missing, the client has neither `CreateDropdown` nor
      `CreateDropDown`; `/lvl set partyAnnounce guild` still works.
- [ ] Each new control shows its tooltip on hover.
- [ ] The first login after this change: the three party settings are at their defaults
      (version check on, the other two off). They moved from `party = { ... }` to
      `partyVersion`, `partyAnnounce` and `partyShare` in the saved settings; a `party` table
      saved by an earlier copy is ignored.

## The command and the page agree

- [ ] With the page open, each of these changes the control on the page as well (close and
      reopen the page if it does not redraw by itself, and note that): `/lvl arrow`,
      `/lvl pin`, `/lvl lock`, `/lvl rows 5`, `/lvl scale 1.2`, `/lvl drown`, `/lvl junk`,
      `/lvl verbose`, `/lvl party version`, `/lvl party share`, `/lvl party announce guild`.
- [ ] `/lvl set` lists every setting on the page with its value, and `/lvl set partyAnnounce
      loudly` answers with the three values it takes.

## At once, with no reload

For each line: change the setting on the page (not with `/reload`) and look right away.

- [ ] Scale, Background opacity, Steps in view: the window follows while the slider moves.
- [ ] Arrow, Map pin, Quest item button: each disappears and comes back at once. In combat
      the item button waits for the end of the fight (it is a secure frame); nothing prints a
      "blocked action" message.
- [ ] Dim in combat, changed during a fight: the window unfolds to all its rows at full
      brightness, and folds again when switched back on. The arrow dims and brightens with it.
- [ ] Lock position: the window cannot be dragged, then can.
- [ ] Drowning alarm: switched off under water before the last 15 seconds, no sound; switched
      on again before them, the sound comes.
- [ ] Sell junk, with a vendor window open and greys in the bags: switching it on sells them
      without closing the window; switching it off part-way stops, and the chat line counts
      only what was sold.
- [ ] Party version check, in a party with another copy of the addon: switching it on sends
      our version within a second or so (and not twice within 10 seconds); switched off,
      nothing is sent on the next join.
- [ ] Announce level-ups and Share quests: the next level-up and the next accepted quest
      follow the new value.
- [ ] Verbose output: grey lines start and stop with the switch.
- [ ] Quest item hint: the next item tooltip has, or lacks, its "Needed for" line.
- [ ] Accept quests automatically, switched on while a suggested quest's offer is open: the
      quest is accepted at once. Hand in quests automatically, switched on at an open reward
      window with no choice of rewards: handed in at once. Check that this is not surprising
      in play; if it is, the fix is one `onChange` in `Automation.lua`.
- [ ] Mark quest rewards, at an open choice of rewards: the coin and the arrow go and come
      back.
- [ ] After every one of these, the steps in the window are as they were: the same finished
      steps above the current one, the same skipped quests, the same counts.

## Preferences and the planner

- [ ] With the quest data loaded, changing a preference about which quests to suggest (the
      dungeon and group quest switches of #20, once they are in) changes the list within a
      moment, and finished steps, skipped quests and counts stay.
- [ ] `/lvl debug` before and after flipping one switch several times quickly: "planner pass"
      ran once for the burst (its time changes once), and the frame rate does not dip.

## Loose ends fixed with #24

- [ ] Quest progress still ticks steps off (accept, kill and loot counts, hand-in) now that
      only `Steps.lua` listens to the quest events. A hand-in of a quest whose hand-in step is
      not among the rows in view is still gone from the list after the next pass.
- [ ] A "go" step (an escort, an exploration) shows no "0/1" beside its name.
- [ ] Standing at a "go" step's point ticks it, and it is not listed a second time below; the
      quest's hand-in appears only when the quest log calls the objective finished.
- [ ] The arrow turns into the ring at the same distance at which a "go" step is ticked (8
      yards).
- [ ] The entry in the addon list by the minimap still only hides and shows the window. It was
      left as it is: opening the settings page from it means choosing which click does what.
