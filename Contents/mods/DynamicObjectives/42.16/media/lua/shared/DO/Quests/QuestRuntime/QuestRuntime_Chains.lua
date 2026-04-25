DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function chainLog(message)
    Runtime.questLog("Quest", "Chain", message)
end

local function getChain(chainOrId)
    if type(chainOrId) == "table" then
        return chainOrId
    end

    return chainOrId and DO.GetQuestChain and DO.GetQuestChain(chainOrId) or nil
end

local function getChainProgress(store, chainId, create)
    if not store or not chainId then
        return nil
    end

    if create then
        store.chainProgress = type(store.chainProgress) == "table" and store.chainProgress or {}
    end

    local bucket = store.chainProgress
    if type(bucket) ~= "table" then
        return nil
    end

    local key = tostring(chainId)
    if create and type(bucket[key]) ~= "table" then
        bucket[key] = {
            chainId = key,
            pendingOffer = nil,
            activeQuestID = nil,
            activeStageId = nil,
            nextStageId = nil,
            completed = false,
        }
    end

    return bucket[key]
end

local function getChainStage(chainOrId, stageId)
    local chain = getChain(chainOrId)
    if not chain or not stageId then
        return nil, nil, chain
    end

    local key = tostring(stageId)
    local index = type(chain.StageIndexByID) == "table" and chain.StageIndexByID[key] or nil
    if index then
        return chain.stages[index], index, chain
    end

    for fallbackIndex, stage in ipairs(chain.stages or {}) do
        if tostring(stage.id or "") == key then
            return stage, fallbackIndex, chain
        end
    end

    return nil, nil, chain
end

local function getResolvedNextStageId(chain, stage, stageIndex)
    if not chain or not stage then
        return nil
    end

    local explicit = stage.nextStageId and tostring(stage.nextStageId) or nil
    if explicit and explicit ~= "" then
        return explicit
    end

    local index = tonumber(stageIndex) or tonumber(stage.stageIndex) or 0
    local nextStage = chain.stages and chain.stages[index + 1] or nil
    return nextStage and tostring(nextStage.id or "") or nil
end

local function getNextChainStage(chainOrId, stageOrId)
    local chain = getChain(chainOrId)
    if not chain then
        return nil, nil, nil
    end

    local stage = stageOrId
    local stageIndex = nil
    if type(stageOrId) ~= "table" then
        stage, stageIndex = getChainStage(chain, stageOrId)
    else
        stageIndex = tonumber(stage.stageIndex)
        if not stageIndex then
            _, stageIndex = getChainStage(chain, stage.id)
        end
    end

    local nextStageId = getResolvedNextStageId(chain, stage, stageIndex)
    if not nextStageId or nextStageId == "" then
        return nil, nil, chain
    end

    return getChainStage(chain, nextStageId)
end

local function resolveChainAdvanceMode(chain, stage)
    local stageMode = stage and stage.advanceMode and tostring(stage.advanceMode) or nil
    if stageMode == "offer" or stageMode == "auto" then
        return stageMode
    end

    local chainMode = chain and chain.defaultAdvanceMode and tostring(chain.defaultAdvanceMode) or nil
    if chainMode == "offer" or chainMode == "auto" then
        return chainMode
    end

    if stage and stage.autoStart == true then
        return "auto"
    end

    return "offer"
end

local function findChainEntryStageForBlueprint(blueprintId)
    local targetId = tostring(blueprintId or "")
    if targetId == "" or not DO.GetQuestChainList then
        return nil, nil, nil
    end

    for _, chain in ipairs(DO.GetQuestChainList()) do
        local stage = chain and chain.stages and chain.stages[1] or nil
        if stage and tostring(stage.blueprintId or "") == targetId then
            return chain, stage, 1
        end
    end

    return nil, nil, nil
end

