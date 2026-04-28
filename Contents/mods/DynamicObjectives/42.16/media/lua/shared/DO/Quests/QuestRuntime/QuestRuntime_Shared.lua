DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

Quests.MODDATA_KEY = Quests.MODDATA_KEY or "DynamicObjectives"
Quests.STATE_VERSION = Quests.STATE_VERSION or 6

Runtime.questUpdateTick = Runtime.questUpdateTick or 0

local function questLog(category, topic, message)
    DO.Log(category, topic, message)
end

local function say(player, text)
    if player and player.Say then
        player:Say(tostring(text))
    end
end

local function isZombie(value)
    if not (value and instanceof and instanceof(value, "IsoZombie")) then
        return false
    end
    
    local modData = value:getModData()
    if modData and modData.IsDTNPC == true then
        return false
    end
    
    return true
end

local function isLivingZombie(zombie)
    if not isZombie(zombie) then
        return false
    end

    if zombie.isDead and zombie:isDead() then
        return false
    end

    if zombie.getHealth and tonumber(zombie:getHealth()) and tonumber(zombie:getHealth()) <= 0 then
        return false
    end

    return true
end

local MAX_ZONE_TARGET_SAMPLES = 6

local function insertNearestZoneTarget(samples, zombie, referenceX, referenceY, referenceZ)
    if type(samples) ~= "table" or not zombie then
        return
    end

    local dx = (tonumber(zombie:getX()) or 0) - (tonumber(referenceX) or 0)
    local dy = (tonumber(zombie:getY()) or 0) - (tonumber(referenceY) or 0)
    local dz = (tonumber(zombie:getZ()) or 0) - (tonumber(referenceZ) or 0)
    local sample = {
        x = tonumber(zombie:getX()) or 0,
        y = tonumber(zombie:getY()) or 0,
        z = tonumber(zombie:getZ()) or 0,
        distanceSq = (dx * dx) + (dy * dy) + (dz * dz * 4),
    }

    local inserted = false
    for index = 1, #samples do
        local existing = samples[index]
        if sample.distanceSq < (existing and tonumber(existing.distanceSq) or math.huge) then
            table.insert(samples, index, sample)
            inserted = true
            break
        end
    end

    if not inserted then
        samples[#samples + 1] = sample
    end

    while #samples > MAX_ZONE_TARGET_SAMPLES do
        table.remove(samples)
    end
end

local function getStore(player, create)
    if not player then
        return nil
    end

    local modData = player:getModData()
    local store = modData[Quests.MODDATA_KEY]
    if not store and create then
        store = {
            version = Quests.STATE_VERSION,
            seq = 0,
            quests = {},
            trackedQuestID = nil,
            locatedQuestID = nil,
            locatorSuppressed = false,
            offerLedger = {},
            proceduralOfferCache = {},
            proceduralOfferHistory = {},
            chainProgress = {},
            ambientOfferState = {},
            uiEventSeq = 0,
            uiEvents = {},
        }
        modData[Quests.MODDATA_KEY] = store
    end

    if store then
        store.version = Quests.STATE_VERSION
        store.seq = tonumber(store.seq) or 0
        store.quests = type(store.quests) == "table" and store.quests or {}
        store.trackedQuestID = store.trackedQuestID and tostring(store.trackedQuestID) or nil
        store.locatedQuestID = store.locatedQuestID and tostring(store.locatedQuestID) or nil
        store.locatorSuppressed = store.locatorSuppressed == true
        store.offerLedger = type(store.offerLedger) == "table" and store.offerLedger or {}
        store.proceduralOfferCache = type(store.proceduralOfferCache) == "table" and store.proceduralOfferCache or {}
        store.proceduralOfferHistory = type(store.proceduralOfferHistory) == "table" and store.proceduralOfferHistory or {}
        store.chainProgress = type(store.chainProgress) == "table" and store.chainProgress or {}
        store.ambientOfferState = type(store.ambientOfferState) == "table" and store.ambientOfferState or {}
        store.uiEventSeq = math.max(0, math.floor(tonumber(store.uiEventSeq) or 0))
        store.uiEvents = type(store.uiEvents) == "table" and store.uiEvents or {}
    end

    return store
end

local function normalizeLocation(location)
    if type(location) ~= "table" then
        return nil
    end

    return {
        x = math.floor(tonumber(location.x) or 0),
        y = math.floor(tonumber(location.y) or 0),
        z = math.floor(tonumber(location.z) or 0),
        label = tostring(location.label or "Objective Site"),
        symbolID = tostring(location.symbolID or "DOQuestTarget"),
        worldIcon = tostring(location.worldIcon or "loot.png"),
        r = tonumber(location.r) or 1.0,
        g = tonumber(location.g) or 0.85,
        b = tonumber(location.b) or 0.2,
        a = tonumber(location.a) or 1.0,
        scale = tonumber(location.scale) or 1.0,
        radius = math.max(1, math.floor(tonumber(location.radius) or 45)),
        source = location.source,
        town = location.town,
        county = location.county,
    }
end

local function buildQuestContactLocation(raw, fallbackLabel, options)
    if type(raw) ~= "table" then
        return nil
    end

    local x = tonumber(raw.x)
    local y = tonumber(raw.y)
    if not x or not y then
        return nil
    end

    options = type(options) == "table" and options or {}
    return normalizeLocation({
        x = x,
        y = y,
        z = tonumber(raw.z) or 0,
        label = raw.label or raw.name or fallbackLabel or "Quest Contact",
        radius = raw.radius or options.radius or 8,
        symbolID = raw.symbolID or options.symbolID or "DOQuestTurnIn",
        worldIcon = raw.worldIcon or options.worldIcon or "friend.png",
        r = raw.r or options.r or 0.25,
        g = raw.g or options.g or 0.85,
        b = raw.b or options.b or 1.0,
        a = raw.a or options.a or 1.0,
        scale = raw.scale or options.scale or 1.0,
        town = raw.town,
        county = raw.county,
        source = raw.source,
    })
end

local function resolveQuestContactLocationForSoul(soul, fallbackLabel, options)
    if type(soul) ~= "table" then
        return nil
    end

    options = type(options) == "table" and options or {}
    local name = tostring(soul.name or fallbackLabel or "Quest Contact")
    local homeLabel = tostring(options.homeLabel or (name .. "'s Base"))

    local live = buildQuestContactLocation({
        x = soul.lastX or soul.x,
        y = soul.lastY or soul.y,
        z = soul.lastZ or soul.z,
        label = name,
    }, name, options)
    local home = buildQuestContactLocation(soul.homeCoords, homeLabel, options)

    if live and home then
        local preferHome = options.preferHome == true
        local status = string.lower(tostring(soul.status or soul.state or ""))
        local state = string.lower(tostring(soul.state or soul.status or ""))
        local shouldAnchorHome = preferHome
            or soul.abstractResident == true
            or status == "resting"
            or state == "resting"
            or status == "stationary"
            or state == "stationary"
            or status == "guarding"
            or state == "guarding"
            or status == "protecting"
            or state == "protecting"

        if not shouldAnchorHome then
            local maxDrift = math.max(0, tonumber(options.maxDrift) or 80)
            if maxDrift > 0 then
                local dx = tonumber(live.x) - tonumber(home.x)
                local dy = tonumber(live.y) - tonumber(home.y)
                shouldAnchorHome = ((dx * dx) + (dy * dy)) > (maxDrift * maxDrift)
            end
        end

        if shouldAnchorHome then
            return home
        end
    end

    return live or home
end

local function nextQuestID(player, store)
    store.seq = (tonumber(store.seq) or 0) + 1
    return string.format(
        "DOQ_%s_%d_%d",
        tostring(DO.GetPlayerKey(player)):gsub("[^%w_:%-]", "_"),
        tonumber(store.seq) or 0,
        math.floor(ZombRand(100000, 999999))
    )
end

local function buildFallbackDestination(player, purpose)
    if DO.Integration and DO.Integration.V2 and DO.Integration.V2.ResolveDebugDestination then
        return DO.Integration.V2.ResolveDebugDestination(player, purpose)
    end
    return nil
end

local function buildDebugRewardContext(location)
    if type(location) ~= "table" or not ModData or not ModData.get then
        return {}
    end

    local data = ModData.get("DynamicTrading_Factions")
    if type(data) ~= "table" then
        return {}
    end

    local bestID = nil
    local bestFaction = nil
    local bestDistance = nil
    local targetTown = location.town and tostring(location.town):lower() or ""
    for factionID, faction in pairs(data) do
        if type(faction) == "table" then
            local home = type(faction.homeCoords) == "table" and faction.homeCoords or nil
            local hx = home and tonumber(home.x) or nil
            local hy = home and tonumber(home.y) or nil
            if hx and hy then
                local dx = hx - (tonumber(location.x) or 0)
                local dy = hy - (tonumber(location.y) or 0)
                local distance = math.sqrt((dx * dx) + (dy * dy))
                local factionTown = faction.town and tostring(faction.town):lower() or ""
                local townBias = (targetTown ~= "" and factionTown == targetTown) and -250 or 0
                local score = distance + townBias
                if not bestDistance or score < bestDistance then
                    bestDistance = score
                    bestID = tostring(factionID)
                    bestFaction = faction
                end
            end
        end
    end

    if not bestID then
        return {}
    end

    return {
        factionID = bestID,
        factionName = bestFaction and tostring(bestFaction.name or bestID) or bestID,
    }
end

local function normalizeDifficulty(value)
    local difficulty = tonumber(value) or 1.0
    if difficulty <= 0 then
        return 1.0
    end
    return difficulty
end

local function getConfiguredQuestDifficulty()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeDifficulty(sandbox and sandbox.QuestDifficulty or 1.0)
end

local function normalizeExpirationMultiplier(value)
    local multiplier = tonumber(value)
    if multiplier == nil then
        return 1.0
    end
    if multiplier < 0 then
        return 0
    end
    return multiplier
end

local function getConfiguredQuestExpirationMultiplier()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeExpirationMultiplier(sandbox and sandbox.QuestExpirationMultiplier or 1.0)
end

local function normalizeChancePercent(value)
    local chance = tonumber(value)
    if chance == nil then
        return 0
    end
    return math.max(0, math.min(100, chance))
end

local function normalizeCountSetting(value, maxValue)
    local cap = math.max(0, math.floor(tonumber(maxValue) or 0))
    local count = math.floor(tonumber(value) or 0)
    return math.max(0, math.min(cap, count))
end

local function getConfiguredRestingContractChancePercent()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeChancePercent(sandbox and sandbox.RestingContractChancePercent or 70)
end

local function getConfiguredMinimumRestingFamiliesAvailable()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeCountSetting(sandbox and sandbox.MinimumRestingFamiliesAvailable or 3, 3)
end

local function getConfiguredEscortIncidentChancePercent()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeChancePercent(sandbox and sandbox.EscortIncidentChancePercent or 60)
end

local function getConfiguredMinimumEscortIncidents()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeCountSetting(sandbox and sandbox.MinimumEscortIncidents or 1, 3)
end

local function getConfiguredQuestRewardMinimumMoney()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return math.max(0, math.floor(tonumber(sandbox and sandbox.QuestRewardMinimumMoney) or 75))
end

local function rollChancePercent(chance)
    local pct = normalizeChancePercent(chance)
    if pct <= 0 then
        return false, 0
    end

    local roll = ZombRand(100)
    return roll < pct, roll
end

local function scaleQuestTimeLimit(baseHours, alreadyScaled)
    local hours = math.max(0, tonumber(baseHours) or 0)
    if alreadyScaled == true then
        return hours
    end
    if hours <= 0 then
        return 0
    end

    local scaled = hours * getConfiguredQuestExpirationMultiplier()
    if scaled <= 0 then
        return 0
    end
    return scaled
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return tonumber(gameTime:getWorldAgeHours()) or 0
    end
    return 0
end

local function isAuthoritativeContext()
    return isServer() or not isClient()
end

local function getObjectiveHookForQuest(quest)
    local hookID = quest and quest.hookId and tostring(quest.hookId) or nil
    if not hookID or not DO.GetObjectiveHook then
        return nil
    end
    return DO.GetObjectiveHook(hookID)
end

local function finalizeObjectiveHookQuest(player, quest, resolution, reason)
    local hook = getObjectiveHookForQuest(quest)
    if not hook then
        return false
    end

    local payload = {
        hookId = tostring(quest.hookId),
        incidentId = quest.hookIncidentId and tostring(quest.hookIncidentId) or nil,
        questID = quest.id and tostring(quest.id) or nil,
        resolution = tostring(resolution or "completed"),
        reason = reason and tostring(reason) or nil,
        traderId = quest.hookState and quest.hookState.traderId or nil,
    }

    if isAuthoritativeContext() and hook.finalizeQuest then
        return hook.finalizeQuest(player, payload) == true
    end

    if player and sendClientCommand then
        sendClientCommand(player, "DynamicObjectives", "FinalizeObjectiveHookQuest", payload)
        return true
    end

    return false
end

local function clampDifficulty(value)
    return math.max(0.5, math.min(100.0, normalizeDifficulty(value)))
end

local function getQuestDifficultyLabel(value)
    local difficulty = clampDifficulty(value)
    if difficulty >= 2.35 then
        return "Deadly"
    elseif difficulty >= 1.7 then
        return "Hard"
    elseif difficulty >= 1.15 then
        return "Standard"
    elseif difficulty >= 0.8 then
        return "Light"
    end
    return "Easy"
end

local function resolveQuestDifficulty(player, quest, location)
    local configured = getConfiguredQuestDifficulty()
    local explicitBase = quest and (quest.baseDifficulty or quest.questDifficulty or quest.difficulty) or nil
    local baseDifficulty = normalizeDifficulty(explicitBase or configured)

    if quest and quest.dynamicDifficulty == false then
        return clampDifficulty(baseDifficulty), {
            base = baseDifficulty,
            configured = configured,
            distanceFactor = 1.0,
            radiusFactor = 1.0,
            kindFactor = 1.0,
            randomFactor = 1.0,
        }
    end

    local distanceFactor = 1.0
    if player and location then
        local dx = (tonumber(location.x) or 0) - (tonumber(player:getX()) or 0)
        local dy = (tonumber(location.y) or 0) - (tonumber(player:getY()) or 0)
        local distance = math.sqrt((dx * dx) + (dy * dy))
        distanceFactor = 1.0 + math.min(0.55, distance / 1200)
    end

    local radius = location and math.max(1, tonumber(location.radius) or 45) or 45
    local radiusFactor = 1.0
    if radius <= 20 then
        radiusFactor = 1.18
    elseif radius <= 30 then
        radiusFactor = 1.1
    elseif radius >= 60 then
        radiusFactor = 0.92
    end

    local encounterKind = quest and quest.encounter and tostring(quest.encounter.kind or "") or ""
    local kindFactor = 1.0
    if encounterKind == "hunt_drop" then
        kindFactor = 1.12
    elseif encounterKind == "kill_zone" then
        kindFactor = 1.0
    elseif encounterKind ~= "" then
        kindFactor = 1.05
    end

    local randomFactor = ZombRand(82, 131) / 100
    local resolved = clampDifficulty(baseDifficulty * distanceFactor * radiusFactor * kindFactor * randomFactor)

    return resolved, {
        base = baseDifficulty,
        configured = configured,
        distanceFactor = distanceFactor,
        radiusFactor = radiusFactor,
        kindFactor = kindFactor,
        randomFactor = randomFactor,
    }
end

local function scaleCountForDifficulty(count, difficulty)
    local baseCount = math.max(1, math.floor(tonumber(count) or 1))
    local scale = normalizeDifficulty(difficulty)
    return math.max(1, math.floor((baseCount * scale) + 0.5))
end

local function normalizeText(value)
    return string.lower(tostring(value or ""))
end

local function matchesNormalizedList(value, list)
    if type(list) ~= "table" or #list == 0 then
        return true
    end

    local probe = normalizeText(value)
    for _, candidate in ipairs(list) do
        local normalized = normalizeText(candidate)
        if normalized == "" or normalized == "*" or normalized == "any" or normalized == probe then
            return true
        end
    end

    return false
end


Runtime.questLog = questLog
Runtime.say = say
Runtime.isZombie = isZombie
Runtime.isLivingZombie = isLivingZombie
Runtime.insertNearestZoneTarget = insertNearestZoneTarget
Runtime.getStore = getStore
Runtime.normalizeLocation = normalizeLocation
Runtime.resolveQuestContactLocationForSoul = resolveQuestContactLocationForSoul
Runtime.nextQuestID = nextQuestID
Runtime.buildFallbackDestination = buildFallbackDestination
Runtime.buildDebugRewardContext = buildDebugRewardContext
Runtime.normalizeDifficulty = normalizeDifficulty
Runtime.getConfiguredQuestDifficulty = getConfiguredQuestDifficulty
Runtime.normalizeExpirationMultiplier = normalizeExpirationMultiplier
Runtime.getConfiguredQuestExpirationMultiplier = getConfiguredQuestExpirationMultiplier
Runtime.normalizeChancePercent = normalizeChancePercent
Runtime.normalizeCountSetting = normalizeCountSetting
Runtime.getConfiguredRestingContractChancePercent = getConfiguredRestingContractChancePercent
Runtime.getConfiguredMinimumRestingFamiliesAvailable = getConfiguredMinimumRestingFamiliesAvailable
Runtime.getConfiguredEscortIncidentChancePercent = getConfiguredEscortIncidentChancePercent
Runtime.getConfiguredMinimumEscortIncidents = getConfiguredMinimumEscortIncidents
Runtime.getConfiguredQuestRewardMinimumMoney = getConfiguredQuestRewardMinimumMoney
Runtime.rollChancePercent = rollChancePercent
Runtime.scaleQuestTimeLimit = scaleQuestTimeLimit
Runtime.getWorldAgeHours = getWorldAgeHours
Runtime.isAuthoritativeContext = isAuthoritativeContext
Runtime.clampDifficulty = clampDifficulty
Runtime.getQuestDifficultyLabel = getQuestDifficultyLabel
Runtime.resolveQuestDifficulty = resolveQuestDifficulty
Runtime.scaleCountForDifficulty = scaleCountForDifficulty
Runtime.normalizeText = normalizeText
Runtime.matchesNormalizedList = matchesNormalizedList
Runtime.getObjectiveHookForQuest = getObjectiveHookForQuest
Runtime.finalizeObjectiveHookQuest = finalizeObjectiveHookQuest
