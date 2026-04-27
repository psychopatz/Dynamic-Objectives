DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.ZombieTargetResolver = DynamicObjectives.ZombieTargetResolver or {}

local DO = DynamicObjectives
local Resolver = DO.ZombieTargetResolver
local Runtime = DO.Quests and DO.Quests.Runtime or {}

Resolver.cacheByQuestID = Resolver.cacheByQuestID or {}
Resolver.MAX_TARGETS = Resolver.MAX_TARGETS or 6
Resolver.EXTRA_SEARCH_RADIUS = Resolver.EXTRA_SEARCH_RADIUS or 12

local function isLivingZombie(zombie)
    return Runtime.isLivingZombie and Runtime.isLivingZombie(zombie) or false
end

local function distanceToPoint(playerObj, x, y)
    if not playerObj then
        return math.huge
    end

    return IsoUtils.DistanceTo(
        tonumber(playerObj:getX()) or 0,
        tonumber(playerObj:getY()) or 0,
        tonumber(x) or 0,
        tonumber(y) or 0
    )
end

local function getObjectiveRemainingCount(objective)
    if not objective or objective.completed == true then
        return 0
    end

    if objective.type == "kill" then
        return math.max(0, math.floor((tonumber(objective.required) or 0) - (tonumber(objective.progress) or 0)))
    end

    if objective.type == "obtainDrop" then
        local progress = math.max(0, math.floor(tonumber(objective.progress) or 0))
        local required = math.max(1, math.floor(tonumber(objective.required) or 1))
        local spawnedCount = math.max(
            0,
            math.floor(
                tonumber(objective.dropState and objective.dropState.spawnedCount)
                    or ((objective.dropState and objective.dropState.spawned == true) and 1 or 0)
            )
        )

        if progress >= required or spawnedCount > progress then
            return 0
        end

        local nextThreshold = math.max(1, math.floor(tonumber(objective.spawnAfterKills) or 1)) * (spawnedCount + 1)
        return math.max(0, nextThreshold - math.max(0, math.floor(tonumber(objective.killProgress) or 0)))
    end

    return 0
end

local function getQuestLocation(quest, objective)
    return Runtime.questLocationFor and Runtime.questLocationFor(quest, objective) or quest and quest.targetLocation or nil
end

local function isLocationLoaded(location)
    local cell = getCell and getCell() or nil
    if not cell or not location then
        return false
    end

    local square = cell:getGridSquare(
        math.floor(tonumber(location.x) or 0),
        math.floor(tonumber(location.y) or 0),
        math.floor(tonumber(location.z) or 0)
    )
    return square ~= nil
end

local function isWithinRadius(location, radius, zombie)
    if not location or not zombie or not Runtime.isWithinRadius then
        return false
    end

    return Runtime.isWithinRadius(location, radius, zombie:getX(), zombie:getY(), zombie:getZ())
end

local function isQuestZombie(playerObj, quest, objective, zombie)
    if not playerObj or not quest or not zombie then
        return false
    end

    if Runtime.doesZombieMatchEncounter and not Runtime.doesZombieMatchEncounter(playerObj, quest, zombie, objective) then
        return false
    end

    return Runtime.isQuestEncounterZombie and Runtime.isQuestEncounterZombie(playerObj, quest, zombie) or false
end

local function sortTargets(left, right)
    local leftPriority = tonumber(left.priority) or 99
    local rightPriority = tonumber(right.priority) or 99
    if leftPriority == rightPriority then
        return (tonumber(left.distance) or math.huge) < (tonumber(right.distance) or math.huge)
    end
    return leftPriority < rightPriority
end

local function addTarget(results, seen, playerObj, entry)
    if not entry then
        return
    end

    local x = tonumber(entry.x) or 0
    local y = tonumber(entry.y) or 0
    local z = tonumber(entry.z) or 0
    local zombie = entry.zombie

    if zombie and isLivingZombie(zombie) ~= true then
        return
    end

    local coordKey = string.format("%d:%d:%d", math.floor(x), math.floor(y), math.floor(z))
    local key = zombie or coordKey
    if seen[key] or seen[coordKey] then
        return
    end

    seen[key] = true
    seen[coordKey] = true
    results[#results + 1] = {
        zombie = zombie,
        x = zombie and zombie:getX() or x,
        y = zombie and zombie:getY() or y,
        z = zombie and zombie:getZ() or z,
        distance = zombie and distanceToPoint(playerObj, zombie:getX(), zombie:getY()) or distanceToPoint(playerObj, x, y),
        priority = tonumber(entry.priority) or 99,
        kind = tostring(entry.kind or (zombie and "live" or "point")),
        note = entry.note and tostring(entry.note) or nil,
    }
end

local function trimTargets(results, limit)
    table.sort(results, sortTargets)
    while #results > limit do
        table.remove(results)
    end
end

local function cacheTargets(questID, targets)
    if not questID then
        return
    end

    local cached = {}
    for index, entry in ipairs(targets or {}) do
        cached[index] = {
            x = tonumber(entry.x) or 0,
            y = tonumber(entry.y) or 0,
            z = tonumber(entry.z) or 0,
            kind = entry.kind,
        }
    end

    Resolver.cacheByQuestID[tostring(questID)] = {
        updatedAt = DO.NowMs and DO.NowMs() or 0,
        entries = cached,
    }
