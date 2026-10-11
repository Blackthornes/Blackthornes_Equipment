-- Blackthornes Equipment -- Data/WeaponTrainers.lua
-- Classic's weapon masters: where each one stands and which weapon skills
-- they teach, so a tooltip can say where to learn a weapon the character
-- can use but has not trained yet.
--
-- Classic 1.12's trainers, as Wowpedia's "Weapon master" page lists them
-- (Sayoc and Hanashi in Orgrimmar, Archibald in Undercity, Ansekhwa in
-- Thunder Bluff; Woo Ping in Stormwind, Buliwyf Stonehand and Bixi
-- Wobblebonk in Ironforge, Ilyenia Moonfire in Darnassus). The Burning
-- Crusade's Silvermoon and Exodar trainers are left out. Not yet checked on
-- Forever; if a trainer there teaches something else, change it here.
--
-- Skills are the client's weapon subclass IDs (item class 2), the same
-- numbers Logic/Weights.lua uses for what each class can equip. Each
-- trainer's NPC ID and spot on its city's map are Classic's, from pfQuest's
-- database; a spot learned on Forever (Logic/NPCSpots.lua) wins over it.

local _, ns = ...

local WeaponTrainers = ns.NewModule("WeaponTrainers")

local AXE, AXE2H, BOW, GUN, MACE, MACE2H = 0, 1, 2, 3, 4, 5
local POLEARM, SWORD, SWORD2H, STAFF = 6, 7, 8, 10
local FIST, DAGGER, THROWN, CROSSBOW = 13, 15, 16, 18

WeaponTrainers.TRAINERS = {
    Horde = {
        { name = "Hanashi", city = "Orgrimmar", npc = 2704, x = 81.5, y = 19.6,
          skills = { BOW, AXE, AXE2H, STAFF, THROWN } },
        { name = "Sayoc", city = "Orgrimmar", npc = 11868, x = 81.7, y = 19.5,
          skills = { BOW, AXE, AXE2H, STAFF, THROWN, DAGGER, FIST } },
        { name = "Archibald", city = "Undercity", npc = 11870, x = 57.3, y = 32.8,
          skills = { CROSSBOW, DAGGER, SWORD, SWORD2H, POLEARM } },
        { name = "Ansekhwa", city = "Thunder Bluff", npc = 11869, x = 40.9, y = 62.7,
          skills = { GUN, MACE, MACE2H, STAFF } },
    },
    Alliance = {
        { name = "Woo Ping", city = "Stormwind", npc = 11867, x = 57.1, y = 57.7,
          skills = { CROSSBOW, DAGGER, SWORD, SWORD2H, POLEARM, STAFF } },
        { name = "Buliwyf Stonehand", city = "Ironforge", npc = 11865, x = 61.2, y = 89.5,
          skills = { GUN, AXE, AXE2H, MACE, MACE2H, FIST } },
        { name = "Bixi Wobblebonk", city = "Ironforge", npc = 13084, x = 62.2, y = 89.6,
          skills = { DAGGER, CROSSBOW, THROWN } },
        { name = "Ilyenia Moonfire", city = "Darnassus", npc = 11866, x = 57.6, y = 46.7,
          skills = { DAGGER, FIST, STAFF, BOW, THROWN } },
    },
}

-- Each weapon skill: its name as the item tooltip prints it, the spell a
-- character holds once they know it, and the names the classic skill list
-- uses for it. Wands and fishing poles have no weapon master, so they are
-- not here.
WeaponTrainers.SKILLS = {
    [AXE]      = { name = "One-Handed Axes", spell = 196, lines = { "Axes", "One-Handed Axes" } },
    [AXE2H]    = { name = "Two-Handed Axes", spell = 197, lines = { "Two-Handed Axes" } },
    [BOW]      = { name = "Bows", spell = 264, lines = { "Bows" } },
    [GUN]      = { name = "Guns", spell = 266, lines = { "Guns" } },
    [MACE]     = { name = "One-Handed Maces", spell = 198, lines = { "Maces", "One-Handed Maces" } },
    [MACE2H]   = { name = "Two-Handed Maces", spell = 199, lines = { "Two-Handed Maces" } },
    [POLEARM]  = { name = "Polearms", spell = 200, lines = { "Polearms" } },
    [SWORD]    = { name = "One-Handed Swords", spell = 201, lines = { "Swords", "One-Handed Swords" } },
    [SWORD2H]  = { name = "Two-Handed Swords", spell = 202, lines = { "Two-Handed Swords" } },
    [STAFF]    = { name = "Staves", spell = 227, lines = { "Staves" } },
    [FIST]     = { name = "Fist Weapons", spell = 15590, lines = { "Fist Weapons" } },
    [DAGGER]   = { name = "Daggers", spell = 1180, lines = { "Daggers" } },
    [THROWN]   = { name = "Thrown", spell = 2567, lines = { "Thrown" } },
    [CROSSBOW] = { name = "Crossbows", spell = 5011, lines = { "Crossbows" } },
}

--- The cities, in the order first listed, where `faction` can learn this
--- weapon skill. Empty when none of that faction's trainers teach it.
function WeaponTrainers:Cities(faction, subclassID)
    local cities, seen = {}, {}
    for _, trainer in ipairs(self.TRAINERS[faction] or {}) do
        for _, skill in ipairs(trainer.skills) do
            if skill == subclassID and not seen[trainer.city] then
                seen[trainer.city] = true
                cities[#cities + 1] = trainer.city
            end
        end
    end
    return cities
end

--- The trainers who teach this weapon skill to `faction`, in the order
--- listed: { name, city, npc, x, y, skills } each.
function WeaponTrainers:Teachers(faction, subclassID)
    local teachers = {}
    for _, trainer in ipairs(self.TRAINERS[faction] or {}) do
        for _, skill in ipairs(trainer.skills) do
            if skill == subclassID then
                teachers[#teachers + 1] = trainer
                break
            end
        end
    end
    return teachers
end
