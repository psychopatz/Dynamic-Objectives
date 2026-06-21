DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

require "DO/Common/Text/DO_Text"

DO.Version = DO.Version or "0.1.0"
DO.Quests = DO.Quests or {}
DO.Kills = DO.Kills or {}
DO.Loot = DO.Loot or {}
DO.MapMarkers = DO.MapMarkers or {}
DO.WorldMarkers = DO.WorldMarkers or {}
DO.ClearIndicators = DO.ClearIndicators or {}
DO.Integration = DO.Integration or {}
DO.UI = DO.UI or {}
DO.QuestBlueprints = DO.QuestBlueprints or { Registry = {}, Order = {} }
DO.QuestLootPools = DO.QuestLootPools or { Registry = {}, Order = {} }
DO.QuestDialogueTrees = DO.QuestDialogueTrees or { Registry = {}, Order = {} }

local function fallbackPrint(message)
    return message
end

function DO.LogLevel(level, category, topic, message)
    if DynamicTrading and DynamicTrading.LogLevel then
        DynamicTrading.LogLevel(
            tostring(level or "info"),
            "DTObjectives",
            tostring(category or "Log"),
            tostring(topic or "Core"),
            tostring(message or "")
        )
        return
    end

    if DynamicTrading and DynamicTrading.Log then
        DynamicTrading.Log("DTObjectives", tostring(category or "Log"), tostring(topic or "Core"), tostring(message or ""))
        return
    end

    fallbackPrint(string.format("[%s][%s][%s] %s", tostring(level or "info"), tostring(category or "Log"), tostring(topic or "Core"), tostring(message or "")))
end

function DO.Log(category, topic, message)
    DO.LogLevel(nil, category, topic, message)
end

function DO.LogWarn(topic, message)
    DO.LogLevel("warn", "Warn", topic, message)
end

function DO.LogError(topic, message)
    DO.LogLevel("error", "Error", topic, message)
end

function DO.LogDebug(topic, message)
    DO.LogLevel("debug", "Debug", topic, message)
end

function DO.LogTrace(topic, message)
    DO.LogLevel("trace", "Trace", topic, message)
end

function DO.NowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    if getGametimeTimestamp then
        return math.floor(getGametimeTimestamp() * 1000)
    end
    return 0
end

function DO.DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy

    for key, inner in pairs(value) do
        copy[DO.DeepCopy(key, seen)] = DO.DeepCopy(inner, seen)
    end

    return copy
end

function DO.SerializeLuaValue(value, indentLevel)
    indentLevel = tonumber(indentLevel) or 0
    local indent = string.rep("    ", indentLevel)
    local childIndent = string.rep("    ", indentLevel + 1)
    local valueType = type(value)

    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    if value == nil then
        return "nil"
    end
    if valueType ~= "table" then
        return string.format("%q", tostring(value))
    end

    local parts = { "{\n" }
    local numericKeys = {}
    local otherKeys = {}

    for key in pairs(value) do
        if type(key) == "number" then
            numericKeys[#numericKeys + 1] = key
        else
            otherKeys[#otherKeys + 1] = key
        end
    end

    table.sort(numericKeys)
    table.sort(otherKeys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    for _, key in ipairs(numericKeys) do
        parts[#parts + 1] = childIndent .. DO.SerializeLuaValue(value[key], indentLevel + 1) .. ",\n"
    end

    for _, key in ipairs(otherKeys) do
        local keyText = type(key) == "string" and string.match(key, "^[%a_][%w_]*$") and key
            or "[" .. DO.SerializeLuaValue(key, indentLevel + 1) .. "]"
        parts[#parts + 1] = childIndent .. tostring(keyText) .. " = " .. DO.SerializeLuaValue(value[key], indentLevel + 1) .. ",\n"
    end

    parts[#parts + 1] = indent .. "}"
    return table.concat(parts)
end

function DO.GetPlayerKey(player)
    if not player then
        return "unknown"
    end

    local onlineID = player.getOnlineID and player:getOnlineID() or nil
    if onlineID ~= nil and tonumber(onlineID) ~= nil and tonumber(onlineID) >= 0 then
        return "online:" .. tostring(onlineID)
    end

    local username = player.getUsername and player:getUsername() or nil
    if username and username ~= "" then
        return "user:" .. tostring(username)
    end

    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    return "local:" .. tostring(playerNum)
end

function DO.TransmitPlayerData(player)
    if player and player.transmitModData then
        player:transmitModData()
    end
end

function DO.GetLocalPlayer()
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

function DO.NotifyStateChanged(player)
    DO.TransmitPlayerData(player)

    if isServer() and not isClient() then
        return
    end

    if DO.ZombieTargetResolver and DO.ZombieTargetResolver.ClearAll then
        DO.ZombieTargetResolver.ClearAll()
    end

    if DO.MapMarkers and DO.MapMarkers.RequestFullRefresh then
        DO.MapMarkers.RequestFullRefresh()
    end

    if DO.WorldMarkers and DO.WorldMarkers.RequestFullRefresh then
        DO.WorldMarkers.RequestFullRefresh()
    end

    if DO.ClearIndicators and DO.ClearIndicators.RequestFullRefresh then
        DO.ClearIndicators.RequestFullRefresh()
    end

    if DO.MapMarkers and DO.MapMarkers.Refresh then
        DO.MapMarkers.Refresh(player)
    end

    if DO.WorldMarkers and DO.WorldMarkers.Refresh then
        DO.WorldMarkers.Refresh(player)
    end

    if DO.ClearIndicators and DO.ClearIndicators.Refresh then
        DO.ClearIndicators.Refresh(player)
    end

    if DO_MissionModalShared and DO_MissionModalShared.ProcessMissionEvents then
        DO_MissionModalShared.ProcessMissionEvents(player)
    end

    if DT_RadioScannerWindow and DT_RadioScannerWindow.instance and DT_RadioScannerWindow.instance.currentCategory == "Quest" then
        DT_RadioScannerWindow.instance.skipQuestServerRefresh = true
        DT_RadioScannerWindow.instance:refresh()
    end
end

require "DO/Integration/DO_V2Integration"
require "DO/Common/DO_MedicalItemUtils"
require "DO/Common/DO_ObjectiveHookRegistry"
require "DO/Common/DO_QuestRegistry"
require "DO/Common/DO_QuestBlueprintValidator"
require "DO/Common/DO_QuestRegistryLoader"
require "DO/Rewards/DO_Rewards"
require "DO/Quests/DO_QuestItemRuntime"
require "DO/Quests/QuestRuntime/QuestRuntime"
require "DO/Objectives/DO_ObjectiveHooks"
require "DO/UI/DO_ScannerQuestProvider"
require "DO/UI/DO_MissionEventQueue"
require "DO/Kills/DO_KillTracking"

if DO.QuestRegistryLoader and DO.QuestRegistryLoader.LoadShippedContent then
    DO.QuestRegistryLoader.LoadShippedContent()
end

DO.Log("Init", "Core", "Shared bootstrap loaded")