end

local function buildFallbackMessage(encounter, locationLoaded)
    if encounter and encounter.spawned ~= true then
        return "Encounter not spawned yet. Move into the mission area."
    end
    if locationLoaded ~= true then
        return "Encounter area is not loaded. Using the mission location."
    end
    return "Using the mission area because no live quest zombie is currently tracked."
end

function Resolver.ClearQuest(questID)
    if questID == nil then
        return
    end

    Resolver.cacheByQuestID[tostring(questID)] = nil
end

function Resolver.ClearAll()
    Resolver.cacheByQuestID = {}
end

function Resolver.ResolveQuestTargets(playerObj, quest)
    local state = {
        quest = quest,
        objective = nil,
        zoneState = nil,
        location = nil,
        locationLoaded = false,
        targetLimit = 0,
        targets = {},
        status = "none",
        message = nil,
    }

    if not playerObj or not quest or quest.status ~= "active" then
        if quest and quest.id then
            Resolver.ClearQuest(quest.id)
        end
        return state
    end

    local objective = Runtime.getPendingObjective and Runtime.getPendingObjective(quest) or nil
    local zoneState = DO.Quests and DO.Quests.GetEncounterStatus and DO.Quests.GetEncounterStatus(playerObj, quest) or nil
    local location = getQuestLocation(quest, objective)
    local locationLoaded = isLocationLoaded(location)
    local targetLimit = math.min(Resolver.MAX_TARGETS, math.max(0, getObjectiveRemainingCount(objective)))

    state.objective = objective
    state.zoneState = zoneState
    state.location = location
    state.locationLoaded = locationLoaded
    state.targetLimit = targetLimit

    if not objective or targetLimit <= 0 then
        Resolver.ClearQuest(quest.id)
        state.status = "complete"
        return state
    end

    local encounter = quest.encounter
    if encounter and encounter.spawned ~= true then
        state.status = "spawn_pending"
        state.message = buildFallbackMessage(encounter, locationLoaded)
        if location then
            addTarget(state.targets, {}, playerObj, {
                x = location.x,
                y = location.y,
                z = location.z,
                priority = 90,
                kind = "location",
                note = state.message,
            })
        end
        return state
    end

    local results = {}
    local seen = {}
    local zombieList = getCell and getCell() and getCell():getZombieList() or nil
    local clearRadius = zoneState and zoneState.clearRadius or (encounter and encounter.clearRadius) or (location and location.radius) or 45
    local searchRadius = clearRadius + Resolver.EXTRA_SEARCH_RADIUS

    if zombieList then
        for index = 0, zombieList:size() - 1 do
            local zombie = zombieList:get(index)
            if isQuestZombie(playerObj, quest, objective, zombie) then
                addTarget(results, seen, playerObj, {
                    zombie = zombie,
                    priority = 1,
                    kind = "live",
                })
            end
        end

        if location and #results < targetLimit then
            for index = 0, zombieList:size() - 1 do
                local zombie = zombieList:get(index)
                if isLivingZombie(zombie) == true and isWithinRadius(location, searchRadius, zombie) then
                    addTarget(results, seen, playerObj, {
                        zombie = zombie,
                        priority = 2,
                        kind = "zone_live",
                    })
                end
            end
        end
    end

    if zoneState and #results < targetLimit then
        for _, sample in ipairs(zoneState.targetSamples or {}) do
            addTarget(results, seen, playerObj, {
                x = sample.x,
                y = sample.y,
                z = sample.z,
                priority = 3,
                kind = "zone_sample",
                note = "Using sampled zombie coordinates from the mission area.",
            })
        end
    end

    if #results > 0 then
        trimTargets(results, targetLimit)
        cacheTargets(quest.id, results)
        state.targets = results
        state.status = results[1].zombie and "live" or "sample"
        return state
    end

    local cache = Resolver.cacheByQuestID[tostring(quest.id)]
    if cache and type(cache.entries) == "table" and #cache.entries > 0 then
        for _, entry in ipairs(cache.entries) do
            addTarget(state.targets, seen, playerObj, {
                x = entry.x,
                y = entry.y,
                z = entry.z,
                priority = 4,
                kind = "cached",
                note = "Using the last known zombie positions.",
            })
        end
        trimTargets(state.targets, targetLimit)
        state.status = locationLoaded and "cached" or "unloaded_cached"
        state.message = locationLoaded and "Using the last known zombie positions." or "Encounter area is unloaded. Using the last known zombie positions."
        return state
    end

    state.status = locationLoaded and "location" or "unloaded"
    state.message = buildFallbackMessage(encounter, locationLoaded)
    if location then
        addTarget(state.targets, seen, playerObj, {
            x = location.x,
            y = location.y,
            z = location.z,
            priority = 90,
            kind = "location",
            note = state.message,
        })
    end

    return state
end

function Resolver.ResolveLocatedQuestTargets(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer and DO.GetLocalPlayer() or nil
    if not playerObj or not DO.Quests or not DO.Quests.GetLocatedQuest then
        return Resolver.ResolveQuestTargets(nil, nil)
    end

    return Resolver.ResolveQuestTargets(playerObj, DO.Quests.GetLocatedQuest(playerObj))
end
