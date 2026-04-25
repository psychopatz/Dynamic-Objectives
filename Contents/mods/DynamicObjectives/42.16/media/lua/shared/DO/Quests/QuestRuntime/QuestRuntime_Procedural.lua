DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local DEFAULT_TTL_HOURS = 6
local MAX_RECENT_SIGNATURES = 5

local THEME_REGISTRY = {
    medical = {
        label = "Medical",
        noun = "relief",
        adjective = "medical",
        preferredTags = { "Medical.General", "Medical.Healthcare", "Tool.Medical", "Theme.Clinical" },
    },
    combat = {
        label = "Combat",
        noun = "arsenal",
        adjective = "combat",
        preferredTags = { "Weapon.Ranged", "Weapon.Melee", "Weapon.Ranged.Ammo", "Theme.Combat" },
    },
    survival = {
        label = "Survival",
        noun = "survival",
        adjective = "survival",
        preferredTags = { "Building.Survival", "Theme.Survival", "Tool.General", "Clothing.Accessory.Utility" },
    },
    engineering = {
        label = "Engineering",
        noun = "repair",
        adjective = "engineering",
        preferredTags = { "Electronics", "Tool.General", "Resource.Material.Hardware", "Theme.Industrial" },
    },
    food = {
        label = "Food",
        noun = "ration",
        adjective = "food",
        preferredTags = { "Food.NonPerishable", "Food.Perishable", "Food.Drink", "Container.Food" },
    },
    scavenge = {
        label = "Scavenge",
        noun = "recovery",
        adjective = "salvage",
        preferredTags = { "Misc.General", "Resource.Material.General", "Container.Storage", "Clothing" },
    },
    fuel = {
        label = "Fuel",
        noun = "fuel",
        adjective = "fuel",
        preferredTags = { "Resource.Fuel", "Electronics.Battery", "Building.Vehicle", "Tool.General" },
    },
    mixed = {
        label = "Mixed",
        noun = "supply",
        adjective = "mixed",
        preferredTags = { "Misc.General", "Tool.General", "Food.NonPerishable", "Medical.General" },
    },
}

local FAMILY_LABELS = {
    Courier = "Courier",
    KillZone = "Sweep",
    HuntDrop = "Recovery",
    Escort = "Escort",
}

local IDENTITY_TEMPLATES = {
    Courier = {
        names = {
            "{themeLabel} Route",
            "{themeLabel} Run",
            "{themeLabel} Dispatch",
            "{themeLabel} Courier",
        },
        titles = {
            "{giverTitle} Dispatch: {themeLabel} Courier Run",
            "{giverName}'s {themeLabel} Delivery Contract",
            "{themeLabel} Transit Request for {giverFactionName}",
        },
    },
    KillZone = {
        names = {
            "{themeLabel} Sweep",
            "{themeLabel} Purge",
            "{themeLabel} Kill Zone",
            "{themeLabel} Clearance",
        },
        titles = {
            "{giverTitle} Contract: {themeLabel} Kill Zone Sweep",
            "{themeLabel} Extermination Order from {giverName}",
            "{giverFactionName} {themeLabel} Hotspot Cleanup",
        },
    },
    HuntDrop = {
        names = {
            "{themeLabel} Hunt",
            "{themeLabel} Recovery",
            "{themeLabel} Sample Run",
            "{themeLabel} Retrieval",
        },
        titles = {
            "{giverTitle} Request: {themeLabel} Hunt and Recover",
            "{themeLabel} Recovery Contract for {giverFactionName}",
            "{giverName}'s {themeLabel} Sample Hunt",
        },
    },
    Escort = {
        names = {
            "{giverName} Escort",
            "{themeLabel} Rescue",
            "{themeLabel} Return Trip",
        },
        titles = {
            "Escort {giverName} Back to {giverFactionName}",
            "{giverTitle} Distress Call: {themeLabel} Escort",
            "{themeLabel} Rescue Route for {giverName}",
        },
    },
}

