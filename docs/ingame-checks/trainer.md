# In-game checks: trainer visits (Trainer.lua)

None of this has been run in the game client yet. The spell list (`ns.Data.classSpells`) is
built by `collector export` (README, "Fetching class spells"). The checks marked *(no data)*
are for an addon folder without `Data/classSpells-1.lua`.

## Without spell data

- [ ] *(no data)* At login nothing is said about trainers or spells, and no "train" row appears.
- [ ] *(no data)* `/lvl trainer list` says "has no spell data yet."
- [ ] *(no data)* `/lvl trainer` prints that visits are not suggested, and again that they are;
      the setting "Suggest trainer visits" on the settings page follows it, and survives
      `/reload` (account-wide).
- [ ] *(no data)* The API exists under these names: `IsPlayerSpell(spellId)` or
      `IsSpellKnown(spellId)`, `GetMoney()`, and the events `TRAINER_SHOW`, `TRAINER_CLOSED`,
      `LEARNED_SPELL_IN_TAB`, `PLAYER_MONEY`. If neither spell function exists the feature stays
      silent.
- [ ] *(no data)* `IsPlayerSpell` on a lower rank of a spell the character has a higher rank of:
      write down whether it says true. The addon skips lower ranks either way, but a "false"
      there means the data's `rank` must be filled in for every spell with ranks.

## With spell data

- [ ] `/dump UnitRace("player")` gives a number as its third value (1 Human, 2 Orc, 3 Dwarf,
      4 Night Elf, 5 Undead, 6 Tauren, 7 Gnome, 8 Troll). Without it no race-only spell (a
      priest's racial spells, a mage's teleports and portals) is ever counted.
- [ ] A Hunter Trainer does not list the pet skills (Great Stamina, Natural Armor, the
      resistances): the data leaves them out on that assumption.
- [ ] Whether a Mage Trainer sells the teleports and portals, or only a portal trainer does. The
      data counts them for a Mage Trainer visit; if that is wrong they must come out.
- [ ] A mage sees its own side's teleports in `/lvl trainer list` and not the other side's.
- [ ] A character with spells waiting it can pay for, two in all or one marked `key`: a row with
      the trainer cursor and the trainer's name appears under the current step, while a class
      trainer of the character's side is within about 200 yards of the way.
- [ ] With five or more points waiting (a key spell counts 3), the row is the current step, at the
      nearest class trainer, and the arrow points at it.
- [ ] Only trainers of the character's own class and side are suggested; a trainer of another
      class standing nearer is not.
- [ ] The icon `Interface\Cursor\Trainer` shows on the row (it is engine art the UI source does
      not list). If it is blank, pick another cursor file.
- [ ] Opening the trainer's window ends the step, and one line says what to learn, cheapest first,
      and what it all costs. The names and costs match the trainer's own list.
- [ ] With too little money for any of it, the line names the cheapest spell and its cost.
- [ ] After the visit no row comes back until the next level, even with more money.
- [ ] Skipping the row keeps it away until the next level; at the next level it comes back if
      spells are still waiting.
- [ ] Learning the spells (clicking "Train") ends the suggestion: no row once nothing affordable is
      left.
- [ ] With a visit due and no trainer in this zone or the next, one line says how many spells are
      waiting, once per level.
- [ ] Reputation discounts: the cost the line gives is the undiscounted one. Write down whether
      that misleads enough to read the price from the trainer window instead.
- [ ] `/lvl debug` after the first suggestion: "trainers read" gives the one-off cost of reading
      the trainers from the NPC table.
