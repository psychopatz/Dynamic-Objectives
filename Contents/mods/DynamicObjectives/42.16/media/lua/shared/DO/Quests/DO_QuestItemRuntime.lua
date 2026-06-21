DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests

Quests.QuestItems = Quests.QuestItems or {
    { name = "Small Package", id = "DTQuest.PackageSmallQuest" },
    { name = "Medium Package", id = "DTQuest.PackageMediumQuest" },
    { name = "Large Package", id = "DTQuest.PackageLargeQuest" },
    { name = "Fragile Cargo", id = "DTQuest.PackageFragileQuest" },
    { name = "Medical Supplies", id = "DTQuest.PackageMedicalQuest" },
    { name = "Military Crate", id = "DTQuest.PackageMilitaryQuest" },
    { name = "Gift Item", id = "DTQuest.PackageGiftQuest" },
}

local weightUpdateTick = 0
local trackedInventoryItems = {}

local function itemLog(category, topic, message)
    DO.Log(category, topic, message)
end

function Quests.RequestSpawnQuestItem(player, itemID, difficulty, questID)
    if not player or not itemID then
        return nil
    end

    questID = questID or ("DOQ_" .. tostring(ZombRand(100000, 999999)))
    difficulty = difficulty or 1.0

    if isClient() then
        sendClientCommand(player, "DynamicObjectives", "SpawnQuestItem", {
            itemID = itemID,
            difficulty = difficulty,
            questID = questID,
        })
        return questID
    end

    Quests.CreateQuestItem(player, itemID, questID, difficulty)
    return questID
end

function Quests.CreateQuestItem(player, itemFullType, questID, difficulty)
    if not player or not itemFullType then
        return nil
    end

    difficulty = difficulty or 1.0

    local inventory = player:getInventory()
    if not inventory then
        return nil
    end

    local item = inventory:AddItem(itemFullType)
    if not item then
        itemLog("Error", "QuestItems", "Failed to spawn quest item: " .. tostring(itemFullType))
        return nil
    end

    local baseName = item:getName()
    item:setName(baseName .. " (" .. tostring(questID) .. ")")

    local tooltip = "Dynamic Objective Item: " .. tostring(questID) .. "\n"
    tooltip = tooltip .. "Objective details are tracked in the quest runtime.\n"
    tooltip = tooltip .. "Equip in hands to reduce weight by 70%."
    item:setTooltip(tooltip)

    local targetWeight = item:getActualWeight() * difficulty
    local modData = item:getModData()
    modData.QuestID = questID
    modData.Timestamp = getGameTime():getWorldAgeHours()
    modData.IsQuestItem = true
    modData.BaseWeight = targetWeight

    local initialWeight = math.min(50.0, targetWeight * 0.3)
    item:setActualWeight(initialWeight)
    item:setCustomWeight(true)

    if (isServer() or isClient()) and sendAddItemToContainer then
        sendAddItemToContainer(inventory, item)
    end

    DO.LogDebug("QuestItems", "Spawned quest item " .. tostring(itemFullType) .. " for " .. tostring(questID))

    return item
end

function Quests.FindItemsInContainer(container, results, visited, predicate)
    if not container or visited[container] then
        return
    end

    visited[container] = true
    local items = container:getItems()
    if not items then
        return
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if not predicate or predicate(item) then
                results[#results + 1] = item
            end

            if item.IsInventoryContainer and item:IsInventoryContainer() then
                local nested = item:getInventory()
                if nested then
                    Quests.FindItemsInContainer(nested, results, visited, predicate)
                end
            end
        end
    end
end

function Quests.FindItemsOnPlayer(player, predicate)
    local results = {}
    if not player then
        return results
    end

    local inventory = player:getInventory()
    if not inventory then
        return results
    end

    Quests.FindItemsInContainer(inventory, results, {}, predicate)
    return results
end

function Quests.HasActiveQuestItem(player)
    local items = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.IsQuestItem == true
    end)

    return #items > 0
end

function Quests.ValidateDelivery(item, requiredQuestID)
    if not item then
        return false
    end

    local modData = item:getModData()
    if not modData then
        return false
    end

    local questID = tostring(requiredQuestID or "")
    return (modData.IsQuestItem == true and tostring(modData.QuestID or "") == questID)
        or (modData.DOQuestDrop == true and tostring(modData.DOQuestID or "") == questID)
end

function Quests.RemoveInventoryItem(item)
    if not item then
        return false
    end

    local container = item:getContainer()
    if not container or not container.DoRemoveItem then
        return false
    end

    container:DoRemoveItem(item)
    return true
end

function Quests.UpdateItemWeight(item, isOnPlayer)
    if not item then
        return
    end

    local modData = item:getModData()
    if not modData or not modData.IsQuestItem or not modData.BaseWeight then
        return
    end

    local isEquipped = false
    if item.isEquipped then
        isEquipped = item:isEquipped()
    end

    local multiplier = 1.0
    if isEquipped or not isOnPlayer then
        multiplier = 0.3
    end

    local targetWeight = modData.BaseWeight * multiplier
    if multiplier < 1.0 and targetWeight > 50.0 then
        targetWeight = 50.0
    end

    if math.abs(item:getActualWeight() - targetWeight) > 0.01 then
        item:setActualWeight(targetWeight)
        item:setCustomWeight(true)
    end
end

function Quests.OnQuestItemPlayerUpdate(player)
    weightUpdateTick = weightUpdateTick + 1
    if weightUpdateTick < 30 then
        return
    end
    weightUpdateTick = 0

    local currentItems = {}
    local found = Quests.FindItemsOnPlayer(player, function(item)
        local modData = item:getModData()
        return modData and modData.IsQuestItem == true
    end)

    for _, item in ipairs(found) do
        currentItems[item] = true
        Quests.UpdateItemWeight(item, true)
        trackedInventoryItems[item] = true
    end

    for item, _ in pairs(trackedInventoryItems) do
        if not currentItems[item] then
            Quests.UpdateItemWeight(item, false)
            trackedInventoryItems[item] = nil
        end
    end
end

function Quests.OnQuestItemEquip(player, item)
    if item and item:getModData() and item:getModData().IsQuestItem then
        Quests.UpdateItemWeight(item, true)
    end
end

if not isServer() then
    Events.OnPlayerUpdate.Add(Quests.OnQuestItemPlayerUpdate)
    Events.OnEquipPrimary.Add(Quests.OnQuestItemEquip)
    Events.OnEquipSecondary.Add(Quests.OnQuestItemEquip)
end
