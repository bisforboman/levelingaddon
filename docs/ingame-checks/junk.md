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
