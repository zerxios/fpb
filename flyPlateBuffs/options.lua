local _, fPB = ...
local L = fPB.L

-- Get Print function from addon namespace
local Print = fPB.Print

-- Initialize AceConfig
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local db = {}
local UpdateAllNameplates = fPB.UpdateAllNameplates

-- Local references for better performance
local GetSpellInfo, tonumber, pairs, table_sort, table_insert =
    GetSpellInfo, tonumber, pairs, table.sort, table.insert

local DISABLE = DISABLE
local chatColor = fPB.chatColor
local linkColor = fPB.linkColor
local strfind = string.find

-- Initialize tooltip for spell descriptions
local tooltip = CreateFrame("GameTooltip", "fPBScanSpellDescTooltip", UIParent, "GameTooltipTemplate")
tooltip:Show()
tooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Compatibility function for GetSpellInfo
local GetSpellInfo = GetSpellInfo or function(spellID)
    if not spellID then
        return nil
    end
  
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if spellInfo then
        return spellInfo.name, nil, spellInfo.iconID, spellInfo.castTime, spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID, spellInfo.originalIconID
    end
end

-- Constants for UI limits
local minIconSize = 10
local maxIconSize = 100
local minTextSize = 6
local maxTextSize = 30
local minInterval = 0
local maxInterval = 80

-- Sort method names for the dropdown
local SortMethodNames = {
	[1] = L["By owner (mine first)"],
	[2] = L["By remaining time"],
}

-- Class and custom icon definitions
local classIcons = {
    ["DEATHKNIGHT"] = 135771,
    ["DEMONHUNTER"] = 1260827,
    ["DRUID"] = 625999,
    ["EVOKER"] = 4574311,
    ["HUNTER"] = 626000,
    ["MAGE"] = 626001,
    ["MONK"] = 626002,
    ["PALADIN"] = 626003,
    ["PRIEST"] = 626004,
    ["ROGUE"] = 626005,
    ["SHAMAN"] = 626006,
    ["WARLOCK"] = 626007,
    ["WARRIOR"] = 626008,
}

local hexFontColors = {
    ["Racials"] = "FF666666",
    ["PvP"] = "FFB9B9B9",
    ["PvE"] = "FF00FE44",
    ["logo"] = "ffff7a00",
}

local customIcons = {
    [L["Eating/Drinking"]] = 134062,
    ["?"] = 134400,
    ["Cogwheel"] = 136243,
    ["Racials"] = 136187,
    ["PvP"] = 132485,
    ["PvE"] = 463447,
}

-- Add class colors to hex font colors
for class, val in pairs(RAID_CLASS_COLORS) do
    hexFontColors[class] = val.colorStr
end

-- Helper functions for UI rendering
local function GetIconString(icon, iconSize)
    local size = iconSize or 0
    local ltTexel = 0.08 * 256
    local rbTexel = 0.92 * 256

    if not icon then
        icon = customIcons["?"]
    end

    return format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", icon, size, size, ltTexel, rbTexel, ltTexel, rbTexel)
end

local function Colorize(text, color)
    if not text then return end
    local hexColor = hexFontColors[color] or hexFontColors["blizzardFont"]
    return "|c" .. hexColor .. text .. "|r"
end

local function CheckSort()
	-- For newer versions with sortMethod integer instead of sortMode table
	if db.sortMethod then
		return db.sortMethod ~= 0
	end
	
	-- For backward compatibility with older sortMode table
	if db.sortMode then
		local i = 1
		while db.sortMode[i] do
			if db.sortMode[i] ~= "disable" then
				return true
			end
			i = i+1
		end
	end
	
	return false
end

local color
local iconTexture
local TextureStringCache = {}
local description
local function TextureString(spellId, IconId)
	if not tonumber(spellId) then
		return "\124TInterface\\Icons\\Inv_misc_questionmark:0\124t"
	else
		if IconId then 
			iconTexture = IconId
		else
			_,_,iconTexture =  GetSpellInfo(spellId)
		end
		if iconTexture then
			iconTexture = "\124T"..iconTexture..":0\124t"
			return iconTexture
		else
			return "\124TInterface\\Icons\\Inv_misc_questionmark:0\124t"
		end
	end
end

local function cmp_col1(a, b)
	if (a and b) then
		local Spells = db.Spells
		a = tostring(Spells[a].class or a)
		b = tostring(Spells[b].class or b)
 		return a < b
	end
end

local function cmp_col1_col2(a, b)
	if (a and b) then
		local Spells = db.Spells
		local a1 = tostring(Spells[a].class or a)
		local b1 = tostring(Spells[b].class or b)
		local a2 = tostring(Spells[a].scale or a)
		local b2 = tostring(Spells[b].scale or b)
	 if a1 < b1 then return true end
	 if a1 > b1 then return false end
		 return a2 > b2
	 end
end

local function cmp_col1_col2_col3(a, b)
	if (a and b ) then
		local Spells = db.Spells
		local a1 = tostring(Spells[a].class or a)
		local b1 = tostring(Spells[b].class or b)
		local a2 = tostring(Spells[a].scale or a)
		local b2 = tostring(Spells[b].scale or b)
		local a3 = tostring(Spells[a].name or a)
		local b3 = tostring(Spells[b].name or b)
	 if a1 < b1 then return true end
	 if a1 > b1 then return false end
	 if a2 > b2 then return true end
	 if a2 < b2 then return false end
		 return a3 < b3
	 end
end

local newNPCName

fPB.NPCTable = {
	name = L["Specific NPCs"],
	type = "group",
	childGroups = "tree",
	order = 1.1,
	args = {
		addSpell = {
			order = 1,
			type = "input",
			name = L["Add new NPC to list (All Changes May Require a Reload or for you to Spin your Camera"],
			desc = L["Enter NPC ID or name (case sensitive)\nand press OK"],
			set = function(info, value)
				if value then
					local npc = true
					local spellId = tonumber(value)
					newNPCName = value
					fPB.AddNewSpell(newNPCName, npc)
				end
			end,
			get = function(info)
				return newNPCName
			end,
		},
		blank = {
			order = 2,
			type = "description",
			name = "",
			width = "normal",
		},

		-- fills up with BuildSpellList()
	},
}




function fPB.BuildNPCList()
	local spellTable = fPB.NPCTable.args
	for item in pairs(spellTable) do
		if item ~= "addSpell" and item ~= "blank" and item ~= "showspellId" then
			spellTable[item] = nil
		end
	end
	local spellList = {}
	local Spells = db.Spells
	for spell in pairs(Spells) do
		if db.Spells[spell].spellTypeNPC then
			table_insert(spellList, spell)
		end
	end
	table_sort(spellList, cmp_col1)
	table_sort(spellList, cmp_col1_col2)
	table_sort(spellList, cmp_col1_col2_col3)
	for i = 1, #spellList do
		local s = spellList[i]
		local Spell = Spells[s]
		local name = Spell.name and Spell.name
		local spellId = Spell.spellId

		if Spell.DEATHKNIGHT then
			local hexColor = hexFontColors["DEATHKNIGHT"]
			color = "|c" .. hexColor
		elseif	Spell.DEMONHUNTER then
			local hexColor = hexFontColors["DEMONHUNTER"]
			color = "|c" .. hexColor
		elseif	Spell.DRUID then
			local hexColor = hexFontColors["DRUID"]
			color = "|c" .. hexColor
		elseif	Spell.EVOKER then
			local hexColor = hexFontColors["EVOKER"]
			color = "|c" .. hexColor
		elseif	Spell.HUNTER then
			local hexColor = hexFontColors["HUNTER"]
			color = "|c" .. hexColor
		elseif	Spell.MAGE then
			local hexColor = hexFontColors["MAGE"]
			color = "|c" .. hexColor
		elseif	Spell.MONK then
			local hexColor = hexFontColors["MONK"]
			color = "|c" .. hexColor
		elseif	Spell.PALADIN then
			local hexColor = hexFontColors["PALADIN"]
			color = "|c" .. hexColor
		elseif	Spell.PRIEST then
			local hexColor = hexFontColors["PRIEST"]
			color = "|c" .. hexColor
		elseif	Spell.ROGUE then
			local hexColor = hexFontColors["ROGUE"]
			color = "|c" .. hexColor
		elseif	Spell.SHAMAN then
			local hexColor = hexFontColors["SHAMAN"]
			color = "|c" .. hexColor
		elseif	Spell.WARLOCK then
			local hexColor = hexFontColors["WARLOCK"]
			color = "|c" .. hexColor
		elseif	Spell.WARRIOR then
			local hexColor = hexFontColors["WARRIOR"]
			color = "|c" .. hexColor
		elseif	Spell.Racials then
			local hexColor = hexFontColors["Racials"]
			color = "|c" .. hexColor
		elseif	Spell.PvP then
			local hexColor = hexFontColors["PvP"]
			color = "|c" .. hexColor
		elseif	Spell.PvE then
			local hexColor = hexFontColors["PvE"]
			color = "|c" .. hexColor
		else
			color = "|cFF00FF00" --green
		end

		if Spell.spellId then
			iconTexture = "\124T"..Spell.spellId ..":0\124t"
		else
			iconTexture = TextureString(spellId)
		end
		spellDesc = L["NPC ID"]

		local red
		local glw

		if Spell.RedifEnemy then
			local color = "|c" .."FF822323"
			red = color.."r"
		end
		if Spell.IconGlow then
			local color = "|c" .."FFEAD516"
			glw = color.."g"
		end


		local buildName = (Spell.scale or "1").." ".. iconTexture..(red or "")..(glw or "").." "..color..name

		buildName = buildName.."|r"


		spellTable[tostring(s)] = {
			name = buildName,
			desc = spellDesc,
			type = "group",
			order = 10 + i,
			get = function(info)
				local key = info[#info]
				local id = info[#info-1]
				return db.Spells[id][key]
			end,
			set = function(info, value)
				local key = info[#info]
				local id = info[#info-1]
				db.Spells[id][key] = value
				fPB.BuildNPCList()
				UpdateAllNameplates()
			end,
			args = {
				blank0 = {
					order = 1,
					type = "description",
					name = "All Changes May Require a Reload or for you to Spin your Camera",
				},
				scale = {
					order = 1,
					name = L["Icon scale"],
					desc = L["Icon scale (Setting Will Adjust Next Time NPC is Seen)"],
					type = "range",
					min = 0.1,
					max = 5,
					softMin = 0.5,
					softMax  = 3,
					step = 0.01,
					bigStep = 0.1,
				},
				durationSize = {
					order = 4,
					name = L["Duration font size"],
					desc = L["Duration font size (Setting Will Adjust Next Time NPC is Seen)"],
					type = "range",
					min = minTextSize,
					max = maxTextSize,
					step = 1,
				},
				durationCLEU = {
					order = 4.5,
					name = L["Duration uptime"],
					desc = L["Duration For NPC Spawn Timer Such as Infernals (Guardians & Minors) or 0 for NPC & Pets"],
					type = "range",
					min = 0,
					max = 60,
					step = 1,
				},
				spellId = {
					order = 5,
					type = "input",
					name = L["Icon ID"],
					get = function(info)
						return Spell.spellId and tostring(Spell.spellId) or L["No spell ID"]
					end,
					set = function(info, value)
						if value then
							local spellId = tonumber(value)
							db.Spells[s].spellId = spellId
							DEFAULT_CHAT_FRAME:AddMessage(chatColor..L[" Icon changed "].."|r"..(db.Spells[s].spellId  or "nil")..chatColor.." -> |r"..spellId)
							UpdateAllNameplates(true)
							fPB.BuildNPCList()
						end
					end,
				},
				blank = {
					order = 2,
					type = "description",
					name = "",
					width = "normal",
				},
				removeSpell = {
					order = 7,
					type = "execute",
					name = L["Remove spell"],
					confirm = true,
					func = function(info)
						fPB.RemoveSpell(s)
					end,
				},
				break2 = {
					order = 7.5,
					type = "header",
					name = L["Icon Settings"],
				},
				IconGlow= {
					order = 8,
					type = "toggle",
					name = L["Glow"],
					desc = L["Gives the icon a Glow"],
				},
				break3 = {
					order = 13,
					type = "header",
					name = L["Select if the NPC Belongs to a Class for Sorting"],
				},
				DEATHKNIGHT = {
					order = 14,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DEATHKNIGHT"], 15), Colorize("Death Knight", "DEATHKNIGHT")),
					get = function(info)
						return Spell.DEATHKNIGHT
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DEATHKNIGHT"
							Spell.DEATHKNIGHT = true
							-- Reset all other class flags
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							-- Reset all class flags
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildNPCList()
					end,
				},
				DEMONHUNTER = {
					order = 15,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DEMONHUNTER"], 15), Colorize("Demon Hunter", "DEMONHUNTER")),
					get = function(info)
						return Spell.DEMONHUNTER
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DEMONHUNTER"
							Spell.DEMONHUNTER = true
							Spell.DEATHKNIGHT = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildNPCList()
					end,
				},
				DRUID = {
					order = 16,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DRUID"], 15), Colorize("Druid", "DRUID")),
					get = function(info)
						return Spell.DRUID
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DRUID"
							Spell.DRUID = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildNPCList()
					end,
				},
				EVOKER = {
					order = 17,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["EVOKER"], 15), Colorize("Evoker", "EVOKER")),
					get = function(info)
						return Spell.EVOKER
					end,
					set = function(info, value)
						if value then 
							Spell.class = "EVOKER"
							Spell.EVOKER = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildNPCList()
					end,
				},
				HUNTER = {
					order = 18,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["HUNTER"], 15), Colorize("Hunter", "HUNTER")),
					get = function(info)
						return Spell.HUNTER
					end,
					set = function(info, value)
						if value then 
							Spell.class = "HUNTER"
							Spell.HUNTER = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				MAGE = {
					order = 19,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["MAGE"], 15), Colorize("Mage", "MAGE")),
					get = function(info)
						return Spell.MAGE
					end,
					set = function(info, value)
						if value then 
							Spell.class = "MAGE"
							Spell.MAGE = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				MONK = {
					order = 20,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["MONK"], 15), Colorize("Monk", "MONK")),
					get = function(info)
						return Spell.MONK
					end,
					set = function(info, value)
						if value then 
							Spell.class = "MONK"
							Spell.MONK = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				PALADIN = {
					order = 21,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["PALADIN"], 15), Colorize("Paladin", "PALADIN")),
					get = function(info)
						return Spell.PALADIN
					end,
					set = function(info, value)
						if value then 
							Spell.class = "PALADIN"
							Spell.PALADIN = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				PRIEST = {
					order = 22,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["PRIEST"], 15), Colorize("Priest", "PRIEST")),
					get = function(info)
						return Spell.PRIEST
					end,
					set = function(info, value)
						if value then 
							Spell.class = "PRIEST"
							Spell.PRIEST = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				ROGUE = {
					order = 23,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["ROGUE"], 15), Colorize("Rogue", "ROGUE")),
					get = function(info)
						return Spell.ROGUE
					end,
					set = function(info, value)
						if value then 
							 Spell.class = "ROGUE"
							Spell.ROGUE = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				SHAMAN = {
					order = 24,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["SHAMAN"], 15), Colorize("Shaman", "SHAMAN")),
					get = function(info)
						return Spell.SHAMAN
					end,
					set = function(info, value)
						if value then 
							Spell.class = "SHAMAN"
							Spell.SHAMAN = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				WARLOCK = {
					order = 25,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["WARLOCK"], 15), Colorize("Warlock", "WARLOCK")),
					get = function(info)
						return Spell.WARLOCK
					end,
					set = function(info, value)
						if value then 
							Spell.class = "WARLOCK"
							Spell.WARLOCK = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				WARRIOR = {
					order = 26,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["WARRIOR"], 15), Colorize("Warrior", "WARRIOR")),
					get = function(info)
						return Spell.WARRIOR
					end,
					set = function(info, value)
						if value then 
							Spell.class = "WARRIOR"
							Spell.WARRIOR = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				Racials = {
					order = 21,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["Racials"], 15), Colorize("Racials", "Racials")),
					get = function(info)
						return Spell.Racials
					end,
					set = function(info, value)
						if value then 
							Spell.class = "xRacials"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = true
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				PvP = {
					order = 22,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["PvP"], 15), Colorize("PvP", "PvP")),
					get = function(info)
						return Spell.PvP
					end,
					set = function(info, value)
						if value then 
							Spell.class = "yPvP"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = false
							Spell.PvP = true
							Spell.PvE = false
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				PvE = {
					order = 23,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["PvE"], 15), Colorize("PvE", "PvE")),
					get = function(info)
						return Spell.PvE
					end,
					set = function(info, value)
						if value then 
							Spell.class = "zPvE"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = true
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				showOnPets = {
					order = 3,
					type = "toggle",
					name = L["Pets"],
					desc = L["Show on pets"],
					width = "half",
				},
				showOnNPC = {
					order = 3.1,
					type = "toggle",
					name = L["NPCs"],
					desc = L["Show on NPCs"],
					width = "half",
				},
				totemTracking = {
					order = 10.0,
					type = "toggle",
					name = "Track as Totem",
					desc = "Show this spell's icon above the actual totem when summoned. The icon will remain until the totem expires or dies. Use the standard Glow setting to add a glow effect.",
					width = 1.5,
					get = function(info)
						return Spell.isTotem
					end,
					set = function(info, value) 
						Spell.isTotem = value
						if value then
							-- Auto-enable required settings for totem tracking
							Spell.showOnNPC = true
							Spell.spellTypeSummon = true
							-- Disable incompatible options
							Spell.showBuff = false
							Spell.showDebuff = false
							Spell.spellTypeCastedAuras = false
							Spell.spellTypeInterrupt = false
						end
						UpdateAllNameplates(true)
					end,
				},
				IconGlow = {
					order = 10.1,
					type = "toggle",
					name = "Glow Effect",
					desc = "Add a glow effect to this spell's icon",
					width = 1.5,
					get = function(info)
						return Spell.IconGlow
					end,
					set = function(info, value)
						Spell.IconGlow = value
						UpdateAllNameplates(true)
					end,
				},
				glowColor = {
					order = 10.2,
					type = "color",
					name = "Glow Color",
					desc = "Set the color of the glow effect",
					width = 1.5,
                    hasAlpha = true,
					get = function(info)
						if not Spell.glowColor then
							Spell.glowColor = {r = 1, g = 1, b = 1, a = 1}
						end
						return Spell.glowColor.r, Spell.glowColor.g, Spell.glowColor.b, Spell.glowColor.a
					end,
					set = function(info, r, g, b, a)
						if not Spell.glowColor then
							Spell.glowColor = {}
						end
						Spell.glowColor.r = r
						Spell.glowColor.g = g
						Spell.glowColor.b = b
						Spell.glowColor.a = a
						UpdateAllNameplates(true)
					end,
					disabled = function()
						return not Spell.IconGlow
					end,
				},
			},
		}
	end
