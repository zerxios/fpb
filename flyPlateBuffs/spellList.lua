local _, fPB = ...
---------------------------------------------------------
-- FlyPlateBuffs Spell Lists
-- Important spells are displayed with large icons
-- Semi-important spells are displayed with medium icons
---------------------------------------------------------

-- Class color definitions
local CLASS_COLORS = {
	MAGE = "|cFF3FC7EB",      -- Light Blue
	DEATHKNIGHT = "|cFFC41F3B", -- Red
	SHAMAN = "|cFF0070DE",    -- Blue
	DRUID = "|cFFFF7D0A",     -- Orange
	PALADIN = "|cFFF58CBA",   -- Pink
	WARRIOR = "|cFFC79C6E",   -- Tan
	ROGUE = "|cFFFFF569",     -- Yellow
	HUNTER = "|cFFABD473",    -- Green
	MONK = "|cFF00FF96",      -- Light Green
	PRIEST = "|cFFFFFFFF",    -- White
	WARLOCK = "|cFF8787ED",   -- Purple
	DEMONHUNTER = "|cFFA330C9", -- Dark Purple
	MISC = "|cFF888888",      -- Gray
}

---------------------------------------------------------
-- Important spells (displayed with large icons)
---------------------------------------------------------
local defaultSpells1 = {
	-- Mage
	[CLASS_COLORS.MAGE .. "Mage|r"] = {
		45438, --Ice Block
		118, --Polymorph
		198111, --Temporal Shield (pvp)
	},

	-- DK
	[CLASS_COLORS.DEATHKNIGHT .. "Death Knight|r"] = {
		48707, --Anti-Magic Shell
		207319, --Corpse Shield
		221562, --Asphyxiate
	},

	-- Shaman
	[CLASS_COLORS.SHAMAN .. "Shaman|r"] = {
		51514, --Hex
		210918, --Ethereal Form
		204437, --Lightning Lasso (pvp)
	},

	-- Druid
	[CLASS_COLORS.DRUID .. "Druid|r"] = {
		61336, --Survival Instincts
		29166, --Innervate
		33786, --Cyclone
		5211, --Mighty Bash
	},

	-- Paladin
	[CLASS_COLORS.PALADIN .. "Paladin|r"] = {
		642, --Divine Shield
		86659, --Guardian of Ancient Kings
		228049, --Guardian of the Forgotten Queen
		6940, --Blessing of Sacrifice
		853, --Hammer of Justice
	},

	-- Warrior
	[CLASS_COLORS.WARRIOR .. "Warrior|r"] = {
		871, --Warrior Shield Wall
		5246, --Intimidating Shout
	},

	-- Rogue
	[CLASS_COLORS.ROGUE .. "Rogue|r"] = {
		2094, --Blind
		199743, --Parley
		6770, --Sap
	},

	-- Hunter
	[CLASS_COLORS.HUNTER .. "Hunter|r"] = {
		19386, --Wyvern Sting
		186265, --Aspect of the Turtle
		53480, --Roar of Sacrifice (pet)
	},

	-- Monk
	[CLASS_COLORS.MONK .. "Monk|r"] = {
		115078, --Paralysis
		115176, --Zen Meditation
		122783, --Diffuse Magic
		122278, --Dampen Harm
	},

	-- Priest
	[CLASS_COLORS.PRIEST .. "Priest|r"] = {
		605, --Mind Control
		8122, --Psychic Scream
		205369, --Mind Bomb
		33206, --Pain Suppression
		64901, --Symbol of Hope
		47788, --Guardian Spirit
		47585, --Dispersion
	},

	-- Warlock
	[CLASS_COLORS.WARLOCK .. "Warlock|r"] = {
		710, --Banish
		5782, --Fear
		104773, --Unending Resolve
		6789, --Death Coil
		5484, --Howl of Terror
		212295, --Nether Ward
		6358, --Seduction (Succubus)
	},

	-- Demon Hunter
	[CLASS_COLORS.DEMONHUNTER .. "Demon Hunter|r"] = {
		162264, --Metamorphosis
		196555, --Netherwalk
		206804, --Rain from Above (pvp) ?
		204490, --Sigil of Silence
		205629, --Demonic Trample
		205630, --Illidan's Grasp
	},

	----
	[CLASS_COLORS.MISC .. "Battleground Objectives|r"] = {
		23333, -- Warsong Flag (horde WSG flag)
		23335, -- Silverwing Flag (alliance WSG flag)
		34976, -- Netherstorm Flag (EotS flag)
		121164, --Orb of Power (Kotmogu?)
		168506, --Ancient Artifact (Ashran)
	},
}

