DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

local DO = DynamicObjectives
local UI = DO.UI

UI.ShowScannerQuestTab = true
UI.ScannerQuestRefreshIntervalMs = UI.ScannerQuestRefreshIntervalMs or 30000

local MAX_RADIO_QUEST_TRADERS = 2

local function getWorldAgeHours()
    if DO.Quests and DO.Quests.Runtime and DO.Quests.Runtime.getWorldAgeHours then
        return DO.Quests.Runtime.getWorldAgeHours()
    end
    local gameTime = getGameTime and getGameTime() or nil
    return gameTime and gameTime.getWorldAgeHours and gameTime:getWorldAgeHours() or 0
end

local function getEntryID(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return tostring(entry.questID or entry.incidentId or entry.uuid or "")
end

local function getRosterData()
    if DT_V2_RadarManager and type(DT_V2_RadarManager.ClientRoster) == "table" then
        return DT_V2_RadarManager.ClientRoster
    end

    return ModData and ModData.get and ModData.get("DynamicTrading_Roster") or nil
end

local function buildLocation(raw, fallbackLabel)
    if type(raw) ~= "table" then
        return nil
    end

    local x = tonumber(raw.x)
    local y = tonumber(raw.y)
    if not x or not y then
        return nil
    end

    return {
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(tonumber(raw.z) or 0),
        label = tostring(raw.label or raw.name or fallbackLabel or "Quest Contact"),
        radius = math.max(4, math.floor(tonumber(raw.radius) or 8)),
        symbolID = tostring(raw.symbolID or "DOQuestTurnIn"),
        worldIcon = tostring(raw.worldIcon or "friend.png"),
        r = tonumber(raw.r) or 0.25,
        g = tonumber(raw.g) or 0.85,
        b = tonumber(raw.b) or 1.0,
        a = tonumber(raw.a) or 1.0,
        scale = tonumber(raw.scale) or 1.0,
    }
end

local function getSoulLocation(soul)
    if type(soul) ~= "table" then
        return nil
    end

    local live = buildLocation({
        x = soul.lastX or soul.x,
        y = soul.lastY or soul.y,
        z = soul.lastZ or soul.z,
        label = tostring(soul.name or "Quest Contact"),
    }, tostring(soul.name or "Quest Contact"))
    if live then
        return live
    end

    return buildLocation(soul.homeCoords, tostring(soul.name or "Quest Contact") .. "'s Camp")
end

local function buildRadioQuestTraderContexts(player)
    local roster = getRosterData()
    local souls = roster and roster.Souls or nil
    if type(souls) ~= "table" then
        return {}
    end

    local px = player and player.getX and player:getX() or 0
    local py = player and player.getY and player:getY() or 0
    local candidates = {}
    for uuid, soul in pairs(souls) do
        if type(soul) == "table" and tostring(soul.status or "") ~= "Dead" then
            local status = tostring(soul.status or soul.state or "")
            local state = tostring(soul.state or soul.status or "")
            if status == "Trading" or status == "Resting" or state == "Trading" or state == "Resting" then
                local pickupLocation = getSoulLocation(soul)
                if pickupLocation then
                    local dx = pickupLocation.x - px
                    local dy = pickupLocation.y - py
                    candidates[#candidates + 1] = {
                        context = {
                            traderID = tostring(uuid),
                            id = tostring(uuid),
                            displayName = tostring(soul.name or "Radio Contact"),
                            name = tostring(soul.name or "Radio Contact"),
                            archetype = tostring(soul.archetypeID or soul.archetype or soul.occupation or "General"),
                            factionID = soul.factionID and tostring(soul.factionID) or nil,
                            factionName = soul.factionName,
                            currentState = status == "Trading" and "Trading" or (state == "Trading" and "Trading" or "Resting"),
                            status = status == "Trading" and "Trading" or (state == "Trading" and "Trading" or "Resting"),
                            pickupLocation = pickupLocation,
                        },
                        distanceSq = (dx * dx) + (dy * dy),
                    }
                end
            end
        end
    end

    table.sort(candidates, function(left, right)
        if tonumber(left and left.distanceSq) == tonumber(right and right.distanceSq) then
            return tostring(left and left.context and left.context.traderID or "") < tostring(right and right.context and right.context.traderID or "")
        end
        return (tonumber(left and left.distanceSq) or math.huge) < (tonumber(right and right.distanceSq) or math.huge)
    end)

    local contexts = {}
    for _, candidate in ipairs(candidates) do
        contexts[#contexts + 1] = candidate.context
        if #contexts >= MAX_RADIO_QUEST_TRADERS then
            break
        end
    end
    return contexts
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

local function buildAvailableOfferScannerEntry(player, traderContext, offer)
    if not player or type(traderContext) ~= "table" or type(offer) ~= "table" or offer.canStart ~= true then
        return nil
    end

    local spec = type(offer.questSpec) == "table" and offer.questSpec or nil
    local target = spec and (spec.pickupLocation or spec.targetLocation) or nil
    target = buildLocation(target, offer.menuLabel or "Quest Objective")
    if not target then
        return nil
    end

    local dist = math.sqrt(((target.x or 0) - player:getX()) ^ 2 + ((target.y or 0) - player:getY()) ^ 2)
    local remainingBoardHours = tonumber(offer.boardExpiresAtWorldHours) and math.max(0, tonumber(offer.boardExpiresAtWorldHours) - getWorldAgeHours()) or nil
    local rewardText = spec and spec.rewardPreview and tostring(spec.rewardPreview) or nil
    local expireText = remainingBoardHours and string.format("Board %.1fh", remainingBoardHours) or "Available today"
    if rewardText and rewardText ~= "" then
        expireText = expireText .. " | " .. rewardText
    end

    local blueprintID = tostring(offer.blueprintId or (spec and spec.blueprintId) or "")
    local traderID = tostring(traderContext.traderID or traderContext.id or "radio")
    return {
        uuid = "DOOffer_" .. traderID .. "_" .. blueprintID,
        entryKind = "availableQuest",
        offerBlueprintId = blueprintID,
        name = tostring(offer.menuLabel or (spec and (spec.title or spec.name)) or "Available Quest"),
        faction = traderContext.factionID,
        factionName = traderContext.factionName or traderContext.factionID or "Quest Board",
        archetype = tostring(traderContext.archetype or "Quest Contact"),
        gender = "Unknown",
        identitySeed = 1,
        x = target.x,
        y = target.y,
        z = target.z,
        distText = (spec and spec.pickupLocation) and string.format("Pickup: %.0fm", dist) or string.format("Objective: %.0fm", dist),
        expireText = expireText,
        isLive = false,
        canLock = false,
        locked = false,
        priority = 100,
        sortTime = tonumber(offer.generatedAtWorldHours) or tonumber(spec and spec.createdAt) or 0,
        traderContext = DO.DeepCopy(traderContext),
    }
end

local function collectAvailableOfferEntries(player)
    local results = {}
    if not player or not (DO.Quests and DO.Quests.BuildTraderQuestOffers) then
        return results
    end

    for _, traderContext in ipairs(buildRadioQuestTraderContexts(player)) do
        local offers = DO.Quests.BuildTraderQuestOffers(player, traderContext) or {}
        for _, offer in ipairs(offers) do
            local entry = buildAvailableOfferScannerEntry(player, traderContext, offer)
            if entry then
                results[#results + 1] = entry
            end
        end
        if #results > 0 then
            break
        end
    end

    return results
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

    for _, entry in ipairs(collectAvailableOfferEntries(player)) do
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

    local nowMs = DO.NowMs and DO.NowMs() or 0
    if nowMs > 0
        and tonumber(UI._lastScannerQuestRefreshAt or 0) > 0
        and nowMs - tonumber(UI._lastScannerQuestRefreshAt or 0) < tonumber(UI.ScannerQuestRefreshIntervalMs or 30000)
    then
        return true
    end
    UI._lastScannerQuestRefreshAt = nowMs

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
