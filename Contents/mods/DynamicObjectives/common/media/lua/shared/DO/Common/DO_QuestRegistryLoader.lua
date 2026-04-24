DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.QuestRegistryLoader = DO.QuestRegistryLoader or {
    loaded = false,
}

function DO.QuestRegistryLoader.LoadShippedContent()
    if DO.QuestRegistryLoader.loaded == true then
        return true
    end

    local ok, err = pcall(require, "DO/Common/Presets/DO_DefaultQuestPresets")
    if not ok then
        DO.Log("Quest", "Registry", "Failed to load shipped quest presets: " .. tostring(err))
        return false
    end

    DO.QuestRegistryLoader.loaded = true
    DO.Log("Quest", "Registry", "Loaded shipped quest blueprints, loot pools, and dialogue trees")
    return true
end

