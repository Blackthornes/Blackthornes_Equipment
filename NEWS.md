# News

What each release says in the Discord server's #general channel: a few
short bullets per version, in plain words for players, saying what they'll
notice, then one line thanking, by their Discord name, everyone whose
feedback or report led to the changes (each name once; no line when nobody
asked). Each release PR writes the new version's section here next to its
CHANGELOG.md section, and after the upload `tools/post_general.py` posts it
under a line with the addon's name and version that points players to
#announcements for the full list. No link or addon card goes with it. This
is the only report that names players. A version with no section here posts
nothing in #general.
This file does not ship in the addon, but its newest sections do, without
the thanks line: `python tools/make_whatsnew.py` writes them into
Core/WhatsNewText.lua for the in-game What's New window. Run it after
writing a section; the release check refuses a tag while it is behind.

The window shows new features only. Write a section's features first, then
a "Fixes and changes:" line with the fixes and other changes under it: those
go to Discord but stay out of the window, and a section of only fixes puts
nothing in it. Say what each feature does in a few plain words, the way you'd
tell a friend: no hype, no questions to the reader, no exclamation marks
outside the thanks line, no dashes as punctuation, no "now you can". The
tool prints a note for a shipped line that reads like an advert.

## 1.3.0

- All your Blackthornes addons now share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.

Fixes and changes:

- Various bug fixes for Equipment.

## 1.2.0

- Gear in the finder takes one line, so you see more at once. Judge Gear As is at the top.
- Upgrade Hunts has Hunts and Done tabs.
- The Upgrade quest panel keeps its options behind one Options button.
- You can make Upgrade Hunts and the Upgrade quest see-through on the General page. It starts Off.
- Show the Way now does the job Follow did.

Fixes and changes:

- Various bug fixes for Equipment.

## 1.1.0

- One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the General page.
- Show on Map puts a bigger gold marker with the upgrade's name on the spot.
- Quest and zone names show in your game's language.

Fixes and changes:

- Several bug fixes for text that wrapped over the line under it.

## 1.0.1

- The Take reward button has the gold plaque look.

Fixes and changes:

- Various UI improvements.

## 1.0.0

- Arrow Size picks 50%, 75% or 100% for the guide arrow.
- A small gem beside the close button folds a window down to its title.
- Mail and plate show as upgrades for later only from level 38.

Fixes and changes:

- Word choices in Settings are now drop-downs.

## 0.35.0

- Dungeon Quests lists quests known to the addon done inside dungeons or raids, and which ones you've done.
- Dungeon Loot shows what each dungeon's bosses drop, with the upgrades for you marked.
- The gear window has tabs now: Upgrades, Enchants, Dungeon Quests, Dungeon Loot and Settings.
- An item's tooltip can say which boss drops it. You pick under Boss Drops on the Gear page of Settings.
- Every window has a size grip, and the General page has an Effects choice.

Fixes and changes:

- Gear made for other classes isn't called an upgrade anymore.
- The headings in Where to Get Upgrades sort the list.
- Right-click a spell in the Training drawer to skip it.
- Several bug fixes for stat weights and Settings.

## 0.34.0

- Where to Get Upgrades now lists your slots down the left. Pick a slot to see every upgrade for it, and tick which sources to show. "Only what I can get now" hides what you can't get yet.
- Untrained Weapons on the Gear page of Settings is now Show or Hide, set for each character.

Fixes and changes:

- Several bug fixes for the upgrade quest and class training.

## 0.33.0

- Each tooltip line Equipment adds can be Off, Shift or Always. You pick in Settings.

Fixes and changes:

- The Training drawer lists only characters on your realm and side.

## 0.32.0

- Equipment speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.
- Best Armor Only is under Put On Upgrades on the Gear page of Settings. It stops Equipment from offering lighter armor in a slot once you wear the heavier kind there. It's off until you turn it on.

## 0.31.2

Fixes and changes:

- Item names use their rarity color.
- Various fixes to Equipment.

## 0.31.1

Fixes and changes:

- Various fixes to Equipment.

## 0.31.0

- Gear with hit or crit ratings now counts for the percent it really gives, so it doesn't look better than it is.
- Casters count hit and crit on their gear.
- Hit you don't need past the cap isn't counted.
- Racial stat bonuses count when Equipment compares gear.
- Gear from recipes you've learned shows under Crafted in the upgrade finder, even the new ones Forever added.

Fixes and changes:

- Various fixes to Equipment.

## 0.30.0

- The upgrade finder has an Enchants view. It shows the best enchant for each piece you wear.
- Worn gear's tooltip shows its best enchant.

Fixes and changes:

- Various fixes to Equipment.

Thanks MagnusBabbage for the ideas and feedback!

## 0.29.0

- Equipment can put an upgrade on for you as soon as it lands in your bags. It's off until you turn it on in Settings.

## 0.28.0