end

local newSpellName

fPB.SpellsTable = {
	name = L["Specific Spells"],
	type = "group",
	childGroups = "tree",
	order = 1,
	args = {
		-- fills up with BuildSpellList()
	},
}

function fPB.BuildSpellList()
	local spellTable = fPB.SpellsTable.args
	for item in pairs(spellTable) do
		if item ~= "showspellId" then
			spellTable[item] = nil
		end
	end
	local spellList = {}
	local Spells = db.Spells
	local Ignored = db.ignoredDefaultSpells
	for spell in pairs(Spells) do
		if not Ignored[spell] and not db.Spells[spell].spellTypeNPC then
			table_insert(spellList, spell)
		end
	end
	table_sort(spellList, cmp_col1)
	table_sort(spellList, cmp_col1_col2)
	table_sort(spellList, cmp_col1_col2_col3)
	for i = 1, #spellList do
		local s = spellList[i]
		local Spell = Spells[s]
		local name = Spell.name and Spell.name or (GetSpellInfo(s) and GetSpellInfo(s) or tostring(s))
		local spellId = Spell.spellId

		-- Determine class color
		local color
		if Spell.DEATHKNIGHT then
			color = "|cFFC41F3B" -- Death Knight Red
		elseif Spell.DEMONHUNTER then
			color = "|cFFA330C9" -- Demon Hunter Purple
		elseif Spell.DRUID then
			color = "|cFFFF7D0A" -- Druid Orange
		elseif Spell.EVOKER then
			color = "|cFF33937F" -- Evoker Green
		elseif Spell.HUNTER then
			color = "|cFFABD473" -- Hunter Green
		elseif Spell.MAGE then
			color = "|cFF3FC7EB" -- Mage Light Blue
		elseif Spell.MONK then
			color = "|cFF00FF96" -- Monk Light Green
		elseif Spell.PALADIN then
			color = "|cFFF58CBA" -- Paladin Pink
		elseif Spell.PRIEST then
			color = "|cFFFFFFFF" -- Priest White
		elseif Spell.ROGUE then
			color = "|cFFFFF569" -- Rogue Yellow
		elseif Spell.SHAMAN then
			color = "|cFF0070DE" -- Shaman Blue
		elseif Spell.WARLOCK then
			color = "|cFF8787ED" -- Warlock Purple
		elseif Spell.WARRIOR then
			color = "|cFFC79C6E" -- Warrior Tan
		elseif Spell.Racials then
			color = "|cFF666666" -- Racials Gray
		elseif Spell.PvP then
			color = "|cFFB9B9B9" -- PvP Light Gray
		elseif Spell.PvE then
			color = "|cFF00FE44" -- PvE Green
		else
			color = "|cFF00FF00" -- Default Green
		end

		iconTexture = TextureString(spellId, Spell.IconId)

		local red
		local glw
		local bff
		local debff

		if Spell.RedifEnemy then
			local redColor = "|cFFFF0505"
			red = redColor.."r"
		end
		if Spell.IconGlow then
			local glowColor = "|cFFEAD516"
			glw = glowColor.."g"
		end
		if Spell.showBuff then
			local buffColor = "|cFF00FF15"
			bff = buffColor.."b"
		end
		if Spell.showDebuff then
			local debuffColor = "|cFFFF0000"
			debff = debuffColor.."d"
		end

		local buildName
		if Spell.spellTypeSummon or Spell.spellTypeCastedAuras or Spell.spellTypeInterrupt then
			buildName = (Spell.scale or "1").." ".. iconTexture..(red or "")..(glw or "")..(bff or "")..(debff or "").." "..color..">"..name.."<|r"
		else
			buildName = (Spell.scale or "1").." ".. iconTexture..(red or "")..(glw or "")..(bff or "")..(debff or "").." "..color..name.."|r"
		end

		spellTable[tostring(s)] = {
			name = buildName,
			desc = spellDesc,
			type = "group",
			order = 10 + i,
			get = function(info)
				local key = info[#info]
				local id = tonumber(info[#info-1]) or info[#info-1]
				return db.Spells[id][key]
			end,
			set = function(info, value)
				local key = info[#info]
				local id = tonumber(info[#info-1]) or info[#info-1]
				db.Spells[id][key] = value
				fPB.BuildSpellList()
				UpdateAllNameplates()
			end,
			args = {
				spellHeader = {
					order = 0.9,
					type = "header",
					name = L["Spell Settings"],
				},
				addSpell = {
					order = 1,
					type = "input",
					name = "Add Spell to Track",
					desc = "Enter a spell ID or exact name to track. Case sensitive.\nSpell ID is recommended for accuracy.",
					width = 1,
					set = function(info, value)
						if value then
							local spellId = tonumber(value)
							if spellId then
								local spellName = GetSpellInfo(spellId)
								if spellName then
									newSpellName = spellName
									fPB.AddNewSpell(spellId)
								end
							else
								newSpellName = value
								fPB.AddNewSpell(newSpellName)
							end
						end
					end,
					get = function(info)
						return newSpellName
					end,
				},
				show = {
					order = 1.1,
					name = "Display Condition",
					desc = "Choose when to show this spell:\n- Always: Show regardless of source\n- Only Mine: Only show if cast by you\n- Never: Disable tracking\n- On Ally: Only show on friendly units\n- On Enemy: Only show on hostile units",
					type = "select",
					style = "dropdown",
					values = {
						[1] = "Always Show (from any source)",
						[2] = "Only My Spells (player cast only)",
						[3] = "Never Show (disabled)",
						[4] = "Friendly Units Only",
						[5] = "Hostile Units Only",
					},
				},
				showOnPets = {
					order = 3,
					type = "toggle",
					name = L["Pets"],
					desc = L["Show on pets"],
					width = "half",
				},
				showOnNPC = {
					order = 3.1,
					type = "toggle",
					name = L["NPCs"],
					desc = L["Show on NPCs"],
					width = "half",
				},
				spellId = {
					order = 1.2,
					type = "input",
					name = L["Spell ID"],
					get = function(info)
						return Spell.spellId and tostring(Spell.spellId) or L["No spell ID"]
					end,
					set = function(info, value)
						if value then
							local spellId = tonumber(value)
							if spellId then
								local spellName = GetSpellInfo(spellId)
								if spellName then
									if spellId ~= Spell.spellId and spellName == Spell.name then
										fPB.ChangespellId(s, spellId)
									elseif spellId ~= Spell.spellId and spellName ~= Spell.name then
										DEFAULT_CHAT_FRAME:AddMessage(spellId..chatColor..L[" It is ID of completely different spell "]..linkColor.."|Hspell:"..spellId.."|h["..GetSpellInfo(spellId).."]|h"..chatColor..L[". You can add it by using top editbox."])
									end
								else
									DEFAULT_CHAT_FRAME:AddMessage(tostring(spellId)..chatColor..L[" Incorrect ID"])
								end
							else
								DEFAULT_CHAT_FRAME:AddMessage(tostring(spellId)..chatColor..L[" Incorrect ID"])
							end
							fPB.BuildSpellList()
							UpdateAllNameplates()
						end
					end,
				},
				removeSpell = {
					order = 2,
					type = "execute",
					name = L["Remove spell"],
					confirm = true,
					func = function(info)
						fPB.RemoveSpell(s)
					end,
				},
				checkID = {
					order = 2.1,
					type = "toggle",
					name = L["Check spell ID"],
					set = function(info, value)
						if value and not Spell.spellId then
							Spell.checkID = nil
							DEFAULT_CHAT_FRAME:AddMessage(tostring(spellId)..chatColor..L[" Incorrect ID"])
						else
							Spell.checkID = value
						end
						fPB.CacheSpells()
						UpdateAllNameplates()
					end,
				},
				visualHeader = {
					order = 3.9,
					type = "header",
					name = L["Visual Settings"],
				},
				scale = {
					order = 4,
					name = "Icon Scale",
					desc = "Adjust how large the spell icon appears on nameplates (0.3 to 2.0)",
					type = "range",
					min = 0.3,
					max = 2,
					step = 0.1,
					width = 1,
				},
				stackSize = {
					order = 4.1,
					name = "Stack Counter Size",
					desc = "Set the text size for stack count numbers (6 to 30)",
					type = "range",
					min = minTextSize,
					max = maxTextSize,
					step = 1,
				},
				durationSize = {
					order = 4.3,
					name = "Timer Text Size",
					desc = "Set the text size for the remaining duration timer (6 to 30)",
					type = "range",
					min = minTextSize,
					max = maxTextSize,
					step = 1,
				},
				IconId = {
					order = 4.2,
					type = "input",
					name = "Override Icon",
					desc = "Replace the default spell icon with a custom one by entering a texture ID",
					width = 1,
				},
				displayHeader = {
					order = 7.1,
					type = "header",
					name = L["Display Options"],
				},
				showBuff = {
					order = 7.2,
					type = "toggle",
					name = "Track as Buff Only",
					desc = "Only display this spell when it appears as a beneficial effect (buff)",
					width = 1.5,
				},
				showDebuff = {
					order = 7.3,
					type = "toggle",
					name = "Track as Debuff Only",
					desc = "Only display this spell when it appears as a harmful effect (debuff)",
					width = 1.5,
				},
				RedifEnemy = {
					order = 7.4,
					type = "toggle",
					name = "Enemy Source Highlight",
					desc = "Tint the icon red when the spell comes from an enemy source",
					width = 1.5,
				},
				IconGlow = {
					order = 7.5,
					type = "toggle",
					name = "Glow Effect",
					desc = "Add a glowing border around the icon to make it more visible",
					width = 1.5,
				},
				glowColor = {
					order = 10.2,
					type = "color",
					name = "Glow Color",
					desc = "Set the color of the glow effect",
					width = 1.5,
                    hasAlpha = true,
					get = function(info)
						if not Spell.glowColor then
							Spell.glowColor = {r = 1, g = 1, b = 1, a = 1}
						end
						return Spell.glowColor.r, Spell.glowColor.g, Spell.glowColor.b, Spell.glowColor.a
					end,
					set = function(info, r, g, b, a)
						if not Spell.glowColor then
							Spell.glowColor = {}
						end
						Spell.glowColor.r = r
						Spell.glowColor.g = g
						Spell.glowColor.b = b
						Spell.glowColor.a = a
						
						UpdateAllNameplates(true)
					end,
					disabled = function()
						return not Spell.IconGlow
					end,
				},
				spellTypeHeader = {
					order = 9.9,
					type = "header",
					name = "Spell Type Settings",
				},
				disableAura = {
					order = 10.1,
					type = "toggle",
					name = "Ignore Buff/Debuff Events",
					desc = "Don't track normal buff/debuff applications for this spell",
					width = 1.5,
				},
				spellTypeCastedAuras = {
					order = 10.2,
					type = "toggle",
					name = "Show Spell Casts",
					desc = "Display when this spell is being cast",
					width = 1.5,
				},
				spellTypeInterrupt = {
					order = 10.3,
					type = "toggle",
					name = "Show Interrupts",
					desc = "Display when this spell interrupts a spellcast",
					width = 1.5,
				},
				spellTypeSummon = {
					order = 10.4,
					type = "toggle",
					name = "Show Summons",
					desc = "Display when this spell summons a unit or object",
					width = 1.5,
				},
				durationCLEU = {
					order = 12,
					name = L["Event Duration"],
					desc = L["How long to show temporary events like interrupts or casts (in seconds)"],
					type = "range",
					min = 1,
					max = 60,
					step = 1,
				},
				classHeader = {
					order = 12.9,
					type = "header",
					name = L["Class Settings"],
				},
				DEATHKNIGHT = {
					order = 14,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DEATHKNIGHT"], 15), Colorize("Death Knight", "DEATHKNIGHT")),
					get = function(info)
						return Spell.DEATHKNIGHT
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DEATHKNIGHT"
							Spell.DEATHKNIGHT = true
							-- Reset all other class flags
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							-- Reset all class flags
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				DEMONHUNTER = {
					order = 15,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DEMONHUNTER"], 15), Colorize("Demon Hunter", "DEMONHUNTER")),
					get = function(info)
						return Spell.DEMONHUNTER
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DEMONHUNTER"
							Spell.DEMONHUNTER = true
							Spell.DEATHKNIGHT = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				DRUID = {
					order = 16,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["DRUID"], 15), Colorize("Druid", "DRUID")),
					get = function(info)
						return Spell.DRUID
					end,
					set = function(info, value)
						if value then 
							Spell.class = "DRUID"
							Spell.DRUID = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				HUNTER = {
					order = 18,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["HUNTER"], 15), Colorize("Hunter", "HUNTER")),
					get = function(info)
						return Spell.HUNTER
					end,
					set = function(info, value)
						if value then 
							Spell.class = "HUNTER"
							Spell.HUNTER = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				MAGE = {
					order = 19,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["MAGE"], 15), Colorize("Mage", "MAGE")),
					get = function(info)
						return Spell.MAGE
					end,
					set = function(info, value)
						if value then 
							Spell.class = "MAGE"
							Spell.MAGE = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				MONK = {
					order = 20,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["MONK"], 15), Colorize("Monk", "MONK")),
					get = function(info)
						return Spell.MONK
					end,
					set = function(info, value)
						if value then 
							Spell.class = "MONK"
							Spell.MONK = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				PALADIN = {
					order = 21,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["PALADIN"], 15), Colorize("Paladin", "PALADIN")),
					get = function(info)
						return Spell.PALADIN
					end,
					set = function(info, value)
						if value then 
							Spell.class = "PALADIN"
							Spell.PALADIN = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				PRIEST = {
					order = 22,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["PRIEST"], 15), Colorize("Priest", "PRIEST")),
					get = function(info)
						return Spell.PRIEST
					end,
					set = function(info, value)
						if value then 
							Spell.class = "PRIEST"
							Spell.PRIEST = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				ROGUE = {
					order = 23,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["ROGUE"], 15), Colorize("Rogue", "ROGUE")),
					get = function(info)
						return Spell.ROGUE
					end,
					set = function(info, value)
						if value then 
							Spell.class = "ROGUE"
							Spell.ROGUE = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				SHAMAN = {
					order = 24,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["SHAMAN"], 15), Colorize("Shaman", "SHAMAN")),
					get = function(info)
						return Spell.SHAMAN
					end,
					set = function(info, value)
						if value then 
							Spell.class = "SHAMAN"
							Spell.SHAMAN = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				WARLOCK = {
					order = 25,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["WARLOCK"], 15), Colorize("Warlock", "WARLOCK")),
					get = function(info)
						return Spell.WARLOCK
					end,
					set = function(info, value)
						if value then 
							Spell.class = "WARLOCK"
							Spell.WARLOCK = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				WARRIOR = {
					order = 26,
					type = "toggle",
					name = format("%s %s", GetIconString(classIcons["WARRIOR"], 15), Colorize("Warrior", "WARRIOR")),
					get = function(info)
						return Spell.WARRIOR
					end,
					set = function(info, value)
						if value then 
							Spell.class = "WARRIOR"
							Spell.WARRIOR = true
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.class = nil
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = false
						end
						fPB.BuildSpellList()
					end,
				},
				Racials = {
					order = 21,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["Racials"], 15), Colorize("Racials", "Racials")),
					get = function(info)
						return Spell.Racials
					end,
					set = function(info, value)
						if value then 
							Spell.class = "xRacials"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = true
							Spell.PvP = false
							Spell.PvE = false
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				PvP = {
					order = 22,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["PvP"], 15), Colorize("PvP", "PvP")),
					get = function(info)
						return Spell.PvP
					end,
					set = function(info, value)
						if value then 
							Spell.class = "yPvP"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = false
							Spell.PvP = true
							Spell.PvE = false
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				PvE = {
					order = 23,
					type = "toggle",
					name = format("%s %s",GetIconString(customIcons["PvE"], 15), Colorize("PvE", "PvE")),
					get = function(info)
						return Spell.PvE
					end,
					set = function(info, value)
						if value then 
							Spell.class = "zPvE"
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false

							Spell.Racials = false
							Spell.PvP = false
							Spell.PvE = true
						else
							Spell.DEATHKNIGHT = false
							Spell.DEMONHUNTER = false
							Spell.DRUID = false
							Spell.EVOKER = false
							Spell.HUNTER = false
							Spell.MAGE = false
							Spell.MONK = false
							Spell.PALADIN = false
							Spell.PRIEST = false
							Spell.ROGUE = false
							Spell.SHAMAN = false
							Spell.WARLOCK = false
							Spell.WARRIOR = false
							Spell.PvP = false
							Spell.Racials = false
							Spell.PvE = false
							
						end
						fPB.BuildNPCList()
						
					end,
				},
				showOnPets = {
					order = 3,
					type = "toggle",
					name = L["Pets"],
					desc = L["Show on pets"],
					width = "half",
				},
				showOnNPC = {
					order = 3.1,
					type = "toggle",
					name = L["NPCs"],
					desc = L["Show on NPCs"],
					width = "half",
				},
				totemTracking = {
					order = 10.0,
					type = "toggle",
					name = "Track as Totem",
					desc = "Show this spell's icon above the actual totem when summoned. The icon will remain until the totem expires or dies. Use the standard Glow setting to add a glow effect.",
					width = 1.5,
					get = function(info)
						return Spell.isTotem
					end,
					set = function(info, value) 
						Spell.isTotem = value
						if value then
							-- Auto-enable required settings for totem tracking
							Spell.showOnNPC = true
							Spell.spellTypeSummon = true
							-- Disable incompatible options
							Spell.showBuff = false
							Spell.showDebuff = false
							Spell.spellTypeCastedAuras = false
							Spell.spellTypeInterrupt = false
						end
						UpdateAllNameplates(true)
					end,
				},
			},
		}
	end
