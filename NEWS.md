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

## 0.26.0

- A new What's New window shows what changed after each update.
- Gear that Forever changed now uses Forever's own levels and prices.
- More lists got the new dark look.

## 0.25.0

- Equipment speaks Deutsch now if your game is in German.

## 0.24.0

- Works on German game clients too.
- A short note at login tells you about our other addons, just once.

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
