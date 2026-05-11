DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Kills = DynamicObjectives.Kills or {}
DynamicObjectives.Loot = DynamicObjectives.Loot or {}

require "Misc/DT_CorpseLootRuntime"

local DO = DynamicObjectives
local Kills = DO.Kills
local Loot = DO.Loot
local Runtime = DO.Quests and DO.Quests.Runtime or {}

if isClient() and not isServer() then
    return
end

Kills.LAST_HIT_TTL_MS = Kills.LAST_HIT_TTL_MS or 15000
Kills.LastHitCache = Kills.LastHitCache or setmetatable({}, { __mode = "k" })

local function killLog(category, topic, message)
    DO.Log(category, topic, message)
end

local function isPlayer(value)
    return value and instanceof and instanceof(value, "IsoPlayer")
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

local function getDropKey(quest, objective)
    if not quest or not objective then
        return nil
    end
    return tostring(quest.id) .. ":" .. tostring(objective.id)
end

local function syncDropState(objective)
    objective.dropState = type(objective and objective.dropState) == "table" and objective.dropState or {}
    objective.dropState.spawnedCount = math.max(
        0,
        math.floor(tonumber(objective.dropState.spawnedCount) or ((objective.dropState.spawned == true) and 1 or 0))
    )
    objective.dropState.spawned = objective.dropState.spawnedCount > 0
    return objective.dropState
end

local function getContainerItems(container)
    return container and container.getItems and container:getItems() or nil
end

local function addItemToContainer(container, fullType, configureItem)
    if not container or not fullType then
        return nil
    end

    if DTCorpseLootRuntime and DTCorpseLootRuntime.AddItemToContainer then
        return DTCorpseLootRuntime.AddItemToContainer(container, fullType, configureItem)
    end

    local item = container:AddItem(fullType)
    if not item then
        return nil
    end

    if type(configureItem) == "function" then
        local ok = pcall(configureItem, item)
        if not ok then
            return nil
        end
    end

    if sendAddItemToContainer and isServer and isServer() then
        sendAddItemToContainer(container, item)
    end

    return item
end

local function countQuestItemsInContainer(container, questID, objectiveID, playerKey)
    local count = 0
    local items = getContainerItems(container)
    if not items then
        return count
    end

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local modData = item and item.getModData and item:getModData() or nil
        if modData
            and modData.DOQuestDrop == true
            and tostring(modData.DOQuestID or "") == tostring(questID or "")
            and tostring(modData.DOQuestObjectiveID or "") == tostring(objectiveID or "")
            and (not playerKey or not modData.DOQuestPlayerKey or tostring(modData.DOQuestPlayerKey) == tostring(playerKey))
        then
            count = count + 1
        end
    end

    return count
end

local function forEachCorpseInRadius(location, radius, callback)
    local cell = getCell and getCell() or nil
    if not cell or not location or type(callback) ~= "function" then
        return nil
    end

    local centerX = math.floor(tonumber(location.x) or 0)
    local centerY = math.floor(tonumber(location.y) or 0)
    local centerZ = math.floor(tonumber(location.z) or 0)
    local searchRadius = math.max(1, math.floor(tonumber(radius) or tonumber(location.radius) or 8))

    for x = centerX - searchRadius, centerX + searchRadius do
        for y = centerY - searchRadius, centerY + searchRadius do
            local square = cell:getGridSquare(x, y, centerZ)
            local objects = square and square.getStaticMovingObjects and square:getStaticMovingObjects() or nil
            if objects then
                for index = 0, objects:size() - 1 do
                    local corpse = objects:get(index)
                    if corpse and instanceof and instanceof(corpse, "IsoDeadBody") then
                        local result = callback(corpse, x, y, centerZ)
                        if result ~= nil then
                            return result
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function spawnQuestDropInContainer(container, corpseModData, player, quest, objective)
    if not container or not player or not quest or not objective or not objective.dropItemType then
        return nil
    end

    local dropState = syncDropState(objective)
    local requiredCount = math.max(1, math.floor(tonumber(objective.required) or 1))
    if dropState.spawnedCount >= requiredCount then
        return nil
    end

    corpseModData = type(corpseModData) == "table" and corpseModData or {}
    corpseModData.DOQuestDropSpawned = type(corpseModData.DOQuestDropSpawned) == "table" and corpseModData.DOQuestDropSpawned or {}

    local dropKey = getDropKey(quest, objective)
    if not dropKey or corpseModData.DOQuestDropSpawned[dropKey] then
        return nil
    end

    local item = addItemToContainer(container, objective.dropItemType, function(createdItem)
        local modData = createdItem:getModData()
        modData.DOQuestDrop = true
        modData.DOQuestID = quest.id
        modData.DOQuestObjectiveID = objective.id
        modData.DOQuestPlayerKey = DO.GetPlayerKey(player)
        modData.DOQuestDropIndex = dropState.spawnedCount + 1

        createdItem:setName(createdItem:getName() .. " (" .. tostring(quest.id) .. ")")
        createdItem:setTooltip("Objective item for " .. tostring(quest.name or quest.id))
    end)
    if not item then
        return nil
    end

    corpseModData.DOQuestDropSpawned[dropKey] = true
    dropState.spawnedCount = dropState.spawnedCount + 1
    dropState.spawned = dropState.spawnedCount > 0
    dropState.spawnedAt = DO.NowMs()

    killLog("Quest", "Loot", "Spawned corpse drop for " .. tostring(dropKey))
    return item
