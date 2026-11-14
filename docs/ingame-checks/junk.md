# In-game checks: junk selling (Junk.lua)

None of this has been run in the game client yet. Tick each off in the game. Selling is off
until `/lvl junk` turns it on.

- [ ] With it off, opening a vendor sells nothing and prints nothing.
- [ ] `/lvl junk` prints "on", and the setting survives `/reload` (account-wide).
- [ ] At a vendor, every grey item in the backpack and the four bags is sold, and one line
      gives the count and the total. The total matches the change in money.
- [ ] The API exists under these names: `C_Container.GetContainerNumSlots`,
      `C_Container.GetContainerItemInfo` (a table with `itemID`, `quality`, `stackCount`,
      `hasNoValue`, `isLocked`) and `C_Container.UseContainerItem`; `C_Item.GetItemInfo` or
      `GetItemInfo` with the sell price as the 11th value and the item class as the 12th
      (12 for quest items); the events `MERCHANT_SHOW` and `MERCHANT_CLOSED`. If
      `C_Container` is missing, nothing is sold and nothing is printed.
- [ ] `UseContainerItem` called from the addon sells at a vendor (it is not blocked as a
      protected action), and never uses or equips an item instead.
- [ ] With a full set of bags of greys, every one is sold at one sale per 0.05 s
      (`SELL_EVERY`). If the client drops sales, raise the number.
- [ ] Closing the vendor window part-way stops the selling, and the line gives what was sold
      until then.
- [ ] A grey item that a quest in the log or a later quest needs is kept. The same grey is
      sold once those quests are handed in. (Needs the quest data loaded, issue #3.)
- [ ] A grey with no sell price is left alone, with no error.
- [ ] With a third-party bag addon enabled, selling works the same.
- [ ] A reagent bag or a keyring, if this client has them (bag ids above 4), is not touched.
- [ ] Only the last 12 items sold can be bought back from the vendor: decide whether that
      matters for greys.
- [ ] `/lvl debug` after the first vendor visit with a grey the quest data knows: the line
      "junk index" gives the one-off cost of building the item-to-quest index.

## The "sell" step (bag space)

A row in the guide window that points at a vendor, added by the planner when the bags run low.
Nothing here has been run in the game either.

- [ ] `C_Container.GetContainerNumFreeSlots(bag)` exists and returns the free slots and the
      bag's family (0 for an ordinary bag); a quiver, a soul bag or a herb bag is not counted.
- [ ] `BAG_UPDATE_DELAYED` fires on this client after the bags change. Without it the step
      neither appears nor ends by itself.
- [ ] With 3 free slots or fewer (`LOW_SLOTS` in `Junk.lua`) and a vendor within 200 yards of
      the straight line to the current step (`SIDE_YARDS` in `Planner.lua`), a row with the
      vendor's name appears right under the current step. Note whether 3 is the right number.
- [ ] With no vendor near the way, no row appears until the bags are full.
- [ ] With no free slot at all, the vendor row is the current step, the arrow and the pin point
      at the vendor, and the vendor is the nearest one in this zone or the zones next to it.
- [ ] The vendor named is one the character can use (not the other faction's), stands where the
      arrow says, and really buys items. The data only knows vendors that some quest refers to
      (about 688), so note places where a much nearer vendor was ignored.
- [ ] The row's icon (`Interface\Cursor\Buy`, the game's vendor cursor) shows and reads as
      "sell".
- [ ] Opening the vendor's window ticks the row off. If the bags are still low after the visit,
      the row does not come back until there has been room again.
- [ ] Making room another way (deleting or using items) ticks the row off as well.
- [ ] The cross on the row skips it: it stays crossed out, and no other vendor row appears. Its
      restore arrow brings it back. Once there is room again the skip is forgotten, and the row
      appears again the next time the bags run low.
- [ ] `/lvl skipped` lists the skipped vendor stop as quest "0 ?": note whether that needs a
      proper name.
- [ ] The row appears and leaves on bag changes only; the planner does not run on movement, so
      on a long walk a vendor that comes near the way is only noticed at the next pass. Note how
      that feels.
- [ ] `/lvl debug` after the first low-bag pass: "vendors read" gives the one-off cost of
      reading the vendors from the NPC table.
