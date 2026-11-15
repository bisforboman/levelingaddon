# In-game checks: guide window and settings page

None of this has been run in the game client yet. Tick each off in the game.

## Settings page

- [ ] The addon loads without an error and "Leveling Addon" is listed under AddOns in the
      game's settings panel. If it is missing, the client's `Settings` API differs from the one
      built against (`Settings.RegisterVerticalLayoutCategory`, `RegisterProxySetting` with
      the arguments category, variable, type, name, default, get, set; `CreateSlider`,
      `CreateCheckbox`, `CreateSettingsButtonInitializer`, `RegisterAddOnCategory`): note
      which call fails. `/lvl set` keeps working either way.
- [ ] `/lvl settings` opens that page (`Settings.OpenToCategory(category:GetID())`), also in
      combat, without a "blocked action" message.
- [ ] The page shows, in this order: Scale, Background opacity, Steps in view, Arrow, Map pin,
      Dim in combat, Lock position, and a Reset position button.
- [ ] The sliders show a value beside them: a percentage for scale and opacity, a whole number
      for steps in view (`MinimalSliderWithSteppersMixin.Label.Right`).
- [ ] Dragging each slider changes the window while dragging, with no reload: size, backplate
      darkness, number of rows.
- [ ] The Arrow switch hides and shows the arrow at once.
- [ ] The page's "Defaults" button puts every setting back, and the window follows.
- [ ] After `/lvl scale 1.5` or `/lvl set rows 5`, reopening the page shows the new value.
- [ ] After `/reload`, every setting is as it was left.

## No background

- [ ] On a fresh install (or after the page's "Defaults") nothing is drawn behind the list:
      Background opacity is 0%. A saved opacity from before this change is kept.
- [ ] The text and the "!" and "?" marks have a dark outline (`SetFont(file, size, "OUTLINE")`
      on the game's font objects) and are readable over grass, bright sky and snow. Note where
      they are not, and whether the icons (which have no outline) get lost.
- [ ] The current step has the yellow bar on its left and larger, brighter text, and no band
      behind it.
- [ ] With the pointer on a row, that row gets a faint highlight and its control: the cross on
      a pending step, the restore arrow on a skipped one. Nothing else appears, and both go
      when the pointer leaves.
- [ ] The empty space between the rows' text still takes the mouse wheel and the drag.

## Lock and position

- [ ] With Lock position on, or after `/lvl lock`, dragging a row does not move the window;
      the cross and the restore arrow still work.
- [ ] Unlocked, the window drags from any row, and the place survives `/reload`.
- [ ] Reset position puts the window back at the right edge, left of the objective tracker.

## Combat

- [ ] With Dim in combat on, entering combat folds the window to the current step at 40%.
- [ ] With it off, the window stays whole in combat. Switching it while in combat applies at
      once.

## Dungeon pause mark

- [ ] Entering a dungeon shrinks the window to a pause mark (two bars, on a small dark
      square if the background is turned on) and prints one line in chat; leaving brings the list back (`IsInInstance()` read at
      `PLAYER_ENTERING_WORLD`).
- [ ] The square stays where the window's anchored corner was, and can be dragged.
- [ ] Note what happens in a battleground or other instance kind: it pauses there too.

## Icons

- [ ] A "go" step (an escort or an exploration) shows the flight cursor's winged boot as its
      icon (`Interface\\Cursor\\Taxi`), not an empty or green square.

## Cost

- [ ] `/lvl debug` while questing: the loop's time per frame is no higher than before this
      change. Progress on one objective redraws one row; this is checked by the tests, and has
      no visible sign in the game.