local FAMILY_OBJECTIVE_LABELS = {
    Courier = {
        medical = "Deliver the medical shipment",
        combat = "Deliver the combat package",
        survival = "Deliver the survival crate",
        engineering = "Deliver the repair package",
        food = "Deliver the ration package",
        scavenge = "Deliver the salvage bundle",
        fuel = "Deliver the fuel package",
        mixed = "Deliver the contract package",
    },
    KillZone = {
        medical = "Clear the clinic hotspot",
        combat = "Eliminate the hostile cluster",
        survival = "Secure the survivor holdout",
        engineering = "Clear the machine yard",
        food = "Clear the ration depot",
        scavenge = "Sweep the scavenging site",
        fuel = "Secure the fuel cache",
        mixed = "Eliminate the infestation",
    },
    HuntDrop = {
        medical = {
            kill = "Purge the marked medical cluster",
            drop = "Recover the field sample",
            returnDrop = "Return the field sample",
        },
        combat = {
            kill = "Purge the hostile knot",
            drop = "Recover the weapons cache",
            returnDrop = "Deliver the weapons cache",
        },
        survival = {
            kill = "Break the marked cluster",
            drop = "Recover the survival cache",
            returnDrop = "Return the survival cache",
        },
        engineering = {
            kill = "Purge the machine yard cluster",
            drop = "Recover the repair parts",
            returnDrop = "Deliver the repair parts",
        },
        food = {
            kill = "Purge the ration site cluster",
            drop = "Recover the ration bundle",
            returnDrop = "Return the ration bundle",
        },
        scavenge = {
            kill = "Purge the scavenging cluster",
            drop = "Recover the salvage parcel",
            returnDrop = "Deliver the salvage parcel",
        },
        fuel = {
            kill = "Purge the fuel depot cluster",
            drop = "Recover the fuel cache",
            returnDrop = "Return the fuel cache",
        },
        mixed = {
            kill = "Purge the marked cluster",
            drop = "Recover the objective",
            returnDrop = "Return the objective",
        },
    },
    Escort = {
        medical = "Keep the medic alive and moving",
        combat = "Escort the trader through the hot zone",
        survival = "Get the trader back to safety",
        engineering = "Protect the trader on the return route",
        food = "Get the supplier home alive",
        scavenge = "Escort the scavenger back to base",
        fuel = "Protect the hauler on the return route",
        mixed = "Guide the trader back to base",
    },
}

local function deepCopy(value)
    return DO.DeepCopy and DO.DeepCopy(value) or value
end

local function normalizeText(value)
    return string.lower(tostring(value or ""))
end

local function trimText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function formatTemplate(template, tokens)
    local source = tostring(template or "")
    return (source:gsub("{([^}]+)}", function(token)
        local value = tokens and tokens[token] or nil
        return tostring(value or "")
    end))
end

local function randomIndex(size)
    if size <= 0 then
        return nil
    end
    return ZombRand(size) + 1
end

