# In-game checks: survival (drowning alarm)

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
