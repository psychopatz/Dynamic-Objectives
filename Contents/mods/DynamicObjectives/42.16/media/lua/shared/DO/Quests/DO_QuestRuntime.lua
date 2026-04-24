DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests

Quests.MODDATA_KEY = Quests.MODDATA_KEY or "DynamicObjectives"
Quests.STATE_VERSION = Quests.STATE_VERSION or 2

local questUpdateTick = 0

local function questLog(category, topic, message)
    DO.Log(category, topic, message)
end

local function say(player, text)
    if player and player.Say then
        player:Say(tostring(text))
    end
end

local function isZombie(value)
    return value and instanceof and instanceof(value, "IsoZombie")
end

local function isLivingZombie(zombie)
    if not isZombie(zombie) then
        return false
    end

    if zombie.isDead and zombie:isDead() then
        return false
    end

    if zombie.getHealth and tonumber(zombie:getHealth()) and tonumber(zombie:getHealth()) <= 0 then
        return false
    end

    return true
end

local MAX_ZONE_TARGET_SAMPLES = 6

local function insertNearestZoneTarget(samples, zombie, referenceX, referenceY, referenceZ)
    if type(samples) ~= "table" or not zombie then
        return
    end

    local dx = (tonumber(zombie:getX()) or 0) - (tonumber(referenceX) or 0)
    local dy = (tonumber(zombie:getY()) or 0) - (tonumber(referenceY) or 0)
    local dz = (tonumber(zombie:getZ()) or 0) - (tonumber(referenceZ) or 0)
    local sample = {
        x = tonumber(zombie:getX()) or 0,
        y = tonumber(zombie:getY()) or 0,
        z = tonumber(zombie:getZ()) or 0,
        distanceSq = (dx * dx) + (dy * dy) + (dz * dz * 4),
    }

    local inserted = false
    for index = 1, #samples do
        local existing = samples[index]
        if sample.distanceSq < (existing and tonumber(existing.distanceSq) or math.huge) then
            table.insert(samples, index, sample)
            inserted = true
            break
        end
    end

    if not inserted then
        samples[#samples + 1] = sample
    end

    while #samples > MAX_ZONE_TARGET_SAMPLES do
        table.remove(samples)
    end
end

local function getStore(player, create)
    if not player then
        return nil
    end

    local modData = player:getModData()
    local store = modData[Quests.MODDATA_KEY]
    if not store and create then
        store = {
            version = Quests.STATE_VERSION,
            seq = 0,
            quests = {},
            trackedQuestID = nil,
        }
        modData[Quests.MODDATA_KEY] = store
    end

    if store and create then
        store.version = Quests.STATE_VERSION
        store.seq = tonumber(store.seq) or 0
        store.quests = type(store.quests) == "table" and store.quests or {}
        store.offerLedger = type(store.offerLedger) == "table" and store.offerLedger or {}
    end

    return store
end

local function normalizeLocation(location)
    if type(location) ~= "table" then
        return nil
    end

    return {
        x = math.floor(tonumber(location.x) or 0),
        y = math.floor(tonumber(location.y) or 0),
        z = math.floor(tonumber(location.z) or 0),
        label = tostring(location.label or "Objective Site"),
        symbolID = tostring(location.symbolID or "DOQuestTarget"),
        worldIcon = tostring(location.worldIcon or "loot.png"),
        r = tonumber(location.r) or 1.0,
        g = tonumber(location.g) or 0.85,
        b = tonumber(location.b) or 0.2,
        a = tonumber(location.a) or 1.0,
        scale = tonumber(location.scale) or 1.0,
        radius = math.max(1, math.floor(tonumber(location.radius) or 45)),
        source = location.source,
        town = location.town,
        county = location.county,
    }
end

local function nextQuestID(player, store)
    store.seq = (tonumber(store.seq) or 0) + 1
    return string.format(
        "DOQ_%s_%d_%d",
        tostring(DO.GetPlayerKey(player)):gsub("[^%w_:%-]", "_"),
        tonumber(store.seq) or 0,
        math.floor(ZombRand(100000, 999999))
    )
end

local function buildFallbackDestination(player, purpose)
    if DO.Integration and DO.Integration.V2 and DO.Integration.V2.ResolveDebugDestination then
        return DO.Integration.V2.ResolveDebugDestination(player, purpose)
    end
    return nil
end

local function buildDebugRewardContext(location)
    if type(location) ~= "table" or not ModData or not ModData.get then
        return {}
    end

    local data = ModData.get("DynamicTrading_Factions")
    if type(data) ~= "table" then
        return {}
    end

    local bestID = nil
    local bestFaction = nil
    local bestDistance = nil
    local targetTown = location.town and tostring(location.town):lower() or ""
    for factionID, faction in pairs(data) do
        if type(faction) == "table" then
            local home = type(faction.homeCoords) == "table" and faction.homeCoords or nil
            local hx = home and tonumber(home.x) or nil
            local hy = home and tonumber(home.y) or nil
            if hx and hy then
                local dx = hx - (tonumber(location.x) or 0)
                local dy = hy - (tonumber(location.y) or 0)
                local distance = math.sqrt((dx * dx) + (dy * dy))
                local factionTown = faction.town and tostring(faction.town):lower() or ""
                local townBias = (targetTown ~= "" and factionTown == targetTown) and -250 or 0
                local score = distance + townBias
                if not bestDistance or score < bestDistance then
                    bestDistance = score
                    bestID = tostring(factionID)
                    bestFaction = faction
                end
            end
        end
    end

    if not bestID then
        return {}
    end

    return {
        factionID = bestID,
        factionName = bestFaction and tostring(bestFaction.name or bestID) or bestID,
    }
end

local function normalizeDifficulty(value)
    local difficulty = tonumber(value) or 1.0
    if difficulty <= 0 then
        return 1.0
    end
    return difficulty
end

local function getConfiguredQuestDifficulty()
    local sandbox = SandboxVars and SandboxVars.DynamicObjectives or nil
    return normalizeDifficulty(sandbox and sandbox.QuestDifficulty or 1.0)
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return tonumber(gameTime:getWorldAgeHours()) or 0
    end
    return 0
end

local function clampDifficulty(value)
    return math.max(0.5, math.min(100.0, normalizeDifficulty(value)))
end

local function getQuestDifficultyLabel(value)
    local difficulty = clampDifficulty(value)
    if difficulty >= 2.35 then
        return "Deadly"
    elseif difficulty >= 1.7 then
        return "Hard"
    elseif difficulty >= 1.15 then
        return "Standard"
    elseif difficulty >= 0.8 then
        return "Light"
    end
    return "Easy"
end

local function resolveQuestDifficulty(player, quest, location)
    local configured = getConfiguredQuestDifficulty()
    local explicitBase = quest and (quest.baseDifficulty or quest.questDifficulty or quest.difficulty) or nil
    local baseDifficulty = normalizeDifficulty(explicitBase or configured)

    if quest and quest.dynamicDifficulty == false then
        return clampDifficulty(baseDifficulty), {
            base = baseDifficulty,
            configured = configured,
            distanceFactor = 1.0,
            radiusFactor = 1.0,
            kindFactor = 1.0,
            randomFactor = 1.0,
        }
    end

    local distanceFactor = 1.0
    if player and location then
        local dx = (tonumber(location.x) or 0) - (tonumber(player:getX()) or 0)
        local dy = (tonumber(location.y) or 0) - (tonumber(player:getY()) or 0)
        local distance = math.sqrt((dx * dx) + (dy * dy))
        distanceFactor = 1.0 + math.min(0.55, distance / 1200)
    end

    local radius = location and math.max(1, tonumber(location.radius) or 45) or 45
    local radiusFactor = 1.0
    if radius <= 20 then
        radiusFactor = 1.18
    elseif radius <= 30 then
        radiusFactor = 1.1
    elseif radius >= 60 then
        radiusFactor = 0.92
    end

    local encounterKind = quest and quest.encounter and tostring(quest.encounter.kind or "") or ""
    local kindFactor = 1.0
    if encounterKind == "hunt_drop" then
        kindFactor = 1.12
    elseif encounterKind == "kill_zone" then
        kindFactor = 1.0
    elseif encounterKind ~= "" then
        kindFactor = 1.05
    end

    local randomFactor = ZombRand(82, 131) / 100
    local resolved = clampDifficulty(baseDifficulty * distanceFactor * radiusFactor * kindFactor * randomFactor)

    return resolved, {
        base = baseDifficulty,
        configured = configured,
        distanceFactor = distanceFactor,
        radiusFactor = radiusFactor,
        kindFactor = kindFactor,
        randomFactor = randomFactor,
    }
end

local function scaleCountForDifficulty(count, difficulty)
    local baseCount = math.max(1, math.floor(tonumber(count) or 1))
    local scale = normalizeDifficulty(difficulty)
    return math.max(1, math.floor((baseCount * scale) + 0.5))
end

local function normalizeText(value)
    return string.lower(tostring(value or ""))
end

local function matchesNormalizedList(value, list)
    if type(list) ~= "table" or #list == 0 then
        return true
    end

    local probe = normalizeText(value)
    for _, candidate in ipairs(list) do
        local normalized = normalizeText(candidate)
        if normalized == "" or normalized == "*" or normalized == "any" or normalized == probe then
            return true
        end
    end

    return false
end

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

    entry[fieldName] = getWorldAgeHours()
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
    local context = {
        player = getPlayerDisplayName(player),
        ["player.firstname"] = getPlayerFirstName(player),
        trader = tostring(traderContext and (traderContext.displayName or traderContext.name) or "trader"),
        ["trader.name"] = tostring(traderContext and (traderContext.displayName or traderContext.name) or "trader"),
        ["quest.name"] = tostring((questSpec and questSpec.name) or (activeQuest and activeQuest.name) or (blueprint and blueprint.name) or "Objective"),
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
    local context = buildDebugRewardContext(location)
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
    local resolved = buildFallbackDestination(player, targetConfig.purpose or blueprint.name or "Objective Site")
    resolved = normalizeLocation(resolved or {})
    resolved.label = tostring(targetConfig.label or resolved.label or blueprint.name or "Objective Site")
    resolved.radius = math.max(1, math.floor(tonumber(targetConfig.radius or resolved.radius) or 45))
    resolved.r = tonumber(targetConfig.r) or resolved.r
    resolved.g = tonumber(targetConfig.g) or resolved.g
    resolved.b = tonumber(targetConfig.b) or resolved.b
    resolved.a = tonumber(targetConfig.a) or resolved.a
    resolved.scale = tonumber(targetConfig.scale) or resolved.scale
    return resolved
end

local function resolveBlueprintRewards(blueprint)
    local resolved = {}

    if type(blueprint and blueprint.rewards) == "table" then
        for _, reward in ipairs(blueprint.rewards) do
            resolved[#resolved + 1] = DO.DeepCopy(reward)
        end
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

local function buildQuestSpecFromBlueprint(player, traderContext, blueprint, overrides)
    if type(blueprint) ~= "table" then
        return nil
    end

    overrides = type(overrides) == "table" and overrides or {}

    local targetLocation = resolveBlueprintTarget(player, blueprint)
    local baseDifficulty = normalizeDifficulty(
        overrides.baseDifficulty
            or blueprint.baseDifficulty
            or blueprint.questDifficulty
            or blueprint.difficulty
            or 1.0
    )
    local timeLimitHours = math.max(0, tonumber(overrides.timeLimitHours or blueprint.timeLimitHours or blueprint.timerHours or 0) or 0)
    local rewards = resolveBlueprintRewards(blueprint)
    local rewardContext = buildQuestRewardContext(targetLocation, traderContext)
    local family = tostring(blueprint.family or "")
    local objectiveConfig = type(blueprint.objective) == "table" and blueprint.objective or {}

    local spec = {
        name = tostring(blueprint.name or blueprint.id),
        baseDifficulty = baseDifficulty,
        timeLimitHours = timeLimitHours,
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
        spec.grantItemDifficulty = normalizeDifficulty(
            (grantEntry and grantEntry.difficulty)
                or blueprint.grantItemDifficulty
                or baseDifficulty
        )
        spec.objectives = {
            {
                id = tostring(objectiveConfig.id or "deliver_package"),
                type = "deliverItem",
                label = tostring(objectiveConfig.label or "Deliver the package"),
                required = 1,
                questItemType = spec.grantItemType,
                consumeOnComplete = objectiveConfig.consumeOnComplete ~= false,
                radius = targetLocation.radius,
            },
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
                type = "kill",
                label = tostring(objectiveConfig.label or "Eliminate the infestation"),
                required = baseCount,
                radius = targetLocation.radius,
                encounterOnly = true,
                requireAreaClear = spec.encounter.requireAreaClear == true,
            },
        }
    elseif family == "HuntDrop" then
        local encounterConfig = type(blueprint.encounter) == "table" and blueprint.encounter or {}
        local baseCount = math.max(1, math.floor(tonumber(encounterConfig.baseCount or encounterConfig.count) or 1))
        local dropEntry = DO.ResolveWeightedEntry and DO.ResolveWeightedEntry(blueprint.dropItemPool) or nil
        local dropItemType = dropEntry and tostring(dropEntry.itemType or dropEntry.item or "") or nil
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
                required = 1,
                radius = targetLocation.radius,
                dropItemType = dropItemType ~= "" and dropItemType or nil,
                spawnAfterKills = math.max(1, math.floor(tonumber(objectiveConfig.spawnAfterKills) or 4)),
                encounterOnly = true,
                requireAreaClear = spec.encounter.requireAreaClear == true,
                completeRemainingObjectives = objectiveConfig.completeRemainingObjectives == true,
                completeQuestOnComplete = objectiveConfig.completeQuestOnComplete == true,
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

    return math.max(0, cooldownHours - (getWorldAgeHours() - lastUsed))
end

local function blueprintMatchesEligibility(player, traderContext, blueprint)
    local eligibility = type(blueprint and blueprint.eligibility) == "table" and blueprint.eligibility or {}
    local traderID = traderContext and (traderContext.traderID or traderContext.id) or nil
    local traderState = traderContext and (traderContext.currentState or traderContext.state or traderContext.status) or nil
    local traderArchetype = traderContext and (traderContext.archetype or traderContext.role) or nil
    local factionID = traderContext and traderContext.factionID or nil

    if not matchesNormalizedList(traderState, eligibility.traderStates) then
        return false
    end
    if not matchesNormalizedList(traderArchetype, eligibility.archetypes) then
        return false
    end
    if not matchesNormalizedList(factionID, eligibility.factionIDs) then
        return false
    end
    if not matchesNormalizedList(traderID, eligibility.traderIDs) then
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

local function normalizeEncounter(quest, encounter)
    if type(encounter) ~= "table" then
        return nil
    end

    local location = normalizeLocation(encounter.location or quest.targetLocation)
    local difficulty = normalizeDifficulty(encounter.difficulty or (quest and quest.difficulty) or 1.0)
    local baseCount = math.max(1, math.floor(tonumber(encounter.baseCount or encounter.count) or 1))
    local count = scaleCountForDifficulty(baseCount, difficulty)
    local spawnRadius = math.max(4, math.floor(tonumber(encounter.spawnRadius or (location and location.radius) or 18)))
    local clearRadius = math.max(spawnRadius, math.floor(tonumber(encounter.clearRadius or (location and location.radius) or spawnRadius)))

    return {
        id = tostring(encounter.id or "encounter_main"),
        kind = tostring(encounter.kind or "kill_zone"),
        difficulty = difficulty,
        baseCount = baseCount,
        count = count,
        spawnedCount = math.max(0, math.floor(tonumber(encounter.spawnedCount) or 0)),
        spawned = encounter.spawned == true,
        spawnRequested = encounter.spawnRequested == true,
        spawnedAt = tonumber(encounter.spawnedAt) or nil,
        lastSpawnAttemptAt = tonumber(encounter.lastSpawnAttemptAt) or nil,
        location = location,
        spawnRadius = spawnRadius,
        clearRadius = clearRadius,
        spawnMode = tostring(encounter.spawnMode or "building"),
        activationRadius = math.max(
            18,
            math.floor(tonumber(encounter.activationRadius) or math.max(clearRadius + 10, spawnRadius + 18))
        ),
        requirePlayerPresence = encounter.requirePlayerPresence ~= false,
        requireAreaClear = encounter.requireAreaClear ~= false,
        questOnlyKills = encounter.questOnlyKills ~= false,
        outfit = encounter.outfit and tostring(encounter.outfit) or nil,
        femaleChance = tonumber(encounter.femaleChance) or 50,
    }
end

local function normalizeObjective(index, quest, objective)
    local normalized = DO.DeepCopy(objective or {})
    normalized.id = tostring(normalized.id or ("objective_" .. tostring(index)))
    normalized.type = tostring(normalized.type or "kill")
    normalized.label = tostring(normalized.label or normalized.id)
    normalized.requiredBase = math.max(1, math.floor(tonumber(normalized.requiredBase or normalized.required) or 1))
    normalized.required = normalized.requiredBase
    normalized.progress = math.max(0, math.floor(tonumber(normalized.progress) or 0))
    normalized.completed = normalized.completed == true
    normalized.radius = math.max(
        1,
        math.floor(tonumber(normalized.radius or normalized.zoneRadius or (quest.targetLocation and quest.targetLocation.radius)) or 45)
    )
    normalized.targetLocation = normalizeLocation(normalized.targetLocation)
    normalized.dropState = type(normalized.dropState) == "table" and normalized.dropState or {}
    normalized.spawnAfterKillsBase = math.max(
        1,
        math.floor(tonumber(normalized.spawnAfterKillsBase or normalized.spawnAfterKills) or normalized.requiredBase)
    )
    normalized.spawnAfterKills = normalized.spawnAfterKillsBase
    normalized.dropItemType = normalized.dropItemType and tostring(normalized.dropItemType) or nil
    normalized.consumeOnComplete = normalized.consumeOnComplete == true
    normalized.killProgress = math.max(0, math.floor(tonumber(normalized.killProgress) or 0))
    normalized.requireAreaClear = normalized.requireAreaClear == true or (quest.encounter and quest.encounter.requireAreaClear == true)
    normalized.encounterOnly = normalized.encounterOnly ~= false and quest.encounter ~= nil
    normalized.questItemType = normalized.questItemType and tostring(normalized.questItemType) or nil
    normalized.completeQuestOnComplete = normalized.completeQuestOnComplete == true
    normalized.completeRemainingObjectives = normalized.completeRemainingObjectives == true or normalized.completeQuestOnComplete == true
    return normalized
end

local function syncEncounterObjectiveCounts(quest)
    if not quest or not quest.encounter then
        return
    end

    local encounterBaseCount = math.max(1, math.floor(tonumber(quest.encounter.baseCount or quest.encounter.count) or 1))
    local encounterCount = math.max(1, math.floor(tonumber(quest.encounter.count) or 1))
    local encounterScale = encounterCount / encounterBaseCount
    for _, objective in ipairs(quest.objectives or {}) do
        if objective.type == "kill" and objective.encounterOnly == true then
            objective.required = encounterCount
            objective.progress = math.min(objective.required, tonumber(objective.progress) or 0)
            objective.completed = objective.progress >= objective.required
        elseif objective.type == "obtainDrop" then
            local baseKills = math.max(1, math.floor(tonumber(objective.spawnAfterKillsBase or objective.spawnAfterKills) or 1))
            objective.spawnAfterKills = math.min(
                encounterCount,
                math.max(1, math.floor((baseKills * encounterScale) + 0.5))
            )
        end
    end
end

local function questLocationFor(quest, objective)
    if objective and objective.targetLocation then
        return objective.targetLocation
    end

    if quest and quest.encounter and quest.encounter.location then
        return quest.encounter.location
    end

    return quest and quest.targetLocation or nil
end

local function isWithinLocation(location, x, y, z)
    if not location then
        return true
    end

    if z ~= nil and tonumber(location.z or 0) ~= tonumber(z or 0) then
        return false
    end

    local dx = (tonumber(x) or 0) - (tonumber(location.x) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(location.y) or 0)
    local radius = math.max(1, tonumber(location.radius) or 45)
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function isWithinRadius(location, radius, x, y, z)
    if not location then
        return true
    end

    if z ~= nil and tonumber(location.z or 0) ~= tonumber(z or 0) then
        return false
    end

    local dx = (tonumber(x) or 0) - (tonumber(location.x) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(location.y) or 0)
    local targetRadius = math.max(1, tonumber(radius) or tonumber(location.radius) or 45)
    return (dx * dx + dy * dy) <= (targetRadius * targetRadius)
end

local function objectivesComplete(quest)
    for _, objective in ipairs(quest.objectives or {}) do
        if objective.completed ~= true then
            return false
        end
    end
    return true
end

local function findQuest(store, questID)
    if not store or not questID then
        return nil
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.id == questID then
            return quest
        end
    end

    return nil
end

local function resolveTrackedQuest(player, store)
    if not store then
        return nil
    end

    local tracked = findQuest(store, store.trackedQuestID)
    if tracked and tracked.status == "active" then
        for _, quest in ipairs(store.quests or {}) do
            quest.tracked = quest.id == tracked.id
        end
        return tracked
    end

    store.trackedQuestID = nil
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            store.trackedQuestID = quest.id
            tracked = quest
            break
        end
    end

    for _, quest in ipairs(store.quests or {}) do
        quest.tracked = tracked and quest.id == tracked.id or false
    end

    return tracked
end

local function onQuestStateChanged(player)
    DO.NotifyStateChanged(player)
end

local function removeQuestItemByQuestID(player, questID)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.IsQuestItem == true and modData.QuestID == questID
    end)

    for _, item in ipairs(items) do
        Quests.RemoveInventoryItem(item)
    end
end

local function removeQuestDropsByQuestID(player, questID)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.DOQuestDrop == true and modData.DOQuestID == questID
    end)

    for _, item in ipairs(items) do
        Quests.RemoveInventoryItem(item)
    end
end

local function markObjectiveCompleted(objective)
    if not objective then
        return false
    end

    local required = math.max(1, math.floor(tonumber(objective.required) or 1))
    local changed = objective.completed ~= true or tonumber(objective.progress) ~= required
    objective.progress = required
    objective.completed = true
    return changed
end

local function completeObjectivesAfter(quest, objectiveID)
    if not quest or not objectiveID then
        return false
    end

    local found = false
    local changed = false
    for _, objective in ipairs(quest.objectives or {}) do
        if found then
            changed = markObjectiveCompleted(objective) or changed
        elseif objective.id == objectiveID then
            found = true
        end
    end

    return changed
end

local function countObjectiveDropItems(player, questID, objectiveID)
    local playerKey = DO.GetPlayerKey(player)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData
            and modData.DOQuestDrop == true
            and modData.DOQuestID == questID
            and modData.DOQuestObjectiveID == objectiveID
            and (not modData.DOQuestPlayerKey or modData.DOQuestPlayerKey == playerKey)
    end)

    return #items, items
