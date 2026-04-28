DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local CLAIM_REWARDS_OBJECTIVE_ID = "claim_rewards"

local function hasClaimableRewards(quest)
    if type(quest) ~= "table" or type(quest.rewards) ~= "table" then
        return false
    end

    for _, reward in ipairs(quest.rewards) do
        if type(reward) == "table" then
            local kind = tostring(reward.kind or reward.type or ""):lower()
            if kind == "item" or kind == "money" or kind == "reputation" then
                return true
            end
        end
    end
    return false
end

local function getRewardClaimObjective(quest)
    for _, objective in ipairs(quest and quest.objectives or {}) do
        if objective.type == "claimRewards" or objective.id == CLAIM_REWARDS_OBJECTIVE_ID then
            return objective
        end
    end
    return nil
end

local function isAwaitingRewardClaim(quest)
    local objective = getRewardClaimObjective(quest)
    return objective ~= nil and objective.completed ~= true
end

local function getRosterData()
    if DT_V2_RadarManager and type(DT_V2_RadarManager.ClientRoster) == "table" then
        return DT_V2_RadarManager.ClientRoster
    end
    return ModData and ModData.get and ModData.get("DynamicTrading_Roster") or nil
end

local function getSoul(uuid)
    if not uuid or tostring(uuid) == "" then
        return nil
    end

    if DynamicTrading_Roster and DynamicTrading_Roster.GetSoul then
        local soul = DynamicTrading_Roster.GetSoul(tostring(uuid))
        if soul then
            return soul
        end
    end

    local roster = getRosterData()
    return roster and roster.Souls and roster.Souls[tostring(uuid)] or nil
end

local function isSoulAlive(soul)
    if type(soul) ~= "table" then
        return false
    end

    local status = tostring(soul.status or "")
    local state = tostring(soul.state or "")
    return status ~= "Dead" and state ~= "Dead" and soul.dead ~= true and soul.isDead ~= true
end

local function isLiveNPCDead(uuid)
    local id = uuid and tostring(uuid) or ""
    if id == "" then
        return false
    end

    local zombie = DTNPCClient and DTNPCClient.FindZombieByUUID and DTNPCClient.FindZombieByUUID(id) or nil
    if zombie and zombie.isDead and zombie:isDead() then
        return true
    end

    local npcData = nil
    if zombie and DTNPC and DTNPC.GetData then
        npcData = DTNPC.GetData(zombie)
    end
    npcData = npcData or (DTNPCClient and DTNPCClient.NPCCache and DTNPCClient.NPCCache[id] and DTNPCClient.NPCCache[id].npcData) or nil
    npcData = npcData or (DTNPCClient and DTNPCClient.MetadataCache and DTNPCClient.MetadataCache[id]) or nil
    return npcData and tostring(npcData.status or "") == "Dead" or false
end

local function buildRewardContactLocation(raw, fallbackLabel)
    if type(raw) ~= "table" then
        return nil
    end

    local location = Runtime.normalizeLocation({
        x = raw.x,
        y = raw.y,
        z = raw.z,
        label = raw.label or raw.name or fallbackLabel or "Reward Contact",
        radius = raw.radius or 8,
        symbolID = raw.symbolID or "DOQuestTurnIn",
        worldIcon = raw.worldIcon or "friend.png",
        r = raw.r or 0.25,
        g = raw.g or 0.85,
        b = raw.b or 1.0,
        a = raw.a or 1.0,
        scale = raw.scale or 1.0,
    })
    return location
end

