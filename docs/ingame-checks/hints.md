# In-game checks: item tooltip hint (Hints.lua)

None of this has been run in the game client. Tick each off in the game. The hint is on by
default; "Quest item hint" on the settings page or `/lvl set itemHint` switches it. It needs the
quest data loaded.

## Which hook this client has

- [ ] Run `/dump TooltipDataProcessor ~= nil, GameTooltip:HasScript("OnTooltipSetItem")`. The
      addon uses `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)` when
      the first is true, and otherwise hooks the script `OnTooltipSetItem` on `GameTooltip` and
      `ItemRefTooltip`. If both are false, no line can appear: report it.
- [ ] On the newer hook, the callback gets `(tooltip, data)` with the item's id as `data.id`.
      On the older one, `GameTooltip:GetItem()` returns the name and the item link.
- [ ] No error on login, and none when hovering items in the bags, on the character sheet, at a
      vendor, in a loot window and in chat links.

## The line

- [ ] Hover an item that a quest in the log needs: the last line of the tooltip is
      "Needed for: <quest name>", and the tooltip has grown to fit it (the line is not cut off
      and does not overlap the border).
- [ ] The same on an item a quest not yet picked up needs, and on an item that starts a quest.
- [ ] An item several quests need: "Needed for: <name> and N more", on one line, naming a quest
      from the log when one of them is there.
- [ ] Click an item link in chat: the tooltip that stays open (`ItemRefTooltip`) has the line.
- [ ] The comparison tooltips beside an equipment tooltip do not have it.
- [ ] Once every quest that needs the item is handed in, the line is gone.
- [ ] An item only the other faction's quests need has no line. `UnitFactionGroup("player")`
      returns "Alliance" or "Horde" in English on every client language.
- [ ] The line appears once per tooltip. On the older hook a recipe's tooltip sets an item
      twice (the recipe and what it makes): if a recipe a quest needs shows the line twice,
      report it.
- [ ] The line does not flicker or pile up while the tooltip refreshes (hold the mouse over an
      item with a cooldown for a few seconds).
- [ ] Is the default text colour right for the line, or should it stand out more?

## Setting and cost

- [ ] Unticking "Quest item hint" removes the line from the next tooltip, with no reload, and
      the choice survives `/reload`.
- [ ] Hovering items in combat, and buying, selling and using items afterwards, raises no
      "action blocked" message (the addon only calls `AddLine`).
- [ ] `/lvl debug` after hovering the first item the quest data knows: "junk index" is the
      one-off cost of the item-to-quest index, shared with junk selling. Hovering more items
      does not add to it, and moving the mouse across a full bag does not hitch.
