DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function normalizeEncounter(quest, encounter)
    if type(encounter) ~= "table" then
        return nil
    end

    local location = Runtime.normalizeLocation(encounter.location or quest.targetLocation)
    local difficulty = Runtime.normalizeDifficulty(encounter.difficulty or (quest and quest.difficulty) or 1.0)
    local baseCount = math.max(1, math.floor(tonumber(encounter.baseCount or encounter.count) or 1))
    local count = Runtime.scaleCountForDifficulty(baseCount, difficulty)
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
    normalized.targetLocation = Runtime.normalizeLocation(normalized.targetLocation)
    normalized.dropState = type(normalized.dropState) == "table" and normalized.dropState or {}
    normalized.dropState.spawnedCount = math.max(
        0,
        math.floor(
            tonumber(normalized.dropState.spawnedCount)
                or ((normalized.dropState.spawned == true) and 1 or 0)
        )
    )
    normalized.dropState.spawned = normalized.dropState.spawnedCount > 0
    normalized.dropState.spawnedAt = tonumber(normalized.dropState.spawnedAt) or nil
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
    normalized.completeEncounterObjectivesOnComplete = normalized.completeEncounterObjectivesOnComplete == true
    normalized.skipAreaClearOnComplete = normalized.skipAreaClearOnComplete == true
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
            local dropRequired = math.max(1, math.floor(tonumber(objective.required) or 1))
            local distributedKills = math.max(1, math.floor(encounterCount / dropRequired))
            objective.spawnAfterKills = math.min(
                encounterCount,
                math.max(1, math.min(math.floor((baseKills * encounterScale) + 0.5), distributedKills))
            )
        end
    end
end

local function questLocationFor(quest, objective)
    local fallbackLocation = nil
    if objective and objective.targetLocation then
        fallbackLocation = objective.targetLocation
    elseif quest and quest.encounter and quest.encounter.location then
        fallbackLocation = quest.encounter.location
    else
        fallbackLocation = quest and quest.targetLocation or nil
    end

    local hook = quest and Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
    if hook and hook.resolveQuestLocation then
        local resolved = hook.resolveQuestLocation(nil, quest, objective, fallbackLocation)
        if resolved then
            return resolved
        end
    end

    return fallbackLocation
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
    if type(quest) ~= "table" or type(quest.objectives) ~= "table" or #quest.objectives == 0 then
        return false
    end

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

local function resolveLocatedQuest(player, store)
    if not store then
        return nil
    end

    local located = findQuest(store, store.locatedQuestID)
    if located and located.status == "active" then
        for _, quest in ipairs(store.quests or {}) do
            quest.located = quest.id == located.id
        end
        return located
    end

    store.locatedQuestID = nil

    if store.locatorSuppressed ~= true then
        local tracked = findQuest(store, store.trackedQuestID)
        if tracked and tracked.status == "active" then
            store.locatedQuestID = tracked.id
            located = tracked
        else
            for _, quest in ipairs(store.quests or {}) do
                if quest.status == "active" then
                    store.locatedQuestID = quest.id
                    located = quest
                    break
                end
            end
        end
    end

    for _, quest in ipairs(store.quests or {}) do
        quest.located = located and quest.id == located.id or false
    end

    return located
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

local function captureObjectiveCompletionState(quest)
    local state = {}
    for _, objective in ipairs(quest and quest.objectives or {}) do
        state[tostring(objective and objective.id or "")] = objective and objective.completed == true or false
    end
    return state
end

local function shouldQueueObjectiveProgressEvent(objective)
    if not objective then
        return false
    end

    if objective.suppressProgressEvent == true then
        return false
    end

    if objective.type == "claimRewards" or tostring(objective.id or "") == "claim_rewards" then
        return false
    end

    return true
end

