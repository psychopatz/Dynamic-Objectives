DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local function getQuestEndTimestamp(quest)
    if not quest then
        return 0
    end

    return tonumber(quest.completedAt or quest.failedAt or quest.abandonedAt or quest.createdAt) or 0
end

local function getQuestStatusLabel(quest)
    local status = quest and tostring(quest.status or "active") or "active"
    if status == "completed" then
        return "Completed"
    end
    if status == "failed" then
        return "Failed"
    end
    if status == "abandoned" then
        return "Abandoned"
    end
    return "Active"
end

local function getQuestChainData(quest)
    if not quest or not quest.chainId then
        return nil
    end

    local chain = Runtime.getChain and Runtime.getChain(quest.chainId) or nil
    local stageCount = chain and #(chain.stages or {}) or 0
    local stageIndex = math.max(1, tonumber(quest.chainStageIndex) or 1)
    local label = tostring(quest.chainLabel or (chain and chain.label) or quest.chainId)

    return {
        chainId = tostring(quest.chainId),
        label = label,
        stageId = quest.chainStageId and tostring(quest.chainStageId) or nil,
        stageIndex = stageIndex,
        stageCount = math.max(stageIndex, stageCount),
        nextStageId = quest.chainNextStageId and tostring(quest.chainNextStageId) or nil,
        summary = string.format("%s %d/%d", label, stageIndex, math.max(stageIndex, stageCount)),
    }
end

local function getQuestMarkerLocation(quest)
    if not quest then
        return nil
    end

    local pendingObjective = Runtime.getPendingObjective and Runtime.getPendingObjective(quest) or nil
    return Runtime.questLocationFor and Runtime.questLocationFor(quest, pendingObjective) or quest.targetLocation
end

