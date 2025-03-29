local AddonName, fPB = ...
L = fPB.L

DEBUFF_MAX_DISPLAY = 200
BUFF_MAX_DISPLAY = 200

-- Initialize global tables and add to addon namespace
local activeAuras = {}
fPB.activeAuras = activeAuras

local activeTotemGUIDs = {}
local PlatesBuffs = {}
local Interrupted = {}
local Earthen = {}
local Grounding = {}
local WarBanner = {}
local Barrier = {}
local SGrounds = {}
local SmokeBombAuras = {}

-- Debug system configuration
fPB.debug = {
    enabled = false,
    verbose = false,
    detailLevel = 2, -- 1 = critical only, 2 = normal, 3 = verbose
    categories = {
        all = true,
        events = true,
        nameplates = true,
        auras = true,
        cache = true,
        filtering = true,
        performance = false,
    },
    memory = true, -- Enable memory logging by default to see table recycling
    cacheMessages = false, -- Toggle for displaying nameplate cache debug messages
    filterMessages = false, -- Toggle for displaying filter optimization messages
    updateCounts = 0,
    skippedUpdates = 0,
    startTime = GetTime(),
    functionTimes = {},
    memoryUsage = {},
    logEntries = {},
    maxLogEntries = 100,
    
    -- Advanced debug settings
    samplingRate = 100, -- Percentage of function calls to track (1-100%)
    memoryTrackingFrequency = 0, -- 0=every update, 1=1s, 5=5s, 10=10s
    lastMemoryTrack = 0, -- Last time memory was tracked
    significantMemoryChangeOnly = false, -- Only log significant memory changes
    memoryChangeThreshold = 50, -- Memory change threshold in KB
    unitNameFilter = "", -- Filter debug by unit name
    autoDisableAfter = 0, -- Auto-disable after X seconds (0 = never)
    
    -- Buffered logs
    logBuffer = {},
    maxBufferSize = 20,
    lastBufferFlush = 0,
    bufferFlushInterval = 0.5, -- Flush buffer every 0.5 seconds
    
    -- Dynamic throttling
    nameplateCount = 0,
    dynamicThrottlingEnabled = true,
    throttlingEnabled = true,
    stats = {
        tablesAcquired = 0,
        tablesReleased = 0,
        tablesReused = 0, -- Track how many tables are reused from the pool
        poolSize = function() return #fPB.tablePool end,
    },
    
    options = {}
}

-- Color theme constants
local COLORS = {
    ADDON_NAME = "|cff36ffe7",     -- Cyan for addon name
    HEADER = "|cff9b6ef3",         -- Light purple for headers
    VALUE = "|cfffe981",          -- Light yellow for values
    SUCCESS = "|cff00ff00",        -- Green for success messages
    ERROR = "|cffff0000",          -- Red for errors
    WARNING = "|cffffa500",        -- Orange for warnings
    LINK = "|cff71d5ff",          -- Light blue for links/references
    NORMAL = "|cffffffff",         -- White for normal text
    DEBUG = "|cff00ffff",         -- Cyan for debug messages
    MUTED = "|cff808080"          -- Gray for less important text
}

-- Helper function for consistent coloring
local function Color(text, colorType)
    if not text then return "" end
    local color = COLORS[colorType] or COLORS.NORMAL
    return color .. text .. "|r"
end

-- Helper function for consistent message formatting
local function FormatMessage(prefix, message, messageType)
    return Color(prefix, "ADDON_NAME") .. ": " .. Color(message, messageType or "NORMAL")
end

-- Update existing color definitions to use the new system
fPB.chatColor = COLORS.WARNING
fPB.linkColor = COLORS.LINK

-- Update Print function to use the new formatting
function fPB.Print(msg)
    print(FormatMessage("FlyPlateBuffs", msg))
end

-- Update debug message formatting
local function DebugLog(category, message, ...)
    if not fPB.debug.enabled then return end
    
    -- Early exits for category checks
    if category == "performance" and not fPB.debug.performance then return end
    if category == "memory" and not fPB.debug.memory then return end
    if category == "events" and not fPB.debug.events then return end
    
    -- Apply sampling rate
    if fPB.debug.samplingRate < 100 and math.random(100) > fPB.debug.samplingRate then
        return
    end
    
    -- Format the message
    local formattedMessage = select("#", ...) > 0 and message:format(...) or message
    
    -- Apply unit name filter if set
    if fPB.debug.unitNameFilter ~= "" and formattedMessage:find("%a") then
        if not formattedMessage:lower():find(fPB.debug.unitNameFilter:lower()) then
            return
        end
    end
    
    -- Create log entry
    local entry = {
        time = GetTime() - fPB.debug.startTime,
        category = category,
        message = formattedMessage
    }
    
    -- Add to buffer
    table.insert(fPB.debug.logBuffer, entry)
    
    -- Flush buffer if needed
    if #fPB.debug.logBuffer >= fPB.debug.maxBufferSize or 
       (GetTime() - fPB.debug.lastBufferFlush) > fPB.debug.bufferFlushInterval then
        FlushDebugLogBuffer()
    end
    
    -- Print to chat if verbose mode is enabled
    if fPB.debug.verbose then
        print(FormatMessage("Debug-" .. category, 
            string.format("%.2fs: %s", entry.time, formattedMessage), 
            "DEBUG"))
    end
end

-- Update error message formatting
local function ShowError(message)
    print(FormatMessage("FlyPlateBuffs", message, "ERROR"))
end

-- Update warning message formatting
local function ShowWarning(message)
    print(FormatMessage("FlyPlateBuffs", message, "WARNING"))
end

-- Update success message formatting
local function ShowSuccess(message)
    print(FormatMessage("FlyPlateBuffs", message, "SUCCESS"))
end

-- Function to flush the debug log buffer
function FlushDebugLogBuffer()
    if #fPB.debug.logBuffer == 0 then return end
    
    for _, entry in ipairs(fPB.debug.logBuffer) do
        -- Add to log with limit on entries
        table.insert(fPB.debug.logEntries, 1, entry)
        if #fPB.debug.logEntries > fPB.debug.maxLogEntries then
            table.remove(fPB.debug.logEntries)
        end
    end
    
    -- Clear buffer
    wipe(fPB.debug.logBuffer)
    fPB.debug.lastBufferFlush = GetTime()
end

-- Improved performance tracking function wrapper
local function TrackPerformance(name, func, ...)
    if not fPB.debug.enabled or not fPB.debug.performance then
        return func(...)
    end
    
    -- Apply sampling rate
    if fPB.debug.samplingRate < 100 and math.random(100) > fPB.debug.samplingRate then
        return func(...)
    end
    
    if not func then
        DebugLog("performance", "TrackPerformance called with nil function: %s", name)
        return
    end
    
    if not fPB.debug.functionTimes[name] then
        fPB.debug.functionTimes[name] = {
            calls = 0,
            totalTime = 0,
            maxTime = 0
        }
    end
    
    local startTime = debugprofilestop()
    local result = {func(...)}
    local elapsed = debugprofilestop() - startTime
    
    local stats = fPB.debug.functionTimes[name]
    stats.calls = stats.calls + 1
    stats.totalTime = stats.totalTime + elapsed
    stats.maxTime = math.max(stats.maxTime, elapsed)
    
    -- Only log slow operations based on detail level
    local logThreshold = 50 -- Default (medium)
    if fPB.debug.detailLevel == 1 then -- Low
        logThreshold = 100
    elseif fPB.debug.detailLevel == 3 then -- High
        logThreshold = 10
    end
    
    if elapsed > logThreshold then
        DebugLog("performance", "%s took %.2fms", name, elapsed)
    end
    
    if #result > 0 then
        return unpack(result)
    end
    return nil
end

-- Add debug command for filter stats
fPB.debug.options["filter"] = function(param)
    if not fPB.filterStats then
        print("|cFF00FFFF[FlyPlateBuffs]|r Filter statistics not initialized yet.")
        return
    end
    
    if param == "reset" then
        fPB.ResetFilterStats()
        print("|cFF00FFFF[FlyPlateBuffs]|r Filter statistics reset.")
        return
    end
    
    local totalBuffs = fPB.filterStats.totalBuffsChecked or 0
    local earlyExits = fPB.filterStats.earlyExits or 0
    local exitRate = totalBuffs > 0 and (earlyExits / totalBuffs) * 100 or 0
    
    print("|cFF00FFFF[FlyPlateBuffs]|r Filter Optimization Statistics:")
    print(string.format("  Total buffs processed: %d", totalBuffs))
    print(string.format("  Early exits: %d (%.1f%%)", earlyExits, exitRate))
    if totalBuffs > 0 then
        print(string.format("  Estimated CPU time saved: %.2f ms", earlyExits * 0.02))
    end
end

-- Improved memory tracking function
local function TrackMemory(label)
    if not fPB.debug.enabled or not fPB.debug.memory then return end
    
    -- Check if we should track memory based on frequency setting
    local currentTime = GetTime()
    if fPB.debug.memoryTrackingFrequency > 0 then
        if (currentTime - fPB.debug.lastMemoryTrack) < fPB.debug.memoryTrackingFrequency then
            return
        end
        fPB.debug.lastMemoryTrack = currentTime
    end
    
    -- Apply sampling rate
    if fPB.debug.samplingRate < 100 and math.random(100) > fPB.debug.samplingRate then
        return
    end
    
    UpdateAddOnMemoryUsage()
    local memory = GetAddOnMemoryUsage(AddonName)
    
    if not fPB.debug.memoryUsage[label] then
        fPB.debug.memoryUsage[label] = {
            lastValue = memory,
            baseline = memory
        }
        DebugLog("memory", "%s baseline: %.2fKB", label, memory)
        return
    end
    
    local memInfo = fPB.debug.memoryUsage[label]
    local diff = memory - memInfo.lastValue
    
    -- Only log if the change is significant enough
    if not fPB.debug.significantMemoryChangeOnly or math.abs(diff) >= fPB.debug.memoryChangeThreshold then
        DebugLog("memory", "%s: %.2fKB (?%.2fKB)", label, memory, diff)
    end
    
    memInfo.lastValue = memory
end

-- Function to display debug stats
function fPB.ShowDebugStats()
    if not fPB.debug.enabled then
        print("|cFF00FFFF[FlyPlateBuffs]|r Debug mode is not enabled. Use |cFFFFFF00/fpb debug|r to enable it.")
        return
    end

    -- Get a local reference to the profile database
    local db = fPB.db and fPB.db.profile

    -- Check if db is available
    if not db then
        print("|cFF00FFFF[FlyPlateBuffs]|r Error: Database not available.")
        return
    end

    print("|cFFFFCC00FlyPlateBuffs Debug Statistics:|r")
    
    -- Performance stats
    if fPB.debug.performance then
        print("|cFFFFCC00Performance:|r")
        local totalTime = 0
        local totalCalls = 0
        for name, stats in pairs(fPB.debug.functionTimes) do
            totalTime = totalTime + stats.totalTime
            totalCalls = totalCalls + stats.calls
            if stats.calls > 0 then
                print(string.format("  %s: %.2fms avg (%.2fms total, %d calls)", 
                    name, stats.totalTime / stats.calls * 1000, stats.totalTime * 1000, stats.calls))
            end
        end
        print(string.format("Total tracked time: %.2fms across %d function calls", totalTime * 1000, totalCalls))
    end
    
    -- Nameplate stats
    if fPB.debug.enabled then
        local nameplateCount = fPB.GetNameplateCount()
        local visibleNameplates = fPB.GetVisibleNameplateCount()
        
        print(string.format("Nameplates: %d tracked, %d visible", nameplateCount, visibleNameplates))
    end
    
    -- Table recycling stats
    if db.tableRecycling then
        local poolSize = fPB.tablePool and #fPB.tablePool or 0
        print("|cFFFFCC00Table Recycling:|r")
        print(string.format("  Pool size: %d", poolSize))
        print(string.format("  Tables created: %d", fPB.tableStats.created or 0))
        print(string.format("  Tables recycled: %d", fPB.tableStats.recycled or 0))
        print(string.format("  Tables released: %d", fPB.tableStats.released or 0))
        
        -- Calculate memory savings (each table ~100 bytes)
        local memorySavings = (fPB.tableStats.recycled or 0) / 10  -- KB
        print(string.format("  Memory savings: %.2f KB", memorySavings))
    end
    
    -- Sort optimization stats
    if db.optimizedSorting and fPB.sortStats then
        local timeRunning = GetTime() - fPB.sortStats.lastReset
        local hitRate = fPB.sortStats.totalSorts > 0 and (fPB.sortStats.cacheHits / fPB.sortStats.totalSorts) * 100 or 0
        
        print("|cFFFFCC00Sort Optimization:|r")
        print(string.format("  Total sorts: %d", fPB.sortStats.totalSorts))
        print(string.format("  Cache hits: %d (%.1f%%)", fPB.sortStats.cacheHits, hitRate))
        print(string.format("  Cache misses: %d", fPB.sortStats.cacheMisses))
        print(string.format("  Sorts per second: %.2f", fPB.sortStats.totalSorts / timeRunning))
    else
        print("|cFFFFCC00Sort Optimization:|r Disabled")
    end
    
    -- Filter optimization stats
    if db.smartBuffFiltering and fPB.filterStats then
        local timeRunning = GetTime() - fPB.filterStats.lastReset
        local totalBuffsChecked = fPB.filterStats.totalBuffsChecked or 0
        local earlyExits = fPB.filterStats.earlyExits or 0
        local exitRate = totalBuffsChecked > 0 and (earlyExits / totalBuffsChecked) * 100 or 0
        
        print("|cFFFFCC00Buff Filtering Optimization:|r")
        print(string.format("  Total buffs processed: %d", totalBuffsChecked))
        print(string.format("  Early exits: %d (%.1f%%)", earlyExits, exitRate))
        print(string.format("  Buffs per second: %.2f", totalBuffsChecked / timeRunning))
        print(string.format("  Estimated CPU time saved: %.2f ms", earlyExits * 0.02)) -- Assuming 0.02ms saved per early exit
    end
end

-- Function to track nameplate count for dynamic throttling
function UpdateNameplateCount()
    if not fPB.debug.dynamicThrottlingEnabled then return end
    
    local count = 0
    for _ in pairs(C_NamePlate.GetNamePlates()) do
        count = count + 1
    end
    
    fPB.debug.nameplateCount = count
    
    -- Adjust sampling rate based on nameplate count
    if count > 20 then
        fPB.debug.samplingRate = math.min(fPB.debug.samplingRate, 25) -- Max 25% sample rate with many plates
    elseif count > 10 then
        fPB.debug.samplingRate = math.min(fPB.debug.samplingRate, 50) -- Max 50% sample rate with moderate plates
    end
end

-- Function to get total number of nameplates
local function GetNameplateCount()
    local count = 0
    if PlatesBuffs then
        for frame, _ in pairs(PlatesBuffs) do
            count = count + 1
        end
    end
    return count
end

-- Function to get visible nameplate count
local function GetVisibleNameplateCount()
    local count = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            if nameplate and nameplate.IsVisible and nameplate:IsVisible() then
                count = count + 1
            end
        end
    end
    return count
end

-- Make debug functions available in the addon namespace
fPB.DebugLog = DebugLog
fPB.TrackPerformance = TrackPerformance
fPB.TrackMemory = TrackMemory
fPB.FlushDebugLogBuffer = FlushDebugLogBuffer
fPB.UpdateNameplateCount = UpdateNameplateCount
fPB.BuffCount = BuffCount
fPB.wipeAllSortCaches = wipeAllSortCaches
fPB.GetNameplateCount = GetNameplateCount
fPB.GetVisibleNameplateCount = GetVisibleNameplateCount
fPB.ResetSortStats = ResetSortStats
fPB.ResetFilterStats = ResetFilterStats  -- Add new function to namespace

-- Throttling configuration
local THROTTLE_INTERVAL = 0.1 -- Minimum time between updates (in seconds)
local lastUpdateTime = 0
local lastUnitUpdateTimes = {}

-- Local references to frequently used functions for better performance
local C_NamePlate_GetNamePlateForUnit, C_NamePlate_GetNamePlates = C_NamePlate.GetNamePlateForUnit, C_NamePlate.GetNamePlates
local CreateFrame, UnitName, UnitIsUnit, UnitIsPlayer, UnitPlayerControlled = CreateFrame, UnitName, UnitIsUnit, UnitIsPlayer, UnitPlayerControlled
local UnitIsEnemy, UnitIsFriend, table_sort, strmatch, format = UnitIsEnemy, UnitIsFriend, table.sort, strmatch, format
local wipe, pairs, GetTime, math_floor = wipe, pairs, GetTime, math.floor

local defaultSpells1, defaultSpells2 = fPB.defaultSpells1, fPB.defaultSpells2

-- Check if newer API is available and use it
local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local UnitAuraBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID

local LSM = LibStub("LibSharedMedia-3.0")
fPB.LSM = LSM
local MSQ, Group

local config = LibStub("AceConfig-3.0")
local dialog = LibStub("AceConfigDialog-3.0")

fPB.db = {}
local db

local tooltip = CreateFrame("GameTooltip", "fPBMouseoverTooltip", UIParent, "GameTooltipTemplate")

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

-- Handle API changes in 10.2.5
local UnitAura = UnitAura
if UnitAura == nil then
  UnitAura = function(unitToken, index, filter)
		local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
		if not aura then
            return nil
		end
		return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable, nil, aura.spellId
	end
end

local UnitBuff = UnitBuff
if UnitBuff == nil then
  UnitBuff = function(unitToken, index, filter)
		local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
		if not aura then
            return nil
		end
		return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable, nil, aura.spellId
	end
end

local UnitDebuff = UnitDebuff
if UnitDebuff == nil then
  UnitDebuff = function(unitToken, index, filter)
        if not filter then filter = "HARMFUL" end
		local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter)
		if not aura then
            return nil
		end
		return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable, nil, aura.spellId
	end
end

-- Table recycling system
-- ----------------------------------------
-- This system reduces garbage collection by reusing tables instead of creating new ones constantly
local MAX_POOLED_TABLES = 500 -- Limit to prevent excessive memory usage

-- Initialize statistics tracking for table recycling
if not fPB.tableStats then
    fPB.tableStats = {
        created = 0,   -- Total tables created
        recycled = 0,  -- Times a table was recycled from the pool
        released = 0   -- Times a table was released back to the pool
    }
end

