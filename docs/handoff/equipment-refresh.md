# The Upgrades window keeps refreshing: causes and fix plan

Working notes for the fix on branch `claude/project-thread-0jk1s0`. Kept so
a fresh session can pick the work up. Lives under `docs/`, which `.pkgmeta`
leaves out of the zip. Take this file out, or fold what matters into
`CLAUDE.md`, once the fix has shipped.

## What players see

With the Upgrades window open (and the upgrade quest on), the list redraws
again and again: counts flip, "Still asking the server about N items" comes
and goes, and worn slots lose their names for a moment. It never settles.

## The rule the fix must hold

From `CLAUDE.md` ("Scanning only when it matters", "Asking for the rest",
"Worn gear the game lets go"): a full scan runs only on a new zone, gear
worn, a level, talents, a recipe or skill learned, or a setting. One item is
judged when it lands in the bags or a quest offers it. No clock makes a scan
old. Item answers settle, then at most one more scan. Every item asked about
is given up on after `ASK_TRIES`, so the waiting count reaches 0.

## Causes found (by reading the code)

1. **The main loop.** `Finder.asked` is never cleared, so
   `Finder:OnItemAnswer` counts every later `GET_ITEM_INFO_RECEIVED` for any
   item ever asked about, whoever caused it. After `ANSWER_SETTLE`,
   `AnswersSettled` says `done` whenever the queue is empty, the window's
   watcher calls `RefreshSoon`, a whole sliced scan runs and `Present`
   rebuilds every line and count.
2. Every `Build` calls `LinkFor`/`RolledLink` (GetItemInfo) for each listed
   pick, kept ones too. For an item the client let go of, that makes the
   client load it and fire the event for an "asked" id, which feeds cause 1.
3. In `Build`, `elseif ok then waiting = waiting + 1` (the client knows the
   item but its stats are not in): nothing is asked, no try is counted, so it
   is never given up on and "Still asking" stays forever.
4. `JudgeOnce` keeps no verdict while not every roll is judged, so those
   items run `Rolls:Best` again every scan and touch rolled links the client
   may load and answer about.
5. Worn gear the client lets go of: `WornStatsRead` flips, so `wornShort`,
   the counts and (through `wornBest`) `JudgeKey` move from scan to scan.
   `Items:Stats` on such gear starts loads, whose answers are for asked ids.
   Worn requests stop after `ASK_TRIES`, so `wornShort` can stay true and
   every item not yet judged counts as waiting forever. `Compare:Against`
   scores an unreadable worn piece as 0, and `ScoreOf`'s memo is keyed by the
   link with its name, so a link with a blank name misses it.
6. `tries` never resets, so an item answered, judged and later let go is
   wrongly "given up" after three real changes. Given-up items are dropped
   even when they could still be judged. `MarkStale` always sets `followUp`.
7. `Items:WornSignature` and `Items:BagSignature` (the quiet-event check in
   `Core/Init.lua`, `ns.NothingChanged`) hold item names. A worn link whose
   name blanks and comes back lets `PLAYER_EQUIPMENT_CHANGED` through, which
   calls `Finder.MarkStale` and sets the upgrade quest's `rescan`.
8. `Finder:ScanSliced` (the window's scan) never clears `self.stale`, so
   `Finder:Fresh()` stays nil and the upgrade quest's `FreshScan` (and
   `Latest()` from the character sheet) runs a second whole scan.
   `Items:Waiting` never clears for an asked item whose quality never comes,
   so every later answer for it redraws the `WatchNames` listeners; the
   upgrade quest updates on every answer for its own item.

## Fix plan (one cause at a time, a small test each, commit and push each)

- **A (main loop, first; then open the PR).** `Finder.pending`: `Request`
  marks the id pending; `OnItemAnswer` acts only on a pending id and clears
  it. `Finder:Asked` still means "ever asked". Stray answers then never
  reach `AnswersSettled`, the watchers or a scan.
  Test: `tools/test_refreshloop.lua`.
