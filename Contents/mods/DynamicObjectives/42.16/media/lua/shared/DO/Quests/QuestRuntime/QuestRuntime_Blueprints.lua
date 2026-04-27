DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function getBlueprintLedger(store, create)
    if not store then
        return nil
    end

    if create then
        store.offerLedger = type(store.offerLedger) == "table" and store.offerLedger or {}
    end

    return store.offerLedger
end

local function getBlueprintLedgerEntry(store, blueprintID, create)
    local ledger = getBlueprintLedger(store, create)
    if not ledger or not blueprintID then
        return nil
    end

    local key = tostring(blueprintID)
    if create and type(ledger[key]) ~= "table" then
        ledger[key] = {}
    end

    return ledger[key]
end

local function markBlueprintLedger(store, quest, fieldName)
    if not store or not quest or not quest.blueprintId or not fieldName then
        return
    end

    local entry = getBlueprintLedgerEntry(store, quest.blueprintId, true)
    if not entry then
        return
    end

    entry[fieldName] = Runtime.getWorldAgeHours()
    entry.lastQuestID = quest.id
    entry.lastTraderID = quest.sourceTrader and (quest.sourceTrader.traderID or quest.sourceTrader.id) or entry.lastTraderID
end

local function getPlayerFirstName(player)
    local descriptor = player and player.getDescriptor and player:getDescriptor() or nil
    local forename = descriptor and descriptor.getForename and descriptor:getForename() or nil
    if forename and forename ~= "" then
        return tostring(forename)
    end

    local username = player and player.getUsername and player:getUsername() or nil
    return tostring(username or "survivor")
end

local function getPlayerDisplayName(player)
    local username = player and player.getUsername and player:getUsername() or nil
    if username and username ~= "" then
        return tostring(username)
    end

    return getPlayerFirstName(player)
end

local function buildTraderDialogueContext(player, traderContext, blueprint, questSpec, activeQuest)
    local dialogueData = Runtime.buildProceduralDialogueTokens and Runtime.buildProceduralDialogueTokens(questSpec or activeQuest or blueprint, traderContext) or nil
    local giver = dialogueData and dialogueData.giver or {}
    local theme = dialogueData and dialogueData.theme or { label = "Mixed" }
    local traderName = tostring(giver.giverName or (traderContext and (traderContext.displayName or traderContext.name)) or "trader")
    local traderFaction = tostring(giver.giverFactionName or "Independent")
    local context = {
        player = getPlayerDisplayName(player),
        ["player.firstname"] = getPlayerFirstName(player),
        trader = traderName,
        ["trader.name"] = traderName,
        ["trader.faction"] = traderFaction,
        ["quest.name"] = tostring((questSpec and questSpec.name) or (activeQuest and activeQuest.name) or (blueprint and blueprint.name) or "Objective"),
        ["quest.title"] = tostring((questSpec and questSpec.title) or (activeQuest and activeQuest.title) or (blueprint and blueprint.title) or (questSpec and questSpec.name) or (activeQuest and activeQuest.name) or (blueprint and blueprint.name) or "Objective"),
        ["quest.theme"] = tostring((questSpec and questSpec.themeID) or (activeQuest and activeQuest.themeID) or theme.label or "Mixed"),
        ["target.label"] = tostring(
            (questSpec and questSpec.targetLocation and questSpec.targetLocation.label)
                or (activeQuest and activeQuest.targetLocation and activeQuest.targetLocation.label)
                or (blueprint and blueprint.target and (blueprint.target.label or blueprint.target.purpose))
                or "the marked objective"
        ),
        ["rewardPreview"] = tostring(
            (questSpec and questSpec.rewardPreview)
                or (activeQuest and activeQuest.rewardPreview)
                or "payment on completion"
        ),
        ["family"] = tostring(blueprint and blueprint.family or "Quest"),
        ["giver.name"] = traderName,
        ["giver.title"] = tostring(giver.giverTitle or traderName),
        ["giver.faction"] = traderFaction,
    }

    return context
end

