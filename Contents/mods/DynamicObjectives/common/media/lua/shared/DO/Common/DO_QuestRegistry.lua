DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.QuestBlueprints = DO.QuestBlueprints or {
    Registry = {},
    Order = {},
}
DO.QuestLootPools = DO.QuestLootPools or {
    Registry = {},
    Order = {},
}
DO.QuestDialogueTrees = DO.QuestDialogueTrees or {
    Registry = {},
    Order = {},
}
DO.QuestChains = DO.QuestChains or {
    Registry = {},
    Order = {},
}
DO.QuestContentModules = DO.QuestContentModules or {
    Registry = {},
    Order = {},
    Loaded = {},
}

local function ensureBucket(bucket)
    bucket.Registry = bucket.Registry or {}
    bucket.Order = bucket.Order or {}
    return bucket
end

local function containsValue(list, value)
    for _, existing in ipairs(list or {}) do
        if existing == value then
            return true
        end
    end
    return false
end

local function addOrderValue(bucket, value)
    if not containsValue(bucket.Order, value) then
        bucket.Order[#bucket.Order + 1] = value
    end
end

local function removeOrderValue(bucket, value)
    for index = #bucket.Order, 1, -1 do
        if bucket.Order[index] == value then
            table.remove(bucket.Order, index)
        end
    end
end

local function normalizeRegistryEntry(id, data)
    local entry = DO.DeepCopy(type(data) == "table" and data or {})
    entry.id = tostring(entry.id or id)
    return entry
end

local function normalizeQuestChain(id, data)
    local entry = normalizeRegistryEntry(id, data)
    entry.label = tostring(entry.label or entry.name or entry.id)
    entry.defaultAdvanceMode = entry.defaultAdvanceMode and tostring(entry.defaultAdvanceMode) or nil
    entry.stages = type(entry.stages) == "table" and DO.DeepCopy(entry.stages) or {}
    entry.StageIndexByID = {}

    for index, stage in ipairs(entry.stages) do
        local normalizedStage = type(stage) == "table" and stage or {}
        normalizedStage.id = tostring(normalizedStage.id or ("stage_" .. tostring(index)))
        normalizedStage.blueprintId = tostring(normalizedStage.blueprintId or normalizedStage.blueprint or "")
        normalizedStage.label = normalizedStage.label and tostring(normalizedStage.label) or nil
        normalizedStage.name = normalizedStage.name and tostring(normalizedStage.name) or nil
        normalizedStage.dialogueTree = normalizedStage.dialogueTree and tostring(normalizedStage.dialogueTree) or nil
        normalizedStage.offerWeight = tonumber(normalizedStage.offerWeight or normalizedStage.weight) or nil
        normalizedStage.advanceMode = normalizedStage.advanceMode and tostring(normalizedStage.advanceMode) or nil
        normalizedStage.nextStageId = normalizedStage.nextStageId and tostring(normalizedStage.nextStageId) or nil
        normalizedStage.autoStart = normalizedStage.autoStart == true
        normalizedStage.stageIndex = index
        entry.stages[index] = normalizedStage
        entry.StageIndexByID[normalizedStage.id] = index
    end

    return entry
end

local function normalizeQuestContentModule(id, data)
    local entry = normalizeRegistryEntry(id, data)
    entry.label = tostring(entry.label or entry.name or entry.id)
    entry.enabled = entry.enabled ~= false
    entry.requirePaths = type(entry.requirePaths) == "table" and DO.DeepCopy(entry.requirePaths) or {}

    local normalizedPaths = {}
    for _, path in ipairs(entry.requirePaths) do
        local candidate = type(path) == "string" and tostring(path) or ""
        if candidate ~= "" and not containsValue(normalizedPaths, candidate) then
            normalizedPaths[#normalizedPaths + 1] = candidate
        end
    end
    entry.requirePaths = normalizedPaths

    return entry
end

local function registerEntry(bucket, id, data)
    if not id or type(data) ~= "table" then
        return nil
    end

    bucket = ensureBucket(bucket)
    local key = tostring(id)
    bucket.Registry[key] = normalizeRegistryEntry(key, data)
    addOrderValue(bucket, key)
    return bucket.Registry[key]
end

local function removeEntry(bucket, id)
    if not id then
        return false
    end

    bucket = ensureBucket(bucket)
    local key = tostring(id)
    if bucket.Registry[key] == nil then
        return false
    end

    bucket.Registry[key] = nil
    removeOrderValue(bucket, key)
    return true
end

local function getEntry(bucket, id)
    bucket = ensureBucket(bucket)
    return id and bucket.Registry[tostring(id)] or nil
end

local function listEntries(bucket)
    bucket = ensureBucket(bucket)
    local results = {}
    for _, id in ipairs(bucket.Order) do
        local entry = bucket.Registry[id]
        if entry then
            results[#results + 1] = entry
        end
    end
    return results
end

local function normalizeWeight(value, fallback)
    local weight = tonumber(value)
    if weight == nil or weight <= 0 then
        return tonumber(fallback) or 1
    end
    return weight
end

function DO.RegisterQuestBlueprint(id, data)
    return registerEntry(DO.QuestBlueprints, id, data)
end

function DO.RemoveQuestBlueprint(id)
    return removeEntry(DO.QuestBlueprints, id)
end

function DO.GetQuestBlueprint(id)
    return getEntry(DO.QuestBlueprints, id)
end

function DO.GetQuestBlueprintList()
    return listEntries(DO.QuestBlueprints)
end

function DO.RegisterQuestLootPool(id, data)
    return registerEntry(DO.QuestLootPools, id, data)
end

function DO.RemoveQuestLootPool(id)
    return removeEntry(DO.QuestLootPools, id)
end

function DO.GetQuestLootPool(id)
    return getEntry(DO.QuestLootPools, id)
end

function DO.GetQuestLootPoolList()
    return listEntries(DO.QuestLootPools)
end

function DO.RegisterQuestDialogueTree(id, data)
    return registerEntry(DO.QuestDialogueTrees, id, data)
end

function DO.RemoveQuestDialogueTree(id)
    return removeEntry(DO.QuestDialogueTrees, id)
end

function DO.GetQuestDialogueTree(id)
    return getEntry(DO.QuestDialogueTrees, id)
end

function DO.GetQuestDialogueTreeList()
    return listEntries(DO.QuestDialogueTrees)
end

function DO.RegisterQuestChain(id, data)
    if not id or type(data) ~= "table" then
        return nil
    end

    local key = tostring(id)
    DO.QuestChains = ensureBucket(DO.QuestChains)
    DO.QuestChains.Registry[key] = normalizeQuestChain(key, data)
    addOrderValue(DO.QuestChains, key)
    return DO.QuestChains.Registry[key]
end

function DO.RemoveQuestChain(id)
    return removeEntry(DO.QuestChains, id)
end

function DO.GetQuestChain(id)
    return getEntry(DO.QuestChains, id)
end

function DO.GetQuestChainList()
    return listEntries(DO.QuestChains)
end

function DO.RegisterQuestContentModule(id, data)
    if not id then
        return nil
    end

    local key = tostring(id)
    DO.QuestContentModules = ensureBucket(DO.QuestContentModules)
    DO.QuestContentModules.Loaded = type(DO.QuestContentModules.Loaded) == "table" and DO.QuestContentModules.Loaded or {}
    DO.QuestContentModules.Registry[key] = normalizeQuestContentModule(key, type(data) == "table" and data or {})
    addOrderValue(DO.QuestContentModules, key)
    return DO.QuestContentModules.Registry[key]
end

function DO.RemoveQuestContentModule(id)
    if DO.QuestContentModules and type(DO.QuestContentModules.Loaded) == "table" and id then
        DO.QuestContentModules.Loaded[tostring(id)] = nil
    end
    return removeEntry(DO.QuestContentModules, id)
end

function DO.GetQuestContentModule(id)
    return getEntry(DO.QuestContentModules, id)
end

function DO.GetQuestContentModuleList()
    return listEntries(DO.QuestContentModules)
end

function DO.LoadQuestContentModules()
    local bucket = ensureBucket(DO.QuestContentModules)
    bucket.Loaded = type(bucket.Loaded) == "table" and bucket.Loaded or {}

    local loadedPaths = 0
    local errors = 0

    for _, module in ipairs(DO.GetQuestContentModuleList()) do
        local moduleID = tostring(module.id or "")
        if module.enabled ~= false and moduleID ~= "" and bucket.Loaded[moduleID] ~= true then
            local moduleFailed = false
            for _, requirePath in ipairs(module.requirePaths or {}) do
                local ok, err = pcall(require, requirePath)
                if not ok then
                    moduleFailed = true
                    errors = errors + 1
                    if DO.Log then
                        DO.Log("Quest", "Registry", "Failed to load quest content module " .. moduleID .. " path " .. tostring(requirePath) .. ": " .. tostring(err))
                    end
                else
                    loadedPaths = loadedPaths + 1
                end
            end

            if not moduleFailed then
                bucket.Loaded[moduleID] = true
            end
        end
    end

    return errors == 0, loadedPaths, errors
end

function DO.GetQuestPoolEntries(poolOrId)
    local pool = type(poolOrId) == "table" and poolOrId or DO.GetQuestLootPool(poolOrId)
    if not pool then
        return {}
    end

    local entries = pool.entries or pool.items or pool.rewards or {}
    return type(entries) == "table" and entries or {}
end

function DO.ResolveWeightedEntry(poolOrId)
    local entries = DO.GetQuestPoolEntries(poolOrId)
    if #entries == 0 then
        return nil, nil
    end

    local totalWeight = 0
    for _, entry in ipairs(entries) do
        totalWeight = totalWeight + normalizeWeight(entry and entry.weight, 1)
    end

    if totalWeight <= 0 then
        return DO.DeepCopy(entries[1]), 1
    end

    local roll = ZombRandFloat(0, totalWeight)
    local cursor = 0
    for index, entry in ipairs(entries) do
        cursor = cursor + normalizeWeight(entry and entry.weight, 1)
        if roll <= cursor then
            return DO.DeepCopy(entry), index
        end
    end

    return DO.DeepCopy(entries[#entries]), #entries
end