-- Pre-populate the table pool with empty tables to reduce initial allocations
local function PrePopulatePool(count)
    -- Ensure the pool exists
    if not fPB.tablePool then
        fPB.tablePool = {}
    end
    
    -- Create initial tables
    local initialCount = #fPB.tablePool
    for i = 1, count do
        if #fPB.tablePool < MAX_POOLED_TABLES then
            tinsert(fPB.tablePool, {})
        end
    end
    
    -- Count as created
    fPB.tableStats.created = fPB.tableStats.created + count
    
    if fPB.debug and fPB.debug.enabled then
        DebugLog("memory", "Table pool pre-populated with %d tables (total: %d)", 
                count, #fPB.tablePool)
    end
    
    return #fPB.tablePool - initialCount
end

-- Acquire a table from the pool or create a new one
local function AcquireTable()
    -- Ensure the pool exists
    if not fPB.tablePool then
        fPB.tablePool = {}
    end
    
    local tbl
    
    -- Get a table from the pool if available
    if #fPB.tablePool > 0 then
        tbl = tremove(fPB.tablePool)
        fPB.tableStats.recycled = fPB.tableStats.recycled + 1
        fPB.debug.stats.tablesReused = fPB.debug.stats.tablesReused + 1
        
        if fPB.debug.enabled then
            DebugLog("memory", "Table reused from pool (pool size: %d)", #fPB.tablePool)
        end
    else
        -- Create a new table if pool is empty
        tbl = {}
        fPB.tableStats.created = fPB.tableStats.created + 1
        
        if fPB.debug.enabled then
            DebugLog("memory", "New table created (pool exhausted)")
        end
    end
    
    return tbl
end

-- Release a table back to the pool
local function ReleaseTable(tbl)
    if not tbl then return end
    
    -- Completely empty the table
    wipe(tbl)
    
    -- Ensure the table pool exists
    if not fPB.tablePool then
        fPB.tablePool = {}
    end
    
    -- Only store up to MAX_POOLED_TABLES tables to prevent memory bloat
    if #fPB.tablePool < MAX_POOLED_TABLES then
        tinsert(fPB.tablePool, tbl)
        -- Count tables released back to the pool
        fPB.tableStats.released = fPB.tableStats.released + 1
    end
    
    if fPB.debug.enabled then
        DebugLog("memory", "Table released (pool size: %d)", #fPB.tablePool)
    end
end

-- Optimized function to process all auras on a unit
local function ProcessAllUnitAuras(unitid, effect)
    -- Use the table pool instead of creating a new table each time
    local unit_auras = AcquireTable()
    fPB.debug.stats.tablesAcquired = fPB.debug.stats.tablesAcquired + 1

    local aura_max_display = (effect == "HARMFUL" and DEBUFF_MAX_DISPLAY) or BUFF_MAX_DISPLAY

    -- Using the newer API
    local continuation_token
    repeat
      local slots = { GetAuraSlots(unitid, effect, aura_max_display, continuation_token) }
      continuation_token = slots[1]

      for i = 2, #slots do
        local unit_aura_info = GetAuraDataBySlot(unitid, slots[i])  
        if unit_aura_info then
          unit_aura_info.duration = unit_aura_info.duration or 0
          unit_auras[#unit_auras + 1] = unit_aura_info
        end
      end
    until continuation_token == nil

    return unit_auras
end

  local function UnpackAuraData(auraData)
	if not auraData then
        return nil
	end

	return auraData.name,
		auraData.icon,
		auraData.applications,
		auraData.dispelName,
		auraData.duration,
		auraData.expirationTime,
		auraData.sourceUnit,
		auraData.isStealable,
		auraData.nameplateShowPersonal,
		auraData.spellId,
		auraData.canApplyAura,
		auraData.isBossAura,
		auraData.isFromPlayerOrPlayerPet,
		auraData.nameplateShowAll,
		auraData.timeMod
end

-- Color definitions
fPB.chatColor = "|cFFFFA500"
fPB.linkColor = "|cff71d5ff"
local chatColor = fPB.chatColor
local linkColor = fPB.linkColor

-- Performance optimizations: pre-allocate and reuse tables
local cachedSpells = {}
local PlatesBuffs = {}
local Ctimer = C_Timer.After
local tblinsert = table.insert
local tremove = table.remove
local substring = string.sub
local strfind = string.find
local type = type
local bit_band = bit.band

-- Optimized tracking tables
local Interrupted = {}
local Earthen = {}
local Grounding = {}
local WarBanner = {}
local Barrier = {}
local SGrounds = {}
local SmokeBombAuras = {}

-- Default settings
local DefaultSettings = {
	profile = {
        -- Add new setting for cache debugging
        showCacheHitMessages = false, -- Show cache hit messages even when debug is disabled
        debugCacheMessages = false,  -- Show detailed cache hit/miss messages in chat
        debugFilterMessages = false, -- Show detailed filter optimization messages in chat
        
        -- Early exit optimization for buff filtering
        smartBuffFiltering = true,   -- Use smart early-exit conditions for FilterBuffs
        
        -- Other settings remain unchanged...
        showDebuffs = 2,        -- 1 = all, 2 = mine + spellList, 3 = only spellList, 4 = only mine, 5 = none
        showBuffs = 3,          -- 1 = all, 2 = mine + spellList, 3 = only spellList, 4 = only mine, 5 = none
		showTooltip = false,
		hidePermanent = true,

		showOnPlayers = true,
		showOnPets = true,
		showOnNPC = true,

		showOnEnemy = true,
		showOnFriend = true,
		showOnNeutral = true,

		parentWorldFrame = false,

		baseWidth = 24,
		baseHeight = 24,
		myScale = 0.2,
		cropTexture = true,

		buffAnchorPoint = "BOTTOM",
		plateAnchorPoint = "TOP",

		xInterval = 4,
		yInterval = 12,

		xOffset = 0,
		yOffset = 4,

		buffPerLine = 6,
		numLines = 3,
        maxBuffsPerPlate = 18, -- Default to buffPerLine * numLines

		showStdCooldown = true,
        showStdSwipe = true,
        blizzardCountdown = false,
        
        -- Performance settings
        limitedScanning = true,  -- Process nameplates in batches
        maxPlatesPerUpdate = 3,  -- Number of nameplates to process per frame
        throttleInterval = 0.1,  -- Default throttle interval
        optimizedSorting = true, -- Cache sort results and only resort when necessary
        smartBuffFiltering = true, -- Skip processing invisible or out-of-range auras
        tableRecycling = true,   -- Recycle tables to reduce garbage collection
        sortCacheTolerance = 2,  -- Tolerance level for sort caching (1=low, 2=medium, 3=high)
        
        -- Adaptive detail settings
        adaptiveDetail = true,    -- Automatically adjust detail level based on nameplate count
        adaptiveThresholds = {    -- Nameplate count thresholds for detail levels
            low = 15,             -- Start reducing detail at this many nameplates
            medium = 25,          -- Further reduce detail at this many nameplates
            high = 35             -- Minimum detail at this many nameplates
        },
        adaptiveFeatures = {      -- Features that can be adjusted for performance
            glows = true,         -- Reduce or disable glow effects at higher nameplate counts
            animations = true,    -- Reduce or disable animations at higher nameplate counts
            cooldownSwipes = true,-- Reduce or disable cooldown swipes at higher nameplate counts
            textUpdates = true    -- Reduce frequency of text updates at higher nameplate counts
        },

		colorTypes = {
            none = {0.80, 0.00, 0.00},    -- Red for unknown types
            Magic = {0.20, 0.60, 1.00},   -- Blue for Magic
            Curse = {0.60, 0.00, 1.00},   -- Purple for Curse
            Disease = {0.60, 0.40, 0.00}, -- Brown for Disease
            Poison = {0.00, 0.60, 0.00},  -- Green for Poison
            Buff = {0.00, 1.00, 0.00},    -- Bright Green for Buffs
        },

        colorTransition = false,
        colorSingle = {1.00, 1.00, 1.00},

		Spells = {},
		ignoredDefaultSpells = {},

        borderStyle = 1,           -- 1 = flyPlateBuffs Default, 0 = None
        borderSize = 1,            -- Scale factor for border size
        colorizeBorder = true,     -- Enable border coloring by default

        targetScale = 1.2,           -- Scale factor for target's auras
        targetGlow = false,          -- Add glow effect to target's auras
        iconMasque = true,           -- Enable Masque support
        frameLevel = 1,              -- Frame level adjustment
        font = "Friz Quadrata TT",   -- Font for text elements
        stackFont = "Friz Quadrata TT", -- Font for stack count

        sortMethod = 2,
        reversSort = false,
        disableSort = false,
        stackOnTop = true,

        durationSize = 10,           -- Size of duration text
        durationPosition = 2,        -- Position of duration text (2 = on icon)
        durationBackgroundPadding = 2, -- Padding around duration text for background (in pixels)
        durationBackgroundAlpha = 0.7, -- Alpha/transparency of the duration text background
        stackSize = 10,
        stackPosition = 1,
        stackColor = {1.00, 1.00, 1.00},

        hideNonBosses = false,
        hideBufnNonPlayers = false,
        
        showDuration = true,         -- Show remaining duration text
        showDecimals = true,         -- Show decimal places in duration
        
        durationSizeY = 0,           -- Y offset for duration text
        durationSizeX = 0,           -- X offset for duration text
        
        -- Stack settings
        stackOverride = false,
        stackScale = false,
        stackSpecific = false,
        stackSizeY = 0,
        stackSizeX = 0,
        showStackText = true,
        
        blinkTimeleft = 0.3,         -- Start blinking when remaining time is below 30% of total duration
        
        -- Debug settings
        debugEnabled = false,
        debugPerformance = false,
        debugMemory = false,
        debugEvents = false,
        debugVerbose = false,
        debugSamplingRate = 100,
        debugMemoryTrackingFrequency = 0,
        debugSignificantMemoryChangeOnly = false,
        debugMemoryChangeThreshold = 50,
        debugUnitNameFilter = "",
        debugAutoDisableAfter = 0,
        debugDetailLevel = 2,
        debugDynamicThrottlingEnabled = true,
    },
}

-- Initialize default spells more efficiently
do
    local function AddDefaultSpell(spellId, scale, durationSize, stackSize, class)
        local name = GetSpellInfo(spellId)
        if name then
            DefaultSettings.profile.Spells[spellId] = {
                name = name,
                spellId = spellId,
                scale = scale,
                durationSize = durationSize,
                show = 1,    -- 1 = always, 2 = mine, 3 = never, 4 = on ally, 5 = on enemy
                stackSize = stackSize,
                class = class, -- Add class information
            }
        end
    end

    -- Process defaultSpells1 (important spells)
    for classHeader, spells in pairs(defaultSpells1) do
        local class = classHeader:match("|c%x+(.+)|r")
        for _, spellId in ipairs(spells) do
            AddDefaultSpell(spellId, 2, 18, 18, class)
        end
    end
    
    -- Process defaultSpells2 (semi-important spells)
    for classHeader, spells in pairs(defaultSpells2) do
        local class = classHeader:match("|c%x+(.+)|r")
        for _, spellId in ipairs(spells) do
            AddDefaultSpell(spellId, 1.5, 14, 14, class)
        end
    end
end

-- Overlay glow functions
local function ActionButton_SetupOverlayGlow(button)
    -- Empty function to prevent Blizzard glow
end

local function ActionButton_ShowOverlayGlow(button, scale)
    -- Empty function to prevent Blizzard glow
end

local function ActionButton_HideOverlayGlow(button)
    -- Empty function to prevent Blizzard glow
end

-- UI coloring functions
local hexFontColors = {
    ["logo"] = "ff36ffe7",
    ["accent"] = "ff9b6ef3",
    ["value"] = "ffffe981",
    ["blizzardFont"] = NORMAL_FONT_COLOR:GenerateHexColor(),
}

local function Colorize(text, color)
    if not text then return end
    local hexColor = hexFontColors[color] or hexFontColors["blizzardFont"]
    return "|c" .. hexColor .. text .. "|r"
end

-- Time formatting constants
local minute, hour, day = 60, 3600, 86400
local aboutMinute, aboutHour, aboutDay = 59.5, 60 * 59.5, 3600 * 23.5

local function round(x) 
    return math_floor(x + 0.5) 
end

local function FormatTime(seconds)
	if seconds < 10 and db.showDecimals then
		return "%.1f", seconds
	elseif seconds < aboutMinute then
		local seconds = round(seconds)
		return seconds ~= 0 and seconds or ""
	elseif seconds < aboutHour then
		return "%dm", round(seconds/minute)
	elseif seconds < aboutDay then
		return "%dh", round(seconds/hour)
	else
		return "%dd", round(seconds/day)
	end
end

local function GetColorByTime(current, max)
	if max == 0 then max = 1 end
	local percentage = (current/max)*100
    local red, green = 0, 0
    
	if percentage >= 50 then
        -- Green to yellow
        green = 1
        red = ((100 - percentage) / 100) * 2
    else
        -- Yellow to red
        red = 1
        green = ((percentage) / 100) * 2
    end
    
	return red, green, 0
end

-- Add these variables near the top of the file with other cache variables
local SortCache = {}
local NeedsSorting = {}

-- Initialize sort stats
fPB.sortStats = {
    totalSorts = 0,
    cacheMisses = 0,
    cacheHits = 0,
    lastReset = GetTime()
}

-- Add this function to reset sort statistics
local function ResetSortStats()
    -- Create or reset the sort stats tracking table
    if not fPB.sortStats then
        fPB.sortStats = {
            totalSorts = 0,
            cacheHits = 0,
            cacheMisses = 0,
            smallExpirationChanges = 0,
            significantExpirationChanges = 0,
            otherPropertyChanges = 0,
            buffCountChanges = 0,
            lastReset = GetTime()
        }
    else
        fPB.sortStats.totalSorts = 0
        fPB.sortStats.cacheHits = 0
        fPB.sortStats.cacheMisses = 0
        fPB.sortStats.smallExpirationChanges = 0
        fPB.sortStats.significantExpirationChanges = 0
        fPB.sortStats.otherPropertyChanges = 0
        fPB.sortStats.buffCountChanges = 0
        fPB.sortStats.lastReset = GetTime()
    end
    
    if fPB.debug and fPB.debug.enabled then
        DebugLog("events", "Sort statistics reset")
    end
end

-- Add this to the addon namespace for use elsewhere
fPB.ResetSortStats = ResetSortStats

-- Add this function to clear the sort caches (called when settings change)
local function wipeAllSortCaches()
    wipe(SortCache)
    wipe(NeedsSorting)
    DebugLog("events", "Wiped all sort caches")
end

-- Mark a frame as needing sorting
local function MarkForSorting(frame)
    if frame then
        NeedsSorting[frame] = true
    end
end

-- Function to check if buffs have changed and need resorting
local function HasBuffsChanged(frame, buffs)
    if not db.optimizedSorting then return true end
    
    local unitName = frame and frame.namePlateUnitToken and UnitName(frame.namePlateUnitToken) or "unknown"
    
    if not SortCache[frame] then
        if fPB.debug.enabled then
            fPB.sortStats.cacheMisses = (fPB.sortStats.cacheMisses or 0) + 1
        end
        if db.showCacheHitMessages or (fPB.debug.enabled and fPB.debug.cacheMessages) then
            print(FormatMessage("Cache", string.format("Miss: No cache exists for %s", unitName), "WARNING"))
        end
        return true
    end
    
    if #buffs ~= #SortCache[frame] then
        if fPB.debug.enabled then
            fPB.sortStats.buffCountChanges = (fPB.sortStats.buffCountChanges or 0) + 1
        end
        if db.showCacheHitMessages or (fPB.debug.enabled and fPB.debug.cacheMessages) then
            print(FormatMessage("Cache", string.format("Miss: Buff count changed for %s from %d to %d", 
                unitName, #SortCache[frame], #buffs), "WARNING"))
        end
        return true
    end
    
    -- Rest of the function remains the same, just update the message formatting
    if db.showCacheHitMessages or (fPB.debug.enabled and fPB.debug.cacheMessages) then
        print(FormatMessage("Cache", string.format("Hit: No significant changes for %s (%d buffs)", 
            unitName, #buffs), "SUCCESS"))
    end
    
    if fPB.debug.enabled then
        fPB.sortStats.cacheHits = (fPB.sortStats.cacheHits or 0) + 1
    end
    
    return false
end

-- Function to cache the current buffs state
local function CacheBuffsState(frame, buffs)
    if not SortCache[frame] then
        SortCache[frame] = {}
    else
        wipe(SortCache[frame])
    end
    
    local cache = SortCache[frame]
    for i = 1, #buffs do
        local buff = buffs[i]
        cache[i] = {
            name = buff.name,
            expiration = buff.expiration,
            my = buff.my,
            type = buff.type,
            scale = buff.scale,
            icon = buff.icon,
            spellId = buff.spellId
        }
    end
    
    NeedsSorting[frame] = false
    DebugLog("events", "Cached sort state for frame with %d buffs", #buffs)
end

-- Function to clear cache when plate is recycled
local function ClearFrameSortCache(frame)
    if SortCache[frame] then
        wipe(SortCache[frame])
        SortCache[frame] = nil
    end
    NeedsSorting[frame] = nil
end

-- Expose the functions for debug commands
fPB.ResetSortStats = ResetSortStats
fPB.wipeAllSortCaches = wipeAllSortCaches

-- Optimized sort function
local function SortFunc(a, b)
    if not a or not b then return false end
    
    -- Use sortMethod instead of sortMode
    local sortMethod = db.sortMethod or 2
    
    -- Default sort by expiration time if sorted by method 2
    if sortMethod == 2 then
        if a.expiration ~= b.expiration then
            local aExp = a.expiration > 0 and a.expiration or 5000000
            local bExp = b.expiration > 0 and b.expiration or 5000000
            return db.reversSort and (aExp > bExp) or (aExp < bExp)
        end
    end
    
    -- Sort by whether it's the player's spell first if sorted by method 1 or not specified
    if sortMethod == 1 or not sortMethod then
        if a.my ~= b.my then
            return db.reversSort and ((a.my and 1 or 0) < (b.my and 1 or 0)) or ((a.my and 1 or 0) > (b.my and 1 or 0))
        end
    end
    
    -- Secondary sort by type
    if a.type ~= b.type then
        return db.reversSort and (a.type < b.type) or (a.type > b.type)
    end
    
    -- Third sort by scale
    if a.scale ~= b.scale then
        return db.reversSort and (a.scale < b.scale) or (a.scale > b.scale)
    end
    
    -- Last, sort by icon
    if a.icon ~= b.icon then
        return db.reversSort and (a.icon > b.icon) or (a.icon < b.icon)
    end
    
    return false
end

-- Optimized plate drawing function
local function DrawOnPlate(frame)
    local buffIcons = frame.fPBiconsFrame.iconsFrame
    local iconsCount = #buffIcons
    
    if iconsCount == 0 then return end

    -- Respect maxBuffsPerPlate setting if it exists
    local maxIcons = db.maxBuffsPerPlate or (db.buffPerLine * db.numLines)
    
    -- Hide excess icons beyond the maximum limit
    if iconsCount > maxIcons then
        for i = maxIcons + 1, iconsCount do
            if buffIcons[i] then
                buffIcons[i]:Hide()
            end
        end
        -- Adjust iconsCount to the maximum
        iconsCount = maxIcons
    end

    local maxWidth = 0
    local sumHeight = 0
    local maxLines = db.numLines
    local maxPerLine = db.buffPerLine
    local xInterval = db.xInterval
    local yInterval = db.yInterval

    for l = 1, maxLines do
        local lineWidth = 0
        local lineHeight = 0
        local startIdx = (l-1) * maxPerLine + 1
        local endIdx = l * maxPerLine
        
        if startIdx > iconsCount then break end
        
        for i = startIdx, math.min(endIdx, iconsCount) do
            if not buffIcons[i] or not buffIcons[i]:IsShown() then break end
            
            buffIcons[i]:ClearAllPoints()
            
            if i == 1 then
                buffIcons[i]:SetPoint("BOTTOMLEFT", frame.fPBiconsFrame, "BOTTOMLEFT", 0, 0)
            elseif i == startIdx then
                buffIcons[i]:SetPoint("BOTTOMLEFT", buffIcons[i-maxPerLine], "TOPLEFT", 0, yInterval)
            else
                buffIcons[i]:SetPoint("BOTTOMLEFT", buffIcons[i-1], "BOTTOMRIGHT", xInterval, 0)
            end
            
            lineWidth = lineWidth + buffIcons[i].width + xInterval
            lineHeight = math.max(lineHeight, buffIcons[i].height)
        end
        
        maxWidth = math.max(maxWidth, lineWidth)
        sumHeight = sumHeight + lineHeight + yInterval
    end
    
    -- Hide excess icons
    if iconsCount > maxIcons then
        for i = maxIcons + 1, iconsCount do
            buffIcons[i]:Hide()
        end
    end
    
    -- Apply frame dimensions
    frame.fPBiconsFrame:SetWidth(maxWidth - xInterval)
    frame.fPBiconsFrame:SetHeight(sumHeight - yInterval)
    frame.fPBiconsFrame:ClearAllPoints()
    frame.fPBiconsFrame:SetPoint(db.buffAnchorPoint, frame, db.plateAnchorPoint, db.xOffset, db.yOffset)
    
    if MSQ then
        Group:ReSkin()
    end
end

local function AddBuff(frame, type, icon, stack, debufftype, duration, expiration, my, id, spellId, EnemyBuff, scale, durationSize, stackSize, icon_override, glow)
    if icon_override then icon = icon_override end
    
    if not PlatesBuffs[frame] then 
        PlatesBuffs[frame] = {} 
    end
    
    -- Get spell settings
    local Spell = db.Spells[spellId]
    
    -- Create buff data
    PlatesBuffs[frame][#PlatesBuffs[frame] + 1] = {
        type = type,
        icon = icon,
        stack = stack,
        debufftype = debufftype,
        duration = duration,
        expiration = expiration,
        scale = (my and tonumber(db.myScale) + 1 or 1) * (tonumber(scale) or 1),
        durationSize = durationSize,
        stackSize = stackSize,
        id = id,
        EnemyBuff = EnemyBuff,
        spellId = spellId,
        my = my,
        IconGlow = Spell and Spell.IconGlow,
        glowColor = Spell and Spell.glowColor,
        glow = glow
    }
    
    -- Mark this frame as needing sorting
    MarkForSorting(frame)
end

-- Log when important aura properties change to help debug caching issues
local function TrackAuraChanges(nameplateID, name, spellId, duration, expiration)
    if not fPB.debug.auraTracking then return end
    
    -- Track this aura if it hasn't been tracked before
    if not fPB.auraHistory then fPB.auraHistory = {} end
    if not fPB.auraHistory[spellId] then 
        fPB.auraHistory[spellId] = {
            name = name,
            lastExpiration = 0,
            lastDuration = 0,
            changes = 0,
            unitName = UnitName(nameplateID) or "unknown"
        }
    end
    
    local history = fPB.auraHistory[spellId]
    
    -- Check if important properties changed
    if history.lastExpiration ~= expiration or history.lastDuration ~= duration then
        history.changes = history.changes + 1
        
        -- Only log the change if it's significant
        if history.changes <= 5 or (history.changes % 10 == 0) then
            print(string.format("|cFF00FFFF[FPB-AuraTracking]|r %s on %s - expiration: %.1f→%.1f, duration: %.1f→%.1f (changes: %d)", 
                name or spellId, history.unitName, 
                history.lastExpiration, expiration,
                history.lastDuration, duration,
                history.changes))
        end
        
        -- Update the history
        history.lastExpiration = expiration
        history.lastDuration = duration
    end
end

-- Add these stats for tracking buff filtering optimizations
if not fPB.filterStats then
    fPB.filterStats = {
        totalBuffsChecked = 0,
        earlyExits = 0,
        lastReset = GetTime()
	}
end

local function FilterBuffs(isAlly, frame, type, name, icon, stack, debufftype, duration, expiration, caster, spellId, id, nameplateID)
    -- Update statistics for debugging
    fPB.filterStats.totalBuffsChecked = (fPB.filterStats.totalBuffsChecked or 0) + 1
    
    -- EARLY EXIT CONDITIONS - Skip processing if obvious conditions are met
    
    -- 1. Immediate type filtering based on settings
    if type == "HARMFUL" and db.showDebuffs == 5 then
        if fPB.debug.enabled and fPB.debug.filterMessages then
            DebugLog("filtering", "Early exit: HARMFUL with showDebuffs=5 for %s", name or "unknown")
        end
        fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
        return 
    end
    
    if type == "HELPFUL" and db.showBuffs == 5 then
        if fPB.debug.enabled and fPB.debug.filterMessages then
            DebugLog("filtering", "Early exit: HELPFUL with showBuffs=5 for %s", name or "unknown")
        end
        fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
        return 
    end
    
    -- Fast path early exits when smart filtering is enabled
    if db.smartBuffFiltering then
        -- 2. Skip permanent auras if setting enabled and no spell is explicitly listed
        local cachedID = cachedSpells[name]
        local isListed = db.Spells[spellId] or (cachedID and (cachedID == "noid" and db.Spells[name] or db.Spells[cachedID]))
        
        if db.hidePermanent and duration == 0 and not isListed then
            if fPB.debug.enabled and fPB.debug.filterMessages then
                DebugLog("filtering", "Early exit: permanent aura %s not explicitly listed", name or "unknown")
            end
            fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
            return
        end
        
        -- 3. Skip if personal aura settings don't match
        local my = caster == "player"
        if type == "HARMFUL" and db.showDebuffs == 4 and not my then
            if fPB.debug.enabled and fPB.debug.filterMessages then
                DebugLog("filtering", "Early exit: non-player HARMFUL with showDebuffs=4 for %s", name or "unknown")
            end
            fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
            return
        end
        
        if type == "HELPFUL" and db.showBuffs == 4 and not my then
            if fPB.debug.enabled and fPB.debug.filterMessages then
                DebugLog("filtering", "Early exit: non-player HELPFUL with showBuffs=4 for %s", name or "unknown")
            end
            fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
            return
        end
        
        -- 4. Skip auras that aren't allowed based on current filter mode
        if not isListed then
            if type == "HARMFUL" and not (db.showDebuffs == 1 or ((db.showDebuffs == 2 or db.showDebuffs == 4) and my)) then
                if fPB.debug.enabled and fPB.debug.filterMessages then
                    DebugLog("filtering", "Early exit: HARMFUL not matching filter criteria for %s", name or "unknown")
                end
                fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
                return
            end
            if type == "HELPFUL" and not (db.showBuffs == 1 or ((db.showBuffs == 2 or db.showBuffs == 4) and my)) then
                if fPB.debug.enabled and fPB.debug.filterMessages then
                    DebugLog("filtering", "Early exit: HELPFUL not matching filter criteria for %s", name or "unknown")
                end
                fPB.filterStats.earlyExits = (fPB.filterStats.earlyExits or 0) + 1
                return
            end
        end
    end
    
    -- Track aura changes for debugging when enabled
    if fPB.debug.auraTracking then
        TrackAuraChanges(nameplateID, name, spellId, duration, expiration)  
    end

    -- REGULAR PROCESSING - Continue with the original function logic
	local Spells = db.Spells
	local listedSpell
	local my = caster == "player"
	local cachedID = cachedSpells[name]
	local EnemyBuff

	if Spells[spellId] and not db.ignoredDefaultSpells[spellId] then
		listedSpell = Spells[spellId]
	elseif cachedID then
		if cachedID == "noid" then
			listedSpell = Spells[name]
		else
			listedSpell = Spells[cachedID]
		end
	end
	
	if (listedSpell and (listedSpell.showBuff or listedSpell.showDebuff) and type == "HARMFUL") and listedSpell.showBuff then return end
	if (listedSpell and (listedSpell.showBuff or listedSpell.showDebuff) and type == "HELPFUL") and listedSpell.showDebuff then return end

	if listedSpell and listedSpell.RedifEnemy and caster and UnitIsEnemy("player", caster) then --still returns true for an enemy currently under mindcontrol I can add your fix.
		EnemyBuff = true
	else
		EnemyBuff = nil
	end

	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--CLEU Deuff Timer
	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	-----------------------------------------------------------------------------------------------------------------
	--SmokeBomb Check For Arena
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 212183 then -- Smoke Bomb
		if caster and SmokeBombAuras[UnitGUID(caster)] then
			duration = SmokeBombAuras[UnitGUID(caster)].duration --Add a check, i rogue bombs in stealth there is a source but the cleu doesnt regester a time
			expiration = SmokeBombAuras[UnitGUID(caster)].expiration
		end
	end

	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--CLEU Buff Timer
	--------------------------------------------------------------------------------------------------------------------------------------------------------------

	-----------------------------------------------------------------------------------------------------------------
	--Barrier Add Timer Check For Arena
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 81782 then -- Barrier
		if caster and Barrier[UnitGUID(caster)] then
			duration = Barrier[UnitGUID(caster)].duration
			expiration = Barrier[UnitGUID(caster)].expiration
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	--SGrounds Add Timer Check For Arena
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 289655 then -- SGrounds
		if caster and SGrounds[UnitGUID(caster)] then
			duration = SGrounds[UnitGUID(caster)].duration
			expiration = SGrounds[UnitGUID(caster)].expiration
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	-- Earthen Totem (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 201633 then -- Earthen Totem (Totems Need a Spawn Time Check)
		if caster then
			local guid = UnitGUID(caster)
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("Earthen Buff Check at: "..spawnTime)
			end
	    if Earthen[spawnTime] then
			duration = Earthen[spawnTime].duration
			expiration = Earthen[spawnTime].expiration
			end
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	-- Grounding (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 8178 then -- Grounding (Totems Need a Spawn Time Check)
		if caster then
			local guid = UnitGUID(caster)
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("Grounding Buff Check at: "..spawnTime)
			end
			if Grounding[spawnTime] then
			duration = Grounding[spawnTime].duration
			expiration = Grounding[spawnTime].expiration
			end
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	-- WarBanner (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 236321 then -- WarBanner (Totems Need a Spawn Time Check)
		if caster then
			local guid = UnitGUID(caster)
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("WarBanner Buff Check at: "..spawnTime)
			end
			if WarBanner[spawnTime] then
				--print("Spawn: "..UnitName(caster))
				duration = WarBanner[spawnTime].duration
				expiration = WarBanner[spawnTime].expiration
			elseif WarBanner[guid] then
				--print("guid: "..UnitName(caster))
				duration = WarBanner[guid].duration 
				expiration = WarBanner[guid].expiration
			elseif WarBanner[1] then
				--print("1: "..UnitName(caster))
				duration = WarBanner[1].duration
				expiration = WarBanner[1].expiration
			end
		else
			--print("WarBanner Nocaster")
			duration = WarBanner[1].duration 
			expiration = WarBanner[1].expiration
		end
	end



	-----------------------------------------------------------------------------------------------------------------
	--Two Buff Conditions Icy Veins Stacks
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 12472 then
		local unit_auras = ProcessAllUnitAuras(nameplateID, type)
		for i = 1, #unit_auras do
			local aura = unit_auras[i]
			local _, _, c, _, d, e, _, _, _, s = UnpackAuraData(aura)
			if s == 382148 then
				stack = c
				break
			end
		end
        -- Release the table back to the pool
        ReleaseTable(unit_auras)
        fPB.debug.stats.tablesReleased = fPB.debug.stats.tablesReleased + 1
	end



	-----------------------------------------------------------------------------------------------------------------
	--Buff Icon Changes
	-----------------------------------------------------------------------------------------------------------------


	if spellId == 363916 then --Obsidian Scales w/Mettles
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "Immune") then
			icon = 1526594
		end
	end

	if spellId == 358267 then --Hover/Unburdened Flight
        local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "Immune") then
			icon = 1029587
		end
    end

	if spellId == 319504 then --Finds Hemotoxin for Shiv
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "35") then
			icon = 3610996
		else
			
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	--Count Changes
	-----------------------------------------------------------------------------------------------------------------
	if spellId == 1714  then --Amplify Curse's Tongues
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if not strfind(tooltipData.lines[2].leftText, "10") then
			stack = 20
		else
			
		end
	end
	if spellId == 702 then --Amplify Curse's Weakness
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "100") then
			stack = 100
		else
			
		end
	end
	if spellId == 334275 then --Amplify Curse's Exhaustion
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "70") then
			stack = 70
		else
			
		end
	end

	if spellId == 454863 then --Friends AMS 50% Magic Wall
		local tooltipData = C_TooltipInfo.GetUnitAura(nameplateID, id, type)
		--print("Unit Aura: ", tooltipData.lines[1].leftText)
		--print("Aura Info: ", tooltipData.lines[2].leftText)
		if strfind(tooltipData.lines[2].leftText, "50") then
			stack = 50
		else
			
		end
	end




	-- showDebuffs  1 = all, 2 = mine + spellList, 3 = only spellList, 4 = only mine, 5 = none
	-- listedSpell.show  -- 1 = always, 2 = mine, 3 = never, 4 = on ally, 5 = on enemy
	
	if not listedSpell then
		if db.hidePermanent and duration == 0 then
			return
		end
		if (type == "HARMFUL" and (db.showDebuffs == 1 or ((db.showDebuffs == 2 or db.showDebuffs == 4) and my)))
		or (type == "HELPFUL"   and (db.showBuffs   == 1 or ((db.showBuffs   == 2 or db.showBuffs   == 4) and my))) then
			AddBuff(frame, type, icon, stack, debufftype, duration, expiration, my, id, spellId, EnemyBuff, nil, nil, nil, nil, nil)
			return
		else
			return
		end
	else --listedSpell
		if (type == "HARMFUL" and (db.showDebuffs == 4 and not my))
		or (type == "HELPFUL" and (db.showBuffs == 4 and not my)) then
			return
		end
		if((listedSpell.show == 1)
		or(listedSpell.show == 2 and my)
		or(listedSpell.show == 4 and isAlly)
		or(listedSpell.show == 5 and not isAlly)) and not listedSpell.spellDisableAura then
			AddBuff(frame, type, icon, stack, debufftype, duration, expiration, my, id, spellId, EnemyBuff, listedSpell.scale, listedSpell.durationSize, listedSpell.stackSize, listedSpell.IconId, listedSpell.IconGlow)
			return
		end
	end
end

-- Helper functions for common patterns
local function GetUnitAuras(unit)
    if not unit then return nil end
    
    local buffs = ProcessAllUnitAuras(unit, "HELPFUL")
    local debuffs = ProcessAllUnitAuras(unit, "HARMFUL")
    
    local result = {
        buffs = buffs,
        debuffs = debuffs,
        Release = function()
            ReleaseTable(buffs)
            ReleaseTable(debuffs)
            fPB.debug.stats.tablesReleased = (fPB.debug.stats.tablesReleased or 0) + 2
        end
    }
    
    return result
end

-- Make GetUnitAuras available to the addon namespace
fPB.GetUnitAuras = GetUnitAuras

local function ScanUnitBuffs(nameplateID, frame)
    -- Guard against nil nameplateID
    if not nameplateID or not frame then
        if fPB.debug.enabled then
            DebugLog("events", "ScanUnitBuffs called with nil nameplateID or frame")
        end
        return
    end

    if PlatesBuffs[frame] then
        wipe(PlatesBuffs[frame])
    end

    -- Make sure nameplateID is valid before using API functions on it
    if not UnitExists(nameplateID) then
        if fPB.debug.enabled then
            DebugLog("events", "ScanUnitBuffs called with non-existent unit: %s", tostring(nameplateID))
        end
        return
    end

    local isAlly = UnitIsFriend(nameplateID, "player")
    local Friend = UnitReaction(nameplateID,"player")
    if Friend and (Friend == 5 or Friend == 6 or Friend == 7) then
        Friend = true 
    else    
        Friend = false
    end

    if isAlly ~= Friend then 
        if UnitReaction(nameplateID,"player") == 4 then 
            isAlly = true
        else
            isAlly = Friend
            if fPB.debug.enabled then
                DebugLog("events", "%s UnitIsFriend is %s ~= UnitReaction is %s %s", 
                    UnitName(nameplateID) or "", tostring(isAlly), tostring(Friend), 
                    tostring(UnitReaction(nameplateID,"player")))
            end
        end
    end

    -- Get all auras at once
    local auras = fPB.GetUnitAuras(nameplateID)
    if not auras then return end

    -- Process harmful auras
    for id = 1, #auras.debuffs do
        local aura = auras.debuffs[id]
        local name, icon, stack, debufftype, duration, expiration, caster, _, _, spellId = UnpackAuraData(aura)
        FilterBuffs(isAlly, frame, "HARMFUL", name, icon, stack, debufftype, duration, expiration, caster, spellId, id, nameplateID)
    end

    -- Process helpful auras
    for id = 1, #auras.buffs do
        local aura = auras.buffs[id]
        local name, icon, stack, debufftype, duration, expiration, caster, _, _, spellId = UnpackAuraData(aura)
        FilterBuffs(isAlly, frame, "HELPFUL", name, icon, stack, debufftype, duration, expiration, caster, spellId, id, nameplateID)
    end

    -- Release the aura tables
    auras:Release()
end

local function FilterUnits(nameplateID)
    -- Guard against nil or invalid nameplateID
    if not nameplateID or not UnitExists(nameplateID) then
        if fPB.debug.enabled then
            DebugLog("events", "FilterUnits called with invalid unit: %s", tostring(nameplateID))
        end
        return true -- Filter out invalid units
    end

    -- filter units
    if UnitIsUnit(nameplateID,"player") then return true end
    if UnitIsPlayer(nameplateID) and not db.showOnPlayers then return true end
    
    -- Check for pets (simplified, removed PvP check)
    if UnitPlayerControlled(nameplateID) and not UnitIsPlayer(nameplateID) and not db.showOnPets then return true end
    
    if not UnitPlayerControlled(nameplateID) and not UnitIsPlayer(nameplateID) and not db.showOnNPC then return true end
    if UnitIsEnemy(nameplateID,"player") and not db.showOnEnemy then return true end
    
    local Friend = UnitReaction(nameplateID,"player")
    if Friend and (Friend == 5 or Friend == 6 or Friend == 7 or Friend == 8) then
        Friend = true 
    else    
        Friend = false
    end
    if Friend and not db.showOnFriend then return true end
    if not Friend and not UnitIsEnemy(nameplateID,"player") and not db.showOnNeutral then return true end

    return false
end

local total = 0
local function iconOnUpdate(self, elapsed)
	total = total + elapsed
	if total > 0 then
		total = 0
		if self.expiration and self.expiration > 0 then
			local timeLeft = self.expiration - GetTime()
			if timeLeft < 0 then
				return
			end
			if db.showDuration then
				self.durationtext:SetFormattedText(FormatTime(timeLeft))
				if db.colorTransition then
					self.durationtext:SetTextColor(GetColorByTime(timeLeft, self.duration))
				end
				
				-- Adjust background size for positions with background
				if (db.durationPosition == 1 or db.durationPosition == 3) and 
                   self.durationBg and self.durationBg:IsShown() then
					-- Use the configurable padding value for the background
					local padding = db.durationBackgroundPadding or 2
					self.durationBg:SetWidth(self.durationtext:GetStringWidth() + padding)
					self.durationBg:SetHeight(self.durationtext:GetStringHeight() + padding/1.5)
					-- Apply the alpha/transparency setting
					self.durationBg:SetAlpha(db.durationBackgroundAlpha or 0.7)
				end
			end
			if (timeLeft / (self.duration + 0.01)) < db.blinkTimeleft and timeLeft < 60 then
				local f = GetTime() % 1
				if f > 0.5 then
					f = 1 - f
				end
				f = math.floor((f * 3) * 100) / 100
				if f < 1 then
					self:SetAlpha(f)
				end
			end
		end
	end
end
local function GetTexCoordFromSize(frame,size,size2)
	local arg = size/size2
	local abj
	if arg > 1 then
		abj = 1/size*((size-size2)/2)

		frame:SetTexCoord(0 ,1,(0+abj),(1-abj))
	elseif arg < 1 then
		abj = 1/size2*((size2-size)/2)

		frame:SetTexCoord((0+abj),(1-abj),0,1)
	else
		frame:SetTexCoord(0, 1, 0, 1)
	end
end

local function UpdateBuffIcon(self, buff)
    self:EnableMouse(false)
    self:SetAlpha(1)
    self.stacktext:Hide()
    self.border:Hide()
    self.cooldown:Hide()
    self.durationtext:Hide()
    self.durationBg:Hide()

    self:SetWidth(self.width)
    self:SetHeight(self.height)

    -- Set texture
    self.texture:SetTexture(self.icon)
    if db.cropTexture then
        GetTexCoordFromSize(self.texture, self.width, self.height)
    else
        self.texture:SetTexCoord(0, 1, 0, 1)
    end

    -- Handle enemy buff desaturation
    if self.EnemyBuff then
        self.texture:SetDesaturated(1)
        self.texture:SetVertexColor(1, .25, 0)
    else
        self.texture:SetDesaturated(nil)
        self.texture:SetVertexColor(1, 1, 1)
    end

    -- Border handling
    if MSQ and db.iconMasque then
        -- When Masque is enabled, let it handle all border styling
        if not self.masqueSet then
            self.masqueData = {
                Icon = self.texture,
                Cooldown = self.cooldown,
                Normal = self.border,
                Count = self.stacktext,
                Duration = self.durationtext,
                Pushed = false,
                Disabled = false,
                Checked = false,
                AutoCastable = false,
                Highlight = false,
                HotKey = false,
                Name = false,
                AutoCast = false,
            }
            Group:AddButton(self, self.masqueData)
            self.masqueSet = true
        end
        self.border:Hide()
    else
        -- When Masque is disabled or our custom borders are desired
        if self.masqueSet then
            Group:RemoveButton(self)
            self.masqueData = nil
            self.masqueSet = nil
        end
        
        if db.borderStyle == 1 then
            -- Set up border texture and coordinates
            self.border:SetTexture("Interface\\AddOns\\flyPlateBuffs\\texture\\border.tga")
            self.border:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            self.border:ClearAllPoints()
            self.border:SetPoint("CENTER", self, "CENTER", 0, 0)
            
            local color = {0, 0, 0} -- Default black
            
            -- Only apply colors if colorizeBorder is enabled and we have at least one aura type selected
            if db.colorizeBorder then
                if self.type == "HELPFUL" then
                    if db.colorTypes.Buff then
                        color = db.colorTypes.Buff
                    end
                else
                    if self.debufftype and db.colorTypes[self.debufftype] then
                        color = db.colorTypes[self.debufftype]
                    elseif db.colorTypes.none then
                        color = db.colorTypes.none
                    end
                end
            end

            -- Show and color the border
            if color and #color >= 3 then
                self.border:SetVertexColor(color[1], color[2], color[3], 1)
                self.border:Show()
            else
                -- Fallback to black if no valid color found
                self.border:SetVertexColor(0, 0, 0, 1)
                self.border:Show()
            end
            
            -- Apply border size
            local borderSize = db.borderSize or 1
            self.border:SetWidth(self.width * borderSize)
            self.border:SetHeight(self.height * borderSize)
        else
            self.border:Hide()
        end
    end

    -- Cooldown handling
    if (db.showStdCooldown or db.showStdSwipe or db.blizzardCountdown) and self.expiration > 0 then
        local start, duration = self.cooldown:GetCooldownTimes()
        if (start ~= (self.expiration - self.duration)) or duration ~= self.durationthen then
            self.cooldown:SetCooldown(self.expiration - self.duration, self.duration)
        end
    end

    -- Duration text
    if db.showDuration and self.expiration > 0 then
        -- Font based on position
        if db.durationPosition == 1 or db.durationPosition == 3 then
            -- Positions with background - use normal font
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "NORMAL")
            self.durationBg:Show()
            -- Apply the alpha/transparency setting
            self.durationBg:SetAlpha(db.durationBackgroundAlpha or 0.7)
        else
            -- Positions without background - use outlined font
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "OUTLINE")
            self.durationBg:Hide()
        end
        
        self.durationtext:Show()
    end

    -- Stack text
    if self.stack > 1 and type(tostring(self.stack)) == "string" then
        local text = tostring(self.stack)
        if db.stackSpecific and (self.stackSize and self.stackSize > 1) then
            self.stacktext:SetFont(fPB.stackFont, (self.stackSize), "OUTLINE")
            self.stacktext:SetText(text)
        elseif db.stackOverride then
            self.stacktext:SetFont(fPB.stackFont, (db.stackSize), "OUTLINE")
            self.stacktext:SetText(text)
        elseif db.stackScale then
            self.stacktext:SetFont(fPB.stackFont, (db.stackSize*self.scale), "OUTLINE")
            self.stacktext:SetText(text)
        else
            self.stacktext:SetFont(fPB.stackFont, (db.stackSize), "OUTLINE")
            self.stacktext:SetText(text)
        end
        self.stacktext:Show()
    end

    -- Glow effect
    if self.glow then
        if buff and buff.IconGlow then
            -- Get color from spell settings
            local color = buff.glowColor
            if color and color.r and color.g and color.b then
                fPB.ShowCustomGlow(self, color.r, color.g, color.b, color.a or 1)
            else
                fPB.ShowCustomGlow(self, 1, 1, 1, 1)
            end
        else
            fPB.HideCustomGlow(self)
        end
    else
        fPB.HideCustomGlow(self)
    end
end

local function UpdateBuffIconOptions(self, buff)
    self.texture:SetAllPoints(self)

    -- Border texture setup
    if db.borderStyle == 1 then
        self.border:SetTexture("Interface\\AddOns\\flyPlateBuffs\\texture\\border.tga")
        self.border:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self.border:ClearAllPoints()
        self.border:SetPoint("CENTER", self, "CENTER", 0, 0)
        -- Border size will be applied in UpdateBuffIcon on each update
    else
        self.border:Hide()
    end

    -- Cooldown swipe
    if db.showStdSwipe then
        self.cooldown:SetDrawSwipe(true)
        self.cooldown:SetSwipeColor(0, 0, 0, 0.6)
    else
        self.cooldown:SetDrawSwipe(false)
    end

    -- OmniCC compatibility
    local hasOmniCC = C_AddOns.IsAddOnLoaded("OmniCC")
    if db.showStdCooldown and hasOmniCC then
        self.cooldown:SetScript("OnUpdate", nil)
        if self.cooldown._occ_display then 
            self.cooldown._occ_display:Show() 
        end
    elseif hasOmniCC then
        self.cooldown:SetScript("OnUpdate", function() 
            if self.cooldown._occ_display and self.cooldown._occ_display:IsShown() then 
                self.cooldown._occ_display:Hide() 
            end 
        end)
    end

    -- Blizzard countdown numbers
    self.cooldown:SetHideCountdownNumbers(hasOmniCC or not db.blizzardCountdown)

    -- Duration and stack text positioning
    if db.showDuration then
        self.durationtext:ClearAllPoints()
        self.durationBg:ClearAllPoints()
        
        -- Position based on durationPosition value
        if db.durationPosition == 1 then
            -- Under icon with background
            self.durationtext:SetPoint("TOP", self, "BOTTOM", db.durationSizeX, db.durationSizeY - 1)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "NORMAL")
            self.durationBg:SetPoint("CENTER", self.durationtext, 0, 0)
            self.durationBg:Show()
        elseif db.durationPosition == 2 then
            -- On icon
            self.durationtext:SetPoint("CENTER", self, "CENTER", db.durationSizeX, db.durationSizeY)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "OUTLINE")
            self.durationBg:Hide()
        elseif db.durationPosition == 3 then
            -- Above icon with background
            self.durationtext:SetPoint("BOTTOM", self, "TOP", db.durationSizeX, db.durationSizeY + 1)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "NORMAL")
            self.durationBg:SetPoint("CENTER", self.durationtext, 0, 0)
            self.durationBg:Show()
        elseif db.durationPosition == 4 then
            -- Under icon
            self.durationtext:SetPoint("TOP", self, "BOTTOM", db.durationSizeX, db.durationSizeY)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "OUTLINE")
            self.durationBg:Hide()
        elseif db.durationPosition == 5 then
            -- Above icon
            self.durationtext:SetPoint("BOTTOM", self, "TOP", db.durationSizeX, db.durationSizeY)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "OUTLINE")
            self.durationBg:Hide()
        else
            -- Default to on icon if unknown value
            self.durationtext:SetPoint("CENTER", self, "CENTER", db.durationSizeX, db.durationSizeY)
            self.durationtext:SetFont(fPB.font, (self.durationSize or db.durationSize), "OUTLINE")
            self.durationBg:Hide()
        end
        
        if not db.colorTransition then
            self.durationtext:SetTextColor(db.colorSingle[1], db.colorSingle[2], db.colorSingle[3], 1)
        end
    end

    -- Stack text coloring and positioning
    self.stacktext:SetTextColor(db.stackColor[1], db.stackColor[2], db.stackColor[3], 1)
    self.stacktext:ClearAllPoints()
    if db.stackPosition == 1 then
        -- on icon
        self.stacktext:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", db.stackSizeX * buff.scale, db.stackSizeY * buff.scale)
    elseif db.stackPosition == 2 then
        -- under icon
        self.stacktext:SetPoint("TOP", self, "BOTTOM", db.stackSizeX * buff.scale, db.stackSizeY * buff.scale)
    else
        -- above icon
        self.stacktext:SetPoint("BOTTOM", self, "TOP", db.stackSizeX * buff.scale, db.stackSizeY * buff.scale)
    end
end

local function iconOnHide(self)
	self.stacktext:Hide()
	self.border:Hide()
	self.cooldown:Hide()
	self.durationtext:Hide()
	self.durationBg:Hide()
end

local function CreateBuffIcon(frame, i, nameplateID)
    local buffIcon = CreateFrame("Frame", nil, frame)
    buffIcon:EnableMouse(false)
    buffIcon:SetWidth(db.baseWidth)
    buffIcon:SetHeight(db.baseHeight)

    -- Create texture
    buffIcon.texture = buffIcon:CreateTexture(nil, "ARTWORK")
    buffIcon.texture:SetAllPoints(buffIcon)

    -- Create border
    buffIcon.border = buffIcon:CreateTexture(nil, "OVERLAY")
    buffIcon.border:SetAllPoints(buffIcon)

    -- Create cooldown frame
    buffIcon.cooldown = CreateFrame("Cooldown", nil, buffIcon, "CooldownFrameTemplate")
    buffIcon.cooldown:SetAllPoints(buffIcon)
    buffIcon.cooldown:SetDrawEdge(false)
    buffIcon.cooldown:SetHideCountdownNumbers(true)

    -- Create stack text
    buffIcon.stacktext = buffIcon:CreateFontString(nil, "OVERLAY")
    buffIcon.stacktext:SetFont(fPB.stackFont, db.stackSize, "OUTLINE")
    buffIcon.stacktext:SetPoint("BOTTOMRIGHT", buffIcon, "BOTTOMRIGHT", 0, 0)

    -- Create duration background
    buffIcon.durationBg = buffIcon:CreateTexture(nil, "OVERLAY")
    buffIcon.durationBg:SetTexture("Interface\\AddOns\\flyPlateBuffs\\texture\\duration_bg.tga")
    buffIcon.durationBg:SetPoint("TOP", buffIcon, "BOTTOM", 0, 0)

    -- Create duration text
    buffIcon.durationtext = buffIcon:CreateFontString(nil, "OVERLAY")
    buffIcon.durationtext:SetFont(fPB.font, db.durationSize, "OUTLINE")
    buffIcon.durationtext:SetPoint("TOP", buffIcon, "BOTTOM", 0, 0)

    return buffIcon
end

local function CleanupBuffIcon(buffIcon)
    if buffIcon.masqueSet then
        if MSQ and Group then
            -- Remove from Masque and reset all Masque-related properties
            Group:RemoveButton(buffIcon)
            buffIcon.masqueData = nil
            buffIcon.masqueSet = nil
            
            -- Reset any Masque-applied textures/points
            if buffIcon.texture then
                buffIcon.texture:SetTexCoord(0, 1, 0, 1)
                buffIcon.texture:ClearAllPoints()
                buffIcon.texture:SetAllPoints(buffIcon)
            end
            
            -- Hide the border explicitly
            if buffIcon.border then
                buffIcon.border:Hide()
            end
        end
    end
    
    -- Reset other icon properties
    if buffIcon.texture then buffIcon.texture:SetVertexColor(1, 1, 1) end
    if buffIcon.stacktext then buffIcon.stacktext:Hide() end
    if buffIcon.cooldown then buffIcon.cooldown:Hide() end
    if buffIcon.durationtext then buffIcon.durationtext:Hide() end
    if buffIcon.durationBg then buffIcon.durationBg:Hide() end
end

-- Function to handle Masque group changes
local function HandleMasqueGroupChanged(addon, group, skinId, gloss, backdrop, colors, disabled)
    if disabled then
        -- Masque is disabled, clean up all icons
        if PlatesBuffs then
            for frame, buffs in pairs(PlatesBuffs) do
                if frame.fPBiconsFrame and frame.fPBiconsFrame.iconsFrame then
                    for _, icon in pairs(frame.fPBiconsFrame.iconsFrame) do
                        CleanupBuffIcon(icon)
                    end
                end
            end
        end
    end
    
    -- Update all nameplates to reflect the Masque changes
    UpdateAllNameplates(true)
end

-- Register Masque callback
if MSQ then
    Group = MSQ:Group(AddonName)
    MSQ:Register(AddonName, HandleMasqueGroupChanged)
end

local function UpdateUnitAuras(nameplateID, updateOptions)
    -- Check for nil nameplateID
    if not nameplateID then
        if fPB.debug.enabled then
            DebugLog("events", "UpdateUnitAuras called with nil nameplateID")
        end
        return
    end
    
    -- Apply throttling
    local currentTime = GetTime()
    local unitThrottleKey = tostring(nameplateID)
    
    -- Skip update if this unit was updated too recently (unless forced by updateOptions)
    if not updateOptions and lastUnitUpdateTimes[unitThrottleKey] and 
       (currentTime - lastUnitUpdateTimes[unitThrottleKey] < THROTTLE_INTERVAL) then
        if fPB.debug.enabled then
            fPB.debug.skippedUpdates = fPB.debug.skippedUpdates + 1
            DebugLog("events", "Skipped update for %s (throttled)", unitThrottleKey)
        end
        return
    end
    
    -- Update the last update time for this unit
    lastUnitUpdateTimes[unitThrottleKey] = currentTime
    
    if fPB.debug.enabled then
        fPB.debug.updateCounts = fPB.debug.updateCounts + 1
        TrackMemory("BeforeUnitUpdate")
    end
    
    -- Wrap the entire function in performance tracking
    local function processUnitAuras()
	local frame = C_NamePlate_GetNamePlateForUnit(nameplateID)

	if frame then
		frame.TPFrame  = _G["ThreatPlatesFrame" .. frame:GetName()]
		frame.unitFrame   = _G[frame:GetName().."PlaterUnitFrame"]
		if frame.TPFrame then frame = frame.TPFrame end
		if frame.unitFrame then frame = frame.unitFrame end
	end

        if not frame then 
            DebugLog("events", "No valid frame for %s", nameplateID)
            return 
        end
        
	if FilterUnits(nameplateID) then
		if frame.fPBiconsFrame then
			frame.fPBiconsFrame:Hide()
		end
            DebugLog("events", "Unit %s filtered out", UnitName(nameplateID) or nameplateID)
		return
	end

        DebugLog("events", "Processing auras for %s", UnitName(nameplateID) or nameplateID)
        
        if fPB.debug.enabled and fPB.debug.performance then
            -- Don't override the original function, just call it through TrackPerformance
            TrackPerformance("ScanUnitBuffs", ScanUnitBuffs, nameplateID, frame)
        else
	ScanUnitBuffs(nameplateID, frame)
        end
        
        -- ADDS CLEU FOUND BUFFS
	if not PlatesBuffs[frame] then
		if Interrupted[UnitGUID(nameplateID)] then
			for i = 1, #Interrupted[UnitGUID(nameplateID)] do
				if not PlatesBuffs[frame] then PlatesBuffs[frame] = {} end
				PlatesBuffs[frame][i] = Interrupted[UnitGUID(nameplateID)][i]
			end
                DebugLog("events", "Added %d CLEU buffs to %s", 
                    #Interrupted[UnitGUID(nameplateID)], UnitName(nameplateID) or nameplateID)
		end
	else
		if Interrupted[UnitGUID(nameplateID)]  then
                local prevCount = #PlatesBuffs[frame]
			for i = 1, #Interrupted[UnitGUID(nameplateID)] do
				PlatesBuffs[frame][#PlatesBuffs[frame] + 1] = Interrupted[UnitGUID(nameplateID)][i]
			end
                DebugLog("events", "Added %d CLEU buffs to %s (now %d total)", 
                    #Interrupted[UnitGUID(nameplateID)], UnitName(nameplateID) or nameplateID,
                    #PlatesBuffs[frame])
	  end
	end
        
	if not PlatesBuffs[frame] then
		if frame.fPBiconsFrame then
			frame.fPBiconsFrame:Hide()
		end
		return
	end
        
	if not db.disableSort then
    -- Use optimized sorting if enabled
    if db.optimizedSorting then
        -- Only track stats if debugging is enabled
        if fPB.debug.enabled then
            fPB.sortStats.totalSorts = (fPB.sortStats.totalSorts or 0) + 1
        end
        
        if NeedsSorting[frame] or HasBuffsChanged(frame, PlatesBuffs[frame]) then
            -- Debug message for sorting
            DebugLog("events", "Sorting buffs for %s (cache miss or changes detected)", UnitName(nameplateID) or "unknown")
            
            -- Count cache misses is already done in HasBuffsChanged
            
            -- Sort the buffs
            table_sort(PlatesBuffs[frame], SortFunc)
            
            -- Cache the current state
            CacheBuffsState(frame, PlatesBuffs[frame])
        else
            -- CACHE HIT: We're reusing previous sort order
            -- The cache hit counter is already incremented in HasBuffsChanged
            
            -- Only print to chat if cache messages are enabled (either via debug or the standalone setting)
            if db.showCacheHitMessages == true or 
               (db.showCacheHitMessages ~= false and fPB.debug.enabled and fPB.debug.cacheMessages) then
                print("|cFF00FF00[FPB-Cache Hit]|r Using cached sort for " .. (UnitName(nameplateID) or "unknown") .. 
                      " (total hits: " .. fPB.sortStats.cacheHits .. "/" .. fPB.sortStats.totalSorts .. ")")
            end
            
            DebugLog("events", "CACHE HIT: Using cached sort for %s (no significant changes)", UnitName(nameplateID) or "unknown")
        end
    else
        -- Always sort if optimization is disabled
        table_sort(PlatesBuffs[frame], SortFunc)
    end
	end

	if not frame.fPBiconsFrame then
		-- if parent == frame then it will change scale and alpha with nameplates
		-- otherwise use UIParent, but this causes mess of icon/border textures
		frame.fPBiconsFrame = CreateFrame("Frame")
		local parent = db.parentWorldFrame and WorldFrame
		if not parent then
			parent = frame.TPFrame -- for ThreatPlates
		end
		if not parent then
			parent = frame.unitFrame -- for Plater
		end
		if not parent then
			parent = frame
		end
		anchor = "ThreatPlatesFrame"..nameplateID -- for ThreatPlates
		anchor = nameplateID.."PlaterUnitFrame" -- for Plater
		frame.fPBiconsFrame:SetParent(parent)
            DebugLog("events", "Created new icons frame for %s", UnitName(nameplateID) or nameplateID)
	end
        
	if not frame.fPBiconsFrame.iconsFrame then
		frame.fPBiconsFrame.iconsFrame = {}
	end

        local buffsCount = #PlatesBuffs[frame]
        DebugLog("events", "Processing %d buffs for %s", buffsCount, UnitName(nameplateID) or nameplateID)

        -- Apply maximum auras limit based on maxBuffsPerPlate
        local maxAuras = buffsCount
        local maxBuffsAllowed = db.maxBuffsPerPlate or (db.buffPerLine * db.numLines)
        
        -- Always limit the number of auras processed for performance
        maxAuras = math.min(buffsCount, maxBuffsAllowed)
        if buffsCount > maxAuras then
            DebugLog("events", "Limiting visible auras from %d to %d for %s",
                buffsCount, maxAuras, UnitName(nameplateID) or nameplateID)
        end

        for i = 1, maxAuras do
		if not frame.fPBiconsFrame.iconsFrame[i] then
                CreateBuffIcon(frame, i, nameplateID)
		end

		local buff = PlatesBuffs[frame][i]
		local buffIcon = frame.fPBiconsFrame.iconsFrame[i]
		buffIcon.type = buff.type
		buffIcon.icon = buff.icon
		buffIcon.stack = buff.stack
		buffIcon.debufftype = buff.debufftype
		buffIcon.duration = buff.duration
		buffIcon.expiration = buff.expiration
		buffIcon.id = buff.id
		buffIcon.durationSize = buff.durationSize
		buffIcon.stackSize = buff.stackSize
		buffIcon.width = db.baseWidth * buff.scale
		buffIcon.height = db.baseHeight * buff.scale
		buffIcon.EnemyBuff = buff.EnemyBuff
		buffIcon.spellId = buff.spellId
		buffIcon.scale = buff.scale
		buffIcon.glow = buff.glow

		if updateOptions then
			UpdateBuffIconOptions(buffIcon, buff)
		end
		UpdateBuffIcon(buffIcon, buff)

            -- Glow
            if buffIcon.glow then
			ActionButton_ShowOverlayGlow(buffIcon, buff.scale)
		else
			ActionButton_HideOverlayGlow(buffIcon)
		end

		buffIcon:Show()
	end
        
	frame.fPBiconsFrame:Show()

        if #frame.fPBiconsFrame.iconsFrame > maxAuras then
            for i = maxAuras + 1, #frame.fPBiconsFrame.iconsFrame do
			if frame.fPBiconsFrame.iconsFrame[i] then
				frame.fPBiconsFrame.iconsFrame[i]:Hide()
				ActionButton_HideOverlayGlow(frame.fPBiconsFrame.iconsFrame[i])
			end
		end
	end

	DrawOnPlate(frame)
        
        if fPB.debug.enabled then
            TrackMemory("AfterUnitUpdate")
        end
    end
    
    if fPB.debug.enabled and fPB.debug.performance then
        TrackPerformance("UpdateUnitAuras:" .. (UnitName(nameplateID) or nameplateID), processUnitAuras)
    else
        processUnitAuras()
    end
end

-- Add settings for limited scanning
local pendingNameplates = {}      -- Queue of nameplates waiting to be processed
local isProcessingQueue = false   -- Flag to track if we're in the middle of processing the queue

function fPB.UpdateAllNameplates(updateOptions)
    -- Apply throttling to global updates
    local currentTime = GetTime()
    
    -- Skip update if a global update happened too recently (unless forced by updateOptions)
    if not updateOptions and (currentTime - lastUpdateTime < THROTTLE_INTERVAL) then
        if fPB.debug.enabled then
            fPB.debug.skippedUpdates = fPB.debug.skippedUpdates + 1
            DebugLog("events", "Skipped global update (throttled)")
        end
        return
    end
    
    -- Update the last global update time
    lastUpdateTime = currentTime
    
    -- Get all nameplates
    local nameplates = C_NamePlate_GetNamePlates()
    local plateCount = #nameplates
    
    -- Debug status check
    if fPB.debug.enabled then
        print("|cFF00FFFF[FPB-Debug]|r UpdateAllNameplates called with " .. plateCount .. " nameplates, limitedScanning: " .. (db.limitedScanning and "ON" or "OFF") .. ", force: " .. (updateOptions and "YES" or "NO"))
    end
    
    -- Always immediate update mode if forced or limited scanning is off
    if updateOptions or not db.limitedScanning then
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r Processing all nameplates immediately")
            TrackMemory("BeforeAllPlatesUpdate")
        end
        
        -- Process all nameplates immediately
        for i, p in ipairs(nameplates) do
		local unit = p.namePlateUnitToken
		if not unit then --try ElvUI
			unit = p.unitFrame and p.unitFrame.unit
		end
		if unit then
                UpdateUnitAuras(unit, updateOptions)
            else
                DebugLog("events", "No valid unit for nameplate at index %d", i)
		end
	end
        
        if fPB.debug.enabled then
            TrackMemory("AfterAllPlatesUpdate")
        end
        return
    end
    
    -- Limited scanning mode - queue nameplates for batch processing
    if fPB.debug.enabled then
        print("|cFF00FFFF[FPB-Debug]|r Queueing " .. plateCount .. " nameplates for batch processing")
    end
    
    -- Clear the pending queue and add all current nameplates
    wipe(pendingNameplates)
    for i, p in ipairs(nameplates) do
        local unit = p.namePlateUnitToken
        if not unit then --try ElvUI
            unit = p.unitFrame and p.unitFrame.unit
        end
        if unit then
            tinsert(pendingNameplates, unit)
        end
    end
    
    -- Start processing the queue if not already doing so
    if not isProcessingQueue then
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r Starting nameplate queue processing")
        end
        isProcessingQueue = true
        C_Timer.After(0, fPB.ProcessNameplateQueue)
    else
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r Queue processing already in progress, added " .. plateCount .. " nameplates")
        end
    end
end

-- New function to process the nameplate queue over multiple frames
function fPB.ProcessNameplateQueue()
    local plateCount = #pendingNameplates
    
    if plateCount == 0 then
        -- Queue is empty, we're done
        isProcessingQueue = false
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r Nameplate queue empty, processing complete")
        end
        return
    end
    
    -- Process a limited number of nameplates using the value from settings
    local processCount = math.min(db.maxPlatesPerUpdate or 3, plateCount)
    if fPB.debug.enabled then
        print("|cFF00FFFF[FPB-Debug]|r Processing batch: " .. processCount .. "/" .. plateCount .. " queued nameplates")
    end
    
    if fPB.debug.enabled then
        TrackMemory("BeforeBatchUpdate")
    end
    
    -- Process the first few nameplates
    for i = 1, processCount do
        if pendingNameplates[1] then
            local unit = pendingNameplates[1]
            if unit and UnitExists(unit) then
                if fPB.debug.enabled then
                    print("|cFF00FFFF[FPB-Debug]|r Processing nameplate: " .. (UnitName(unit) or "Unknown"))
                end
                UpdateUnitAuras(unit, false)  -- false = not a forced update
            end
            tremove(pendingNameplates, 1)  -- Remove the processed nameplate
        end
    end
    
    if fPB.debug.enabled then
        TrackMemory("AfterBatchUpdate")
    end
    
    -- Schedule the next batch
    local remainingCount = #pendingNameplates
    if remainingCount > 0 then
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r Scheduling next batch, " .. remainingCount .. " nameplates remaining")
        end
        C_Timer.After(0.01, fPB.ProcessNameplateQueue)  -- Small delay between batches
    else
        isProcessingQueue = false
        if fPB.debug.enabled then
            print("|cFF00FFFF[FPB-Debug]|r All nameplates processed")
        end
    end
end

local function Nameplate_Added(...)
	local nameplateID = ...
    
    -- Check for nil nameplateID
    if not nameplateID then
        if fPB.debug.enabled then
            DebugLog("events", "Nameplate_Added called with nil nameplateID")
        end
        return
    end
    
	local frame = C_NamePlate_GetNamePlateForUnit(nameplateID)
    if not frame then
        if fPB.debug.enabled then
            DebugLog("events", "Nameplate_Added: No frame found for %s", tostring(nameplateID))
        end
        return
    end
    
	local guid = UnitGUID(nameplateID)
    if not guid then
        if fPB.debug.enabled then
            DebugLog("events", "Nameplate_Added: No GUID for %s", tostring(nameplateID))
        end
        return
    end

	--disable blizzard Auras on nameplates
	local Blizzardframe = frame.UnitFrame
    if Blizzardframe:IsForbidden() then return end
	Blizzardframe.BuffFrame:ClearAllPoints()
	Blizzardframe.BuffFrame:SetAlpha(0)

	local unitType, _, _, _, _, ID, spawnUID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" then --and UnitIsEnemy("player" , nameplateID) then --or unitType == "Pet"  then
		local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
        local spawnEpochOffset = bit.band(tonumber(substring(spawnUID, 5), 16), 0x7fffff)
		local spawnTime = spawnEpoch + spawnEpochOffset
		local nameCreature = UnitName(nameplateID)
		local type,  debufftype
		if UnitIsEnemy("player" , nameplateID) then 
			type = "HARMFUL"
			debufftype = "none"
		else
			type = "HELPFUL"
			debufftype = "Buff"
		end
		local duration, expiration, icon, scale, tracked, seen, glow
		local stack = 0
		-- Magic = {0.20,0.60,1.00},	Curse = {0.60,0.00,1.00} Disease = {0.60,0.40,0}, Poison= {0.00,0.60,0}, none = {0.80,0,   0}, Buff = {0.00,1.00,0},
		--if unitType == "Creature" or unitType == "Vehicle" then scale = 1.3 elseif unitType =="Pet" then scale = 1.1 end
		local durationSize 
		local stackSize 
		local id = 1 --Need to figure this out
		local upTime = tonumber((GetServerTime() % 2^23) - (spawnTime % 2^23))
		--print(nameCreature.." "..unitType..":"..ID.." alive for: "..((GetServerTime() % 2^23) - (spawnTime % 2^23)))

		local Spells = db.Spells
		local listedSpell


		if Spells[ID] and not db.ignoredDefaultSpells[ID] then
			listedSpell = Spells[ID]
		elseif Spells[nameCreature] and not db.ignoredDefaultSpells[ID] then
			listedSpell = Spells[nameCreature]
		end

		if listedSpell and listedSpell.spellTypeNPC then
			scale = listedSpell.scale  or 1
			durationSize = listedSpell.durationSize or 13
			stackSize = listedSpell.stackSize or 10
			icon = listedSpell.spellId or 134400
			duration = listedSpell.durationCLEU or 0
			glow = listedSpell.IconGlow
		else 
			
		end

		if icon then
			expiration = GetTime() + (duration - upTime)
			if not Interrupted[guid] then
				Interrupted[guid] = {}
			end
			if Interrupted[guid] then
				for k, v in pairs(Interrupted[guid]) do
					if v.ID then
						seen = true
						break
					end
				end
			end
			if not seen then
				if duration == 0 then --Permanent
					expiration = 0;	duration = 0
				end
				--print(nameCreature.." "..unitType..":"..ID.." alive for: "..upTime)
				local tablespot = #Interrupted[guid] + 1
				tblinsert (Interrupted[guid], tablespot, { type = type, icon = icon, stack = stack, debufftype = debufftype,duration = duration, expiration = expiration, scale = scale, durationSize = durationSize, stackSize = stackSize, id = id, glow = glow, ["ID"] = ID})
				if duration ~= 0 and duration - (GetServerTime() - spawnTime) > 0 then
					Ctimer(duration - (GetServerTime() - spawnTime) , function()
						if Interrupted[guid] then
							Interrupted[guid][tablespot] = nil
							fPB.UpdateAllNameplates()
						end
					end)
				else
					frame.fPBtimer = C_Timer.NewTicker(1, function()
						local unitToken = UnitTokenFromGUID(guid)
						if not unitToken then
							if Interrupted[guid] then
								Interrupted[guid][tablespot] = nil
								fPB.UpdateAllNameplates()
							end
							frame.fPBtimer:Cancel()
						end
					end)
				end
			end
		end
	end
	UpdateUnitAuras(nameplateID)
end

local function Nameplate_Removed(...)
	local nameplateID = ...
    
    -- Check for nil nameplateID
    if not nameplateID then
        if fPB.debug.enabled then
            DebugLog("events", "Nameplate_Removed called with nil nameplateID")
        end
        return
    end
    
    -- Clean up throttling data for this nameplate
    local unitThrottleKey = tostring(nameplateID)
    lastUnitUpdateTimes[unitThrottleKey] = nil
    
    local frame = C_NamePlate_GetNamePlateForUnit(nameplateID)
    if not frame then return end
	if frame.fPBiconsFrame then
		frame.fPBiconsFrame:Hide()
	end
	if PlatesBuffs[frame] then
		PlatesBuffs[frame] = nil
	end
    
    -- Clear sort cache for this frame
    ClearFrameSortCache(frame)
end

local function FixSpells()
	for spell,s in pairs(db.Spells) do
		if not s.name then
			local name
			local spellId = tonumber(spell) and tonumber(spell) or spell.spellId
			if spellId then
				name = GetSpellInfo(spellId)
			else
				name = tostring(spell)
			end
			db.Spells[spell].name = name
		end
	end
end

function fPB.CacheSpells() -- spells filtered by names, not checking id
	cachedSpells = {}
	for spell,s in pairs(db.Spells) do
		if not s.checkID and not db.ignoredDefaultSpells[spell] and s.name then
			if s.spellId then
				cachedSpells[s.name] = s.spellId
			else
				cachedSpells[s.name] = "noid"
			end
		end
	end
end
local CacheSpells = fPB.CacheSpells

function fPB.AddNewSpell(spell, npc)
	local defaultSpell, name
	if db.ignoredDefaultSpells[spell] then
		db.ignoredDefaultSpells[spell] = nil
		defaultSpell = true
	end
	local spellId = tonumber(spell)
	if db.Spells[spell] and not defaultSpell then
		if spellId then
			DEFAULT_CHAT_FRAME:AddMessage(chatColor..L["Spell with this ID is already in the list. Its name is "]..linkColor.."|Hspell:"..spellId.."|h["..GetSpellInfo(spellId).."]|h|r")
			return
		else
			DEFAULT_CHAT_FRAME:AddMessage(spell..chatColor..L[" already in the list."].."|r")
			return
		end
	end

	if not npc then
		name = GetSpellInfo(spellId)
	end
	if spellId and name then
		if not db.Spells[spellId] then
			db.Spells[spellId] = {
				show = 1,
				name = name,
				spellId = spellId,
				scale = 1,
				stackSize = db.stackSize,
				durationSize = db.durationSize,
			}
		end
	elseif npc then
		print("fPB Added NPC: "..spell)
		db.Spells[spell] = {
			show = 1,
			name = spell,
			scale = 1,
			stackSize = db.stackSize,
			durationSize = db.durationSize,
			spellTypeNPC = true,
		}
	else
		db.Spells[spell] = {
			show = 1,
			name = spell,
			scale = 1,
			stackSize = db.stackSize,
			durationSize = db.durationSize,
		}
	end
	CacheSpells()
	if not npc then
		fPB.BuildSpellList()
	else
		fPB.BuildNPCList()
	end
	UpdateAllNameplates(true)
end
function fPB.RemoveSpell(spell)
	if DefaultSettings.profile.Spells[spell] then
		db.ignoredDefaultSpells[spell] = true
	end
	db.Spells[spell] = nil
	CacheSpells()
	fPB.BuildSpellList()
	fPB.BuildNPCList()
	UpdateAllNameplates(true)
end
function fPB.ChangespellId(oldID, newID, npc)
	if db.Spells[newID] then
		DEFAULT_CHAT_FRAME:AddMessage(chatColor..L["Spell with this ID is already in the list. Its name is "]..linkColor.."|Hspell:"..newID.."|h["..GetSpellInfo(newID).."]|h|r")
		return
	end
	db.Spells[newID] = {}
	for k,v in pairs(db.Spells[oldID]) do
		db.Spells[newID][k] = v
		db.Spells[newID].spellId = newID
	end
	fPB.RemoveSpell(oldID)
	DEFAULT_CHAT_FRAME:AddMessage(GetSpellInfo(newID)..chatColor..L[" ID changed "].."|r"..(tonumber(oldID) or "nil")..chatColor.." -> |r"..newID)
	UpdateAllNameplates(true)
	fPB.BuildSpellList()
end

local function ConvertDBto2()
	local temp
	for _,p in pairs(flyPlateBuffsDB.profiles) do
		if p.Spells then
			temp = {}
			for n,s in pairs(p.Spells) do
				local spellId = s.spellId
				if not spellId then
					for i=1, #defaultSpells1 do
						if n == GetSpellInfo(defaultSpells1[i]) then
							spellId = defaultSpells1[i]
							break
						end
					end
				end
				if not spellId then
					for i=1, #defaultSpells2 do
						if n == GetSpellInfo(defaultSpells2[i]) then
							spellId = defaultSpells2[i]
							break
						end
					end
				end
				local spell = spellId and spellId or n
				if spell then
					temp[spell] = {}
					for k,v in pairs(s) do
						temp[spell][k] = v
					end
					temp[spell].name = GetSpellInfo(spellId) and GetSpellInfo(spellId) or n
				end
			end
			p.Spells = temp
			temp = nil
		end
		if p.ignoredDefaultSpells then
			temp = {}
			for n,v in pairs(p.ignoredDefaultSpells) do
				local spellId
				for i=1, #defaultSpells1 do
					if n == GetSpellInfo(defaultSpells1[i]) then
						spellId = defaultSpells1[i]
						break
					end
				end
				if not spellId then
					for i=1, #defaultSpells2 do
						if n == GetSpellInfo(defaultSpells2[i]) then
							spellId = defaultSpells2[i]
							break
						end
					end
				end
				if spellId then
					temp[spellId] = true
				end
			end
			p.ignoredDefaultSpells = temp
			temp = nil
		end
	end
	flyPlateBuffsDB.version = 2
end
function fPB.OnProfileChanged()
	db = fPB.db.profile
	fPB.OptionsOnEnable()
	UpdateAllNameplates(true)
end
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

	config:RegisterOptionsTable(AddonName.." Options", fPB.OptionsOpen)
	fPBMainOptions = dialog:AddToBlizOptions(AddonName.." Options", AddonName)

	-- Make sure the main options table exists before registering it
	if type(fPB.MainOptionTable) == "table" then
		config:RegisterOptionsTable(AddonName, fPB.MainOptionTable)
		
		-- Initialize profile options
		if fPB.InitializeProfileOptions then
			fPB.InitializeProfileOptions()
		end
	else
		print("|cFFFF0000[FlyPlateBuffs]|r Error: Main options table not defined. Options interface may not work correctly.")
	end

	config:RegisterOptionsTable(AddonName.." Spells", fPB.SpellsTable)
	--fPBSpellsList = dialog:AddToBlizOptions(AddonName.." Spells", L["Specific spells"], AddonName)

	-- Register the profile options separately
	local profilesOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(fPB.db)
	config:RegisterOptionsTable(AddonName.." Profiles", profilesOptions)
	fPBProfilesOptions = dialog:AddToBlizOptions(AddonName.." Profiles", L["Profiles"], AddonName)

    -- Initialize debug stats tracking
    fPB.debug.startTime = GetTime()
    fPB.debug.updateCounts = 0
    fPB.debug.skippedUpdates = 0
    
    -- Initialize table pool
    fPB.tablePool = fPB.tablePool or {}
    wipe(fPB.tablePool) -- Start fresh
    PrePopulatePool(50) -- Pre-populate with 50 tables
    
    -- Register slash commands
	SLASH_FLYPLATEBUFFS1, SLASH_FLYPLATEBUFFS2 = "/fpb", "/pb"
	function SlashCmdList.FLYPLATEBUFFS(msg, editBox)
        -- Check for debug commands first
        if msg == "debug" then
            fPB.debug.enabled = not fPB.debug.enabled
            fPB.Print(format("Debugging is now %s.", fPB.debug.enabled and "enabled" or "disabled"))
            return
        elseif msg == "stats" then
            fPB.ShowDebugStats()
            return
        elseif msg == "resetstats" then
            fPB.debug.updateCounts = 0
            fPB.debug.skippedUpdates = 0
            fPB.debug.startTime = GetTime()
            fPB.debug.functionTimes = {}
            fPB.debug.memoryUsage = {}
            fPB.debug.logEntries = {}
            ResetTableRecyclingStats()
            ResetSortStats()
            fPB.Print("Debug statistics reset.")
            return
        elseif msg == "recycle" then
            ResetTableRecyclingStats()
            return
        elseif msg == "auras" then
            -- Toggle aura tracking
            fPB.debug.auraTracking = not fPB.debug.auraTracking
            fPB.Print(format("Aura change tracking is now %s.", fPB.debug.auraTracking and "enabled" or "disabled"))
            return
        elseif msg == "sortstats" then
            -- Only show sort optimization stats
            if fPB.db and fPB.db.profile and fPB.db.profile.optimizedSorting then
                -- Initialize sortStats if needed
                if not fPB.sortStats then
                    fPB.sortStats = {
                        totalSorts = 0,
                        cacheMisses = 0,
                        cacheHits = 0,
                        lastReset = GetTime()
                    }
                end
                
                local timeRunning = GetTime() - fPB.sortStats.lastReset
                local hitRate = fPB.sortStats.totalSorts > 0 and (fPB.sortStats.cacheHits / fPB.sortStats.totalSorts) * 100 or 0
                
                print("|cFFFFCC00Sort Optimization:|r")
                print(string.format("  Total sorts: %d", fPB.sortStats.totalSorts))
                print(string.format("  Cache hits: %d (%.1f%%)", fPB.sortStats.cacheHits, hitRate))
                print(string.format("  Cache misses: %d", fPB.sortStats.cacheMisses))
                if timeRunning > 0 then
                    print(string.format("  Sorts per second: %.2f", fPB.sortStats.totalSorts / timeRunning))
                end
            else
                fPB.Print("Optimized sorting is disabled")
            end
            return
        elseif msg == "resetsort" then
            ResetSortStats()
            if fPB.wipeAllSortCaches then
                fPB.wipeAllSortCaches()
            end
            return
        elseif msg == "help" or msg == "?" then
            -- Display available commands
            fPB.Print("Available commands:")
            fPB.Print("  /fpb or /pb - Open options panel")
            fPB.Print("  /fpb debug - Toggle debugging")
            fPB.Print("  /fpb stats - Show debug statistics")
            fPB.Print("  /fpb resetstats - Reset debug statistics")
            fPB.Print("  /fpb recycle - Reset table recycling statistics")
            fPB.Print("  /fpb auras - Toggle aura change tracking")
            fPB.Print("  /fpb sortstats - Show sort optimization statistics")
            fPB.Print("  /fpb resetsort - Reset sort statistics and wipe caches")
            fPB.Print("  /fpb fill [count] - Pre-populate pool with tables")
            fPB.Print("  /fpb help or ? - Show this help message")
            return
        elseif msg:match("^fill%s*(%d*)$") then
            local count = tonumber(msg:match("^fill%s*(%d*)$")) or 100
            PrePopulatePool(count)
            return
        end
        
        -- Default behavior - open options
		dialog:Open(AddonName)
	end
end

function fPB.RegisterCombat()
	fPB.Events:RegisterEvent("PLAYER_REGEN_DISABLED")
	fPB.Events:RegisterEvent("PLAYER_REGEN_ENABLED")
end
function fPB.UnregisterCombat()
	fPB.Events:UnregisterEvent("PLAYER_REGEN_DISABLED")
	fPB.Events:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

fPB.Events = CreateFrame("Frame")
fPB.Events:RegisterEvent("ADDON_LOADED")
fPB.Events:RegisterEvent("PLAYER_LOGIN")

fPB.Events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" and (...) == AddonName then
		Initialize()
	elseif event == "PLAYER_LOGIN" then
		-- Check if the function exists before calling it
		if type(fPB.OptionsOnEnable) == "function" then
			fPB.OptionsOnEnable()
		else
			print(Color("FlyPlateBuffs", "ADDON_NAME") .. ": " .. Color("Error: Options module not loaded properly. Using default settings.", "ERROR"))
			db = fPB.db.profile
		end
		
		-- Use direct print with formatted message
		print(Color("FlyPlateBuffs", "ADDON_NAME") .. ": " .. format("Type %s or %s to open the options panel. Type %s for available commands.", 
			Colorize("/fPB", "accent"), 
			Colorize("/pb", "accent"), 
			Colorize("/fpb help", "accent")))
		
		if db.blizzardCountdown then
			SetCVar("countdownForCooldowns", 1)
		end
		MSQ = LibStub("Masque", true)
		if MSQ then
			Group = MSQ:Group(AddonName)
			MSQ:Register(AddonName, function(addon, group, skinId, gloss, backdrop, colors, disabled)
				if disabled then
					UpdateAllNameplates(true)
				end
			end)
		end

		fPB.Events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		fPB.Events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		fPB.Events:RegisterEvent("UNIT_AURA")
		fPB.Events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	elseif event == "PLAYER_REGEN_DISABLED" then
		fPB.Events:RegisterEvent("UNIT_AURA")
		UpdateAllNameplates()
	elseif event == "PLAYER_REGEN_ENABLED" then
		fPB.Events:UnregisterEvent("UNIT_AURA")
		UpdateAllNameplates()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Nameplate_Added(...)
        -- Update nameplate count for dynamic throttling
        if fPB.debug.enabled and fPB.debug.dynamicThrottlingEnabled then
            fPB.UpdateNameplateCount()
        end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		Nameplate_Removed(...)
        -- Update nameplate count for dynamic throttling
        if fPB.debug.enabled and fPB.debug.dynamicThrottlingEnabled then
            fPB.UpdateNameplateCount()
        end
	elseif event == "UNIT_AURA" then
		if strmatch((...),"nameplate%d+") then
			UpdateUnitAuras(...)
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		fPB:CLEU()
	end
end)

-- Function to check if pvp talents are active for the player
local function ArePvpTalentsActive()
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "pvp" or instanceType == "arena") then
        return true
    elseif inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario") then
        return false
    else
        local talents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
        for _, pvptalent in pairs(talents) do
            local spellID = select(6, GetPvpTalentInfoByID(pvptalent))
            if IsPlayerSpell(spellID) then
                return true
            end
        end
    end
end

local function interruptDuration(destGUID, duration)
	local unit
	for i, p in ipairs(C_NamePlate_GetNamePlates()) do
		unit = p.namePlateUnitToken
		if (destGUID == UnitGUID(unit)) then
			break
		end
	end
    
    if not unit then return duration end
    
		local duration3 = duration
		local shamTranquilAirBuff = false
		local _, destClass = GetPlayerInfoByGUID(destGUID)
		
    local auras = fPB.GetUnitAuras(unit)
    if not auras then return duration end
    
    -- Check buffs
    for i = 1, #auras.buffs do
        local aura = auras.buffs[i]
		local _, _, _, _, _, _, _, _, _, auxSpellId = UnpackAuraData(aura)
		if (destClass == "DRUID") then
            if auxSpellId == 234084 then -- Moon and Stars (Druid)
					duration = duration * 0.5
				end
			end
        if auxSpellId == 317920 then     -- Concentration Aura
				duration = duration * 0.7
        elseif auxSpellId == 383020 then -- Tranquil Air
				shamTranquilAirBuff = true
			end
		end
    
    -- Check debuffs
    for i = 1, #auras.debuffs do
        local aura = auras.debuffs[i]
			local _, _, _, _, _, _, _, _, _, auxSpellId = UnpackAuraData(aura)
        if auxSpellId == 372048 then -- Oppressing Roar
				if ArePvpTalentsActive() then
					duration = duration * 1.3
					duration3 = duration3 * 1.3
				else
					duration = duration * 1.5
					duration3 = duration3 * 1.5
				end
			end
		end
    
    -- Release the aura tables
    auras:Release()
    
    if shamTranquilAirBuff then
			duration3 = duration3 * 0.5
        if duration3 < duration then
				duration = duration3
			end
		end
    
	return duration
end


local function ObjectDNE(guid) --Used for Infrnals and Ele
	local tooltipData =  C_TooltipInfo.GetHyperlink('unit:' .. guid or '')

	if #tooltipData.lines == 1 then -- Fel Obelisk
		return "Despawned"
	end

	for i = 1, #tooltipData.lines do 
		local text = tooltipData.lines[i].leftText
		if text and (type(text == "string")) then
			--print(i.." "..text)
			if strfind(text, "Level ??") or strfind(text, "Corpse") then 
				return "Despawned"
			end
		end
	end
end


function fPB:CLEU()
	local _, event, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellId, _, _, _, _, spellSchool = CombatLogGetCurrentEventInfo()
    -------------------------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------------------------------
    ----------------------------------------------------------------------------------------------
	--CLEU Deuff Timer
    ----------------------------------------------------------------------------------------------
	
	-----------------------------------------------------------------------------------------------------------------
	--SmokeBomb Check
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_CAST_SUCCESS") and (spellId == 212182 or spellId == 359053)) then
		if (sourceGUID ~= nil) then
			local duration = 5
			local expiration = GetTime() + duration
			if (SmokeBombAuras[sourceGUID] == nil) then
				SmokeBombAuras[sourceGUID] = {}
			end
			SmokeBombAuras[sourceGUID] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + 1, function()	-- execute in some close next frame to accurate use of UnitAura function
				SmokeBombAuras[sourceGUID] = nil
				fPB.UpdateAllNameplates()
			end)
		end
	end
		
	--------------------------------------------------------------------------------------------------------------------------------------------------------------
	--CLEU Buff Timer
	--------------------------------------------------------------------------------------------------------------------------------------------------------------

	-----------------------------------------------------------------------------------------------------------------
	--Barrier Check
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_CAST_SUCCESS") and (spellId == 62618)) then
		if (sourceGUID ~= nil) then
			local duration = 10
			local expiration = GetTime() + duration
			if (Barrier[sourceGUID] == nil) then
				Barrier[sourceGUID] = {}
			end
			Barrier[sourceGUID] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + 1, function()	-- execute iKn some close next frame to accurate use of UnitAura function
				Barrier[sourceGUID] = nil
			end)
			Ctimer(.2, function()	-- execute a second timer to ensure it catches
				UpdateAllNameplates()
			end)
		end
		UpdateAllNameplates()
	end

	-----------------------------------------------------------------------------------------------------------------
	--SGrounds Check
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_CAST_SUCCESS") and (spellId == 34861)) then
		if (sourceGUID ~= nil) then
			local duration = 5
			local expiration = GetTime() + duration
			if (SGrounds[sourceGUID] == nil) then
				SGrounds[sourceGUID] = {}
			end
			SGrounds[sourceGUID] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + 1, function()	-- execute iKn some close next frame to accurate use of UnitAura function
				SGrounds[sourceGUID] = nil
			end)
			Ctimer(.2, function()	-- execute a second timer to ensure it catches
				fPB.UpdateAllNameplates()
			end)
		end
		fPB.UpdateAllNameplates()
	end

	-----------------------------------------------------------------------------------------------------------------
	--Earthen Check (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_SUMMON") or (event == "SPELL_CREATE")) and (spellId == 198838) then
		if (destGUID ~= nil) then
			local duration = 18 --Totemic Focus Makes it 18
			local guid = destGUID
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("Earthen Totem Spawned at: "..spawnTime)
			end
			local expiration = GetTime() + duration
			if (Earthen[spawnTime] == nil) then --source becomes the totem ><
				Earthen[spawnTime] = {}
			end
			Earthen[spawnTime] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + .2, function()	-- execute in some close next frame to accurate use of UnitAura function
			Earthen[spawnTime] = nil
			end)
			Ctimer(.2, function()	-- execute a second timer to ensure it catches
				UpdateAllNameplates()
			end)
		end
		UpdateAllNameplates()
	end

	-----------------------------------------------------------------------------------------------------------------
	--Grounding Check (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_SUMMON") or (event == "SPELL_CREATE")) and (spellId == 204336) then
		if (destGUID ~= nil) then
			local duration = 3
			local guid = destGUID
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("Grounding Totem Spawned at: "..spawnTime)
			end
			local expiration = GetTime() + duration
			if (Grounding[spawnTime] == nil) then --source becomes the totem ><
				Grounding[spawnTime] = {}
			end
			Grounding[spawnTime] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + .2, function()	-- execute in some close next frame to accurate use of UnitAura function
			Grounding[spawnTime] = nil
			end)
			Ctimer(.2, function()	-- execute a second timer to ensure it catches
				UpdateAllNameplates()
			end)
		end
		fPB.UpdateAllNameplates()
	end

	-----------------------------------------------------------------------------------------------------------------
	--WarBanner Check (Totems Need a Spawn Time Check)
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_SUMMON") or (event == "SPELL_CREATE")) and (spellId == 236320) then
		if (destGUID ~= nil) then
			local duration = 15
			local expiration = GetTime() + duration
			if (WarBanner[destGUID] == nil) then
				WarBanner[destGUID] = {}
			end
			WarBanner[destGUID] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + 1, function()	-- execute in some close next frame to accurate use of UnitAura function
				WarBanner[destGUID] = nil
				fPB.UpdateAllNameplates()
			end)
		end
		if (destGUID ~= nil) then
			local duration = 15
			local expiration = GetTime() + duration
			if (WarBanner[1] == nil) then
				WarBanner[1] = {}
			end
			WarBanner[1] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + 1, function()	-- execute in some close next frame to accurate use of UnitAura function
				WarBanner[1] = nil
				fPB.UpdateAllNameplates()
			end)
		end
		if (destGUID ~= nil) then
			local duration = 15
			local guid = destGUID
			local spawnTime
			local unitType, _, _, _, _, _, spawnUID = strsplit("-", guid)
			if unitType == "Creature" or unitType == "Vehicle" then
			local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
			local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
			spawnTime = spawnEpoch + spawnEpochOffset
			--print("WarBanner Totem Spawned at: "..spawnTime)
			end
			local expiration = GetTime() + duration
			if (WarBanner[spawnTime] == nil) then --source becomes the totem ><
				WarBanner[spawnTime] = {}
			end
			WarBanner[spawnTime] = { ["duration"] = duration, ["expiration"] = expiration }
			Ctimer(duration + .2, function()	-- execute in some close next frame to accurate use of UnitAura function
				WarBanner[spawnTime] = nil
			end)
			Ctimer(.2, function()	-- execute a second timer to ensure it catches
				fPB.UpdateAllNameplates()
			end)
		end
		fPB.UpdateAllNameplates()
	end

    -------------------------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------------------------------

	local Spells = db.Spells
	local name = GetSpellInfo(spellId)
	local cachedID = cachedSpells[name]
	local listedSpell

	if Spells[spellId] and not db.ignoredDefaultSpells[spellId] then
		listedSpell = Spells[spellId]
	elseif cachedID then
		if cachedID == "noid" then
			listedSpell = Spells[name]
		else
			listedSpell = Spells[cachedID]
		end
	end

	local isAlly, EnemyBuff

	-----------------------------------------------------------------------------------------------------------------
	--Summoned Spells Check
	-----------------------------------------------------------------------------------------------------------------
	if ((event == "SPELL_SUMMON") or (event == "SPELL_CREATE"))  then --Summoned CDs
	--print(sourceName.." "..spellId.." Summoned "..substring(destGUID, -7).." fPB")
		if listedSpell and listedSpell.spellTypeSummon then
			if sourceGUID and (bit_band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isAlly = false else isAlly = true end
			local guid = destGUID
			local duration = listedSpell.durationCLEU or 1
			local type = "HELPFUL"
			local namePrint, _, icon = GetSpellInfo(spellId)
			if listedSpell.IconId then icon = listedSpell.IconId end
			if listedSpell.RedifEnemy and not isAlly then EnemyBuff = true end

			local my = sourceGUID == UnitGUID("player")
			local stack = 0
			local debufftype = "Buff" -- Magic = {0.20,0.60,1.00},	Curse = {0.60,0.00,1.00} Disease = {0.60,0.40,0}, Poison= {0.00,0.60,0}, none = {0.80,0,   0}, Buff = {0.00,1.00,0},
			local expiration = GetTime() + duration
			local scale = listedSpell.scale
			local durationSize = listedSpell.durationSize
			local stackSize = listedSpell.stackSize
			local glow = listedSpell.IconGlow
			local id = 1 --Need to figure this out
			if not Interrupted[sourceGUID] then
				Interrupted[sourceGUID] = {}
			end
			if(listedSpell.show == 1)
			or(listedSpell.show == 2 and my)
			or(listedSpell.show == 4 and isAlly)
			or(listedSpell.show == 5 and not isAlly) then
				--print(sourceName.." Summoned "..namePrint.." "..substring(destGUID, -7).." for "..duration.." fPB")
				local tablespot = #Interrupted[sourceGUID] + 1
				tblinsert (Interrupted[sourceGUID], tablespot, { type = type, icon = icon, stack = stack, debufftype = debufftype,	duration = duration, expiration = expiration, scale = scale, durationSize = durationSize, stackSize = stackSize, id = id, EnemyBuff = EnemyBuff, sourceGUID = sourceGUID, glow = glow, ["destGUID"] = destGUID, ["sourceName"] = sourceName, ["namePrint"] = namePrint, ["expiration"] = expiration, ["spellId"] = spellId})
				UpdateAllNameplates()
				local ticker = 1
				Ctimer(duration, function()
					if Interrupted[sourceGUID] then
						for k, v in pairs(Interrupted[sourceGUID]) do
							if v.spellId == spellId and v.expiration == expiration then
								--print(v.sourceName.." Timed Out "..v.namePrint.." "..substring(v.destGUID, -7).." left w/ "..string.format("%.2f", v.expiration-GetTime()).." fPB C_Timer")
								Interrupted[sourceGUID][k] = nil
								UpdateAllNameplates()
							end
						end
					end
				end)
				local iteration, check
				iteration = duration * 10 + 5; check = .1
				self.ticker = C_Timer.NewTicker(check, function()
					local name = GetSpellInfo(spellId)
					if Interrupted[sourceGUID] then
						for k, v in pairs(Interrupted[sourceGUID]) do
							if v.destGUID and v.spellId ~= 394243 and v.spellId ~= 387979 and v.spellId ~= 394235 then --Dimensional Rift Hack
								if substring(v.destGUID, -5) == substring(guid, -5) then --string.sub is to help witj Mirror Images bug
									if ObjectDNE(v.destGUID, ticker, v.namePrint, v.sourceName) then
										--print(v.sourceName.." "..ObjectDNE(v.destGUID, ticker, v.namePrint, v.sourceName).." "..v.namePrint.." "..substring(v.destGUID, -7).." left w/ "..string.format("%.2f", v.expiration-GetTime()).." fPB C_Ticker")
										Interrupted[sourceGUID][k] = nil
										UpdateAllNameplates()
										self.ticker:Cancel()
										break
									end
								end
							end
						end
					end
					ticker = ticker + 1
				end, iteration)
			end
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	--Casted  CDs w/o Aura (fury of Elune)
	-----------------------------------------------------------------------------------------------------------------
	if (event == "SPELL_CAST_SUCCESS") then 
		if listedSpell and listedSpell.spellTypeCastedAuras then
			if sourceGUID and (bit_band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isAlly = false else isAlly = true end
			local duration = listedSpell.durationCLEU or 1
			local type = "HELPFUL"
			local namePrint, _, icon = GetSpellInfo(spellId)
			if listedSpell.IconId then icon = listedSpell.IconId end
			if listedSpell.RedifEnemy and not isAlly then EnemyBuff = true end
			--print(sourceName.." Casted "..namePrint.." "..substring(destGUID, -7).." for "..duration.." fPB")
			local my = sourceGUID == UnitGUID("player")
			local stack = 0
			local debufftype = "Buff" -- Magic = {0.20,0.60,1.00},	Curse = {0.60,0.00,1.00} Disease = {0.60,0.40,0}, Poison= {0.00,0.60,0}, none = {0.80,0,   0}, Buff = {0.00,1.00,0},
			local expiration = GetTime() + duration
			local scale = listedSpell.scale
			local durationSize = listedSpell.durationSize
			local stackSize = listedSpell.stackSize
			local glow = listedSpell.IconGlow
			local id = 1 --Need to figure this out
			if not Interrupted[sourceGUID] then
				Interrupted[sourceGUID] = {}
			end
			if(listedSpell.show == 1)
			or(listedSpell.show == 2 and my)
			or(listedSpell.show == 4 and isAlly)
			or(listedSpell.show == 5 and not isAlly) then
				local tablespot = #Interrupted[sourceGUID] + 1
				tblinsert (Interrupted[sourceGUID], tablespot, { type = type, icon = icon, stack = stack, debufftype = debufftype,	duration = duration, expiration = expiration, scale = scale, durationSize = durationSize, stackSize = stackSize, id = id, EnemyBuff = EnemyBuff, sourceGUID = sourceGUID, glow = glow, ["destGUID"] = destGUID, ["sourceName"] = sourceName, ["namePrint"] = namePrint, ["expiration"] = expiration, ["spellId"] = spellId})
				UpdateAllNameplates()
				Ctimer(duration, function()
					if Interrupted[sourceGUID] then
						for k, v in pairs(Interrupted[sourceGUID]) do
							if v.spellId == spellId and v.expiration == expiration then
								--print(v.sourceName.." Timed Out "..v.namePrint.." "..substring(v.destGUID, -7).." left w/ "..string.format("%.2f", v.expiration-GetTime()).." fPB C_Timer")
								Interrupted[sourceGUID][k] = nil
								UpdateAllNameplates()
							end
						end
					end
				end)
			end
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	--Channeled Kicks
	-----------------------------------------------------------------------------------------------------------------
	if (destGUID ~= nil) then --Channeled Kicks
		if (event == "SPELL_CAST_SUCCESS") and not (event == "SPELL_INTERRUPT") then
			if listedSpell and listedSpell.spellTypeInterrupt then
				local isFriendly
				if destGUID and (bit_band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isAlly = false else isAlly = true end
				if sourceGUID and (bit_band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isFriendly = false else isFriendly = true end
				local unit
				for i = 1,  #C_NamePlate_GetNamePlates() do --Issue arrises if nameplates are not shown, you will not be able to capture the kick for channel
					if (destGUID == UnitGUID("nameplate"..i)) then
						unit = "nameplate"..i
						break
					end
				end
				for i = 1, 3 do
					if (destGUID == UnitGUID("arena"..i)) then
						unit = "arena"..i
						break
					end
				end
				if unit and (select(7, UnitChannelInfo(unit)) == false) then
					local duration = listedSpell.durationCLEU or 1
					if (duration ~= nil) then
						duration = interruptDuration(destGUID, duration) or duration
					end
					local namePrint, _, icon = GetSpellInfo(spellId)
					if listedSpell.IconId then icon = listedSpell.IconId end
					if listedSpell.RedifEnemy and not isFriendly then EnemyBuff = true end
					--print(sourceName.." Casted "..namePrint.." "..substring(destGUID, -7).." for "..duration.." fPB")
					local my = sourceGUID == UnitGUID("player")
					local stack = 0
					local debufftype = "none"  -- Magic = {0.20,0.60,1.00},	Curse = {0.60,0.00,1.00} Disease = {0.60,0.40,0}, Poison= {0.00,0.60,0}, none = {0.80,0,   0}, Buff = {0.00,1.00,0},
					local expiration = GetTime() + duration
					local scale = listedSpell.scale
					local durationSize = listedSpell.durationSize
					local stackSize = listedSpell.stackSize
					local glow = listedSpell.IconGlow
					local id = 1 --Need to figure this out
					if not Interrupted[destGUID] then
						Interrupted[destGUID] = {}
					end
					if(listedSpell.show == 1)
					or(listedSpell.show == 2 and my)
					or(listedSpell.show == 4 and isAlly)
					or(listedSpell.show == 5 and not isAlly) then
						local tablespot = #Interrupted[destGUID] + 1
						local sourceGUID_Kick = true
						for k, v in pairs(Interrupted[destGUID]) do
							if v.icon == icon and v.sourceGUID == sourceGUID and ((expiration - v.expiration) < 1) then
								--print("Regular Kick Spell Exists, kick used within: "..(expiration - v.expiration))
								sourceGUID_Kick = false -- the source already used his kick within a GCD on this destGUID
								break
							end
						end
						if sourceGUID_Kick then
							--print(sourceName.." kicked "..(select(1, UnitChannelInfo(unit))).." channel cast w/ "..name.. " from "..destName)
							tblinsert (Interrupted[destGUID], tablespot, { type = "HARMFUL", icon = icon, stack = stack, debufftype = debufftype, duration = duration, expiration = expiration, scale = scale, durationSize = durationSize, stackSize = stackSize, id = id, EnemyBuff = EnemyBuff, sourceGUID = sourceGUID, glow = glow, spellSchool = spellSchool,  ["destGUID"] = destGUID, ["sourceName"] = sourceName, ["namePrint"] = namePrint, ["expiration"] = expiration, ["spellId"] = spellId, ["spellSchool"] = spellSchool})
							Ctimer(duration, function()
								if Interrupted[destGUID] then
									for k, v in pairs(Interrupted[destGUID]) do
										if v.spellId == spellId and v.expiration == expiration then
											--print(v.sourceName.." Timed Out "..v.namePrint.." "..substring(v.destGUID, -7).." left w/ "..string.format("%.2f", v.expiration-GetTime()).." fPB C_Timer")
											Interrupted[destGUID][k] = nil
											UpdateAllNameplates()
										end
									end
								end
							end)
						end
					end
				end
			end
		end
	end

	-----------------------------------------------------------------------------------------------------------------
	--Regular Casted Kicks
	-----------------------------------------------------------------------------------------------------------------
	if (destGUID ~= nil) then --Regular Casted Kicks
		if (event == "SPELL_INTERRUPT") then
			if listedSpell and listedSpell.spellTypeInterrupt then
				local isFriendly
				if destGUID and (bit_band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isAlly = false else isAlly = true end
				if sourceGUID and (bit_band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE) then isFriendly = false else isFriendly = true end

				local duration = listedSpell.durationCLEU or 1
				if (duration ~= nil) then
					duration = interruptDuration(destGUID, duration) or duration
				end
				local namePrint, _, icon = GetSpellInfo(spellId)
				if listedSpell.IconId then icon = listedSpell.IconId end
				if listedSpell.RedifEnemy and not isFriendly then EnemyBuff = true end
				--print(sourceName.." Casted "..namePrint.." "..substring(destGUID, -7).." for "..duration.." fPB")
				local my = sourceGUID == UnitGUID("player")
				local stack = 0
				local debufftype = "none"  -- Magic = {0.20,0.60,1.00},	Curse = {0.60,0.00,1.00} Disease = {0.60,0.40,0}, Poison= {0.00,0.60,0}, none = {0.80,0,   0}, Buff = {0.00,1.00,0},
				local expiration = GetTime() + duration
				local scale = listedSpell.scale
				local durationSize = listedSpell.durationSize
				local stackSize = listedSpell.stackSize
				local glow = listedSpell.IconGlow
				local id = 1 --Need to figure this out
				if not Interrupted[destGUID] then
					Interrupted[destGUID] = {}
				end
				if(listedSpell.show == 1)
					or(listedSpell.show == 2 and my)
					or(listedSpell.show == 4 and isAlly)
					or(listedSpell.show == 5 and not isAlly) then
					local tablespot = #Interrupted[destGUID] + 1
					local sourceGUID_Kick = true
					for k, v in pairs(Interrupted[destGUID]) do
						if v.icon == icon and v.sourceGUID == sourceGUID and ((expiration - v.expiration) < 1) then
							--print("Casted Kick Fired but Did Not Execute within: "..(expiration - v.expiration).." of Channel Kick Firing")
							sourceGUID_Kick = false -- the source already used his kick within a GCD on this destGUID
							break
						end
					end
					if sourceGUID_Kick then
						--print(sourceName.." kicked cast w/ "..name.. " from "..destName)
						tblinsert (Interrupted[destGUID], tablespot, { type = "HARMFUL", icon = icon, stack = stack, debufftype = debufftype, duration = duration, expiration = expiration, scale = scale, durationSize = durationSize, stackSize = stackSize, id = id, EnemyBuff = EnemyBuff, sourceGUID = sourceGUID, glow = glow, spellSchool = spellSchool, ["destGUID"] = destGUID, ["sourceName"] = sourceName, ["namePrint"] = namePrint, ["expiration"] = expiration, ["spellId"] = spellId, ["spellSchool"] = spellSchool})
						UpdateAllNameplates()
						Ctimer(duration, function()
							if Interrupted[destGUID] then
								for k, v in pairs(Interrupted[destGUID]) do
									if v.spellId == spellId and v.expiration == expiration then
										--print(v.sourceName.." Timed Out "..v.namePrint.." "..substring(v.destGUID, -7).." left w/ "..string.format("%.2f", v.expiration-GetTime()).." fPB C_Timer")
										Interrupted[destGUID][k] = nil
										UpdateAllNameplates()
									end
								end
							end
						end)
					end
				end
			end
		end
	end

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	-----------------------------------------------------------------------------------------------------------------
	--Reset Cold Snap (Resets Block/Barrier/Nova/CoC)
	-----------------------------------------------------------------------------------------------------------------
	if ((sourceGUID ~= nil) and (event == "SPELL_CAST_SUCCESS") and (spellId == 235219)) then --Reset Cold Snap (Resets Block/Barrier/Nova/CoC)
		local needUpdateUnitAura = false
		if (Interrupted[sourceGUID] ~= nil) then
			for k, v in pairs(Interrupted[sourceGUID]) do
				if v.spellSchool then
					if v.spellSchool == 16 then
						needUpdateUnitAura = true
						Interrupted[sourceGUID][k] = nil
					end
				end
			end
		end
		if needUpdateUnitAura then
			UpdateAllNameplates()
		end
	end

	if (((event == "UNIT_DIED") or (event == "UNIT_DESTROYED") or (event == "UNIT_DISSIPATES")) and (select(2, GetPlayerInfoByGUID(destGUID)) ~= "HUNTER")) then
			if (Interrupted[destGUID] ~= nil) then
				Interrupted[destGUID]= nil
				UpdateAllNameplates()
		end
	end
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
end -- End of fPB:CLEU() function

-- Function to reset table recycling stats
local function ResetTableRecyclingStats()
    if not fPB.tableStats then
        fPB.tableStats = {
            created = 0,
            recycled = 0,
            released = 0
        }
    else
        fPB.tableStats.created = 0
        fPB.tableStats.recycled = 0
        fPB.tableStats.released = 0
    end
    
    -- Don't clear the pool, just reset statistics
    -- We want to keep reusing the tables in the pool
    
    if fPB.debug.enabled then
        fPB.Print("Table recycling statistics reset. Pool size: " .. #fPB.tablePool)
    end
end

-- Add Print to addon namespace for use by other functions
fPB.Print = Print

-- Make MarkForSorting available globally through the addon table
fPB.MarkForSorting = MarkForSorting

-- Function to initialize debug system with proper defaults
local function InitializeDebugSystem()
    -- Ensure we have debug options initialized
    if not fPB.debug then
        fPB.debug = {
            enabled = false,
            performance = false,
            memory = false,
            events = false,
            verbose = false,
            cacheMessages = false,  -- Add new field for cache messages
            samplingRate = 100,
            memoryTrackingFrequency = 0,
            significantMemoryChangeOnly = false,
            memoryChangeThreshold = 50,
            unitNameFilter = "",
            detailLevel = 2,
            startTime = GetTime(),
            updateCounts = 0,
            skippedUpdates = 0,
            dynamicThrottlingEnabled = true,
            autoDisableAfter = 0
        }
    end
    
    -- Ensure our sort stats are initialized
    if not fPB.sortStats then
        fPB.sortStats = {
            totalSorts = 0,
            cacheMisses = 0,
            cacheHits = 0,
            lastReset = GetTime()
        }
    end
    
    -- Ensure our table stats are initialized
    if not fPB.tableStats then
        fPB.tableStats = {
            created = 0,
            recycled = 0,
            released = 0
        }
    end
    
    return fPB.debug
end

-- Call this during initialization
InitializeDebugSystem()

-- Initialize more detailed statistics tracking
local function InitializeStatTracking()
    -- Basic table stats
    fPB.tableStats = fPB.tableStats or {
        created = 0,
        recycled = 0,
        released = 0
    }
    
    -- Sort optimization stats
    fPB.sortStats = fPB.sortStats or {
        totalSorts = 0,
        cacheHits = 0,
        cacheMisses = 0,
        smallExpirationChanges = 0,
        significantExpirationChanges = 0,
        otherPropertyChanges = 0,
        buffCountChanges = 0
    }
end

-- Function to print detailed statistics
function fPB.PrintDetailedStats()
    print(Color("FlyPlateBuffs Performance Statistics:", "HEADER"))
    
    -- Table Recycling Stats
    print(Color("\nTable Recycling:", "HEADER"))
    print(Color("  Pool size: ", "NORMAL") .. Color(tostring(fPB.tablePool and #fPB.tablePool or 0), "VALUE"))
    print(Color("  Tables created: ", "NORMAL") .. Color(tostring(fPB.tableStats and fPB.tableStats.created or 0), "VALUE"))
    print(Color("  Tables recycled: ", "NORMAL") .. Color(tostring(fPB.tableStats and fPB.tableStats.recycled or 0), "VALUE"))
    print(Color("  Tables released: ", "NORMAL") .. Color(tostring(fPB.tableStats and fPB.tableStats.released or 0), "VALUE"))
    
    -- Sort Optimization Stats
    print(Color("\nSort Optimization:", "HEADER"))
    local totalSorts = (fPB.sortStats and fPB.sortStats.totalSorts or 0)
    local cacheHits = (fPB.sortStats and fPB.sortStats.cacheHits or 0)
    local hitRate = totalSorts > 0 and (cacheHits / totalSorts * 100) or 0
    
    print(Color("  Total sorts: ", "NORMAL") .. Color(tostring(totalSorts), "VALUE"))
    print(Color("  Cache hits: ", "NORMAL") .. Color(string.format("%d (%.1f%%)", cacheHits, hitRate), "VALUE"))
    
    -- Cache Miss Details
    print(Color("\nCache Miss Reasons:", "HEADER"))
    print(Color("  Small changes: ", "NORMAL") .. Color(tostring(fPB.sortStats and fPB.sortStats.smallExpirationChanges or 0), "VALUE"))
    print(Color("  Significant changes: ", "NORMAL") .. Color(tostring(fPB.sortStats and fPB.sortStats.significantExpirationChanges or 0), "VALUE"))
end

-- Add command handler for stats
local function StatsHandler(subcmd)
    if subcmd == "reset" then
        -- Reset all statistics
        if fPB.ResetSortStats then
            fPB.ResetSortStats()
        end
        ResetFilterStats()
        print("|cFF00FFFF[FlyPlateBuffs]|r Statistics reset")
    else
        -- Print detailed stats
        fPB.PrintDetailedStats()
    end
end

-- Function to handle the cache command
function CacheHandler(subcmd)
    if subcmd == "messages" or subcmd == "msgs" then
        -- Toggle cache messages
        fPB.debug.cacheMessages = not fPB.debug.cacheMessages
        db.debugCacheMessages = fPB.debug.cacheMessages
        
        -- Print status message
        if fPB.debug.cacheMessages then
            print("|cFF00FFFF[FlyPlateBuffs]|r Cache debug messages |cFF00FF00enabled|r - You'll see detailed information about cache operations")
        else
            print("|cFF00FFFF[FlyPlateBuffs]|r Cache debug messages |cFFFF0000disabled|r - Cache messages will be suppressed")
        end
    elseif subcmd == "wipe" or subcmd == "clear" then
        -- Wipe the sort cache
        if fPB.wipeAllSortCaches then
            fPB.wipeAllSortCaches()
            print("|cFF00FFFF[FlyPlateBuffs]|r Sort cache wiped")
        else
            print("|cFF00FFFF[FlyPlateBuffs]|r Error: Sort cache wipe function not available")
        end
    else
        -- Show cache status
        DumpSortCacheStatus()
    end
end

-- Initialize addon and variables
function fPB:Initialize()
    -- Record when the addon started
    fPB.startTime = GetTime()
    
    -- Initialize debug stats
    fPB.sortStats = {
        totalSorts = 0,
        cacheHits = 0,
        cacheMisses = 0,
        smallExpirationChanges = 0,
        significantExpirationChanges = 0,
        otherPropertyChanges = 0,
        buffCountChanges = 0
    }
    
    -- Initialize filter stats
    fPB.filterStats = {
        totalBuffsChecked = 0,
        earlyExits = 0,
        lastReset = GetTime()
    }
    
    -- Initialize table stats
    fPB.tableStats = {
        created = 0,
        recycled = 0,
        released = 0
    }
    
    -- Other initialization code...
    
    -- Pre-populate table pool
    PrePopulatePool(50)
end

-- Create a local function for clarity and to avoid namespace issues
local function UpdateAllNameplatesLocal(updateOptions)
    return fPB.UpdateAllNameplates(updateOptions)
end

-- Add this near the beginning of the file, right after fPB.UpdateAllNameplates is defined
-- This will make all unqualified calls use our namespaced function
UpdateAllNameplates = fPB.UpdateAllNameplates

-- Function to wipe all sort caches
function fPB.wipeAllSortCaches()
    wipe(SortCache)
    print("|cFF00FFFF[FlyPlateBuffs]|r All sort caches have been cleared")
    
    -- Reset cache stats
    if fPB.sortStats then
        fPB.sortStats.totalSorts = 0
        fPB.sortStats.cacheHits = 0
        fPB.sortStats.cacheMisses = 0
        fPB.sortStats.smallExpirationChanges = 0
        fPB.sortStats.significantExpirationChanges = 0
        fPB.sortStats.otherPropertyChanges = 0
        fPB.sortStats.buffCountChanges = 0
        fPB.sortStats.lastReset = GetTime()
    end
    
    -- Force update all nameplates
    UpdateAllNameplates(true)
end

-- A dedicated function to clear sort caches that can be called from slash commands or options
function ClearSortCaches()
    if fPB.wipeAllSortCaches then
        fPB.wipeAllSortCaches()
    end
end

-- Create a local function for clarity and to avoid namespace issues
local function UpdateAllNameplatesLocal(updateOptions)
    return fPB.UpdateAllNameplates(updateOptions)
end

-- Add a function to reset filter statistics
local function ResetFilterStats()
    if fPB.filterStats then
        fPB.filterStats.totalBuffsChecked = 0
        fPB.filterStats.earlyExits = 0
        fPB.filterStats.lastReset = GetTime()
    end
    
    if fPB.debug and fPB.debug.enabled then
        DebugLog("filtering", "Filter statistics reset")
    end
end

-- Make this function available to the addon namespace
fPB.ResetFilterStats = ResetFilterStats

-- Load necessary database values
function fPB:LoadDBValues()
    db = fPB.db.profile
    
    -- Load debug settings from database if they exist
    if db.debugEnabled ~= nil then fPB.debug.enabled = db.debugEnabled end
    if db.debugVerbose ~= nil then fPB.debug.verbose = db.debugVerbose end
    if db.debugDetailLevel ~= nil then fPB.debug.detailLevel = db.debugDetailLevel end
    if db.debugCategories ~= nil then fPB.debug.categories = db.debugCategories end
    if db.debugCacheMessages ~= nil then fPB.debug.cacheMessages = db.debugCacheMessages end
    if db.debugFilterMessages ~= nil then fPB.debug.filterMessages = db.debugFilterMessages end
    if db.debugPerformance ~= nil then fPB.debug.performance = db.debugPerformance end
    if db.debugAuraTracking ~= nil then fPB.debug.auraTracking = db.debugAuraTracking end
end

-- Function to print detailed statistics
function fPB.PrintDetailedStats()
    print("|cFF00FFFF[FlyPlateBuffs]|r Performance Statistics:")
    
    -- Table Recycling Stats
    print("Table Recycling:")
    print("  Pool size: " .. (fPB.tablePool and #fPB.tablePool or 0))
    print("  Tables created: " .. (fPB.tableStats and fPB.tableStats.created or 0))
    print("  Tables recycled: " .. (fPB.tableStats and fPB.tableStats.recycled or 0))
    print("  Tables released: " .. (fPB.tableStats and fPB.tableStats.released or 0))
    local memorySaved = (fPB.tableStats and fPB.tableStats.recycled or 0) * 0.1 -- Approximate KB saved
    print("  Memory savings: " .. string.format("%.2f", memorySaved) .. " KB")
    
    -- Sort Optimization Stats
    local totalSorts = (fPB.sortStats and fPB.sortStats.totalSorts or 0)
    local cacheHits = (fPB.sortStats and fPB.sortStats.cacheHits or 0)
    local cacheMisses = (fPB.sortStats and fPB.sortStats.cacheMisses or 0)
    local hitRate = (totalSorts > 0) and (cacheHits / totalSorts * 100) or 0
    
    print("Sort Optimization:")
    print("  Total sorts: " .. totalSorts)
    print("  Cache hits: " .. cacheHits .. " (" .. string.format("%.1f", hitRate) .. "%)")
    print("  Cache misses: " .. cacheMisses)
    
    -- Sort rate
    local uptime = GetTime() - (fPB.startTime or GetTime())
    local sortsPerSecond = (uptime > 0) and (totalSorts / uptime) or 0
    print("  Sorts per second: " .. string.format("%.2f", sortsPerSecond))
    
    -- Detailed Cache Miss Reasons
    print("Cache Miss Reasons:")
    print("  Small expiration changes (ignored): " .. (fPB.sortStats and fPB.sortStats.smallExpirationChanges or 0))
    print("  Significant expiration changes: " .. (fPB.sortStats and fPB.sortStats.significantExpirationChanges or 0))
    print("  Other property changes: " .. (fPB.sortStats and fPB.sortStats.otherPropertyChanges or 0))
    print("  Buff count changes: " .. (fPB.sortStats and fPB.sortStats.buffCountChanges or 0))
end

-- Add PrintDetailedStats to addon namespace
-- fPB.PrintDetailedStats assignment removed

-- Global variables for adaptive detail system
local fPB_currentDetailLevel = "full" -- "full", "low", "medium", "high"
local fPB_visibleNameplateCount = 0
local fPB_lastDetailCheck = 0
local fPB_detailCheckInterval = 0.5 -- Check every 0.5 seconds

-- Function to determine current detail level based on nameplate count
function DetermineDetailLevel()
    if not db.adaptiveDetail then
        return "full"
    end
    
    -- Count visible nameplates
    local nameplateCount = 0
    for _, plateFrame in pairs(C_NamePlate.GetNamePlates()) do
        if plateFrame:IsVisible() then
            nameplateCount = nameplateCount + 1
        end
    end
    
    -- Save current count for other functions to use
    fPB_visibleNameplateCount = nameplateCount
    
    -- Determine detail level based on thresholds
    local detailLevel = "full"
    if nameplateCount >= db.adaptiveThresholds.high then
        detailLevel = "high" -- Minimum detail
    elseif nameplateCount >= db.adaptiveThresholds.medium then
        detailLevel = "medium" -- Medium detail
    elseif nameplateCount >= db.adaptiveThresholds.low then
        detailLevel = "low" -- Low detail
    end
    
    -- Only log if detail level changed
    if detailLevel ~= fPB_currentDetailLevel then
        DebugLog("events", "Detail level changed from %s to %s (nameplates: %d)", 
            fPB_currentDetailLevel, detailLevel, nameplateCount)
        fPB_currentDetailLevel = detailLevel
    end
    
    return detailLevel
end

-- Check if we should apply adaptive detail settings
function ShouldApplyAdaptiveDetail(featureType)
    if not db.adaptiveDetail then
        return false
    end
    
    -- Check if this specific feature type is enabled for adaptation
    if featureType and db.adaptiveFeatures[featureType] ~= true then
        return false
    end
    
    -- Update detail level if needed
    local currentTime = GetTime()
    if currentTime - fPB_lastDetailCheck > fPB_detailCheckInterval then
        DetermineDetailLevel()
        fPB_lastDetailCheck = currentTime
    end
    
    -- Only apply adaptive features if we're not at full detail
    return fPB_currentDetailLevel ~= "full"
end

-- Function to get the current detail factor (0.0 - 1.0)
-- 1.0 = full detail, 0.0 = minimum detail
function GetDetailFactor()
    local detailLevel = fPB_currentDetailLevel
    
    if detailLevel == "full" then
        return 1.0
    elseif detailLevel == "low" then
        return 0.7
    elseif detailLevel == "medium" then
        return 0.4
    else -- high (minimum detail)
        return 0.1
    end
end

-- Modify the UpdateAura function to apply adaptive detail
local function UpdateAura(button, aura)
    local shouldAdaptGlows = ShouldApplyAdaptiveDetail("glows")
    local shouldAdaptAnimations = ShouldApplyAdaptiveDetail("animations")
    local shouldAdaptCooldowns = ShouldApplyAdaptiveDetail("cooldownSwipes")
    local detailFactor = GetDetailFactor()
    
    -- (Original code preserved)
    
    -- For glow effects, adapt based on detail level
    if shouldAdaptGlows and button.fPBglow and button.fPBglow:IsVisible() then
        -- At lower detail levels, show glows only for very important buffs
        if aura.important <= 2 and detailFactor < 0.5 then
            button.fPBglow:Hide()
        elseif aura.important == 3 and detailFactor < 0.3 then
            button.fPBglow:Hide()
        end
    end
    
    -- For cooldown swipes, adapt based on detail level
    if shouldAdaptCooldowns and button.cooldown then
        if detailFactor < 0.3 then
            -- At minimum detail, hide all cooldown swipes
            if db.showStdSwipe then
                if type(button.cooldown.SetSwipeTexture) == "function" then
                    button.cooldown:SetSwipeTexture("Interface\\AddOns\\flyPlateBuffs\\texture\\SwipeSimple")
                end
            end
        elseif detailFactor < 0.6 then
            -- At medium detail, use less detailed swipe texture
            if db.showStdSwipe then
                if type(button.cooldown.SetSwipeTexture) == "function" then
                    button.cooldown:SetSwipeTexture("Interface\\AddOns\\flyPlateBuffs\\texture\\SwipeSimple")
                end
            end
        end
    end
    
    -- For animations, adapt based on detail level
    if shouldAdaptAnimations then
        -- At low detail levels, disable certain animations
        if button.Fader and button.Fader:IsPlaying() and detailFactor < 0.5 then
            button.Fader:Stop()
        end
        
        -- At minimum detail, disable all animations
        if button.AnimFrame and detailFactor < 0.3 then
            button.AnimFrame:Hide()
        end
    end
end

-- Timer update function
local function UpdateTimer(button, expirationTime, duration)
    -- Skip frequent updates when many nameplates are visible
    local shouldAdaptTextUpdates = ShouldApplyAdaptiveDetail("textUpdates")
    local detailFactor = GetDetailFactor()
    
    if shouldAdaptTextUpdates then
        -- Reduce update frequency based on detail level
        local currentTime = GetTime()
        if not button.lastTextUpdate then
            button.lastTextUpdate = 0
        end
        
        -- Calculate update interval based on detail factor
        -- - At full detail (1.0): update every 0.1s
        -- - At minimum detail (0.1): update every 1.0s
        local updateInterval = 0.1 + ((1.0 - detailFactor) * 0.9)
        
        -- Skip update if not enough time has passed
        if currentTime - button.lastTextUpdate < updateInterval then
            return
        end
        
        -- Remember last update time
        button.lastTextUpdate = currentTime
    end
    
    -- (Original timer update code)
    if expirationTime and expirationTime > 0 then
        local remaining = expirationTime - GetTime()
        if remaining > 0 then
            if button.timetext then
                if remaining < 60 then
                    -- For short durations, adapt precision based on detail level
                    if shouldAdaptTextUpdates and detailFactor < 0.4 then
                        -- Round to whole seconds for very short times at low detail
                        button.timetext:SetText(format("%d", remaining + 0.5))
                    else
                        -- Standard formatting for normal operation
                        if remaining < 3 then
                            button.timetext:SetText(format("%.1f", remaining))
                        elseif remaining < 60 then
                            button.timetext:SetText(format("%d", remaining + 0.5))
                        end
                    end
                elseif remaining < 3600 then
                    button.timetext:SetText(format("%d:%02d", remaining / 60, remaining % 60))
                else
                    button.timetext:SetText(format("%d:%02d", remaining / 3600, (remaining % 3600) / 60))
                end
            end
        else
            if button.timetext then
                button.timetext:SetText("")
            end
        end
    elseif button.timetext then
        button.timetext:SetText("")
    end
end

-- Hook to monitor nameplate count changes
local function MonitorNameplateChanges()
    -- Create a frame to watch for nameplate changes
    local adaptiveDetailFrame = CreateFrame("Frame")
    
    -- Events that could trigger nameplate count changes
    adaptiveDetailFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    adaptiveDetailFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    
    -- Check detail level on these events
    adaptiveDetailFrame:SetScript("OnEvent", function(self, event, ...)
        -- Force an immediate update of the detail level
        DetermineDetailLevel()
        fPB_lastDetailCheck = GetTime()
    end)
    
    -- Also check periodically in case other events affect nameplates
    adaptiveDetailFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Only check periodically to avoid performance impact
        if not fPB_lastDetailCheck then
            fPB_lastDetailCheck = 0
        end
        
        local currentTime = GetTime()
        if currentTime - fPB_lastDetailCheck > fPB_detailCheckInterval then
            DetermineDetailLevel()
            fPB_lastDetailCheck = currentTime
        end
    end)
    
    return adaptiveDetailFrame
end

-- Initialize the monitor when the addon loads
local adaptiveMonitor
function InitializeAdaptiveMonitor()
    if not adaptiveMonitor then
        adaptiveMonitor = MonitorNameplateChanges()
        DebugLog("events", "Adaptive detail monitor initialized")
    end
end

function fPB:UpdateBorderStyle(self)
    if not self or not self.border then return end
    
    -- If Masque is enabled, skip our custom border styling
    if MSQ and db.iconMasque and self.masqueSet then
        self.border:Hide()
        return
    end
    
    -- Apply our custom border styling
    local borderSize = db.borderSize or 1
    local style = db.borderStyle or 1
    
    self.border:ClearAllPoints()
    self.border:SetPoint("CENTER", self, "CENTER", 0, 0)
    
    -- Rest of the function remains the same
end

-- Helper functions for common patterns
local function CreateTimedAura(storageTable, guid, duration, onExpire)
    if not guid or not storageTable then return end
    
    if not storageTable[guid] then
        storageTable[guid] = {}
    end
    
    local expiration = GetTime() + duration
    storageTable[guid] = {
        duration = duration,
        expiration = expiration
    }
    
    -- Single timer for cleanup
    C_Timer.After(duration + 0.1, function()
        if storageTable[guid] then
            storageTable[guid] = nil
            if onExpire then onExpire() end
            UpdateAllNameplates()
        end
    end)
end

local function HandleWarBanner(destGUID)
    if not destGUID then return end
    
    local duration = 15
    
    -- Handle spawn time tracking
    local spawnTime
    local unitType, _, _, _, _, _, spawnUID = strsplit("-", destGUID)
    if unitType == "Creature" or unitType == "Vehicle" then
        local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
        local spawnEpochOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
        spawnTime = spawnEpoch + spawnEpochOffset
    end
    
    -- Create timed auras for all tracking methods
    CreateTimedAura(WarBanner, destGUID, duration)
    CreateTimedAura(WarBanner, 1, duration)
    if spawnTime then
        CreateTimedAura(WarBanner, spawnTime, duration)
    end
    
    -- Ensure nameplates update
    C_Timer.After(0.2, UpdateAllNameplates)
end

local function GetUnitAuras(unit)
    if not unit then return nil end
    
    local buffs = ProcessAllUnitAuras(unit, "HELPFUL")
    local debuffs = ProcessAllUnitAuras(unit, "HARMFUL")
    
    local result = {
        buffs = buffs,
        debuffs = debuffs,
        Release = function()
            ReleaseTable(buffs)
            ReleaseTable(debuffs)
            fPB.debug.stats.tablesReleased = (fPB.debug.stats.tablesReleased or 0) + 2
        end
    }
    
    return result
end

-- Track totem spawns
local function HandleTotemSpawn(spellId, srcGUID, srcName, dstGUID)
    local Spell = db.Spells[spellId]
    if not Spell or not Spell.isTotem then return end

    -- Get totem info
    local totemName = GetSpellInfo(spellId)
    if not totemName then return end

    -- Store totem info for nameplate handling
    local totemInfo = {
        spellId = spellId,
        name = totemName,
        ownerGUID = srcGUID,
        ownerName = srcName,
        totemGUID = dstGUID
    }
    
    if not fPB.activeAuras[dstGUID] then
        fPB.activeAuras[dstGUID] = {}
    end
    fPB.activeAuras[dstGUID][spellId] = totemInfo
end

-- Hook into CLEU for totem tracking
local function COMBAT_LOG_EVENT_UNFILTERED(...)
    local timestamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName = ...

    if eventType == "SPELL_SUMMON" then
        -- Check if it's a totem
        local Spell = db.Spells[spellId]
        if Spell and Spell.isTotem then
            HandleTotemSpawn(spellId, srcGUID, srcName, dstGUID)
            UpdateNameplate(dstGUID)
        end
    elseif eventType == "UNIT_DIED" then
        -- Clean up totem tracking when it dies
        if activeAuras[dstGUID] then
            for spellId, auraInfo in pairs(activeAuras[dstGUID]) do
                if db.Spells[spellId] and db.Spells[spellId].isTotem then
                    activeAuras[dstGUID][spellId] = nil
                end
            end
            if not next(activeAuras[dstGUID]) then
                activeAuras[dstGUID] = nil
            end
        end
    end
end

-- Modify nameplate icon creation for totems
local function CreateTotemIcon(frame, spellId, auraInfo)
    local icon = frame.fPBIcons[spellId] or CreateFrame("Frame", nil, frame)
    icon.texture = icon.texture or icon:CreateTexture(nil, "ARTWORK")
    
    -- Set up icon appearance
    local Spell = db.Spells[spellId]
    local size = Spell.scale or 1
    icon:SetSize(size * 20, size * 20)
    icon.texture:SetAllPoints()
    
    -- Set texture and glow if enabled
    if Spell.IconId then
        icon.texture:SetTexture(Spell.IconId)
    else
        local _, _, texture = GetSpellInfo(spellId)
        icon.texture:SetTexture(texture)
    end
    
    -- Apply standard glow if enabled in spell settings
    if Spell.IconGlow then
        fPB.ShowCustomGlow(icon, 1, 1, 1, 1)
    else
        fPB.HideCustomGlow(icon)
    end
    
    return icon
end

-- Add totem GUID tracking
local activeTotemGUIDs = {}

-- Modify the nameplate update function to handle totems
local function UpdateNameplateAuras(frame, unit)
    if not unit then return end
    local guid = UnitGUID(unit)
    if not guid then return end

    -- Check if this is a totem
    local isTotem = UnitCreatureType(unit) == "Totem"
    
    -- Clear existing icons
    if frame.fPBIcons then
        for _, icon in pairs(frame.fPBIcons) do
            icon:Hide()
        end
    else
        frame.fPBIcons = {}
    end

    -- Handle totem nameplates
    if isTotem then
        local totemInfo = fPB.activeAuras[guid]
        if totemInfo then
            for spellId, info in pairs(totemInfo) do
                local Spell = db.Spells[spellId]
                if Spell and Spell.isTotem then
                    -- Create or update totem icon
                    local icon = CreateTotemIcon(frame, spellId, info)
                    icon:ClearAllPoints()
                    icon:SetPoint("BOTTOM", frame, "TOP", 0, 5)
                    icon:Show()
                    frame.fPBIcons[spellId] = icon
                end
            end
        end
    end

    -- Continue with normal aura processing
    if not PlatesBuffs[frame] then
        if frame.fPBiconsFrame then
            frame.fPBiconsFrame:Hide()
        end
        return
    end

    -- Process remaining auras
    for i = 1, #PlatesBuffs[frame] do
        local buff = PlatesBuffs[frame][i]
        if buff then
            -- Create or update buff icon
            local icon = frame.fPBIcons[i] or CreateBuffIcon(frame, i, unit)
            UpdateBuffIcon(icon, buff)
            icon:Show()
            frame.fPBIcons[i] = icon
        end
    end
end

-- Modify the CLEU handler to track totem spawns and deaths
local function HandleCombatLogEvent(...)
    local timestamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, 
          dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()

    if eventType == "SPELL_SUMMON" then
        local Spell = db.Spells[spellId]
        if Spell and Spell.isTotem then
            -- Track the totem
            activeTotemGUIDs[dstGUID] = true
            HandleTotemSpawn(spellId, srcGUID, srcName, dstGUID)
            
            -- Force nameplate update
            C_Timer.After(0.1, function()
                for _, frame in pairs(C_NamePlate.GetNamePlates()) do
                    if frame.namePlateUnitToken and UnitGUID(frame.namePlateUnitToken) == dstGUID then
                        UpdateNameplateAuras(frame, frame.namePlateUnitToken)
                        break
                    end
                end
            end)
        end
    elseif eventType == "UNIT_DIED" then
        if activeTotemGUIDs[dstGUID] then
            -- Clean up totem tracking
            activeTotemGUIDs[dstGUID] = nil
            if activeAuras[dstGUID] then
                activeAuras[dstGUID] = nil
                -- Force nameplate update
                for _, frame in pairs(C_NamePlate.GetNamePlates()) do
                    if frame.namePlateUnitToken and UnitGUID(frame.namePlateUnitToken) == dstGUID then
                        UpdateNameplateAuras(frame, frame.namePlateUnitToken)
                        break
                    end
                end
            end
        end
    end
end

-- Register for nameplate events
local function RegisterTotemEvents(self)
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

-- Event handler
local function OnEvent(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLogEvent(CombatLogGetCurrentEventInfo())
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local frame = C_NamePlate.GetNamePlateForUnit(unit)
        if frame then
            UpdateNameplateAuras(frame, unit)
        end
    end
end

-- Initialize
local function InitTotemTracking()
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    RegisterTotemEvents(frame)
end

-- Hook into addon initialization
local function OnAddonLoaded(self, event, addonName)
    if addonName == "flyPlateBuffs" then
        InitTotemTracking()
    end
end

-- Register initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", OnAddonLoaded)

-- Add after the local variables section
local function CreatePixelGlow(button)
    if button.CustomGlow then return end
    
    button.CustomGlow = CreateFrame("Frame", nil, button)
    button.CustomGlow:SetPoint("CENTER", button, "CENTER", 0, 0)
    
    -- Create the glow texture
    button.glowTexture = button.CustomGlow:CreateTexture(nil, "OVERLAY", nil, 7)
    button.glowTexture:SetBlendMode("ADD")
    button.glowTexture:SetAtlas("clickcast-highlight-spellbook")
    button.glowTexture:SetDesaturated(true)

    -- Create and set up the mask
    button.CustomGlow.Mask = button.CustomGlow:CreateMaskTexture()
    button.CustomGlow.Mask:SetTexture("Interface\\TalentFrame\\talentsmasknodechoiceflyout", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    button.CustomGlow.Mask:SetAllPoints(button)
    
    -- Add the mask to the icon texture
    button.texture:AddMaskTexture(button.CustomGlow.Mask)
    
    -- Create animation
    local ag = button.CustomGlow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    
    -- Scale animation instead of alpha
    local grow = ag:CreateAnimation("Scale")
    grow:SetOrder(1)
    grow:SetScale(1.1, 1.1)
    grow:SetDuration(0.5)

    local shrink = ag:CreateAnimation("Scale")
    shrink:SetOrder(2)
    shrink:SetScale(0.9091, 0.9091)
    shrink:SetDuration(0.5)
    
    button.CustomGlow.anim = ag
end

local function ShowCustomGlow(button, r, g, b, a)
    if not button.CustomGlow then
        CreatePixelGlow(button)
    end
    
    -- Calculate offset based on button size
    local offsetMultiplier = 0.41
    local widthOffset = button:GetWidth() * offsetMultiplier
    local heightOffset = button:GetHeight() * offsetMultiplier

    -- Position and size the glow texture
    button.glowTexture:SetPoint("TOPLEFT", button, "TOPLEFT", -widthOffset, heightOffset)
    button.glowTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", widthOffset, -heightOffset)
    
    -- Set the glow color
    button.glowTexture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    button.glowTexture:Show()
    
    button.CustomGlow:Show()
    button.CustomGlow.anim:Play()
end

local function HideCustomGlow(button)
    if button.CustomGlow then
        button.CustomGlow:Hide()
        button.CustomGlow.anim:Stop()
        if button.glowTexture then
            button.glowTexture:Hide()
        end
    end
end

-- Add after local variable declarations
fPB.CreatePixelGlow = function(button)
    if button.CustomGlow then return end
    
    button.CustomGlow = CreateFrame("Frame", nil, button)
    button.CustomGlow:SetPoint("CENTER", button, "CENTER", 0, 0)
    
    -- Create the glow texture
    button.glowTexture = button.CustomGlow:CreateTexture(nil, "OVERLAY", nil, 7)
    button.glowTexture:SetBlendMode("ADD")
    button.glowTexture:SetAtlas("clickcast-highlight-spellbook")
    button.glowTexture:SetDesaturated(true)

    -- Create and set up the mask
    button.CustomGlow.Mask = button.CustomGlow:CreateMaskTexture()
    button.CustomGlow.Mask:SetTexture("Interface\\TalentFrame\\talentsmasknodechoiceflyout", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    button.CustomGlow.Mask:SetAllPoints(button)
    
    -- Add the mask to the icon texture
    if button.texture then
        button.texture:AddMaskTexture(button.CustomGlow.Mask)
    end
    
    -- Create animation
    local ag = button.CustomGlow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    
    -- Scale animation instead of alpha
    local grow = ag:CreateAnimation("Scale")
    grow:SetOrder(1)
    grow:SetScale(1.1, 1.1)
    grow:SetDuration(0.5)

    local shrink = ag:CreateAnimation("Scale")
    shrink:SetOrder(2)
    shrink:SetScale(0.9091, 0.9091)
    shrink:SetDuration(0.5)
    
    button.CustomGlow.anim = ag
end

fPB.ShowCustomGlow = function(button, r, g, b, a)
    if not button.CustomGlow then
        fPB.CreatePixelGlow(button)
    end
    
    -- Calculate offset based on button size
    local offsetMultiplier = 0.41
    local widthOffset = button:GetWidth() * offsetMultiplier
    local heightOffset = button:GetHeight() * offsetMultiplier

    -- Position and size the glow texture
    button.glowTexture:SetPoint("TOPLEFT", button, "TOPLEFT", -widthOffset, heightOffset)
    button.glowTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", widthOffset, -heightOffset)
    
    -- Set the glow color
    button.glowTexture:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    button.glowTexture:Show()
    
    button.CustomGlow:Show()
    button.CustomGlow.anim:Play()
end

fPB.HideCustomGlow = function(button)
    if button.CustomGlow then
        button.CustomGlow:Hide()
        button.CustomGlow.anim:Stop()
        if button.glowTexture then
            button.glowTexture:Hide()
        end
    end
end






