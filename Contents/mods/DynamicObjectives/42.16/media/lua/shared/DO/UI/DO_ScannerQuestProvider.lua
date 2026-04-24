DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

local DO = DynamicObjectives
local UI = DO.UI

UI.ShowScannerQuestTab = true

function UI.GetScannerQuestEntries(player)
    local results = {}
    if not player or not DO.GetObjectiveHookList then
        return results
    end

    for _, hook in ipairs(DO.GetObjectiveHookList()) do
        if hook and hook.buildScannerEntries then
            local entries = hook.buildScannerEntries(player)
            for _, entry in ipairs(type(entries) == "table" and entries or {}) do
                results[#results + 1] = entry
            end
        end
    end

    table.sort(results, function(left, right)
        local leftPriority = tonumber(left and left.priority) or 0
        local rightPriority = tonumber(right and right.priority) or 0
        if leftPriority == rightPriority then
            local leftTime = tonumber(left and (left.sortTime or left.createdAt or left.updatedAt)) or 0
            local rightTime = tonumber(right and (right.sortTime or right.createdAt or right.updatedAt)) or 0
            if leftTime == rightTime then
                return tostring(left and left.uuid or left and left.questID or "") < tostring(right and right.uuid or right and right.questID or "")
            end
            return leftTime > rightTime
        end
        return leftPriority > rightPriority
    end)

    return results
end

function UI.RequestScannerQuestRefresh(player)
    player = player or (DO.GetLocalPlayer and DO.GetLocalPlayer() or nil)
    if not player then
        return false
    end

    if isClient() and not isServer() then
        sendClientCommand(player, "DynamicObjectives", "RefreshObjectiveHooks", {})
        return true
    end

    for _, hook in ipairs(DO.GetObjectiveHookList and DO.GetObjectiveHookList() or {}) do
        if hook and hook.refreshIncidentsForPlayer then
            hook.refreshIncidentsForPlayer(player)
        end
    end

    if DO.NotifyStateChanged then
        DO.NotifyStateChanged(player)
    end
    return true
end
