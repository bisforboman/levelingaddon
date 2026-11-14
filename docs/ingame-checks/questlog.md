# In-game checks: full quest log (issue #23)

None of this has been run in the game client. The limit is not written into the addon: each
planner pass asks the client. `/lvl plan` prints what it got, on its last line: "N quests in the
log, which holds M."

## The limit and the count

- [ ] `/lvl plan` gives the same two numbers as the quest log's own header ("Quests: N/M").
      This answers the open question of #23: note M in the issue.
- [ ] If it says "holds an unknown number", the client has neither
      `C_QuestLog.GetMaxNumQuestsCanAccept` nor the global `MAX_QUESTS`: say so in #23. Until
      then pick-ups are not held back and no notice is given.
- [ ] If N differs from the header: on the modern log API the addon leaves out entries marked
      `isHidden`, `isTask` or `isBounty` and counts the rest; on the older API it counts every
      entry that is not a header. Note which kind of quest is counted wrongly.
- [ ] Right after accepting a quest that fills the log, the window shows no pick-up step. If one
      lingers until the next quest event, the count lags `QUEST_ACCEPTED` on this client.

## Ranking

- [ ] With a full log the window shows no pick-up steps, and quests ready to hand in come
      first, the nearest first.
- [ ] With one place free there is exactly one pick-up among the steps; with two free, at most
      two. In both cases the hand-ins still come first.
- [ ] With three or more places free the order is the usual one. "Nearly full" is two free
      places (`NEARLY_FULL` at the top of `Planner.lua`), a first guess: note if hand-ins should
      take over earlier or later.

## The notice

- [ ] With a full log, standing where the next step would otherwise be a pick-up, one chat line
      says the log is full and names that quest. If a quest is ready to hand in, the line names
      it and its NPC, and that hand-in is the first step.
- [ ] The line is not repeated while nothing changes: kill something, cross a zone border,
      `/reload` aside. It comes again after the log has had room and filled up, or when the
      hand-in it names changes.
- [ ] "Nearest" hand-in means within the current zone and the zones next to it. Note if the line
      sends the player somewhere that does not feel nearby.
- [ ] With a full log, nothing ready to hand in and a quest in the log that `/lvl abandon`
      would list, the line ends "N quests are not worth keeping: /lvl abandon", with the same N
      as the list shows. With an empty list, or when a hand-in is named, it says nothing about
      abandoning.
- [ ] The line never opens the list and never abandons anything: only `/lvl abandon` and its
      button do.
