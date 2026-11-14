# In-game checks: shared machinery (Core)

None of this has been run in the game client yet. Tick each off in the game.

- [ ] The addon loads without an error, and `/lvl help` lists the commands.
- [ ] After `/reload`, the window position and settings are kept (account-wide), and a second
      character has its own per-character data (`LevelingAddonCharDB` in that character's
      saved-variables file).
- [ ] The `#` comment line in the TOC is accepted.
- [ ] `/lvl debug` prints a memory figure, not "not available" (`UpdateAddOnMemoryUsage`,
      `GetAddOnMemoryUsage`).
- [ ] `/lvl debug` prints loop timings (`debugprofilestop` exists), and "moving" has frames
      after running around (`GetUnitSpeed`).
- [ ] The arrow turns and the row under the pointer lights up as smoothly as before (both now
      run on the shared loop at 0.05 s; the arrow redraws only for a turn of about a degree).
- [ ] With `/lvl hide`, `/lvl debug` twice in a row reports that the loop did not run.
- [ ] Accepting, progressing and handing in a quest still moves the list (events now go
      through `ns.On`).
- [ ] Record for issue #2: memory after login, and the loop's time per frame idle and moving.
