DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function shouldCompleteQuest(player, quest)
    if not Runtime.objectivesComplete(quest) then
        return false
    end

    if not Runtime.questRequiresAreaClear(quest) then
        return true
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    return zoneState and zoneState.areaClear == true
end

function Quests.OnZombieKilled(player, zombie)
    local store = Runtime.getStore(player, true)
    if not store or not zombie then
        return false
    end

    local changed = false

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true and (objective.type == "kill" or objective.type == "obtainDrop") then
                    local location = Runtime.questLocationFor(quest, objective)
                    if Runtime.doesZombieMatchEncounter(player, quest, zombie, objective)
                        and Runtime.isWithinLocation(location, zombie:getX(), zombie:getY(), zombie:getZ())
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
        Runtime.onQuestStateChanged(player)
    end

    return changed
end

function Quests.OnPlayerQuestUpdate(player)
    if not player then
        return
    end

    Runtime.questUpdateTick = (tonumber(Runtime.questUpdateTick) or 0) + 1
    if (tonumber(Runtime.questUpdateTick) or 0) < 20 then
        return
    end
    Runtime.questUpdateTick = 0

    local store = Runtime.getStore(player, false)
    if not store then
        return
    end

    local changed = false
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            local remainingHours = Runtime.getQuestRemainingHours(quest)
            if remainingHours ~= nil and remainingHours <= 0 then
                Quests.FailQuest(player, quest.id, "time_expired")
                return
            end

            local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
            if hook and hook.onQuestUpdate then
                local hookResult = hook.onQuestUpdate(player, quest, store)
                if type(hookResult) == "table" then
                    changed = hookResult.changed == true or changed
                    if hookResult.complete == true then
                        Quests.CompleteQuest(player, quest.id, hookResult.reason or "hook_completed")
                        return
                    end
                    if hookResult.fail == true then
                        Quests.FailQuest(player, quest.id, hookResult.reason or "hook_failed")
                        return
                    end
                end
            end

            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true then
                    if quest.encounter and quest.encounter.spawned ~= true and Runtime.isEncounterActivationReady(player, quest) then
                        if Quests.RequestEncounterSpawn(player, quest) then
                            changed = true
                        end
                    end

                    if objective.type == "obtainDrop" then
                        local count = Runtime.countObjectiveDropItems(player, quest.id, objective.id)
                        if count > 0 then
                            changed = Runtime.markObjectiveCompleted(objective) or changed
                            if objective.completeRemainingObjectives == true then
                                changed = Runtime.completeObjectivesAfter(quest, objective.id) or changed
                            end
                            if objective.completeQuestOnComplete == true then
                                quest.skipAreaClear = true
                                Quests.CompleteQuest(player, quest.id, "objective_completed")
                                return
                            end
                            changed = true
                        end
                    elseif objective.type == "pickupItem" then
                        local location = Runtime.questLocationFor(quest, objective)
                        if Runtime.isWithinLocation(location, px, py, pz) then
                            if quest.grantItemType and Quests.RequestSpawnQuestItem then
                                Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
                            end
                            objective.progress = objective.required
                            objective.completed = true
                            changed = true
                        end
                    elseif objective.type == "deliverItem" then
                        local location = Runtime.questLocationFor(quest, objective)
                        if Runtime.isWithinLocation(location, px, py, pz) then
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
        Runtime.onQuestStateChanged(player)
    end
end

if not (isServer() and not isClient()) then
    Events.OnPlayerUpdate.Add(Quests.OnPlayerQuestUpdate)
end
