DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests

Quests.MODDATA_KEY = Quests.MODDATA_KEY or "DynamicObjectives"
Quests.STATE_VERSION = Quests.STATE_VERSION or 2

local questUpdateTick = 0

local function questLog(category, topic, message)
    DO.Log(category, topic, message)
end

local function say(player, text)
    if player and player.Say then
        player:Say(tostring(text))
    end
end

local function isZombie(value)
    return value and instanceof and instanceof(value, "IsoZombie")
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
        }
        modData[Quests.MODDATA_KEY] = store
    end

    if store and create then
        store.version = Quests.STATE_VERSION
        store.seq = tonumber(store.seq) or 0
        store.quests = type(store.quests) == "table" and store.quests or {}
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

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return tonumber(gameTime:getWorldAgeHours()) or 0
    end
    return 0
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

local function normalizeEncounter(quest, encounter)
    if type(encounter) ~= "table" then
        return nil
    end

    local location = normalizeLocation(encounter.location or quest.targetLocation)
    local difficulty = normalizeDifficulty(encounter.difficulty or (quest and quest.difficulty) or 1.0)
    local baseCount = math.max(1, math.floor(tonumber(encounter.baseCount or encounter.count) or 1))
    local count = scaleCountForDifficulty(baseCount, difficulty)
    local spawnRadius = math.max(4, math.floor(tonumber(encounter.spawnRadius or (location and location.radius) or 18)))
    local clearRadius = math.max(spawnRadius, math.floor(tonumber(encounter.clearRadius or (location and location.radius) or spawnRadius)))

    return {
        id = tostring(encounter.id or "encounter_main"),
        kind = tostring(encounter.kind or "kill_zone"),
        difficulty = difficulty,
        baseCount = baseCount,
        count = count,
        spawnedCount = math.max(0, math.floor(tonumber(encounter.spawnedCount) or 0)),
        spawned = encounter.spawned == true,
        spawnRequested = encounter.spawnRequested == true,
        spawnedAt = tonumber(encounter.spawnedAt) or nil,
        lastSpawnAttemptAt = tonumber(encounter.lastSpawnAttemptAt) or nil,
        location = location,
        spawnRadius = spawnRadius,
        clearRadius = clearRadius,
        spawnMode = tostring(encounter.spawnMode or "building"),
        activationRadius = math.max(
            18,
            math.floor(tonumber(encounter.activationRadius) or math.max(clearRadius + 10, spawnRadius + 18))
        ),
        requirePlayerPresence = encounter.requirePlayerPresence ~= false,
        requireAreaClear = encounter.requireAreaClear ~= false,
        questOnlyKills = encounter.questOnlyKills ~= false,
        outfit = encounter.outfit and tostring(encounter.outfit) or nil,
        femaleChance = tonumber(encounter.femaleChance) or 50,
    }
end

local function normalizeObjective(index, quest, objective)
    local normalized = DO.DeepCopy(objective or {})
    normalized.id = tostring(normalized.id or ("objective_" .. tostring(index)))
    normalized.type = tostring(normalized.type or "kill")
    normalized.label = tostring(normalized.label or normalized.id)
    normalized.requiredBase = math.max(1, math.floor(tonumber(normalized.requiredBase or normalized.required) or 1))
    normalized.required = normalized.requiredBase
    normalized.progress = math.max(0, math.floor(tonumber(normalized.progress) or 0))
    normalized.completed = normalized.completed == true
    normalized.radius = math.max(
        1,
        math.floor(tonumber(normalized.radius or normalized.zoneRadius or (quest.targetLocation and quest.targetLocation.radius)) or 45)
    )
    normalized.targetLocation = normalizeLocation(normalized.targetLocation)
    normalized.dropState = type(normalized.dropState) == "table" and normalized.dropState or {}
    normalized.spawnAfterKillsBase = math.max(
        1,
        math.floor(tonumber(normalized.spawnAfterKillsBase or normalized.spawnAfterKills) or normalized.requiredBase)
    )
    normalized.spawnAfterKills = normalized.spawnAfterKillsBase
    normalized.dropItemType = normalized.dropItemType and tostring(normalized.dropItemType) or nil
    normalized.consumeOnComplete = normalized.consumeOnComplete == true
    normalized.killProgress = math.max(0, math.floor(tonumber(normalized.killProgress) or 0))
    normalized.requireAreaClear = normalized.requireAreaClear == true or (quest.encounter and quest.encounter.requireAreaClear == true)
    normalized.encounterOnly = normalized.encounterOnly ~= false and quest.encounter ~= nil
    normalized.questItemType = normalized.questItemType and tostring(normalized.questItemType) or nil
    normalized.completeQuestOnComplete = normalized.completeQuestOnComplete == true
    normalized.completeRemainingObjectives = normalized.completeRemainingObjectives == true or normalized.completeQuestOnComplete == true
    return normalized
end

local function syncEncounterObjectiveCounts(quest)
    if not quest or not quest.encounter then
        return
    end

    local encounterBaseCount = math.max(1, math.floor(tonumber(quest.encounter.baseCount or quest.encounter.count) or 1))
    local encounterCount = math.max(1, math.floor(tonumber(quest.encounter.count) or 1))
    local encounterScale = encounterCount / encounterBaseCount
    for _, objective in ipairs(quest.objectives or {}) do
        if objective.type == "kill" and objective.encounterOnly == true then
            objective.required = encounterCount
            objective.progress = math.min(objective.required, tonumber(objective.progress) or 0)
            objective.completed = objective.progress >= objective.required
        elseif objective.type == "obtainDrop" then
            local baseKills = math.max(1, math.floor(tonumber(objective.spawnAfterKillsBase or objective.spawnAfterKills) or 1))
            objective.spawnAfterKills = math.min(
                encounterCount,
                math.max(1, math.floor((baseKills * encounterScale) + 0.5))
            )
        end
    end
