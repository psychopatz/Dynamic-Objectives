DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

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
    quest.status = "active"
    quest.createdAt = DO.NowMs()
    quest.startedAtWorldHours = Runtime.getWorldAgeHours()
    quest.playerKey = DO.GetPlayerKey(player)
    quest.targetLocation = Runtime.normalizeLocation(quest.targetLocation or Runtime.buildFallbackDestination(player, quest.name))
    quest.baseDifficulty = Runtime.normalizeDifficulty(quest.baseDifficulty or quest.questDifficulty or quest.difficulty or Runtime.getConfiguredQuestDifficulty())
    quest.difficulty, quest.difficultyFactors = Runtime.resolveQuestDifficulty(player, quest, quest.targetLocation)
    quest.difficultyLabel = Runtime.getQuestDifficultyLabel(quest.difficulty)
    quest.timeLimitHours = math.max(0, tonumber(quest.timeLimitHours or quest.timerHours or quest.expireHours) or 0)
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
    Runtime.markBlueprintLedger(store, quest, "lastStartedAtWorldHours")
    Runtime.markChainQuestStarted(store, quest)

    if not store.trackedQuestID then
        store.trackedQuestID = quest.id
        quest.tracked = true
    else
        quest.tracked = store.trackedQuestID == quest.id
    end
    quest.located = store.locatedQuestID == quest.id

    if quest.grantItemType and Quests.RequestSpawnQuestItem then
        Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
    end

    Runtime.say(player, "Objective accepted: " .. tostring(quest.name))
    Runtime.questLog("Quest", "Runtime", "Started quest " .. tostring(quest.id))
    Runtime.onQuestStateChanged(player)
    return quest
end