local function formatDialogueText(text, context)
    local source = tostring(text or "")
    if source == "" then
        return source
    end

    return (string.gsub(source, "{([^}]+)}", function(token)
        local key = tostring(token or "")
        local value = context and context[key] or nil
        if value == nil or value == "" then
            return "{" .. key .. "}"
        end
        return tostring(value)
    end))
end

local function buildQuestRewardContext(location, traderContext)
    local context = Runtime.buildDebugRewardContext(location)
    if type(traderContext) == "table" then
        if not context.factionID and traderContext.factionID then
            context.factionID = tostring(traderContext.factionID)
        end
        if not context.factionName and traderContext.factionName then
            context.factionName = tostring(traderContext.factionName)
        end
    end
    return context
end

local function resolveBlueprintDialogueTree(blueprint)
    local tree = blueprint and blueprint.dialogueTree and DO.GetQuestDialogueTree and DO.GetQuestDialogueTree(blueprint.dialogueTree) or nil
    return type(tree) == "table" and DO.DeepCopy(tree) or { choices = {}, nodes = {} }
end

local function resolveBlueprintTarget(player, blueprint)
    local targetConfig = type(blueprint and blueprint.target) == "table" and blueprint.target or {}
    local resolved = Runtime.buildFallbackDestination(player, targetConfig.purpose or blueprint.name or "Objective Site")
    resolved = Runtime.normalizeLocation(resolved or {})
    resolved.label = tostring(targetConfig.label or resolved.label or blueprint.name or "Objective Site")
    resolved.radius = math.max(1, math.floor(tonumber(targetConfig.radius or resolved.radius) or 45))
    resolved.r = tonumber(targetConfig.r) or resolved.r
    resolved.g = tonumber(targetConfig.g) or resolved.g
    resolved.b = tonumber(targetConfig.b) or resolved.b
    resolved.a = tonumber(targetConfig.a) or resolved.a
    resolved.scale = tonumber(targetConfig.scale) or resolved.scale
    return resolved
end