local function buildChainStageSpec(player, traderContext, chainOrId, stageOrId, options)
    local chain = getChain(chainOrId)
    if not chain then
        return nil
    end

    local stage = stageOrId
    local stageIndex = nil
    if type(stageOrId) ~= "table" then
        stage, stageIndex = getChainStage(chain, stageOrId)
    else
        stageIndex = tonumber(stage.stageIndex)
        if not stageIndex then
            _, stageIndex = getChainStage(chain, stage.id)
        end
    end

    if not stage or not stage.blueprintId or not DO.GetQuestBlueprint then
        return nil
    end

    local blueprint = DO.GetQuestBlueprint(stage.blueprintId)
    if not blueprint then
        return nil
    end

    local effectiveTrader = type(options and options.traderContext) == "table"
        and DO.DeepCopy(options.traderContext)
        or DO.DeepCopy(traderContext or {})

    if Runtime.blueprintMatchesEligibility and not Runtime.blueprintMatchesEligibility(player, effectiveTrader, blueprint) then
        return nil
    end

    local spec = Runtime.buildQuestSpecFromBlueprint(player, effectiveTrader, blueprint, type(options and options.overrides) == "table" and options.overrides or nil)
    if not spec then
        return nil
    end

    spec.sourceTrader = DO.DeepCopy(effectiveTrader or spec.sourceTrader or {})
    spec.chainId = tostring(chain.id or "")
    spec.chainLabel = tostring(chain.label or chain.id)
    spec.chainStageId = tostring(stage.id or "")
    spec.chainStageIndex = tonumber(stageIndex) or 1
    spec.chainEntry = spec.chainStageIndex == 1
    spec.chainAdvanceMode = resolveChainAdvanceMode(chain, stage)
    spec.chainNextStageId = getResolvedNextStageId(chain, stage, stageIndex)
    spec.isChainQuest = true
    spec.isChainFollowup = options and options.isFollowup == true or false
    spec.bypassBlueprintCooldown = options and options.bypassCooldown == true or false

    if stage.name or stage.label then
        spec.name = tostring(stage.name or stage.label)
    end
    if stage.dialogueTree then
        spec.dialogueTree = tostring(stage.dialogueTree)
    end
    if tonumber(stage.offerWeight) then
        spec.offerWeight = tonumber(stage.offerWeight)
    end

    return spec
end

local function markChainQuestStarted(store, quest)
    if not store or not quest or not quest.chainId or not quest.chainStageId then
        return nil
    end

    local progress = getChainProgress(store, quest.chainId, true)
    if not progress then
        return nil
    end

    progress.activeQuestID = quest.id
    progress.activeStageId = quest.chainStageId
    progress.nextStageId = quest.chainNextStageId
    progress.pendingOffer = nil
    progress.completed = false
    progress.lastStartedAt = DO.NowMs and DO.NowMs() or nil
    progress.sourceTrader = type(quest.sourceTrader) == "table" and DO.DeepCopy(quest.sourceTrader) or progress.sourceTrader
    return progress
end

local function clearChainProgress(store, quest, status)
    if not store or not quest or not quest.chainId then
        return nil
    end

    local progress = getChainProgress(store, quest.chainId, true)
    if not progress then
        return nil
    end

    progress.activeQuestID = nil
    progress.activeStageId = nil
    progress.pendingOffer = nil
    progress.nextStageId = nil
    progress.completed = false
    progress.lastStatus = tostring(status or quest.status or "ended")
    progress.lastEndedAt = DO.NowMs and DO.NowMs() or nil
    return progress
end

local function buildPendingChainOffer(store, player, traderContext)
    if not store or type(store.chainProgress) ~= "table" then
        return nil
    end

    local traderID = traderContext and tostring(traderContext.traderID or traderContext.id or "") or ""

    for _, chain in ipairs(DO.GetQuestChainList and DO.GetQuestChainList() or {}) do
        local progress = getChainProgress(store, chain.id, false)
        local pending = progress and progress.pendingOffer or nil
        if type(pending) == "table" and pending.stageId and pending.blueprintId then
            local sourceTrader = type(pending.sourceTrader) == "table" and pending.sourceTrader or {}
            local pendingTraderID = tostring(sourceTrader.traderID or sourceTrader.id or "")
            if pendingTraderID == "" or traderID == "" or pendingTraderID == traderID then
                local stage = getChainStage(chain, pending.stageId)
                local spec = buildChainStageSpec(player, sourceTrader, chain, stage, {
                    traderContext = sourceTrader,
                    isFollowup = true,
                    bypassCooldown = true,
                })
                local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint(pending.blueprintId) or nil
                if spec and blueprint then
                    chainLog(
                        "Resolved pending follow-up chain=" .. tostring(chain.id or "")
                            .. " stage=" .. tostring(stage and stage.id or pending.stageId)
                            .. " traderId=" .. tostring(sourceTrader.traderID or sourceTrader.id or "")
                    )
                    return {
                        blueprintId = tostring(blueprint.id or pending.blueprintId),
                        blueprint = blueprint,
                        activeQuest = nil,
                        cooldownRemainingHours = 0,
                        canStart = true,
                        weight = tonumber(stage and stage.offerWeight) or tonumber(spec.offerWeight) or tonumber(blueprint.weight) or 1,
                        questSpec = spec,
                        dialogueTree = spec.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(spec.dialogueTree) or Runtime.resolveBlueprintDialogueTree(blueprint),
                        isChainFollowup = true,
                        chainId = tostring(chain.id or ""),
                        chainStageId = tostring(stage and stage.id or pending.stageId),
                        sourceTrader = DO.DeepCopy(sourceTrader),
                    }
                end
            end
        end
    end

    return nil