end

function fPB.OptionsOnEnable()
	db = fPB.db.profile
	fPB.BuildSpellList()
	fPB.BuildNPCList()
	UpdateAllNameplates()
end

function fPB.ToggleOptions()
	AceConfigDialog:Open("flyPlateBuffs")
end

-- Remove the separate options registration
fPB.OptionsOpen = nil

-- Add optimization settings group
local optimizationSettings = {
    order = 6,
    name = L["Optimization"] or "Optimization",
    type = "group",
    args = {
        -- PROCESSING PERFORMANCE GROUP
        processingGroup = {
            order = 1,
            name = L["Processing Performance"] or "Processing Performance",
            type = "group",
            inline = true,
            args = {
                throttleInterval = {
                    order = 1,
                    name = L["Throttle interval"],
                    type = "range",
                    desc = L["Time in seconds between updates (lower = more updates but higher CPU usage)"] or "Time in seconds between updates (lower = more updates but higher CPU usage)",
                    min = 0,
                    max = 0.5,
                    step = 0.01,
                    set = function(info, value)
                        db[info[#info]] = value
                        -- Update the global throttle interval
                        THROTTLE_INTERVAL = value
                        
                        -- Print status message
                        local msg
                        if value == 0 then
                            msg = "|cFF00FFFF[FlyPlateBuffs]|r Throttling |cFFFF0000disabled|r - Updates will process as fast as possible"
                        else
                            msg = "|cFF00FFFF[FlyPlateBuffs]|r Throttle interval set to |cFF00FF00" .. string.format("%.2f", value) .. "s|r"
                        end
                        print(msg)
                    end,
                },
                limitedScanning = {
                    order = 2,
                    name = L["Limited Scanning"] or "Limited Scanning",
                    type = "toggle",
                    desc = L["Process nameplates in batches to improve performance"] or "Process nameplates in batches to improve performance",
                    width = "full",
                    get = function() return db.limitedScanning end,
                    set = function(_, value) 
                        db.limitedScanning = value 
                        -- Print status message
                        if value then
                            print("|cFF00FFFF[FlyPlateBuffs]|r Limited Scanning |cFF00FF00enabled|r - Nameplates will process in batches of " .. (db.maxPlatesPerUpdate or 3))
                        else
                            print("|cFF00FFFF[FlyPlateBuffs]|r Limited Scanning |cFFFF0000disabled|r - All nameplates will process immediately")
                        end
                    end,
                },
                maxPlatesPerUpdate = {
                    order = 3,
                    name = L["Max nameplates per update"] or "Max nameplates per update",
                    type = "range",
                    desc = L["Maximum number of nameplates to update per frame"] or "Maximum number of nameplates to update per frame",
                    min = 1,
                    max = 10,
                    step = 1,
                    disabled = function() return not db.limitedScanning end,
                    get = function() return db.maxPlatesPerUpdate end,
                    set = function(_, value) 
                        db.maxPlatesPerUpdate = value 
                        
                        -- Print status message
                        local msg = "|cFF00FFFF[FlyPlateBuffs]|r Batch size set to |cFF00FF00" .. value .. " nameplates|r per frame"
                        print(msg)
                    end,
                },
                maxBuffsPerPlate = {
                    order = 4,
                    name = L["Max buffs per nameplate"] or "Max buffs per nameplate",
                    type = "range",
                    desc = L["Controls both the UI layout capacity and performance optimization. Sets the maximum number of buffs/debuffs to process and show on each nameplate."] or "Controls both the UI layout capacity and performance optimization. Sets the maximum number of buffs/debuffs to process and show on each nameplate.",
                    min = 1,
                    max = 40,
                    step = 1,
                    get = function() 
                        return db.maxBuffsPerPlate or (db.buffPerLine * db.numLines)
                    end,
                    set = function(_, value) 
                        db.maxBuffsPerPlate = value 
                        db.maxVisibleAuras = value -- Keep these synced
                        db.limitVisibleAuras = true -- Always enable aura limiting
                        
                        -- Print status message
                        local msg = "|cFF00FFFF[FlyPlateBuffs]|r Max buffs per nameplate set to |cFF00FF00" .. value .. "|r"
                        print(msg)
                        
                        UpdateAllNameplates()
                    end,
                },
                limitedScanningDesc = {
                    order = 5,
                    type = "description",
                    name = L["Limited Scanning processes only a few nameplates each frame, spreading the work across multiple frames for better performance."] or "Limited Scanning processes only a few nameplates each frame, spreading the work across multiple frames for better performance.",
                    width = "full",
                },
                smartBuffFiltering = {
                    order = 6,
                    name = L["Smart Buff Filtering"] or "Smart Buff Filtering",
                    type = "toggle",
                    desc = L["Use optimized early-exit conditions when filtering buffs (improves performance)"] or 
                        "Use optimized early-exit conditions when filtering buffs (improves performance)",
                    width = "full",
                    get = function() return db.smartBuffFiltering end,
                    set = function(_, value) 
                        db.smartBuffFiltering = value 
                        
                        -- Print status message
                        if value then
                            print("|cFF00FFFF[FlyPlateBuffs]|r Smart Buff Filtering |cFF00FF00enabled|r - Buff processing will be optimized (faster CPU performance)")
                        else
                            print("|cFF00FFFF[FlyPlateBuffs]|r Smart Buff Filtering |cFFFF0000disabled|r - Standard buff processing will be used")
                        end
                    end,
                },
                optimizedSorting = {
                    order = 7,
                    name = L["Sort Caching"] or "Sort Caching",
                    type = "toggle",
                    desc = L["Cache sort results to avoid resorting buffs when unnecessary (improves performance)"] or 
                        "Cache sort results to avoid resorting buffs when unnecessary (improves performance)",
                    width = "full",
                    get = function() return db.optimizedSorting end,
                    set = function(_, value) 
                        db.optimizedSorting = value 
                        
                        -- Print status message
                        if value then
                            print("|cFF00FFFF[FlyPlateBuffs]|r Sort Caching |cFF00FF00enabled|r - Improves performance by avoiding unnecessary sorts (20% reduction in CPU usage)")
                            -- Clear all caches so they're rebuilt with latest settings
                            ClearSortCaches()
                        else
                            print("|cFF00FFFF[FlyPlateBuffs]|r Sort Caching |cFFFF0000disabled|r - Buffs will be sorted every frame (higher accuracy, more CPU usage)")
                            -- Clear all caches when disabling since they're no longer valid
                            ClearSortCaches()
                        end
                    end,
                },
                sortCacheAggressiveness = {
                    order = 8,
                    name = L["Sort Cache Tolerance"] or "Sort Cache Tolerance",
                    type = "select",
                    desc = L["How tolerant the sort cache should be of changes (higher = more cache hits but less accurate sorting)"] or 
                        "How tolerant the sort cache should be of changes (higher = more cache hits but less accurate sorting)",
                    width = "full",
                    disabled = function() return not db.optimizedSorting end,
                    values = {
                        [1] = L["Low (Sort More Often)"] or "Low (Sort More Often)",
                        [2] = L["Medium (Balanced)"] or "Medium (Balanced)",
                        [3] = L["High (Maximum Performance)"] or "High (Maximum Performance)",
                    },
                    get = function() return db.sortCacheTolerance or 2 end,
                    set = function(_, value)
                        db.sortCacheTolerance = value
                        
                        local toleranceDesc = "Medium (Balanced)"
                        if value == 1 then
                            toleranceDesc = "Low (Sort More Often)"
                        elseif value == 3 then
                            toleranceDesc = "High (Maximum Performance)"
                        end
                        
                        print("|cFF00FFFF[FlyPlateBuffs]|r Sort Cache Tolerance set to |cFF00FF00" .. toleranceDesc .. "|r")
                        
                        -- Clear any existing sort caches
                        if fPB.wipeAllSortCaches then
                            fPB.wipeAllSortCaches()
                        end
                    end,
                },
            },
        },
        
        -- MEMORY OPTIMIZATION GROUP
        memoryGroup = {
            order = 2,
            name = L["Memory Optimization"] or "Memory Optimization",
            type = "group",
            inline = true,
            args = {
                tableRecycling = {
                    order = 1,
                    name = L["Table Recycling"] or "Table Recycling",
                    type = "toggle",
                    desc = L["Recycle tables to reduce garbage collection"] or "Recycle tables to reduce garbage collection",
                    width = "full",
                    get = function() return db.tableRecycling end,
                    set = function(_, value) 
                        db.tableRecycling = value 
                        
                        -- Print status message
                        if value then
                            print("|cFF00FFFF[FlyPlateBuffs]|r Table Recycling |cFF00FF00enabled|r - Memory usage will be optimized")
                        else
                            print("|cFF00FFFF[FlyPlateBuffs]|r Table Recycling |cFFFF0000disabled|r - Standard memory management will be used")
                        end
                    end,
                },
                tableRecyclingDesc = {
                    order = 2,
                    type = "description",
                    name = L["Table recycling keeps temporary tables in a pool and reuses them instead of creating new ones. This reduces memory fragmentation and garbage collection stutters."] or 
                        "Table recycling keeps temporary tables in a pool and reuses them instead of creating new ones. This reduces memory fragmentation and garbage collection stutters.",
                    width = "full",
                },
            },
        },
        
        -- VISUAL ADAPTATIONS GROUP
        visualGroup = {
            order = 3,
            name = L["Visual Adaptations"] or "Visual Adaptations",
            type = "group",
            inline = true,
            args = {
                adaptiveDetail = {
                    order = 1,
                    name = L["Enable Adaptive Detail"] or "Enable Adaptive Detail",
                    type = "toggle",
                    desc = L["Automatically adjust visual detail based on number of visible nameplates for improved performance"] or 
                        "Automatically adjust visual detail based on number of visible nameplates for improved performance",
                    width = "full",
                    get = function() return db.adaptiveDetail end,
                    set = function(_, value) 
                        db.adaptiveDetail = value 
                        
                        -- Print status message
                        if value then
                            print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive Detail |cFF00FF00enabled|r - Detail level will adjust based on nameplate count")
                        else
                            print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive Detail |cFFFF0000disabled|r - Full detail level will be used at all times")
                        end
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                adaptiveDetailDesc = {
                    order = 2,
                    type = "description",
                    name = L["Adaptive detail reduces visual effects when many nameplates are visible to maintain performance in crowded areas."] or 
                        "Adaptive detail reduces visual effects when many nameplates are visible to maintain performance in crowded areas.",
                    width = "full",
                },
                thresholdsHeader = {
                    order = 3,
                    type = "header",
                    name = L["Detail Thresholds"] or "Detail Thresholds",
                },
                lowThreshold = {
                    order = 4,
                    name = L["Low Detail Threshold"] or "Low Detail Threshold",
                    type = "range",
                    desc = L["Number of nameplates at which to start reducing detail"] or 
                        "Number of nameplates at which to start reducing detail",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    min = 5,
                    max = 30,
                    step = 1,
                    get = function() return db.adaptiveThresholds.low end,
                    set = function(_, value) 
                        -- Ensure thresholds remain in correct order
                        db.adaptiveThresholds.low = value
                        if db.adaptiveThresholds.medium < value + 5 then
                            db.adaptiveThresholds.medium = value + 5
                        end
                        if db.adaptiveThresholds.high < db.adaptiveThresholds.medium + 5 then
                            db.adaptiveThresholds.high = db.adaptiveThresholds.medium + 5
                        end
                        
                        -- Print status message
                        print("|cFF00FFFF[FlyPlateBuffs]|r Low detail threshold set to |cFF00FF00" .. value .. "|r nameplates")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                mediumThreshold = {
                    order = 5,
                    name = L["Medium Detail Threshold"] or "Medium Detail Threshold",
                    type = "range",
                    desc = L["Number of nameplates at which to further reduce detail"] or 
                        "Number of nameplates at which to further reduce detail",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    min = 10, -- Static number instead of function
                    max = 40,
                    step = 1,
                    get = function() return db.adaptiveThresholds.medium end,
                    set = function(_, value) 
                        -- Ensure thresholds remain in correct order
                        db.adaptiveThresholds.medium = value
                        if db.adaptiveThresholds.high < value + 5 then
                            db.adaptiveThresholds.high = value + 5
                        end
                        
                        -- Print status message
                        print("|cFF00FFFF[FlyPlateBuffs]|r Medium detail threshold set to |cFF00FF00" .. value .. "|r nameplates")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                highThreshold = {
                    order = 6,
                    name = L["Minimum Detail Threshold"] or "Minimum Detail Threshold",
                    type = "range",
                    desc = L["Number of nameplates at which to use minimum detail"] or 
                        "Number of nameplates at which to use minimum detail",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    min = 15, -- Static number instead of function
                    max = 50,
                    step = 1,
                    get = function() return db.adaptiveThresholds.high end,
                    set = function(_, value) 
                        db.adaptiveThresholds.high = value
                        
                        -- Print status message
                        print("|cFF00FFFF[FlyPlateBuffs]|r Minimum detail threshold set to |cFF00FF00" .. value .. "|r nameplates")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                featureHeader = {
                    order = 7,
                    type = "header",
                    name = L["Adaptive Features"] or "Adaptive Features",
                },
                adaptiveGlows = {
                    order = 8,
                    name = L["Adjust Glow Effects"] or "Adjust Glow Effects",
                    type = "toggle",
                    desc = L["Reduce or disable glow effects at higher nameplate counts"] or 
                        "Reduce or disable glow effects at higher nameplate counts",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    get = function() return db.adaptiveFeatures.glows end,
                    set = function(_, value) 
                        db.adaptiveFeatures.glows = value 
                        
                        -- Print status message
                        local status = value and "enabled" or "disabled"
                        local statusColor = value and "|cFF00FF00" or "|cFFFF0000"
                        print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive glow effects " .. statusColor .. status .. "|r")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                adaptiveAnimations = {
                    order = 9,
                    name = L["Adjust Animations"] or "Adjust Animations",
                    type = "toggle",
                    desc = L["Reduce or disable animations at higher nameplate counts"] or 
                        "Reduce or disable animations at higher nameplate counts",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    get = function() return db.adaptiveFeatures.animations end,
                    set = function(_, value) 
                        db.adaptiveFeatures.animations = value 
                        
                        -- Print status message
                        local status = value and "enabled" or "disabled"
                        local statusColor = value and "|cFF00FF00" or "|cFFFF0000"
                        print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive animations " .. statusColor .. status .. "|r")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                adaptiveCooldownSwipes = {
                    order = 10,
                    name = L["Adjust Cooldown Swipes"] or "Adjust Cooldown Swipes",
                    type = "toggle",
                    desc = L["Reduce or disable cooldown swipes at higher nameplate counts"] or 
                        "Reduce or disable cooldown swipes at higher nameplate counts",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    get = function() return db.adaptiveFeatures.cooldownSwipes end,
                    set = function(_, value) 
                        db.adaptiveFeatures.cooldownSwipes = value 
                        
                        -- Print status message
                        local status = value and "enabled" or "disabled"
                        local statusColor = value and "|cFF00FF00" or "|cFFFF0000"
                        print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive cooldown swipes " .. statusColor .. status .. "|r")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
                adaptiveTextUpdates = {
                    order = 11,
                    name = L["Adjust Text Update Frequency"] or "Adjust Text Update Frequency",
                    type = "toggle",
                    desc = L["Reduce frequency of text updates at higher nameplate counts"] or 
                        "Reduce frequency of text updates at higher nameplate counts",
                    width = "full",
                    disabled = function() return not db.adaptiveDetail end,
                    get = function() return db.adaptiveFeatures.textUpdates end,
                    set = function(_, value) 
                        db.adaptiveFeatures.textUpdates = value 
                        
                        -- Print status message
                        local status = value and "enabled" or "disabled"
                        local statusColor = value and "|cFF00FF00" or "|cFFFF0000"
                        print("|cFF00FFFF[FlyPlateBuffs]|r Adaptive text updates " .. statusColor .. status .. "|r")
                        
                        -- Update all nameplates to reflect the change
                        UpdateAllNameplates()
                    end,
                },
            },
        },
    },
}

-- Add debug settings group
local debugSettings = {
    order = 7,
    name = L["Debug Tools"] or "Debug Tools",
    type = "group",
    args = {
        debugHeader = {
            order = 1,
            type = "header",
            name = L["Debug Settings"] or "Debug Settings",
        },
        debugEnabled = {
            order = 2,
            type = "toggle",
            name = L["Enable debugging"] or "Enable debugging",
            desc = L["Enables the debugging tools"] or "Enables the debugging tools",
            width = "full",
            get = function() return fPB.debug.enabled end,
            set = function(_, value) 
                fPB.debug.enabled = value 
                db.debugEnabled = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Debugging |cFF00FF00enabled|r - Debug tools are now active")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Debugging |cFFFF0000disabled|r - Debug tools are now inactive")
                end
            end,
        },
        debugPerformance = {
            order = 3,
            type = "toggle",
            name = L["Track performance"] or "Track performance",
            desc = L["Track function execution times"] or "Track function execution times",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.performance end,
            set = function(_, value) 
                fPB.debug.performance = value 
                db.debugPerformance = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Performance tracking |cFF00FF00enabled|r")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Performance tracking |cFFFF0000disabled|r")
                end
            end,
        },
        debugMemory = {
            order = 4,
            type = "toggle",
            name = L["Track memory usage"] or "Track memory usage",
            desc = L["Track addon memory consumption"] or "Track addon memory consumption",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.memory end,
            set = function(_, value) 
                fPB.debug.memory = value 
                db.debugMemory = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Memory usage tracking |cFF00FF00enabled|r")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Memory usage tracking |cFFFF0000disabled|r")
                end
            end,
        },
        debugEvents = {
            order = 5,
            type = "toggle",
            name = L["Track events"] or "Track events",
            desc = L["Log processing events"] or "Log processing events",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.events end,
            set = function(_, value) 
                fPB.debug.events = value 
                db.debugEvents = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Event logging |cFF00FF00enabled|r")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Event logging |cFFFF0000disabled|r")
                end
            end,
        },
        debugVerbose = {
            order = 6,
            type = "toggle",
            name = L["Verbose mode"] or "Verbose mode",
            desc = L["Print debug messages to chat"] or "Print debug messages to chat",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.verbose end,
            set = function(_, value) 
                fPB.debug.verbose = value 
                db.debugVerbose = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Verbose debugging |cFF00FF00enabled|r - Messages will be printed to chat")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Verbose debugging |cFFFF0000disabled|r - Messages will be logged but not printed")
                end
            end,
        },
        
        debugCacheMessages = {
            order = 9,
            type = "toggle",
            name = L["Show Cache Messages"] or "Show Cache Messages",
            desc = L["Display detailed information about cache hits and misses"] or "Display detailed information about cache hits and misses",
            width = "full",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return db.debugCacheMessages end,
            set = function(_, value) 
                db.debugCacheMessages = value 
                fPB.debug.cacheMessages = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Cache debug messages |cFF00FF00enabled|r - You'll see detailed information about cache operations")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Cache debug messages |cFFFF0000disabled|r - Cache messages will be suppressed")
                end
            end,
        },
        
        debugFilterMessages = {
            order = 10,
            type = "toggle",
            name = L["Show Filter Messages"] or "Show Filter Messages",
            desc = L["Display detailed information about buff filtering optimization"] or "Display detailed information about buff filtering optimization",
            width = "full",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return db.debugFilterMessages end,
            set = function(_, value) 
                db.debugFilterMessages = value 
                fPB.debug.filterMessages = value
                
                -- Print status message
                if value then
                    print("|cFF00FFFF[FlyPlateBuffs]|r Filter debug messages |cFF00FF00enabled|r - You'll see detailed information about buffer filtering")
                else
                    print("|cFF00FFFF[FlyPlateBuffs]|r Filter debug messages |cFFFF0000disabled|r - Filter messages will be suppressed")
                end
            end,
        },
        
        -- Advanced debug settings header
        advancedHeader = {
            order = 10,
            type = "header",
            name = L["Advanced Debug Settings"] or "Advanced Debug Settings",
        },
        
        -- Sampling rate slider
        samplingRate = {
            order = 11,
            type = "range",
            name = L["Sampling rate"] or "Sampling rate",
            desc = L["Percentage of function calls to track (lower = better performance)"] or "Percentage of function calls to track (lower = better performance)",
            min = 1,
            max = 100,
            step = 1,
            width = "full",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.samplingRate end,
            set = function(_, value) 
                fPB.debug.samplingRate = value 
                db.debugSamplingRate = value
                
                -- Print status message
                print("|cFF00FFFF[FlyPlateBuffs]|r Debug sampling rate set to |cFF00FF00" .. value .. "%|r")
            end,
        },
        
        -- Memory tracking frequency dropdown
        memoryTrackingFrequency = {
            order = 12,
            type = "select",
            style = "dropdown",
            name = L["Memory tracking frequency"] or "Memory tracking frequency",
            desc = L["How often to track memory usage"] or "How often to track memory usage",
            disabled = function() return not fPB.debug.enabled or not fPB.debug.memory end,
            values = {
                [0] = L["Every update"] or "Every update",
                [1] = L["Every second"] or "Every second",
                [5] = L["Every 5 seconds"] or "Every 5 seconds",
                [10] = L["Every 10 seconds"] or "Every 10 seconds",
            },
            get = function() return fPB.debug.memoryTrackingFrequency end,
            set = function(_, value) 
                fPB.debug.memoryTrackingFrequency = value 
                db.debugMemoryTrackingFrequency = value
                
                -- Print status message
                local frequencyText
                if value == 0 then
                    frequencyText = "every update"
                elseif value == 1 then
                    frequencyText = "every second"
                else
                    frequencyText = "every " .. value .. " seconds"
                end
                print("|cFF00FFFF[FlyPlateBuffs]|r Memory tracking frequency set to |cFF00FF00" .. frequencyText .. "|r")
            end,
        },
        
        -- Significant memory changes only
        significantMemoryChangeOnly = {
            order = 13,
            type = "toggle",
            name = L["Track only significant memory changes"] or "Track only significant memory changes",
            desc = L["Only log memory changes above the threshold"] or "Only log memory changes above the threshold",
            width = "full",
            disabled = function() return not fPB.debug.enabled or not fPB.debug.memory end,
            get = function() return fPB.debug.significantMemoryChangeOnly end,
            set = function(_, value) 
                fPB.debug.significantMemoryChangeOnly = value 
                db.debugSignificantMemoryChangeOnly = value
            end,
        },
        
        -- Memory change threshold
        memoryChangeThreshold = {
            order = 14,
            type = "range",
            name = L["Memory change threshold (KB)"] or "Memory change threshold (KB)",
            desc = L["Only log memory changes larger than this value"] or "Only log memory changes larger than this value",
            min = 5,
            max = 200,
            step = 5,
            disabled = function() return not fPB.debug.enabled or not fPB.debug.memory or not fPB.debug.significantMemoryChangeOnly end,
            get = function() return fPB.debug.memoryChangeThreshold end,
            set = function(_, value) fPB.debug.memoryChangeThreshold = value end,
        },
        
        -- Unit name filter
        unitNameFilter = {
            order = 15,
            type = "input",
            name = L["Filter debug by unit name"] or "Filter debug by unit name",
            desc = L["Only show debug info for units containing this text (case insensitive, leave empty to show all)"] or "Only show debug info for units containing this text (case insensitive, leave empty to show all)",
            width = "full",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.unitNameFilter end,
            set = function(_, value) fPB.debug.unitNameFilter = value end,
        },
        
        -- Auto-disable after X seconds
        autoDisableAfter = {
            order = 16,
            type = "range",
            name = L["Auto-disable after seconds"] or "Auto-disable after seconds",
            desc = L["Automatically disable debugging after this many seconds (0 = never)"] or "Automatically disable debugging after this many seconds (0 = never)",
            min = 0,
            max = 300,
            step = 10,
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.autoDisableAfter end,
            set = function(_, value) fPB.debug.autoDisableAfter = value end,
        },
        
        -- Detail level dropdown
        detailLevel = {
            order = 17,
            type = "select",
            style = "dropdown",
            name = L["Detail level"] or "Detail level",
            desc = L["How much detail to include in debug logs"] or "How much detail to include in debug logs",
            disabled = function() return not fPB.debug.enabled end,
            values = {
                [1] = L["Low (performance critical)"] or "Low (performance critical)",
                [2] = L["Medium (balanced)"] or "Medium (balanced)",
                [3] = L["High (more verbose)"] or "High (more verbose)",
            },
            get = function() return fPB.debug.detailLevel end,
            set = function(_, value) fPB.debug.detailLevel = value end,
        },
        
        -- Dynamic throttling
        dynamicThrottlingEnabled = {
            order = 18,
            type = "toggle",
            name = L["Enable dynamic throttling"] or "Enable dynamic throttling",
            desc = L["Automatically reduce sampling rate when many nameplates are present"] or "Automatically reduce sampling rate when many nameplates are present",
            width = "full",
            disabled = function() return not fPB.debug.enabled end,
            get = function() return fPB.debug.dynamicThrottlingEnabled end,
            set = function(_, value) fPB.debug.dynamicThrottlingEnabled = value end,
        },
        
        -- Action buttons
        buttonsHeader = {
            order = 20,
            type = "header",
            name = L["Debug Actions"] or "Debug Actions",
        },
        
        showDebugStats = {
            order = 21,
            type = "execute",
            name = L["Show debug stats"] or "Show debug stats",
            desc = L["Display current debugging statistics"] or "Display current debugging statistics",
            disabled = function() return not fPB.debug.enabled end,
            func = function() fPB.ShowDebugStats() end,
        },
        
        resetDebugStats = {
            order = 22,
            type = "execute",
            name = L["Reset debug stats"] or "Reset debug stats",
            desc = L["Reset all debugging counters and timers"] or "Reset all debugging counters and timers",
            disabled = function() return not fPB.debug.enabled end,
            func = function()
                fPB.debug.updateCounts = 0
                fPB.debug.skippedUpdates = 0
                fPB.debug.startTime = GetTime()
                fPB.debug.functionTimes = {}
                fPB.debug.memoryUsage = {}
                fPB.debug.logEntries = {}
                print("|cFF00FFFF[FlyPlateBuffs]|r Debug statistics reset.")
            end,
        },
    },
}

-- Add version retrieval function
local function GetAddonVersion()
    -- Try C_AddOns first (new API)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata("flyPlateBuffs", "Version")
    end
    -- Fallback to old API
    if GetAddOnMetadata then
        return GetAddOnMetadata("flyPlateBuffs", "Version")
    end
    -- Final fallback
    return "Unknown"
end

fPB.MainOptionTable = {
	name = L["FlyPlateBuffs"],
	type = "group",
	childGroups = "tab",
	get = function(info)
        return db[info[#info]]
    end,

	set = function(info, value)
        db[info[#info]] = value
		UpdateAllNameplates()
    end,

	args = {
		mainDescription = {
			order = 0,
			type = "description",
			name = "|cFF6495EDFlyPlateBuffs|r - " .. L["Elegant buff and debuff display for nameplates"] .. "\n\n" ..
				L["Configure how buffs and debuffs appear on nameplates. Use the tabs below to access different settings categories."],
			fontSize = "medium",
			width = "full",
		},
		general = {
			name = "|cFFE6CC80" .. L["General"] .. "|r",
			desc = L["Basic settings and filtering options"],
			type = "group",
			order = 3,
			args = {
				generalDescription = {
					order = 0,
					type = "description",
					name = L["Configure which buffs and debuffs are displayed and which unit types show auras."],
					fontSize = "medium",
					width = "full",
				},
				unitTypeGroup = {
					order = 1,
					name = "|cFFFFFFFF" .. L["Unit Types"] .. "|r",
					type = "group",
					inline = true,
					args = {
						unitTypeDesc = {
							order = 0,
							type = "description",
							name = L["Choose which types of units should display auras"],
							fontSize = "small",
							width = "full",
						},
						showOnPlayers = {
							order = 1,
							type = "toggle",
							name = L["Players"],
							desc = L["Show on players"],
							width = "half",
						},
						showOnPets = {
							order = 2, 
							type = "toggle",
							name = L["Pets"],
							desc = L["Show on pets"],
							width = "half",
						},
						showOnNPC = {
							order = 3,
							type = "toggle", 
							name = L["NPCs"],
							desc = L["Show on NPCs"],
							width = "half",
						},
						showOnEnemy = {
							order = 4,
							type = "toggle",
							name = L["Enemies"],
							desc = L["Show on enemy units"],
							width = "half", 
						},
						showOnFriend = {
							order = 5,
							type = "toggle",
							name = L["Friendly"],
							desc = L["Show on friendly units"],
							width = "half",
						},
						showOnNeutral = {
							order = 6,
							type = "toggle",
							name = L["Neutral"],
							desc = L["Show on neutral units"],
							width = "half",
						},
					},
				},

				auraFilterGroup = {
					order = 2,
					name = "|cFFFFFFFF" .. L["Aura Filtering"] .. "|r",
					type = "group",
					inline = true,
					args = {
						auraFilterDesc = {
							order = 0,
							type = "description",
							name = L["Configure which types of auras to display"],
							fontSize = "small",
							width = "full",
						},
						showBuffs = {
							order = 1,
							type = "select",
							name = L["Show Buffs"],
							desc = L["Which buffs to display"],
							values = {
								[1] = L["All buffs"],
								[2] = L["Mine + Listed"],
								[3] = L["Only Listed"],
								[4] = L["Only Mine"],
								[5] = L["None"],
							},
							width = "double",
						},
						showDebuffs = {
							order = 2,
							type = "select",
							name = L["Show Debuffs"],
							desc = L["Which debuffs to display"],
							values = {
								[1] = L["All debuffs"],
								[2] = L["Mine + Listed"],
								[3] = L["Only Listed"],
								[4] = L["Only Mine"],
								[5] = L["None"],
							},
							width = "double",
						},
						hidePermanent = {
							order = 3,
							type = "toggle",
							name = L["Hide Permanent"],
							desc = L["Hide auras with no duration"],
							width = "full",
						},
					},
				},

				visualGroup = {
					order = 3,
					name = "|cFFFFFFFF" .. L["Visual Settings"] .. "|r",
					type = "group",
					inline = true,
					args = {
						visualDesc = {
							order = 0,
							type = "description",
							name = L["Configure the visual appearance of auras"],
							fontSize = "small",
							width = "full",
						},
						baseWidth = {
							order = 1,
							type = "range",
							name = L["Icon Width"],
							min = 16,
							max = 64,
							step = 1,
							width = "full",
						},
						baseHeight = {
							order = 2,
							type = "range",
							name = L["Icon Height"],
							min = 16,
							max = 64,
							step = 1,
							width = "full",
						},
						myScale = {
							order = 3,
							type = "range",
							name = L["My Auras Scale"],
							desc = L["Scale multiplier for your own auras"],
							min = 0,
							max = 2,
							step = 0.05,
							width = "full",
						},
						cropTexture = {
							order = 4,
							type = "toggle",
							name = L["Crop Icons"],
							desc = L["Crop icon textures to fit dimensions"],
							width = "full",
						},
					},
				},

				layoutGroup = {
					order = 4,
					name = "|cFFFFFFFF" .. L["Layout"] .. "|r",
					type = "group",
					inline = true,
					args = {
						layoutDesc = {
							order = 0,
							type = "description",
							name = L["Configure how icons are arranged"],
							fontSize = "small",
							width = "full",
						},
						buffPerLine = {
							order = 1,
							type = "range",
							name = L["Icons Per Row"],
							min = 1,
							max = 20,
							step = 1,
							width = "full",
						},
						numLines = {
							order = 2,
							type = "range",
							name = L["Number of Rows"],
							min = 1,
							max = 10,
							step = 1,
							width = "full",
						},
						xInterval = {
							order = 3,
							type = "range",
							name = L["Horizontal Spacing"],
							min = 0,
							max = 20,
							step = 1,
							width = "full",
						},
						yInterval = {
							order = 4,
							type = "range",
							name = L["Vertical Spacing"],
							min = 0,
							max = 20,
							step = 1,
							width = "full",
						},
						buffAnchorPoint = {
							order = 5,
							type = "select",
							name = L["Anchor Point"],
							desc = L["Where to anchor the aura frame"],
							values = {
								["TOP"] = L["Top"],
								["BOTTOM"] = L["Bottom"],
								["LEFT"] = L["Left"],
								["RIGHT"] = L["Right"],
								["CENTER"] = L["Center"],
							},
							width = "full",
						},
						xOffset = {
							order = 6,
							type = "range",
							name = L["X Offset"],
							min = -100,
							max = 100,
							step = 1,
							width = "full",
						},
						yOffset = {
							order = 7,
							type = "range",
							name = L["Y Offset"],
							min = -100,
							max = 100,
							step = 1,
							width = "full",
						},
					},
				},

				textGroup = {
					order = 5,
					name = "|cFFFFFFFF" .. L["Text"] .. "|r",
					type = "group",
					inline = true,
					args = {
						textDesc = {
							order = 0,
							type = "description",
							name = L["Configure text appearance"],
							fontSize = "small",
							width = "full",
						},
						font = {
							order = 1,
							type = "select",
							dialogControl = "LSM30_Font",
							name = L["Duration Font"],
							values = AceGUIWidgetLSMlists.font,
							width = "double",
						},
						stackFont = {
							order = 2,
							type = "select",
							dialogControl = "LSM30_Font",
							name = L["Stack Count Font"],
							values = AceGUIWidgetLSMlists.font,
							width = "double",
						},
						stackSize = {
							order = 3,
							type = "range",
							name = L["Stack Count Size"],
							min = 6,
							max = 24,
							step = 1,
							width = "full",
						},
						durationSize = {
							order = 4,
							type = "range",
							name = L["Duration Text Size"],
							min = 6,
							max = 24,
							step = 1,
							width = "full",
						},
						iconScale = {
							name = "Icon scale",
							desc = "Scale of the icon",
							type = "range",
							order = 5.1,
							min = 0.3,
							max = 2,
							step = 0.1,
							width = 1,
						},
						IconId = {
							name = "Icon ID",
							desc = "Icon ID",
							type = "input",
							order = 4,
							width = 1,
						},
					},
				},
			},
		},
		appearance = {
			order = 2,
			name = "|cFFE6CC80" .. L["Appearance"] .. "|r",
			desc = L["Configure the visual appearance of auras"],
			type = "group",
			childGroups = "tab",
			args = {
				icons = {
					order = 1,
					name = "|cFFE6CC80" .. L["Icons"] .. "|r",
					type = "group",
					args = {
						iconBasics = {
							order = 1,
							name = "|cFFFFFFFF" .. L["Basic Settings"] .. "|r",
							type = "group",
							inline = true,
							args = {
								baseWidth = {
									order = 1,
									type = "range",
									name = L["Base Width"],
									desc = L["Base width of buff icons"],
									min = minIconSize,
									max = maxIconSize,
									step = 1,
									width = "full",
								},
								baseHeight = {
									order = 2,
									type = "range",
									name = L["Base Height"],
									desc = L["Base height of buff icons"],
									min = minIconSize,
									max = maxIconSize,
									step = 1,
									width = "full",
								},
								myScale = {
									order = 3,
									type = "range",
									name = L["My Auras Scale"],
									desc = L["Additional scale for your own auras"],
									min = 0,
									max = 1,
									step = 0.05,
									width = "full",
								},
								cropTexture = {
									order = 4,
									type = "toggle",
									name = L["Crop Icons"],
									desc = L["Crop icon textures to fit dimensions"],
									width = "full",
								},
							},
						},
						borders = {
							order = 2,
							name = "|cFFFFFFFF" .. L["Borders"] .. "|r",
							type = "group",
							inline = true,
							args = {
								borderStyle = {
									order = 1,
									type = "select",
									name = L["Border Style"],
									width = "full",
									values = {
										[0] = L["None"],
										[1] = L["FlyPlateBuffs Default"],
									},
									disabled = function() return db.iconMasque end,
								},
								borderSize = {
									order = 2,
									type = "range",
									name = L["Border Size"],
									desc = L["Adjust the thickness of the border"],
									min = 0.5,
									max = 2,
									step = 0.1,
									width = "full",
									disabled = function() return db.borderStyle == 0 or db.iconMasque end,
								},
								colorizeBorder = {
									order = 3,
									type = "toggle",
									name = L["Colorize Border"],
									desc = L["Color borders based on aura type"],
									width = "full",
									disabled = function() return db.borderStyle == 0 or db.iconMasque end,
								},
								colorTypes = {
									order = 4,
									type = "group",
									name = L["Border Colors"],
									inline = true,
									disabled = function() return not db.colorizeBorder or db.borderStyle == 0 or db.iconMasque end,
									args = {
										magic = {
											order = 1,
											type = "color",
											name = L["Magic"],
											get = function() return unpack(db.colorTypes.Magic or {0.20, 0.60, 1.00}) end,
											set = function(_, r, g, b) db.colorTypes.Magic = {r, g, b}; UpdateAllNameplates(true) end,
										},
										curse = {
											order = 2,
											type = "color",
											name = L["Curse"],
											get = function() return unpack(db.colorTypes.Curse or {0.60, 0.00, 1.00}) end,
											set = function(_, r, g, b) db.colorTypes.Curse = {r, g, b}; UpdateAllNameplates(true) end,
										},
										disease = {
											order = 3,
											type = "color",
											name = L["Disease"],
											get = function() return unpack(db.colorTypes.Disease or {0.60, 0.40, 0.00}) end,
											set = function(_, r, g, b) db.colorTypes.Disease = {r, g, b}; UpdateAllNameplates(true) end,
										},
										poison = {
											order = 4,
											type = "color",
											name = L["Poison"],
											get = function() return unpack(db.colorTypes.Poison or {0.00, 0.60, 0.00}) end,
											set = function(_, r, g, b) db.colorTypes.Poison = {r, g, b}; UpdateAllNameplates(true) end,
										},
										buff = {
									order = 5,
											type = "color",
											name = L["Buff"],
											get = function() return unpack(db.colorTypes.Buff or {0.00, 1.00, 0.00}) end,
											set = function(_, r, g, b) db.colorTypes.Buff = {r, g, b}; UpdateAllNameplates(true) end,
										},
										none = {
											order = 6,
											type = "color",
											name = L["Other"],
											get = function() return unpack(db.colorTypes.none or {0.80, 0.00, 0.00}) end,
											set = function(_, r, g, b) db.colorTypes.none = {r, g, b}; UpdateAllNameplates(true) end,
										},
									},
								},
							},
						},
						masque = {
							order = 3,
							name = "|cFFFFFFFF" .. L["Masque Support"] .. "|r",
							type = "group",
							inline = true,
							args = {
								iconMasque = {
									order = 1,
									type = "toggle",
									name = L["Enable Masque Support"],
									desc = L["Allow Masque addon to skin the icons"],
									width = "full",
									set = function(info, value)
										local currentValue = db.iconMasque
										
										-- Create a static popup dialog if it doesn't exist
										if not StaticPopupDialogs["FLYPLATEBUFFS_RELOAD_UI"] then
											StaticPopupDialogs["FLYPLATEBUFFS_RELOAD_UI"] = {
												text = "FlyPlateBuffs: Masque setting changed. A UI reload is required for this change to take effect properly.\n\nReload UI now?",
												button1 = "Yes",
												button2 = "No",
												OnAccept = function()
													db.iconMasque = value
													ReloadUI()
												end,
												OnCancel = function()
													if info and info.option and info.option.get then
														local widget = info.option.get(info)
														if widget and widget.SetValue then
															widget:SetValue(currentValue)
														end
													else
														db.iconMasque = currentValue
													end
												end,
												timeout = 0,
												whileDead = true,
												hideOnEscape = true,
												preferredIndex = 3,
											}
										end
										
										-- Show the reload prompt
										StaticPopup_Show("FLYPLATEBUFFS_RELOAD_UI")
									end,
								},
							},
						},
					},
				},
				layout = {
					order = 2,
					name = "|cFFE6CC80" .. L["Layout"] .. "|r",
					type = "group",
					args = {
						parentFrame = {
							order = 0,
							name = "|cFFFFFFFF" .. L["Frame Parent"] .. "|r",
							type = "group",
							inline = true,
							args = {
								parentWorldFrame = {
									order = 1,
									type = "toggle",
									name = L["Parent to WorldFrame"],
									desc = L["Parent icons to WorldFrame instead of nameplates"],
									width = "full",
								},
								frameLevel = {
									order = 2,
									type = "range",
									name = L["Frame Level"],
									desc = L["Adjust the frame stacking level"],
									min = 1,
									max = 10,
									step = 1,
									width = "full",
								},
							},
						},
						grid = {
							order = 1,
							name = "|cFFFFFFFF" .. L["Grid Layout"] .. "|r",
							type = "group",
							inline = true,
							args = {
								buffPerLine = {
									order = 1,
									type = "range",
									name = L["Icons Per Row"],
									min = 1,
									max = 20,
									step = 1,
									width = "full",
								},
								
								numLines = {
									order = 2,
									type = "range",
									name = L["Number of Rows"],
									min = 1,
									max = 10,
									step = 1,
									width = "full",
								},
								xInterval = {
									order = 3,
									type = "range",
									name = L["Horizontal Spacing"],
									min = minInterval,
									max = maxInterval,
									step = 1,
									width = "full",
								},
								yInterval = {
									order = 4,
									type = "range",
									name = L["Vertical Spacing"],
									min = minInterval,
									max = maxInterval,
									step = 1,
									width = "full",
								},
							},
						},
						position = {
							order = 2,
							name = "|cFFFFFFFF" .. L["Position"] .. "|r",
							type = "group",
							inline = true,
							args = {
								buffAnchorPoint = {
									order = 1,
									type = "select",
									name = L["Anchor Point"],
									desc = L["Where to anchor the aura frame"],
									values = {
										["TOP"] = L["Top"],
										["BOTTOM"] = L["Bottom"],
										["LEFT"] = L["Left"],
										["RIGHT"] = L["Right"],
										["CENTER"] = L["Center"],
									},
									width = "full",
								},
								xOffset = {
									order = 2,
									type = "range",
									name = L["X Offset"],
									min = -100,
									max = 100,
									step = 1,
									width = "full",
								},
								yOffset = {
									order = 3,
									type = "range",
									name = L["Y Offset"],
									min = -100,
									max = 100,
									step = 1,
									width = "full",
								},
							},
						},
						sorting = {
							order = 3,
							name = "|cFFFFFFFF" .. L["Sorting"] .. "|r",
							type = "group",
							inline = true,
							args = {
								sortMethod = {
									order = 1,
									type = "select",
									style = "dropdown",
									name = L["Sorting method"],
									desc = L["Select how to sort buffs and debuffs"],
									values = SortMethodNames,
									width = "full",
								},
								reversSort = {
									order = 2,
									type = "toggle",
									name = L["Reverse sorting"],
									desc = L["Reverse the sort direction"],
									width = "full",
								},
								disableSort = {
									order = 3,
									type = "toggle",
									name = L["Disable sorting"],
									desc = L["Don't sort auras at all"],
									width = "full",
								},
								cacheSettingsNote = {
									order = 4,
									type = "description",
									name = "|cFFFFD100" .. L["Cache settings (Sort Cache Tolerance and Show Cache Hit Messages) can be found in the Performance tab under Advanced settings."] .. "|r",
									width = "full",
								},
							},
						},
					},
				},
				text = {
					order = 3,
					name = "|cFFE6CC80" .. L["Text"] .. "|r",
					type = "group",
					args = {
						stack = {
							order = 2,
							name = "|cFFFFFFFF" .. L["Stack Text"] .. "|r",
							type = "group",
							inline = true,
							args = {
								showStackText = {
									order = 1,
									type = "toggle",
									name = L["Show Stack Count"],
							width = "full",
						},
								stackSize = {
									order = 2,
									type = "range",
									name = L["Text Size"],
									min = minTextSize,
									max = maxTextSize,
									step = 1,
									width = "full",
								},
								stackOverride = {
									order = 3,
									type = "toggle",
									name = L["Override Stack Settings"],
									desc = L["Override global stack settings for this aura"],
									width = "full",
								},
								stackScale = {
									order = 4,
									type = "toggle",
									name = L["Scale Stack Text"],
									desc = L["Scale stack text with icon size"],
									width = "full",
								},
								stackSpecific = {
									order = 5,
									type = "toggle",
									name = L["Specific Stack Settings"],
									desc = L["Use specific settings for stack text"],
									width = "full",
								},
								stackPosition = {
									order = 6,
									type = "select",
									name = L["Position"],
									values = {
										[1] = L["Bottom right (default)"],
										[2] = L["Bottom left"],
										[3] = L["Top right"],
										[4] = L["Top left"],
										[5] = L["Center"],
									},
									width = "full",
								},
								stackOffset = {
									order = 7,
							type = "group",
							inline = true,
									name = L["Stack Position"],
							args = {
										stackSizeX = {
											order = 1,
											type = "range",
											name = L["X Offset"],
											min = -50,
											max = 50,
											step = 1,
									width = "full",
								},
										stackSizeY = {
											order = 2,
											type = "range",
											name = L["Y Offset"],
											min = -50,
											max = 50,
											step = 1,
											width = "full",
										},
									},
								},
								stackColor = {
									order = 8,
									type = "color",
									name = L["Color"],
									get = function() return unpack(db.stackColor or {1, 1, 1}) end,
									set = function(_, r, g, b) db.stackColor = {r, g, b}; UpdateAllNameplates(true) end,
									width = "full",
								},
							},
						},
						duration = {
							order = 1,
							name = "|cFFFFFFFF" .. L["Duration Text"] .. "|r",
							type = "group",
							inline = true,
							args = {
								showDuration = {
									order = 1,
									type = "toggle",
									name = L["Show Duration"],
									width = "full",
								},
								durationSize = {
									order = 2,
									type = "range",
									name = L["Text Size"],
									min = minTextSize,
									max = maxTextSize,
									step = 1,
									width = "full",
								},
								showDecimals = {
									order = 3,
									type = "toggle",
									name = L["Show Decimals"],
									desc = L["Show decimal places for durations under 10 seconds"],
									width = "full",
								},
								durationPosition = {
									order = 4,
									type = "select",
									name = L["Position"],
									values = {
										[2] = L["On icon (default)"],
										[5] = L["Above icon"],
										[3] = L["Above icon with background"],
										[4] = L["Under icon"],
										[1] = L["Under icon with background"],
									},
									width = "full",
								},
								durationBackgroundAlpha = {
									order = 5,
									type = "range",
									name = L["Background Alpha"],
									min = 0,
									max = 1,
									step = 0.1,
									width = "full",
								},
								colorTransition = {
									order = 6,
									type = "toggle",
									name = L["Color transition"],
									desc = L["Change text color based on remaining time"],
									width = "full",
								},
								durationBackgroundPadding = {
									order = 7,
									type = "select",
									name = L["Background padding"],
									desc = L["Amount of padding around duration text"],
									values = {
										[1] = L["Small (1 pixel)"],
										[2] = L["Medium (2 pixels)"],
										[3] = L["Large (3 pixels)"],
										[4] = L["Extra Large (4 pixels)"],
									},
									width = "full",
									disabled = function() 
										return not db.showDuration or (db.durationPosition ~= 1 and db.durationPosition ~= 3)
									end,
								},
								durationOffset = {
									order = 8,
							type = "group",
							inline = true,
									name = L["Duration Position"],
							args = {
										durationSizeX = {
									order = 1,
											type = "range",
											name = L["X Offset"],
											min = -50,
											max = 50,
											step = 1,
									width = "full",
								},
										durationSizeY = {
									order = 2,
									type = "range",
											name = L["Y Offset"],
											min = -50,
											max = 50,
									step = 1,
											width = "full",
										},
									},
								},
							},
						},
						fonts = {
							order = 3,
							name = "|cFFFFFFFF" .. L["Fonts"] .. "|r",
							type = "group",
							inline = true,
							args = {
								font = {
									type = "select",
									dialogControl = "LSM30_Font",
									order = 1,
									name = L["Duration Font"],
									values = AceGUIWidgetLSMlists.font,
									width = "full",
								},
								stackFont = {
									type = "select",
									dialogControl = "LSM30_Font",
									order = 2,
									name = L["Stack Font"],
									values = AceGUIWidgetLSMlists.font,
									width = "full",
								},
							},
						},
					},
				},
				effects = {
					order = 4,
					name = "|cFFE6CC80" .. L["Effects"] .. "|r",
					type = "group",
					args = {
						cooldown = {
							order = 1,
							name = "|cFFFFFFFF" .. L["Cooldown"] .. "|r",
							type = "group",
							inline = true,
							args = {
								showStdCooldown = {
									order = 1,
									type = "toggle",
									name = L["Show Cooldown"],
									desc = L["Show the standard spinning cooldown animation"],
									width = "full",
								},
								showStdSwipe = {
									order = 2,
									type = "toggle",
									name = L["Show Swipe"],
									desc = L["Show the standard cooldown swipe animation"],
									width = "full",
								},
								blizzardCountdown = {
									order = 3,
									type = "toggle",
									name = L["Blizzard Countdown"],
									desc = L["Use Blizzard's built-in cooldown count"],
									width = "full",
								},
							},
						},
						special = {
							order = 2,
							name = "|cFFFFFFFF" .. L["Special Effects"] .. "|r",
							type = "group",
							inline = true,
							args = {
								targetScale = {
									order = 1,
									type = "range",
									name = L["Target Scale"],
									desc = L["Scale multiplier for target's auras"],
									min = 1,
									max = 2,
									step = 0.05,
									width = "full",
								},
								targetGlow = {
									order = 2,
									type = "toggle",
									name = L["Target Glow"],
									desc = L["Add a glow effect to target's auras"],
									width = "full",
								},
								blinkTimeleft = {
									order = 3,
									type = "range",
									name = L["Blink Threshold"],
									desc = L["Start blinking when this percentage of duration remains"],
									min = 0,
									max = 1,
									step = 0.05,
									width = "full",
								},
							},
						},
					},
				},
			},
		},
		spells = {
			name = "|cFFE6CC80" .. L["Spell List"] .. "|r",
			desc = L["Manage spells that are shown or hidden"],
			type = "group",
			order = 1,
			childGroups = "tab",
			args = {
				spellListDescription = {
					order = 0,
					type = "description",
					name = L["Configure specific spells to show or hide. Add important buffs and debuffs to track."],
					fontSize = "medium",
					width = "full",
				},
				spellsTab = {
					name = "|cFFE6CC80" .. L["Spells"] .. "|r",
					type = "group",
					order = 1,
					args = fPB.SpellsTable.args,
				},
				npcTab = {
					name = "|cFFE6CC80" .. L["NPCs"] .. "|r",
					desc = L["NPC specific configurations"],
					type = "group",
					order = 2,
					args = fPB.NPCTable.args,
				},
			},
		},
		advanced = {
			name = "|cFFE6CC80" .. L["Advanced"] .. "|r",
			desc = L["Performance and technical settings"],
			type = "group",
			order = 4,
			childGroups = "tab",
			get = function(info) return db[info[#info]] end,
			set = function(info, value)
				db[info[#info]] = value
				UpdateAllNameplates()
			end,
			args = {
				advancedDescription = {
					order = 0,
					type = "description",
					name = L["Fine-tune performance settings and advanced features. These options affect addon behavior and performance."],
					fontSize = "medium",
					width = "full",
				},

				-- Performance Tab
				performance = {
					name = "|cFFE6CC80" .. L["Performance"] .. "|r",
					type = "group",
					order = 1,
					args = {
						-- Core Processing Settings
						processingHeader = {
							order = 1,
							type = "header",
							name = L["Core Processing"],
						},
						processingDesc = {
							order = 2,
							type = "description",
							name = L["Configure how nameplates and auras are processed. These settings directly impact CPU usage."],
							fontSize = "small",
							width = "full",
						},
								limitedScanning = {
							order = 3,
									type = "toggle",
									name = L["Limited nameplate scanning"],
							desc = L["Process only a limited number of nameplates per frame for better performance"],
									width = "full",
								},
								maxPlatesPerUpdate = {
							order = 4,
									type = "range",
									name = L["Max plates per update"],
									desc = L["Maximum number of nameplates to update per frame"],
									min = 1,
									max = 10,
									step = 1,
									width = "full",
									disabled = function() return not db.limitedScanning end,
								},
								throttleInterval = {
							order = 5,
									type = "range",
							name = L["Update interval"],
									desc = L["Minimum time between updates (seconds)"],
									min = 0.01,
									max = 0.5,
									step = 0.01,
									width = "full",
									set = function(info, value)
										db[info[#info]] = value
								THROTTLE_INTERVAL = value -- Update global throttle interval
										UpdateAllNameplates()
									end,
								},

						-- Memory Optimization
						memoryHeader = {
							order = 10,
							type = "header",
							name = L["Memory Optimization"],
						},
						memoryDesc = {
							order = 11,
							type = "description",
							name = L["Settings that affect memory usage and garbage collection."],
							fontSize = "small",
							width = "full",
						},
								tableRecycling = {
							order = 12,
									type = "toggle",
									name = L["Table recycling"],
							desc = L["Reuse tables to reduce garbage collection"],
							width = "full",
						},
						maxBuffsPerPlate = {
							order = 13,
							type = "range",
							name = L["Max buffs per nameplate"],
							desc = L["Maximum number of buffs/debuffs to process per nameplate"],
							min = 1,
							max = 40,
							step = 1,
							width = "full",
							get = function() return db.maxBuffsPerPlate or (db.buffPerLine * db.numLines) end,
							set = function(_, value)
								db.maxBuffsPerPlate = value
								db.maxVisibleAuras = value -- Keep these synced
								db.limitVisibleAuras = true
								UpdateAllNameplates()
							end,
						},

						-- Sorting Optimization
						sortingHeader = {
							order = 20,
							type = "header",
							name = L["Sorting Optimization"],
						},
						sortingDesc = {
							order = 21,
							type = "description",
							name = L["Configure how auras are sorted and cached."],
							fontSize = "small",
									width = "full",
								},
								optimizedSorting = {
							order = 22,
									type = "toggle",
							name = L["Enable sort caching"],
							desc = L["Cache sort results to avoid unnecessary resorting"],
									width = "full",
									set = function(info, value)
										db[info[#info]] = value
								if not value and fPB.wipeAllSortCaches then
											fPB.wipeAllSortCaches()
										end
										UpdateAllNameplates()
									end,
								},
								sortCacheTolerance = {
							order = 23,
									type = "select",
							name = L["Cache tolerance"],
							desc = L["How much change to allow before resorting (higher = better performance)"],
									width = "full",
									disabled = function() return not db.optimizedSorting end,
									values = {
										[1] = L["Low (Sort More Often)"],
										[2] = L["Medium (Balanced)"],
										[3] = L["High (Maximum Performance)"],
									},
									get = function() return db.sortCacheTolerance or 2 end,
									set = function(_, value)
										db.sortCacheTolerance = value
										if fPB.wipeAllSortCaches then
											fPB.wipeAllSortCaches()
										end
										UpdateAllNameplates()
									end,
								},
						showCacheMessages = {
							order = 24,
									type = "toggle",
							name = L["Show cache messages"],
							desc = L["Display messages when sort cache is used"],
									width = "full",
									disabled = function() return not db.optimizedSorting end,
						},

						-- Filtering Optimization
						filteringHeader = {
							order = 30,
							type = "header",
							name = L["Filtering Optimization"],
						},
						filteringDesc = {
							order = 31,
							type = "description",
							name = L["Settings that affect how auras are filtered."],
							fontSize = "small",
							width = "full",
						},
						smartBuffFiltering = {
							order = 32,
							type = "toggle",
							name = L["Smart buff filtering"],
							desc = L["Use optimized early-exit conditions when filtering buffs"],
							width = "full",
						},
						showFilterMessages = {
							order = 33,
							type = "toggle",
							name = L["Show filter messages"],
							desc = L["Display messages about filter optimization"],
							width = "full",
							disabled = function() return not db.smartBuffFiltering end,
						},
					},
				},

				-- Adaptive Detail Tab
				adaptive = {
					name = "|cFFE6CC80" .. L["Adaptive"] .. "|r",
					type = "group",
					order = 2,
					args = {
						adaptiveDesc = {
							order = 1,
							type = "description",
							name = L["Configure how the addon adapts to high-load situations."],
							fontSize = "medium",
							width = "full",
						},
						
						-- Main Toggle
						enableGroup = {
							order = 2,
							type = "group",
							inline = true,
							name = L["Main Settings"],
							args = {
								adaptiveDetail = {
							order = 1,
							type = "toggle",
									name = L["Enable adaptive detail"],
									desc = L["Automatically adjust visual quality based on nameplate count"],
							width = "full",
							get = function() return db.adaptiveDetail end,
							set = function(_, value) 
								db.adaptiveDetail = value 
										-- Initialize thresholds if needed
										if value and not db.adaptiveThresholds then
											db.adaptiveThresholds = {
												low = 15,
												medium = 25,
												high = 35
											}
										end
								UpdateAllNameplates()
							end,
						},
						adaptiveDetailDesc = {
							order = 2,
							type = "description",
									name = L["When enabled, visual effects will be reduced as more nameplates become visible."],
									fontSize = "small",
							width = "full",
						},
							},
						},

						-- Thresholds
						thresholdsGroup = {
							order = 3,
							type = "group",
							inline = true,
							name = L["Thresholds"],
							disabled = function() return not db.adaptiveDetail end,
							args = {
								thresholdsDesc = {
									order = 1,
									type = "description",
									name = L["Set the nameplate counts at which detail levels change."],
									fontSize = "small",
									width = "full",
								},
								lowThreshold = {
									order = 2,
									type = "range",
									name = L["Low detail threshold"],
									desc = L["Start reducing effects at this many nameplates"],
									min = 5,
									max = 30,
									step = 1,
									width = "full",
									get = function() return db.adaptiveThresholds and db.adaptiveThresholds.low or 15 end,
									set = function(_, value) 
										if not db.adaptiveThresholds then
											db.adaptiveThresholds = {
												low = 15,
												medium = 25,
												high = 35
											}
										end
										db.adaptiveThresholds.low = value
										if db.adaptiveThresholds.medium < value + 5 then
											db.adaptiveThresholds.medium = value + 5
										end
										if db.adaptiveThresholds.high < db.adaptiveThresholds.medium + 5 then
											db.adaptiveThresholds.high = db.adaptiveThresholds.medium + 5
										end
										UpdateAllNameplates()
									end,
								},
								mediumThreshold = {
									order = 3,
									type = "range",
									name = L["Medium detail threshold"],
									desc = L["Further reduce effects at this many nameplates"],
									min = 10,
									max = 40,
									step = 1,
									width = "full",
									get = function() return db.adaptiveThresholds and db.adaptiveThresholds.medium or 25 end,
									set = function(_, value) 
										if not db.adaptiveThresholds then
											db.adaptiveThresholds = {
												low = 15,
												medium = 25,
												high = 35
											}
										end
										db.adaptiveThresholds.medium = value
										if db.adaptiveThresholds.high < value + 5 then
											db.adaptiveThresholds.high = value + 5
										end
										UpdateAllNameplates()
									end,
								},
								highThreshold = {
									order = 4,
									type = "range",
									name = L["Minimum detail threshold"],
									desc = L["Use minimum effects at this many nameplates"],
									min = 15,
									max = 50,
									step = 1,
									width = "full",
									get = function() return db.adaptiveThresholds and db.adaptiveThresholds.high or 35 end,
									set = function(_, value) 
										if not db.adaptiveThresholds then
											db.adaptiveThresholds = {
												low = 15,
												medium = 25,
												high = 35
											}
										end
										db.adaptiveThresholds.high = value
										UpdateAllNameplates()
									end,
								},
							},
						},

						-- Features
						featuresGroup = {
							order = 4,
							type = "group",
							inline = true,
							name = L["Adaptive Features"],
							disabled = function() return not db.adaptiveDetail end,
							args = {
								featuresDesc = {
									order = 1,
									type = "description",
									name = L["Choose which visual features to adapt based on load."],
									fontSize = "small",
									width = "full",
								},
								glowEffects = {
									order = 2,
									type = "toggle",
									name = L["Adapt glow effects"],
									desc = L["Reduce glow effects at higher nameplate counts"],
									width = "full",
									get = function() return db.adaptiveFeatures and db.adaptiveFeatures.glows end,
									set = function(_, value) 
										if not db.adaptiveFeatures then
											db.adaptiveFeatures = {
												glows = true,
												animations = true,
												cooldownSwipes = true,
												textUpdates = true
											}
										end
										db.adaptiveFeatures.glows = value 
										UpdateAllNameplates()
									end,
								},
								animations = {
									order = 3,
									type = "toggle",
									name = L["Adapt animations"],
									desc = L["Reduce animations at higher nameplate counts"],
									width = "full",
									get = function() return db.adaptiveFeatures and db.adaptiveFeatures.animations end,
									set = function(_, value) 
										if not db.adaptiveFeatures then
											db.adaptiveFeatures = {
												glows = true,
												animations = true,
												cooldownSwipes = true,
												textUpdates = true
											}
										end
										db.adaptiveFeatures.animations = value 
										UpdateAllNameplates()
									end,
								},
								cooldownSwipes = {
									order = 4,
									type = "toggle",
									name = L["Adapt cooldown swipes"],
									desc = L["Reduce cooldown swipe effects at higher nameplate counts"],
									width = "full",
									get = function() return db.adaptiveFeatures and db.adaptiveFeatures.cooldownSwipes end,
									set = function(_, value) 
										if not db.adaptiveFeatures then
											db.adaptiveFeatures = {
												glows = true,
												animations = true,
												cooldownSwipes = true,
												textUpdates = true
											}
										end
										db.adaptiveFeatures.cooldownSwipes = value 
										UpdateAllNameplates()
									end,
								},
								textUpdates = {
									order = 5,
									type = "toggle",
									name = L["Adapt text updates"],
									desc = L["Reduce text update frequency at higher nameplate counts"],
									width = "full",
									get = function() return db.adaptiveFeatures and db.adaptiveFeatures.textUpdates end,
									set = function(_, value) 
										if not db.adaptiveFeatures then
											db.adaptiveFeatures = {
												glows = true,
												animations = true,
												cooldownSwipes = true,
												textUpdates = true
											}
										end
										db.adaptiveFeatures.textUpdates = value 
										UpdateAllNameplates()
									end,
								},
							},
						},
					},
				},

				-- Debug Tab
				debug = {
					name = "|cFFE6CC80" .. L["Debug"] .. "|r",
					type = "group",
					order = 3,
					args = {
						debugDesc = {
							order = 1,
							type = "description",
							name = L["Tools for troubleshooting and performance monitoring."],
							fontSize = "medium",
							width = "full",
						},

						-- Main Settings
						mainGroup = {
							order = 2,
							type = "group",
							inline = true,
							name = L["Main Settings"],
					args = {
						debugEnabled = {
							order = 1,
							type = "toggle",
							name = L["Enable debugging"],
									desc = L["Enable debug logging and tools"],
							width = "full",
							get = function() return fPB.debug.enabled end,
							set = function(_, value) 
								fPB.debug.enabled = value 
								db.debugEnabled = value
								if value then
									print("|cFF00FFFF[FlyPlateBuffs]|r Debug mode |cFF00FF00enabled|r")
								else
									print("|cFF00FFFF[FlyPlateBuffs]|r Debug mode |cFFFF0000disabled|r")
								end
							end,
						},
								debugLevel = {
							order = 2,
									type = "select",
									name = L["Debug level"],
									
									desc = L["Amount of detail in debug output"],
									width = "full",
							disabled = function() return not fPB.debug.enabled end,
									values = {
										[1] = L["Basic"],
										[2] = L["Detailed"],
										[3] = L["Verbose"],
									},
									get = function() return fPB.debug.detailLevel end,
									set = function(_, value)
										fPB.debug.detailLevel = value
										db.debugDetailLevel = value
									end,
								},
							},
						},

						-- Tracking Options
						trackingGroup = {
							order = 3,
							type = "group",
							inline = true,
							name = L["Tracking Options"],
							disabled = function() return not fPB.debug.enabled end,
							args = {
								performance = {
									order = 1,
									type = "toggle",
									name = L["Track performance"],
									desc = L["Monitor function execution times"],
									width = "full",
									get = function() return fPB.debug.performance end,
									set = function(_, value) 
										fPB.debug.performance = value 
										db.debugPerformance = value
									end,
								},
								memory = {
									order = 2,
									type = "toggle",
									name = L["Track memory"],
									desc = L["Monitor memory usage"],
									width = "full",
									get = function() return fPB.debug.memory end,
									set = function(_, value) 
										fPB.debug.memory = value 
										db.debugMemory = value
									end,
								},
								events = {
									order = 3,
									type = "toggle",
									name = L["Track events"],
									desc = L["Monitor event processing"],
									width = "full",
									get = function() return fPB.debug.events end,
									set = function(_, value) 
										fPB.debug.events = value 
										db.debugEvents = value
									end,
								},
							},
						},

						-- Advanced Debug
						advancedGroup = {
							order = 4,
							type = "group",
							inline = true,
							name = L["Advanced Options"],
							disabled = function() return not fPB.debug.enabled end,
							args = {
								samplingRate = {
									order = 1,
									type = "range",
									name = L["Sampling rate"],
									desc = L["Percentage of operations to track"],
									min = 1,
									max = 100,
									step = 1,
									width = "full",
									get = function() return fPB.debug.samplingRate end,
									set = function(_, value) 
										fPB.debug.samplingRate = value
										db.debugSamplingRate = value
									end,
								},
								autoDisable = {
									order = 2,
									type = "range",
									name = L["Auto-disable after"],
									desc = L["Automatically disable debug after this many seconds (0 = never)"],
									min = 0,
									max = 300,
									step = 10,
									width = "full",
									get = function() return fPB.debug.autoDisableAfter end,
									set = function(_, value)
										fPB.debug.autoDisableAfter = value
										db.debugAutoDisableAfter = value
									end,
								},
								unitFilter = {
									order = 3,
									type = "input",
									name = L["Unit name filter"],
									desc = L["Only show debug for units matching this text"],
									width = "full",
									get = function() return fPB.debug.unitNameFilter end,
									set = function(_, value)
										fPB.debug.unitNameFilter = value
										db.debugUnitNameFilter = value
									end,
								},
							},
						},

						-- Actions
						actionsGroup = {
							order = 5,
							type = "group",
							inline = true,
							name = L["Debug Actions"],
							disabled = function() return not fPB.debug.enabled end,
							args = {
								showStats = {
									order = 1,
									type = "execute",
									name = L["Show Statistics"],
									desc = L["Display current debug statistics"],
									func = function() fPB.ShowDebugStats() end,
									width = "half",
								},
								resetStats = {
									order = 2,
									type = "execute",
									name = L["Reset Statistics"],
									desc = L["Reset all debug counters"],
									func = function()
										fPB.debug.updateCounts = 0
										fPB.debug.skippedUpdates = 0
										fPB.debug.startTime = GetTime()
										fPB.debug.functionTimes = {}
										fPB.debug.memoryUsage = {}
										fPB.debug.logEntries = {}
										print("|cFF00FFFF[FlyPlateBuffs]|r Debug statistics reset.")
									end,
									width = "half",
								},
							},
						},
					},
				},
			},
		},
		about = {
			name = "|cFFE6CC80" .. L["About"] .. "|r",
			desc = L["Information about FlyPlateBuffs"],
			type = "group",
			order = 5,
			args = {
				header = {
					order = 1,
					type = "description",
					name = "|cFFE6CC80" .. L["FlyPlateBuffs"] .. "|r\n" ..
						   "|cFFAAAAAA" .. L["Version"] .. ":|r " .. GetAddonVersion() .. "\n" ..
						   "|cFFAAAAAA" .. L["Author"] .. ":|r Talentdplayr\n\n",
					fontSize = "medium",
					width = "full",
				},
				
				description = {
					order = 2,
					type = "description",
					name = L["A powerful and customizable nameplate aura display addon that helps you track buffs and debuffs efficiently."] .. "\n\n",
					fontSize = "medium",
					width = "full",
				},
				features = {
					order = 3,
					type = "group",
					inline = true,
					name = "|cFFFFFFFF" .. L["Key Features"] .. "|r",
					args = {
						feature1 = {
							order = 1,
							type = "description",
							name = "• " .. L["Customizable aura display with size, spacing, and layout options"] .. "\n",
							fontSize = "medium",
							width = "full",
						},
						feature2 = {
					order = 2,
					type = "description",
							name = "• " .. L["Smart filtering system for buffs and debuffs"] .. "\n",
					fontSize = "medium",
					width = "full",
				},
						feature3 = {
					order = 3,
					type = "description",
							name = "• " .. L["Performance optimizations for smooth gameplay"] .. "\n",
					fontSize = "medium",
					width = "full",
				},
						feature4 = {
							order = 4,
							type = "description",
							name = "• " .. L["Adaptive detail system for high-stress situations"] .. "\n",
							fontSize = "medium",
							width = "full",
						},
						feature5 = {
							order = 5,
							type = "description",
							name = "• " .. L["Comprehensive spell tracking and NPC configurations"] .. "\n\n",
							fontSize = "medium",
							width = "full",
						},
					},
				},
				usage = {
					order = 4,
					type = "group",
					inline = true,
					name = "|cFFFFFFFF" .. L["Usage"] .. "|r",
					args = {
						commands = {
							order = 1,
							type = "description",
							name = "|cFFFFD700" .. L["Commands"] .. ":|r\n" ..
								   "• |cFFFFFFFF/fpb|r " .. L["or"] .. " |cFFFFFFFF/pb|r - " .. L["Open options panel"] .. "\n" ..
								   "• |cFFFFFFFF/fpb debug|r - " .. L["Toggle debugging mode"] .. "\n" ..
								   "• |cFFFFFFFF/fpb stats|r - " .. L["Show performance statistics"] .. "\n\n",
							fontSize = "medium",
							width = "full",
						},
					},
				},
				support = {
					order = 5,
					type = "group",
					inline = true,
					name = "|cFFFFFFFF" .. L["Support"] .. "|r",
					args = {
						info = {
							order = 1,
							type = "description",
							name = L["For bug reports and feature requests, please use the CurseForge page or WoWInterface comments section."] .. "\n\n",
							fontSize = "medium",
							width = "full",
						},
					},
				},
				credits = {
					order = 6,
					type = "group",
					inline = true,
					name = "|cFFFFFFFF" .. L["Credits"] .. "|r",
					args = {
						libs = {
							order = 1,
							type = "description",
							name = "|cFFFFD700" .. L["Libraries"] .. ":|r\n" ..
								   "• Ace3\n" ..
								   "• LibSharedMedia-3.0\n" ..
								   "• LibStub\n" ..
								   "• Masque (optional)\n\n",
							fontSize = "medium",
							width = "full",
						},
						special = {
							order = 2,
							type = "description",
							name = "|cFFFFD700" .. L["Special Thanks"] .. ":|r\n" ..
								   L["Thanks to all contributors and testers who helped make this addon better."] .. "\n\n",
							fontSize = "medium",
							width = "full",
						},
					},
				},
				license = {
					order = 7,
					type = "group",
					inline = true,
					name = "|cFFFFFFFF" .. L["License"] .. "|r",
					args = {
						text = {
							order = 1,
							type = "description",
							name = L["FlyPlateBuffs is released under the MIT License."] .. "\n" ..
								   L["You are free to use, modify, and distribute this addon as long as you include the original copyright notice."] .. "\n",
							fontSize = "medium",
							width = "full",
						},
					},
				},
			},
		},
	},
}

local DefaultSettings = {
    profile = {
        -- Debug settings
        debugEnabled = false,
        debugPerformance = false,
        debugMemory = false,
        debugEvents = false,
        debugVerbose = false,
        debugCacheMessages = false,
        debugFilterMessages = false,
        debugSamplingRate = 100,
        debugMemoryTrackingFrequency = 0,
        debugSignificantMemoryChangeOnly = false,
        debugMemoryChangeThreshold = 50,
        debugUnitNameFilter = "",
        debugAutoDisableAfter = 0,
        debugDetailLevel = 2,
        debugDynamicThrottlingEnabled = true,
        debugCategories = {
            all = true,
            events = true,
            nameplates = true,
            auras = true,
            cache = true,
            filtering = true,
            performance = false,
        },
        debugBufferSettings = {
            maxBufferSize = 20,
            flushInterval = 0.5,
        },
        debugThrottling = {
            enabled = true,
            dynamic = true,
        },
        
        -- Adaptive settings
        adaptiveThresholds = {
            low = 15,
            medium = 25,
            high = 35
        },
        adaptiveFeatures = {
            glows = true,
            animations = true,
            cooldownSwipes = true,
            textUpdates = true
        },
        
        -- Rest of settings remain unchanged...
    }
}

local function Initialize()
    if flyPlateBuffsDB and (not flyPlateBuffsDB.version or flyPlateBuffsDB.version < 2) then
        ConvertDBto2()
    end

    fPB.db = LibStub("AceDB-3.0"):New("flyPlateBuffsDB", DefaultSettings, true)
    fPB.db.RegisterCallback(fPB, "OnProfileChanged", "OnProfileChanged")
    fPB.db.RegisterCallback(fPB, "OnProfileCopied", "OnProfileChanged")
    fPB.db.RegisterCallback(fPB, "OnProfileReset", "OnProfileChanged")

    db = fPB.db.profile
    fPB.font = fPB.LSM:Fetch("font", db.font)
    fPB.stackFont = fPB.LSM:Fetch("font", db.stackFont)
    
    -- Initialize throttle interval from settings
    THROTTLE_INTERVAL = db.throttleInterval or 0.1
    
    -- Initialize debug settings from saved variables if they exist
    if db.debugEnabled ~= nil then fPB.debug.enabled = db.debugEnabled end
    if db.debugPerformance ~= nil then fPB.debug.performance = db.debugPerformance end
    if db.debugMemory ~= nil then fPB.debug.memory = db.debugMemory end
    if db.debugEvents ~= nil then fPB.debug.events = db.debugEvents end
    if db.debugVerbose ~= nil then fPB.debug.verbose = db.debugVerbose end
    if db.debugCacheMessages ~= nil then fPB.debug.cacheMessages = db.debugCacheMessages end
    if db.debugFilterMessages ~= nil then fPB.debug.filterMessages = db.debugFilterMessages end
    if db.showCacheHitMessages ~= nil then db.showCacheHitMessages = db.showCacheHitMessages end
    if db.debugSamplingRate ~= nil then fPB.debug.samplingRate = db.debugSamplingRate end
    if db.debugMemoryTrackingFrequency ~= nil then fPB.debug.memoryTrackingFrequency = db.debugMemoryTrackingFrequency end
    if db.debugSignificantMemoryChangeOnly ~= nil then fPB.debug.significantMemoryChangeOnly = db.debugSignificantMemoryChangeOnly end
    if db.debugMemoryChangeThreshold ~= nil then fPB.debug.memoryChangeThreshold = db.debugMemoryChangeThreshold end
    if db.debugUnitNameFilter ~= nil then fPB.debug.unitNameFilter = db.debugUnitNameFilter end
    if db.debugAutoDisableAfter ~= nil then fPB.debug.autoDisableAfter = db.debugAutoDisableAfter end
    if db.debugDetailLevel ~= nil then fPB.debug.detailLevel = db.debugDetailLevel end
    if db.debugDynamicThrottlingEnabled ~= nil then fPB.debug.dynamicThrottlingEnabled = db.debugDynamicThrottlingEnabled end
    
    -- Initialize adaptive detail system
    if db.adaptiveDetail then
        InitializeAdaptiveMonitor()
    end

    FixSpells()
    CacheSpells()

    -- Register only the main options table
    AceConfig:RegisterOptionsTable("flyPlateBuffs", fPB.MainOptionTable)
    AceConfigDialog:AddToBlizOptions("flyPlateBuffs", "FlyPlateBuffs")

    -- Initialize profile options
    if fPB.InitializeProfileOptions then
        fPB.InitializeProfileOptions()
    end

    -- Register the profile options separately
    local profilesOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(fPB.db)
    AceConfig:RegisterOptionsTable("flyPlateBuffs_Profiles", profilesOptions)
    fPBProfilesOptions = AceConfigDialog:AddToBlizOptions("flyPlateBuffs_Profiles", L["Profiles"], "FlyPlateBuffs")
end

function fPB.OptionsOnEnable()
    db = fPB.db.profile
    fPB.BuildSpellList()
    fPB.BuildNPCList()
    UpdateAllNameplates()
end

function fPB.ToggleOptions()
    AceConfigDialog:Open("flyPlateBuffs")
end

-- Remove the separate options registration
fPB.OptionsOpen = nil

-- Remove the separate options registration
fPB.OptionsOpen = {
    name = L["FlyPlateBuffs Options"],
    type = "group",
    args = {
        openMenu = {
            order = 1,
            type = "execute",
            name = L["Open Menu"],
            func = function(info)
                fPB.ToggleOptions()
            end,
		},
	},
}