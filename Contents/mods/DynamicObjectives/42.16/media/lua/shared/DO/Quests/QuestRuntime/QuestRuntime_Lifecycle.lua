DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function applyQuestFocus(store, quest)
    if not store or not quest or quest.status ~= "active" then
        return false
    end

    store.trackedQuestID = quest.id
    store.locatedQuestID = quest.id
    store.locatorSuppressed = false

    for _, other in ipairs(store.quests or {}) do
        local isFocused = other.id == quest.id
        other.tracked = isFocused
        other.located = isFocused
    end
    return true
end

function Quests.FocusQuest(player, questID, silent)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    local quest = Runtime.findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    applyQuestFocus(store, quest)
    if silent ~= true then
        Runtime.say(player, "Focused objective: " .. tostring(quest.name))
    end
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.SetTrackedQuest(player, questID)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    local tracked = Runtime.findQuest(store, questID)
    if not tracked or tracked.status ~= "active" then
        return false
    end

    store.trackedQuestID = tracked.id
    for _, quest in ipairs(store.quests or {}) do
        quest.tracked = quest.id == tracked.id
    end
    Runtime.resolveLocatedQuest(player, store)

    Runtime.say(player, "Tracking objective: " .. tostring(tracked.name))
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.GetLocatedQuest(player)
    local store = Runtime.getStore(player, false)
    if not store then
        return nil
    end

    return Runtime.resolveLocatedQuest(player, store)
end

function Quests.SetLocatedQuest(player, questID)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    local located = Runtime.findQuest(store, questID)
    if not located or located.status ~= "active" then
        return false
    end

    store.locatedQuestID = located.id
    store.locatorSuppressed = false
    for _, quest in ipairs(store.quests or {}) do
        quest.located = quest.id == located.id
    end

    Runtime.say(player, "Locator enabled: " .. tostring(located.name))
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.ClearLocatedQuest(player, questID, silent)
    local store = Runtime.getStore(player, true)
    if not store or not store.locatedQuestID then
        return false
    end

    if questID and tostring(store.locatedQuestID) ~= tostring(questID) then
        return false
    end

    local located = Runtime.findQuest(store, store.locatedQuestID)
    store.locatedQuestID = nil
    store.locatorSuppressed = true
    for _, quest in ipairs(store.quests or {}) do
        quest.located = false
    end

    if silent ~= true then
        Runtime.say(player, "Locator disabled: " .. tostring(located and located.name or "Mission"))
    end
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.ToggleLocatedQuest(player, questID)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    if store.locatedQuestID and tostring(store.locatedQuestID) == tostring(questID) then
        return Quests.ClearLocatedQuest(player, questID)
    end

    return Quests.SetLocatedQuest(player, questID)
end

function Quests.AbandonQuest(player, questID)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.id == questID and quest.status == "active" then
            quest.status = "abandoned"
            quest.tracked = false
            quest.located = false
            quest.abandonedAt = DO.NowMs()
            quest.failureReason = "abandoned"
            if Runtime.finalizeObjectiveHookQuest then
                Runtime.finalizeObjectiveHookQuest(player, quest, "abandoned", "abandoned")
            end
            local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
            if hook and hook.onQuestFail then
                hook.onQuestFail(player, quest, store, "abandoned")
            end
            Runtime.removeQuestItemByQuestID(player, quest.id)
            Runtime.removeQuestDropsByQuestID(player, quest.id)
            Runtime.markBlueprintLedger(store, quest, "lastAbandonedAtWorldHours")
            if store.trackedQuestID == quest.id then
                store.trackedQuestID = nil
            end
            if store.locatedQuestID == quest.id then
                store.locatedQuestID = nil
            end
            Runtime.clearChainProgress(store, quest, "abandoned")
            Runtime.resolveTrackedQuest(player, store)
            Runtime.resolveLocatedQuest(player, store)
            Runtime.say(player, "Objective abandoned: " .. tostring(quest.name))
            if DO.UI and DO.UI.QueueMissionEvent then
                DO.UI.QueueMissionEvent(player, {
                    kind = "failed",
                    source = "abandon_quest",
                    status = "abandoned",
                    reason = "abandoned",
                    occurredAt = quest.abandonedAt,
                    quest = quest,
                })
            end
            Runtime.onQuestStateChanged(player)
            return true
        end
    end

    return false
end