- You can mark a character, such as a crafting alt, to skip upgrades, so it never gets gear offered or arrows.
- Upgrade quests and vendor gear are learned as you play, which helps most in zones the data doesn't cover.

Fixes and changes:

- Skyborne characters only see their own side's quests and gear.
- Several bug fixes for the training drawer and the gear window.

## 0.27.1

Fixes and changes:

- A few more starting-area quests and their gear rewards show up in upgrade searches.

## 0.27.0

- This is the largest AddOn update so far across the whole suite of Blackthornes addons.
- Equipment can show which class spells you can train, what they cost, and what your other characters can train too.
- The upgrade quest is easy to close and bring back, and it can show just the step you're on.
- The step you're on shows your quest's goals and counts, like the game's tracker.
- The arrow is a compass that lies on the ground now, and it stays out of the way of the XP bar.
- Your alts only get armor of the kind they actually wear.

## 0.26.1

Fixes and changes:

- Weapons you haven't trained are never picked as the one to wear.
- The trainer arrow stays on until you get there.
- The upgrade quest's map pin goes right to the vendor.

## 0.26.0

- The upgrade finder uses Forever's own levels and prices for gear Forever changed.

Fixes and changes:

- More lists use the dark list look.

## 0.25.0

- Equipment is in Deutsch on a German client.

## 0.24.0

- One line at login names the Blackthornes addons you don't have yet. It says it once.

Fixes and changes:

- Fixes for German game clients.

## 0.23.0

- Weapons you can't use yet now offer to show you the trainer, or let you ignore that weapon type.
- Learn the skill and the weapon pops up ready to wear.

Thanks Ezmode for the report!

## 0.22.1

- Less stutter when you gain a skill point while crafting or gathering.
- Fixed the alt upgrade line sometimes naming the character you're playing.

## 0.22.0

- New upgrade? Hit Put it on and you're wearing it.
- Quest rewards get a Take button that grabs the best one for you.
- Upgrades sitting in your bank or on an alt show up now.
- Fixed alts losing their saved gear after a reload.

## 0.21.2

- The upgrade quest and the upgrade finder are a lot lighter while you play.
- The quest arrow is calmer and doesn't get lost after a loading screen.
- A bunch of small fixes to the finder and the quest panel.

## 0.21.1

- When an alt can craft an upgrade, it now shows their full name.

## 0.21.0

- The upgrade quest shows a yellow ? when a quest is ready to turn in, just like the game does.

## 0.20.1

- Your mining pick, skinning knife and other profession tools don't get the sell coin anymore.

## 0.20.0

- Gear in your bags that's worth selling now gets a gold coin. You can turn it off in Settings.
- Dragging the quest arrow won't count as a click anymore.
- An empty upgrade tab now looks again when you reach a new zone.

## 0.19.0

- Quest rewards you get without picking are now checked for upgrades too.
- When no reward is an upgrade, a gold coin shows the one that sells for the most.

## 0.18.1

- Fixed an error that could pop up when the game's quest tracker or bag button was hidden.
- The quest arrow now moves on to the hand-in by itself when you finish a step.

## 0.18.0

- The upgrade quest window has a new Quest log tab with all your quests in one place.
- Weapons you haven't trained yet now say "Train" in red, so you know before you chase them.
- You can pick a new window look that matches the game's own windows. The gold look is still the default.
- Lists are calmer now, and the arrow comes back if TomTom drops your waypoint.

Thanks Ezmode for the Train idea!

## 0.17.0

Hey everyone! A small Equipment update just went up.

Crafted upgrades have a Queue it button now. If you use Tradeskills too, one click puts the craft in your queue, or puts what you need on your shopping list. Thanks Ezmode for the idea!

Restart the game fully after you update. Have fun!

## 0.16.0

Hey everyone! A new Equipment update just went up.

When two upgrades are just as good, the closer one comes first now, and the zone you're in shows up in green. Clicking an upgrade tells you it becomes your quest. And you can see which version you have at the bottom of the gear window. Thanks Ezmode for all of these!

Hovering over gear doesn't lag anymore. Thanks Lottus27 for spotting it!

The sort button on your combined bags is back. Forever's new controller button was sitting on top of it. Settings got a makeover too, with pages, a search box and bigger text if you want it. And everything runs lighter.

Restart the game fully after you update. Have fun!

## 0.15.0

Hey everyone! Equipment just got an update.

You can tell Equipment which weapon types you like best. If you love daggers, bump them up and they'll count for more. Thanks Ezmode for asking!

Where to get upgrades has a "This zone only" box now, so you only see gear from where you are. Thanks Lottus27!

The upgrade quest stays in your zone when you ask it to, instead of sending you somewhere else. Thanks Lottus27 for catching that!

If you use TomTom, the quest arrow hands its spot to TomTom so you only see one arrow. Thanks Ezmode!

Quest reward choices shouldn't show up blank anymore when you turn in a quest. Thanks Ezmode for reporting it!

Restart the game fully after you update. Good luck with the upgrades!
