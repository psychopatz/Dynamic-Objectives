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

