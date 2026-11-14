# In-game checks: map and minimap pin (Pins)

None of this has been run in the game client yet. Tick each off in the game.

World map

- [ ] A yellow dot sits on the current step's spot on its zone map, and its tooltip names the
      step. It moves when the step changes, with the map open and with it closed.
- [ ] The dot is drawn above the map and the game's own icons (frame level: the canvas's plus
      3000), and the texture `Interface\COMMON\Indicator-Yellow` exists in this client.
- [ ] The dot keeps its size on screen and its place on the ground while the map is zoomed and
      dragged, in the windowed and the full-screen map (`OnCanvasScaleChanged`,
      `canvas:GetScale()`).
- [ ] On the continent map the dot is at the right place; on another continent's maps and on
      the world map there is none (`C_Map.GetMapPosFromWorldPos`).
- [ ] Changing zone in the map's own drop-down and right-clicking out works as before, and the
      map never switches zone by itself. Clicks on the dot go through to the map
      (`SetMouseClickEnabled`).
- [ ] No "action blocked" or taint message when opening the map in combat, or when using the
      quest tracker's or the map's buttons after the dot has been shown.

Minimap

- [ ] The dot is in the right direction and at the right distance: walk onto the step's spot
      and the dot reaches the middle of the minimap. If it is mirrored or turned, the axes of
      `UnitPosition` and `C_Map.GetWorldPosFromMapPos` differ from what the code assumes
      (first number north, second west, for both).
- [ ] The dot shows at all: the instance id from `UnitPosition` equals the continent id from
      `C_Map.GetWorldPosFromMapPos` on every continent tried.
- [ ] At each of the six zoom levels the dot crosses the minimap's rim at the same distance as
      the ground does (outdoors 466.67, 400, 333.33, 266.67, 200, 133.33 yards across).
- [ ] Indoors, in a building and in a cave such as Echo Ridge Mine, the same holds (300, 240,
      180, 120, 80, 50 yards across). `IsIndoors()` is taken to say when the minimap uses its
      indoor zoom; note any place where the two disagree.
- [ ] With "Rotate minimap" on, the dot turns with the minimap (`GetCVar("rotateMinimap")`).
- [ ] A step further away than the minimap shows has its dot on the rim, in its direction.
- [ ] With a square minimap from another addon (one that defines `GetMinimapShape`), the dot
      uses the corners.
- [ ] The dot moves smoothly while running and flying (placed every 0.05 s). `/lvl debug`
      while moving, with and without `/lvl pin`: record the difference for issue #2.
- [ ] Clicking the minimap under the dot still pings.
- [ ] In a dungeon there is no dot and no error.

Later places on the world map

- [ ] The next three places after the current step each have a smaller, fainter dot with a
      black number 1, 2 or 3 that can be read on it (`GameFontNormalSmall` on an 18 px dot at
      70% opacity), under the current step's dot where they overlap.
- [ ] The numbers follow the order of the window's rows, a place taken by several rows has one
      dot, and its tooltip lists each name once. The current dot's tooltip lists the later
      steps at the same place under the current one.
- [ ] Steps within 2 percent of the zone map share a dot. Note whether that is too much or too
      little, also on the continent map, where dots of different places may still overlap.
- [ ] A place in another zone shows when that zone's map or the continent map is opened.
- [ ] After a planner pass (a level-up, a skip, a quest handed in) the numbered dots are the
      new plan's, with none left over from the old one.
- [ ] Note whether three is the right number of later places.
- [ ] There is no numbered dot on the minimap.

Both

- [ ] `/lvl pin` removes every dot and brings them back; the setting survives `/reload`.
- [ ] `/lvl hide` removes every dot along with the window.
- [ ] With TomTom installed there is no dot of ours on either map, numbered or not, and TomTom shows its own
      icon on both.
