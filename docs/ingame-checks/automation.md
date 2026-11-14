# In-game checks: quest automation (Automation.lua)

None of this has been run in the game client. It is built against the documented classic and
retail addon API; which of these calls the Forever client lets addon code make is the open
question of issue #9, and only the game can answer it. Tick each off in the game. Both halves
are on by default: "Accept quests automatically" and "Hand in quests automatically" on the
settings page, or `/lvl set autoAccept` and `/lvl set autoTurnIn`.

## The calls

For each, the check is that it exists, does what is said, and raises no "action blocked"
message when the addon calls it (also in combat).

- [ ] No error on login.
- [ ] `GetQuestID()` returns the quest's id in the detail, progress and reward windows.
- [ ] `AcceptQuest()` accepts the quest in the detail window (event `QUEST_DETAIL`).
- [ ] `IsQuestCompletable()` and `CompleteQuest()` in the progress window (`QUEST_PROGRESS`):
      the reward window follows.
- [ ] `GetNumQuestChoices()` and `GetQuestReward(n)` in the reward window (`QUEST_COMPLETE`):
      `GetQuestReward(0)` hands in a quest with no reward to choose, `GetQuestReward(1)` one
      whose single reward is listed as a choice.
- [ ] Gossip window (`GOSSIP_SHOW`): `C_GossipInfo.GetActiveQuests()` and
      `GetAvailableQuests()` return tables with `questID`, `isComplete` (active) and
      `repeatable` (available), and `C_GossipInfo.SelectActiveQuest(questID)` and
      `SelectAvailableQuest(questID)` take the quest's id. Older clients took the row's number
      instead: if the wrong quest opens, or none, report it.
- [ ] Plain greeting window (`QUEST_GREETING`, an NPC with several quests and no gossip text):
      `GetNumActiveQuests`, `GetActiveTitle(i)` (second value: ready to hand in),
      `GetActiveQuestID(i)`, `GetNumAvailableQuests`, `GetAvailableQuestInfo(i)` (third value:
      repeatable, fifth: the quest's id), `SelectActiveQuest(i)`, `SelectAvailableQuest(i)`.
      Run `/dump GetActiveQuestID, GetAvailableQuestInfo`: where either is nil the addon picks
      nothing from that half of the list, and the quest's own window still works once clicked.
- [ ] `IsShiftKeyDown()` is true while Shift is held as the window opens.
- [ ] `QUEST_FINISHED` fires when a quest window closes, and `GOSSIP_CLOSED` when the gossip
      window does. (If one does not, a later change of steps could look at a window that is
      gone.)
- [ ] A quest the game accepts by itself as its window opens (an auto-accept quest) raises no
      error and is not accepted twice.

## Behaviour

- [ ] Talk to the NPC of the current "accept" step: the quest is accepted without a click. The
      same for a quest suggested further down the list.
- [ ] Talk to an NPC offering a quest the addon does not suggest (a skipped quest, say): the
      window stays open and nothing is accepted.
- [ ] Hand in a suggested quest with no reward, or one reward: it goes through the progress and
      reward windows without a click.
- [ ] A quest that offers a choice of rewards stops at the reward window, and choosing by hand
      works as usual.
- [ ] A quest in the log whose "turnin" step is in the list but which is not finished: talking
      to its NPC does not open or complete anything.
- [ ] An NPC with several quests: the suggested ones are handed in and accepted one after the
      other, hand-ins first, and the rest of the list stays for the player. Count how often
      the list reopens by itself; if it does not reopen after a hand-in, the next quest needs a
      second visit.
- [ ] A repeatable quest is never accepted or handed in.
- [ ] Hold Shift while opening the window: nothing is automatic. With a setting off, Shift
      makes that half automatic for the one window, and still only for suggested quests.
- [ ] Each setting switches its half off at once, with no reload, and survives `/reload`.
- [ ] Open the window of a quest that is not suggested and leave it open; make the addon suggest
      it (`/lvl unskip all` after skipping it): it is accepted then.
- [ ] Vendors, flight masters, innkeepers and trainers with a gossip window work as usual: the
      addon picks nothing but suggested quests.