function Quests.CompleteQuest(player, questID, reason)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    local quest = Runtime.findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    if DO.Rewards and DO.Rewards.GrantQuestRewards then
        DO.Rewards.GrantQuestRewards(player, quest)
    end

    quest.status = "completed"
    quest.tracked = false
    quest.located = false
    quest.completedAt = DO.NowMs()
    quest.completionReason = reason or "completed"
    Runtime.markBlueprintLedger(store, quest, "lastCompletedAtWorldHours")
    if Runtime.finalizeObjectiveHookQuest then
        Runtime.finalizeObjectiveHookQuest(player, quest, "completed", reason or "completed")
    end
    local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
    if hook and hook.onQuestComplete then
        hook.onQuestComplete(player, quest, store, reason or "completed")
    end

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end
    if store.locatedQuestID == quest.id then
        store.locatedQuestID = nil
    end

    Runtime.completeQuestChain(player, store, quest)
    Runtime.resolveTrackedQuest(player, store)
    Runtime.resolveLocatedQuest(player, store)
    Runtime.say(player, "Objective complete: " .. tostring(quest.name))
    if DO.UI and DO.UI.QueueMissionEvent then
        DO.UI.QueueMissionEvent(player, {
            kind = "completed",
            source = reason or "completed",
            status = "completed",
            reason = reason or "completed",
            occurredAt = quest.completedAt,
            quest = quest,
        })
    end
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.FailQuest(player, questID, reason)
    local store = Runtime.getStore(player, true)
    if not store then
        return false
    end

    local quest = Runtime.findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    quest.status = "failed"
    quest.tracked = false
    quest.located = false
    quest.failedAt = DO.NowMs()
    quest.failureReason = reason or "failed"
    Runtime.markBlueprintLedger(store, quest, "lastFailedAtWorldHours")
    if Runtime.finalizeObjectiveHookQuest then
        Runtime.finalizeObjectiveHookQuest(player, quest, "failed", reason or "failed")
    end
    local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
    if hook and hook.onQuestFail then
        hook.onQuestFail(player, quest, store, reason or "failed")
    end

    Runtime.removeQuestItemByQuestID(player, quest.id)
    Runtime.removeQuestDropsByQuestID(player, quest.id)

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end
    if store.locatedQuestID == quest.id then
        store.locatedQuestID = nil
    end

    Runtime.clearChainProgress(store, quest, "failed")
    Runtime.resolveTrackedQuest(player, store)
    Runtime.resolveLocatedQuest(player, store)
    Runtime.say(player, "Objective failed: " .. tostring(quest.name))
    if DO.UI and DO.UI.QueueMissionEvent then
        DO.UI.QueueMissionEvent(player, {
            kind = "failed",
            source = reason or "failed",
            status = "failed",
            reason = reason or "failed",
            occurredAt = quest.failedAt,
            quest = quest,
        })
    end
    Runtime.onQuestStateChanged(player)
    return true
end