local function buildObjectiveLines(quest, zoneState)
    local lines = {}
    local totalSteps = #(quest.objectives or {})
    local currentStep = totalSteps > 0 and totalSteps or 1
    local currentObjective = nil
    local activeKillObjective = nil
    local currentObjectiveLabel = nil
    local hasAreaClearObjective = false

    for index, objective in ipairs(quest.objectives or {}) do
        if not currentObjective and objective.completed ~= true then
            currentObjective = objective
            currentStep = index
            currentObjectiveLabel = tostring(objective.label or objective.id)
        end

        if not activeKillObjective and objective.type == "kill" and objective.completed ~= true then
            activeKillObjective = objective
        end

        local progress = math.max(0, tonumber(objective.progress) or 0)
        local required = math.max(1, tonumber(objective.required) or 1)
        local line = {
            id = objective.id,
            label = tostring(objective.label or objective.type),
            completed = objective.completed == true,
            current = objective.completed ~= true and currentObjective and currentObjective.id == objective.id,
            objectiveType = objective.type,
            progress = progress,
            required = required,
            remaining = math.max(0, required - progress),
        }

        if objective.type == "kill" then
            line.value = string.format("%d / %d zombies", progress, required)
        elseif objective.type == "obtainDrop" then
            if objective.completed == true then
                line.value = string.format("%d / %d recovered", required, required)
            elseif progress > 0 then
                line.value = string.format("%d / %d recovered", progress, required)
            elseif objective.dropState and objective.dropState.spawned == true then
                line.value = "Recover the spawned sample"
            else
                line.value = "Keep clearing the zone"
            end
        elseif objective.type == "deliverItem" then
            if objective.completed == true then
                line.value = string.format("%d / %d delivered", required, required)
            elseif progress > 0 then
                line.value = string.format("%d / %d delivered", progress, required)
            else
                line.value = "Take the objective item to the marker"
            end
        elseif objective.type == "areaClear" then
            hasAreaClearObjective = true
            line.value = zoneState and Runtime.buildAreaClearText(zoneState) or "Move into the mission area"
        elseif objective.type == "claimRewards" then
            line.value = objective.completed == true and "Rewards claimed" or "Meet the contact and collect your payout"
        elseif objective.type == "pickupItem" then
            line.value = objective.completed == true and "Picked up" or "Go to the sender and collect the package"
        elseif objective.type == "escortTarget" then
            line.value = objective.completed == true and "Escorted home" or "Keep the trader alive and moving"
        else
            line.value = string.format("%d / %d", progress, required)
        end

        lines[#lines + 1] = line
    end

    if zoneState and not hasAreaClearObjective then
        local zoneCurrent = currentObjective == nil and zoneState.areaClear ~= true
        lines[#lines + 1] = {
            id = "zone_clear",
            label = "Secure the building",
            value = Runtime.buildAreaClearText(zoneState),
            completed = zoneState.areaClear == true,
            accent = zoneState.areaClear == true and "good" or "warn",
            current = zoneCurrent,
        }
        totalSteps = totalSteps + 1
        if zoneCurrent then
            currentStep = totalSteps
            currentObjectiveLabel = "Secure the building"
        end

    end

    if not currentObjective then
        currentObjective = quest.objectives and quest.objectives[#quest.objectives] or nil
    end

    return {
        lines = lines,
        totalSteps = math.max(1, totalSteps),
        currentStep = currentStep,
        currentObjective = currentObjective,
        currentObjectiveLabel = currentObjectiveLabel
            or (currentObjective and tostring(currentObjective.label or currentObjective.id))
            or "Objective",
        activeKillObjective = activeKillObjective,
    }
end

local function buildPrimaryProgress(quest, zoneState, activeKillObjective)
    if activeKillObjective then
        local usesZoneClearProgress = zoneState
            and Runtime.questRequiresAreaClear
            and Runtime.questRequiresAreaClear(quest) == true
        if usesZoneClearProgress then
            if zoneState.playerPresent ~= true then
                return {
                    label = "Secure the Building",
                    value = "Awaiting Arrival",
                    detail = "Move into the mission area to begin the sweep",
                    ratio = 0,
                    color = { r = 0.95, g = 0.62, b = 0.18 },
                }
            end

            if quest.encounter and quest.encounter.spawned ~= true then
                return {
                    label = "Secure the Building",
                    value = "Searching",
                    detail = Runtime.buildAreaClearText(zoneState) or "Move closer to trigger the encounter",
                    ratio = 0,
                    color = { r = 0.95, g = 0.62, b = 0.18 },
                }
            end

            local totalZombies = math.max(
                1,
                math.floor(
                    tonumber(zoneState.totalZombies)
                        or tonumber(activeKillObjective.required)
                        or 1
                )
            )
            local clearedZombies = math.max(0, math.floor(tonumber(zoneState.clearedZombies) or 0))
            local nearbyZombies = math.max(0, math.floor(tonumber(zoneState.nearbyZombies) or math.max(0, totalZombies - clearedZombies)))
            local ratio = math.max(0, math.min(1, clearedZombies / totalZombies))
            return {
                label = "Secure the Building",
                value = string.format("%d / %d cleared", clearedZombies, totalZombies),
                detail = zoneState.areaClear == true
                    and "Area secure"
                    or string.format("%d remaining in the area", nearbyZombies),
                ratio = zoneState.areaClear == true and 1 or ratio,
                color = zoneState.areaClear == true and { r = 0.34, g = 0.82, b = 0.48 } or { r = 0.86, g = 0.28, b = 0.22 },
            }
        end

        local killProgress = math.max(0, tonumber(activeKillObjective.progress) or 0)
        local killRequired = math.max(1, tonumber(activeKillObjective.required) or 1)
        local progressData = {
            label = "Zombies Cleared",
            value = string.format("%d / %d", killProgress, killRequired),
            detail = string.format("%d remaining", math.max(0, killRequired - killProgress)),
            ratio = killProgress / killRequired,
            color = { r = 0.86, g = 0.28, b = 0.22 },
        }
        if quest.encounter and quest.encounter.spawned ~= true then
            progressData.detail = zoneState and Runtime.buildAreaClearText(zoneState) or "Move closer to trigger the encounter"
            progressData.ratio = 0
        end
        return progressData
    end

    if zoneState then
        local totalZombies = math.max(
            0,
            math.floor(
                tonumber(zoneState.totalZombies)
                    or tonumber(zoneState.nearbyZombies)
                    or 0
            )
        )
        local nearbyZombies = math.max(0, math.floor(tonumber(zoneState.nearbyZombies) or 0))
        local clearedZombies = math.max(0, math.floor(tonumber(zoneState.clearedZombies) or (totalZombies - nearbyZombies)))
        local ratio = zoneState.areaClear == true and 1 or 0
        local detail = Runtime.buildAreaClearText(zoneState)
        if totalZombies > 0 then
            ratio = math.max(0, math.min(1, clearedZombies / totalZombies))
            detail = string.format("%d / %d cleared", clearedZombies, totalZombies)
            if zoneState.areaClear ~= true then
                detail = detail .. " | " .. tostring(Runtime.buildAreaClearText(zoneState) or "")
            end
        end
        return {
            label = "Zone Status",
            value = zoneState.areaClear == true and "Secure" or "Active",
            detail = detail,
            ratio = ratio,
            color = zoneState.areaClear == true and { r = 0.34, g = 0.82, b = 0.48 } or { r = 0.95, g = 0.62, b = 0.18 },
        }
    end

    return nil
end

local function buildQuestDetailData(player, quest)
    if not quest then
        return nil
    end

    local chainData = getQuestChainData(quest)
    local zoneState = Quests.GetEncounterStatus(player, quest)
    local lineData = buildObjectiveLines(quest, zoneState)
    local remainingHours = Runtime.getQuestRemainingHours(quest)
    local location = getQuestMarkerLocation(quest)

    local detail = {
        questID = quest.id,
        name = tostring(quest.name or quest.id),
        title = quest.title and tostring(quest.title) or nil,
        status = tostring(quest.status or "active"),
        statusLabel = getQuestStatusLabel(quest),
        tracked = quest.tracked == true,
        located = quest.located == true,
        targetLabel = location and tostring(location.label or "") or "",
        targetLocation = location,
        difficulty = Runtime.normalizeDifficulty(quest.difficulty),
        rewardPreview = quest.rewardPreview and tostring(quest.rewardPreview) or nil,
        giverName = quest.giverName and tostring(quest.giverName) or nil,
        giverTitle = quest.giverTitle and tostring(quest.giverTitle) or nil,
        giverFactionID = quest.giverFactionID and tostring(quest.giverFactionID) or nil,
        giverFactionName = quest.giverFactionName and tostring(quest.giverFactionName) or nil,
        themeID = quest.themeID and tostring(quest.themeID) or nil,
        budgetValue = tonumber(quest.budgetValue) or nil,
        rewardTags = DO.DeepCopy(type(quest.rewardTags) == "table" and quest.rewardTags or {}),
        timeLimitHours = tonumber(quest.timeLimitHours) or 0,
        timeRemainingHours = remainingHours,
        expiresSoon = remainingHours ~= nil and remainingHours <= 1,
        currentStep = lineData.currentStep,
        totalSteps = lineData.totalSteps,
        currentObjectiveLabel = lineData.currentObjectiveLabel,
        difficultyLabel = tostring(quest.difficultyLabel or Runtime.getQuestDifficultyLabel(quest.difficulty)),
        primaryProgress = buildPrimaryProgress(quest, zoneState, lineData.activeKillObjective),
        lines = lineData.lines,
        zoneState = zoneState,
        encounter = quest.encounter,
        chain = chainData,
        chainLabel = chainData and chainData.label or nil,
        chainStageIndex = chainData and chainData.stageIndex or nil,
        chainStageCount = chainData and chainData.stageCount or nil,
        chainSummary = chainData and chainData.summary or nil,
        createdAt = tonumber(quest.createdAt) or 0,
        completedAt = tonumber(quest.completedAt) or nil,
        failedAt = tonumber(quest.failedAt) or nil,
        abandonedAt = tonumber(quest.abandonedAt) or nil,
        completionReason = quest.completionReason and tostring(quest.completionReason) or nil,
        failureReason = quest.failureReason and tostring(quest.failureReason) or nil,
    }
    local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
    if hook and hook.buildSummary then
        local hookSummary = hook.buildSummary(player, quest, detail)
        if type(hookSummary) == "table" then
            detail.hookSummary = hookSummary
            if hookSummary.name then
                detail.name = tostring(hookSummary.name)
            end
            if hookSummary.targetLabel then
                detail.targetLabel = tostring(hookSummary.targetLabel)
            end
            if hookSummary.currentObjectiveLabel then
                detail.currentObjectiveLabel = tostring(hookSummary.currentObjectiveLabel)
            end
            if hookSummary.primaryProgress then
                detail.primaryProgress = hookSummary.primaryProgress
            end
            if type(hookSummary.lines) == "table" and #hookSummary.lines > 0 then
                detail.lines = hookSummary.lines
                detail.totalSteps = math.max(1, #hookSummary.lines)
                detail.currentStep = math.min(detail.totalSteps, math.max(1, tonumber(hookSummary.currentStep) or 1))
            end
        end
    end
    return detail
end

local function buildSummaryFragments(quest, player, detail)
    local parts = {}
    local chainData = detail and detail.chain or getQuestChainData(quest)
    local hookSummary = detail and detail.hookSummary or nil

    if chainData then
        parts[#parts + 1] = chainData.summary
    end

    if detail and detail.giverName then
        local issuer = detail.giverTitle and detail.giverTitle ~= ""
            and (tostring(detail.giverName) .. " (" .. tostring(detail.giverTitle) .. ")")
            or tostring(detail.giverName)
        if detail.giverFactionName and detail.giverFactionName ~= "" then
            issuer = issuer .. " - " .. tostring(detail.giverFactionName)
        end
        parts[#parts + 1] = "Issued by " .. issuer
    end

    if hookSummary and type(hookSummary.summaryFragments) == "table" then
        for _, fragment in ipairs(hookSummary.summaryFragments) do
            if fragment and tostring(fragment) ~= "" then
                parts[#parts + 1] = tostring(fragment)
            end
        end
        if hookSummary.replaceSummaryFragments == true then
            return parts
        end
    end

    local currentLabel = detail and detail.currentObjectiveLabel or nil
    if currentLabel and currentLabel ~= "" and tostring(quest.status or "active") == "active" then
        parts[#parts + 1] = currentLabel
    end

    for _, objective in ipairs(quest.objectives or {}) do
        local progress = math.max(0, math.floor(tonumber(objective.progress) or 0))
        local required = math.max(1, math.floor(tonumber(objective.required) or 1))
        parts[#parts + 1] = string.format("%s %d/%d", tostring(objective.label or objective.type), progress, required)
    end

    local zoneState = detail and detail.zoneState or Quests.GetEncounterStatus(player, quest)
    if zoneState then
        parts[#parts + 1] = Runtime.buildAreaClearText(zoneState)
    end

    local remainingHours = detail and detail.timeRemainingHours or Runtime.getQuestRemainingHours(quest)
    if remainingHours ~= nil then
        parts[#parts + 1] = string.format("Time left %.1fh", remainingHours)
    end

    if quest.rewardPreview and quest.rewardPreview ~= "" then
        parts[#parts + 1] = "Rewards " .. tostring(quest.rewardPreview)
    end

    return parts
end

local function buildMissionSummary(quest, player)
    local detail = buildQuestDetailData(player, quest)
    local parts = buildSummaryFragments(quest, player, detail)
    local badges = {}

    if detail.tracked then
        badges[#badges + 1] = "Tracked"
    end
    if detail.located then
        badges[#badges + 1] = "Located"
    end
    if detail.status ~= "active" then
        badges[#badges + 1] = detail.statusLabel
    end

    local badgeText = #badges > 0 and (" [" .. table.concat(badges, ", ") .. "]") or ""
    local summaryText = #parts > 0 and (" - " .. table.concat(parts, " | ")) or ""
    local displayName = tostring(detail.title or detail.name)
    local display = string.format("%s%s%s", displayName, badgeText, summaryText)
    if detail.hookSummary and detail.hookSummary.display then
        display = tostring(detail.hookSummary.display)
    end

    return {
        questID = quest.id,
        name = detail.name,
        title = detail.title,
        status = detail.status,
        statusLabel = detail.statusLabel,
        tracked = detail.tracked,
        located = detail.located,
        display = display,
        targetLabel = detail.targetLabel,
        rewardPreview = detail.rewardPreview,
        giverName = detail.giverName,
        giverTitle = detail.giverTitle,
        giverFactionID = detail.giverFactionID,
        giverFactionName = detail.giverFactionName,
        themeID = detail.themeID,
        budgetValue = detail.budgetValue,
        rewardTags = DO.DeepCopy(detail.rewardTags or {}),
        timeRemainingHours = detail.timeRemainingHours,
        timeLimitHours = detail.timeLimitHours,
        difficulty = detail.difficulty,
        difficultyLabel = detail.difficultyLabel,
        currentObjectiveLabel = detail.currentObjectiveLabel,
        chain = detail.chain,
        chainSummary = detail.chainSummary,
        detail = detail,
        sortTime = detail.status == "active" and (tonumber(quest.createdAt) or 0) or getQuestEndTimestamp(quest),
    }
end

function Quests.GetActiveQuests(player)
    local store = Runtime.getStore(player, false)
    if not store then
        return {}
    end

    local results = {}
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = quest
        end
    end

    return results
end

function Quests.GetTrackedQuest(player)
    local store = Runtime.getStore(player, false)
    if not store then
        return nil
    end

    return Runtime.resolveTrackedQuest(player, store)
end

function Quests.GetQuest(player, questID)
    local store = Runtime.getStore(player, false)
    return Runtime.findQuest(store, questID)
end

function Quests.GetEncounterStatus(player, quest)
    if not player or not quest or quest.status ~= "active" or not Runtime.questRequiresAreaClear(quest) then
        return nil
    end

    return Runtime.gatherLiveZoneState(player, quest, Runtime.getPendingObjective(quest))
end

function Quests.GetClearanceTargetData(player, quest)
    local zoneState = Quests.GetEncounterStatus(player, quest)
    if not zoneState or zoneState.areaClear == true or zoneState.encounterSpawned ~= true then
        return nil
    end

    local targets = zoneState.targetSamples or {}
    if #targets == 0 then
        return nil
    end

    return {
        questID = quest.id,
        questName = tostring(quest.name or quest.id),
        location = zoneState.location,
        clearRadius = zoneState.clearRadius,
        nearbyZombies = zoneState.nearbyZombies,
        playerPresent = zoneState.playerPresent,
        targetSamples = DO.DeepCopy(targets),
    }
end

function Quests.GetTrackedClearanceTargetData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    return Quests.GetClearanceTargetData(player, quest)
end

function Quests.GetLocatedClearanceTargetData(player)
    local quest = Quests.GetLocatedQuest and Quests.GetLocatedQuest(player) or nil
    if not quest or quest.status ~= "active" then
        return nil
    end

    return Quests.GetClearanceTargetData(player, quest)
end

function Quests.GetQuestMarkerData(player, quest)
    if not quest or quest.status ~= "active" then
        return nil
    end

    local location = getQuestMarkerLocation(quest)
    if not location then
        return nil
    end

    local chainData = getQuestChainData(quest)
    local description = tostring(location.label or quest.name or "Objective")
    if chainData then
        description = string.format("%s (%s)", description, chainData.summary)
    end

    return {
        questID = quest.id,
        name = quest.title or quest.name,
        description = description,
        x = location.x,
        y = location.y,
        z = location.z,
        symbolID = location.symbolID or "DOQuestTarget",
        worldIcon = location.worldIcon or "loot.png",
        r = location.r,
        g = location.g,
        b = location.b,
        a = location.a,
        scale = location.scale,
    }
end

function Quests.GetTrackedMarkerData(player)
    return Quests.GetQuestMarkerData(player, Quests.GetTrackedQuest(player))
end

function Quests.GetLocatedMarkerData(player)
    return Quests.GetQuestMarkerData(player, Quests.GetLocatedQuest and Quests.GetLocatedQuest(player) or nil)
end

function Quests.BuildSummaryText(quest, player)
    return buildMissionSummary(quest, player).display
end

function Quests.GetActiveQuestSummary(player)
    local results = {}
    local store = Runtime.getStore(player, false)
    if not store then
        return results
    end

    Runtime.resolveTrackedQuest(player, store)
    Runtime.resolveLocatedQuest(player, store)

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            results[#results + 1] = buildMissionSummary(quest, player)
        end
    end

    table.sort(results, function(left, right)
        if left.tracked ~= right.tracked then
            return left.tracked == true
        end
        if left.located ~= right.located then
            return left.located == true
        end
        return (tonumber(left.sortTime) or 0) > (tonumber(right.sortTime) or 0)
    end)

    return results
end

function Quests.GetCompletedQuestSummary(player)
    local results = {}
    local store = Runtime.getStore(player, false)
    if not store then
        return results
    end

    Runtime.resolveTrackedQuest(player, store)
    Runtime.resolveLocatedQuest(player, store)

    for _, quest in ipairs(store.quests or {}) do
        if quest.status ~= "active" then
            results[#results + 1] = buildMissionSummary(quest, player)
        end
    end

    table.sort(results, function(left, right)
        return (tonumber(left.sortTime) or 0) > (tonumber(right.sortTime) or 0)
    end)

    return results
end

function Quests.GetQuestDetailData(player, questID)
    return buildQuestDetailData(player, Quests.GetQuest(player, questID))
end

function Quests.GetTrackedObjectiveUIData(player)
    local quest = Quests.GetTrackedQuest(player)
    if not quest or quest.status ~= "active" then
        return nil
    end

    return buildQuestDetailData(player, quest)
end

function Quests.GetLatestCompletedQuest(player)
    local store = Runtime.getStore(player, false)
    if not store then
        return nil
    end

    local latest = nil
    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "completed" and tonumber(quest.completedAt) then
            if not latest or tonumber(quest.completedAt) > tonumber(latest.completedAt or 0) then
                latest = quest
            end
        end
    end

    return latest
end

function Quests.GetLatestFailedQuest(player)
    local store = Runtime.getStore(player, false)
    if not store then
        return nil
    end

    local latest = nil
    for _, quest in ipairs(store.quests or {}) do
        local failedAt = tonumber(quest.failedAt or quest.abandonedAt)
        if (quest.status == "failed" or quest.status == "abandoned") and failedAt then
            if not latest or failedAt > tonumber(latest.failedAt or latest.abandonedAt or 0) then
                latest = quest
            end
        end
    end

    return latest
end