- **B.** Keep each pick's real link once read (`Finder.links`); only call
  GetItemInfo for an item the client has cached, else use `item:ID` (the
  rows already resolve names through `Items.ShowLink`).
- **C.** The "known but no stats" path asks (inside the batch budget,
  counting tries) and counts as waiting only until given up. A given-up item
  the client can describe is still judged. `tries` resets only when the
  judge key changes. `WaitForAnswers` whenever a scan asked for anything
  (still one timer a scan), so unanswered items are retried, then given up.
- **D.** Hold worn stats in `Data/Items.lua`: once a worn piece's stats are
  read they are kept for as long as that piece is worn, so a link the client
  lets go of still scores. Make `WornSignature` and `BagSignature` name
  free. Key `ScoreOf`'s memo by the item part of the link.
  Two checks in `tools/test_speed.lua` change on purpose ("the worn piece is
  asked for again", "a new item is not judged while the worn stats are
  missing").
- **E.** Judge an item as its answer arrives, so the verdict is kept before
  the client can let go of it again.
- **F.** A whole scan clears `stale` at its start (as `ScanInBackground`
  does), so the window's scan leaves `Fresh()` valid and the upgrade quest
  does not scan again.
- **G.** Cap answer-driven redraws per item in `Items:OnItemInfo` and the
  upgrade quest's own-item updates.
- **H.** Read the other `GET_ITEM_INFO_RECEIVED` and `Items:WatchNames`
  listeners (Enchants, BagIcons, DungeonLootWindow, DungeonQuestsWindow,
  IgnoredWindow, LootRolls, QuestRewards, Tooltip, UpgradeChat, QuestPanel,
  TrackerPanel) for redraws that feed themselves.

Why it ends: an answer-driven scan needs a pending answer or a timeout after
a `Request`, and requests are capped at `ASK_TRIES` an item per judge key.
So one real change costs a handful of scans at most.

## Progress

Tick these as each lands (commit shas in the PR).

- [x] A pending answers
- [ ] B kept links
- [x] C bounded waiting (an item is not asked again inside `ANSWER_WAIT`; `Build` waits when anything is due; `AskMore` asks old unanswered ones again with no scan, three tries, then gives up)
- [x] D name-free signatures (`Items.LinkKey`; `WornSignature` and `BagSignature` leave the name out, so a worn or carried link read with no name is no change to `ns.NothingChanged`; `tools/test_quietgear.lua`). Worn stats held was already in (`Finder:WornState`).
- [ ] E judge on arrival
- [x] F whole scan clears stale (`Finder.changes`: a change during the scan keeps it stale)
- [ ] G redraw caps
- [ ] H other listeners
  - [x] upgrade quest: an upgrade a tab let go (live judge says no, kept
    verdict says yes) is not picked back until `Finder:JudgeKey` moves
    (`UpgradeQuest:LetGo`, `LetGoNow`; test in `tools/test_upgradequest.lua`)
  - `WeaponSkills` hide and ignore, `SetBestArmorOnly`: fine, they go
    through `Weights:Changed`. `LookForBetter`: fine, bounded by `LEVEL_LOOK`.
  - [x] upgrade quest: an answer about a tab's own upgrade is looked at
    once per gear, level and weights (`UpgradeQuest:OwnItemHeard`; one that
    brought nothing still counts; `tools/test_speed.lua`)
- [ ] `CLAUDE.md` notes updated

Test notes: `tools/testenv.lua` runs timers at once, so a scan's wait settles
inside the scan unless the test holds `C_Timer.After`. Move the clock with
`Finder.Now`, and reset `Finder.pending` and `Finder.askedAt` between parts.

## How to work on it

Read big files 100 to 200 lines at a time (`grep -n` first). Pipe all output
through `tail` or `grep`. Checks: `python tools/syntaxcheck.py`,
`python tools/lintcalls.py`, `python tools/runtests.py`,
`python tools/check_locale.py`. The fix adds no words for players.