end

local function buildEntryChainSpec(player, traderContext, blueprint, store)
    if type(blueprint) ~= "table" then
        return nil
    end

    local chain, stage = findChainEntryStageForBlueprint(blueprint.id)
    if not chain or not stage then
        return Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
    end

    local progress = getChainProgress(store, chain.id, false)
    if progress and (progress.activeQuestID or progress.pendingOffer) then
        return Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
    end

    return buildChainStageSpec(player, traderContext, chain, stage, {
        traderContext = traderContext,
    }) or Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
end

local function completeQuestChain(player, store, quest)
    if not store or not quest or not quest.chainId or not quest.chainStageId then
        return nil
    end

    local chain = getChain(quest.chainId)
    if not chain then
        return nil
    end

    local currentStage, currentStageIndex = getChainStage(chain, quest.chainStageId)
    if not currentStage then
        return nil
    end

    local progress = getChainProgress(store, quest.chainId, true)
    if not progress then
        return nil
    end

    progress.activeQuestID = nil
    progress.activeStageId = nil
    progress.lastCompletedStageId = tostring(currentStage.id)
    progress.lastCompletedQuestID = quest.id
    progress.lastCompletedAt = DO.NowMs and DO.NowMs() or nil
    progress.sourceTrader = type(quest.sourceTrader) == "table" and DO.DeepCopy(quest.sourceTrader) or progress.sourceTrader

    local nextStage = getNextChainStage(chain, currentStage)
    if not nextStage then
        progress.nextStageId = nil
        progress.pendingOffer = nil
        progress.completed = true
        chainLog(
            "Completed final stage chain=" .. tostring(chain.id or quest.chainId)
                .. " stage=" .. tostring(currentStage.id or quest.chainStageId)
        )
        return nil
    end

    progress.completed = false
    progress.nextStageId = tostring(nextStage.id or "")
    local advanceMode = resolveChainAdvanceMode(chain, currentStage)

    if advanceMode == "auto" then
        local autoSpec = buildChainStageSpec(player, progress.sourceTrader, chain, nextStage, {
            traderContext = progress.sourceTrader,
            isFollowup = true,
            bypassCooldown = true,
        })
        if autoSpec then
            chainLog(
                "Auto-starting follow-up chain=" .. tostring(chain.id or quest.chainId)
                    .. " fromStage=" .. tostring(currentStage.id or quest.chainStageId)
                    .. " toStage=" .. tostring(nextStage.id or "")
            )
            return Quests.StartQuest(player, autoSpec)
        end
        chainLog(
            "Auto-start follow-up unavailable chain=" .. tostring(chain.id or quest.chainId)
                .. " fromStage=" .. tostring(currentStage.id or quest.chainStageId)
                .. " toStage=" .. tostring(nextStage.id or "")
        )
    end

    progress.pendingOffer = {
        chainId = tostring(chain.id or quest.chainId),
        stageId = tostring(nextStage.id or ""),
        blueprintId = tostring(nextStage.blueprintId or ""),
        sourceTrader = type(progress.sourceTrader) == "table" and DO.DeepCopy(progress.sourceTrader) or {},
        unlockedAt = DO.NowMs and DO.NowMs() or nil,
    }

    chainLog(
        "Queued follow-up offer chain=" .. tostring(chain.id or quest.chainId)
            .. " fromStage=" .. tostring(currentStage.id or quest.chainStageId)
            .. " toStage=" .. tostring(nextStage.id or "")
    )

    return nil
end

Runtime.getChain = getChain
Runtime.getChainProgress = getChainProgress
Runtime.getChainStage = getChainStage
Runtime.getResolvedNextStageId = getResolvedNextStageId
Runtime.getNextChainStage = getNextChainStage
Runtime.resolveChainAdvanceMode = resolveChainAdvanceMode
Runtime.findChainEntryStageForBlueprint = findChainEntryStageForBlueprint
Runtime.buildChainStageSpec = buildChainStageSpec
Runtime.markChainQuestStarted = markChainQuestStarted
Runtime.clearChainProgress = clearChainProgress
Runtime.buildPendingChainOffer = buildPendingChainOffer
Runtime.buildEntryChainSpec = buildEntryChainSpec
Runtime.completeQuestChain = completeQuestChain