local function queueObjectiveProgressEvents(player, quest, previousState, source)
    if not player or not quest or type(previousState) ~= "table" or not (DO.UI and DO.UI.QueueMissionEvent) then
        return 0
    end

    local queued = 0
    local occurredAt = DO.NowMs and DO.NowMs() or 0
    for _, objective in ipairs(quest.objectives or {}) do
        local objectiveID = tostring(objective and objective.id or "")
        if objectiveID ~= ""
            and objective
            and objective.completed == true
            and previousState[objectiveID] ~= true
            and shouldQueueObjectiveProgressEvent(objective)
        then
            DO.UI.QueueMissionEvent(player, {
                kind = "progress",
                source = source or "objective_completed",
                quest = quest,
                objective = objective,
                objectiveID = objectiveID,
                occurredAt = occurredAt,
            })
            queued = queued + 1
        end
    end

    return queued
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
    local targetSamples = {}
    local playerX = player and tonumber(player:getX()) or (location and tonumber(location.x) or 0)
    local playerY = player and tonumber(player:getY()) or (location and tonumber(location.y) or 0)
    local playerZ = player and tonumber(player:getZ()) or (location and tonumber(location.z) or 0)

    if player and location then
        playerPresent = isWithinRadius(location, clearRadius + 8, player:getX(), player:getY(), player:getZ())
    end

    local cell = getCell and getCell() or nil
    local zombieList = cell and cell.getZombieList and cell:getZombieList() or nil
    if zombieList and location then
        for index = 0, zombieList:size() - 1 do
            local zombie = zombieList:get(index)
            if Runtime.isLivingZombie(zombie)
                and isWithinRadius(location, clearRadius, zombie:getX(), zombie:getY(), zombie:getZ())
            then
                nearbyCount = nearbyCount + 1
                Runtime.insertNearestZoneTarget(targetSamples, zombie, playerX, playerY, playerZ)
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

    local totalZombies = math.max(0, nearbyCount)
    local clearedZombies = 0
    if encounter and encounter.spawned == true then
        encounter.clearBaselineCount = math.max(
            0,
            math.floor(
                tonumber(encounter.clearBaselineCount)
                    or tonumber(encounter.maxNearbyZombies)
                    or tonumber(encounter.spawnedCount)
                    or tonumber(encounter.count)
                    or 0
            )
        )
        encounter.maxNearbyZombies = math.max(
            encounter.clearBaselineCount,
            math.floor(tonumber(encounter.maxNearbyZombies) or 0),
            nearbyCount,
            math.floor(tonumber(encounter.spawnedCount) or 0),
            math.floor(tonumber(encounter.count) or 0)
        )
        if playerPresent == true or nearbyCount > 0 then
            encounter.clearBaselineCount = math.max(encounter.clearBaselineCount, encounter.maxNearbyZombies)
        end
        totalZombies = math.max(
            math.floor(tonumber(encounter.clearBaselineCount) or 0),
            math.floor(tonumber(encounter.spawnedCount) or 0),
            math.floor(tonumber(encounter.count) or 0),
            nearbyCount
        )
        clearedZombies = math.max(0, totalZombies - nearbyCount)
    end

    return {
        location = location,
        clearRadius = clearRadius,
        nearbyZombies = nearbyCount,
        totalZombies = totalZombies,
        clearedZombies = clearedZombies,
        playerPresent = playerPresent,
        areaClear = areaClear,
        encounterSpawned = encounter and encounter.spawned == true or false,
        targetSamples = targetSamples,
        closestTarget = targetSamples[1],
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

    local location = zoneState.location
    local locationLoaded = true
    local cell = getCell and getCell() or nil
    if cell and location then
        locationLoaded = cell:getGridSquare(
            math.floor(tonumber(location.x) or 0),
            math.floor(tonumber(location.y) or 0),
            math.floor(tonumber(location.z) or 0)
        ) ~= nil
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

    if location and locationLoaded ~= true then
        return "Encounter area unloaded; move closer to locate targets"
    end

    if zoneState.playerPresent ~= true then
        return "Return to the marked zone"
    end

    if math.max(0, tonumber(zoneState.totalZombies) or 0) > 0 then
        return string.format(
            "Nearby zeds: %d / %d",
            math.max(0, tonumber(zoneState.nearbyZombies) or 0),
            math.max(0, tonumber(zoneState.totalZombies) or 0)
        )
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

    return math.max(0, expiresAt - Runtime.getWorldAgeHours())
end

Runtime.normalizeEncounter = normalizeEncounter
Runtime.normalizeObjective = normalizeObjective
Runtime.syncEncounterObjectiveCounts = syncEncounterObjectiveCounts
Runtime.questLocationFor = questLocationFor
Runtime.isWithinLocation = isWithinLocation
Runtime.isWithinRadius = isWithinRadius
Runtime.objectivesComplete = objectivesComplete
Runtime.findQuest = findQuest
Runtime.resolveTrackedQuest = resolveTrackedQuest
Runtime.resolveLocatedQuest = resolveLocatedQuest
Runtime.onQuestStateChanged = onQuestStateChanged
Runtime.removeQuestItemByQuestID = removeQuestItemByQuestID
Runtime.removeQuestDropsByQuestID = removeQuestDropsByQuestID
Runtime.markObjectiveCompleted = markObjectiveCompleted
Runtime.captureObjectiveCompletionState = captureObjectiveCompletionState
Runtime.queueObjectiveProgressEvents = queueObjectiveProgressEvents
Runtime.completeObjectivesAfter = completeObjectivesAfter
Runtime.countObjectiveDropItems = countObjectiveDropItems
Runtime.isQuestEncounterZombie = isQuestEncounterZombie
Runtime.doesZombieMatchEncounter = doesZombieMatchEncounter
Runtime.gatherLiveZoneState = gatherLiveZoneState
Runtime.getPendingObjective = getPendingObjective
Runtime.questRequiresAreaClear = questRequiresAreaClear
Runtime.buildAreaClearText = buildAreaClearText
Runtime.getQuestRemainingHours = getQuestRemainingHours
