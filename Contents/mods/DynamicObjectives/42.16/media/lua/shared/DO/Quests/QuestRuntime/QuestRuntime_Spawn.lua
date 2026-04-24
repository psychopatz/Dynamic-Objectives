DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

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
        Runtime.syncEncounterObjectiveCounts(quest)
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
    Runtime.onQuestStateChanged(player)
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
    modData.DOQuestTarget = true
    modData.DOQuestTargetType = "zombie"
    modData.DOQuestEncounterQuestID = quest.id
    modData.DOQuestEncounterID = encounter and encounter.id or "encounter_main"
    modData.DOQuestEncounterPlayerKey = DO.GetPlayerKey(player)
end

function Quests.SpawnQuestEncounterFromData(player, data)
    if not player or type(data) ~= "table" then
        return 0
    end

    local location = Runtime.normalizeLocation(data.location)
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

    Runtime.questLog(
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
    if not Runtime.isWithinRadius(location, activationRadius, player:getX(), player:getY(), player:getZ()) then
        return false
    end

    if not getSquareAt(location.x, location.y, location.z) and not resolveSpawnBuilding(location) then
        return false
    end

    return true
end

Runtime.applyEncounterSpawnResult = applyEncounterSpawnResult
Runtime.getSquareAt = getSquareAt
Runtime.getBuildingKey = getBuildingKey
Runtime.resolveSpawnBuilding = resolveSpawnBuilding
Runtime.isValidSpawnSquare = isValidSpawnSquare
Runtime.buildZSearchOrder = buildZSearchOrder
Runtime.findSpawnPointInBuilding = findSpawnPointInBuilding
Runtime.findSpawnPoint = findSpawnPoint
Runtime.stampQuestSpawn = stampQuestSpawn
Runtime.isEncounterActivationReady = isEncounterActivationReady