local function getSoulLocation(soul, fallbackLabel)
    if type(soul) ~= "table" then
        return nil
    end

    local name = tostring(soul.name or fallbackLabel or "Reward Contact")
    if Runtime.resolveQuestContactLocationForSoul then
        return Runtime.resolveQuestContactLocationForSoul(soul, name, {
            preferHome = true,
            homeLabel = tostring((type(soul.homeCoords) == "table" and soul.homeCoords.name) or (name .. "'s Base")),
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

    return buildRewardContactLocation({
        x = soul.lastX or soul.x,
        y = soul.lastY or soul.y,
        z = soul.lastZ or soul.z,
        label = name,
    }, name) or buildRewardContactLocation(soul.homeCoords, name .. "'s Camp")
end

local function getQuestFactionID(quest)
    local source = quest and quest.sourceTrader or nil
    local context = quest and quest.rewardContext or nil
    local value = quest and (quest.giverFactionID or quest.factionID)
        or nil
    value = value or (source and (source.factionID or source.factionId))
    value = value or (context and (context.factionID or context.factionId))
    value = value and tostring(value) or ""
    return value ~= "" and value or nil
end

local function getQuestOriginalTraderID(quest)
    local source = quest and quest.sourceTrader or nil
    local value = source and (source.traderID or source.id or source.uuid) or nil
    value = value and tostring(value) or ""
    return value ~= "" and value or nil
end

local function buildContact(uuid, soul, delegated)
    if not isSoulAlive(soul) or isLiveNPCDead(uuid or soul.uuid) then
        return nil
    end

    local name = tostring(soul.name or "Reward Contact")
    local location = getSoulLocation(soul, name)
    if not location then
        return nil
    end

    return {
        uuid = tostring(uuid or soul.uuid or ""),
        name = name,
        factionID = soul.factionID and tostring(soul.factionID) or nil,
        location = location,
        delegated = delegated == true,
    }
end

local function findFactionRewardDelegate(quest, skipTraderID)
    local factionID = getQuestFactionID(quest)
    if not factionID then
        return nil
    end

    local roster = getRosterData()
    local souls = roster and roster.Souls or nil
    if type(souls) ~= "table" then
        return nil
    end

    local members = roster.FactionMembers and roster.FactionMembers[factionID] or nil
    if type(members) == "table" then
        for _, uuid in ipairs(members) do
            local id = tostring(uuid or "")
            if id ~= "" and id ~= tostring(skipTraderID or "") then
                local contact = buildContact(id, getSoul(id) or souls[id], true)
                if contact then
                    return contact
                end
            end
        end
    end

    for uuid, soul in pairs(souls) do
        local id = tostring(uuid or "")
        if id ~= "" and id ~= tostring(skipTraderID or "") and tostring(soul.factionID or "") == factionID then
            local contact = buildContact(id, getSoul(id) or soul, true)
            if contact then
                return contact
            end
        end
    end

    return nil
end

local function resolveRewardContact(quest, currentContactID)
    local originalID = getQuestOriginalTraderID(quest)
    local currentID = currentContactID and tostring(currentContactID) or ""

    if currentID ~= "" then
        local current = buildContact(currentID, getSoul(currentID), currentID ~= tostring(originalID or ""))
        if current then
            return current
        end
    end

    if originalID then
        local original = buildContact(originalID, getSoul(originalID), false)
        if original then
            return original
        end

        local delegate = findFactionRewardDelegate(quest, originalID)
        if delegate then
            return delegate
        end

        local roster = getRosterData()
        local source = quest and quest.sourceTrader or nil
        local fallbackName = tostring(source and (source.displayName or source.name) or "Reward Contact")
        local fallbackLocation = buildRewardContactLocation(
            source and (source.pickupLocation or source.location or source.targetLocation),
            fallbackName
        )
        if fallbackLocation and (not getQuestFactionID(quest) or not (roster and type(roster.Souls) == "table")) then
            return {
                uuid = originalID,
                name = fallbackName,
                factionID = getQuestFactionID(quest),
                location = fallbackLocation,
                delegated = false,
            }
        end
        return nil
    end

    local source = quest and quest.sourceTrader or nil
    local fallbackName = tostring(source and (source.displayName or source.name) or "Reward Contact")
    local fallbackLocation = buildRewardContactLocation(
        source and (source.pickupLocation or source.location or source.targetLocation),
        fallbackName
    )
    if fallbackLocation then
        return {
            uuid = "",
            name = fallbackName,
            factionID = getQuestFactionID(quest),
            location = fallbackLocation,
            delegated = false,
        }
    end

    return findFactionRewardDelegate(quest, nil)
end

local function ensureRewardClaimObjective(player, quest)
    if not hasClaimableRewards(quest) then
        return true, false
    end

    local objective = getRewardClaimObjective(quest)
    if objective and objective.completed == true then
        return true, false
    end

    local contact = resolveRewardContact(quest, objective and objective.rewardContactID or nil)
    if not contact then
        return false, false
    end

    local label = "Claim rewards from " .. tostring(contact.name)
    if contact.delegated == true then
        label = "Claim delegated rewards from " .. tostring(contact.name)
    end

    if objective then
        local previousLocation = objective.targetLocation
        local changed = objective.label ~= label
            or tostring(objective.rewardContactID or "") ~= tostring(contact.uuid or "")
            or tostring(objective.rewardContactName or "") ~= tostring(contact.name or "")
            or objective.rewardDelegated ~= (contact.delegated == true)
            or not previousLocation
            or tonumber(previousLocation.x) ~= tonumber(contact.location and contact.location.x)
            or tonumber(previousLocation.y) ~= tonumber(contact.location and contact.location.y)
            or tonumber(previousLocation.z or 0) ~= tonumber(contact.location and contact.location.z or 0)
        objective.label = label
        objective.rewardContactID = contact.uuid
        objective.rewardContactName = contact.name
        objective.rewardDelegated = contact.delegated == true
        objective.targetLocation = contact.location
        objective.radius = contact.location and contact.location.radius or objective.radius
        quest.skipAreaClear = true
        return true, changed
    end

    quest.objectives = type(quest.objectives) == "table" and quest.objectives or {}
    quest.objectives[#quest.objectives + 1] = Runtime.normalizeObjective(#quest.objectives + 1, quest, {
        id = CLAIM_REWARDS_OBJECTIVE_ID,
        type = "claimRewards",
        label = label,
        required = 1,
        progress = 0,
        targetLocation = contact.location,
        radius = contact.location and contact.location.radius or 8,
        rewardContactID = contact.uuid,
        rewardContactName = contact.name,
        rewardDelegated = contact.delegated == true,
    })
    quest.rewardsPendingClaim = true
    quest.skipAreaClear = true

    if Runtime.say then
        Runtime.say(player, "Return to " .. tostring(contact.name) .. " to claim your reward.")
    end
    return true, true
end

local function completeQuestOrRequestRewardClaim(player, quest, reason)
    local claimObjective = getRewardClaimObjective(quest)
    if hasClaimableRewards(quest) and not (claimObjective and claimObjective.completed == true) then
        local ok, changed = ensureRewardClaimObjective(player, quest)
        if not ok then
            Quests.FailQuest(player, quest.id, "reward_contact_unavailable")
            return true
        end
        if changed then
            Runtime.onQuestStateChanged(player)
        end
        return true
    end

    quest.rewardsPendingClaim = false
    Quests.CompleteQuest(player, quest.id, reason or "completed")
    return true
end

local function shouldCompleteQuest(player, quest)
    if not Runtime.objectivesComplete(quest) then
        return false
    end

    if not Runtime.questRequiresAreaClear(quest) then
        return true
    end

    local zoneState = Quests.GetEncounterStatus(player, quest)
    return zoneState and zoneState.areaClear == true
end

local function getObjectiveDropSpawnedCount(objective)
    local dropState = objective and objective.dropState or nil
    return math.max(
        0,
        math.floor(tonumber(dropState and dropState.spawnedCount) or ((dropState and dropState.spawned == true) and 1 or 0))
    )
end

local function getNextDropSpawnThreshold(objective)
    if not objective then
        return math.huge
    end

    local required = math.max(1, math.floor(tonumber(objective.required) or 1))
    local spawnedCount = getObjectiveDropSpawnedCount(objective)
    if spawnedCount >= required then
        return math.huge
    end

    local spawnEvery = math.max(1, math.floor(tonumber(objective.spawnAfterKills) or 1))
    return spawnEvery * (spawnedCount + 1)
end

local function completeEncounterObjectives(quest)
    if not quest then
        return false
    end

    local changed = false
    for _, objective in ipairs(quest.objectives or {}) do
        if objective.completed ~= true and (objective.type == "kill" or objective.type == "areaClear") and objective.encounterOnly ~= false then
            changed = Runtime.markObjectiveCompleted(objective) or changed
        end
    end

    return changed
end

local function syncEncounterKillObjectiveFromZoneState(quest, objective, zoneState)
    if not quest or not objective or objective.type ~= "kill" or objective.encounterOnly ~= true then
        return false
    end

    if not zoneState or zoneState.encounterSpawned ~= true or zoneState.playerPresent ~= true then
        return false
    end

    if Runtime.questRequiresAreaClear and Runtime.questRequiresAreaClear(quest) ~= true then
        return false
    end

    local totalZombies = math.max(
        1,
        math.floor(
            tonumber(zoneState.totalZombies)
                or tonumber(objective.required)
                or 1
        )
    )
    local clearedZombies = math.max(0, math.floor(tonumber(zoneState.clearedZombies) or 0))
    local progress = math.min(totalZombies, clearedZombies)
    local completed = zoneState.areaClear == true or progress >= totalZombies
    local changed = false

    if tonumber(objective.required) ~= totalZombies then
        objective.required = totalZombies
        changed = true
    end

    if tonumber(objective.progress) ~= progress then
        objective.progress = progress
        changed = true
    end

    if objective.completed ~= completed then
        objective.completed = completed
        changed = true
    end

    return changed
end

function Quests.OnZombieKilled(player, zombie)
    local store = Runtime.getStore(player, true)
    if not store or not zombie then
        return false
    end

    local changed = false

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            local completionState = Runtime.captureObjectiveCompletionState and Runtime.captureObjectiveCompletionState(quest) or {}
            local queuedObjectiveEvents = false
            local questChanged = false
            local function flushObjectiveEvents()
                if queuedObjectiveEvents ~= true and Runtime.queueObjectiveProgressEvents then
                    Runtime.queueObjectiveProgressEvents(player, quest, completionState, "zombie_killed")
                    queuedObjectiveEvents = true
                end
            end

            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true and (objective.type == "kill" or objective.type == "obtainDrop") then
                    local location = Runtime.questLocationFor(quest, objective)
                    if Runtime.doesZombieMatchEncounter(player, quest, zombie, objective)
                        and Runtime.isWithinLocation(location, zombie:getX(), zombie:getY(), zombie:getZ())
                    then
                        if objective.type == "kill" then
                            local newProgress = math.min(objective.required, (tonumber(objective.progress) or 0) + 1)
                            if newProgress ~= objective.progress then
                                objective.progress = newProgress
                                objective.completed = objective.progress >= objective.required
                                questChanged = true
                            end
                        elseif objective.type == "obtainDrop" then
                            objective.killProgress = math.max(0, math.floor(tonumber(objective.killProgress) or 0)) + 1
                            questChanged = true

                            local nextSpawnThreshold = getNextDropSpawnThreshold(objective)
                            local prerequisiteReady = objective.killProgress >= nextSpawnThreshold
                            if prerequisiteReady and DO.Loot and DO.Loot.SpawnQuestCorpseDrop then
                                if DO.Loot.SpawnQuestCorpseDrop(zombie, player, quest, objective) then
                                    questChanged = true
                                end
                            end
                        end
                    end
                end
            end

            if shouldCompleteQuest(player, quest) then
                flushObjectiveEvents()
                return completeQuestOrRequestRewardClaim(player, quest, "kill_objectives")
            end

            if questChanged then
                flushObjectiveEvents()
                changed = true
            end
        end
    end

    if changed then
        Runtime.onQuestStateChanged(player)
    end

    return changed
end

function Quests.OnPlayerQuestUpdate(player)
    if not player then
        return
    end

    Runtime.questUpdateTick = (tonumber(Runtime.questUpdateTick) or 0) + 1
    if (tonumber(Runtime.questUpdateTick) or 0) < 20 then
        return
    end
    Runtime.questUpdateTick = 0

    local store = Runtime.getStore(player, false)
    if not store then
        return
    end

    local changed = false
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" then
            local completionState = Runtime.captureObjectiveCompletionState and Runtime.captureObjectiveCompletionState(quest) or {}
            local queuedObjectiveEvents = false
            local questChanged = false
            local function flushObjectiveEvents(source)
                if queuedObjectiveEvents ~= true and Runtime.queueObjectiveProgressEvents then
                    Runtime.queueObjectiveProgressEvents(player, quest, completionState, source or "player_update")
                    queuedObjectiveEvents = true
                end
            end
            local zoneState = nil
            local remainingHours = Runtime.getQuestRemainingHours(quest)
            if remainingHours ~= nil and remainingHours <= 0 then
                Quests.FailQuest(player, quest.id, "time_expired")
                return
            end

            local hook = Runtime.getObjectiveHookForQuest and Runtime.getObjectiveHookForQuest(quest) or nil
            if hook and hook.onQuestUpdate then
                local hookResult = hook.onQuestUpdate(player, quest, store)
                if type(hookResult) == "table" then
                    changed = hookResult.changed == true or changed
                    questChanged = hookResult.changed == true or questChanged
                    if hookResult.complete == true then
                        if not isAwaitingRewardClaim(quest) then
                            flushObjectiveEvents("hook_completed")
                            completeQuestOrRequestRewardClaim(player, quest, hookResult.reason or "hook_completed")
                            return
                        end
                    end
                    if hookResult.fail == true then
                        Quests.FailQuest(player, quest.id, hookResult.reason or "hook_failed")
                        return
                    end
                end
            end

            for _, objective in ipairs(quest.objectives or {}) do
                if objective.completed ~= true then
                    if quest.encounter and quest.encounter.spawned ~= true and Runtime.isEncounterActivationReady(player, quest) then
                        if Quests.RequestEncounterSpawn(player, quest) then
                            changed = true
                            questChanged = true
                        end
                    end

                    if objective.type == "kill" then
                        zoneState = zoneState or Quests.GetEncounterStatus(player, quest)
                        if syncEncounterKillObjectiveFromZoneState(quest, objective, zoneState) then
                            changed = true
                            questChanged = true
                        end
                    end

                    if objective.type == "obtainDrop" then
                        local count = Runtime.countObjectiveDropItems(player, quest.id, objective.id)
                        local requiredCount = math.max(1, tonumber(objective.required) or 1)
                        local targetProgress = math.min(requiredCount, math.max(0, tonumber(count) or 0))
                        if targetProgress ~= tonumber(objective.progress) then
                            objective.progress = targetProgress
                            changed = true
                            questChanged = true
                        end

                        if count >= requiredCount then
                            local objectiveCompleted = Runtime.markObjectiveCompleted(objective)
                            changed = objectiveCompleted or changed
                            questChanged = objectiveCompleted or questChanged
                            if objective.completeRemainingObjectives == true then
                                local completedAfter = Runtime.completeObjectivesAfter(quest, objective.id)
                                changed = completedAfter or changed
                                questChanged = completedAfter or questChanged
                            end
                            if objective.completeEncounterObjectivesOnComplete == true then
                                local encounterCompleted = completeEncounterObjectives(quest)
                                changed = encounterCompleted or changed
                                questChanged = encounterCompleted or questChanged
                            end
                            if objective.skipAreaClearOnComplete == true then
                                quest.skipAreaClear = true
                            end
                            if objective.completeQuestOnComplete == true then
                                quest.skipAreaClear = true
                                flushObjectiveEvents("objective_completed")
                                completeQuestOrRequestRewardClaim(player, quest, "objective_completed")
                                return
                            end
                            changed = true
                        else
                            zoneState = zoneState or Quests.GetEncounterStatus(player, quest)
                            if zoneState
                                and zoneState.areaClear == true
                                and DO.Loot
                                and DO.Loot.EnsureQuestCorpseDropInArea
                                and DO.Loot.EnsureQuestCorpseDropInArea(player, quest, objective, zoneState)
                            then
                                changed = true
                                questChanged = true
                            end
                        end
                    elseif objective.type == "areaClear" then
                        zoneState = zoneState or Quests.GetEncounterStatus(player, quest)
                        if zoneState and zoneState.areaClear == true then
                            local areaCompleted = Runtime.markObjectiveCompleted(objective)
                            changed = areaCompleted or changed
                            questChanged = areaCompleted or questChanged
                        end
                    elseif objective.type == "pickupItem" then
                        local location = Runtime.questLocationFor(quest, objective)
                        if Runtime.isWithinLocation(location, px, py, pz) then
                            if quest.grantItemType and Quests.RequestSpawnQuestItem then
                                Quests.RequestSpawnQuestItem(player, quest.grantItemType, tonumber(quest.grantItemDifficulty) or 1.0, quest.id)
                            end
                            objective.progress = objective.required
                            objective.completed = true
                            changed = true
                            questChanged = true
                        end
                    elseif objective.type == "deliverItem" then
                        local location = Runtime.questLocationFor(quest, objective)
                        if Runtime.isWithinLocation(location, px, py, pz) then
                            local items = Quests.FindItemsOnPlayer(player, function(item)
                                if not Quests.ValidateDelivery(item, quest.id) then
                                    return false
                                end
                                if objective.questItemType and item:getFullType() ~= objective.questItemType then
                                    return false
                                end
                                return true
                            end)

                            local requiredCount = math.max(1, math.floor(tonumber(objective.required) or 1))
                            local targetProgress = math.min(requiredCount, #items)
                            if targetProgress ~= tonumber(objective.progress) then
                                objective.progress = targetProgress
                                changed = true
                                questChanged = true
                            end

                            if #items >= requiredCount then
                                if objective.consumeOnComplete then
                                    for index = 1, requiredCount do
                                        Quests.RemoveInventoryItem(items[index])
                                    end
                                end
                                local delivered = Runtime.markObjectiveCompleted(objective)
                                changed = delivered or changed
                                questChanged = delivered or questChanged
                                if objective.skipAreaClearOnComplete == true then
                                    quest.skipAreaClear = true
                                end
                                changed = true
                                questChanged = true
                            end
                        end
                    elseif objective.type == "claimRewards" then
                        local ok, claimChanged = ensureRewardClaimObjective(player, quest)
                        if not ok then
                            Quests.FailQuest(player, quest.id, "reward_contact_unavailable")
                            return
                        end
                        changed = claimChanged or changed
                        questChanged = claimChanged or questChanged

                        local location = Runtime.questLocationFor(quest, objective)
                        if Runtime.isWithinLocation(location, px, py, pz) then
                            local rewardsClaimed = Runtime.markObjectiveCompleted(objective)
                            changed = rewardsClaimed or changed
                            questChanged = rewardsClaimed or questChanged
                            quest.rewardsPendingClaim = false
                        end
                    end
                end
            end

            if shouldCompleteQuest(player, quest) then
                flushObjectiveEvents("player_update")
                completeQuestOrRequestRewardClaim(player, quest, "player_update")
                return
            end

            if questChanged then
                flushObjectiveEvents("player_update")
            end
        end
    end

    if changed then
        Runtime.onQuestStateChanged(player)
    end
end

if not (isServer() and not isClient()) then
    Events.OnPlayerUpdate.Add(Quests.OnPlayerQuestUpdate)
end
