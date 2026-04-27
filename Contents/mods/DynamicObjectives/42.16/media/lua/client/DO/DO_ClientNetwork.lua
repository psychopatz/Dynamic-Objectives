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
    elseif command == "ObjectiveHooksRefreshed" then
        if DT_RadioScannerWindow and DT_RadioScannerWindow.instance and DT_RadioScannerWindow.instance.currentCategory == "Quest" then
            DT_RadioScannerWindow.instance.skipQuestServerRefresh = true
            DT_RadioScannerWindow.instance:refresh()
        end
    elseif command == "HookIncidentAccepted" then
        local player = getLocalPlayer()
        if player and args and args.questSpec and not args.questID and DO.Quests and DO.Quests.StartQuest then
            DO.Quests.StartQuest(player, DO.DeepCopy and DO.DeepCopy(args.questSpec) or args.questSpec)
        end

        if _G.DOTraderHelpEscortJobUI and _G.DOTraderHelpEscortJobUI.OnIncidentAccepted then
            _G.DOTraderHelpEscortJobUI.OnIncidentAccepted(args)
        end
    elseif command == "HookIncidentFailed" then
        if _G.DOTraderHelpEscortJobUI and _G.DOTraderHelpEscortJobUI.OnIncidentFailed then
            _G.DOTraderHelpEscortJobUI.OnIncidentFailed(args)
        end
    elseif command == "HookEscortActionResult" then
        if _G.DOTraderHelpEscortJobUI and _G.DOTraderHelpEscortJobUI.OnEscortActionResult then
            _G.DOTraderHelpEscortJobUI.OnEscortActionResult(args)
        end
    end
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end
