# Equipment UI cleanup (2026-11-16)

What a pass over Equipment's UI found, what was fixed, and what is waiting
on the owner. Nothing under "Recommended" is built. Each has a mockup in the
project's shared folder, `previews/equipment-ui-cleanup/`; visual changes
and new player words need the owner's yes first.

## Fixed in this pass

- **Slot panel buttons** (`UI/SlotUpgrades.lua`): Track and Map now take
  one width, the longest of Track, Untrack and Map, measured
  (`SlotUpgrades.ButtonWidth`, `FixedText`). Untrack used to grow its
  button past the room worked out from Track and run over the gain beside
  it, worst in German. Tested in `tools/test_hunts.lua`.
- **Upgrade Tracker past eight hunts** (`UI/TrackerPanel.lua`): the panel
  has eight rows and no way to reach a ninth, while its count said more.
  The mouse wheel moves the list (`TrackerPanel:Scroll`, `Offset`), with a
  thin gold thumb down the right edge while there is more
  (`PlaceThumb`), the same thumb the drop-down menus use. Tested in
  `tools/test_hunts.lua`.
- **Session room**: `tools/runtests.py -q` and `tools/syntaxcheck.py -q`
  print failures and one total line (a plain run was about 20 KB), and
  `-q word` runs only the suites named. CLAUDE.md went from 16 KB to 7 KB:
  a short form of each standing rule, the full words under "Standing rules
  in full" in `Docs/claude-notes.md`. The big files map has today's sizes
  and now names `Data/ForeverQuests.lua`, `Data/ForeverDrops.lua` and the
  data files with lines over 1000 characters.

## Looked at and left alone

- **Hitches and scans.** Every scan is behind a change check
  (`ns.NothingChanged` for bags, worn gear, skills and talents), bursts are
  coalesced (`RefreshSoon`, 0.2 to 0.3 s), windows skip work while hidden,
  and the item-details event only wakes modules waiting on an item. The
  per-frame scripts all return early (the motion driver hides when idle).
  `/beq perf` times the big pieces if a hitch is reported.
- **Memory.** The session caches are keyed by item seen (`schoolCache`,
  sell prices, tools) and stay small. Rows and pins are pooled and reused.
  Nothing found that grows without end.
- **`UI/TravelMap.lua`**: a shared file, measured as nearly free while
  idle. Not changed, so the copies stay the same.

## Recommended: windows that overlap

1. **Dock beside the character sheet.** Mockup
   `1-character-sheet-dock.png`. The gear window opens mid-screen
   (`FinderWindow.lua`, CENTER 0, 40) and the Alt-click slot panel opens on
   the slot itself (`SlotUpgrades:Open`, TOPLEFT of the slot button), so
   both cover the character sheet. Add a `character` place to
   `SharedWindow.PLACES` (frames `CharacterFrame`; it has no show event, so
   hook its OnShow and OnHide) so the one window docks beside the sheet as
   it does at a vendor. Alt-click a slot then scrolls the docked list to
   that slot instead of opening a second panel; with One Window off the
   slot panel anchors to the sheet's outer edge. Green arrows on the
   sheet's slots (our textures laid over the game's buttons, as the bag
   arrows are) mark slots with an upgrade. `SharedWindow.lua` is shared:
   build it once and copy to all five.
2. **One stack at the top of the screen.** Mockup `2-top-stack.png`. The
   upgrade banner (`Toast:Place`), Upgrade Done! (`Done.TOP`) and the
   shared note cards (`Notice.TOP`) each start 150 px from the top and
   know nothing of each other. Let the banner and the plaque take a slot
   in the stack `UI/Notice.lua` already lays out (`_G.BlackthornesNotice`),
   each with its own height. A banner the player dragged keeps its spot.
   `Notice.lua` is shared by all five.
3. **Moved to the shared work** (the one window's right shelf, all five
   addons). **Side panels in one column.** Mockup `3-side-panels.png`. Starting
   spots: Upgrade Tracker RIGHT -40, 120; Guide Me card RIGHT -60, 60;
   Upgrade Quest panel RIGHT -40, -120. Each is taller than the gaps, and
   all three sit where the game's quest list is. Panels never dragged
   stack in one column left of the game's list, each under the one above,
   closing up when one hides. A dragged panel leaves the column and keeps
   its saved spot (no saved key changes; only the defaults).
4. **Built 2026-11-16** (the owner said build all). **Game pop-ups on top.** Mockup `4-popups-on-top.png`. The one window
   is strata HIGH; Stat Weights, Ignored, Dungeon Loot, Dungeon Quests,
   the slot panel and the stand-alone gear and Settings windows are
   DIALOG, the game's own layer for confirm boxes, so a clicked window of
   ours can cover one. Move them to HIGH with `SetToplevel(true)`. Menus
   stay FULLSCREEN_DIALOG. Needs a look in game before it ships.

## Recommended: Settings

5. **Built 2026-11-16** (the owner said build all and picked the words
   SHOW ON SCREEN and OPEN). The grid is `SettingsUI:BuildShowGrid`, the
   buttons `SettingsUI:BuildOpenRows` (Gear page, right column, with the
   Quest Log row and its Tracked Only box); names drop their colon through
   `SettingsUI.GridName`. **Four pages and one list of what shows.** Mockup
   `5-settings-pages.png`. The Upgrade Hunts page holds five rows. Ten
   on/off boxes (Upgrade Arrows, Sell Coins, Take Reward Button, Upgrades
   in Chat, Character Sheet, Upgrade Banner, Upgrade Tracker, Map Pins,
   Upgrade Quest, Quest Arrow) are spread over three pages. Put them in
   one tick grid at the top of the Gear page, each box on its saved key as
   today, their descriptions on the hover; put the buttons that open a
   window together; drop the Upgrade Hunts page. New words: section names
   "SHOW ON SCREEN" and "OPEN".
6. **Shared settings shown once.** Mockup `6-shared-settings.png`. Window
   Style, Text Size, Effects, Mute All Sounds, Combine Addon Buttons, One
   Window, Window Spots, Sister Addons and the three What's New rows are
   on every addon's General page, and most already change all five at
   once. One page behind a gear at the foot of the one window's rail
   holds them; each addon's General page keeps only its own rows (here
   Window Size and TRANSPARENT). The two What's New boxes become one
   drop-down. New words: tab "All Addons", section "WHAT'S NEW", row
   "After Updates:" with "Off", "Show", "Show With Motion". This is work
   in the shared files for all five addons.

## Not checked (needs the game)

- Whether the docked one window and the open bags overlap at a vendor on
  a small screen.
- Whether the quest panel's "Hide Game's Tracker:" still leaves the two
  overlapping while the panel is folded.
