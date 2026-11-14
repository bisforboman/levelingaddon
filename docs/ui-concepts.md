# UI concepts for the leveling addon

Research notes and design directions for a minimal UI. No Lua has been written. The mockups
that go with this file are in [`mockups/ui-directions.html`](mockups/ui-directions.html).

Researched 2026-11-14.

## How far to trust this

The research ran in a cloud session whose network could not open CurseForge, the Blizzard
forums, zygorguides.com, nngroup.com, w3.org or warcraft.wiki.gg. Each claim below carries one
of three marks:

- **[read]**: the page or source file was opened (GitHub repositories, issues, Blizzard's UI
  source mirror).
- **[snippet]**: taken from a search-result summary of the linked page. The page itself was not
  opened, so numbers may be stale and context may be missing.
- **[inferred]**: our own conclusion.

Wowhead was not fetched. No addon archives were downloaded and no commercial addon's source was
read; RestedXP, Zygor and Dugi are described from public pages and other people's issue
trackers only. Concepts are described in our own words. Nothing here should be copied as a
layout, a texture or code.

Download counts are lifetime totals across all game flavours and are all **[snippet]**.

## 1. What the data lets the UI say

This comes from `data/parsed/`, not from other addons, and it shapes everything else.

| The data has | So the UI can |
| --- | --- |
| Quest start and end NPCs/objects with map-percent spawns | Point at a quest giver or turn-in, and pin it |
| Objectives by type (2,826 item, 713 NPC, 74 object) with spawns and drop sources | Say "kill X" or "loot Y from X" and point at the nearest spawn cluster |
| Level, required level, side, races, classes, XP | Decide which quests are worth offering to this character |
| Pre-quest, chain, breadcrumb and exclusive-to links | Know what unlocks next and avoid offering dead ends |
| `uiMapId` per zone | Convert coordinates to the game's map |

| The data lacks | Consequence |
| --- | --- |
| A hand-written route (step order, "set hearth here", "grind to 12") | **[inferred]** The addon computes "best next thing" from position, level and quest log. It is a next-step helper, not a scripted speedrun guide. Each step should be able to say why it was chosen, and "not this one" has to be cheap. |
| Item and money rewards | No reward previews |
| Travel instructions (flight paths, boats, cave entrances) | The arrow is a straight line. Step text needs a place name as a hedge. |
| Everything loaded at once (about 47 MB, per the README) | The UI cannot assume a full-database search or a "show every quest on the continent" view is free. Per-zone loading fits a UI that only talks about the current step. |

## 2. Platform constraints

Verified against Blizzard's UI source mirror, branch `forever`, build 1.60.1.70938
([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever)) unless marked.