function Quests.StartQuest(player, spec)
    if not player or type(spec) ~= "table" then
        return nil
    end

    local store = Runtime.getStore(player, true)
    if not store then
        return nil
    end

    local quest = DO.DeepCopy(spec)
    quest.id = quest.id or Runtime.nextQuestID(player, store)
    quest.name = tostring(quest.name or quest.id)
    quest.hookId = quest.hookId and tostring(quest.hookId) or nil
    quest.hookIncidentId = quest.hookIncidentId and tostring(quest.hookIncidentId) or nil
    quest.hookState = type(quest.hookState) == "table" and DO.DeepCopy(quest.hookState) or nil
    quest.status = "active"
    quest.createdAt = DO.NowMs()
    quest.startedAtWorldHours = Runtime.getWorldAgeHours()
    quest.playerKey = DO.GetPlayerKey(player)
    quest.targetLocation = Runtime.normalizeLocation(quest.targetLocation or Runtime.buildFallbackDestination(player, quest.name))
    quest.baseDifficulty = Runtime.normalizeDifficulty(quest.baseDifficulty or quest.questDifficulty or quest.difficulty or Runtime.getConfiguredQuestDifficulty())
    if quest.precomputedDifficulty == true and tonumber(quest.difficulty) ~= nil then
        quest.difficulty = Runtime.normalizeDifficulty(quest.difficulty)
        quest.difficultyFactors = type(quest.difficultyFactors) == "table" and DO.DeepCopy(quest.difficultyFactors) or {}
    else
        quest.difficulty, quest.difficultyFactors = Runtime.resolveQuestDifficulty(player, quest, quest.targetLocation)
    end
    quest.difficultyLabel = Runtime.getQuestDifficultyLabel(quest.difficulty)
    local explicitBaseTimeLimitHours = tonumber(quest.baseTimeLimitHours)
    local explicitTimeLimitHours = tonumber(quest.timeLimitHours)
    if not explicitTimeLimitHours or explicitTimeLimitHours <= 0 then
        explicitTimeLimitHours = tonumber(quest.timerHours)
    end
    if not explicitTimeLimitHours or explicitTimeLimitHours <= 0 then
        explicitTimeLimitHours = tonumber(quest.expireHours)
    end
    quest.baseTimeLimitHours = math.max(0, explicitBaseTimeLimitHours and explicitBaseTimeLimitHours > 0 and explicitBaseTimeLimitHours or explicitTimeLimitHours or 0)
    local defaultedTimeLimit = false
    if quest.baseTimeLimitHours <= 0 and Runtime.getConfiguredQuestExpirationMultiplier and Runtime.getConfiguredQuestExpirationMultiplier() > 0 then
        quest.baseTimeLimitHours = 24
        defaultedTimeLimit = true
    end
    local alreadyScaledTimeLimit = quest.expirationScaled == true and defaultedTimeLimit ~= true
    quest.timeLimitHours = Runtime.scaleQuestTimeLimit(
        alreadyScaledTimeLimit and quest.timeLimitHours or quest.baseTimeLimitHours,
        alreadyScaledTimeLimit
    )
    quest.expirationScaled = true
    if quest.timeLimitHours > 0 then
        quest.expiresAtWorldHours = quest.startedAtWorldHours + quest.timeLimitHours
    else
        quest.expiresAtWorldHours = nil
    end
    quest.chainId = quest.chainId and tostring(quest.chainId) or nil
    quest.chainLabel = quest.chainLabel and tostring(quest.chainLabel) or nil
    quest.chainStageId = quest.chainStageId and tostring(quest.chainStageId) or nil
    quest.chainStageIndex = tonumber(quest.chainStageIndex) or nil
    quest.chainAdvanceMode = quest.chainAdvanceMode and tostring(quest.chainAdvanceMode) or nil
    quest.chainNextStageId = quest.chainNextStageId and tostring(quest.chainNextStageId) or nil
    quest.isChainQuest = quest.chainId ~= nil
    quest.title = quest.title and tostring(quest.title) or nil
    quest.giverName = quest.giverName and tostring(quest.giverName) or nil
    quest.giverTitle = quest.giverTitle and tostring(quest.giverTitle) or nil
    quest.giverFactionID = quest.giverFactionID and tostring(quest.giverFactionID) or nil
    quest.giverFactionName = quest.giverFactionName and tostring(quest.giverFactionName) or nil
    quest.themeID = quest.themeID and tostring(quest.themeID) or nil
    quest.budgetValue = tonumber(quest.budgetValue) or nil
    quest.rewardTags = type(quest.rewardTags) == "table" and DO.DeepCopy(quest.rewardTags) or {}
    quest.encounter = Runtime.normalizeEncounter(quest, quest.encounter)
    quest.objectives = type(quest.objectives) == "table" and quest.objectives or {}

    for index, objective in ipairs(quest.objectives) do
        quest.objectives[index] = Runtime.normalizeObjective(index, quest, objective)
    end

    if #quest.objectives == 0 then
        quest.objectives[1] = Runtime.normalizeObjective(1, quest, {
            id = "kill_default",
            type = "kill",
            label = "Kill Zombies",
            required = 5,
        })
    end

    quest.rewardContext = type(quest.rewardContext) == "table" and DO.DeepCopy(quest.rewardContext) or {}
    if DO.Rewards and DO.Rewards.NormalizeRewards then
        DO.Rewards.NormalizeRewards(quest, quest.rewards)
    else
        quest.rewards = {}
        quest.rewardPreview = nil
        quest.rewardState = {
            granted = false,
            grantedAt = nil,
            entries = {},
        }
    end

    Runtime.syncEncounterObjectiveCounts(quest)

    store.quests[#store.quests + 1] = quest
    
    local QUEST_CAP = 50
    while #store.quests > QUEST_CAP do
        local removed = false
        for i = 1, #store.quests do
            if store.quests[i].status ~= "active" then
                table.remove(store.quests, i)
                removed = true
                break
            end
        end
        if not removed then
            table.remove(store.quests, 1)
        end
    end
    Runtime.markBlueprintLedger(store, quest, "lastStartedAtWorldHours")
    Runtime.markChainQuestStarted(store, quest)
    applyQuestFocus(store, quest)

    if quest.grantItemType and quest.grantItemOnPickup ~= true and Quests.RequestSpawnQuestItem then
        Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
    end

    local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
    if hook and hook.onQuestAccepted then
        hook.onQuestAccepted(player, quest, store, spec)
    end

    Runtime.say(player, "Objective accepted: " .. tostring(quest.name))
    Runtime.questLog("Quest", "Runtime", "Started quest " .. tostring(quest.id))
    Runtime.onQuestStateChanged(player)
    return quest
end
