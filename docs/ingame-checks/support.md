# In-game checks: support tools (report, events, verbose)

None of this has been run in the game client yet. Tick each off in the game.

## `/lvl report`

- [ ] The window opens without an error. It uses two of the game's templates,
      `UIPanelCloseButton` and `UIPanelScrollFrameTemplate`, and the font `ChatFontNormal`; a
      missing one shows as an error on the first `/lvl report`.
- [ ] The text is selected when the window opens, Ctrl+C copies it, and it pastes complete
      into another program (all lines, down to "recent errors").
- [ ] A long report scrolls with the mouse wheel and the scroll bar.
- [ ] Escape and the close button both close it; it can be dragged; a second `/lvl report`
      shows fresh text in the same window.
- [ ] The first line after the title shows the client version (`GetBuildInfo`), and the
      interface number matches the TOC (16001).
- [ ] Level, class, zone, sub-zone and position are right. Inside an instance the position
      line says "no position" and nothing fails.
- [ ] Read the whole text once for anything personal: there must be no character name, realm,
      guild or account name. Check the settings lines especially, since they print whatever
      features have saved.
- [ ] "data:" shows the source commit and counts once the data files load (#3), and "not
      loaded" before that.
- [ ] After an error in a task or a job (there is none to provoke by hand; see whether one
      ever appears), it is listed under "recent errors".

## Events

- [ ] Which registry is in use: `/run print(LevelingAddonEvents == EventRegistry)` prints
      `true` if the client has the game's `EventRegistry`, `false` if the stand-in is used.
- [ ] With `/lvl verbose` on, `LevelingAddon.StepShown 1 table: ...` appears once at login or
      `/reload`, and again only when the current step changes: not on `/lvl rows 5`, not when
      an objective count goes up.
- [ ] Accepting a quest prints `LevelingAddon.QuestAccepted` with the quest's id, not a small
      number. (`QUEST_ACCEPTED` carries the quest log index first in the classic client and
      the id alone in the modern one; the code takes the second argument when there is one.)
- [ ] Handing a quest in prints `LevelingAddon.QuestTurnedIn` with the quest's id.
- [ ] No line "... failed:" follows an event while verbose. One would mean the client's
      `EventRegistry` refuses events it does not know.
- [ ] A listener receives the arguments in the documented order, after its owner:
      `/run LevelingAddonEvents:RegisterCallback("LevelingAddon.StepShown", function(_, i, s) print(i, s.kind, s.questID) end, "check")`
      then skip a step.

## Verbose

- [ ] `/lvl verbose` says "on", then "off"; the setting survives `/reload`.
- [ ] With it off, nothing grey is printed.
