DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local RESTING_FAMILY_ORDER = {
    "Courier",
    "KillZone",
    "HuntDrop",
}

local RESTING_FAMILY_INDEX = {
    Courier = 1,
    KillZone = 2,
    HuntDrop = 3,
}

local MAX_FAMILY_HISTORY = 6
local DAILY_BOARD_HOURS = 24

local function ambientLog(message)
    Runtime.questLog("Quest", "Ambient", message)
end

local function isQuestBoardState(state)
    local normalized = Runtime.normalizeText and Runtime.normalizeText(state) or string.lower(tostring(state or ""))
    return normalized == "resting" or normalized == "trading"
end

local function isRestingFamily(family)
    return RESTING_FAMILY_INDEX[tostring(family or "")] ~= nil
end

local function getCurrentBoardDay()
    local worldHours = Runtime.getWorldAgeHours and Runtime.getWorldAgeHours() or 0
    return math.floor((tonumber(worldHours) or 0) / DAILY_BOARD_HOURS)
end

local function getBoardKey(traderContext)
    local traderID = traderContext and tostring(traderContext.traderID or traderContext.id or "") or ""
    if traderID == "" then
        traderID = "radio_board"
    end
    return traderID
end

local function ensureAmbientOfferState(store, create)
    if not store then
        return nil
    end

    local state = store.ambientOfferState
    if not state and create then
        state = {}
        store.ambientOfferState = state
    end

    if state then
        state.entries = type(state.entries) == "table" and state.entries or {}
        state.familyHistory = type(state.familyHistory) == "table" and state.familyHistory or {}
        state.lastRefreshWorldHours = tonumber(state.lastRefreshWorldHours) or 0
        state.lastSelectionKey = tostring(state.lastSelectionKey or "")
        state.lastTraderId = state.lastTraderId and tostring(state.lastTraderId) or nil
        state.lastTraderState = state.lastTraderState and tostring(state.lastTraderState) or nil
        state.boards = type(state.boards) == "table" and state.boards or {}
    end

    return state
end

local function getFamilyHistoryRank(state, family)
    local probe = tostring(family or "")
    for index, entry in ipairs(state and state.familyHistory or {}) do
        if tostring(entry or "") == probe then
            return index
        end
    end
    return math.huge
end

