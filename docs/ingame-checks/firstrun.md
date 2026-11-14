# In-game checks: first-run setup and quest preferences (FirstRun.lua)

None of this has been run in the game client. Tick each off in the game. To see the panel as a
new character does, log in on a character that has never had the addon, or run `/lvl setup`.

## The panel

- [ ] First login of a character with the addon: a small dark panel in the middle of the
      screen, titled "Welcome to Leveling" in the addon's yellow, with two tick boxes
      ("Include dungeon quests", "Include group quests"), both empty, one dimmed line "Drag the
      window where you want it." and a "Start" button. No error on login.
- [ ] `CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")` and
      `CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")` exist on this client and
      look right at 24 x 24 and 90 x 22. If a tick box draws a label of its own beside ours,
      report it.
- [ ] `GetChecked()` returns true or false (or 1 or nil) and `SetChecked(false)` empties the
      box.
- [ ] The text fits the panel (260 x 150) at the default UI scale and at the smallest and
      largest; nothing overlaps the button.
- [ ] No line "is on. Drag the window to move it." in chat at a first login: the panel
      replaces it.
- [ ] While the panel is open the guide window and the arrow are on screen with real
      suggestions, and the window can be dragged; the panel does not cover it at its starting
      place (top right). The arrow cannot be dragged (it has no dragging yet), which is why the
      line does not mention it.
- [ ] The panel sits above the window and the arrow (frame strata `DIALOG`) and below the
      game's own menus. Clicks on it do not reach the world behind.
- [ ] Ticking a box changes the suggestions in the window behind it within a moment, with no
      reload.
- [ ] "Start" closes it; the first suggestion is already there. After `/reload` and after
      logging out and in again it does not come back.
- [ ] Logging out without pressing "Start" shows it again at the next login.
- [ ] Another character on the same account gets the panel once too, with both boxes empty
      whatever the first character chose.
- [ ] A character at a high level with a long quest history gets it the same way, and the
      window shows suggestions for where it stands.
- [ ] With the window hidden (`/lvl hide`) on another character before, a new character's
      panel brings the window back. With the window locked ("Lock position"), the panel's line
      still says to drag it: is that worth a different line?
- [ ] In combat and in an instance at first login (log out inside a dungeon, install the
      addon, log in): the panel appears without an "action blocked" message.
- [ ] `/lvl setup` shows the panel again with the boxes as the settings are now.

## The two switches

- [ ] With both off, no dungeon, group, raid or PvP quest is suggested. Stand where a group
      quest is offered at the character's level (a "WANTED" poster is a good one) to see it
      left out.
- [ ] "Include group quests" on: that quest is suggested within a moment. Off again: it goes.
      The same with a dungeon quest (one that sends the character into an instance) and
      "Include dungeon quests".
- [ ] Raid and PvP quests are never suggested, with both switches on.
- [ ] A change keeps everything else: finished steps stay above the current one, the count on
      the current step is unchanged, and skipped quests stay skipped (`/lvl skipped`).
- [ ] The same two switches are on the settings page (`/lvl settings`), as "Include dungeon
      quests" and "Include group quests", and they follow the panel and the commands. If the
      page is open while `/lvl dungeons` is typed, does its tick box follow at once, or only
      when the page is opened again?
- [ ] `/lvl dungeons` and `/lvl groups` flip a switch and say what it is now; `on` and `off`
      set it. `/lvl set dungeons` and `/lvl set groups` do the same.
- [ ] The choice is per character: set it differently on two characters, log between them,
      and each has its own on the settings page and in the suggestions.
- [ ] `/lvl debug` after flipping a switch several times quickly: one "planner pass", not one
      per click.
