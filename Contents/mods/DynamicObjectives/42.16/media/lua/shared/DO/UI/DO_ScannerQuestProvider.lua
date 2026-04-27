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

local function getEntryKeys(entry)
    if type(entry) ~= "table" then
        return {}
    end

    local keys = {}
    local seen = {}
    local function add(value)
        local text = value and tostring(value) or ""
        if text == "" or seen[text] == true then
            return
        end
        seen[text] = true
        keys[#keys + 1] = text
    end

    local hookId = tostring(entry.hookId or "")
    local entryKind = tostring(entry.entryKind or "")
    local uuid = tostring(entry.uuid or "")
    local questID = tostring(entry.questID or "")
    local incidentId = tostring(entry.incidentId or "")
    local x = tonumber(entry.x)
    local y = tonumber(entry.y)
    local z = tonumber(entry.z)

    add(getEntryID(entry))
    if questID ~= "" then
        add("quest:" .. questID)
        if hookId ~= "" then
            add("hookquest:" .. hookId .. ":" .. questID)
        end
    end
    if incidentId ~= "" then
        add("incident:" .. incidentId)
        if hookId ~= "" then
            add("hookincident:" .. hookId .. ":" .. incidentId)
        end
    end
    if uuid ~= "" then
        add("uuid:" .. uuid)
        if hookId ~= "" and entryKind ~= "" then
            add("hookuuid:" .. hookId .. ":" .. entryKind .. ":" .. uuid)
        end
        if x ~= nil and y ~= nil then
            add(string.format("uuidpos:%s:%d:%d:%d", uuid, math.floor(x), math.floor(y), math.floor(tonumber(z) or 0)))
        end
    end
    if uuid ~= "" and hookId ~= "" and entryKind ~= "" and x ~= nil and y ~= nil then
        add(string.format("hookpos:%s:%s:%s:%d:%d:%d", hookId, entryKind, uuid, math.floor(x), math.floor(y), math.floor(tonumber(z) or 0)))
    end

    return keys
end

local function registerScannerEntry(results, seen, entry)
    local keys = getEntryKeys(entry)
    if #keys == 0 then
        return false
    end

    for _, key in ipairs(keys) do
        if seen[key] == true then
            return false
        end
    end

    for _, key in ipairs(keys) do
        seen[key] = true
    end
    results[#results + 1] = entry
    return true
end

local function formatHoursLabel(prefix, hours)
    local value = tonumber(hours)
    if not value then
        return ""
    end
    return string.format("%s %.1fh", tostring(prefix or "Expires"), math.max(0, value))
end

local function humanizeID(value)
    local text = tostring(value or "")
    text = text:gsub("_%d+$", "")
    text = text:gsub("[%_%-]+", " ")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return (text:gsub("(%a)([%w']*)", function(first, rest)
        local head = tostring(first or "")
        local tail = tostring(rest or "")
        if head == "" then
            return tail
        end
        return string.upper(head) .. string.lower(tail)
    end))
end

local function resolveFactionDisplayName(factionID, fallback)
    local id = factionID and tostring(factionID) or nil
    if id and id ~= "" and DynamicTrading_Factions and DynamicTrading_Factions.GetFaction then
        local ok, faction = pcall(function()
            return DynamicTrading_Factions.GetFaction(id)
        end)
        if ok and type(faction) == "table" and faction.name and tostring(faction.name) ~= "" then
            return tostring(faction.name)
        end
    end

    if id and id ~= "" and ModData and ModData.get then
        local factionData = ModData.get("DynamicTrading_Factions")
        local faction = type(factionData) == "table" and factionData[id] or nil
        if type(faction) == "table" and faction.name and tostring(faction.name) ~= "" then
            return tostring(faction.name)
        end
    end

    local fallbackText = fallback and tostring(fallback) or ""
    if fallbackText ~= "" and fallbackText ~= id then
        return fallbackText
    end

    return humanizeID(id) or humanizeID(fallbackText) or "Independent"
end

local function getItemDisplayName(itemType)
    local value = tostring(itemType or "")
    if value == "" then
        return "Item"
    end

    local masterList = DynamicTrading and DynamicTrading.Config and DynamicTrading.Config.MasterList or nil
    if type(masterList) == "table" then
        local itemData = type(masterList[value]) == "table" and masterList[value] or nil
        if not itemData then
            for _, data in pairs(masterList) do
                if type(data) == "table" and tostring(data.item or "") == value then
                    itemData = data
                    break
                end
            end
        end
        if itemData and itemData.displayName and tostring(itemData.displayName) ~= "" then
            return tostring(itemData.displayName)
        end
        if itemData and itemData.name and tostring(itemData.name) ~= "" then
            return tostring(itemData.name)
        end
    end

    local manager = (getScriptManager and getScriptManager()) or (ScriptManager and ScriptManager.instance) or nil
    if manager and manager.getItem then
        local ok, scriptItem = pcall(function()
            return manager:getItem(value)
        end)
        if ok and scriptItem and scriptItem.getDisplayName then
            local okName, name = pcall(function()
                return scriptItem:getDisplayName()
            end)
            if okName and name and tostring(name) ~= "" then
                return tostring(name)
            end
        end
    end

    return humanizeID(value:match("([^%.]+)$") or value) or value
end

local function buildRewardTextFromRewards(rewards)
    local parts = {}
    for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
        if type(reward) == "table" then
            local kind = tostring(reward.kind or reward.type or ""):lower()
            if kind == "item" then
                local itemType = tostring(reward.itemType or reward.item or "Item")
                parts[#parts + 1] = tostring(math.max(1, math.floor(tonumber(reward.count) or 1))) .. "x " .. getItemDisplayName(itemType)
            elseif kind == "money" then
                parts[#parts + 1] = "$" .. tostring(math.floor(tonumber(reward.amount) or 0))
            elseif kind == "reputation" then
                local amount = math.floor(tonumber(reward.amount) or 0)
                parts[#parts + 1] = (amount > 0 and "+" or "") .. tostring(amount) .. " rep"
            elseif reward.previewText and tostring(reward.previewText) ~= "" then
                parts[#parts + 1] = tostring(reward.previewText)
            end
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or ""
end

local function firstNonEmptyText(primary, fallback)
    local primaryText = primary and tostring(primary) or ""
    if primaryText ~= "" then
        return primaryText
    end
    local fallbackText = fallback and tostring(fallback) or ""
    return fallbackText
end

local function cleanDisplayText(text, rawID, displayName)
    local value = tostring(text or "")
    local raw = rawID and tostring(rawID) or ""
    local name = displayName and tostring(displayName) or ""
    if value == "" then
        return value
    end
    if raw ~= "" and name ~= "" and raw ~= name then
        value = value:gsub(raw:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"), name)
    end
    return value
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

    if DO.Quests and DO.Quests.Runtime and DO.Quests.Runtime.resolveQuestContactLocationForSoul then
        return DO.Quests.Runtime.resolveQuestContactLocationForSoul(soul, tostring(soul.name or "Quest Contact"), {
            preferHome = true,
            homeLabel = tostring((type(soul.homeCoords) == "table" and soul.homeCoords.name) or (tostring(soul.name or "Quest Contact") .. "'s Base")),
            radius = 8,
            symbolID = "DOQuestTurnIn",
            worldIcon = "friend.png",
            r = 0.25,
            g = 0.85,
            b = 1.0,
            a = 1.0,
            scale = 1.0,
            maxDrift = 64,
        })
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
                            factionName = resolveFactionDisplayName(soul.factionID, soul.factionName),
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
    local factionID = (detail and detail.giverFactionID) or quest.giverFactionID or quest.factionID or nil
    local factionName = resolveFactionDisplayName(factionID, (detail and detail.giverFactionName) or quest.giverFactionName or "Objective")
    local rewardText = firstNonEmptyText(buildRewardTextFromRewards(quest.rewards), detail and detail.rewardPreview)

    return {
        uuid = tostring(quest.id),
        questID = tostring(quest.id),
        entryKind = "activeQuest",
        name = cleanDisplayText((detail and (detail.title or detail.name)) or quest.title or quest.name or quest.id, factionID, factionName),
        faction = factionID,
        factionName = factionName,
        archetype = (detail and detail.giverTitle) or "Quest",
        gender = "Unknown",
        identitySeed = 1,
        x = marker.x,
        y = marker.y,
        z = marker.z,
        distText = string.format("Objective: %.0fm", dist),
        expireText = remainingHours ~= nil and formatHoursLabel("Expires", remainingHours) or "",
        rewardText = rewardText,
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
    local factionID = traderContext.factionID
    local factionName = resolveFactionDisplayName(factionID, traderContext.factionName or traderContext.faction)
    local rewardText = firstNonEmptyText(buildRewardTextFromRewards(spec and spec.rewards), spec and spec.rewardPreview)

    local blueprintID = tostring(offer.blueprintId or (spec and spec.blueprintId) or "")
    local traderID = tostring(traderContext.traderID or traderContext.id or "radio")
    return {
        uuid = "DOOffer_" .. traderID .. "_" .. blueprintID,
        entryKind = "availableQuest",
        offerBlueprintId = blueprintID,
        name = cleanDisplayText(offer.menuLabel or (spec and (spec.title or spec.name)) or "Available Quest", factionID, factionName),
        faction = factionID,
        factionName = factionName,
        archetype = tostring(traderContext.archetype or "Quest Contact"),
        gender = "Unknown",
        identitySeed = 1,
        x = target.x,
        y = target.y,
        z = target.z,
        distText = (spec and spec.pickupLocation) and string.format("Pickup: %.0fm", dist) or string.format("Objective: %.0fm", dist),
        expireText = remainingBoardHours and formatHoursLabel("Board", remainingBoardHours) or "Available today",
        rewardText = rewardText,
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
                    registerScannerEntry(results, seen, entry)
                end
            end
        end
    end

    local activeQuests = DO.Quests and DO.Quests.GetActiveQuests and DO.Quests.GetActiveQuests(player) or {}
    for _, quest in ipairs(activeQuests) do
        local entry = buildGenericQuestScannerEntry(player, quest)
        registerScannerEntry(results, seen, entry)
    end

    for _, entry in ipairs(collectAvailableOfferEntries(player)) do
        registerScannerEntry(results, seen, entry)
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
