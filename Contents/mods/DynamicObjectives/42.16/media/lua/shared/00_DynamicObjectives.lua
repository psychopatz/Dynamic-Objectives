DynamicObjectives = DynamicObjectives or {}

local DO = DynamicObjectives

DO.Version = DO.Version or "0.1.0"
DO.Quests = DO.Quests or {}
DO.Kills = DO.Kills or {}
DO.Loot = DO.Loot or {}
DO.MapMarkers = DO.MapMarkers or {}
DO.WorldMarkers = DO.WorldMarkers or {}
DO.Integration = DO.Integration or {}

local function fallbackPrint(message)
    if print then
        print("[DynamicObjectives] " .. tostring(message))
    end
end

function DO.Log(category, topic, message)
    if DynamicTrading and DynamicTrading.Log then
        DynamicTrading.Log("DTObjectives", tostring(category or "Log"), tostring(topic or "Core"), tostring(message or ""))
        return
    end

    fallbackPrint(string.format("[%s][%s] %s", tostring(category or "Log"), tostring(topic or "Core"), tostring(message or "")))
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

    if DO.MapMarkers and DO.MapMarkers.RequestFullRefresh then
        DO.MapMarkers.RequestFullRefresh()
    end

    if DO.WorldMarkers and DO.WorldMarkers.RequestFullRefresh then
        DO.WorldMarkers.RequestFullRefresh()
    end
end

require "DO/Integration/DO_V2Integration"
require "DO/Quests/DO_QuestItemRuntime"
require "DO/Quests/DO_QuestRuntime"
require "DO/Kills/DO_KillTracking"

DO.Log("Init", "Core", "Shared bootstrap loaded")
