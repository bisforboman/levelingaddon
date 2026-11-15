# In-game checks: reward marks (Rewards.lua)

None of this has been run in the game client. It is built against the documented classic and
retail addon API and against Blizzard's UI source for this client (`QuestInfo.lua`, branch
`forever`); only the game can confirm it. Tick each off in the game. The setting is "Mark quest
rewards" on the settings page, or `/lvl set rewardMarks`, on by default.

## What should be seen

- [ ] No error on login, and none when a reward window opens.
- [ ] A quest with a choice of rewards: a gold coin on the top right corner of the icon of the
      reward that sells for most (sell price times count), and a green arrow on the top left
      corner of the icon of the best upgrade. Both can sit on the same reward.
- [ ] Nothing is chosen for the player, and clicking a reward and "Complete Quest" work as
      before, with no "action blocked" message, also in combat.
- [ ] A quest with one reward or none: no badge.
- [ ] Two rewards with the same highest sell value, or rewards no vendor buys: no coin.
- [ ] The badges are 16 units wide: say if they are too small, too large, or cover the count.
- [ ] The badges scroll with the reward buttons and never show outside the quest window.
- [ ] After the window closes, no badge is left on a reward of the next quest window (accepting
      a quest that previews its rewards, or a quest with one reward).
- [ ] With the setting off, no badge; switching it while the window is open applies at once.

## The textures

Both badges use the game's own art. Check which one shows, and that it looks right at this size.

| Badge | First choice | Used when the atlas is missing |
| --- | --- | --- |
| Sells for most | atlas `coin-gold` (the coin of the game's money display) | file `Interface\MoneyFrame\UI-GoldIcon` |
| Upgrade | atlas `bags-greenarrow` (the arrow on bag items that are upgrades) | file `Interface\PetBattles\BattleBar-AbilityBadge-Strong` |

- [ ] `C_Texture.GetAtlasInfo("coin-gold")` and `C_Texture.GetAtlasInfo("bags-greenarrow")` both
      return a table (`/dump C_Texture.GetAtlasInfo("bags-greenarrow")`).
- [ ] If either returns nil, the file named beside it shows instead and is not a green square
      (a missing file).

## The upgrade rule

The arrow is a rough rule, chosen by the owner: item level against what is worn in the same
slot. It knows nothing of stats, armour type or what suits the class.

- [ ] An armour piece with a higher item level than the one worn gets the arrow; a lower or
      equal one does not.
- [ ] A ring or trinket is compared with the weaker of the two worn; an empty slot counts as
      the weakest.
- [ ] A one-hand weapon is compared with the main hand, and with the off hand too only when a
      weapon is held there.
- [ ] A shield or off-hand item gets no arrow while a two-handed weapon is worn.
- [ ] A reward the game shows in red (the class cannot use it) never gets the arrow.
- [ ] Ranged weapons, thrown weapons and relics get no arrow, on purpose: say which slot they go
      in on this client (16 as on retail, or 18 as on classic) so that they can be added.
- [ ] Of several upgrades, the one with the biggest gain in item level has the arrow.

## The calls

- [ ] `GetNumQuestChoices()`, `GetQuestItemLink("choice", i)` and `GetQuestItemInfo("choice", i)`
      (third value: count, fifth: usable by the character) work in the reward window
      (`QUEST_COMPLETE`), and `QUEST_FINISHED` comes when it closes.
- [ ] `C_Item.GetItemInfo(link)`: item level fourth, equip location ninth (`INVTYPE_HEAD` and so
      on), sell price eleventh; nil while the item has not loaded.
- [ ] `C_Item.GetDetailedItemLevelInfo(link)` gives the item level the tooltip shows, for a
      reward and for a worn item (`GetInventoryItemLink("player", slot)`).
- [ ] The reward buttons are `QuestInfoRewardsFrame.RewardButtons`, each with `type == "choice"`,
      `GetID()` equal to the choice's number, and an `Icon`. If no badge ever shows, this is the
      first thing to look at.
- [ ] Right after login, with an empty item cache, open a reward window: the badges appear a
      moment later, when `GET_ITEM_INFO_RECEIVED` or `QUEST_ITEM_UPDATE` arrives. If they never
      do, say so.
- [ ] A choice that is a currency and not an item: no badges at all in that window.
- [ ] `/lvl debug` with no reward window open shows nothing from this feature; it has no task
      on the shared loop.
