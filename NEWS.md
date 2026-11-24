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

## 1.20.0

- The All Addons page in Settings has a Set Default button. Click Confirm and this addon's settings go back to how they started.

Fixes and changes:
- Hunters are no longer offered thrown weapons.

## 1.19.0

- The small Upgrade Quest panel has a Search Again magnifying glass.
- The panel's Options menu is shorter: Current Zone Only, Update on Zone Change, Solo Quests Only and Open Equipment.
- Worn gear names show in their rarity color on My Gear.

Fixes and changes:
- Upgrade Quest shows another source's upgrade when the one you picked has none.

## 1.18.0

- A new Biggest Upgrade First box on the Upgrade Quest page of Settings makes each tab pick the biggest gain first. It starts off.

Fixes and changes:
- The New Upgrade pop-up no longer covers the small Upgrade Quest panel.
- Solo Quests Only no longer suggests dungeon quests.

## 1.17.0

- I was not happy with the overall quality of Equipment and did a full rework of the Addon. Feedback is appreciated.
- Equipment opens in one new window. My Gear shows your character with a green mark on every slot that has an upgrade. Find Upgrades lists every upgrade in one place. Upgrade Quest, Dungeons and Training have their own tabs.
- Your character sheet shows green arrows on slots with an upgrade. Alt-click a slot to see it in My Gear.
- Arrows on bags, bank, vendor and loot say how much better the item is, like +14%.
- Four dungeons were missing and are in now: Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold and The Shaper's Terrace.
- This Zone Only keeps dungeon and raid drops in the list when you are not in that zone.


## 1.16.2

Fixes and changes:
- Old copies of the character you play no longer get upgrade tips.
- Beta characters stay out when the realm name is blank.
- The character list in Settings shows the realm for names from another realm.

## 1.16.1

Fixes and changes:
- A second copy of a one-hander you hold gets its off hand arrow in your bags.

## 1.16.0

- Settings has a Forget button for characters you deleted.

## 1.15.0

- Windows fold into a round button with the Equipment badge.

Fixes and changes:
- Folding the One Window no longer shuts it for good.
- The Upgrade quest starts the Gnomish Zapper chain at Land Ho!.

## 1.14.0

- Panels and rows have a warm brown-black look.
- Item rows link in chat and try on gear.
- Equipment has its own key in Key Bindings.
Fixes and changes:
- Rogues can use one-handed axes.

## 1.13.5

Fixes and changes:
- The gear finder and upgrade quest stall less while they look for upgrades.

## 1.13.4

Fixes and changes:
- Hunters get the attack power from Careful Aim counted when Intellect is weighed.

## 1.13.3

Fixes and changes:
- Each character keeps its own saved realm.

## 1.13.2

Fixes and changes:
- Horde characters are no longer offered Alliance quests that don't name their side.
- A quest with no giver named no longer shows a blank line.

## 1.13.1

Fixes and changes:
- The trip line and stop dots now draw on the world map.
- Upgrades for an alt wait until the alt's gear has loaded.
- Show the way to a class trainer no longer gives an error.
- The upgrade quest percent follows the gear you wear now.

## 1.13.0

- Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.
- The Weights window lists Spirit and Health every 5 sec for every class. Both start at 0.

## 1.12.3

Fixes and changes:
- Swapping a fishing pole and a weapon no longer freezes the game.

## 1.12.2

Fixes and changes:
- Upgrade picks no longer show the other side's quest rewards.

## 1.12.1

Fixes and changes:
- Hovering gear no longer makes the game stutter.

## 1.12.0

- A one-handed weapon that beats your main hand now shows under Main hand too.
- Spell power scores fairer for casters.
- The Drowned City is in Dungeon Loot.
- Settings pages sit in the same order in every Blackthornes addon.
- Various bug fixes for Equipment.

## 1.11.1

Fixes and changes:
- The window stays where you drag it.

## 1.11.0

- Settings has one grid for what shows on screen, and an All Addons page.
- You can scroll the Upgrade Tracker past eight hunts.
- The window can dock in more places and you can resize it by hand.
Fixes and changes:
- Game pop-ups no longer hide behind our windows.
- Slot upgrade buttons no longer run over the gain.

## 1.10.3

Fixes and changes:
- Tool gear your class can never wear no longer counts as a tool in tooltips.

## 1.10.2

Fixes and changes:
- Upgrade arrows no longer show by mistake while your worn gear is still loading.

## 1.10.1

Fixes and changes:
- Words on the upgrade quest panel wrap now, so nothing gets cut off.
- Show the way skips class trainers who stop teaching too early.

## 1.10.0

- The upgrade quest panel tells you how your gear is doing and why it picked each upgrade.
- You can choose how you like to gear up, like quick and close, or vendors first.
- A gold card pops up when you finish an upgrade.
- Clicking the upgrade's marker on the map aims your arrow at it.
- The quest log shows how much a quest reward would help you.
Fixes and changes:
- The Upgrades window stops refreshing on its own.
- The controller bag button setting is gone.

## 1.9.2

Fixes and changes:
- Various bug fixes for Equipment.

## 1.9.1

Fixes and changes:
- The Upgrades window no longer keeps asking the server, so it stops stuttering.

## 1.9.0

- Windows now remember where you drag them, so they come back in the same spot.
- A new button on the General page puts every window back where it started.

## 1.8.0

- There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.
- Gear with both damage and healing now counts for both, so healers and casters get better upgrade picks.

## 1.7.2

Fixes and changes:

- Butler can now tell which gear your class can never wear.

## 1.7.1

Fixes and changes:

- Holding Shift over a tooltip no longer causes an error.

## 1.7.0

- Set bonuses now count. If a piece is part of a set you're wearing, Equipment thinks about the bonus before it tells you to swap it out.

## 1.6.4

Fixes and changes:

- The game no longer hitches every few seconds while Equipment looks for upgrades.

## 1.6.3

Fixes and changes:

- Equipment now uses much less CPU and memory. It only looks for upgrades when something changes.

## 1.6.2

Fixes and changes:

- Queue It now works for a pattern you learn after your first click.

## 1.6.1

Fixes and changes:

- Soulbound gear on a skipped character now shows the sell coin. It can't be mailed, so it no longer just sits in your bags.
- If you share your data, it now goes to one more of our characters. It is still off until you turn it on.

## 1.6.0

- Druids have a new Bear Tank spec, so tanks and cats get the right gear.
- Haste and expertise on gear now count when Equipment looks for upgrades.
- Destruction, Retribution and Shadow get new stat weights, and the spell hit cap is fixed.

## 1.5.2

Fixes and changes:

- Soulbound gear is no longer shown as an upgrade for your other characters.

## 1.5.1

Fixes and changes:

- Characters on your second account now count as this realm.

## 1.5.0

- You can drag the upgrade popup where you want it. Right-click puts it back.

## 1.4.5

Fixes and changes:

- One Window keeps its size when it docks while folded.

## 1.4.4

Fixes and changes:

- Various bug fixes for Equipment.

## 1.4.3

Fixes and changes:

- Various bug fixes for Equipment.

## 1.4.2

Fixes and changes:

- Various bug fixes for Equipment.

## 1.4.1

Fixes and changes:

- Settings in the one window now fit all their text.
- Various bug fixes for Equipment.

## 1.4.0

- The one window now stays next to the auction house.
- Item icons get a soft ring for their quality.

Fixes and changes:

- Various bug fixes for Equipment.

## 1.3.0

- All your Blackthornes addons share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.

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