local function chooseFromList(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    local index = randomIndex(#list)
    return index and list[index] or nil
end

local function itemMatchesTag(itemTags, targetTag)
    local probe = normalizeText(targetTag)
    if probe == "" then
        return false
    end

    for _, rawTag in ipairs(type(itemTags) == "table" and itemTags or {}) do
        local itemTag = normalizeText(rawTag)
        if itemTag == probe or itemTag:find("^" .. probe:gsub("%.", "%%.") .. "%.") then
            return true
        end
        if probe:find("^" .. itemTag:gsub("%.", "%%.") .. "%.") then
            return true
        end
    end

    return false
end

local function countTagMatches(itemTags, wantedTags)
    local matches = 0
    for _, tag in ipairs(type(wantedTags) == "table" and wantedTags or {}) do
        if itemMatchesTag(itemTags, tag) then
            matches = matches + 1
        end
    end
    return matches
end

local function getArchetype(archetypeID)
    if not archetypeID or not DynamicTrading or not DynamicTrading.Archetypes then
        return nil
    end
    return DynamicTrading.Archetypes[tostring(archetypeID)]
end

local function getArchetypeLabel(archetypeID)
    local archetype = getArchetype(archetypeID)
    if archetype and archetype.name then
        return tostring(archetype.name)
    end
    return tostring(archetypeID or "Contract Broker")
end

local function getIndependentFactionName()
    return "Independent"
end

local function humanizeID(value)
    local text = tostring(value or "")
    text = text:gsub("_%d+$", "")
    text = text:gsub("[%_%-]+", " ")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return (text:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function resolveFactionDisplayName(factionID, fallback)
    local id = factionID and tostring(factionID) or nil
    if id and id ~= "" and DynamicTrading_Factions and DynamicTrading_Factions.GetFaction then
        local ok, faction = pcall(function()
            return DynamicTrading_Factions.GetFaction(id)
        end)
        if ok and type(faction) == "table" and faction.name and tostring(faction.name) ~= "" then
            return tostring(faction.name)
        end
    end

    if id and id ~= "" and ModData and ModData.get then
        local factionData = ModData.get("DynamicTrading_Factions")
        local faction = type(factionData) == "table" and factionData[id] or nil
        if type(faction) == "table" and faction.name and tostring(faction.name) ~= "" then
            return tostring(faction.name)
        end
    end

    local fallbackText = fallback and tostring(fallback) or ""
    if fallbackText ~= "" and fallbackText ~= id then
        return fallbackText
    end

    return humanizeID(id) or humanizeID(fallbackText) or getIndependentFactionName()
end

local function resolveGiverContext(traderContext, overrides)
    traderContext = type(traderContext) == "table" and traderContext or {}
    overrides = type(overrides) == "table" and overrides or {}

    local archetypeID = overrides.archetypeID or traderContext.archetype or traderContext.role or "General"
    local factionID = overrides.factionID or traderContext.factionID or traderContext.factionId or nil
    local factionName = resolveFactionDisplayName(
        factionID,
        overrides.factionName or traderContext.factionName or traderContext.faction
    )
    local giverName = overrides.giverName or traderContext.displayName or traderContext.name or traderContext.traderName or "Contract Broker"
    local giverTitle = overrides.giverTitle or getArchetypeLabel(archetypeID)

    return {
        giverName = tostring(giverName),
        giverTitle = tostring(giverTitle ~= "" and giverTitle or "Contract Broker"),
        giverFactionID = factionID and tostring(factionID) or nil,
        giverFactionName = tostring(factionName ~= "" and factionName or getIndependentFactionName()),
        archetypeID = archetypeID and tostring(archetypeID) or nil,
        traderID = traderContext.traderID or traderContext.id or overrides.traderID or nil,
        traderState = traderContext.currentState or traderContext.state or traderContext.status or overrides.traderState or nil,
    }
end

local function ensureProceduralState(store, create)
    if not store then
        return nil, nil
    end

    if create then
        store.proceduralOfferCache = type(store.proceduralOfferCache) == "table" and store.proceduralOfferCache or {}
        store.proceduralOfferHistory = type(store.proceduralOfferHistory) == "table" and store.proceduralOfferHistory or {}
    end

    local cache = store.proceduralOfferCache
    local history = store.proceduralOfferHistory
    if history then
        history.recentSignatures = type(history.recentSignatures) == "table" and history.recentSignatures or {}
        history.lastThemeByTrader = type(history.lastThemeByTrader) == "table" and history.lastThemeByTrader or {}
    end

    return cache, history
end

local function trimRecentHistory(recent)
    while #recent > MAX_RECENT_SIGNATURES do
        table.remove(recent, 1)
    end
end

local function pushRecentSignature(history, signature)
    if not history or not signature or signature == "" then
        return
    end
    history.recentSignatures[#history.recentSignatures + 1] = tostring(signature)
    trimRecentHistory(history.recentSignatures)
end

local function buildContextSignature(giver, extra)
    extra = type(extra) == "table" and extra or {}
    return table.concat({
        tostring(giver and giver.traderID or "none"),
        tostring(giver and giver.traderState or "none"),
        tostring(giver and giver.giverFactionID or giver and giver.giverFactionName or "none"),
        tostring(extra.blueprintId or extra.hookId or "none"),
        tostring(extra.routeBucket or "none"),
        tostring(extra.objectiveSeed or "none"),
        tostring(extra.rewardTableVersion or "none"),
    }, "|")
end

local function findRecentSignature(history, signature)
    if not history or not signature then
        return false
    end

    for _, value in ipairs(history.recentSignatures or {}) do
        if tostring(value) == tostring(signature) then
            return true
        end
    end
    return false
end

local function getTheme(themeID)
    return THEME_REGISTRY[tostring(themeID or "mixed")] or THEME_REGISTRY.mixed
end

local function buildThemeWeights(profile, family, archetype, history, giver)
    local weights = {}
    local lastTheme = history and history.lastThemeByTrader and giver and giver.traderID
        and history.lastThemeByTrader[tostring(giver.traderID)]
        or nil

    for themeID, theme in pairs(THEME_REGISTRY) do
        local weight = 1.0
        weight = weight + (countTagMatches(archetype and archetype.expertTags or {}, theme.preferredTags) * 1.15)
        weight = weight + (countTagMatches(profile and profile.preferredTags or {}, theme.preferredTags) * 0.9)

        if family == "Courier" and (themeID == "food" or themeID == "medical") then
            weight = weight + 1.0
        elseif family == "KillZone" and (themeID == "combat" or themeID == "survival") then
            weight = weight + 1.0
        elseif family == "HuntDrop" and (themeID == "scavenge" or themeID == "engineering") then
            weight = weight + 1.0
        elseif family == "Escort" and (themeID == "survival" or themeID == "medical") then
            weight = weight + 1.0
        end

        if lastTheme and tostring(lastTheme) == tostring(themeID) then
            weight = weight * 0.45
        end

        weights[#weights + 1] = {
            id = themeID,
            weight = math.max(0.05, weight),
            theme = theme,
        }
    end

    return weights
end

local function pickWeightedEntry(entries)
    local total = 0
    for _, entry in ipairs(entries or {}) do
        total = total + math.max(0, tonumber(entry.weight) or 0)
    end
    if total <= 0 then
        return nil
    end

    local roll = ZombRand(0, math.max(1, math.floor(total * 1000))) / 1000
    local cursor = 0
    for _, entry in ipairs(entries) do
        cursor = cursor + math.max(0, tonumber(entry.weight) or 0)
        if roll <= cursor then
            return entry
        end
    end

    return entries[#entries]
end

local function getProfile(profileID)
    if Runtime.getProceduralRewardProfile then
        return Runtime.getProceduralRewardProfile(profileID)
    end
    return { preferredTags = {}, cashMin = 0, cashMax = 0, itemRollsMin = 1, itemRollsMax = 1 }
end

local function buildHistorySignature(family, themeID, rewardTags)
    local primaryTag = type(rewardTags) == "table" and rewardTags[2] or nil
    return table.concat({
        tostring(family or "Quest"),
        tostring(themeID or "mixed"),
        tostring(primaryTag or "cash"),
    }, "|")
end

local function resolveTheme(profile, family, archetype, history, giver, previewRewardTags)
    local weights = buildThemeWeights(profile, family, archetype, history, giver)
    local fallback = weights[1] and weights[1].id or "mixed"

    for _ = 1, 8 do
        local picked = pickWeightedEntry(weights)
        local themeID = picked and picked.id or fallback
        local signature = buildHistorySignature(family, themeID, previewRewardTags or { themeID })
        if not findRecentSignature(history, signature) then
            return themeID
        end
    end

    return fallback
end

local function buildIdentity(family, themeID, giver)
    local templates = IDENTITY_TEMPLATES[tostring(family or "")] or IDENTITY_TEMPLATES.Courier
    local theme = getTheme(themeID)
    local tokens = {
        theme = themeID,
        themeLabel = theme.label,
        themeAdjective = theme.adjective,
        themeNoun = theme.noun,
        giverName = giver.giverName,
        giverTitle = giver.giverTitle,
        giverFactionName = giver.giverFactionName,
        family = FAMILY_LABELS[tostring(family or "")] or tostring(family or "Quest"),
    }

    local name = trimText(formatTemplate(chooseFromList(templates.names) or "{themeLabel} Contract", tokens))
    local title = trimText(formatTemplate(chooseFromList(templates.titles) or "{giverTitle} Contract", tokens))

    if title == "" then
        title = name
    end

    return name, title
end

local function buildProceduralRewards(request, themeID)
    local giver = request.giver
    local archetype = getArchetype(giver and giver.archetypeID)
    local theme = deepCopy(getTheme(themeID))
    theme.id = tostring(themeID or "mixed")

    if Runtime.buildProceduralRewardData then
        return Runtime.buildProceduralRewardData({
            profileID = request.profileID,
            family = request.family,
            giver = giver,
            archetype = archetype,
            themeID = themeID,
            theme = theme,
            difficulty = request.difficulty,
            allowCash = request.allowCash,
            allowReputation = request.allowReputation,
        })
    end

    return {
        targetValue = 0,
        actualValue = 0,
        rewards = {},
        rewardTags = { tostring(themeID or "mixed") },
        signature = buildHistorySignature(request.family, themeID, { themeID }),
    }
end

local function applyGeneratedFields(spec, request, themeID, rewardData)
    local giver = request.giver
    local family = request.family
    local name, title = buildIdentity(family, themeID, giver)

    spec.name = name
    spec.title = title
    spec.giverName = giver.giverName
    spec.giverTitle = giver.giverTitle
    spec.giverFactionID = giver.giverFactionID
    spec.giverFactionName = giver.giverFactionName
    spec.themeID = tostring(themeID)
    local rewardValue = tonumber(rewardData.actualValue or rewardData.targetValue or rewardData.targetBudget) or 0
    spec.budgetValue = rewardValue
    spec.rewardValue = rewardValue
    spec.rewardTags = deepCopy(rewardData.rewardTags or {})
    spec.rewards = deepCopy(rewardData.rewards or {})
    spec.rewardPreview = rewardData.previewText or spec.rewardPreview
    spec.rewardContext = spec.rewardContext or {}
    spec.rewardContext.factionID = spec.rewardContext.factionID or giver.giverFactionID
    spec.rewardContext.factionName = spec.rewardContext.factionName or giver.giverFactionName
    spec.sourceTrader = type(spec.sourceTrader) == "table" and spec.sourceTrader or {}
    spec.sourceTrader.displayName = spec.sourceTrader.displayName or giver.giverName
    spec.sourceTrader.name = spec.sourceTrader.name or giver.giverName
    spec.sourceTrader.factionID = spec.sourceTrader.factionID or giver.giverFactionID
    spec.sourceTrader.factionName = spec.sourceTrader.factionName or giver.giverFactionName
    spec.sourceTrader.archetype = spec.sourceTrader.archetype or giver.archetypeID
    spec.proceduralOffer = true

    if family == "Courier" and spec.objectives and spec.objectives[1] then
        spec.objectives[1].label = FAMILY_OBJECTIVE_LABELS.Courier[themeID] or FAMILY_OBJECTIVE_LABELS.Courier.mixed
    elseif family == "KillZone" and spec.objectives and spec.objectives[1] then
        spec.objectives[1].label = FAMILY_OBJECTIVE_LABELS.KillZone[themeID] or FAMILY_OBJECTIVE_LABELS.KillZone.mixed
    elseif family == "HuntDrop" and spec.objectives then
        local labels = FAMILY_OBJECTIVE_LABELS.HuntDrop[themeID] or FAMILY_OBJECTIVE_LABELS.HuntDrop.mixed
        if spec.objectives[1] then
            spec.objectives[1].label = labels.kill
        end
        if spec.objectives[2] then
            spec.objectives[2].label = labels.drop
        end
        if spec.objectives[3] then
            spec.objectives[3].label = labels.returnDrop
        end
    elseif family == "Escort" and spec.objectives and spec.objectives[1] then
        spec.objectives[1].label = FAMILY_OBJECTIVE_LABELS.Escort[themeID] or FAMILY_OBJECTIVE_LABELS.Escort.mixed
    end
end

local function precomputeDifficulty(player, spec)
    local difficulty, factors = Runtime.resolveQuestDifficulty(player, spec, spec and spec.targetLocation or nil)
    spec.difficulty = difficulty
    spec.difficultyFactors = deepCopy(factors or {})
    spec.precomputedDifficulty = true
    spec.difficultyLabel = Runtime.getQuestDifficultyLabel(difficulty)
    return difficulty, factors
end

function Runtime.isProceduralGenerationEnabled(blueprint)
    local generation = type(blueprint and blueprint.generation) == "table" and blueprint.generation or nil
    return generation and generation.enabled == true or false
end

function Runtime.resolveProceduralOfferSpec(player, store, cacheKey, contextSignature, ttlHours, builder)
    if type(builder) ~= "function" then
        return nil
    end

    local cache = ensureProceduralState(store, true)
    local history = select(2, ensureProceduralState(store, true))
    local now = Runtime.getWorldAgeHours()
    local entry = cache and cache[tostring(cacheKey)] or nil
    local ttl = math.max(0.25, tonumber(ttlHours) or DEFAULT_TTL_HOURS)

    if entry
        and type(entry.spec) == "table"
        and tostring(entry.contextSignature or "") == tostring(contextSignature or "")
        and tonumber(entry.expiresAtWorldHours or 0) > now
    then
        return deepCopy(entry.spec)
    end

    local spec, themeID, signature = builder(history)
    if type(spec) ~= "table" then
        return nil
    end

    if cache then
        cache[tostring(cacheKey)] = {
            contextSignature = tostring(contextSignature or ""),
            expiresAtWorldHours = now + ttl,
            spec = deepCopy(spec),
        }
    end

    if history then
        if signature and signature ~= "" then
            pushRecentSignature(history, signature)
        end
        local traderID = spec.sourceTrader and (spec.sourceTrader.traderID or spec.sourceTrader.id) or nil
        if traderID and themeID then
            history.lastThemeByTrader[tostring(traderID)] = tostring(themeID)
        end
    end

    return deepCopy(spec)
end

function Runtime.buildProceduralBlueprintSpec(player, store, traderContext, blueprint, overrides, buildBaseSpec)
    if type(blueprint) ~= "table" or type(buildBaseSpec) ~= "function" then
        return nil
    end

    local generation = type(blueprint.generation) == "table" and blueprint.generation or {}
    local giver = resolveGiverContext(traderContext)
    local cacheKey = table.concat({
        "blueprint",
        tostring(giver.traderID or "trader"),
        tostring(blueprint.id or "blueprint"),
    }, ":")
    local contextSignature = buildContextSignature(giver, {
        blueprintId = blueprint.id,
        rewardTableVersion = Runtime.getProceduralRewardTableVersion and Runtime.getProceduralRewardTableVersion() or 0,
    })
    local profileID = generation.rewardProfile or ({
        Courier = "courier_default",
        KillZone = "killzone_default",
        HuntDrop = "huntdrop_default",
    })[tostring(blueprint.family or "")] or "courier_default"
    local ttlHours = generation.offerTtlHours or DEFAULT_TTL_HOURS

    return Runtime.resolveProceduralOfferSpec(player, store, cacheKey, contextSignature, ttlHours, function(history)
        local spec = buildBaseSpec()
        if type(spec) ~= "table" then
            return nil
        end

        precomputeDifficulty(player, spec)
        spec.sourceTrader = type(spec.sourceTrader) == "table" and spec.sourceTrader or {}
        spec.sourceTrader.traderID = spec.sourceTrader.traderID or giver.traderID

        local previewRewardData = buildProceduralRewards({
            profileID = profileID,
            family = blueprint.family,
            giver = giver,
            difficulty = spec.difficulty,
            allowCash = generation.allowProceduralCash ~= false,
            allowReputation = generation.allowProceduralReputation == true,
        }, "mixed")
        local themeID = resolveTheme(getProfile(profileID), blueprint.family, getArchetype(giver.archetypeID), history, giver, previewRewardData.rewardTags)
        local rewardData = buildProceduralRewards({
            profileID = profileID,
            family = blueprint.family,
            giver = giver,
            difficulty = spec.difficulty,
            allowCash = generation.allowProceduralCash ~= false,
            allowReputation = generation.allowProceduralReputation == true,
        }, themeID)

        applyGeneratedFields(spec, {
            family = blueprint.family,
            giver = giver,
        }, themeID, rewardData)

        return spec, themeID, rewardData.signature
    end)
end

function Runtime.buildProceduralEscortSpec(player, store, incident, buildBaseSpec)
    if type(incident) ~= "table" or type(buildBaseSpec) ~= "function" then
        return nil
    end

    local routeDistance = math.max(0, tonumber(incident.routeDistance) or 0)
    local giver = resolveGiverContext({
        traderID = incident.traderId,
        displayName = incident.traderName,
        factionID = incident.factionId,
        factionName = incident.factionName,
        archetype = incident.archetype or "General",
        currentState = incident.status,
    }, {
        giverTitle = incident.archetypeName or getArchetypeLabel(incident.archetype or "General"),
    })

    local cacheKey = table.concat({
        "hook",
        "escort",
        tostring(incident.incidentId or incident.questId or giver.traderID or "escort"),
    }, ":")
    local contextSignature = buildContextSignature(giver, {
        hookId = "TraderNeeds.HelpEscort",
        routeBucket = math.floor(routeDistance / 50),
        objectiveSeed = incident.questId or incident.incidentId,
        rewardTableVersion = Runtime.getProceduralRewardTableVersion and Runtime.getProceduralRewardTableVersion() or 0,
    })

    return Runtime.resolveProceduralOfferSpec(player, store, cacheKey, contextSignature, DEFAULT_TTL_HOURS, function(history)
        local spec = buildBaseSpec()
        if type(spec) ~= "table" then
            return nil
        end

        local rescueDistance = routeDistance / 200
        spec.baseDifficulty = Runtime.normalizeDifficulty(spec.baseDifficulty or 1.0 + rescueDistance)
        precomputeDifficulty(player, spec)
        spec.sourceTrader = type(spec.sourceTrader) == "table" and spec.sourceTrader or {}
        spec.sourceTrader.traderID = spec.sourceTrader.traderID or giver.traderID

        local previewRewardData = buildProceduralRewards({
            profileID = "escort_default",
            family = "Escort",
            giver = giver,
            difficulty = spec.difficulty,
            allowCash = true,
            allowReputation = giver.giverFactionID ~= nil,
        }, "mixed")
        local themeID = resolveTheme(getProfile("escort_default"), "Escort", getArchetype(giver.archetypeID), history, giver, previewRewardData.rewardTags)
        local rewardData = buildProceduralRewards({
            profileID = "escort_default",
            family = "Escort",
            giver = giver,
            difficulty = spec.difficulty,
            allowCash = true,
            allowReputation = giver.giverFactionID ~= nil,
        }, themeID)

        applyGeneratedFields(spec, {
            family = "Escort",
            giver = giver,
        }, themeID, rewardData)

        return spec, themeID, rewardData.signature
    end)
end

function Runtime.buildProceduralDialogueTokens(questLike, fallbackTrader)
    local source = type(questLike) == "table" and questLike or {}
    local trader = type(fallbackTrader) == "table" and fallbackTrader or {}
    local giver = resolveGiverContext(trader, {
        giverName = source.giverName,
        giverTitle = source.giverTitle,
        factionID = source.giverFactionID,
        factionName = source.giverFactionName,
    })
    local theme = getTheme(source.themeID)

    return {
        giver = giver,
        theme = theme,
    }
end

function Quests.DebugSampleProceduralOffers(player, archetypeID, iterations)
    local store = Runtime.getStore(player, true)
    local count = math.max(1, math.floor(tonumber(iterations) or 10))
    local traderContext = {
        traderID = "debug_" .. tostring(archetypeID or "General"),
        displayName = tostring(archetypeID or "General") .. " Debug Trader",
        currentState = "Resting",
        archetype = tostring(archetypeID or "General"),
    }
    local blueprints = {
        DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_courier_run") or nil,
        DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_kill_zone") or nil,
        DO.GetQuestBlueprint and DO.GetQuestBlueprint("resting_hunt_drop") or nil,
    }

    for _, blueprint in ipairs(blueprints) do
        if blueprint then
            for _ = 1, count do
                local spec = Runtime.buildQuestSpecFromBlueprint and Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint) or nil
                if spec then
                    Runtime.questLog(
                        "Quest",
                        "Procedural",
                        string.format(
                            "%s [%s] theme=%s value=%s rewards=%s tags=%s",
                            tostring(spec.title or spec.name or blueprint.id),
                            tostring(archetypeID or "General"),
                            tostring(spec.themeID or "mixed"),
                            tostring(spec.rewardValue or spec.budgetValue or 0),
                            tostring(spec.rewardPreview or "none"),
                            table.concat(spec.rewardTags or {}, ",")
                        )
                    )
                end
            end
        end
    end
end
