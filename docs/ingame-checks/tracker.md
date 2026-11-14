# In-game checks: leveling tracker (Tracker)

None of this has been run in the game client yet. Tick each off in the game. The saved data is
`LevelingAddonCharDB.tracker` in the character's saved-variables file.

- [ ] On a character's first login with the addon, the game prints its two "time played" lines
      once (`RequestTimePlayed` exists and may be called at `PLAYER_LOGIN`), and `/lvl stats`
      then shows a time played. It is not asked again on later logins.
- [ ] If the time played stays unknown, typing `/played` fills it in (`TIME_PLAYED_MSG` carries
      the total in seconds as its first value).
- [ ] `/lvl stats` on a character that already had levels: the current level says "partial",
      earlier levels say "unknown". On a new level 1 character the first level is not partial
      (`UnitLevel` and `UnitXP` are right at `PLAYER_LOGIN`).
- [ ] Kill a creature: the XP shows under "from kills" (`CHAT_MSG_COMBAT_XP_GAIN` fires for a
      kill, within 0.3 seconds of `PLAYER_XP_UPDATE`). Rested XP is included.
- [ ] Hand in a quest: the XP shows under "from quests" (`QUEST_TURNED_IN` carries the XP
      reward as its second value, and it is the XP actually given).
- [ ] Discover a new area: that XP is under neither. If it shows up as a kill, the game sends
      `CHAT_MSG_COMBAT_XP_GAIN` for it and the split needs the message's text after all.
- [ ] Level up from a kill and from a quest: the finished level's line has the time and all of
      its XP, and the new level starts near zero. (If `UnitXP` is still the old value at
      `PLAYER_LEVEL_UP`, the last gain is counted on the new level instead.)
- [ ] Die: "1 death" on the level and, under `/lvl stats zones`, on the zone (`PLAYER_DEAD`
      fires once per death, not again on releasing the spirit).
- [ ] Change zone and enter an instance: `/lvl stats zones` has a row with the right name for
      each (`GetRealZoneText`, `ZONE_CHANGED_NEW_AREA`), and no "?" row.
- [ ] `/reload` and logging out keep the time (`PLAYER_LOGOUT` fires for both), and after
      logging back in the level is not marked partial.
- [ ] Level up on a level that was recorded from its start: one line in chat, "level N took
      ..., ... XP an hour", once. No line for the level the addon was installed on.
- [ ] Switch "Level time in chat" off on the settings page (or `/lvl set levelLine off`): the
      next level-up prints no line.
- [ ] With "Announce level-ups" set to party and in a party: the party message carries the
      time, and our own line is left out. Outside a party the line is back.
- [ ] After that level-up, `LevelingAddonDB.runs` in the account's saved-variables file has
      one key of eight hex digits with the level under it, and a second character adds a
      second key (`math.random` gives a different number on each character).
- [ ] `/lvl report` shows `runs` and no character name.
- [ ] Record for issue #2: `/lvl debug` memory with and without a long history.
