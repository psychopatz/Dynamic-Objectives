DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

local function getLocalPlayer()
    if DO.GetLocalPlayer then
        return DO.GetLocalPlayer()
    end
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

local function onServerCommand(module, command, args)
    if module ~= "DynamicObjectives" then
        return
    end

    if command == "EncounterSpawned" then
        local player = getLocalPlayer()
        if player and DO.Quests and DO.Quests.ApplyEncounterSpawnResult then
            DO.Quests.ApplyEncounterSpawnResult(player, args and args.questID, args and args.spawnedCount)
        end
    end
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end
