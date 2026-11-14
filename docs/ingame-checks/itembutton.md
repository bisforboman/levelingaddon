# In-game checks: quest item button (ItemButton.lua)

None of this has been run in the game client. Tick each off in the game. The button is on by
default; "Quest item button" on the settings page or `/lvl set itemButton` switches it. It
needs the quest data loaded, except where the quest log itself names the item.

This is the open question of issue #11: how a protected item button behaves on the Forever
client. The code follows the documented rules for secure buttons; the first two sections are
the ones that answer the question.

## The secure button

- [ ] The addon loads without an error, and `/dump LevelingAddonItemButton:IsProtected()`
      prints `true` (the template `SecureActionButtonTemplate` exists and made the button
      protected).
- [ ] On a step with a usable quest item in the bags, a 36-pixel button with the item's icon
      is shown left of the guide window's starting place. A left click uses the item.
- [ ] The click works whichever way "cast on key down" is set (`/dump
      GetCVar("ActionButtonUseKeyDown")`): the button is registered for `LeftButtonUp` and
      `LeftButtonDown`. If the item is used twice per click, or not at all, note the CVar's
      value.
- [ ] The attribute `item` set to `"item:<id>"` uses the item from the bags. If nothing
      happens on a click, try `/run LevelingAddonItemButton:SetAttribute("item", "<the item's
      name>")` out of combat and click again: if that works, the client wants a name there.
- [ ] An item that is used on a target or on the ground (a targeting circle) works from the
      button as it does from the bags.
- [ ] A right click does nothing.

## Combat

- [ ] No "action blocked" or "interface action failed because of an addon" message in any of
      these, done while in combat: the step changes; the item is used up or looted;
      `/lvl set itemButton`; `/lvl hide` and `/lvl show`; `/lvl reset`; trying to drag the
      button with the right mouse button. Run `/console taintLog 1` first and look in
      `Logs/taint.log` afterwards for `LevelingAddon`.
- [ ] In each of those cases the button stays exactly as it was until combat ends, and is
      brought up to date the moment it ends (`PLAYER_REGEN_ENABLED`): shown, hidden, pointed
      at the new step's item, or back at its starting place.
- [ ] `InCombatLockdown()` is already false when `PLAYER_REGEN_ENABLED` arrives. If the button
      is still stale after combat until the next bag change, it is not: report it.
- [ ] Clicking the button and pressing its key use the item in combat.
- [ ] Start dragging the button and get attacked while holding it: the button stops where it
      is (`PLAYER_REGEN_DISABLED` still allows `StopMovingOrSizing`), with no blocked-action
      message, and the place is kept.
- [ ] `/reload` in combat with a usable item for the current step: is the button there after
      loading, or only after combat ends? Either is acceptable; a blocked-action message is
      not (it would mean `InCombatLockdown()` is false at login while the lockdown is on).
- [ ] The guide window still folds and fades in combat with the button on screen: the button
      is its own frame, anchored to the screen.

## Which item

These calls decide it; check each exists (`/dump` the name) and returns what the code expects.

- [ ] `C_QuestLog.GetLogIndexForQuestID(questID)` gives the quest's place in the log, and
      `GetQuestLogSpecialItemInfo(index)` returns the item's link first, for a quest that
      shows an item button in the game's own objective tracker. Where the second function is
      missing, only the quest data below is used: note that it is.
- [ ] `C_Item.GetItemSpell(itemID)` returns something for an item with a "Use:" line and nil
      for one without, also for an item the client has not shown this session.
- [ ] `C_Item.GetItemCount(itemID)` counts an equipped item too (a quest trinket or cloak that
      must be worn and used): the button shows while it is equipped.
- [ ] A quest whose item the quest log names: the button shows that item.
- [ ] A quest whose item only the data knows (`sourceItemId`, then `requiredSourceItems`, then
      the item objectives, first match with a use effect): the button shows it. Note any quest
      where it picks the wrong item, such as food among the items to collect.
- [ ] No button on a step whose quest has no usable item, on a hand-in step, or once the item
      is used up; the button comes back when the item is looted again (0.2 s after
      `BAG_UPDATE`).
- [ ] An accept step for a quest started from an item in the bags shows no button: the data's
      step does not name that item. Note whether that is missed in play.

## Cooldown and tooltip

- [ ] Using the item draws its cooldown sweep on the button (`C_Container.GetItemCooldown`,
      `CooldownFrameTemplate`, on `BAG_UPDATE_COOLDOWN`), and the sweep ends when the cooldown
      does.
- [ ] No error from the cooldown in combat: the two numbers are handed to
      `Cooldown:SetCooldown` untouched, in case the client makes them secret values there.
- [ ] Hovering shows the item's own tooltip (`GameTooltip:SetItemByID`), with "Drag with the
      right mouse button to move." as its last line, and the "Needed for:" hint above it.

## Key binding

- [ ] The game's key bindings screen lists "Leveling Addon" with one entry, "Use the step's
      quest item". If it is missing, the client did not load `Bindings.xml` from the addon's
      folder by itself: add the line `Bindings.xml` to the TOC and try again, and report
      which it was.
- [ ] A key set there uses the item, in and out of combat, and does nothing while the button
      is hidden.
- [ ] The binding survives `/reload` and a restart.

## Position and setting

- [ ] Dragging with the right button moves the button, out of combat; it cannot leave the
      screen; the place survives `/reload` (`SetUserPlaced(false)`, our own saved point).
- [ ] `/lvl reset` and "Reset position" on the settings page put the button back beside the
      window's starting place, as well as the window.
- [ ] The starting place (478 from the right edge, 190 from the top) is clear of the window at
      the scales tried, and not over another part of the game's interface.
- [ ] Unticking "Quest item button" hides it at once out of combat; the choice survives
      `/reload`.
- [ ] `/lvl debug` with the button on and off: no difference while idle or moving. It has no
      update of its own.
