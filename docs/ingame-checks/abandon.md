# In-game checks: quests not worth keeping (Abandon.lua, issue #13)

None of this has been run in the game client. Two of the points decide whether the feature
works at all on the Forever client; they come first.

## The two open questions

- [ ] **May addon code abandon quests?** With a quest ticked, press "Abandon N quests". The
      quest leaves the log and chat says "abandoned N quests." a second later. If the client
      refuses, the quest stays, chat says "N still in the quest log: the game did not let the
      addon abandon them", and the game may show its own "action blocked" message: note which,
      in #13. The calls are made straight from the button's click, which is the most a
      protected function can ask for.
- [ ] **Which abandon API is there?** In order of preference the addon uses
      `C_QuestLog.SetSelectedQuest(questID)`, `C_QuestLog.SetAbandonQuest()`,
      `C_QuestLog.AbandonQuest()`; or `GetQuestLogIndexByID(questID)`,
      `SelectQuestLogEntry(index)`, `SetAbandonQuest()`, `AbandonQuest()`. With neither set
      complete it abandons nothing and says the quests are still in the log.
- [ ] **Does the client mark trivial quests itself?** The addon does not ask: "too low level"
      is the planner's own rule, a quest more than 7 levels under the character
      (`LEVELS_BELOW` in `Abandon.lua`, the same number as in `Planner.lua`). Check whether
      `/dump C_QuestLog.IsQuestTrivial(questID)` exists, or whether the quest log greys such
      quests (`GetQuestDifficultyColor`, `GetQuestGreenRange`), and whether a grey quest there
      is the same set as "too low level" here. Note the answer in #13; if the client's marking
      is better, the rule is one function, `tooLow`.

## The list

- [ ] `/lvl abandon` with nothing to list prints "no quest in the log needs abandoning." and
      opens no window.
- [ ] The button "Quests not worth keeping" on the settings page (`/lvl settings`) opens the
      same list, and the list is drawn above the settings panel, not behind it.
- [ ] A quest more than 7 levels under the character is listed as "too low level" and starts
      ticked.
- [ ] The same quest is not listed while it is a prerequisite of a quest still worth doing,
      directly or further up its chain. Pick one from a chain you know.
- [ ] A quest skipped in the guide window is listed as "skipped by you", unticked; after
      `/lvl unskip` it is not listed.
- [ ] A dungeon, raid, group or PvP quest is listed as such, unticked, unless that kind is
      allowed (the switches of #20).
- [ ] A quest ready to hand in is never listed, including one with nothing to collect or kill
      (a delivery): `C_QuestLog.IsComplete(questID)` or `IsQuestComplete(questID)` should say
      so for it. If neither exists, such a quest counts as not finished and a too-low delivery
      is listed: note it.
- [ ] A quest in another zone or on another continent is not listed for that alone.
- [ ] A quest the data does not know (a world event, say) is never listed.
- [ ] The first time the list is opened, `/lvl debug` shows "abandon index": the one-off cost
      of finding each quest's follow-ups.

## The window

- [ ] Dark plate, title in the addon's yellow, one row per quest: tick box, name, reason on the
      right. Long names are cut, not wrapped. The tick is the atlas `common-icon-checkmark`
      and the close cross `common-icon-redx`, as in the guide window.
- [ ] Clicking a row ticks or unticks it, and the button's count follows. With nothing ticked
      the button does nothing.
- [ ] The window can be dragged, the cross and Escape close it, and closing abandons nothing.
- [ ] A full log of listed quests (20 or 25 rows) fits on the screen at the UI scale in use.
- [ ] After abandoning, the guide window's steps no longer name those quests.
- [ ] Abandoning changes which quest is selected in the game's quest log. Note if that is
      noticeable.
- [ ] The result line comes one second after the click (`REPORT_AFTER`). If it says quests are
      still in the log although they left, the client needs longer: raise the number.
