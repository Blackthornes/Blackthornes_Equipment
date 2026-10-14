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

## 0.28.0

- You can mark a character, such as a crafting alt, to skip upgrades, so it never gets gear offered or arrows.
- Upgrade quests and vendor gear are learned as you play, which helps most in zones the data doesn't cover.

Fixes and changes:

- Skyborne characters only see their own side's quests and gear.
- The training drawer and the gear window show whole names without cutting them.

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
