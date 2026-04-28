DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function buildDebugTraderContext()
    return {
        traderID = "debug_manager",
        displayName = "Debug Manager",
        currentState = "Resting",
    }
end

local function buildDebugOverrides(difficulty, timeLimitHours)
    return {
        baseDifficulty = difficulty and Runtime.normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
    }
end

local function buildDebugCompletionSpec(player, difficulty, timeLimitHours)
    local store = Runtime.getStore and Runtime.getStore(player, true) or nil
    local destination = Runtime.buildFallbackDestination and Runtime.buildFallbackDestination(player, "Debug Completion Contract") or nil
    local location = Runtime.normalizeLocation and Runtime.normalizeLocation(destination or {}) or destination or {}
    local context = Runtime.buildDebugRewardContext and Runtime.buildDebugRewardContext(location) or {}
    local id = Runtime.nextQuestID and Runtime.nextQuestID(player, store or { seq = 0 }) or ("DOQ_DEBUG_COMPLETE_" .. tostring(ZombRand(100000, 999999)))

    return {
        id = id,
        name = "Debug Completion Contract",
        title = "Mission Complete Modal Test",
        giverName = "Debug Manager",
        giverTitle = "Simulation",
        giverFactionID = context.factionID,
        giverFactionName = context.factionName or "Independent",
        targetLocation = location,
        baseDifficulty = difficulty and Runtime.normalizeDifficulty(difficulty) or 1.0,
        baseTimeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
        expirationScaled = true,
        rewardContext = context,
        rewards = {
            { kind = "money", amount = 180 },
            { kind = "reputation", amount = 12, factionID = context.factionID, factionName = context.factionName },
            { kind = "item", count = 2, itemType = "Base.Axe" },
            { kind = "item", count = 1, itemType = "Base.HuntingKnife" },
            { kind = "item", count = 3, itemType = "Base.CannedSoup" },
        },
        objectives = {
            {
                id = "debug_secure_site",
                type = "kill",
                label = "Secure the debug objective",
                required = 1,
                progress = 0,
                completed = false,
            },
        },
        debugLifecycleSimulation = true,
    }
end

function Quests.BuildDebugKillZoneQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_kill_zone") or nil
    return Runtime.buildQuestSpecFromBlueprint(player, buildDebugTraderContext(), blueprint or {}, buildDebugOverrides(difficulty, timeLimitHours))
end

function Quests.BuildDebugHuntQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_hunt_drop") or nil
    return Runtime.buildQuestSpecFromBlueprint(player, buildDebugTraderContext(), blueprint or {}, buildDebugOverrides(difficulty, timeLimitHours))
end

function Quests.BuildDebugCourierQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_courier_run") or nil
    return Runtime.buildQuestSpecFromBlueprint(player, buildDebugTraderContext(), blueprint or {}, buildDebugOverrides(difficulty, timeLimitHours))
end

function Quests.BuildDebugChainQuest(player, chainID, stageID, difficulty, timeLimitHours)
    if not Runtime.buildChainStageSpec then
        return nil
    end

    local chain = chainID and Runtime.getChain and Runtime.getChain(chainID) or nil
    local stage = stageID and Runtime.getChainStage and Runtime.getChainStage(chain, stageID) or nil
    if not chain then
        return nil
    end

    if not stage then
        stage = chain.stages and chain.stages[1] or nil
    end

    if not stage then
        return nil
    end

    local traderContext = buildDebugTraderContext()
    return Runtime.buildChainStageSpec(player, traderContext, chain, stage, {
        traderContext = traderContext,
        overrides = buildDebugOverrides(difficulty, timeLimitHours),
    })
end

function Quests.BuildDebugRestingChainQuest(player, difficulty, timeLimitHours)
    return Quests.BuildDebugChainQuest(player, "resting_contract_progression", nil, difficulty, timeLimitHours)
end

function Quests.DebugStartKillZoneQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugKillZoneQuest(player, difficulty, timeLimitHours))
end

function Quests.DebugStartHuntQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugHuntQuest(player, difficulty, timeLimitHours))
end

function Quests.DebugStartCourierQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugCourierQuest(player, difficulty, timeLimitHours))
end

function Quests.DebugStartChainQuest(player, chainID, stageID, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugChainQuest(player, chainID, stageID, difficulty, timeLimitHours))
end

function Quests.DebugStartRestingChainQuest(player, difficulty, timeLimitHours)
    return Quests.StartQuest(player, Quests.BuildDebugRestingChainQuest(player, difficulty, timeLimitHours))
end

function Quests.BuildDebugCompletionQuest(player, difficulty, timeLimitHours)
    return buildDebugCompletionSpec(player, difficulty, timeLimitHours)
end

