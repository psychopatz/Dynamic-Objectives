DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO_QuestPresetIO = DO_QuestPresetIO or {}

local PRESET_PREFIX = "DynamicObjectives_QuestPreset_"
local PRESET_FOLDER_HINT = "Zomboid/Lua/"

local function trim(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function sanitizeName(name)
    local text = trim(name)
    if text == "" then
        text = "custom"
    end

    text = string.gsub(text, "[^%w%-_ ]", "_")
    text = string.gsub(text, "%s+", "_")
    if text == "" then
        text = "custom"
    end

    return text
end

local function readEntireFile(fileName)
    local reader = getFileReader(fileName, false)
    if not reader then
        return nil
    end

    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()

    return table.concat(lines, "\n")
end

local function registerPackage(package)
    if type(package.lootPools) == "table" then
        for poolID, pool in pairs(package.lootPools) do
            DO.RegisterQuestLootPool(poolID, pool)
        end
    end

    if type(package.dialogueTrees) == "table" then
        for treeID, tree in pairs(package.dialogueTrees) do
            DO.RegisterQuestDialogueTree(treeID, tree)
        end
    end

    if type(package.chains) == "table" then
        for chainID, chain in pairs(package.chains) do
            DO.RegisterQuestChain(chainID, chain)
        end
    end

    if type(package.blueprint) == "table" then
        DO.RegisterQuestBlueprint(package.blueprint.id, package.blueprint)
    end

    return true
end

function DO_QuestPresetIO.getFileName(presetName)
    return PRESET_PREFIX .. sanitizeName(presetName) .. ".txt"
end

function DO_QuestPresetIO.getExportPathHint(presetName)
    return PRESET_FOLDER_HINT .. DO_QuestPresetIO.getFileName(presetName)
end

function DO_QuestPresetIO.buildPackageFromBlueprint(blueprintID)
    local blueprint = DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
    if not blueprint then
        return nil, "Blueprint not found: " .. tostring(blueprintID)
    end

    local package = {
        id = tostring(blueprint.id),
        blueprint = DO.DeepCopy(blueprint),
        lootPools = {},
        dialogueTrees = {},
        chains = {},
    }

    local function addPool(poolID)
        if not poolID or package.lootPools[poolID] then
            return
        end
        local pool = DO.GetQuestLootPool and DO.GetQuestLootPool(poolID) or nil
        if pool then
            package.lootPools[poolID] = DO.DeepCopy(pool)
        end
    end

    addPool(blueprint.grantItemPool)
    addPool(blueprint.dropItemPool)
    for _, poolID in ipairs(type(blueprint.rewardPools) == "table" and blueprint.rewardPools or {}) do
        addPool(poolID)
    end

    if blueprint.dialogueTree and DO.GetQuestDialogueTree then
        local tree = DO.GetQuestDialogueTree(blueprint.dialogueTree)
        if tree then
            package.dialogueTrees[blueprint.dialogueTree] = DO.DeepCopy(tree)
        end
    end

    if DO.GetQuestChainList then
        for _, chain in ipairs(DO.GetQuestChainList()) do
            for _, stage in ipairs(chain.stages or {}) do
                if tostring(stage.blueprintId or "") == tostring(blueprintID) then
                    package.chains[chain.id] = DO.DeepCopy(chain)
                    break
                end
            end
        end
    end

    return package
end

function DO_QuestPresetIO.exportPreset(presetName, blueprintID, packageOverride)
    local resolvedName = sanitizeName(presetName)
    local package = packageOverride
    if type(package) ~= "table" then
        local okPackage, err = DO_QuestPresetIO.buildPackageFromBlueprint(blueprintID)
        if not okPackage then
            return false, err
        end
        package = okPackage
    end

    local validator = DO.QuestBlueprintValidator
    if validator and validator.ValidatePackage then
        local ok, errors = validator.ValidatePackage(package)
        if not ok then
            return false, table.concat(errors or {}, "\n")
        end
    end

    local writer = getFileWriter(DO_QuestPresetIO.getFileName(resolvedName), true, false)
    if not writer then
        return false, "Unable to open quest preset file for writing."
    end

    writer:write("return ")
    writer:write(DO.SerializeLuaValue(package))
    writer:write("\r\n")
    writer:close()

    return true, DO_QuestPresetIO.getFileName(resolvedName)
end

function DO_QuestPresetIO.importPreset(presetName)
    local resolvedName = sanitizeName(presetName)
    local fileName = DO_QuestPresetIO.getFileName(resolvedName)
    local content = readEntireFile(fileName)
    if not content or content == "" then
        return false, "Preset file not found: " .. fileName
    end

    local loader = loadstring or load
    local chunk, err = loader(content)
    if not chunk then
        return false, "Preset parse failed: " .. tostring(err)
    end

    local ok, package = pcall(chunk)
    if not ok then
        return false, "Preset execution failed: " .. tostring(package)
    end

    local validator = DO.QuestBlueprintValidator
    if validator and validator.ValidatePackage then
        local valid, errors, warnings = validator.ValidatePackage(package)
        if not valid then
            return false, table.concat(errors or {}, "\n")
        end
        registerPackage(package)
        return true, package, warnings
    end

    registerPackage(package)
    return true, package, {}
end

function DO_QuestPresetIO.registerPackage(package)
    return registerPackage(package)
end

return DO_QuestPresetIO
