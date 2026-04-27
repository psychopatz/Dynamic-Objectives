DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Kills = DynamicObjectives.Kills or {}
DynamicObjectives.Loot = DynamicObjectives.Loot or {}

local DO = DynamicObjectives
local Kills = DO.Kills
local Loot = DO.Loot

if isServer() and not isClient() then
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

local function getLocalPlayerForKey(playerKey)
    local player = DO.GetLocalPlayer()
    if not player then
        return nil
    end

    if DO.GetPlayerKey(player) == playerKey then
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
        return getLocalPlayerForKey(cached.playerKey)
    end

    local modData = zombie:getModData()
    if modData and modData.DO_LastHitPlayerKey then
        local age = DO.NowMs() - (tonumber(modData.DO_LastHitAt) or 0)
        if age <= Kills.LAST_HIT_TTL_MS then
            return getLocalPlayerForKey(modData.DO_LastHitPlayerKey)
        end
    end

    return nil
end

function Loot.SpawnQuestCorpseDrop(zombie, player, quest, objective)
    if not zombie or not player or not quest or not objective or not objective.dropItemType then
        return nil
    end

    objective.dropState = type(objective.dropState) == "table" and objective.dropState or {}
    objective.dropState.spawnedCount = math.max(
        0,
        math.floor(tonumber(objective.dropState.spawnedCount) or ((objective.dropState.spawned == true) and 1 or 0))
    )
    local requiredCount = math.max(1, math.floor(tonumber(objective.required) or 1))
    if objective.dropState.spawnedCount >= requiredCount then
        return nil
    end

    local corpseModData = zombie:getModData()
    corpseModData.DOQuestDropSpawned = type(corpseModData.DOQuestDropSpawned) == "table" and corpseModData.DOQuestDropSpawned or {}

    local dropKey = tostring(quest.id) .. ":" .. tostring(objective.id)
    if corpseModData.DOQuestDropSpawned[dropKey] then
        return nil
    end

    local inventory = zombie:getInventory()
    if not inventory then
        return nil
    end

    local item = inventory:AddItem(objective.dropItemType)
    if not item then
        return nil
    end

    local modData = item:getModData()
    modData.DOQuestDrop = true
    modData.DOQuestID = quest.id
    modData.DOQuestObjectiveID = objective.id
    modData.DOQuestPlayerKey = DO.GetPlayerKey(player)
    modData.DOQuestDropIndex = objective.dropState.spawnedCount + 1

    item:setName(item:getName() .. " (" .. tostring(quest.id) .. ")")
    item:setTooltip("Objective item for " .. tostring(quest.name or quest.id))

    corpseModData.DOQuestDropSpawned[dropKey] = true
    objective.dropState.spawnedCount = objective.dropState.spawnedCount + 1
    objective.dropState.spawned = objective.dropState.spawnedCount > 0
    objective.dropState.spawnedAt = DO.NowMs()

    if sendAddItemToContainer then
        sendAddItemToContainer(inventory, item)
    end

    killLog("Quest", "Loot", "Spawned corpse drop for " .. tostring(dropKey))
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