end

local function getPlayerForKey(playerKey)
    if not playerKey then
        return nil
    end

    if isServer and isServer() and getOnlinePlayers then
        local onlinePlayers = getOnlinePlayers()
        if onlinePlayers then
            for index = 0, onlinePlayers:size() - 1 do
                local onlinePlayer = onlinePlayers:get(index)
                if onlinePlayer and DO.GetPlayerKey(onlinePlayer) == playerKey then
                    return onlinePlayer
                end
            end
        end
    end

    local player = DO.GetLocalPlayer()
    if player and DO.GetPlayerKey(player) == playerKey then
        return player
    end

    return nil
end

function Kills.CacheWeaponHit(attacker, target, weapon, damage)
    if not isPlayer(attacker) or not isZombie(target) then
        return
    end

    local entry = {
        playerKey = DO.GetPlayerKey(attacker),
        playerNum = attacker.getPlayerNum and attacker:getPlayerNum() or 0,
        username = attacker.getUsername and attacker:getUsername() or nil,
        timestamp = DO.NowMs(),
    }

    Kills.LastHitCache[target] = entry

    local modData = target:getModData()
    modData.DO_LastHitPlayerKey = entry.playerKey
    modData.DO_LastHitAt = entry.timestamp
end

function Kills.ResolveKiller(zombie)
    if not zombie then
        return nil
    end

    local attacker = zombie.getAttackedBy and zombie:getAttackedBy() or nil
    if isPlayer(attacker) then
        return attacker
    end

    local cached = Kills.LastHitCache[zombie]
    if cached and (DO.NowMs() - (tonumber(cached.timestamp) or 0)) <= Kills.LAST_HIT_TTL_MS then
        return getPlayerForKey(cached.playerKey)
    end

    local modData = zombie:getModData()
    if modData and modData.DO_LastHitPlayerKey then
        local age = DO.NowMs() - (tonumber(modData.DO_LastHitAt) or 0)
        if age <= Kills.LAST_HIT_TTL_MS then
            return getPlayerForKey(modData.DO_LastHitPlayerKey)
        end
    end

    return nil
end

function Loot.SpawnQuestCorpseDrop(zombie, player, quest, objective)
    if not zombie or not player or not quest or not objective or not objective.dropItemType then
        return nil
    end

    local corpseSourceModData = zombie:getModData() or {}
    local playerKey = DO.GetPlayerKey(player)
    local deathX = math.floor(zombie:getX())
    local deathY = math.floor(zombie:getY())
    local deathZ = math.floor(zombie:getZ())
    local encounterQuestID = tostring(corpseSourceModData.DOQuestEncounterQuestID or quest.id)
    local encounterID = tostring(corpseSourceModData.DOQuestEncounterID or "encounter_main")
    local encounterPlayerKey = tostring(corpseSourceModData.DOQuestEncounterPlayerKey or playerKey)

    if not DTCorpseLootRuntime or not DTCorpseLootRuntime.QueueCorpseMutation then
        local inventory = zombie:getInventory()
        return spawnQuestDropInContainer(inventory, corpseSourceModData, player, quest, objective)
    end

    local corpseToken = DTCorpseLootRuntime.EnsureCorpseToken and DTCorpseLootRuntime.EnsureCorpseToken(zombie, "do_quest_drop") or nil
    local queuedKey = DTCorpseLootRuntime.QueueCorpseMutation({
        label = "do_quest_drop",
        x = deathX,
        y = deathY,
        z = deathZ,
        radius = 1,
        ttlTicks = 240,
        matcher = function(corpse, corpseModData, corpseX, corpseY, corpseZ)
            corpseModData = corpseModData or {}
            if corpseToken and DTCorpseLootRuntime.MatchCorpseByToken and DTCorpseLootRuntime.MatchCorpseByToken(corpseToken, corpseModData) then
                return true
            end

            return tostring(corpseModData.DOQuestEncounterQuestID or "") == encounterQuestID
                and tostring(corpseModData.DOQuestEncounterID or "") == encounterID
                and tostring(corpseModData.DOQuestEncounterPlayerKey or "") == encounterPlayerKey
                and corpseX == deathX
                and corpseY == deathY
                and corpseZ == deathZ
        end,
        apply = function(corpse, container)
            local corpseModData = corpse and corpse.getModData and corpse:getModData() or {}
            return spawnQuestDropInContainer(container, corpseModData, player, quest, objective) ~= nil
        end,
    })

    return queuedKey