end

local function isQuestEncounterZombie(player, quest, zombie)
    local modData = zombie and zombie:getModData() or nil
    if not modData or not quest then
        return false
    end

    return modData.DOQuestSpawn == true
        and modData.DOQuestEncounterQuestID == quest.id
        and modData.DOQuestEncounterPlayerKey == DO.GetPlayerKey(player)
end

local function doesZombieMatchEncounter(player, quest, zombie, objective)
    if not objective or objective.encounterOnly ~= true then
        return true
    end

    local encounter = quest and quest.encounter or nil
    if not encounter or encounter.questOnlyKills ~= true then
        return true
    end

    return isQuestEncounterZombie(player, quest, zombie)
end

local function gatherLiveZoneState(player, quest, objective)
    local location = questLocationFor(quest, objective)
    local encounter = quest and quest.encounter or nil
    local clearRadius = encounter and encounter.clearRadius or (location and location.radius) or 45
    local playerPresent = false
    local nearbyCount = 0
    local targetSamples = {}
    local playerX = player and tonumber(player:getX()) or (location and tonumber(location.x) or 0)
    local playerY = player and tonumber(player:getY()) or (location and tonumber(location.y) or 0)
    local playerZ = player and tonumber(player:getZ()) or (location and tonumber(location.z) or 0)

    if player and location then
        playerPresent = isWithinRadius(location, clearRadius + 8, player:getX(), player:getY(), player:getZ())
    end

    local cell = getCell and getCell() or nil
    local zombieList = cell and cell.getZombieList and cell:getZombieList() or nil
    if zombieList and location then
        for index = 0, zombieList:size() - 1 do
            local zombie = zombieList:get(index)
            if isLivingZombie(zombie)
                and isWithinRadius(location, clearRadius, zombie:getX(), zombie:getY(), zombie:getZ())
            then
                nearbyCount = nearbyCount + 1
                insertNearestZoneTarget(targetSamples, zombie, playerX, playerY, playerZ)
            end
        end
    end

    local areaClear = nearbyCount <= 0
    if encounter and encounter.requirePlayerPresence == true and not playerPresent then
        areaClear = false
    end
    if encounter and encounter.spawned ~= true then
        areaClear = false
    end

    return {
        location = location,
        clearRadius = clearRadius,
        nearbyZombies = nearbyCount,
        playerPresent = playerPresent,
        areaClear = areaClear,
        encounterSpawned = encounter and encounter.spawned == true or false,
        targetSamples = targetSamples,
        closestTarget = targetSamples[1],
    }
