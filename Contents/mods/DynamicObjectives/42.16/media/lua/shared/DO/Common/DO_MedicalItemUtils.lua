DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.MedicalItemUtils = DynamicObjectives.MedicalItemUtils or {}

local Utils = DynamicObjectives.MedicalItemUtils

local BANDAGE_FULL_TYPES = {
    ["Base.Bandage"] = true,
    ["Base.BandageBox"] = true,
    ["Base.AlcoholBandage"] = true,
    ["Base.RippedSheets"] = true,
    ["Base.AlcoholRippedSheets"] = true,
    ["Base.Bandaid"] = true,
    ["Base.AdhesiveBandage"] = true,
    ["Base.AdhesiveBandageBox"] = true,
}

local function normalizeText(value)
    local text = value and tostring(value) or ""
    return text ~= "" and text or nil
end

local function isBandageItem(item)
    if not item or not item.getFullType then
        return false
    end
    return BANDAGE_FULL_TYPES[tostring(item:getFullType() or "")] == true
end

local function walkContainer(container, results, visited)
    if not container or visited[container] then
        return
    end
    visited[container] = true

    local items = container.getItems and container:getItems() or nil
    if not items then
        return
    end

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if isBandageItem(item) then
            results[#results + 1] = item
        end

        local nested = item and item.getInventory and item:getInventory() or nil
        if nested then
            walkContainer(nested, results, visited)
        end
    end
end

function Utils.IsBandageFullType(fullType)
    fullType = normalizeText(fullType)
    return fullType ~= nil and BANDAGE_FULL_TYPES[fullType] == true
end

function Utils.IsBandageItem(item)
    return isBandageItem(item)
end

function Utils.FindBandageItems(player)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then
        return {}
    end

    local results = {}
    walkContainer(inventory, results, {})
    return results
end

function Utils.FindFirstBandageItem(player)
    local items = Utils.FindBandageItems(player)
    return items[1] or nil
end

function Utils.CountBandageItems(player)
    return #(Utils.FindBandageItems(player))
end

function Utils.GetBandageDisplayName(item)
    if not item then
        return "bandage"
    end

    if item.getDisplayName then
        local name = normalizeText(item:getDisplayName())
        if name then
            return name
        end
    end

    return normalizeText(item.getName and item:getName() or nil) or "bandage"
end

function Utils.ConsumeFirstBandageItem(player)
    local item = Utils.FindFirstBandageItem(player)
    if not item then
        return nil
    end

    local container = item.getContainer and item:getContainer() or nil
    if not container or not container.DoRemoveItem then
        return nil
    end

    local result = {
        fullType = tostring(item:getFullType() or ""),
        displayName = Utils.GetBandageDisplayName(item),
    }

    container:DoRemoveItem(item)
    return result
end