end

function Loot.EnsureQuestCorpseDropInArea(player, quest, objective, zoneState)
    if not player or not quest or not objective or not objective.dropItemType or not zoneState then
        return nil
    end

    if zoneState.encounterSpawned ~= true or zoneState.areaClear ~= true then
        return nil
    end

    local location = zoneState.location
    if not location then
        return nil
    end

    local dropState = syncDropState(objective)
    local requiredCount = math.max(1, math.floor(tonumber(objective.required) or 1))
    local playerKey = DO.GetPlayerKey(player)
    local inventoryCount = Runtime.countObjectiveDropItems and Runtime.countObjectiveDropItems(player, quest.id, objective.id) or 0
    local corpseCount = 0
    local fallbackCorpse = nil
    local bestDistanceSq = nil
    local dropKey = getDropKey(quest, objective)
    local searchRadius = math.max(1, math.floor(tonumber(zoneState.clearRadius) or tonumber(location.radius) or 8))

    forEachCorpseInRadius(location, searchRadius, function(corpse, x, y, z)
        local container = corpse and corpse.getContainer and corpse:getContainer() or nil
        if not container then
            return nil
        end

        corpseCount = corpseCount + countQuestItemsInContainer(container, quest.id, objective.id, playerKey)

        local corpseModData = corpse.getModData and corpse:getModData() or nil
        local spawnedLookup = corpseModData and corpseModData.DOQuestDropSpawned or nil
        local alreadyUsed = dropKey and type(spawnedLookup) == "table" and spawnedLookup[dropKey] == true
        if alreadyUsed ~= true then
            local dx = (tonumber(x) or 0) - (tonumber(location.x) or 0)
            local dy = (tonumber(y) or 0) - (tonumber(location.y) or 0)
            local distanceSq = (dx * dx) + (dy * dy) + ((math.floor(tonumber(z) or 0) - math.floor(tonumber(location.z) or 0)) ^ 2 * 16)
            if not fallbackCorpse or distanceSq < bestDistanceSq then
                fallbackCorpse = corpse
                bestDistanceSq = distanceSq
            end
        end

        return nil
    end)

    local knownTotal = math.max(0, math.floor(tonumber(inventoryCount) or 0)) + corpseCount
    if knownTotal > dropState.spawnedCount then
        dropState.spawnedCount = knownTotal
        dropState.spawned = dropState.spawnedCount > 0
    end
    if knownTotal >= requiredCount or dropState.spawnedCount >= requiredCount then
        return nil
    end

    local container = fallbackCorpse and fallbackCorpse.getContainer and fallbackCorpse:getContainer() or nil
    local corpseModData = fallbackCorpse and fallbackCorpse.getModData and fallbackCorpse:getModData() or nil
    if not container or not corpseModData then
        return nil
    end

    local item = spawnQuestDropInContainer(container, corpseModData, player, quest, objective)
    if item then
        killLog("Quest", "Loot", "Spawned cleared-area fallback corpse drop for " .. tostring(dropKey))
    end
    return item
end

function Kills.ProcessZombieDeath(zombie)
    if not isZombie(zombie) then
        return
    end

    local modData = zombie:getModData()
    if modData and modData.DOQuestDeathProcessed == true then
        return
    end

    local killer = Kills.ResolveKiller(zombie)
    if not killer then
        return
    end

    if modData then
        modData.DOQuestDeathProcessed = true
        modData.DOQuestDeathProcessedBy = DO.GetPlayerKey(killer)
    end

    if DO.Quests and DO.Quests.OnZombieKilled then
        DO.Quests.OnZombieKilled(killer, zombie)
    end
end

if Events and Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(Kills.CacheWeaponHit)
end

if Events and Events.OnZombieDead then
    Events.OnZombieDead.Add(Kills.ProcessZombieDeath)
end
