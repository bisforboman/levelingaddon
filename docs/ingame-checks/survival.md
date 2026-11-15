# In-game checks: survival (drowning alarm, elite warning)

None of this has been run in the game client yet. Tick each off in the game.

- [ ] Dive and stay under: a warning sound plays once, when about 15 seconds of breath are
      left, and no error appears.
- [ ] The sound is the raid warning (`SOUNDKIT.RAID_WARNING`, 8959) and is heard with sound
      effects switched off (it plays on the "Master" channel). Is it loud and distinct enough?
- [ ] Is 15 seconds enough time to surface from where quests send the player under water?
- [ ] Surface for a moment while the bar is still low and dive again: no second alarm. Let the
      bar refill past 15 seconds, dive again and stay under: it sounds again.
- [ ] Surface before the alarm: nothing sounds afterwards.
- [ ] `MIRROR_TIMER_START` arrives as `timerName, value, maxValue, scale, paused` with
      `timerName == "BREATH"`, `value` in milliseconds and `scale` negative under water. If the
      alarm never sounds, print the arguments first.
- [ ] With something that changes how fast breath runs out or how long it lasts (an underwater
      breathing potion or a racial), the alarm still comes with about 15 seconds left.
- [ ] If the breath bar is ever seen paused: `MIRROR_TIMER_PAUSE` arrives as
      `timerName, paused`, and `GetMirrorTimerProgress("BREATH")` returns milliseconds.
- [ ] Breath values are plain numbers, not secret values (an error mentioning a secret value
      while under water would say otherwise).
- [ ] `/lvl drown` switches the alarm off and on, and the choice survives `/reload`.
- [ ] Known gap: after `/reload` or logging in while already under water, no alarm sounds on
      that dive, because the game does not send `MIRROR_TIMER_START` again. Confirm, and say
      whether it matters.

## Elite warning

Needs the quest data built with a collector that writes `dangers-N.lua`.

- [ ] When a step starts near an elite (for example a step by Hogger's hill in Elwynn that is
      not his own quest), one line appears in chat, "Elite nearby: Hogger (level 11).", with
      one short sound, and no error.
- [ ] The sound (`SOUNDKIT.MAP_PING`, 3175) exists on this client and is short and distinct
      from the drowning alarm.
- [ ] 4 percent of the zone map is the right reach: are elites named that are too far from
      the step to matter, or missed that stand on the way to it? Zones differ in size.
- [ ] Elites more than 5 levels under the character are left out. Is that the right cut?
- [ ] The elite named is hostile. The data cannot tell a neutral elite from a hostile one
      (only "friendly to a side"), so note any neutral or friendly elite that is named.
- [ ] "Patrols the area." appears only for mobs that do walk a path.
- [ ] Each elite is named once per session: the same step after a planner pass, or another
      step at the same place, says nothing; after `/reload` it is said again.
- [ ] In an elite area with many elites near one step, the line names the nearest and counts
      the rest ("3 more near this step."), instead of a line each.
- [ ] A step of the elite's own quest (kill it, or loot what it drops) gives no warning.
- [ ] The "Elite warning" checkbox on the settings page and `/lvl set eliteNotice off` both
      silence it.
- [ ] `UnitFactionGroup("player")` returns "Alliance" or "Horde": an Alliance character is
      not warned of Alliance-friendly elites (city bosses, quest givers), a Horde one is.
