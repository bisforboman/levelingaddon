# In-game checks: side tasks (issue #8)

None of this has been run in the game client. A side task is not a new element: it is a kill or
collect row placed right under the current step by the planner, when the quest is already in
the log and one of the objective's points in the data lies within 200 yards (`SIDE_YARDS` at the
top of `Planner.lua`) of the straight line from the character to the current step.

## Placement

- [ ] With a kill quest in the log, standing among its creatures while the current step is a
      pick-up or hand-in close by: the kill row is the row right under the current step.
- [ ] The same quest's row is not right under the current step when its creatures are in
      another part of the zone; it sits further down, or is not among the steps at all.
- [ ] Walking to a current step that is far away, past creatures of a quest in the log: the row
      comes up under the current step while they are near the way, without anything else
      having changed. The planner runs on quest events, level up and zone change, not on
      movement, so note how stale this feels on a long walk.
- [ ] The data keeps a few points per creature or item and zone, not every spawn. Note
      objectives that were plainly on the way and were not listed, and rows listed for
      creatures that were not really there: both say whether 200 yards is right.
- [ ] With several side tasks at once, note whether they push the next real step out of the
      window at its usual number of rows.

## Behaviour

- [ ] The count on a side task row ticks with each kill or pick-up, like any other row.
- [ ] The arrow keeps pointing at the current step, not at the side task.
- [ ] A finished side task shows as done and the next pass moves on without it.
- [ ] After the current step is done and the next one lies elsewhere, the row leaves its place
      under the current step and is ranked like any other step.
- [ ] A current step with other things to do at the same spot (a hand-in and a pick-up at one
      NPC): the side task row sits between them. Note whether that reads badly.
- [ ] `/lvl debug`: "planner pass" takes no noticeably longer than before with five or more
      kill and collect quests in the log (issue #2).
