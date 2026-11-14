# In-game checks: steps that complete themselves (issue #7)

None of this has been run in the game client. `Steps.lua` is built against the documented
classic and retail addon API; the list below is what only the client can confirm.

## Each kind

- [ ] Accepting a quest ticks its "!" row within about a second, and abandoning the quest
      brings the row back (`QUEST_ACCEPTED`, `QUEST_REMOVED`, `C_QuestLog.IsOnQuest`).
- [ ] Handing a quest in ticks its "?" row at once, and it stays ticked ten seconds later and
      after `/reload` (`QUEST_TURNED_IN` carries the quest id first;
      `C_QuestLog.IsQuestFlaggedCompleted`).
- [ ] A kill or loot row counts up with each kill or item and is ticked on the last one
      (`QUEST_LOG_UPDATE`; `C_QuestLog.GetQuestObjectives` gives `finished`, `numFulfilled`
      and `numRequired` per objective).
- [ ] A "go" row (an exploration quest, an escort) is ticked on walking up to its point with
      the quest in the log, stays ticked after walking on, and is not ticked without the
      quest. Note whether 8 yards is the right radius: too small means running past it does
      not count.
- [ ] `UnitPosition("player")` returns world coordinates outdoors, and its fourth value equals
      the first value of `C_Map.GetWorldPosFromMapPos` for a point in the same zone. If not,
      no "go" row is ever ticked by position.
- [ ] An exploration quest's "go" row is ticked when the quest log marks the objective
      finished, even from further away than 8 yards.

## Several objectives

- [ ] With a quest that has two or more objectives, each row shows the count of its own
      objective, and finishing one objective ticks only its row.
- [ ] A "go" row with a count shows it as "0/1": note whether that reads well (the window is
      #4's).

## The grace period

- [ ] No row flickers back to open right after accepting or handing in. If one does, the quest
      log is more than 3 seconds behind its event on this client: say so in #7.
- [ ] Accepting a quest from an item, a shared quest and an automatically accepted quest each
      tick the row (`QUEST_ACCEPTED` carries the quest id alone, or the log index first).

## Any character state

- [ ] Logging in with quests already in the log or handed in: no row asks for something the
      character has done.
- [ ] Finishing several things before their rows are current (an objective two rows down, a
      quest picked up early): the rows are ticked as they are, and the current step moves past
      them without stopping.
- [ ] Scrolling far down the list shows counts from the last planner pass, not live ones; note
      whether that is ever noticeable.

## Cost

- [ ] `/lvl debug` while a "go" row is in view, standing still and moving: the loop's time per
      frame stays in line with the arrow's alone (the position is looked at twice a second).
- [ ] In a busy fight (many `QUEST_LOG_UPDATE`s) there is no hitch, and with only "!" and "?"
      rows in view kills do not change anything in the window.