---------------------------------------------------------
-- Semi-important spells (displayed with medium icons)
---------------------------------------------------------
local defaultSpells2 = {
	-- Mage
	[CLASS_COLORS.MAGE .. "Mage|r"] = {
		80353, --Timewarp
		12042, --Arcane Power
		190319, --Combustion - burst
		12472, --Icy Veins
		82691, --Ring of frost
		198144, --Ice form (pvp)
		86949, --Cauterize
	},

	-- DK
	[CLASS_COLORS.DEATHKNIGHT .. "Death Knight|r"] = {
		47476, --Strangulate (pvp) - silence
		48792, --Icebound Fortitude
		116888, --Shroud of Purgatory
		114556, --Purgatory (cd)
	},

	-- Shaman
	[CLASS_COLORS.SHAMAN .. "Shaman|r"] = {
		32182, --Heroism
		2825, --Bloodlust
		108271, --Astral shift
		16166, --Elemental Mastery - burst
		204288, --Earth Shield
		114050, --Ascendance
	},

	-- Druid
	[CLASS_COLORS.DRUID .. "Druid|r"] = {
		106951, --Berserk - burst
		102543, --Incarnation: King of the Jungle - burst
		102560, --Incarnation: Chosen of Elune - burst
		33891, --Incarnation: Tree of Life
		1850, --Dash
		22812, --Barkskin
		194223, --Celestial Alignment - burst
		78675, --Solar beam
		77761, --Stampeding Roar
		102793, --Ursol's Vortex
		102342, --Ironbark
		339, --Entangling Roots
		102359, --Mass Entanglement
		22570, --Maim
	},

	-- Paladin
	[CLASS_COLORS.PALADIN .. "Paladin|r"] = {
		1022, --Blessing of Protection
		204018, --Blessing of Spellwarding
		1044, --Blessing of Freedom
		31884, --Avenging Wrath
		224668, --Crusade
		216331, --Avenging Crusader
		20066, --Repentance
		184662, --Shield of Vengeance
		498, --Divine Protection
		53563, --Beacon of Light
		156910, --Beacon of Faith
		115750, --Blinding Light
	},

	-- Warrior
	[CLASS_COLORS.WARRIOR .. "Warrior|r"] = {
		1719, --Battle Cry
		23920, --Spell Reflection
		46968, --Shockwave
		18499, --Berserker Rage
		107574, --Avatar
		213915, --Mass Spell Reflection
		118038, --Die by the Sword
		46924, --Bladestorm
		12292, --Bloodbath
		199261, --Death Wish
		107570, --Storm Bolt
	},

	-- Rogue
	[CLASS_COLORS.ROGUE .. "Rogue|r"] = {
		45182, --Cheating Death
		31230, --Cheat Death (cd)
		31224, --Cloak of Shadows
		2983, --Sprint
		121471, --Shadow Blades
		1966, --Feint
		5277, --Evasion
		212182, --Smoke Bomb
		13750, --Adrenaline Rush
		199754, --Riposte
		198529, --Plunder Armor
		199804, --Between the Eyes
		1833, --Cheap Shot
		1776, --Gouge
		408, --Kidney Shot
	},

	-- Hunter
	[CLASS_COLORS.HUNTER .. "Hunter|r"] = {
		117526, --Binding Shot
		209790, --Freezing Arrow
		213691, --Scatter Shot
		3355, --Freezing Trap
		162480, -- Steel Trap
		19574, --Bestial Wrath
		193526, --Trueshot
		19577, --Intimidation
		90355, --Ancient Hysteria
		160452, --Netherwinds
	},

	-- Monk
	[CLASS_COLORS.MONK .. "Monk|r"] = {
		125174, --Touch of Karma
		116849, -- Life Cocoon
		119381, --Leg Sweep
	},

	-- Priest
	[CLASS_COLORS.PRIEST .. "Priest|r"] = {
		10060, --Power Infusion
		9484, --Shackle Undead
		200183, --Apotheosis
		15487, --Silence
		15286, --Vampiric Embrace
		193223, --Surrender to Madness
		88625, --Holy Word: Chastise
	},

	-- Warlock
	[CLASS_COLORS.WARLOCK .. "Warlock|r"] = {
		108416, --Dark Pact
		196098, --Soul Harvest
		30283, --Shadowfury
	},

	-- Demon Hunter
	[CLASS_COLORS.DEMONHUNTER .. "Demon Hunter|r"] = {
		198589, --Blur
		179057, --Chaos Nova
		209426, --Darkness
		217832, --Imprison
		206491, --Nemesis
		211048, --Chaos Blades
		207685, --Sigil of Misery
		209261, --Last Resort (cd)
		207810, --Nether Bond
	},

	-- Consumables and miscellaneous
	[CLASS_COLORS.MISC .. "Consumables & Misc|r"] = {
		2335, --Swiftness Potion
		6624, --Free Action Potion
		67867, --Trampled (ToC arena spell when you run over someone)
	},
}

-- Export spell lists to the addon namespace
fPB.defaultSpells1 = defaultSpells1
fPB.defaultSpells2 = defaultSpells2
