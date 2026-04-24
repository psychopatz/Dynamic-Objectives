DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.QuestBlueprintValidator = DO.QuestBlueprintValidator or {}

local Validator = DO.QuestBlueprintValidator

local VALID_FAMILIES = {
    Courier = true,
    KillZone = true,
    HuntDrop = true,
}
local VALID_ADVANCE_MODES = {
    offer = true,
    auto = true,
}

local function addIssue(list, message)
    list[#list + 1] = tostring(message)
end

local function validateItemType(itemType)
    if not itemType or tostring(itemType) == "" then
        return false
    end

    local manager = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
    if manager and manager.getItem then
        return manager:getItem(tostring(itemType)) ~= nil
    end

    return true
end

local function validateDialogueTree(id, tree, errors)
    if type(tree) ~= "table" then
        addIssue(errors, "Dialogue tree " .. tostring(id) .. " is missing.")
        return
    end

    local nodes = type(tree.nodes) == "table" and tree.nodes or nil
    if not nodes then
        addIssue(errors, "Dialogue tree " .. tostring(id) .. " has no nodes table.")
        return
    end

    if not nodes.offer or tostring(nodes.offer.text or "") == "" then
        addIssue(errors, "Dialogue tree " .. tostring(id) .. " is missing offer text.")
    end
end

local function validateRewardEntry(entry, errors, prefix)
    local kind = tostring(entry.kind or entry.type or ""):lower()
    if kind == "item" then
        local itemType = entry.itemType or entry.item or entry.fullType
        if not validateItemType(itemType) then
            addIssue(errors, prefix .. " reward item is invalid: " .. tostring(itemType))
        end
    elseif kind == "money" then
        if tonumber(entry.amount or entry.count) == nil then
            addIssue(errors, prefix .. " money reward amount is invalid.")
        end
    elseif kind == "reputation" then
        if tonumber(entry.amount) == nil then
            addIssue(errors, prefix .. " reputation amount is invalid.")
        end
    elseif kind == "recruit" then
        if tonumber(entry.count or 1) == nil then
            addIssue(errors, prefix .. " recruit count is invalid.")
        end
    else
        addIssue(errors, prefix .. " reward kind is unsupported: " .. tostring(kind))
    end
end

local function validateLootPool(id, pool, errors)
    if type(pool) ~= "table" then
        addIssue(errors, "Loot pool " .. tostring(id) .. " is missing.")
        return
    end

    local entries = type(pool.entries) == "table" and pool.entries or {}
    if #entries == 0 then
        addIssue(errors, "Loot pool " .. tostring(id) .. " has no entries.")
        return
    end

    for index, entry in ipairs(entries) do
        if tonumber(entry.weight or 1) == nil then
            addIssue(errors, "Loot pool " .. tostring(id) .. " entry " .. tostring(index) .. " has invalid weight.")
        end

        local itemType = entry.itemType or entry.item
        if itemType and not validateItemType(itemType) then
            addIssue(errors, "Loot pool " .. tostring(id) .. " entry " .. tostring(index) .. " item is invalid: " .. tostring(itemType))
        end

        if type(entry.rewards) == "table" then
            if #entry.rewards == 0 then
                addIssue(errors, "Loot pool " .. tostring(id) .. " entry " .. tostring(index) .. " reward bundle is empty.")
            else
                for rewardIndex, reward in ipairs(entry.rewards) do
                    validateRewardEntry(reward, errors, "Loot pool " .. tostring(id) .. " entry " .. tostring(index) .. " reward " .. tostring(rewardIndex))
                end
            end
        end
    end
end

local function resolvePackageBlueprint(package, blueprintID)
    local localBlueprint = type(package and package.blueprint) == "table" and package.blueprint or nil
    if localBlueprint and tostring(localBlueprint.id or package.id or "") == tostring(blueprintID or "") then
        return localBlueprint
    end

    return DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
end

function Validator.ValidateChain(id, chain, package)
    local errors = {}
    local warnings = {}

    if type(chain) ~= "table" then
        addIssue(errors, "Chain " .. tostring(id) .. " is missing.")
        return false, errors, warnings
    end

    local stages = type(chain.stages) == "table" and chain.stages or {}
    if #stages == 0 then
        addIssue(errors, "Chain " .. tostring(id) .. " has no stages.")
        return false, errors, warnings
    end

    local defaultAdvanceMode = chain.defaultAdvanceMode and tostring(chain.defaultAdvanceMode) or nil
    if defaultAdvanceMode and VALID_ADVANCE_MODES[defaultAdvanceMode] ~= true then
        addIssue(errors, "Chain " .. tostring(id) .. " has invalid defaultAdvanceMode: " .. tostring(defaultAdvanceMode))
    end

    local stageById = {}
    local incomingCounts = {}
    for index, stage in ipairs(stages) do
        local stageID = tostring(stage and stage.id or "")
        if stageID == "" then
            addIssue(errors, "Chain " .. tostring(id) .. " stage " .. tostring(index) .. " is missing id.")
        elseif stageById[stageID] then
            addIssue(errors, "Chain " .. tostring(id) .. " has duplicate stage id: " .. tostring(stageID))
        else
            stageById[stageID] = stage
        end

        local blueprintID = tostring(stage and (stage.blueprintId or stage.blueprint) or "")
        if blueprintID == "" then
            addIssue(errors, "Chain " .. tostring(id) .. " stage " .. tostring(stageID ~= "" and stageID or index) .. " is missing blueprintId.")
        elseif not resolvePackageBlueprint(package, blueprintID) then
            addIssue(errors, "Chain " .. tostring(id) .. " stage " .. tostring(stageID ~= "" and stageID or index) .. " references missing blueprint: " .. tostring(blueprintID))
        end

        local advanceMode = stage and stage.advanceMode and tostring(stage.advanceMode) or nil
        if advanceMode and VALID_ADVANCE_MODES[advanceMode] ~= true then
            addIssue(errors, "Chain " .. tostring(id) .. " stage " .. tostring(stageID ~= "" and stageID or index) .. " has invalid advanceMode: " .. tostring(advanceMode))
        end

        local nextStageId = stage and stage.nextStageId and tostring(stage.nextStageId) or nil
        if nextStageId and nextStageId ~= "" then
            incomingCounts[nextStageId] = (incomingCounts[nextStageId] or 0) + 1
        end
    end

    for index, stage in ipairs(stages) do
        local stageID = tostring(stage.id or ("stage_" .. tostring(index)))
        local nextStageId = stage.nextStageId and tostring(stage.nextStageId) or nil
        if nextStageId and nextStageId ~= "" and not stageById[nextStageId] then
            addIssue(errors, "Chain " .. tostring(id) .. " stage " .. tostring(stageID) .. " references missing nextStageId: " .. tostring(nextStageId))
        end
    end

    for stageID, count in pairs(incomingCounts) do
        if count > 1 then
            addIssue(errors, "Chain " .. tostring(id) .. " is non-linear: stage " .. tostring(stageID) .. " has multiple incoming links.")
        end
    end

    if #errors > 0 then
        return false, errors, warnings
    end

    local rootCount = 0
    local rootID = nil
    for _, stage in ipairs(stages) do
        local stageID = tostring(stage.id)
        if (incomingCounts[stageID] or 0) == 0 then
            rootCount = rootCount + 1
            rootID = rootID or stageID
        end
    end

    if rootCount ~= 1 then
        addIssue(errors, "Chain " .. tostring(id) .. " must have exactly one root stage.")
        return false, errors, warnings
    end

    local visited = {}
    local currentID = rootID
    local visitCount = 0
    while currentID do
        if visited[currentID] then
            addIssue(errors, "Chain " .. tostring(id) .. " contains a cycle at stage " .. tostring(currentID))
            break
        end

        visited[currentID] = true
        visitCount = visitCount + 1
        local stage = stageById[currentID]
        currentID = stage and stage.nextStageId and tostring(stage.nextStageId) or nil
    end

    if visitCount ~= #stages then
        addIssue(errors, "Chain " .. tostring(id) .. " is non-linear or disconnected.")
    end

    return #errors == 0, errors, warnings
end

function Validator.ValidateBlueprint(id, blueprint)
    local errors = {}
    local warnings = {}

    if type(blueprint) ~= "table" then
        addIssue(errors, "Blueprint " .. tostring(id) .. " is missing.")
        return false, errors, warnings
    end

    local family = tostring(blueprint.family or "")
    if VALID_FAMILIES[family] ~= true then
        addIssue(errors, "Blueprint " .. tostring(id) .. " has invalid family: " .. tostring(family))
    end

    if tonumber(blueprint.weight or 1) == nil then
        addIssue(errors, "Blueprint " .. tostring(id) .. " has invalid weight.")
    end

    local target = type(blueprint.target) == "table" and blueprint.target or nil
    if not target then
        addIssue(errors, "Blueprint " .. tostring(id) .. " is missing target settings.")
    else
        if tonumber(target.radius or 0) == nil then
            addIssue(errors, "Blueprint " .. tostring(id) .. " target radius is invalid.")
        end
    end

    if tostring(blueprint.dialogueTree or "") == "" then
        addIssue(errors, "Blueprint " .. tostring(id) .. " is missing dialogueTree.")
    end

    if family == "Courier" then
        if tostring(blueprint.grantItemPool or "") == "" then
            addIssue(errors, "Courier blueprint " .. tostring(id) .. " is missing grantItemPool.")
        end
    elseif family == "KillZone" or family == "HuntDrop" then
        local encounter = type(blueprint.encounter) == "table" and blueprint.encounter or nil
        if not encounter then
            addIssue(errors, family .. " blueprint " .. tostring(id) .. " is missing encounter settings.")
        else
            if tonumber(encounter.baseCount or encounter.count) == nil then
                addIssue(errors, family .. " blueprint " .. tostring(id) .. " encounter count is invalid.")
            end
        end
    end

    if family == "HuntDrop" and tostring(blueprint.dropItemPool or "") == "" then
        addIssue(errors, "HuntDrop blueprint " .. tostring(id) .. " is missing dropItemPool.")
    end

    local generation = type(blueprint.generation) == "table" and blueprint.generation or nil
    if generation then
        if generation.enabled ~= nil and generation.enabled ~= true and generation.enabled ~= false then
            addIssue(errors, "Blueprint " .. tostring(id) .. " generation.enabled must be a boolean.")
        end
        if generation.rewardProfile ~= nil and tostring(generation.rewardProfile) == "" then
            addIssue(errors, "Blueprint " .. tostring(id) .. " generation.rewardProfile is invalid.")
        end
        if generation.offerTtlHours ~= nil and tonumber(generation.offerTtlHours) == nil then
            addIssue(errors, "Blueprint " .. tostring(id) .. " generation.offerTtlHours is invalid.")
        end
    end

    return #errors == 0, errors, warnings
end

function Validator.ValidatePackage(package)
    local errors = {}
    local warnings = {}

    if type(package) ~= "table" then
        addIssue(errors, "Preset package is not a table.")
        return false, errors, warnings
    end

    local blueprint = type(package.blueprint) == "table" and package.blueprint or nil
    if not blueprint then
        addIssue(errors, "Preset package is missing a blueprint table.")
        return false, errors, warnings
    end

    local blueprintId = tostring(blueprint.id or package.id or "")
    if blueprintId == "" then
        addIssue(errors, "Preset package blueprint id is empty.")
        return false, errors, warnings
    end

    local ok, blueprintErrors, blueprintWarnings = Validator.ValidateBlueprint(blueprintId, blueprint)
    if not ok then
        for _, message in ipairs(blueprintErrors) do
            addIssue(errors, message)
        end
    end
    for _, message in ipairs(blueprintWarnings) do
        warnings[#warnings + 1] = message
    end

    local lootPools = type(package.lootPools) == "table" and package.lootPools or {}
    for poolId, pool in pairs(lootPools) do
        validateLootPool(poolId, pool, errors)
    end

    local dialogueTrees = type(package.dialogueTrees) == "table" and package.dialogueTrees or {}
    for treeId, tree in pairs(dialogueTrees) do
        validateDialogueTree(treeId, tree, errors)
    end

    local chains = type(package.chains) == "table" and package.chains or {}
    for chainId, chain in pairs(chains) do
        local chainOk, chainErrors, chainWarnings = Validator.ValidateChain(chainId, chain, package)
        if not chainOk then
            for _, message in ipairs(chainErrors) do
                addIssue(errors, message)
            end
        end
        for _, message in ipairs(chainWarnings) do
            warnings[#warnings + 1] = message
        end
    end

    if blueprint.grantItemPool and not lootPools[blueprint.grantItemPool] and not DO.GetQuestLootPool(blueprint.grantItemPool) then
        addIssue(errors, "Blueprint references missing grantItemPool: " .. tostring(blueprint.grantItemPool))
    end
    if blueprint.dropItemPool and not lootPools[blueprint.dropItemPool] and not DO.GetQuestLootPool(blueprint.dropItemPool) then
        addIssue(errors, "Blueprint references missing dropItemPool: " .. tostring(blueprint.dropItemPool))
    end

    local rewardPools = type(blueprint.rewardPools) == "table" and blueprint.rewardPools or {}
    if #rewardPools == 0 then
        addIssue(errors, "Blueprint " .. tostring(blueprintId) .. " has no rewardPools.")
    else
        for _, poolId in ipairs(rewardPools) do
            if not lootPools[poolId] and not DO.GetQuestLootPool(poolId) then
                addIssue(errors, "Blueprint references missing reward pool: " .. tostring(poolId))
            end
        end
    end

    if blueprint.dialogueTree and not dialogueTrees[blueprint.dialogueTree] and not DO.GetQuestDialogueTree(blueprint.dialogueTree) then
        addIssue(errors, "Blueprint references missing dialogue tree: " .. tostring(blueprint.dialogueTree))
    end

    return #errors == 0, errors, warnings
end
