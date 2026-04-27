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
    elseif command == "RefreshObjectiveHooks" then
        if not player or not DynamicObjectives or not DynamicObjectives.GetObjectiveHookList then
            return
        end

        for _, hook in ipairs(DynamicObjectives.GetObjectiveHookList()) do
            if hook and hook.refreshIncidentsForPlayer then
                hook.refreshIncidentsForPlayer(player)
            end
        end

        if DynamicObjectives.NotifyStateChanged then
            DynamicObjectives.NotifyStateChanged(player)
        elseif player.transmitModData then
            player:transmitModData()
        end
        if sendServerCommand then
            sendServerCommand(player, "DynamicObjectives", "ObjectiveHooksRefreshed", {})
        end
    elseif command == "AcceptObjectiveHookIncident" then
        if not player or type(args) ~= "table" then
            return
        end

        local hook = DynamicObjectives.GetObjectiveHook and DynamicObjectives.GetObjectiveHook(args.hookId) or nil
        if not hook or not hook.acceptIncident then
            return
        end

        local result = hook.acceptIncident(player, args)
        if sendServerCommand then
            sendServerCommand(player, "DynamicObjectives", result and result.ok and "HookIncidentAccepted" or "HookIncidentFailed", result or {
                ok = false,
                hookId = args.hookId,
                incidentId = args.incidentId,
                reason = "invalid_accept",
                message = "This incident could not be accepted.",
            })
        end
    elseif command == "ForceObjectiveHookIncident" then
        if not player or type(args) ~= "table" then
            return
        end

        local hook = DynamicObjectives.GetObjectiveHook and DynamicObjectives.GetObjectiveHook(args.hookId) or nil
        if not hook or not hook.forceIncidentForPlayer then
            return
        end

        hook.forceIncidentForPlayer(player, args)
        if DynamicObjectives.NotifyStateChanged then
            DynamicObjectives.NotifyStateChanged(player)
        elseif player.transmitModData then
            player:transmitModData()
        end
        if sendServerCommand then
            sendServerCommand(player, "DynamicObjectives", "ObjectiveHooksRefreshed", {
                hookId = args.hookId,
                forced = true,
            })
        end
    elseif command == "FinalizeObjectiveHookQuest" then
        if not player or type(args) ~= "table" then
            return
        end

        local hook = DynamicObjectives.GetObjectiveHook and DynamicObjectives.GetObjectiveHook(args.hookId) or nil
        if not hook or not hook.finalizeQuest then
            return
        end

        hook.finalizeQuest(player, args)
    elseif command == "EscortObjectiveAction" then
        if not player or type(args) ~= "table" then
            return
        end

        local hook = DynamicObjectives.GetObjectiveHook and DynamicObjectives.GetObjectiveHook(args.hookId) or nil
        if not hook or not hook.performEscortAction then
            return
        end

        local result = hook.performEscortAction(player, args) or {
            ok = false,
            hookId = args.hookId,
            incidentId = args.incidentId,
            traderId = args.traderId,
            action = args.action,
            message = "The escort order could not be applied.",
        }
        if sendServerCommand then
            sendServerCommand(player, "DynamicObjectives", "HookEscortActionResult", result)
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