end

local function questLocationFor(quest, objective)
    if objective and objective.targetLocation then
        return objective.targetLocation
    end

    if quest and quest.encounter and quest.encounter.location then
        return quest.encounter.location
    end

    return quest and quest.targetLocation or nil
end

local function isWithinLocation(location, x, y, z)
    if not location then
        return true
    end

    if z ~= nil and tonumber(location.z or 0) ~= tonumber(z or 0) then
        return false
    end

    local dx = (tonumber(x) or 0) - (tonumber(location.x) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(location.y) or 0)
    local radius = math.max(1, tonumber(location.radius) or 45)
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function isWithinRadius(location, radius, x, y, z)
    if not location then
        return true
    end

    if z ~= nil and tonumber(location.z or 0) ~= tonumber(z or 0) then
        return false
    end

    local dx = (tonumber(x) or 0) - (tonumber(location.x) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(location.y) or 0)
    local targetRadius = math.max(1, tonumber(radius) or tonumber(location.radius) or 45)
    return (dx * dx + dy * dy) <= (targetRadius * targetRadius)
end

local function objectivesComplete(quest)
    for _, objective in ipairs(quest.objectives or {}) do
        if objective.completed ~= true then
            return false
        end
    end
    return true
end

local function findQuest(store, questID)
    if not store or not questID then
        return nil
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.id == questID then
            return quest
        end
    end

    return nil
end

local function resolveTrackedQuest(player, store)
    if not store then
        return nil
    end

    local tracked = findQuest(store, store.trackedQuestID)
    if tracked and tracked.status == "active" then
        for _, quest in ipairs(store.quests or {}) do
            quest.tracked = quest.id == tracked.id
        end
        return tracked
    end

    store.trackedQuestID = nil
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            store.trackedQuestID = quest.id
            tracked = quest
            break
        end
    end

    for _, quest in ipairs(store.quests or {}) do
        quest.tracked = tracked and quest.id == tracked.id or false
    end

    return tracked
end

local function onQuestStateChanged(player)
    DO.NotifyStateChanged(player)
end

local function removeQuestItemByQuestID(player, questID)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.IsQuestItem == true and modData.QuestID == questID
    end)

    for _, item in ipairs(items) do
        Quests.RemoveInventoryItem(item)
    end
end

local function removeQuestDropsByQuestID(player, questID)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.DOQuestDrop == true and modData.DOQuestID == questID
    end)

    for _, item in ipairs(items) do
        Quests.RemoveInventoryItem(item)
    end
end

local function markObjectiveCompleted(objective)
    if not objective then
        return false
    end

    local required = math.max(1, math.floor(tonumber(objective.required) or 1))
    local changed = objective.completed ~= true or tonumber(objective.progress) ~= required
    objective.progress = required
    objective.completed = true
    return changed
end

local function completeObjectivesAfter(quest, objectiveID)
    if not quest or not objectiveID then
        return false
    end

    local found = false
    local changed = false
    for _, objective in ipairs(quest.objectives or {}) do
        if found then
            changed = markObjectiveCompleted(objective) or changed
        elseif objective.id == objectiveID then
            found = true
        end
    end

    return changed
end

local function countObjectiveDropItems(player, questID, objectiveID)
    local playerKey = DO.GetPlayerKey(player)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData
            and modData.DOQuestDrop == true
            and modData.DOQuestID == questID
            and modData.DOQuestObjectiveID == objectiveID
            and (not modData.DOQuestPlayerKey or modData.DOQuestPlayerKey == playerKey)
    end)

    return #items, items
end

local function isQuestEncounterZombie(player, quest, zombie)
    local modData = zombie and zombie:getModData() or nil
    if not modData or not quest then
        return false
    end

    return modData.DOQuestSpawn == true
        and modData.DOQuestEncounterQuestID == quest.id
        and modData.DOQuestEncounterPlayerKey == DO.GetPlayerKey(player)
end

local function doesZombieMatchEncounter(player, quest, zombie, objective)
    if not objective or objective.encounterOnly ~= true then
        return true
    end

    local encounter = quest and quest.encounter or nil
    if not encounter or encounter.questOnlyKills ~= true then
        return true
    end

    return isQuestEncounterZombie(player, quest, zombie)
end

local function gatherLiveZoneState(player, quest, objective)
    local location = questLocationFor(quest, objective)
    local encounter = quest and quest.encounter or nil
    local clearRadius = encounter and encounter.clearRadius or (location and location.radius) or 45
    local playerPresent = false
    local nearbyCount = 0

    if player and location then
        playerPresent = isWithinRadius(location, clearRadius + 8, player:getX(), player:getY(), player:getZ())
    end

    local cell = getCell and getCell() or nil
    local zombieList = cell and cell.getZombieList and cell:getZombieList() or nil
    if zombieList and location then
        for index = 0, zombieList:size() - 1 do
            local zombie = zombieList:get(index)
            if isLivingZombie(zombie)
                and isWithinRadius(location, clearRadius, zombie:getX(), zombie:getY(), zombie:getZ())
            then
                nearbyCount = nearbyCount + 1
            end
        end
    end

    local areaClear = nearbyCount <= 0
    if encounter and encounter.requirePlayerPresence == true and not playerPresent then
        areaClear = false
    end
    if encounter and encounter.spawned ~= true then
        areaClear = false
    end

    return {
        location = location,
        clearRadius = clearRadius,
        nearbyZombies = nearbyCount,
        playerPresent = playerPresent,
        areaClear = areaClear,
        encounterSpawned = encounter and encounter.spawned == true or false,
    }
