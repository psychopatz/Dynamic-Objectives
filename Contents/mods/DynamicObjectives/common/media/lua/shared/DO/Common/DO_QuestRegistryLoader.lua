DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.QuestRegistryLoader = DO.QuestRegistryLoader or {
    loaded = false,
}

function DO.QuestRegistryLoader.LoadShippedContent()
    if DO.QuestRegistryLoader.loaded == true then
        return true
    end

    local okModules, errModules = pcall(require, "DO/Common/QuestContentModules/DO_QuestContentModules")
    if not okModules then
        DO.Log("Quest", "Registry", "Failed to register shipped quest content modules: " .. tostring(errModules))
        return false
    end

    local okLoad = false
    local loadedCount = 0
    local errorCount = 1
    if DO.LoadQuestContentModules then
        okLoad, loadedCount, errorCount = DO.LoadQuestContentModules()
    end
    if okLoad ~= true then
        DO.Log("Quest", "Registry", "Failed to load shipped quest content modules. Loaded=" .. tostring(loadedCount or 0) .. " Errors=" .. tostring(errorCount or 0))
        return false
    end

    DO.QuestRegistryLoader.loaded = true
    DO.Log("Quest", "Registry", "Loaded shipped quest content modules (" .. tostring(loadedCount or 0) .. " paths)")
    return true
end
