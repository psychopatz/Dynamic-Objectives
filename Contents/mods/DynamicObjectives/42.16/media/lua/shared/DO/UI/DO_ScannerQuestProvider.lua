DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

local DO = DynamicObjectives
local UI = DO.UI

UI.ShowScannerQuestTab = true

local function getEntryID(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return tostring(entry.questID or entry.incidentId or entry.uuid or "")
end

local function buildGenericQuestScannerEntry(player, quest)
    if not player or not quest or tostring(quest.status or "") ~= "active" then
        return nil
    end

    local marker = DO.Quests and DO.Quests.GetQuestMarkerData and DO.Quests.GetQuestMarkerData(player, quest) or nil
    if not marker then
        return nil
    end

    local detail = DO.Quests and DO.Quests.GetQuestDetailData and DO.Quests.GetQuestDetailData(player, quest.id) or nil
    local dist = math.sqrt(((marker.x or 0) - player:getX()) ^ 2 + ((marker.y or 0) - player:getY()) ^ 2)
    local remainingHours = detail and tonumber(detail.timeRemainingHours) or nil
    local expireText = remainingHours ~= nil and string.format("Expires in %.1fh", math.max(0, remainingHours))
        or (detail and detail.rewardPreview and ("Rewards: " .. tostring(detail.rewardPreview)))
        or (detail and detail.currentObjectiveLabel)
        or ""

    return {
        uuid = tostring(quest.id),
        questID = tostring(quest.id),
        entryKind = "activeQuest",
        name = tostring((detail and (detail.title or detail.name)) or quest.title or quest.name or quest.id),
        faction = (detail and detail.giverFactionID) or quest.giverFactionID or quest.factionID or nil,
        factionName = (detail and detail.giverFactionName) or quest.giverFactionName or "Objective",
        archetype = (detail and detail.giverTitle) or "Quest",
        gender = "Unknown",
        identitySeed = 1,
        x = marker.x,
        y = marker.y,
        z = marker.z,
        distText = string.format("Objective: %.0fm", dist),
        expireText = expireText,
        isLive = false,
        canLock = false,
        locked = false,
        priority = 110,
        sortTime = tonumber(quest.createdAt) or 0,
    }
end

function UI.GetScannerQuestEntries(player)
    local results = {}
    local seen = {}
    if not player then
        return results
    end

    if DO.GetObjectiveHookList then
        for _, hook in ipairs(DO.GetObjectiveHookList()) do
            if hook and hook.buildScannerEntries then
                local entries = hook.buildScannerEntries(player)
                for _, entry in ipairs(type(entries) == "table" and entries or {}) do
                    local entryID = getEntryID(entry)
                    if entryID and not seen[entryID] then
                        seen[entryID] = true
                        results[#results + 1] = entry
                    end
                end
            end
        end
    end

    local activeQuests = DO.Quests and DO.Quests.GetActiveQuests and DO.Quests.GetActiveQuests(player) or {}
    for _, quest in ipairs(activeQuests) do
        local entry = buildGenericQuestScannerEntry(player, quest)
        local entryID = getEntryID(entry)
        if entryID and not seen[entryID] then
            seen[entryID] = true
            results[#results + 1] = entry
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