local function resolveBlueprintRewards(blueprint, options)
    options = type(options) == "table" and options or {}
    local resolved = {}

    if type(blueprint and blueprint.rewards) == "table" then
        for _, reward in ipairs(blueprint.rewards) do
            resolved[#resolved + 1] = DO.DeepCopy(reward)
        end
    end

    if options.skipRewardPools == true then
        return resolved
    end

    local rewardPools = type(blueprint and blueprint.rewardPools) == "table" and blueprint.rewardPools or {}
    for _, poolID in ipairs(rewardPools) do
        local entry = DO.ResolveWeightedEntry and DO.ResolveWeightedEntry(poolID) or nil
        if type(entry) == "table" then
            if type(entry.rewards) == "table" and #entry.rewards > 0 then
                for _, reward in ipairs(entry.rewards) do
                    resolved[#resolved + 1] = DO.DeepCopy(reward)
                end
            elseif entry.kind or entry.type then
                resolved[#resolved + 1] = DO.DeepCopy(entry)
            end
        end
    end

    return resolved
end

local function buildBaseQuestSpecFromBlueprint(player, traderContext, blueprint, overrides, options)
    if type(blueprint) ~= "table" then
        return nil
    end

    overrides = type(overrides) == "table" and overrides or {}
    options = type(options) == "table" and options or {}

    local targetLocation = resolveBlueprintTarget(player, blueprint)
    local baseDifficulty = Runtime.normalizeDifficulty(
        overrides.baseDifficulty
            or blueprint.baseDifficulty
            or blueprint.questDifficulty
            or blueprint.difficulty
            or 1.0
    )
    local baseTimeLimitHours = math.max(0, tonumber(overrides.timeLimitHours or blueprint.timeLimitHours or blueprint.timerHours or 0) or 0)
    local timeLimitHours = Runtime.scaleQuestTimeLimit(baseTimeLimitHours)
    local rewards = resolveBlueprintRewards(blueprint, {
        skipRewardPools = options.skipRewardPools == true,
    })
    local rewardContext = buildQuestRewardContext(targetLocation, traderContext)
    local family = tostring(blueprint.family or "")
    local objectiveConfig = type(blueprint.objective) == "table" and blueprint.objective or {}

    local spec = {
        name = tostring(blueprint.name or blueprint.id),
        baseDifficulty = baseDifficulty,
        baseTimeLimitHours = baseTimeLimitHours,
        timeLimitHours = timeLimitHours,
        expirationScaled = true,
        rewardContext = rewardContext,
        targetLocation = targetLocation,
        rewards = rewards,
        blueprintId = tostring(blueprint.id or ""),
        blueprintFamily = family,
        sourceTrader = DO.DeepCopy(traderContext or {}),
        dialogueTree = blueprint.dialogueTree and tostring(blueprint.dialogueTree) or nil,
    }

    if family == "Courier" then
        local grantEntry = DO.ResolveWeightedEntry and DO.ResolveWeightedEntry(blueprint.grantItemPool) or nil
        local grantItemType = grantEntry and tostring(grantEntry.itemType or grantEntry.item or "") or nil
        spec.grantItemType = grantItemType ~= "" and grantItemType or nil
        spec.grantItemDifficulty = Runtime.normalizeDifficulty(
            (grantEntry and grantEntry.difficulty)
                or blueprint.grantItemDifficulty
                or baseDifficulty
        )
        spec.pickupLocation = Runtime.normalizeLocation(traderContext and traderContext.pickupLocation or nil)
        spec.grantItemOnPickup = spec.pickupLocation ~= nil
        spec.objectives = {}
        if spec.pickupLocation then
            spec.objectives[#spec.objectives + 1] = {
                id = "pickup_package",
                type = "pickupItem",
                label = "Pick up the package",
                required = 1,
                targetLocation = spec.pickupLocation,
                questItemType = spec.grantItemType,
            }
        end
        spec.objectives[#spec.objectives + 1] = {
            id = tostring(objectiveConfig.id or "deliver_package"),
            type = "deliverItem",
            label = tostring(objectiveConfig.label or "Deliver the package"),
            required = 1,
            questItemType = spec.grantItemType,
            consumeOnComplete = objectiveConfig.consumeOnComplete ~= false,
            radius = targetLocation.radius,
        }
    elseif family == "KillZone" then
        local encounterConfig = type(blueprint.encounter) == "table" and blueprint.encounter or {}
        local baseCount = math.max(1, math.floor(tonumber(encounterConfig.baseCount or encounterConfig.count) or 1))
        spec.encounter = {
            id = tostring(encounterConfig.id or "kill_zone_encounter"),
            kind = tostring(encounterConfig.kind or "kill_zone"),
            count = baseCount,
            spawnRadius = math.max(4, math.floor(tonumber(encounterConfig.spawnRadius) or 18)),
            clearRadius = math.max(6, math.floor(tonumber(encounterConfig.clearRadius or targetLocation.radius) or targetLocation.radius)),
            spawnMode = tostring(encounterConfig.spawnMode or "building"),
            requireAreaClear = encounterConfig.requireAreaClear ~= false,
            requirePlayerPresence = encounterConfig.requirePlayerPresence ~= false,
        }
        spec.objectives = {
            {
                id = tostring(objectiveConfig.id or "kill_zone"),
                type = "areaClear",
                label = tostring(objectiveConfig.label or "Secure the building"),
                required = 1,
                radius = targetLocation.radius,
                requireAreaClear = true,
            },
        }
    elseif family == "HuntDrop" then
        local encounterConfig = type(blueprint.encounter) == "table" and blueprint.encounter or {}
        local baseCount = math.max(1, math.floor(tonumber(encounterConfig.baseCount or encounterConfig.count) or 1))
        local dropEntry = DO.ResolveWeightedEntry and DO.ResolveWeightedEntry(blueprint.dropItemPool) or nil
        local dropItemType = dropEntry and tostring(dropEntry.itemType or dropEntry.item or "") or nil
        local returnLocation = Runtime.normalizeLocation(
            traderContext and (traderContext.pickupLocation or traderContext.location or traderContext.targetLocation) or nil
        ) or Runtime.normalizeLocation(targetLocation)
        local giverName = tostring(traderContext and (traderContext.displayName or traderContext.name or traderContext.traderName) or "the quest giver")
        local requiredSamples = math.max(
            1,
            math.min(
                baseCount,
                math.floor(
                    tonumber(
                        objectiveConfig.requiredSamples
                            or objectiveConfig.sampleCount
                            or objectiveConfig.dropRequired
                            or objectiveConfig.required
                    ) or 1
                )
            )
        )
        spec.encounter = {
            id = tostring(encounterConfig.id or "sample_hunt_encounter"),
            kind = tostring(encounterConfig.kind or "hunt_drop"),
            count = baseCount,
            spawnRadius = math.max(4, math.floor(tonumber(encounterConfig.spawnRadius) or 18)),
            clearRadius = math.max(6, math.floor(tonumber(encounterConfig.clearRadius or targetLocation.radius) or targetLocation.radius)),
            spawnMode = tostring(encounterConfig.spawnMode or "building"),
            requireAreaClear = encounterConfig.requireAreaClear ~= false,
            requirePlayerPresence = encounterConfig.requirePlayerPresence ~= false,
        }
        spec.objectives = {
            {
                id = tostring(objectiveConfig.killID or "kill_for_drop"),
                type = "kill",
                label = tostring(objectiveConfig.killLabel or "Purge the marked cluster"),
                required = baseCount,
                radius = targetLocation.radius,
                encounterOnly = true,
                requireAreaClear = spec.encounter.requireAreaClear == true,
            },
            {
                id = tostring(objectiveConfig.dropID or "recover_drop"),
                type = "obtainDrop",
                label = tostring(objectiveConfig.dropLabel or "Recover the objective"),
                required = requiredSamples,
                radius = targetLocation.radius,
                dropItemType = dropItemType ~= "" and dropItemType or nil,
                spawnAfterKills = math.max(1, math.floor(tonumber(objectiveConfig.spawnAfterKills) or 4)),
                encounterOnly = true,
                requireAreaClear = spec.encounter.requireAreaClear == true,
                completeRemainingObjectives = objectiveConfig.completeRemainingObjectives == true,
                completeQuestOnComplete = objectiveConfig.completeQuestOnComplete == true,
                completeEncounterObjectivesOnComplete = objectiveConfig.completeEncounterObjectivesOnComplete == true
                    or objectiveConfig.skipAreaClearOnComplete == true
                    or objectiveConfig.completeQuestOnComplete == true,
                skipAreaClearOnComplete = objectiveConfig.skipAreaClearOnComplete == true
                    or objectiveConfig.completeQuestOnComplete == true,
            },
            {
                id = tostring(objectiveConfig.returnID or "return_drop"),
                type = "deliverItem",
                label = tostring(
                    objectiveConfig.returnLabel
                        or ((requiredSamples > 1) and ("Return the samples to " .. giverName) or ("Return the sample to " .. giverName))
                ),
                required = requiredSamples,
                targetLocation = returnLocation,
                questItemType = dropItemType ~= "" and dropItemType or nil,
                consumeOnComplete = objectiveConfig.consumeOnReturn ~= false,
                skipAreaClearOnComplete = true,
                radius = returnLocation and returnLocation.radius or targetLocation.radius,
            },
        }
    else
        return nil
    end

    if DO.Rewards and DO.Rewards.NormalizeRewards then
        DO.Rewards.NormalizeRewards(spec, spec.rewards)
    end

    return spec
end

local function buildQuestSpecFromBlueprint(player, traderContext, blueprint, overrides)
    if type(blueprint) ~= "table" then
        return nil
    end

    overrides = type(overrides) == "table" and overrides or {}
    if Runtime.isProceduralGenerationEnabled and Runtime.isProceduralGenerationEnabled(blueprint) then
        local store = Runtime.getStore(player, true)
        local spec = Runtime.buildProceduralBlueprintSpec and Runtime.buildProceduralBlueprintSpec(player, store, traderContext, blueprint, overrides, function()
            return buildBaseQuestSpecFromBlueprint(player, traderContext, blueprint, overrides, {
                skipRewardPools = true,
            })
        end) or nil
        if spec then
            if DO.Rewards and DO.Rewards.NormalizeRewards then
                DO.Rewards.NormalizeRewards(spec, spec.rewards)
            end
            return spec
        end
    end

    return buildBaseQuestSpecFromBlueprint(player, traderContext, blueprint, overrides)
end

local function getActiveQuestForBlueprint(store, blueprintID)
    if not store or not blueprintID then
        return nil
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" and tostring(quest.blueprintId or "") == tostring(blueprintID) then
            return quest
        end
    end

    return nil
end

local function getBlueprintCooldownRemaining(store, blueprint)
    if not store or type(blueprint) ~= "table" then
        return 0
    end

    local cooldownHours = math.max(0, tonumber(blueprint.cooldown or blueprint.cooldownHours) or 0)
    if cooldownHours <= 0 then
        return 0
    end

    local entry = getBlueprintLedgerEntry(store, blueprint.id, false)
    if not entry then
        return 0
    end

    local lastUsed = math.max(
        tonumber(entry.lastCompletedAtWorldHours) or 0,
        tonumber(entry.lastFailedAtWorldHours) or 0,
        tonumber(entry.lastAbandonedAtWorldHours) or 0
    )
    if lastUsed <= 0 then
        return 0
    end

    return math.max(0, cooldownHours - (Runtime.getWorldAgeHours() - lastUsed))
end

local function blueprintMatchesEligibility(player, traderContext, blueprint)
    local eligibility = type(blueprint and blueprint.eligibility) == "table" and blueprint.eligibility or {}
    local traderID = traderContext and (traderContext.traderID or traderContext.id) or nil
    local traderState = traderContext and (traderContext.currentState or traderContext.state or traderContext.status) or nil
    local traderArchetype = traderContext and (traderContext.archetype or traderContext.role) or nil
    local factionID = traderContext and traderContext.factionID or nil

    if not Runtime.matchesNormalizedList(traderState, eligibility.traderStates)
        and not (
            Runtime.normalizeText
            and Runtime.normalizeText(traderState) == "trading"
            and Runtime.matchesNormalizedList("Resting", eligibility.traderStates)
        ) then
        return false
    end
    if not Runtime.matchesNormalizedList(traderArchetype, eligibility.archetypes) then
        return false
    end
    if not Runtime.matchesNormalizedList(factionID, eligibility.factionIDs) then
        return false
    end
    if not Runtime.matchesNormalizedList(traderID, eligibility.traderIDs) then
        return false
    end

    return true
end

local function pickWeightedOffer(offers)
    local totalWeight = 0
    for _, offer in ipairs(offers or {}) do
        totalWeight = totalWeight + math.max(0.1, tonumber(offer.weight) or 1)
    end

    if totalWeight <= 0 or #offers == 0 then
        return offers and offers[1] or nil
    end

    local roll = ZombRandFloat(0, totalWeight)
    local cursor = 0
    for _, offer in ipairs(offers) do
        cursor = cursor + math.max(0.1, tonumber(offer.weight) or 1)
        if roll <= cursor then
            return offer
        end
    end

    return offers[#offers]
end

Runtime.getBlueprintLedger = getBlueprintLedger
Runtime.getBlueprintLedgerEntry = getBlueprintLedgerEntry
Runtime.markBlueprintLedger = markBlueprintLedger
Runtime.getPlayerFirstName = getPlayerFirstName
Runtime.getPlayerDisplayName = getPlayerDisplayName
Runtime.buildTraderDialogueContext = buildTraderDialogueContext
Runtime.formatDialogueText = formatDialogueText
Runtime.buildQuestRewardContext = buildQuestRewardContext
Runtime.resolveBlueprintDialogueTree = resolveBlueprintDialogueTree
Runtime.resolveBlueprintTarget = resolveBlueprintTarget
Runtime.resolveBlueprintRewards = resolveBlueprintRewards
Runtime.buildBaseQuestSpecFromBlueprint = buildBaseQuestSpecFromBlueprint
Runtime.buildQuestSpecFromBlueprint = buildQuestSpecFromBlueprint
Runtime.getActiveQuestForBlueprint = getActiveQuestForBlueprint
Runtime.getBlueprintCooldownRemaining = getBlueprintCooldownRemaining
Runtime.blueprintMatchesEligibility = blueprintMatchesEligibility
Runtime.pickWeightedOffer = pickWeightedOffer