local function pushFamilyHistory(state, family)
    if not state or not isRestingFamily(family) then
        return
    end

    local probe = tostring(family)
    local filtered = {}
    filtered[1] = probe
    for _, entry in ipairs(state.familyHistory or {}) do
        local text = tostring(entry or "")
        if text ~= probe then
            filtered[#filtered + 1] = text
        end
        if #filtered >= MAX_FAMILY_HISTORY then
            break
        end
    end
    state.familyHistory = filtered
end

local function compareFamilyPriority(state, leftFamily, rightFamily)
    local leftRank = getFamilyHistoryRank(state, leftFamily)
    local rightRank = getFamilyHistoryRank(state, rightFamily)
    if leftRank == rightRank then
        return (RESTING_FAMILY_INDEX[tostring(leftFamily or "")] or math.huge)
            < (RESTING_FAMILY_INDEX[tostring(rightFamily or "")] or math.huge)
    end
    return leftRank > rightRank
end

local function buildAmbientCandidate(player, traderContext, store, blueprint)
    local family = tostring(blueprint and blueprint.family or "")
    if not isRestingFamily(family) then
        return nil, "non_resting_family"
    end

    local activeQuest = Runtime.getActiveQuestForBlueprint and Runtime.getActiveQuestForBlueprint(store, blueprint.id) or nil
    if activeQuest then
        return nil, "active_quest"
    end

    local cooldownRemaining = Runtime.getBlueprintCooldownRemaining and Runtime.getBlueprintCooldownRemaining(store, blueprint) or 0
    if tonumber(cooldownRemaining) and tonumber(cooldownRemaining) > 0 then
        return nil, string.format("cooldown_%.1fh", tonumber(cooldownRemaining))
    end

    local spec = Runtime.buildEntryChainSpec and Runtime.buildEntryChainSpec(player, traderContext, blueprint, store)
        or Runtime.buildQuestSpecFromBlueprint(player, traderContext, blueprint)
    if not spec then
        return nil, "build_failed"
    end

    return {
        family = family,
        blueprintId = tostring(blueprint.id or family),
        blueprint = blueprint,
        weight = tonumber(spec.offerWeight) or tonumber(blueprint.weight) or 1,
        questSpec = spec,
    }, nil
end

local function collectAmbientCandidates(player, traderContext, store)
    local results = {}
    local rejections = {}
    local traderState = tostring(traderContext and (traderContext.currentState or traderContext.state or traderContext.status) or "")

    for _, blueprint in ipairs(DO.GetQuestBlueprintList and DO.GetQuestBlueprintList() or {}) do
        local family = tostring(blueprint and blueprint.family or "")
        if blueprint and blueprint.enabled ~= false and isRestingFamily(family) then
            if Runtime.blueprintMatchesEligibility and Runtime.blueprintMatchesEligibility(player, traderContext, blueprint) then
                local candidate, reason = buildAmbientCandidate(player, traderContext, store, blueprint)
                if candidate then
                    results[family] = candidate
                else
                    rejections[family] = reason or "unavailable"
                end
            else
                rejections[family] = traderState ~= "" and ("state_" .. traderState) or "not_eligible"
            end
        end
    end

    return results, rejections
end

local function countCoveredFamilies(coveredFamilies)
    local total = 0
    for _, family in ipairs(RESTING_FAMILY_ORDER) do
        if coveredFamilies and coveredFamilies[family] == true then
            total = total + 1
        end
    end
    return total
end

local function buildSelectionKey(traderContext, selected)
    local parts = {
        tostring(traderContext and (traderContext.traderID or traderContext.id) or ""),
        tostring(traderContext and (traderContext.currentState or traderContext.state or traderContext.status) or ""),
    }
    for _, entry in ipairs(selected or {}) do
        parts[#parts + 1] = tostring(entry.family or "")
        parts[#parts + 1] = tostring(entry.blueprintId or "")
    end
    return table.concat(parts, "|")
end

local function buildCachedOffers(player, traderContext, store, coveredFamilies, board)
    local results = {}
    if type(board) ~= "table" or type(board.offers) ~= "table" then
        return results
    end

    for _, cached in ipairs(board.offers) do
        local blueprintID = tostring(cached and cached.blueprintId or "")
        local family = tostring(cached and cached.family or "")
        local blueprint = blueprintID ~= "" and DO.GetQuestBlueprint and DO.GetQuestBlueprint(blueprintID) or nil
        if blueprint
            and blueprint.enabled ~= false
            and not (coveredFamilies and coveredFamilies[family] == true)
            and not (Runtime.getActiveQuestForBlueprint and Runtime.getActiveQuestForBlueprint(store, blueprintID))
            and not (Runtime.getBlueprintCooldownRemaining and Runtime.getBlueprintCooldownRemaining(store, blueprint) > 0)
        then
            local questSpec = type(cached.questSpec) == "table" and DO.DeepCopy(cached.questSpec) or nil
            if questSpec then
                results[#results + 1] = {
                    family = family,
                    blueprintId = blueprintID,
                    blueprint = blueprint,
                    weight = tonumber(cached.weight) or tonumber(blueprint.weight) or 1,
                    questSpec = questSpec,
                    boardDay = tonumber(board.day) or getCurrentBoardDay(),
                    boardExpiresAtWorldHours = tonumber(board.expiresAtWorldHours) or nil,
                    generatedAtWorldHours = tonumber(cached.generatedAtWorldHours) or tonumber(board.generatedAtWorldHours) or 0,
                }
            end
        end
    end

    return results
end

function Runtime.selectAmbientRestingOffers(player, traderContext, store, coveredFamilies)
    store = store or (Runtime.getStore and Runtime.getStore(player, true) or nil)
    local state = ensureAmbientOfferState(store, true)
    if not player or not store or not state then
        return {}
    end

    local traderState = tostring(traderContext and (traderContext.currentState or traderContext.state or traderContext.status) or "")
    if not isQuestBoardState(traderState) then
        state.entries = {}
        state.lastTraderId = traderContext and tostring(traderContext.traderID or traderContext.id or "") or nil
        state.lastTraderState = traderState
        if state.lastSelectionKey ~= ("skip|" .. traderState) then
            ambientLog("Skipping ambient resting offers: trader state is " .. tostring(traderState ~= "" and traderState or "Unknown"))
            state.lastSelectionKey = "skip|" .. traderState
        end
        return {}
    end

    local boardKey = getBoardKey(traderContext)
    local currentDay = getCurrentBoardDay()
    local board = state.boards and state.boards[boardKey] or nil
    if board and tonumber(board.day) == currentDay then
        return buildCachedOffers(player, traderContext, store, coveredFamilies, board)
    end

    local candidateByFamily, rejectionByFamily = collectAmbientCandidates(player, traderContext, store)
    local coveredCount = countCoveredFamilies(coveredFamilies)
    local configuredMinimum = Runtime.getConfiguredMinimumRestingFamiliesAvailable and Runtime.getConfiguredMinimumRestingFamiliesAvailable() or 0
    local minimumFamilies = math.max(configuredMinimum, #RESTING_FAMILY_ORDER)
    local extraChance = Runtime.getConfiguredRestingContractChancePercent and Runtime.getConfiguredRestingContractChancePercent() or 0
    local requiredCount = math.max(0, minimumFamilies - coveredCount)
    local selected = {}
    local selectedFamilies = {}
    local dailyRolls = {}

    local orderedFamilies = {}
    for _, family in ipairs(RESTING_FAMILY_ORDER) do
        orderedFamilies[#orderedFamilies + 1] = family
    end
    table.sort(orderedFamilies, function(left, right)
        return compareFamilyPriority(state, left, right)
    end)

    for _, family in ipairs(orderedFamilies) do
        local candidate = candidateByFamily[family]
        if coveredFamilies and coveredFamilies[family] == true then
            rejectionByFamily[family] = rejectionByFamily[family] or "already_covered"
        elseif candidate and #selected < requiredCount then
            local passed, roll = Runtime.rollChancePercent(extraChance)
            dailyRolls[#dailyRolls + 1] = string.format("%s=%s(%s/%s)", family, passed and "pass" or "floor", tostring(roll), tostring(extraChance))
            selected[#selected + 1] = candidate
            selectedFamilies[family] = true
        end
    end

    local optionalRolls = {}
    if #selected >= requiredCount then
        for _, family in ipairs(orderedFamilies) do
            local candidate = candidateByFamily[family]
            if candidate and not selectedFamilies[family] and not (coveredFamilies and coveredFamilies[family] == true) then
                local passed, roll = Runtime.rollChancePercent(extraChance)
                optionalRolls[#optionalRolls + 1] = string.format("%s=%s(%s/%s)", family, passed and "pass" or "fail", tostring(roll), tostring(extraChance))
                if passed then
                    selected[#selected + 1] = candidate
                    selectedFamilies[family] = true
                end
            end
        end
    end

    state.entries = {}
    local boardOffers = {}
    local generatedAtWorldHours = Runtime.getWorldAgeHours and Runtime.getWorldAgeHours() or 0
    local expiresAtWorldHours = (currentDay + 1) * DAILY_BOARD_HOURS
    for _, entry in ipairs(selected) do
        state.entries[#state.entries + 1] = {
            family = tostring(entry.family or ""),
            blueprintId = tostring(entry.blueprintId or ""),
            generatedAtWorldHours = generatedAtWorldHours,
        }
        boardOffers[#boardOffers + 1] = {
            family = tostring(entry.family or ""),
            blueprintId = tostring(entry.blueprintId or ""),
            weight = tonumber(entry.weight) or 1,
            questSpec = DO.DeepCopy(entry.questSpec),
            generatedAtWorldHours = generatedAtWorldHours,
        }
        pushFamilyHistory(state, entry.family)
    end

    state.boards[boardKey] = {
        day = currentDay,
        generatedAtWorldHours = generatedAtWorldHours,
        expiresAtWorldHours = expiresAtWorldHours,
        traderId = traderContext and tostring(traderContext.traderID or traderContext.id or "") or nil,
        traderState = traderState,
        offers = boardOffers,
    }
    state.lastRefreshWorldHours = generatedAtWorldHours
    state.lastTraderId = traderContext and tostring(traderContext.traderID or traderContext.id or "") or nil
    state.lastTraderState = traderState

    local selectionKey = buildSelectionKey(traderContext, selected)
    local selectedLabels = {}
    for _, entry in ipairs(selected) do
        selectedLabels[#selectedLabels + 1] = tostring(entry.family or entry.blueprintId or "?")
    end

    local rejectionLabels = {}
    for _, family in ipairs(RESTING_FAMILY_ORDER) do
        if not candidateByFamily[family] and not (coveredFamilies and coveredFamilies[family] == true) then
            rejectionLabels[#rejectionLabels + 1] = family .. "=" .. tostring(rejectionByFamily[family] or "missing")
        end
    end

    if selectionKey ~= state.lastSelectionKey then
        ambientLog(
            "Refresh traderId=" .. tostring(state.lastTraderId or "")
                .. " covered=" .. tostring(coveredCount)
                .. " minimum=" .. tostring(minimumFamilies)
                .. " selected=" .. (#selectedLabels > 0 and table.concat(selectedLabels, ",") or "none")
                .. " extraChance=" .. tostring(extraChance)
                .. " dailyRolls=" .. (#dailyRolls > 0 and table.concat(dailyRolls, ";") or "none")
                .. " extraRolls=" .. (#optionalRolls > 0 and table.concat(optionalRolls, ";") or "none")
                .. " unavailable=" .. (#rejectionLabels > 0 and table.concat(rejectionLabels, ";") or "none")
        )
    end

    state.lastSelectionKey = selectionKey
    return selected
end

Runtime.getAmbientOfferState = ensureAmbientOfferState
Runtime.getRestingFamilyOrder = function()
    local results = {}
    for _, family in ipairs(RESTING_FAMILY_ORDER) do
        results[#results + 1] = family
    end
    return results
end