end

local function getPendingObjective(quest)
    if not quest then
        return nil
    end

    for _, objective in ipairs(quest.objectives or {}) do
        if objective.completed ~= true then
            return objective
        end
    end

    return quest.objectives and quest.objectives[#quest.objectives] or nil
end

local function questRequiresAreaClear(quest)
    if quest and quest.skipAreaClear == true then
        return false
    end

    if quest and quest.encounter and quest.encounter.requireAreaClear == true then
        return true
    end

    for _, objective in ipairs(quest and quest.objectives or {}) do
        if objective.requireAreaClear == true then
            return true
        end
    end

    return false
end

local function buildAreaClearText(zoneState)
    if not zoneState then
        return nil
    end

    if zoneState.encounterSpawned ~= true then
        if zoneState.playerPresent == true then
            return "Searching the building..."
        end
        return "Move closer to trigger the encounter"
    end

    if zoneState.areaClear == true then
        return "Area secure"
    end

    if zoneState.playerPresent ~= true then
        return "Return to the marked zone"
    end

    return string.format("Nearby zeds: %d", math.max(0, tonumber(zoneState.nearbyZombies) or 0))
end

local function getQuestRemainingHours(quest)
    if not quest or tonumber(quest.timeLimitHours) == nil or tonumber(quest.timeLimitHours) <= 0 then
        return nil
    end

    local expiresAt = tonumber(quest.expiresAtWorldHours)
    if not expiresAt then
        return nil
    end

    return math.max(0, expiresAt - getWorldAgeHours())
end

function Quests.GetStore(player, create)
    return getStore(player, create)
end

function Quests.GetEligibleTraderOffers(player, traderContext)
    local results = {}
    local store = getStore(player, true)
    if not store or not DO.GetQuestBlueprintList then
        return results
    end

    for _, blueprint in ipairs(DO.GetQuestBlueprintList()) do
        if blueprint and blueprint.enabled ~= false and blueprintMatchesEligibility(player, traderContext, blueprint) then
            local activeQuest = getActiveQuestForBlueprint(store, blueprint.id)
            local cooldownRemaining = getBlueprintCooldownRemaining(store, blueprint)
            local questSpec = nil
            if not activeQuest and cooldownRemaining <= 0 then
                questSpec = buildQuestSpecFromBlueprint(player, traderContext, blueprint)
            end

            results[#results + 1] = {
                blueprintId = blueprint.id,
                blueprint = blueprint,
                activeQuest = activeQuest,
                cooldownRemainingHours = cooldownRemaining,
                canStart = activeQuest == nil and cooldownRemaining <= 0 and questSpec ~= nil,
                weight = tonumber(blueprint.weight) or 1,
                questSpec = questSpec,
                dialogueTree = resolveBlueprintDialogueTree(blueprint),
            }
        end
    end

    return results
end

function Quests.BuildTraderQuestOffer(player, traderContext)
    local offers = Quests.GetEligibleTraderOffers(player, traderContext)
    if #offers == 0 then
        return nil
    end

    local startable = {}
    local active = {}
    local blocked = {}

    for _, offer in ipairs(offers) do
        if offer.canStart == true then
            startable[#startable + 1] = offer
        elseif offer.activeQuest then
            active[#active + 1] = offer
        else
            blocked[#blocked + 1] = offer
        end
    end

    local selected = pickWeightedOffer(#startable > 0 and startable or (#active > 0 and active or blocked))
    if not selected then
        return nil
    end

    local blueprint = selected.blueprint
    local tree = selected.dialogueTree or { nodes = {}, choices = {} }
    local context = buildTraderDialogueContext(player, traderContext, blueprint, selected.questSpec, selected.activeQuest)

    selected.choiceLabels = {
        accept = tostring(tree.choices and tree.choices.accept or "Accept"),
        details = tostring(tree.choices and tree.choices.details or "Tell me more"),
        rewards = tostring(tree.choices and tree.choices.rewards or "What's the reward?"),
        decline = tostring(tree.choices and tree.choices.decline or "Not now"),
        back = tostring(tree.choices and tree.choices.back or "Back"),
    }

    local activeQuest = selected.activeQuest
    if activeQuest then
        context["rewardPreview"] = tostring(activeQuest.rewardPreview or context["rewardPreview"])
        context["quest.name"] = tostring(activeQuest.name or context["quest.name"])
        if activeQuest.targetLocation and activeQuest.targetLocation.label then
            context["target.label"] = tostring(activeQuest.targetLocation.label)
        end
    end

    local unavailableSuffix = ""
    if tonumber(selected.cooldownRemainingHours) and tonumber(selected.cooldownRemainingHours) > 0 then
        unavailableSuffix = string.format(" Check back in %.1f hours.", tonumber(selected.cooldownRemainingHours))
    end

    selected.resolvedDialogue = {
        offer = formatDialogueText(tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        details = formatDialogueText(tree.nodes and tree.nodes.details and tree.nodes.details.text or tree.nodes and tree.nodes.offer and tree.nodes.offer.text or "", context),
        rewards = formatDialogueText(tree.nodes and tree.nodes.rewards and tree.nodes.rewards.text or "", context),
        accept = formatDialogueText(tree.nodes and tree.nodes.accept and tree.nodes.accept.text or "Objective accepted.", context),
        decline = formatDialogueText(tree.nodes and tree.nodes.decline and tree.nodes.decline.text or "Maybe later.", context),
        active = formatDialogueText(
            tree.nodes and tree.nodes.active and tree.nodes.active.text or (activeQuest and Quests.BuildSummaryText(activeQuest, player) or "You already have this objective."),
            context
        ),
        unavailable = formatDialogueText(
            tree.nodes and tree.nodes.unavailable and tree.nodes.unavailable.text or ("No work from me right now." .. unavailableSuffix),
            context
        ),
    }

    if activeQuest then
        selected.progressSummary = Quests.BuildSummaryText(activeQuest, player)
    elseif selected.questSpec then
        selected.progressSummary = Quests.BuildSummaryText(selected.questSpec, player)
    end

    return selected
end

function Quests.StartQuestFromBlueprint(player, traderContext, blueprintID)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if not blueprint then
        return nil
    end

    local store = getStore(player, true)
    if getActiveQuestForBlueprint(store, blueprint.id) then
        return nil
    end
    if getBlueprintCooldownRemaining(store, blueprint) > 0 then
        return nil
    end

    local spec = buildQuestSpecFromBlueprint(player, traderContext, blueprint)
    if not spec then
        return nil
    end

    return Quests.StartQuest(player, spec)
end

function Quests.StartQuestFromResolvedOffer(player, offer)
    if not player or type(offer) ~= "table" or type(offer.questSpec) ~= "table" then
        return nil
    end

    local blueprintID = offer.blueprintId or (offer.questSpec and offer.questSpec.blueprintId) or nil
    local blueprint = blueprintID and DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    local store = getStore(player, true)
    if blueprint and (getActiveQuestForBlueprint(store, blueprint.id) or getBlueprintCooldownRemaining(store, blueprint) > 0) then
        return nil
    end

    return Quests.StartQuest(player, DO.DeepCopy(offer.questSpec))
end

function Quests.GetActiveQuests(player)
    local store = getStore(player, false)
    if not store then
        return {}
    end

    local results = {}
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = quest
        end
    end

    return results
end

function Quests.GetTrackedQuest(player)
    local store = getStore(player, false)
    if not store then
        return nil
    end

    return resolveTrackedQuest(player, store)
end

function Quests.GetQuest(player, questID)
    local store = getStore(player, false)
    return findQuest(store, questID)
end

function Quests.GetEncounterStatus(player, quest)
    if not player or not quest or quest.status ~= "active" or not questRequiresAreaClear(quest) then
        return nil
    end

    return gatherLiveZoneState(player, quest, getPendingObjective(quest))
end

function Quests.GetClearanceTargetData(player, quest)
    local zoneState = Quests.GetEncounterStatus(player, quest)
    if not zoneState or zoneState.areaClear == true or zoneState.encounterSpawned ~= true then
        return nil
    end

    local targets = zoneState.targetSamples or {}
    if #targets == 0 then
        return nil
    end

    return {
        questID = quest.id,
        questName = tostring(quest.name or quest.id),
        location = zoneState.location,
        clearRadius = zoneState.clearRadius,
        nearbyZombies = zoneState.nearbyZombies,
        playerPresent = zoneState.playerPresent,
        targetSamples = DO.DeepCopy(targets),
    }
end

function Quests.GetTrackedClearanceTargetData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    return Quests.GetClearanceTargetData(player, quest)
end

function Quests.GetTrackedMarkerData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    local location = quest.targetLocation
    if not location then
        return nil
    end

    return {
        questID = quest.id,
        name = quest.name,
        description = tostring(location.label or quest.name or "Tracked Objective"),
        x = location.x,
        y = location.y,
        z = location.z,
        symbolID = location.symbolID or "DOQuestTarget",
        worldIcon = location.worldIcon or "loot.png",
        r = location.r,
        g = location.g,
        b = location.b,
        a = location.a,
        scale = location.scale,
    }
end

function Quests.BuildSummaryText(quest, player)
    local parts = {}
    for _, objective in ipairs(quest.objectives or {}) do
        local progress = math.max(0, math.floor(tonumber(objective.progress) or 0))
        local required = math.max(1, math.floor(tonumber(objective.required) or 1))
        parts[#parts + 1] = string.format("%s %d/%d", tostring(objective.label or objective.type), progress, required)
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    if zoneState then
        parts[#parts + 1] = buildAreaClearText(zoneState)
    end

    local remainingHours = getQuestRemainingHours(quest)
    if remainingHours ~= nil then
        parts[#parts + 1] = string.format("Time left %.1fh", remainingHours)
    end

    if quest.rewardPreview and quest.rewardPreview ~= "" then
        parts[#parts + 1] = "Rewards " .. tostring(quest.rewardPreview)
    end

    local suffix = quest.tracked and " [Tracked]" or ""
    return string.format("%s%s - %s", tostring(quest.name or quest.id), suffix, table.concat(parts, " | "))
end

function Quests.GetActiveQuestSummary(player)
    local results = {}
    local store = getStore(player, false)
    if not store then
        return results
    end

    resolveTrackedQuest(player, store)

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = {
                questID = quest.id,
                name = quest.name,
                tracked = quest.tracked == true,
                display = Quests.BuildSummaryText(quest, player),
                targetLabel = quest.targetLocation and quest.targetLocation.label or nil,
            }
        end
    end

    return results
end

function Quests.GetTrackedObjectiveUIData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    local lines = {}
    local totalSteps = #(quest.objectives or {})
    local currentStep = totalSteps > 0 and totalSteps or 1
    local currentObjective = nil
    local activeKillObjective = nil
    local currentObjectiveLabel = nil

    for index, objective in ipairs(quest.objectives or {}) do
        if not currentObjective and objective.completed ~= true then
            currentObjective = objective
            currentStep = index
            currentObjectiveLabel = tostring(objective.label or objective.id)
        end

        if not activeKillObjective and objective.type == "kill" and objective.completed ~= true then
            activeKillObjective = objective
        end

        local progress = math.max(0, tonumber(objective.progress) or 0)
        local required = math.max(1, tonumber(objective.required) or 1)
        local line = {
            id = objective.id,
            label = tostring(objective.label or objective.type),
            completed = objective.completed == true,
            current = objective.completed ~= true and currentObjective and currentObjective.id == objective.id,
            objectiveType = objective.type,
            progress = progress,
            required = required,
            remaining = math.max(0, required - progress),
        }

        if objective.type == "kill" then
            line.value = string.format(
                "%d / %d zombies",
                progress,
                required
            )
        elseif objective.type == "obtainDrop" then
            if objective.completed == true then
                line.value = "Recovered"
            else
                line.value = objective.dropState and objective.dropState.spawned and "Loot the marked corpse drop" or "Keep clearing the zone"
            end
        elseif objective.type == "deliverItem" then
            line.value = objective.completed == true and "Delivered" or "Take the package to the marker"
        else
            line.value = string.format("%d / %d", tonumber(objective.progress) or 0, tonumber(objective.required) or 0)
        end

        lines[#lines + 1] = line
    end

    if zoneState then
        local zoneCurrent = currentObjective == nil and zoneState.areaClear ~= true
        lines[#lines + 1] = {
            id = "zone_clear",
            label = "Secure the building",
            value = buildAreaClearText(zoneState),
            completed = zoneState.areaClear == true,
            accent = zoneState.areaClear == true and "good" or "warn",
            current = zoneCurrent,
        }
        totalSteps = totalSteps + 1
        if zoneCurrent then
            currentStep = totalSteps
            currentObjectiveLabel = "Secure the building"
        end

        if zoneState.encounterSpawned == true and zoneState.areaClear ~= true and #(zoneState.targetSamples or {}) > 0 then
            lines[#lines + 1] = {
                id = "zone_locator",
                label = "Zombie Locator",
                value = string.format("%d closest zeds highlighted", #(zoneState.targetSamples or {})),
                completed = false,
                current = false,
                accent = "info",
            }
        end
    end

    if not currentObjective then
        currentObjective = quest.objectives and quest.objectives[#quest.objectives] or nil
    end

    local primaryProgress = nil
    if activeKillObjective then
        local killProgress = math.max(0, tonumber(activeKillObjective.progress) or 0)
        local killRequired = math.max(1, tonumber(activeKillObjective.required) or 1)
        primaryProgress = {
            label = "Zombies Cleared",
            value = string.format("%d / %d", killProgress, killRequired),
            detail = string.format("%d remaining", math.max(0, killRequired - killProgress)),
            ratio = killProgress / killRequired,
            color = { r = 0.86, g = 0.28, b = 0.22 },
        }
        if quest.encounter and quest.encounter.spawned ~= true then
            primaryProgress.detail = zoneState and buildAreaClearText(zoneState) or "Move closer to trigger the encounter"
            primaryProgress.ratio = 0
        end
    elseif zoneState then
        primaryProgress = {
            label = "Zone Status",
            value = zoneState.areaClear == true and "Secure" or "Active",
            detail = buildAreaClearText(zoneState),
            ratio = zoneState.areaClear == true and 1 or 0,
            color = zoneState.areaClear == true and { r = 0.34, g = 0.82, b = 0.48 } or { r = 0.95, g = 0.62, b = 0.18 },
        }
    end

    return {
        questID = quest.id,
        name = tostring(quest.name or quest.id),
        targetLabel = quest.targetLocation and tostring(quest.targetLocation.label or "") or "",
        targetLocation = quest.targetLocation,
        difficulty = normalizeDifficulty(quest.difficulty),
        rewardPreview = quest.rewardPreview and tostring(quest.rewardPreview) or nil,
        timeLimitHours = tonumber(quest.timeLimitHours) or 0,
        timeRemainingHours = getQuestRemainingHours(quest),
        currentStep = currentStep,
        totalSteps = math.max(1, totalSteps),
        currentObjectiveLabel = currentObjectiveLabel
            or (currentObjective and tostring(currentObjective.label or currentObjective.id))
            or "Objective",
        difficultyLabel = tostring(quest.difficultyLabel or getQuestDifficultyLabel(quest.difficulty)),
        primaryProgress = primaryProgress,
        lines = lines,
        zoneState = zoneState,
        encounter = quest.encounter,
    }
end

function Quests.GetLatestCompletedQuest(player)
    local store = getStore(player, false)
    if not store then
        return nil
    end

    local latest = nil
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "completed" and tonumber(quest.completedAt) then
            if not latest or tonumber(quest.completedAt) > tonumber(latest.completedAt or 0) then
                latest = quest
            end
        end
    end

    return latest
end

function Quests.SetTrackedQuest(player, questID)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local tracked = findQuest(store, questID)
    if not tracked or tracked.status ~= "active" then
        return false
    end

    store.trackedQuestID = tracked.id
    for _, quest in ipairs(store.quests or {}) do
        quest.tracked = quest.id == tracked.id
    end

    say(player, "Tracking objective: " .. tostring(tracked.name))
    onQuestStateChanged(player)
    return true
end

function Quests.AbandonQuest(player, questID)
    local store = getStore(player, true)
    if not store then
        return false
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.id == questID and quest.status == "active" then
            quest.status = "abandoned"
            quest.tracked = false
            quest.abandonedAt = DO.NowMs()
            removeQuestItemByQuestID(player, quest.id)
            removeQuestDropsByQuestID(player, quest.id)
            markBlueprintLedger(store, quest, "lastAbandonedAtWorldHours")
            if store.trackedQuestID == quest.id then
                store.trackedQuestID = nil
            end
            resolveTrackedQuest(player, store)
            say(player, "Objective abandoned: " .. tostring(quest.name))
            onQuestStateChanged(player)
            return true
        end
    end

    return false
end

function Quests.CompleteQuest(player, questID, reason)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local quest = findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    if DO.Rewards and DO.Rewards.GrantQuestRewards then
        DO.Rewards.GrantQuestRewards(player, quest)
    end

    quest.status = "completed"
    quest.tracked = false
    quest.completedAt = DO.NowMs()
    quest.completionReason = reason or "completed"
    markBlueprintLedger(store, quest, "lastCompletedAtWorldHours")

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end

    resolveTrackedQuest(player, store)
    say(player, "Objective complete: " .. tostring(quest.name))
    onQuestStateChanged(player)
    return true
end

function Quests.FailQuest(player, questID, reason)
    local store = getStore(player, true)
    if not store then
        return false
    end

    local quest = findQuest(store, questID)
    if not quest or quest.status ~= "active" then
        return false
    end

    quest.status = "failed"
    quest.tracked = false
    quest.failedAt = DO.NowMs()
    quest.failureReason = reason or "failed"
    markBlueprintLedger(store, quest, "lastFailedAtWorldHours")

    removeQuestItemByQuestID(player, quest.id)
    removeQuestDropsByQuestID(player, quest.id)

    if store.trackedQuestID == quest.id then
        store.trackedQuestID = nil
    end

    resolveTrackedQuest(player, store)
    say(player, "Objective failed: " .. tostring(quest.name))
    onQuestStateChanged(player)
    return true
end

local function applyEncounterSpawnResult(quest, spawnedCount)
    if not quest or not quest.encounter then
        return
    end

    local encounter = quest.encounter
    encounter.lastSpawnAttemptAt = DO.NowMs()
    encounter.spawnedCount = math.max(0, math.floor(tonumber(spawnedCount) or 0))
    if encounter.spawnedCount > 0 then
        encounter.spawned = true
        encounter.spawnRequested = false
        encounter.spawnedAt = encounter.spawnedAt or encounter.lastSpawnAttemptAt
        encounter.count = encounter.spawnedCount
        syncEncounterObjectiveCounts(quest)
    else
        encounter.spawned = false
        encounter.spawnRequested = false
    end
end

function Quests.ApplyEncounterSpawnResult(player, questID, spawnedCount)
    local quest = Quests.GetQuest(player, questID)
    if not quest then
        return false
    end

    applyEncounterSpawnResult(quest, spawnedCount)
    onQuestStateChanged(player)
    return true
end

local function getSquareAt(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
end

local function getBuildingKey(building)
    local def = building and building.getDef and building:getDef() or nil
    if def and def.getKeyId then
        return tostring(def:getKeyId())
    end
    return nil
end

local function resolveSpawnBuilding(location)
    if not location then
        return nil
    end

    local directSquare = getSquareAt(location.x, location.y, location.z)
    if directSquare and directSquare.getBuilding then
        local building = directSquare:getBuilding()
        if building then
            return building
        end
    end

    local searchRadius = 4
    local bestBuilding = nil
    local bestDistanceSq = nil
    local baseX = math.floor(tonumber(location.x) or 0)
    local baseY = math.floor(tonumber(location.y) or 0)
    local baseZ = math.floor(tonumber(location.z) or 0)

    for dx = -searchRadius, searchRadius do
        for dy = -searchRadius, searchRadius do
            local square = getSquareAt(baseX + dx, baseY + dy, baseZ)
            local building = square and square.getBuilding and square:getBuilding() or nil
            if building then
                local distanceSq = (dx * dx) + (dy * dy)
                if not bestDistanceSq or distanceSq < bestDistanceSq then
                    bestBuilding = building
                    bestDistanceSq = distanceSq
                end
            end
        end
    end

    return bestBuilding
end

local function isValidSpawnSquare(square, buildingKey)
    if not square then
        return false
    end

    if square.isSolid and square:isSolid() then
        return false
    end

    if square.isSolidTrans and square:isSolidTrans() then
        return false
    end

    if buildingKey then
        if not square.getRoom or not square:getRoom() then
            return false
        end

        local building = square.getBuilding and square:getBuilding() or nil
        if getBuildingKey(building) ~= buildingKey then
            return false
        end
    end

    return true
end

local function buildZSearchOrder(baseZ)
    local order = {}
    local seen = {}
    local function add(z)
        z = math.floor(tonumber(z) or 0)
        if z < 0 or z > 7 or seen[z] then
            return
        end
        seen[z] = true
        order[#order + 1] = z
    end

    add(baseZ)
    add(baseZ + 1)
    add(baseZ - 1)

    for z = 0, 7 do
        add(z)
    end

    return order
end

local function findSpawnPointInBuilding(location, building)
    local def = building and building.getDef and building:getDef() or nil
    if not def then
        return nil
    end

    local minX = math.floor(tonumber(def:getX()) or 0)
    local minY = math.floor(tonumber(def:getY()) or 0)
    local width = math.max(1, math.floor(tonumber(def:getW()) or 1))
    local height = math.max(1, math.floor(tonumber(def:getH()) or 1))
    local maxX = minX + width - 1
    local maxY = minY + height - 1
    local buildingKey = getBuildingKey(building)
    local zOrder = buildZSearchOrder(location and location.z or 0)

    for _ = 1, 80 do
        local x = ZombRand(minX, maxX + 1)
        local y = ZombRand(minY, maxY + 1)
        local z = zOrder[ZombRand(0, #zOrder) + 1]
        local square = getSquareAt(x, y, z)
        if isValidSpawnSquare(square, buildingKey) then
            return x, y, z
        end
    end

    for _, z in ipairs(zOrder) do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = getSquareAt(x, y, z)
                if isValidSpawnSquare(square, buildingKey) then
                    return x, y, z
                end
            end
        end
    end

    return nil
end

local function findSpawnPoint(location, radius, spawnMode)
    local cell = getCell and getCell() or nil
    if not cell or not location then
        return location and location.x or 0, location and location.y or 0, location and location.z or 0, "fallback"
    end

    if spawnMode ~= "zone" then
        local building = resolveSpawnBuilding(location)
        if building then
            local spawnX, spawnY, spawnZ = findSpawnPointInBuilding(location, building)
            if spawnX ~= nil and spawnY ~= nil then
                return spawnX, spawnY, spawnZ, "building"
            end
        end
    end

    local z = tonumber(location.z) or 0
    local maxRadius = math.max(2, math.floor(tonumber(radius) or tonumber(location.radius) or 10))

    for _ = 1, 25 do
        local x = ZombRand(math.floor(location.x - maxRadius), math.floor(location.x + maxRadius + 1))
        local y = ZombRand(math.floor(location.y - maxRadius), math.floor(location.y + maxRadius + 1))
        local square = cell:getGridSquare(x, y, z)
        if square and not square:isSolid() and not square:isSolidTrans() then
            return x, y, z, "zone"
        end
    end

    return location.x, location.y, z, "fallback"
end

local function stampQuestSpawn(zombie, player, quest, encounter)
    if not zombie or not player or not quest then
        return
    end

    local modData = zombie:getModData()
    modData.DOQuestSpawn = true
    modData.DOQuestEncounterQuestID = quest.id
    modData.DOQuestEncounterID = encounter and encounter.id or "encounter_main"
    modData.DOQuestEncounterPlayerKey = DO.GetPlayerKey(player)
end

function Quests.SpawnQuestEncounterFromData(player, data)
    if not player or type(data) ~= "table" then
        return 0
    end

    local location = normalizeLocation(data.location)
    if not location or not addZombiesInOutfit then
        return 0
    end

    local count = math.max(1, math.floor(tonumber(data.count) or 1))
    local outfit = data.outfit and tostring(data.outfit) or nil
    local femaleChance = tonumber(data.femaleChance) or 50
    local spawnRadius = math.max(4, math.floor(tonumber(data.spawnRadius) or tonumber(location.radius) or 12))
    local spawnMode = tostring(data.spawnMode or "building")
    local spawnedCount = 0
    local usedMode = "fallback"

    local quest = {
        id = tostring(data.questID or "unknown"),
    }
    local encounter = {
        id = tostring(data.encounterID or "encounter_main"),
    }

    for _ = 1, count do
        local spawnX, spawnY, spawnZ, resolvedMode = findSpawnPoint(location, spawnRadius, spawnMode)
        local zombieList = addZombiesInOutfit(spawnX, spawnY, spawnZ, 1, outfit, femaleChance)
        if zombieList and zombieList.size and zombieList:size() > 0 then
            local zombie = zombieList:get(0)
            stampQuestSpawn(zombie, player, quest, encounter)
            spawnedCount = spawnedCount + 1
            usedMode = resolvedMode or usedMode
        end
    end

    questLog(
        "Quest",
        "Spawn",
        "Spawned encounter for " .. tostring(data.questID) .. " count=" .. tostring(spawnedCount) .. " mode=" .. tostring(usedMode)
    )
    return spawnedCount
end

function Quests.RequestEncounterSpawn(player, quest)
    if not player or not quest or not quest.encounter then
        return false
    end

    if quest.encounter.spawned == true or quest.encounter.spawnRequested == true then
        return false
    end

    quest.encounter.spawnRequested = true
    quest.encounter.lastSpawnAttemptAt = DO.NowMs()

    local payload = {
        questID = quest.id,
        encounterID = quest.encounter.id,
        count = quest.encounter.count,
        outfit = quest.encounter.outfit,
        femaleChance = quest.encounter.femaleChance,
        spawnRadius = quest.encounter.spawnRadius,
        spawnMode = quest.encounter.spawnMode,
        location = quest.encounter.location or quest.targetLocation,
    }

    if isClient() and not isServer() then
        sendClientCommand(player, "DynamicObjectives", "SpawnQuestEncounter", payload)
        return true
    end

    local spawnedCount = Quests.SpawnQuestEncounterFromData(player, payload)
    applyEncounterSpawnResult(quest, spawnedCount)
    return true
end

local function isEncounterActivationReady(player, quest)
    local encounter = quest and quest.encounter or nil
    local location = encounter and (encounter.location or quest.targetLocation) or nil
    if not player or not encounter or encounter.spawned == true or not location then
        return false
    end

    local activationRadius = math.max(18, tonumber(encounter.activationRadius) or 50)
    if not isWithinRadius(location, activationRadius, player:getX(), player:getY(), player:getZ()) then
        return false
    end

    if not getSquareAt(location.x, location.y, location.z) and not resolveSpawnBuilding(location) then
        return false
    end

    return true
end

function Quests.StartQuest(player, spec)
    if not player or type(spec) ~= "table" then
        return nil
    end

    local store = getStore(player, true)
    if not store then
        return nil
    end

    local quest = DO.DeepCopy(spec)
    quest.id = quest.id or nextQuestID(player, store)
    quest.name = tostring(quest.name or quest.id)
    quest.status = "active"
    quest.createdAt = DO.NowMs()
    quest.startedAtWorldHours = getWorldAgeHours()
    quest.playerKey = DO.GetPlayerKey(player)
    quest.targetLocation = normalizeLocation(quest.targetLocation or buildFallbackDestination(player, quest.name))
    quest.baseDifficulty = normalizeDifficulty(quest.baseDifficulty or quest.questDifficulty or quest.difficulty or getConfiguredQuestDifficulty())
    quest.difficulty, quest.difficultyFactors = resolveQuestDifficulty(player, quest, quest.targetLocation)
    quest.difficultyLabel = getQuestDifficultyLabel(quest.difficulty)
    quest.timeLimitHours = math.max(0, tonumber(quest.timeLimitHours or quest.timerHours or quest.expireHours) or 0)
    if quest.timeLimitHours > 0 then
        quest.expiresAtWorldHours = quest.startedAtWorldHours + quest.timeLimitHours
    else
        quest.expiresAtWorldHours = nil
    end
    quest.encounter = normalizeEncounter(quest, quest.encounter)
    quest.objectives = type(quest.objectives) == "table" and quest.objectives or {}

    for index, objective in ipairs(quest.objectives) do
        quest.objectives[index] = normalizeObjective(index, quest, objective)
    end

    if #quest.objectives == 0 then
        quest.objectives[1] = normalizeObjective(1, quest, {
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

    syncEncounterObjectiveCounts(quest)

    store.quests[#store.quests + 1] = quest
    markBlueprintLedger(store, quest, "lastStartedAtWorldHours")

    if not store.trackedQuestID then
        store.trackedQuestID = quest.id
        quest.tracked = true
    else
        quest.tracked = store.trackedQuestID == quest.id
    end

    if quest.grantItemType and Quests.RequestSpawnQuestItem then
        Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
    end

    say(player, "Objective accepted: " .. tostring(quest.name))
    questLog("Quest", "Runtime", "Started quest " .. tostring(quest.id))
    onQuestStateChanged(player)
    return quest
end

function Quests.BuildDebugKillZoneQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_kill_zone") or nil
    return buildQuestSpecFromBlueprint(player, {
        traderID = "debug_manager",
        displayName = "Debug Manager",
        currentState = "Resting",
    }, blueprint or {}, {
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
    })
end

function Quests.BuildDebugHuntQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_hunt_drop") or nil
    return buildQuestSpecFromBlueprint(player, {
        traderID = "debug_manager",
        displayName = "Debug Manager",
        currentState = "Resting",
    }, blueprint or {}, {
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
    })
end

function Quests.BuildDebugCourierQuest(player, difficulty, timeLimitHours)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_courier_run") or nil
    return buildQuestSpecFromBlueprint(player, {
        traderID = "debug_manager",
        displayName = "Debug Manager",
        currentState = "Resting",
    }, blueprint or {}, {
        baseDifficulty = difficulty and normalizeDifficulty(difficulty) or nil,
        timeLimitHours = math.max(0, tonumber(timeLimitHours) or 0),
    })
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

function Quests.DumpState(player)
    local store = getStore(player, false)
    if not store then
        questLog("Quest", "Dump", "No Dynamic Objectives state found")
        return
    end

    questLog("Quest", "Dump", "========================================================")
    questLog("Quest", "Dump", " DYNAMIC OBJECTIVES STATE DUMP")
    questLog("Quest", "Dump", "========================================================")
    questLog("Quest", "Dump", "Tracked Quest: " .. tostring(store.trackedQuestID))

    for _, quest in ipairs(store.quests or {}) do
        questLog("Quest", "Dump", string.format("%s [%s]", tostring(quest.name), tostring(quest.status)))
        if quest.encounter then
            questLog(
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
            questLog(
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

    questLog("Quest", "Dump", "========================================================")
end

local function shouldCompleteQuest(player, quest)
    if not objectivesComplete(quest) then
        return false
    end

    if not questRequiresAreaClear(quest) then
        return true
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    return zoneState and zoneState.areaClear == true
end

function Quests.OnZombieKilled(player, zombie)
    local store = getStore(player, true)
    if not store or not zombie then
        return false
    end

    local changed = false

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true and (objective.type == "kill" or objective.type == "obtainDrop") then
                    local location = questLocationFor(quest, objective)
                    if doesZombieMatchEncounter(player, quest, zombie, objective)
                        and isWithinLocation(location, zombie:getX(), zombie:getY(), zombie:getZ())
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
        onQuestStateChanged(player)
    end

    return changed
end

function Quests.OnPlayerQuestUpdate(player)
    if not player then
        return
    end

    questUpdateTick = questUpdateTick + 1
    if questUpdateTick < 20 then
        return
    end
    questUpdateTick = 0

    local store = getStore(player, false)
    if not store then
        return
    end

    local changed = false
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            local remainingHours = getQuestRemainingHours(quest)
            if remainingHours ~= nil and remainingHours <= 0 then
                Quests.FailQuest(player, quest.id, "time_expired")
                return
            end

            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true then
                    if quest.encounter and quest.encounter.spawned ~= true and isEncounterActivationReady(player, quest) then
                        if Quests.RequestEncounterSpawn(player, quest) then
                            changed = true
                        end
                    end

                    if objective.type == "obtainDrop" then
                        local count = countObjectiveDropItems(player, quest.id, objective.id)
                        if count > 0 then
                            changed = markObjectiveCompleted(objective) or changed
                            if objective.completeRemainingObjectives == true then
                                changed = completeObjectivesAfter(quest, objective.id) or changed
                            end
                            if objective.completeQuestOnComplete == true then
                                quest.skipAreaClear = true
                                Quests.CompleteQuest(player, quest.id, "objective_completed")
                                return
                            end
                            changed = true
                        end
                    elseif objective.type == "deliverItem" then
                        local location = questLocationFor(quest, objective)
                        if isWithinLocation(location, px, py, pz) then
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
        onQuestStateChanged(player)
    end
end

if not (isServer() and not isClient()) then
    Events.OnPlayerUpdate.Add(Quests.OnPlayerQuestUpdate)
end
