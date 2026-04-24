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