end

local function getPendingObjective(quest)
    if not quest then
        return nil
    end

    for _, objective in ipairs(quest.objectives or {}) do
        if objective.completed ~= true then
            return objective
        end
    end

    return quest.objectives and quest.objectives[#quest.objectives] or nil
end

local function questRequiresAreaClear(quest)
    if quest and quest.skipAreaClear == true then
        return false
    end

    if quest and quest.encounter and quest.encounter.requireAreaClear == true then
        return true
    end

    for _, objective in ipairs(quest and quest.objectives or {}) do
        if objective.requireAreaClear == true then
            return true
        end
    end

    return false
end

local function buildAreaClearText(zoneState)
    if not zoneState then
        return nil
    end

    if zoneState.encounterSpawned ~= true then
        if zoneState.playerPresent == true then
            return "Searching the building..."
        end
        return "Move closer to trigger the encounter"
    end

    if zoneState.areaClear == true then
        return "Area secure"
    end

    if zoneState.playerPresent ~= true then
        return "Return to the marked zone"
    end

    return string.format("Nearby zeds: %d", math.max(0, tonumber(zoneState.nearbyZombies) or 0))
end

local function getQuestRemainingHours(quest)
    if not quest or tonumber(quest.timeLimitHours) == nil or tonumber(quest.timeLimitHours) <= 0 then
        return nil
    end

    local expiresAt = tonumber(quest.expiresAtWorldHours)
    if not expiresAt then
        return nil
    end

    return math.max(0, expiresAt - getWorldAgeHours())
end

function Quests.GetStore(player, create)
    return getStore(player, create)
end

function Quests.GetActiveQuests(player)
    local store = getStore(player, false)
    if not store then
        return {}
    end

    local results = {}
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = quest
        end
    end

    return results
end

function Quests.GetTrackedQuest(player)
    local store = getStore(player, false)
    if not store then
        return nil
    end

    return resolveTrackedQuest(player, store)
end

function Quests.GetQuest(player, questID)
    local store = getStore(player, false)
    return findQuest(store, questID)
end

function Quests.GetEncounterStatus(player, quest)
    if not player or not quest or quest.status ~= "active" or not questRequiresAreaClear(quest) then
        return nil
    end

    return gatherLiveZoneState(player, quest, getPendingObjective(quest))
end

function Quests.GetTrackedMarkerData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    local location = quest.targetLocation
    if not location then
        return nil
    end

    return {
        questID = quest.id,
        name = quest.name,
        description = tostring(location.label or quest.name or "Tracked Objective"),
        x = location.x,
        y = location.y,
        z = location.z,
        symbolID = location.symbolID or "DOQuestTarget",
        worldIcon = location.worldIcon or "loot.png",
        r = location.r,
        g = location.g,
        b = location.b,
        a = location.a,
        scale = location.scale,
    }
end

function Quests.BuildSummaryText(quest, player)
    local parts = {}
    for _, objective in ipairs(quest.objectives or {}) do
        local progress = math.max(0, math.floor(tonumber(objective.progress) or 0))
        local required = math.max(1, math.floor(tonumber(objective.required) or 1))
        parts[#parts + 1] = string.format("%s %d/%d", tostring(objective.label or objective.type), progress, required)
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    if zoneState then
        parts[#parts + 1] = buildAreaClearText(zoneState)
    end

    local remainingHours = getQuestRemainingHours(quest)
    if remainingHours ~= nil then
        parts[#parts + 1] = string.format("Time left %.1fh", remainingHours)
    end

    if quest.rewardPreview and quest.rewardPreview ~= "" then
        parts[#parts + 1] = "Rewards " .. tostring(quest.rewardPreview)
    end

    local suffix = quest.tracked and " [Tracked]" or ""
    return string.format("%s%s - %s", tostring(quest.name or quest.id), suffix, table.concat(parts, " | "))
end

function Quests.GetActiveQuestSummary(player)
    local results = {}
    local store = getStore(player, false)
    if not store then
        return results
    end

    resolveTrackedQuest(player, store)

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = {
                questID = quest.id,
                name = quest.name,
                tracked = quest.tracked == true,
                display = Quests.BuildSummaryText(quest, player),
                targetLabel = quest.targetLocation and quest.targetLocation.label or nil,
            }
        end
    end

    return results
end

function Quests.GetTrackedObjectiveUIData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    local lines = {}
    local totalSteps = #(quest.objectives or {})
    local currentStep = totalSteps > 0 and totalSteps or 1
    local currentObjective = nil
    local activeKillObjective = nil
    local currentObjectiveLabel = nil

    for index, objective in ipairs(quest.objectives or {}) do
        if not currentObjective and objective.completed ~= true then
            currentObjective = objective
            currentStep = index
            currentObjectiveLabel = tostring(objective.label or objective.id)
        end

        if not activeKillObjective and objective.type == "kill" and objective.completed ~= true then
            activeKillObjective = objective
        end

        local progress = math.max(0, tonumber(objective.progress) or 0)
        local required = math.max(1, tonumber(objective.required) or 1)
        local line = {
            id = objective.id,
            label = tostring(objective.label or objective.type),
            completed = objective.completed == true,
            current = objective.completed ~= true and currentObjective and currentObjective.id == objective.id,
            objectiveType = objective.type,
            progress = progress,
            required = required,
            remaining = math.max(0, required - progress),
        }

        if objective.type == "kill" then
            line.value = string.format(
                "%d / %d zombies",
                progress,
                required
            )
        elseif objective.type == "obtainDrop" then
            if objective.completed == true then
                line.value = "Recovered"
            else
                line.value = objective.dropState and objective.dropState.spawned and "Loot the marked corpse drop" or "Keep clearing the zone"
            end
        elseif objective.type == "deliverItem" then
            line.value = objective.completed == true and "Delivered" or "Take the package to the marker"
        else
            line.value = string.format("%d / %d", tonumber(objective.progress) or 0, tonumber(objective.required) or 0)
        end

        lines[#lines + 1] = line
    end

    if zoneState then
        local zoneCurrent = currentObjective == nil and zoneState.areaClear ~= true
        lines[#lines + 1] = {
            id = "zone_clear",
            label = "Secure the building",
            value = buildAreaClearText(zoneState),
            completed = zoneState.areaClear == true,
            accent = zoneState.areaClear == true and "good" or "warn",
            current = zoneCurrent,
        }
        totalSteps = totalSteps + 1
        if zoneCurrent then
            currentStep = totalSteps
            currentObjectiveLabel = "Secure the building"
        end
    end

    if not currentObjective then
        currentObjective = quest.objectives and quest.objectives[#quest.objectives] or nil
    end

    local primaryProgress = nil
    if activeKillObjective then
        local killProgress = math.max(0, tonumber(activeKillObjective.progress) or 0)
        local killRequired = math.max(1, tonumber(activeKillObjective.required) or 1)
        primaryProgress = {
            label = "Zombies Cleared",
            value = string.format("%d / %d", killProgress, killRequired),
            detail = string.format("%d remaining", math.max(0, killRequired - killProgress)),
            ratio = killProgress / killRequired,
            color = { r = 0.86, g = 0.28, b = 0.22 },
        }
        if quest.encounter and quest.encounter.spawned ~= true then
            primaryProgress.detail = zoneState and buildAreaClearText(zoneState) or "Move closer to trigger the encounter"
            primaryProgress.ratio = 0
        end
    elseif zoneState then
        primaryProgress = {
            label = "Zone Status",
            value = zoneState.areaClear == true and "Secure" or "Active",
            detail = buildAreaClearText(zoneState),
            ratio = zoneState.areaClear == true and 1 or 0,
            color = zoneState.areaClear == true and { r = 0.34, g = 0.82, b = 0.48 } or { r = 0.95, g = 0.62, b = 0.18 },
        }
    end

    return {
        questID = quest.id,
        name = tostring(quest.name or quest.id),
        targetLabel = quest.targetLocation and tostring(quest.targetLocation.label or "") or "",
        targetLocation = quest.targetLocation,
        difficulty = normalizeDifficulty(quest.difficulty),
        rewardPreview = quest.rewardPreview and tostring(quest.rewardPreview) or nil,
        timeLimitHours = tonumber(quest.timeLimitHours) or 0,
        timeRemainingHours = getQuestRemainingHours(quest),
        currentStep = currentStep,
        totalSteps = math.max(1, totalSteps),
        currentObjectiveLabel = currentObjectiveLabel
            or (currentObjective and tostring(currentObjective.label or currentObjective.id))
            or "Objective",
        difficultyLabel = tostring(quest.difficultyLabel or getQuestDifficultyLabel(quest.difficulty)),
        primaryProgress = primaryProgress,
        lines = lines,
        zoneState = zoneState,
        encounter = quest.encounter,
    }
end

function Quests.GetLatestCompletedQuest(player)
    local store = getStore(player, false)
    if not store then
        return nil
    end

    local latest = nil
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "completed" and tonumber(quest.completedAt) then
            if not latest or tonumber(quest.completedAt) > tonumber(latest.completedAt or 0) then
                latest = quest
            end
        end
    end

    return latest
end

function Quests.SetTrackedQuest(player, questID)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local tracked = findQuest(store, questID)
    if not tracked or tracked.status ~= "active" then
        return false
    end

    store.trackedQuestID = tracked.id
    for _, quest in ipairs(store.quests or {}) do
        quest.tracked = quest.id == tracked.id
    end

    say(player, "Tracking objective: " .. tostring(tracked.name))
    onQuestStateChanged(player)
    return true
end

function Quests.AbandonQuest(player, questID)
    local store = getStore(player, true)
    if not store then
        return false
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.id == questID and quest.status == "active" then
            quest.status = "abandoned"
            quest.tracked = false
            quest.abandonedAt = DO.NowMs()
            removeQuestItemByQuestID(player, quest.id)
            removeQuestDropsByQuestID(player, quest.id)
            if store.trackedQuestID == quest.id then
                store.trackedQuestID = nil
            end
            resolveTrackedQuest(player, store)
            say(player, "Objective abandoned: " .. tostring(quest.name))
            onQuestStateChanged(player)
            return true
        end
    end

    return false
end

function Quests.CompleteQuest(player, questID, reason)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local quest = findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    if DO.Rewards and DO.Rewards.GrantQuestRewards then
        DO.Rewards.GrantQuestRewards(player, quest)
    end

    quest.status = "completed"
    quest.tracked = false
    quest.completedAt = DO.NowMs()
    quest.completionReason = reason or "completed"

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end

    resolveTrackedQuest(player, store)
    say(player, "Objective complete: " .. tostring(quest.name))
    onQuestStateChanged(player)
    return true
end

function Quests.FailQuest(player, questID, reason)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local quest = findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    quest.status = "failed"
    quest.tracked = false
    quest.failedAt = DO.NowMs()
    quest.failureReason = reason or "failed"

    removeQuestItemByQuestID(player, quest.id)
    removeQuestDropsByQuestID(player, quest.id)

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end

    resolveTrackedQuest(player, store)
    say(player, "Objective failed: " .. tostring(quest.name))
    onQuestStateChanged(player)
    return true
end

local function applyEncounterSpawnResult(quest, spawnedCount)
    if not quest or not quest.encounter then
        return
    end

    local encounter = quest.encounter
    encounter.lastSpawnAttemptAt = DO.NowMs()
    encounter.spawnedCount = math.max(0, math.floor(tonumber(spawnedCount) or 0))
    if encounter.spawnedCount > 0 then
        encounter.spawned = true
        encounter.spawnRequested = false
        encounter.spawnedAt = encounter.spawnedAt or encounter.lastSpawnAttemptAt
        encounter.count = encounter.spawnedCount
        syncEncounterObjectiveCounts(quest)
    else
        encounter.spawned = false
        encounter.spawnRequested = false
    end
end

function Quests.ApplyEncounterSpawnResult(player, questID, spawnedCount)
    local quest = Quests.GetQuest(player, questID)
    if not quest then
        return false
    end

    applyEncounterSpawnResult(quest, spawnedCount)
    onQuestStateChanged(player)
    return true
end

local function getSquareAt(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
end

local function getBuildingKey(building)
    local def = building and building.getDef and building:getDef() or nil
    if def and def.getKeyId then
        return tostring(def:getKeyId())
    end
    return nil
end

local function resolveSpawnBuilding(location)
    if not location then
        return nil
    end

    local directSquare = getSquareAt(location.x, location.y, location.z)
    if directSquare and directSquare.getBuilding then
        local building = directSquare:getBuilding()
        if building then
            return building
        end
    end

    local searchRadius = 4
    local bestBuilding = nil
    local bestDistanceSq = nil
    local baseX = math.floor(tonumber(location.x) or 0)
    local baseY = math.floor(tonumber(location.y) or 0)
    local baseZ = math.floor(tonumber(location.z) or 0)

    for dx = -searchRadius, searchRadius do
        for dy = -searchRadius, searchRadius do
            local square = getSquareAt(baseX + dx, baseY + dy, baseZ)
            local building = square and square.getBuilding and square:getBuilding() or nil
            if building then
                local distanceSq = (dx * dx) + (dy * dy)
                if not bestDistanceSq or distanceSq < bestDistanceSq then
                    bestBuilding = building
                    bestDistanceSq = distanceSq
                end
            end
        end
    end

    return bestBuilding
end

local function isValidSpawnSquare(square, buildingKey)
    if not square then
        return false
    end

    if square.isSolid and square:isSolid() then
        return false
    end

    if square.isSolidTrans and square:isSolidTrans() then
        return false
    end

    if buildingKey then
        if not square.getRoom or not square:getRoom() then
            return false
        end

        local building = square.getBuilding and square:getBuilding() or nil
        if getBuildingKey(building) ~= buildingKey then
            return false
        end
    end

    return true
end

local function buildZSearchOrder(baseZ)
    local order = {}
    local seen = {}
    local function add(z)
        z = math.floor(tonumber(z) or 0)
        if z < 0 or z > 7 or seen[z] then
            return
        end
        seen[z] = true
        order[#order + 1] = z
    end

    add(baseZ)
    add(baseZ + 1)
    add(baseZ - 1)

    for z = 0, 7 do
        add(z)
    end

    return order
end

local function findSpawnPointInBuilding(location, building)
    local def = building and building.getDef and building:getDef() or nil
    if not def then
        return nil
    end

    local minX = math.floor(tonumber(def:getX()) or 0)
    local minY = math.floor(tonumber(def:getY()) or 0)
    local width = math.max(1, math.floor(tonumber(def:getW()) or 1))
    local height = math.max(1, math.floor(tonumber(def:getH()) or 1))
    local maxX = minX + width - 1
    local maxY = minY + height - 1
    local buildingKey = getBuildingKey(building)
    local zOrder = buildZSearchOrder(location and location.z or 0)

    for _ = 1, 80 do
        local x = ZombRand(minX, maxX + 1)
        local y = ZombRand(minY, maxY + 1)
        local z = zOrder[ZombRand(0, #zOrder) + 1]
        local square = getSquareAt(x, y, z)
        if isValidSpawnSquare(square, buildingKey) then
            return x, y, z
        end
    end

    for _, z in ipairs(zOrder) do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = getSquareAt(x, y, z)
                if isValidSpawnSquare(square, buildingKey) then
                    return x, y, z
                end
            end
        end
    end

    return nil
end

local function findSpawnPoint(location, radius, spawnMode)
    local cell = getCell and getCell() or nil
    if not cell or not location then
        return location and location.x or 0, location and location.y or 0, location and location.z or 0, "fallback"
    end

    if spawnMode ~= "zone" then
        local building = resolveSpawnBuilding(location)
        if building then
            local spawnX, spawnY, spawnZ = findSpawnPointInBuilding(location, building)
            if spawnX ~= nil and spawnY ~= nil then
                return spawnX, spawnY, spawnZ, "building"
            end
        end
    end

    local z = tonumber(location.z) or 0
    local maxRadius = math.max(2, math.floor(tonumber(radius) or tonumber(location.radius) or 10))

    for _ = 1, 25 do
        local x = ZombRand(math.floor(location.x - maxRadius), math.floor(location.x + maxRadius + 1))
        local y = ZombRand(math.floor(location.y - maxRadius), math.floor(location.y + maxRadius + 1))
        local square = cell:getGridSquare(x, y, z)
        if square and not square:isSolid() and not square:isSolidTrans() then
            return x, y, z, "zone"
        end
    end

    return location.x, location.y, z, "fallback"
end

local function stampQuestSpawn(zombie, player, quest, encounter)
    if not zombie or not player or not quest then
        return
    end

    local modData = zombie:getModData()
    modData.DOQuestSpawn = true
    modData.DOQuestEncounterQuestID = quest.id
    modData.DOQuestEncounterID = encounter and encounter.id or "encounter_main"
    modData.DOQuestEncounterPlayerKey = DO.GetPlayerKey(player)
end

function Quests.SpawnQuestEncounterFromData(player, data)
    if not player or type(data) ~= "table" then
        return 0
    end

    local location = normalizeLocation(data.location)
    if not location or not addZombiesInOutfit then
        return 0
    end

    local count = math.max(1, math.floor(tonumber(data.count) or 1))
    local outfit = data.outfit and tostring(data.outfit) or nil
    local femaleChance = tonumber(data.femaleChance) or 50
    local spawnRadius = math.max(4, math.floor(tonumber(data.spawnRadius) or tonumber(location.radius) or 12))
    local spawnMode = tostring(data.spawnMode or "building")
    local spawnedCount = 0
    local usedMode = "fallback"

    local quest = {
        id = tostring(data.questID or "unknown"),
    }
    local encounter = {
        id = tostring(data.encounterID or "encounter_main"),
    }

    for _ = 1, count do
        local spawnX, spawnY, spawnZ, resolvedMode = findSpawnPoint(location, spawnRadius, spawnMode)
        local zombieList = addZombiesInOutfit(spawnX, spawnY, spawnZ, 1, outfit, femaleChance)
        if zombieList and zombieList.size and zombieList:size() > 0 then
            local zombie = zombieList:get(0)
            stampQuestSpawn(zombie, player, quest, encounter)
            spawnedCount = spawnedCount + 1
            usedMode = resolvedMode or usedMode
        end
    end

    questLog(
        "Quest",
        "Spawn",
        "Spawned encounter for " .. tostring(data.questID) .. " count=" .. tostring(spawnedCount) .. " mode=" .. tostring(usedMode)
    )
    return spawnedCount
end

function Quests.RequestEncounterSpawn(player, quest)
    if not player or not quest or not quest.encounter then
        return false
    end

    if quest.encounter.spawned == true or quest.encounter.spawnRequested == true then
        return false
    end

    quest.encounter.spawnRequested = true
    quest.encounter.lastSpawnAttemptAt = DO.NowMs()

    local payload = {
        questID = quest.id,
        encounterID = quest.encounter.id,
        count = quest.encounter.count,
        outfit = quest.encounter.outfit,
        femaleChance = quest.encounter.femaleChance,
        spawnRadius = quest.encounter.spawnRadius,
        spawnMode = quest.encounter.spawnMode,
        location = quest.encounter.location or quest.targetLocation,
    }

    if isClient() and not isServer() then
        sendClientCommand(player, "DynamicObjectives", "SpawnQuestEncounter", payload)
        return true
    end

    local spawnedCount = Quests.SpawnQuestEncounterFromData(player, payload)
    applyEncounterSpawnResult(quest, spawnedCount)
    return true
end

local function isEncounterActivationReady(player, quest)
    local encounter = quest and quest.encounter or nil
    local location = encounter and (encounter.location or quest.targetLocation) or nil
    if not player or not encounter or encounter.spawned == true or not location then
        return false
    end

    local activationRadius = math.max(18, tonumber(encounter.activationRadius) or 50)
    if not isWithinRadius(location, activationRadius, player:getX(), player:getY(), player:getZ()) then
        return false
    end

    if not getSquareAt(location.x, location.y, location.z) and not resolveSpawnBuilding(location) then
        return false
    end

    return true
end

function Quests.StartQuest(player, spec)
    if not player or type(spec) ~= "table" then
        return nil
    end

    local store = getStore(player, true)
    if not store then
        return nil
    end

    local quest = DO.DeepCopy(spec)
    quest.id = quest.id or nextQuestID(player, store)
    quest.name = tostring(quest.name or quest.id)
    quest.status = "active"
    quest.createdAt = DO.NowMs()
    quest.startedAtWorldHours = getWorldAgeHours()
    quest.playerKey = DO.GetPlayerKey(player)
    quest.targetLocation = normalizeLocation(quest.targetLocation or buildFallbackDestination(player, quest.name))
    quest.baseDifficulty = normalizeDifficulty(quest.baseDifficulty or quest.questDifficulty or quest.difficulty or getConfiguredQuestDifficulty())
    quest.difficulty, quest.difficultyFactors = resolveQuestDifficulty(player, quest, quest.targetLocation)
    quest.difficultyLabel = getQuestDifficultyLabel(quest.difficulty)
    quest.timeLimitHours = math.max(0, tonumber(quest.timeLimitHours or quest.timerHours or quest.expireHours) or 0)
    if quest.timeLimitHours > 0 then
        quest.expiresAtWorldHours = quest.startedAtWorldHours + quest.timeLimitHours
    else
        quest.expiresAtWorldHours = nil
    end
    quest.encounter = normalizeEncounter(quest, quest.encounter)
    quest.objectives = type(quest.objectives) == "table" and quest.objectives or {}

    for index, objective in ipairs(quest.objectives) do
        quest.objectives[index] = normalizeObjective(index, quest, objective)
    end

    if #quest.objectives == 0 then
        quest.objectives[1] = normalizeObjective(1, quest, {
            id = "kill_default",
            type = "kill",
            label = "Kill Zombies",
            required = 5,
        })
    end

    quest.rewardContext = type(quest.rewardContext) == "table" and DO.DeepCopy(quest.rewardContext) or {}
    if DO.Rewards and DO.Rewards.NormalizeRewards then
        DO.Rewards.NormalizeRewards(quest, quest.rewards)
    else
        quest.rewards = {}
        quest.rewardPreview = nil
        quest.rewardState = {
            granted = false,
            grantedAt = nil,
            entries = {},
        }
    end

    syncEncounterObjectiveCounts(quest)

    store.quests[#store.quests + 1] = quest

    if not store.trackedQuestID then
        store.trackedQuestID = quest.id
        quest.tracked = true
    else
        quest.tracked = store.trackedQuestID == quest.id
    end

    if quest.grantItemType and Quests.RequestSpawnQuestItem then
        Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
    end

    say(player, "Objective accepted: " .. tostring(quest.name))
    questLog("Quest", "Runtime", "Started quest " .. tostring(quest.id))
    onQuestStateChanged(player)
    return quest
end

function Quests.BuildDebugKillZoneQuest(player, difficulty, timeLimitHours)
    local destination = buildFallbackDestination(player, "Marked Kill Zone")
    destination.r = 1.0
    destination.g = 0.3
    destination.b = 0.2
    destination.radius = math.max(26, destination.radius or 26)

    local spawnCount = 8
    return {
        name = "Kill Zone Sweep",
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
        rewardContext = buildDebugRewardContext(destination),
        targetLocation = destination,
        rewards = {
            { kind = "money", amount = 150 },
            { kind = "item", itemType = "Base.Bandage", count = 2 },
        },
        encounter = {
            id = "kill_zone_encounter",
            kind = "kill_zone",
            count = spawnCount,
            spawnRadius = 18,
            clearRadius = 28,
            spawnMode = "building",
            requireAreaClear = true,
            requirePlayerPresence = true,
        },
        objectives = {
            {
                id = "kill_zone",
                type = "kill",
                label = "Eliminate the infestation",
                required = spawnCount,
                radius = destination.radius,
                encounterOnly = true,
                requireAreaClear = true,
            },
        },
    }
end

function Quests.BuildDebugHuntQuest(player, difficulty, timeLimitHours)
    local destination = buildFallbackDestination(player, "Sample Hunt Zone")
    destination.r = 0.95
    destination.g = 0.65
    destination.b = 0.1
    destination.radius = math.max(28, destination.radius or 28)

    local spawnCount = 7
    return {
        name = "Infected Sample Hunt",
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
        rewardContext = buildDebugRewardContext(destination),
        targetLocation = destination,
        rewards = {
            { kind = "money", amount = 220 },
            { kind = "reputation", amount = 5 },
            {
                kind = "recruit",
                count = 1,
                template = {
                    profession = "Scavenger",
                    jobType = "Scavenger",
                    name = "Recovered Scout",
                },
            },
        },
        encounter = {
            id = "sample_hunt_encounter",
            kind = "hunt_drop",
            count = spawnCount,
            spawnRadius = 18,
            clearRadius = 30,
            spawnMode = "building",
            requireAreaClear = true,
            requirePlayerPresence = true,
        },
        objectives = {
            {
                id = "kill_for_sample",
                type = "kill",
                label = "Purge the marked cluster",
                required = spawnCount,
                radius = destination.radius,
                encounterOnly = true,
                requireAreaClear = true,
            },
            {
                id = "recover_sample",
                type = "obtainDrop",
                label = "Recover the sample",
                required = 1,
                radius = destination.radius,
                dropItemType = "DTQuest.InfectedSampleQuest",
                spawnAfterKills = 4,
                encounterOnly = true,
                requireAreaClear = true,
                completeRemainingObjectives = true,
                completeQuestOnComplete = true,
            },
        },
    }
end

function Quests.BuildDebugCourierQuest(player, difficulty, timeLimitHours)
    local destination = buildFallbackDestination(player, "Delivery Destination")
    destination.r = 0.25
    destination.g = 0.85
    destination.b = 1.0
    destination.radius = math.max(12, math.min(destination.radius or 12, 20))

    return {
        name = "Courier Run",
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
        rewardContext = buildDebugRewardContext(destination),
        targetLocation = destination,
        grantItemType = "DTQuest.PackageMedicalQuest",
        grantItemDifficulty = difficulty and normalizeDifficulty(difficulty) or 1.0,
        rewards = {
            { kind = "money", amount = 300 },
            { kind = "reputation", amount = 3 },
            { kind = "item", itemType = "Base.CannedSoup", count = 2 },
        },
        objectives = {
            {
                id = "deliver_package",
                type = "deliverItem",
                label = "Deliver the package",
                required = 1,
                questItemType = "DTQuest.PackageMedicalQuest",
                consumeOnComplete = true,
                radius = destination.radius,
            },
        },
    }
end

function Quests.DebugStartKillZoneQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugKillZoneQuest(player, difficulty, timeLimitHours))
end

function Quests.DebugStartHuntQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugHuntQuest(player, difficulty, timeLimitHours))
end

function Quests.DebugStartCourierQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugCourierQuest(player, difficulty, timeLimitHours))
end

function Quests.DumpState(player)
    local store = getStore(player, false)
    if not store then
        questLog("Quest", "Dump", "No Dynamic Objectives state found")
        return
    end

    questLog("Quest", "Dump", "========================================================")
    questLog("Quest", "Dump", " DYNAMIC OBJECTIVES STATE DUMP")
    questLog("Quest", "Dump", "========================================================")
    questLog("Quest", "Dump", "Tracked Quest: " .. tostring(store.trackedQuestID))

    for _, quest in ipairs(store.quests or {}) do
        questLog("Quest", "Dump", string.format("%s [%s]", tostring(quest.name), tostring(quest.status)))
        if quest.encounter then
            questLog(
                "Quest",
                "Dump",
                string.format(
                    "  Encounter: spawned=%s spawnedCount=%d clearRadius=%d",
                    tostring(quest.encounter.spawned == true),
                    tonumber(quest.encounter.spawnedCount) or 0,
                    tonumber(quest.encounter.clearRadius) or 0
                )
            )
        end
        for _, objective in ipairs(quest.objectives or {}) do
            questLog(
                "Quest",
                "Dump",
                string.format(
                    "  - %s (%s): %d/%d completed=%s",
                    tostring(objective.label),
                    tostring(objective.type),
                    tonumber(objective.progress) or 0,
                    tonumber(objective.required) or 0,
                    tostring(objective.completed == true)
                )
            )
        end
    end

    questLog("Quest", "Dump", "========================================================")
end

local function shouldCompleteQuest(player, quest)
    if not objectivesComplete(quest) then
        return false
    end

    if not questRequiresAreaClear(quest) then
        return true
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    return zoneState and zoneState.areaClear == true
end

function Quests.OnZombieKilled(player, zombie)
    local store = getStore(player, true)
    if not store or not zombie then
        return false
    end

    local changed = false

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true and (objective.type == "kill" or objective.type == "obtainDrop") then
                    local location = questLocationFor(quest, objective)
                    if doesZombieMatchEncounter(player, quest, zombie, objective)
                        and isWithinLocation(location, zombie:getX(), zombie:getY(), zombie:getZ())
                    then
                        if objective.type == "kill" then
                            local newProgress = math.min(objective.required, (tonumber(objective.progress) or 0) + 1)
                            if newProgress ~= objective.progress then
                                objective.progress = newProgress
                                objective.completed = objective.progress >= objective.required
                                changed = true
                            end
                        elseif objective.type == "obtainDrop" then
                            objective.killProgress = math.max(0, math.floor(tonumber(objective.killProgress) or 0)) + 1
                            changed = true

                            local prerequisiteReady = objective.killProgress >= objective.spawnAfterKills
                            if prerequisiteReady and not objective.dropState.spawned and DO.Loot and DO.Loot.SpawnQuestCorpseDrop then
                                if DO.Loot.SpawnQuestCorpseDrop(zombie, player, quest, objective) then
                                    changed = true
                                end
                            end
                        end
                    end
                end
            end

            if shouldCompleteQuest(player, quest) then
                Quests.CompleteQuest(player, quest.id, "kill_objectives")
                return true
            end
        end
    end

    if changed then
        onQuestStateChanged(player)
    end

    return changed
end

function Quests.OnPlayerQuestUpdate(player)
    if not player then
        return
    end

    questUpdateTick = questUpdateTick + 1
    if questUpdateTick < 20 then
        return
    end
    questUpdateTick = 0

    local store = getStore(player, false)
    if not store then
        return
    end

    local changed = false
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            local remainingHours = getQuestRemainingHours(quest)
            if remainingHours ~= nil and remainingHours <= 0 then
                Quests.FailQuest(player, quest.id, "time_expired")
                return
            end

            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true then
                    if quest.encounter and quest.encounter.spawned ~= true and isEncounterActivationReady(player, quest) then
                        if Quests.RequestEncounterSpawn(player, quest) then
                            changed = true
                        end
                    end

                    if objective.type == "obtainDrop" then
                        local count = countObjectiveDropItems(player, quest.id, objective.id)
                        if count > 0 then
                            changed = markObjectiveCompleted(objective) or changed
                            if objective.completeRemainingObjectives == true then
                                changed = completeObjectivesAfter(quest, objective.id) or changed
                            end
                            if objective.completeQuestOnComplete == true then
                                quest.skipAreaClear = true
                                Quests.CompleteQuest(player, quest.id, "objective_completed")
                                return
                            end
                            changed = true
                        end
                    elseif objective.type == "deliverItem" then
                        local location = questLocationFor(quest, objective)
                        if isWithinLocation(location, px, py, pz) then
                            local items = Quests.FindItemsOnPlayer(player, function(item)
                                if not Quests.ValidateDelivery(item, quest.id) then
                                    return false
                                end
                                if objective.questItemType and item:getFullType() ~= objective.questItemType then
                                    return false
                                end
                                return true
                            end)

                            if #items > 0 then
                                if objective.consumeOnComplete then
                                    Quests.RemoveInventoryItem(items[1])
                                end
                                objective.progress = objective.required
                                objective.completed = true
                                changed = true
                            end
                        end
                    end
                end
            end

            if shouldCompleteQuest(player, quest) then
                Quests.CompleteQuest(player, quest.id, "player_update")
                return
            end
        end
    end

    if changed then
        onQuestStateChanged(player)
    end
end

if not (isServer() and not isClient()) then
    Events.OnPlayerUpdate.Add(Quests.OnPlayerQuestUpdate)
end
