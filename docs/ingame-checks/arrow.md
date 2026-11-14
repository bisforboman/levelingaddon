# In-game checks: the arrow (Arrow)

None of this has been run in the game client yet. Tick each off in the game.

Direction and distance

- [ ] The arrow points at the current step and the distance counts down to it while walking
      there, facing any way. If it is mirrored or turned, `UnitPosition("player")` and
      `C_Map.GetWorldPosFromMapPos` do not share one coordinate system (the arrow takes the
      player from the first and the target, and the map's east and south, from the second).
- [ ] The arrow shows at all, on every continent tried: the fourth value of `UnitPosition`
      equals the continent id that `C_Map.GetWorldPosFromMapPos` returns first. If they
      differ the arrow stays hidden everywhere (and so does the minimap pin).
- [ ] The arrow turns smoothly enough while the character turns. It now updates every 0.1 s
      (it was 0.05 s) and redraws for a turn of about a degree; the interval is the number in
      `ns.Task("arrow", 0.1, ...)`.
- [ ] `/lvl debug` while moving, with and without `/lvl arrow`: record the difference for
      issue #2.

Several places

- [ ] On a kill step (Kobold Vermin, for one) the arrow points at the nearest of the mob's
      places, not at the middle of the area.
- [ ] Within about 30 yards of that place the arrow moves on to the next nearest one, and after
      the last one it starts again. Say whether 30 yards (`AREA_YARDS`) is right: too small and
      the arrow keeps pointing at a place whose mobs are already in view, too large and it
      leaves before they are.
- [ ] The same on a collect step whose item drops from several kinds of mob (Tough Wolf Meat).
- [ ] An NPC to talk to with several places in the data: the arrow points at the nearest and
      stays on it. Note any NPC that is not at that place.
- [ ] No hitch when a step with many places becomes current (a common drop can have several
      hundred; they are converted once, then). `/lvl debug` shows the loop's longest frame.
- [ ] The places match the map pin roughly: the pin marks the planner's one point, the arrow
      the nearest spawn point, so they differ within the same area and never by a zone.

Arrived

- [ ] Within 8 yards of an NPC or object the arrow is replaced by a ring around a dot, in the
      arrow's colour, with no distance. The texture is the addon's own file, `ring.tga`
      (64 x 64, 32-bit, uncompressed): if the ring is a green square, the client did not load
      it, and it needs converting to BLP or a different path.
- [ ] A kill or collect step with a single place shows the ring within 30 yards of it.

Corpse

- [ ] After releasing the spirit the arrow points at the corpse, with the distance, and becomes
      the ring within 8 yards of it (`UnitIsGhost`, `C_DeathInfo.GetCorpseMapPosition`, on
      `PLAYER_ALIVE`).
- [ ] The same when the graveyard is in another zone than the corpse: the corpse is then looked
      for on the zone's parent maps (`C_Map.GetMapInfo(...).parentMapID`). Note what
      `GetCorpseMapPosition` returns for a map the corpse is not on.
- [ ] Before the spirit is released the arrow is unchanged; after coming back to life it points
      at the step again (`PLAYER_UNGHOST`, and `PLAYER_ALIVE` for a resurrection on the spot).
- [ ] With the corpse inside a dungeon there is no arrow and no error.
- [ ] With TomTom installed we draw nothing while dead either; TomTom has its own corpse arrow.

Nothing to point at

- [ ] With the current step on another continent there is no arrow (the window still shows the
      step). It comes back after the boat, zeppelin or portal, without `/reload`
      (`PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`).
- [ ] In a dungeon there is no arrow and no error, and it comes back on leaving
      (`IsInInstance`).
- [ ] In both cases `/lvl debug` shows the shared loop is not running for the arrow: with
      `/lvl pin` off as well, the loop's frame count stays still while standing there.
- [ ] Entering combat in a dungeon, or on another continent than the step, does not bring a
      stale arrow back.

Settings

- [ ] "Dim in combat" on: the arrow fades to 40% in combat, as the window does. Off: it does
      not.
- [ ] The Arrow switch and `/lvl arrow` hide and show it at once; `/lvl hide` hides it with the
      window.