**Forever is a modern client, not a Classic one.** Interface `16001`, internal flavour
`camelot` (TOC suffix `_Forever` or `_Camelot`), running the Mainline 12.1.x UI code with
Midnight's addon restrictions and secret values active. **[read]**
([version.txt](https://github.com/Gethe/wow-ui-source/blob/forever/version.txt),
[Questie_Forever.toc](https://github.com/Questie/Questie/blob/master/Questie_Forever.toc))
Detect it by interface range 16000-16999; the source and Questie disagree on `WOW_PROJECT_ID`.

| Area | Constraint | UI consequence |
| --- | --- | --- |
| Combat lockdown | Plain addon frames can be shown, hidden, moved and resized in combat as long as they are not anchored to, or parents of, a protected frame. **[read]** ([SimpleFrameAPIDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua)) | The step panel and arrow can fade in combat. Never anchor them to a Blizzard secure frame. |
| Secure buttons | A "use quest item" or "target NPC" button needs `SecureActionButtonTemplate`; it cannot be created, re-anchored or re-pointed in combat. **[read]** ([SecureTemplates.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)) | If the step changes mid-fight, the button lags until combat ends. A reason to leave it out of v1. |
| Secret values | Combat data is restricted; the quest log, map, super-track and minimap APIs carry no secret returns. **[read]** | Quest guidance is unaffected. Do not design anything that reacts to combat numbers. |
| Quest state | `C_QuestLog` only (`GetQuestObjectives`, `IsQuestFlaggedCompleted`, `ReadyForTurnIn`); the old `GetQuestLogTitle` family is not loaded. Events: `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED`, `QUEST_LOG_UPDATE`. **[read]** ([QuestLogDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)) | Step progress can be derived from the log, so the UI needs no "mark done" checkbox. |
| Position and facing | `C_Map.GetPlayerMapPosition` and `GetPlayerFacing` return nil in instances. **[snippet]** ([wiki](https://warcraft.wiki.gg/wiki/API_GetPlayerFacing)) | The arrow needs a designed "no direction here" state, not a frozen arrow. |
| Built-in waypoint | `C_Map.SetUserWaypoint` and `C_SuperTrack` exist. Whether Blizzard's in-world marker works on Forever maps is untested. **[read]** | Possible route to zero custom arrow. Needs an in-game check. |
| Map pins | MapCanvas data providers exist. HereBeDragons-Pins lists 16001 and a BSD licence. Calling `WorldMapFrame:SetMapID` from addon code taints the map. **[read]** ([HereBeDragons](https://github.com/Nevcairiel/HereBeDragons)) | Pins are feasible. Never drive the world map from our code. |
| Pixels and scale | 768 UI units of height; `PixelUtil` exists for 1-pixel borders; re-snap on `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED`. **[read]** ([PixelUtil.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/PixelUtil.lua)) | Thin borders are safe. Width varies by aspect ratio, so anchor to the screen centre or an edge, never by absolute x. |
| Saved positions | Saved variables are readable from `ADDON_LOADED`. A dragged, named frame is also restored by the client's layout cache unless `SetUserPlaced(false)` is called. **[snippet]** ([wiki](https://warcraft.wiki.gg/wiki/API_StartMoving)) | Store the anchor ourselves and switch the layout cache off, or the two fight. |
| Edit Mode | Present. Addon frames can only join through LibEditMode, which lists 16001. **[read]** ([LibEditMode.toc](https://github.com/p3lim-wow/LibEditMode/blob/master/LibEditMode.toc)) | The player's existing "move things" mode can move our frame; no home-made unlock mode. |
| Fonts | Font objects such as `GameFontNormal` switch file and size per locale (12 for Latin, 15 for Simplified Chinese). A hard-coded font path breaks Cyrillic and CJK. **[read]** ([Fonts.xml](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Fonts_Shared/Shared/Fonts.xml)) | Inherit the game's font objects. Lay out by measured text height, not fixed row heights. |
| Entry points | Addon compartment TOC fields work; the `Settings` API is present and `InterfaceOptions_AddCategory` is gone; slash commands work. **[read]** | Compartment entry, settings category and slash command, with no minimap button of our own. |
| Data loading | `LoadOnDemand` addons plus `C_AddOns.LoadAddOn` exist. The login cost of a 47 MB table is undocumented. **[read]** | Splitting data per zone or level band is possible; the UI should tolerate "loading this zone". |

## 3. What other addons do

### 3.1 Who is on Forever

| Addon | On-screen by default | Adoption | Notes |
| --- | --- | --- | --- |
| Questie | Map and minimap icons, tracker, tooltips; no guide window **[read]** ([repo](https://github.com/Questie/Questie)) | About 222M downloads **[snippet]** | Has a Forever TOC |
| TomTom | One arrow | About 93M **[snippet]** | The de facto arrow |
| RestedXP | Four frames: guide window, arrow, quest-item bar, target frame **[read]** ([description in another addon's issue](https://github.com/cjber/adventure-guide-forever/issues/354)) | About 24-30M **[snippet]** | Commercial. Forever routes reported to level 35 **[snippet]** |
| Zygor | One viewer showing one step, 3D arrow **[snippet]** ([manual](https://zygorguides.com/support/manual/window.php)) | Not public | Commercial |
| Azeroth Pilot Reloaded | Step panel, arrow, quest-order list, filler panel **[read]** ([repo](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded)) | About 3.8M **[snippet]** | |
| Guidelime | Step-list window, arrow, markers **[read]** ([repo](https://github.com/max-ri/Guidelime)) | About 5.7M **[snippet]** | Says Forever will be supported |
| Polestar | Guide window, 3D arrow with distance, four movable buttons; map markers off by default **[read]** ([repo](https://github.com/fitzforge/polestar)) | 301 GitHub stars | GPL-3.0, Forever-native, beta 0.3.7.2 on 12 Nov |

Polestar is the closest neighbour: same licence, same client, already in beta. Worth the
owner's attention before more is built. Its code was not read for this document.

### 3.2 Concepts, with evidence

**One current step, not a list**
- Problem: "what do I do now" without reading.
- Evidence: Zygor shows one step by default and caps its multi-step view at five
  **[snippet]** ([forum](https://zygorguides.com/forum/forum/technical-support/zygor-guide-viewer/183018-step-display-number-of-steps-shown-missing-all)).
  A permanent step-list frame drew a frame-rate complaint and a "too large" complaint in Azeroth
  Pilot Reloaded ([#214](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/issues/214) **[snippet]**,
  [#595](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/issues/595) **[read]**).
- For us: one step at rest. Upcoming steps appear on demand inside the same frame.

**Exactly one arrow**
- Problem: navigating without opening the map.
- Evidence: the best-documented failure in the genre is two arrows at once, when a guide and
  TomTom (or two guides) each draw their own. One addon exists only to swap RestedXP's arrow for
  TomTom's ([RestedXP-TomTom](https://github.com/HerrHaseGermany/RestedXP-TomTom) **[snippet]**;
  [audit of clashes](https://github.com/cjber/shortest-path-forever/issues/329) **[read]**).
  Straight-line arrows that point into cliffs are reported against Polestar **[read]**
  ([releases](https://github.com/fitzforge/polestar/releases)). A Questie maintainer declined to
  override the player's manual waypoint ([#3208](https://github.com/Questie/Questie/issues/3208) **[snippet]**).
- For us: one arrow, one target. If TomTom is installed, hand it the waypoint and draw nothing.
  Never replace a waypoint the player set by hand.

**Pins for the current target only**
- Problem: spatial overview.
- Evidence: Questie's adoption shows the demand; icon density is also its longest-running
  complaint, most recently a user who found the map overwhelming and could not find the density
  setting ([#8172](https://github.com/Questie/Questie/issues/8172) **[read]**).
- For us: pin the current step's target area and nothing else. Players who want every quest on
  the map already have Questie.

**Progress read from the quest log**
- Problem: guide and player drift apart.
- Evidence: years of "guide skipped a step" threads for Zygor, with fixes hidden in sliders
  **[snippet]** ([thread](https://zygorguides.com/forum/archive/index.php/t-4536.html)); a
  route loop in Azeroth Pilot Reloaded ([#246](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/issues/246) **[snippet]**).
  Polestar derives the step from the log and made Skip undoable **[read]**.
- For us: no checkboxes. One Skip with Undo, no confirmation dialog.

**Fade in combat, and keep working when hidden**
- Problem: the window sits over the fight.
- Evidence: a third-party addon exists only to fade RestedXP in combat
  ([RXPCombatHide](https://github.com/SoloWaltz/RXPCombatHide) **[read]**). Hiding one guide's
  window stalls its logic, so integrators park it off-screen **[read]**
  ([issue](https://github.com/cjber/adventure-guide-forever/issues/354)). Zygor users asked for a
  compact mode back because hiding the viewer broke the arrow **[snippet]**
  ([thread](https://zygorguides.com/forum/forum/general/general-guide-discussion/19246-a-couple-of-feature-suggestions-requests)).
- For us: combat fade is built in. Visibility is only a view; the step logic never depends on a
  frame being shown.

**Leave Blizzard's objective tracker alone**
- Evidence: tracker replacements break after patches and collide with other addons
  **[snippet]** ([issue](https://github.com/cjber/shortest-path-forever/issues/718),
  [Dugi forum](https://www.dugiguides.com/forums/topic/objective-tracker-moving/)).
- For us: sit beside it, never inside it.

**Automation is opt-in and narrow**
- Evidence: auto-accept complaints in Questie: firing with the setting off, blocking vendors,
  looping on repeatables ([#5970](https://github.com/Questie/Questie/issues/5970),
  [#1537](https://github.com/Questie/Questie/issues/1537),
  [#7032](https://github.com/Questie/Questie/issues/7032) **[snippet]**). Leatrix Plus ships with
  everything off ([page](https://www.curseforge.com/wow/addons/leatrix-plus) **[snippet]**).
- For us: no automation in v1.

**Look like the host, with one accent**
- Evidence: Baganator and Chattynator ship skins matching the default UI and popular overhauls
  **[snippet]** ([Baganator](https://www.curseforge.com/wow/addons/baganator)). A third-party
  reskin of RestedXP exists purely for darker surfaces and thinner borders
  ([Ez XP](https://www.curseforge.com/wow/addons/ez-xp) **[snippet]**).
- For us: game font objects, a dark backplate, thin border, one accent colour.

**Several ways in, and a way back**
- Evidence: a Zygor user closed the guide and could not reopen it **[snippet]**
  ([thread](https://zygorguides.com/forum/forum/world-of-warcraft-retail-version/leveling-and-loremaster-guides/18716-wasnt-paying-attention-and-closed-the-guide-ingame-how-do-i-reload-it-back));
  an addon's only entry point vanished after a patch ([issue](https://www.wowace.com/projects/elephant/issues/79) **[snippet]**);
  a user could not work out how to use an addon with no visible surface **[snippet]**
  ([forum](https://us.forums.blizzard.com/en/wow/t/i-downloaded-an-add-on-called-omnicc-how-do-i-use-it/2093477)).
- For us: compartment entry, slash command and settings category. When hidden, print the command
  that brings it back. Say one line on first login.

**Few settings; positions survive updates**
- Evidence: users cannot find the toggle they need (Questie #8172 **[read]**); position resets
  after an update anger people (Azeroth Pilot Reloaded #595 **[read]**).
- For us: about eight settings. Position is saved by us and never reset by an update.

**No evidence found** either way for config wizards, quest-item buttons, or tooltip additions.
They stay out of v1 on cost, not on evidence.

## 4. UI and UX principles that apply

All sources here are **[snippet]**. The first three topics borrow from driving, aviation and
smartwatch research; none of it was measured on MMO players.

| Principle | Source | Rule for this addon |
| --- | --- | --- |
| A glance is short. Driving guidance caps one glance near 2 s; simple watch-face comparisons are readable in under half a second. | [US DOT](https://www.transportation.gov/briefing-room/us-dot-releases-guidelines-minimize-vehicle-distractions), [Blascheck et al.](https://www.microsoft.com/en-us/research/?p=500399) | A step is verb, target, count: "Kill Kobold Vermin 6/10". |
| Symbols over the scene pull attention from it. Pilots using head-up displays were slower to notice unexpected events. | [Wickens and Ververs, FAA](https://www.faa.gov/data_research/research/med_humanfacs/oamtechreports/1990s/1998/9828) | Nothing of ours in the middle third of the screen. No continuous animation. |
| Progressive disclosure: secondary information one obvious step away. | [NN/g](https://nngroup.com/articles/progressive-disclosure/) | Rest state shows one step. Hover or a key shows why, what is next, and Skip. |
| User control: a clear exit and undo beat confirmation dialogs. | [NN/g](https://www.nngroup.com/articles/user-control-and-freedom/), [NN/g](https://www.nngroup.com/articles/confirmation-dialog/) | Skip is one click with Undo. |
| No display type is best for everything; for navigation a HUD indicator is competitive with in-world markers. | [Peacocke et al. 2018](https://www.yorku.ca/mack/ec2018.pdf) | A flat arrow is a sound choice; no need for a 3D one. |
| Dynamic HUDs: show on change, recede when idle, per-element toggles. | [Horizon Zero Dawn options](https://www.gamespot.com/articles/horizon-zero-dawns-custom-hud-options-revealed-pho/1100-6447620/) | Brighten on step change, dim in combat. Arrow and pins can each be turned off. |
| Text over a moving scene has no guaranteed contrast. Measure against the worst background and offer a solid backing. | [Xbox guideline 102](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102) | Always a dark backplate, default about 65% opacity, adjustable, plus the game's text shadow. |
| Minimum text height on PC is 18 px at 1080p, scalable. | [Xbox guideline 101](https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/101) | Step text is at least that. One scale slider. Minimal does not mean small. |
| Never signal by colour alone. | [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/?p=3102) | Step kind has an icon shape; done has a tick; arrival changes the arrow's shape. |
| Arrows convey relative distance well for off-screen targets. | [Burigat et al.](https://bibbase.org/network/publication/burigat-chittaro-gabrielli-visualizinglocationsofoffscreenobjectsonmobiledevicesacomparativeevaluationofthreeapproaches) | Arrow plus a number in yards. |
| Navigation aids and spatial learning: evidence is mixed. Landmark wording helps where minimaps do not. | [Johanson et al.](https://researchr.org/publication/JohansonGM17), [Khan and Rahman](https://cs.brown.edu/~nkhan6/docs/khan_rahman_ijhci17.pdf) | Step text carries a place name ("Echo Ridge Mine"). Also covers the straight-line arrow's blind spots. |
| Working memory is about four chunks, but that limits recall, not what may be visible. Brevity is justified by glance time. | [Cowan 2001](https://www.cambridge.org/core/product/44023F1147D4A1D44BDC0AD226838496) | At most three upcoming lines when expanded. Verb and target first, so truncation eats the tail; counts are never truncated. |
| Skip onboarding where the UI can explain itself; most people keep defaults. | [NN/g](https://www.nngroup.com/articles/mobile-app-onboarding/) | No wizard. The first step is on screen at first login. |

A leveling-addon user has asked for guidance, so the "too much hand-holding" debate in game
design is not a reason to withhold it. It is a reason to keep it small.

## 5. Design rules drawn from the above

1. One frame at rest. One step in it.
2. One arrow, one target; hand over to TomTom when it is installed.
3. Step state comes from the quest log. No checkboxes, no manual sync.
4. Outside the middle third of the screen; dimmed in combat; nil-safe in instances.
5. Dark backplate, game fonts, 18 px minimum at 1080p, one accent colour, shape plus colour.
6. Detail on demand in the same frame: why this step, next three, Skip with Undo.
7. Pins for the current target only. No tracker replacement. No automation.
8. Moved through Edit Mode; position saved by us; three ways to open settings.

## 6. Three directions

Drawn to scale on a 1920x1080 screen in the mockup file. Screen share is the addon's own frames
as a fraction of the screen.

| | A. Step strip | B. Side card | C. Quiet arrow |
| --- | --- | --- | --- |
| At rest | One strip, upper centre: direction, step, distance | Card on the right edge beside the tracker with step and next two, plus a separate arrow | Nothing. Minimap pin only. |
| On demand | Strip grows downward: why, next three, Skip | Already open | Arrow and one caption line on step change, on a key, or when heading the wrong way |
| Frames | 1 | 2 | 0 to 1 |
| Share at rest | about 0.7% | about 2.0% | 0% |
| Share at most | about 2.3% | about 2.0% | about 0.6% |
| Strength | One glance gets direction and instruction together. One anchor to move. | Upcoming steps always visible; familiar from other guides | Least screen of all |
| Risk | Sits nearer the centre than a side panel | Two frames; arrow and text are far apart; the right edge is the most crowded part of the default UI | Invisible addons confuse people; hover-only and key-only features go undiscovered (section 3.2) |

**Recommendation: A.** It is the only one that satisfies rules 1, 2 and 6 at once, and it puts
direction and instruction in a single glance. B is the genre's default and inherits the genre's
complaints. C is the smallest, but the research has more evidence against hidden UI than for it.

**Decision (owner, 2026-11-14): B, the side card.** The mockup file now shows B only, refined
to answer its risks:

- Distance is on the card as well as the arrow, so the card stands alone when the arrow is far
  away (ultrawide), switched off, or handed to TomTom.
- The card is anchored to the right edge, left of the objective tracker, and grows downward.
- The resting card is the step plus two dimmed upcoming lines.
- Width is fixed; long localized names wrap and the count is never cut.
- Each moment has a defined state: objective, hover, pick up quest, arrived (arrow becomes a
  ring), combat (one line, 40%), dungeon (arrow removed, card says guidance is paused), TomTom
  present (no arrow of ours), first login (one explanatory line, once), hidden (chat prints the
  command that restores it).

It never touches the middle third of the screen. The text-heavy first version of this card
is superseded by the iteration below.

**Second iteration (owner, 2026-11-14): as little text as possible.** The card keeps only
what cannot be drawn: the name of the thing to find, and a count.

| Was text | Now |
| --- | --- |
| Accept, Turn in, Kill, Collect | An icon in front of the name. `!` and `?` are the marks the game already shows over quest NPCs. |
| Done | A box per step that the addon ticks from the quest log (count reached, quest accepted, quest handed in). The player never ticks it. |
| Skip, Undo | Two small marks shown only on hover; see the three designs below. A skipped step shows a dash in its box, not a tick. |
| Quest name, place | The game's ordinary tooltip on hover |
| Distance | On the arrow only |
| Settings hint | A gear shown on hover, plus the addon compartment |
| First login, hidden, dungeon messages | One line in chat; in a dungeon the card shrinks to a pause mark |

This brings the resting footprint to about 1.3% of a 1920x1080 screen and leaves the addon
with almost no strings of its own to localize. Known trade-offs: icons do not say which quest a turn-in belongs to without the tooltip, and
section 3.2's evidence against hover-only features applies to the gear, which is why settings
also stay reachable from the compartment and a slash command.

**Skip and undo: three candidates** (third iteration; the owner asked for the boxes to tick
themselves and for clean skip designs). All three are switchable in the mockup.

| | 1. Hover rail | 2. Row x | 3. Right-click |
| --- | --- | --- | --- |
| How | Hovering the card shows a thin rail beside it with skip and settings; after a skip an undo arrow joins it | Hovering a row shows an x just outside its end; on a skipped row it becomes undo | Right-click a row to skip, again to restore; the tooltip shows a mouse with the right button lit |
| Skips | The current step | Any step | Any step |
| Added pixels at rest | None | None | None |
| Added on hover | Two or three small squares, always in the same place | One square that follows the pointer | Nothing |
| Risk | Cannot skip a later step directly | More movement inside the card's edge | Easy never to discover |

Recommendation: 1. It keeps the rows as pure status, puts every control in one predictable
place, and skipping "what I am told to do now" is the case that matters. Undo stays available
until the next step completes. A key binding for skip can accompany any of them.

**Planning ahead** (owner's question: is there a timeline of following steps?). At rest the
card shows the current step and the next two. Two on-demand views extend that without adding
anything to the screen during play:

- A chevron on the hover rail unrolls the card into a timeline of roughly the next eight steps
  along a line, grouped under the place they happen in. Place names are the only added text.
  Unrolled, the card takes about 5% of a 1920x1080 screen.
- On the world map, the next few stops are numbered and joined by a dashed line.

Since the route is computed as the player goes (section 1), steps further out are a forecast
and can change after a level-up, a new quest or a skip. Later stops are drawn hollow on the map
to show that.

## 7. Suggested v1 surfaces

Chosen by the owner on 2026-11-14:

- Step card and arrow, with the hover view (quest name, place, Skip/Undo) and combat dimming.
- One map and minimap pin for the current target.
- TomTom hand-off: when TomTom is installed it gets the waypoint and we draw no arrow.
- Settings page (scale, backplate opacity, arrow on/off, pin on/off, combat dimming, reset
  position), Edit Mode positioning, compartment entry and slash command.

Not in v1: secure "use item" button, automation, an all-quests map layer, tooltip lines.

## 8. Open questions

- Should the card move when the game's objective tracker grows long enough to crowd it?
- What does the arrow show when the target is in another zone?
- Does Blizzard's own waypoint marker (`C_Map.SetUserWaypoint`, super-tracking) work on Forever
  maps? If so the arrow could be the game's own. Needs an in-game test.
- What does loading 47 MB at login cost, and does per-zone loading change what the expanded view
  can list?
- Every **[snippet]** claim should be re-read from a machine that can open the page before it is
  relied on.
- How does this addon differ from Polestar for a player choosing between them?
