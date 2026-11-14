# In-game checks: party features (Party.lua)

None of this has been run in the game client yet. Most of it needs two characters with the
addon, in one party. `/lvl party` prints the four settings and each party member's step;
`/lvl party version`, `/lvl party share` and `/lvl party step` switch one,
`/lvl party announce party`, `guild` or `off` sets the fourth.

Version check (on by default)

- [ ] The addon loads without an error: `C_AddOns.GetAddOnMetadata`,
      `C_ChatInfo.RegisterAddonMessagePrefix`, `IsInGroup` and `GetNumGroupMembers` exist.
      If the first is missing the check is silently off, and nothing below happens.
- [ ] Raise `## Version` in one character's copy of the TOC. When the two form a party, the
      character with the older copy is told once, about a second later, with the other's name
      and both versions. The character with the newer copy is told nothing.
- [ ] Leaving and forming the party again in the same session says nothing more; after
      `/reload` it is said once again.
- [ ] `/reload` while in the party: the older copy is still told (`PLAYER_LOGIN` finds the
      group already there).
- [ ] With an addon-message viewer, or `/etrace`: one message on a join, none when somebody
      leaves, and never two within 10 seconds, however fast people join.
- [ ] With `/lvl party version` off: nothing is sent and nothing is reported.
- [ ] In a raid the message goes to "PARTY". Find out whether it then reaches the whole raid,
      the subgroup, or nobody.

Level-up announcement (off by default)

- [ ] `/lvl party announce party`, then a level-up in a party: one line in party chat, sent
      without an error from the `PLAYER_LEVEL_UP` handler (`SendChatMessage` or
      `C_ChatInfo.SendChatMessage`). Nothing when not in a party.
- [ ] `/lvl party announce guild`: the same in guild chat; nothing without a guild.
- [ ] With the level tracker (#19) in place, the line ends with the time the level took, and
      it is the time of the level just finished, not of the new one.

Quest sharing (off by default)

- [ ] `/lvl party share`, then accept a quest in a party: the other member is offered the
      quest. Note which arguments `QUEST_ACCEPTED` carries here (quest id alone, or quest log
      index and quest id), and that `C_QuestLog.IsPushableQuest` or `GetQuestLogPushable`
      exists.
- [ ] A quest that cannot be shared is accepted without an error or a message.
- [ ] The quest selected in the quest log is the same before and after.
- [ ] Sharing right at `QUEST_ACCEPTED` works; if the quest is not in the log yet at that
      moment, it needs a short delay.
- [ ] Accepting a quest that the other member just shared does not start a loop of offers.

Party members' steps (sharing one's own step is off by default)

Both characters need the quest data loaded, and `/lvl party step` on for the one whose step
is to be seen.

- [ ] Point at the other character in the world, and at their party frame: the tooltip ends
      with "Leveling: " and their current step, for example "Leveling: Kobold Vermin 6/10",
      "Leveling: ! Marshal McBride" for a quest to pick up, "Leveling: ? Marshal McBride" for
      one to hand in. `/lvl party` prints the same after its settings line.
- [ ] Note which path adds the line: `TooltipDataProcessor` with `Enum.TooltipDataType.Unit`,
      or the `OnTooltipSetUnit` script, and that `GameTooltip:GetUnit()` returns the unit in
      both places. If neither exists there is no line and no error; `/lvl party` still works.
- [ ] The line is there in combat and in a dungeon, or it is absent without an error. On a
      client that keeps unit identity from addons there (`issecretvalue`), it must be absent.
- [ ] After pointing at party members for a while, in and out of combat: no "action blocked"
      message and no taint error from the tooltip or the party frames (`/console taintLog 1`).
- [ ] The line follows the other character: it changes within about a second of their step
      changing, the count moves as they kill, and it goes when they switch `/lvl party step`
      off or leave the party.
- [ ] With an addon-message viewer: one "S ..." message per change of step or count, never
      two within 5 seconds, none while the step stays the same through a planner pass, none
      with the setting off, none when alone.
- [ ] A third character joining gets the step of both within a few seconds.
- [ ] The sender's name in `CHAT_MSG_ADDON` ("Name" or "Name-Realm") matches `UnitName` of
      the party unit once the realm is cut off; with two realms in the party, the line is on
      the right character.
- [ ] After `/reload`, the other members' lines are gone until their step next changes. Decide
      whether that is good enough or a reload should ask the party again.
- [ ] Two game languages, if available: each client shows the names from its own data.
