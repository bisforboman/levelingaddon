# In-game checks: planner (issue #3)

None of this has been run in the game client. The planner is built against the documented
classic and retail addon API, with a fallback wherever the two differ; the list below is what
only the client can confirm. Build the data first (README, "Building the quest data").
`/lvl plan` prints what the last pass saw and `/lvl debug` prints the timings.

## Loading the data

- [ ] The addon loads with the `Data\data.xml` line in the TOC: no Lua error, no "has no quest
      data" line in chat, and the window shows steps.
- [ ] Logging in does not hitch noticeably. Note the memory figure from `/lvl debug` (issue #2):
      the planner's two tables are about 8 MB in Lua 5.1, the six plain tables about 23 MB more.
- [ ] If the client refuses `data.xml`, list the Lua files in the TOC directly and say so in #3.

## Reading the character

- [ ] `/lvl plan`, first line: the level, race, class and side are right. Race and class must
      be the client's tokens in upper case (`HUMAN`, `NIGHTELF`, `SCOURGE` for undead,
      `WARRIOR`). Note what a Skyborne character prints: the data calls those races
      `SKYBORNEALLIANCE` and `SKYBORNEHORDE`, which is a guess at the client's token.
- [ ] `/lvl plan`, third line, says completed quests were "read in one call". If it says "asked
      one by one", neither `C_QuestLog.GetAllCompletedQuestIDs` nor `GetQuestsCompleted` exists
      on this client: say so in #3.
- [ ] `/lvl debug` shows "completed quests read". Note the time on the character with the most
      finished quests: this is the open question of #3 (how expensive is that call).
- [ ] The same line says the quest log is "listed" (`C_QuestLog.GetNumQuestLogEntries` with
      `GetInfo`, or `GetNumQuestLogEntries` with `GetQuestLogTitle`).
- [ ] On a character with many completed quests, no quest it has already done is suggested.
- [ ] A quest handed in disappears from the suggestions at once and stays gone after `/reload`.

## Zones and neighbours

- [ ] `/lvl plan`, second line: the zone and its map id are right, in a starting area
      (Northshire, for one) as well as in the open zone. A wrong or missing zone means
      `C_Map.GetBestMapForUnit` returns a map the data does not know and `C_Map.GetMapInfo`
      does not lead up to one that it does.
- [ ] The zones named as "next to" are the zones around it, for three or four zones including a
      city. They come from the client's map rectangles (`C_Map.GetWorldPosFromMapPos`); a zone
      that only touches a corner may be listed, a zone across the continent must not be.
- [ ] Standing near a zone border, a step in the neighbouring zone gets a sensible distance on
      the arrow.
- [ ] Inside a dungeon the steps stay as they were, and come back to life outside.
- [ ] At level 30 in a starting zone the steps point into a zone that fits level 30.

## Steps

- [ ] A fresh human in Northshire gets "Deputy Willem" first, and the arrow points at him.
- [ ] Accepting a quest, finishing an objective, handing a quest in, levelling up and crossing
      into another zone each change the steps within about a second (`QUEST_ACCEPTED`,
      `QUEST_REMOVED`, `QUEST_TURNED_IN`, `QUEST_LOG_UPDATE`, `PLAYER_LEVEL_UP`,
      `ZONE_CHANGED_NEW_AREA`).
- [ ] A kill or loot step shows the right count and points at the right creature, for a quest
      with two or more objectives too. Objectives are matched by type and order: the game's
      `objective.type` must be `monster`, `item`, `object` or `event`. A step that counts one
      objective while pointing at another means that order differs on this client.
- [ ] A quest that needs a profession or a reputation is offered only when the character has it
      (`GetProfessions` with `GetProfessionInfo`; `C_Reputation.GetFactionDataByID` or
      `GetFactionInfoByID`). Where the client has no profession call, such quests are never
      offered.
- [ ] No dungeon, raid, battleground or elite ("group") quest is offered. Note any that slips
      through, and any ordinary quest that is wrongly left out.
- [ ] `/lvl debug` shows "planner pass". Note the time in a quiet zone and in a capital city
      (issue #2).
- [ ] The order feels like a route: nearby pick-ups together, then objectives, then hand-ins.
      The weights at the top of `Planner.lua` are first guesses; note what feels wrong.
- [ ] A step of kind "go" (an escort, an exploration) has no icon yet (the window is #4's);
      note whether the row is readable without one.

## Skips

- [ ] The cross on a row skips that quest: the row stays, crossed out, and nothing else of the
      quest is suggested.
- [ ] After `/reload` and after a relog the quest is still left out; another character is not
      affected.
- [ ] The arrow on the crossed-out row brings the quest back. `/lvl skipped` lists skipped
      quests by number and name; `/lvl unskip NUMBER` and `/lvl unskip all` bring them back.
