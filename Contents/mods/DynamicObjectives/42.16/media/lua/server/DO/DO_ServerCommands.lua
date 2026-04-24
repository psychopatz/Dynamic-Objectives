DynamicObjectives = DynamicObjectives or {}

local function onClientCommand(module, command, player, args)
    if module ~= "DynamicObjectives" then
        return
    end

    if command == "SpawnQuestItem" then
        if not player or not args or not DynamicObjectives.Quests or not DynamicObjectives.Quests.CreateQuestItem then
            return
        end

        DynamicObjectives.Quests.CreateQuestItem(
            player,
            args.itemID,
            args.questID,
            tonumber(args.difficulty) or 1.0
        )
    elseif command == "SpawnQuestEncounter" then
        if not player or not args or not DynamicObjectives.Quests or not DynamicObjectives.Quests.SpawnQuestEncounterFromData then
            return
        end

        local spawnedCount = DynamicObjectives.Quests.SpawnQuestEncounterFromData(player, args)
        if sendServerCommand then
            sendServerCommand(player, "DynamicObjectives", "EncounterSpawned", {
                questID = args.questID,
                encounterID = args.encounterID,
                spawnedCount = spawnedCount,
            })
        end
    elseif command == "GrantQuestRewards" then
        if not player or not args or not DynamicObjectives.Rewards or not DynamicObjectives.Rewards.GrantQuestRewardsFromPayload then
            return
        end

        DynamicObjectives.Rewards.GrantQuestRewardsFromPayload(player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
