# First session in the game

Nothing in the addon has been run in the game client yet. This page is the order to test in
for the first session: the checks that can stop a whole feature come first, each with the file
that has the full list. Every check here is also in that file; tick it in both, or only there.
About an hour covers sections 1 to 4. Section 5 is for later sessions.

Before you start: build the data and copy the addon (README, "Building the quest data"). Turn on
`/lvl verbose`, and after anything odd run `/lvl report` and paste the report into the issue.
Use a fresh character in a starting zone and a character of level 10 or more who knows a few
flight points.

## 1. Does it load? (5 minutes, `core.md`, `planner.md`)

- [ ] No Lua error at login, and `/lvl help` lists the commands. If there is an error, stop here
      and paste it into #2. Nothing below can be checked until this works.
- [ ] No line saying the addon "has no quest data". If there is one, the client refused
      `Data\data.xml`: see `planner.md`.
- [ ] `/lvl debug`: note the memory figure after login in #1 and #2. The data alone measured
      22.3 MB in stock Lua 5.1 after #85; the game's figure includes the addon's code too.
- [ ] `/lvl plan`, first line: level, race, class and side are right (`planner.md`).

## 2. The client calls that decide whole features (20 minutes)

These are the answers the issues wait for. If one fails, write in the issue what happened
(an error, "action blocked", or nothing) and move on.

- [ ] **Arrow position** (#5, `arrow.md`): walk towards the current step facing different ways.
      The arrow points the right way and the distance counts down. If it is mirrored or turned,
      `UnitPosition` and `C_Map.GetWorldPosFromMapPos` use different coordinates. If there is
      no arrow at all, their continent ids differ.
- [ ] **Completed quests** (#3, `planner.md`): on the level 10 character, the window does not
      suggest quests it has already handed in. `/lvl debug` shows "completed quests read".
- [ ] **Accepting and handing in** (#9, `automation.md`): talk to the giver of the current "!"
      step: the quest is accepted without a click. Hand it in: it goes through without a click
      (when there is no reward to choose). If not, note which window stayed open.
- [ ] **Abandoning** (#13, `abandon.md`): `/lvl abandon` on the level 10 character, tick one
      quest, press the button. Does it leave the log, or does the client refuse?
- [ ] **Taking the suggested flight** (#78, `flights.md`): when chat says "fly from A to B",
      talk to the flight master at A. Does it take off at once? Also: does the flight map
      tooltip show "Flight time: about ..."? If not, the client does not call
      `TaxiNodeOnButtonEnter`.
- [ ] **Tooltips** (#14, #80, `hints.md`): hover a quest item in the bags ("Needed for: ...")
      and a quest giver ("! <quest>"). If an NPC never gets a line, run
      `/dump UnitGUID("mouseover")` over one and paste it into #80.
- [ ] **Quest log marks** (#80, `hints.md`): open the quest log. The quests in the guide's steps
      have a small yellow ring. If there are none, say what the quest log looks like.
- [ ] **Secure buttons** (#11, #12): on a step with a usable quest item, the item button shows
      and works (`itembutton.md`). `/lvl macro` makes the "LvlTarget" macro (`target.md`).

## 3. The guide window and the steps (15 minutes)

On the fresh character, play through the first few quests.

- [ ] The window shows the steps, the current one bright, with live counts like "3/8"
      (`window.md`). Drag it by the header; the header appears when pointing at the list.
- [ ] Steps tick themselves: accept, kill or loot, hand in (`steps.md`).
- [ ] The cross on a row skips its quest, and the arrow on a skipped row brings it back.
- [ ] The arrow can be dragged (#76, `arrow.md`, "Moving it"); "Lock position" stops both.
- [ ] The first-run panel looked right at the first login (`firstrun.md`).
- [ ] `/lvl settings` opens the addon's page, and every switch takes effect without `/reload`
      (`settings.md`).

## 4. Whatever happens along the way

Note these when they come up; no need to set them up.

- [ ] A trainer visit suggested at a new level (#17, `trainer.md`): the "train" row, the
      trainer's name, and the line at the trainer.
- [ ] A reward to choose: the coin and arrow badges (#10, `rewards.md`).
- [ ] Bags nearly full: a "sell" row (#15, `junk.md`).
- [ ] Diving: the drowning alarm at about 15 seconds of breath (#18, `survival.md`).
- [ ] A level-up: the line with the level's time, and `/lvl stats` (#19, `tracker.md`).
- [ ] The world map: the numbered pins and the dots of a kill area (#6, `pins.md`).

## 5. Later sessions

These need more setup and can wait: `party.md` (two clients in one party), `questlog.md` (a full
quest log), `sidetasks.md`, `support.md`, and the rest of each file above.

## After the session

Post what you found on each issue, even "works": most issues are waiting only for the game.
Issues whose checks all pass can then be closed.