function Quests.DebugSimulateQuestCompletion(player, difficulty, timeLimitHours)
    if not player then
        return nil
    end

    local quest = Quests.StartQuest(player, buildDebugCompletionSpec(player, difficulty, timeLimitHours))
    if not quest then
        return nil
    end

    for _, objective in ipairs(quest.objectives or {}) do
        objective.progress = math.max(tonumber(objective.required) or 1, tonumber(objective.progress) or 0)
        objective.completed = true
    end

    quest.rewardsPendingClaim = false
    local completed = Quests.CompleteQuest(player, quest.id, "debug_completion_modal")
    if not completed then
        return nil
    end

    if Quests.GetQuest then
        return Quests.GetQuest(player, quest.id) or quest
    end

    return quest
end

function Quests.DebugSimulateQuestFailure(player, difficulty, timeLimitHours)
    if not player then
        return nil
    end

    local quest = Quests.StartQuest(player, buildDebugCompletionSpec(player, difficulty, timeLimitHours))
    if not quest then
        return nil
    end

    quest.title = "Mission Failure Modal Test"
    quest.name = "Debug Failure Contract"

    if not Quests.FailQuest(player, quest.id, "escort_target_incapacitated") then
        return nil
    end

    if Quests.GetQuest then
        return Quests.GetQuest(player, quest.id) or quest
    end

    return quest
end

function Quests.DebugSimulateQuestProgress(player, difficulty, timeLimitHours)
    if not player then
        return nil
    end

    local quest = buildDebugCompletionSpec(player, difficulty, timeLimitHours)
    if not quest then
        return nil
    end

    quest.status = "active"
    quest.title = "Mission Progress Modal Test"
    quest.name = "Debug Progress Contract"
    quest.objectives = {
        {
            id = "debug_pickup_parcel",
            type = "pickupItem",
            label = "Grab the parcel",
            required = 1,
            progress = 1,
            completed = true,
        },
        {
            id = "debug_clear_infestation",
            type = "areaClear",
            label = "Clear the infestation",
            required = 1,
            progress = 0,
            completed = false,
        },
        {
            id = "debug_deliver_parcel",
            type = "deliverItem",
            label = "Deliver the parcel",
            required = 1,
            progress = 0,
            completed = false,
        },
    }

    if DO.UI and DO.UI.QueueMissionEvent then
        DO.UI.QueueMissionEvent(player, {
            kind = "progress",
            source = "debug_progress_modal",
            occurredAt = DO.NowMs and DO.NowMs() or 0,
            quest = quest,
            objective = quest.objectives[1],
            objectiveID = quest.objectives[1].id,
        })
    end

    if DO.NotifyStateChanged then
        DO.NotifyStateChanged(player)
    end

    return quest
end

function Quests.DumpState(player)
    local store = Runtime.getStore(player, false)
    if not store then
        Runtime.questLog("Quest", "Dump", "No Dynamic Objectives state found")
        return
    end

    Runtime.questLog("Quest", "Dump", "========================================================")
    Runtime.questLog("Quest", "Dump", " DYNAMIC OBJECTIVES STATE DUMP")
    Runtime.questLog("Quest", "Dump", "========================================================")
    Runtime.questLog("Quest", "Dump", "Tracked Quest: " .. tostring(store.trackedQuestID))
    Runtime.questLog("Quest", "Dump", "Located Quest: " .. tostring(store.locatedQuestID))

    for _, quest in ipairs(store.quests or {}) do
        Runtime.questLog("Quest", "Dump", string.format("%s [%s]", tostring(quest.name), tostring(quest.status)))
        Runtime.questLog(
            "Quest",
            "Dump",
            string.format("  Flags: tracked=%s located=%s", tostring(quest.tracked == true), tostring(quest.located == true))
        )
        if quest.chainId then
            Runtime.questLog(
                "Quest",
                "Dump",
                string.format(
                    "  Chain: id=%s stage=%s next=%s",
                    tostring(quest.chainId),
                    tostring(quest.chainStageId),
                    tostring(quest.chainNextStageId)
                )
            )
        end
        if quest.encounter then
            Runtime.questLog(
                "Quest",
                "Dump",
                string.format(
                    "  Encounter: spawned=%s spawnedCount=%d clearRadius=%d",
                    tostring(quest.encounter.spawned == true),
                    tonumber(quest.encounter.spawnedCount) or 0,
                    tonumber(quest.encounter.clearRadius) or 0
                )
            )
        end
        for _, objective in ipairs(quest.objectives or {}) do
            Runtime.questLog(
                "Quest",
                "Dump",
                string.format(
                    "  - %s (%s): %d/%d completed=%s",
                    tostring(objective.label),
                    tostring(objective.type),
                    tonumber(objective.progress) or 0,
                    tonumber(objective.required) or 0,
                    tostring(objective.completed == true)
                )
            )
        end
    end

    for chainId, progress in pairs(store.chainProgress or {}) do
        Runtime.questLog(
            "Quest",
            "Dump",
            string.format(
                "Chain Progress %s: activeQuest=%s activeStage=%s nextStage=%s pending=%s completed=%s",
                tostring(chainId),
                tostring(progress.activeQuestID),
                tostring(progress.activeStageId),
                tostring(progress.nextStageId),
                tostring(progress.pendingOffer and progress.pendingOffer.stageId or nil),
                tostring(progress.completed == true)
            )
        )
    end

    Runtime.questLog("Quest", "Dump", "========================================================")
end
