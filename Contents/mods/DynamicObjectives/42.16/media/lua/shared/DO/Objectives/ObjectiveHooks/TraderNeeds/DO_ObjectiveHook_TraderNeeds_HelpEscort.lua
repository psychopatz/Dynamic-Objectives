DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Quests = DynamicObjectives.Quests or {}

local DO = DynamicObjectives
local Quests = DO.Quests
Quests.Runtime = Quests.Runtime or {}
local Runtime = Quests.Runtime

local HOOK_ID = "TraderNeeds.HelpEscort"
local WORLD_KEY = "DynamicObjectives_HookWorld"
local INCIDENT_TTL_MS = 1000 * 60 * 60 * 24
local MAX_PLAYER_DISTANCE = 3000
local MIN_RESCUE_DISTANCE_FROM_HOME = 35
local RESCUE_RADIUS = 18
local HOME_RADIUS = 14
local ZOMBIE_ACTIVATION_RADIUS = 75
local EXTERIOR_ZOMBIE_GROUPS = 8
local EXTERIOR_ZOMBIES_PER_GROUP = 2
local ESCORT_NOISE_RADIUS = 90
local ESCORT_NOISE_VOLUME = 120
local ESCORT_NOISE_COOLDOWN_MS = 12000

local PREFERRED_HOUSE_ROOMS = {
    livingroom = true,
    bedroom = true,
    kitchen = true,
    bathroom = true,
}

local BLACKLISTED_RESCUE_ROOMS = {
    classroom = true,
    church = true,
    factory = true,
    garage = false,
    gunstore = true,
    hospitalroom = true,
    motelroom = false,
    office = true,
    policestorage = true,
    prisoncell = true,
    restaurant = true,
    shop = true,
    storageunit = true,
    warehouse = true,
}

local function hookLog(topic, message)
    DO.Log("ObjectiveHook", topic, message)
end

local function isAuthoritative()
    return isServer() or not isClient()
end

local function normalizeText(value)
    local text = tostring(value or "")
    if text == "" then
        return nil
    end
    return text
end

local function normalizeLower(value)
    local text = normalizeText(value)
    return text and string.lower(text) or nil
end

local function roundNumber(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function formatDistanceLabel(prefix, value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return string.format("%s %.0fm", tostring(prefix or "Distance"), number)
end

local function formatEscortRouteText(routeDistance, homeDistance)
    local left = formatDistanceLabel("Route", routeDistance)
    local right = formatDistanceLabel("Home", homeDistance)
    if left and right then
        return left .. " | " .. right
    end
    return left or right or ""
end

local function isAliveSoul(soul)
    return soul and tostring(soul.status or "") ~= "Dead"
end

local function buildCoords(raw, fallbackLabel, radius)
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
        label = tostring(raw.label or raw.name or fallbackLabel or "Objective Site"),
        town = raw.town,
        county = raw.county,
        radius = math.max(4, math.floor(tonumber(raw.radius) or tonumber(radius) or RESCUE_RADIUS)),
        symbolID = tostring(raw.symbolID or "DOQuestTarget"),
        worldIcon = tostring(raw.worldIcon or "friend.png"),
        r = tonumber(raw.r) or 0.95,
        g = tonumber(raw.g) or 0.76,
        b = tonumber(raw.b) or 0.22,
        a = tonumber(raw.a) or 1.0,
        scale = tonumber(raw.scale) or 1.0,
        building = type(raw.building) == "table" and DO.DeepCopy(raw.building) or nil,
    }
end

local function getWorldState(create)
    if not ModData then
        return nil
    end

    local data = nil
    if create and ModData.getOrCreate then
        data = ModData.getOrCreate(WORLD_KEY)
    elseif ModData.get then
        data = ModData.get(WORLD_KEY)
    end

    if not data and create and ModData.add then
        data = {}
        ModData.add(WORLD_KEY, data)
    end

    if data then
        data.version = tonumber(data.version) or 1
        data.incidents = type(data.incidents) == "table" and data.incidents or {}
        data.byTraderId = type(data.byTraderId) == "table" and data.byTraderId or {}
    end

    return data
end

local function transmitWorldState()
    if isAuthoritative() and ModData and ModData.transmit then
        ModData.transmit(WORLD_KEY)
    end
end

local function ensurePlayerHookStore(player, create)
    local store = Quests.GetStore and Quests.GetStore(player, create) or nil
    if not store then
        return nil, nil
    end

    store.hookState = type(store.hookState) == "table" and store.hookState or {}
    local hookStore = store.hookState[HOOK_ID]
    if not hookStore and create then
        hookStore = {
            incidents = {},
            recentTraderUsage = {},
        }
        store.hookState[HOOK_ID] = hookStore
    end

    if hookStore then
        hookStore.incidents = type(hookStore.incidents) == "table" and hookStore.incidents or {}
        hookStore.recentTraderUsage = type(hookStore.recentTraderUsage) == "table" and hookStore.recentTraderUsage or {}
    end

    return store, hookStore
end

local function getPlayerIncidentMap(player, create)
    local _, hookStore = ensurePlayerHookStore(player, create)
    return hookStore and hookStore.incidents or nil
end

local function getRecentTraderUsage(player, traderId)
    local _, hookStore = ensurePlayerHookStore(player, false)
    local usage = hookStore and hookStore.recentTraderUsage or nil
    return usage and traderId and tonumber(usage[tostring(traderId)]) or nil
end

local function markRecentTraderUsage(player, traderId)
    local _, hookStore = ensurePlayerHookStore(player, true)
    if not hookStore or not traderId then
        return
    end

    hookStore.recentTraderUsage[tostring(traderId)] = DO.NowMs and DO.NowMs() or 0
end

local function getSoul(uuid)
    if not uuid then
        return nil
    end

    if DynamicTrading_Roster and DynamicTrading_Roster.GetSoul then
        return DynamicTrading_Roster.GetSoul(uuid)
    end

    local roster = ModData and ModData.get and ModData.get("DynamicTrading_Roster") or nil
    return roster and roster.Souls and roster.Souls[uuid] or nil
end

local function saveSoul(uuid, soul)
    if not uuid or not soul then
        return false
    end

    if DynamicTrading_Roster and DynamicTrading_Roster.SaveSoul then
        DynamicTrading_Roster.SaveSoul(uuid, soul)
        return true
    end

    if not ModData or not ModData.getOrCreate then
        return false
    end

    local roster = ModData.getOrCreate("DynamicTrading_Roster")
    roster.Souls = type(roster.Souls) == "table" and roster.Souls or {}
    roster.Souls[uuid] = soul
    if ModData.transmit then
        ModData.transmit("DynamicTrading_Roster")
    end
    return true
end

local function getFactionName(factionID)
    if not factionID then
        return nil
    end

    local factions = ModData and ModData.get and ModData.get("DynamicTrading_Factions") or nil
    local faction = factions and factions[tostring(factionID)] or nil
    return faction and faction.name or tostring(factionID)
end

local function getPlayerUsername(player)
    return player and player.getUsername and player:getUsername() or nil
end

local function getPlayerOnlineID(player)
    local value = player and player.getOnlineID and player:getOnlineID() or nil
    return value ~= nil and tonumber(value) or nil
end

local function distanceSq(ax, ay, bx, by)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    return (dx * dx) + (dy * dy)
end

local function distanceBetween(ax, ay, bx, by)
    return math.sqrt(distanceSq(ax, ay, bx, by))
end

local function buildEscortDistanceMetrics(player, rescueSite, homeCoords)
    if not player or not rescueSite or not homeCoords then
        return nil
    end

    local px = player.getX and player:getX() or nil
    local py = player.getY and player:getY() or nil
    if px == nil or py == nil then
        return nil
    end

    local rescueDistance = distanceBetween(px, py, rescueSite.x, rescueSite.y)
    local homeDistance = distanceBetween(px, py, homeCoords.x, homeCoords.y)
    local routeDistance = rescueDistance + distanceBetween(rescueSite.x, rescueSite.y, homeCoords.x, homeCoords.y)

    return {
        rescueDistance = rescueDistance,
        homeDistance = homeDistance,
        routeDistance = routeDistance,
        withinPlayerRange = rescueDistance <= MAX_PLAYER_DISTANCE and homeDistance <= MAX_PLAYER_DISTANCE,
    }
end

local function computeEscortCashReward(routeDistance)
    local normalized = math.max(0, math.floor(tonumber(routeDistance) or 0))
    local scaled = 180 + (math.floor(normalized / 500) * 20)
    return math.max(180, math.min(300, scaled))
end

local function incidentMatchesPlayerRange(player, incident)
    if not player or type(incident) ~= "table" then
        return false
    end

    local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local homeCoords = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS)
    local metrics = buildEscortDistanceMetrics(player, rescueSite, homeCoords)
    return metrics and metrics.withinPlayerRange == true or false
end

local function isWithinRadius(location, x, y, z)
    if not location or x == nil or y == nil then
        return false
    end

    if z ~= nil and tonumber(location.z or 0) ~= tonumber(z or 0) then
        return false
    end

    return distanceSq(location.x, location.y, x, y) <= ((tonumber(location.radius) or RESCUE_RADIUS) ^ 2)
end

local function nextIncidentID(player, traderID)
    return string.format(
        "DOHI_%s_%s_%d_%d",
        tostring(DO.GetPlayerKey and DO.GetPlayerKey(player) or "player"):gsub("[^%w_:%-]", "_"),
        tostring(traderID or "trader"):gsub("[^%w_:%-]", "_"),
        math.floor(DO.NowMs() or 0),
        ZombRand(1000, 9999)
    )
end

local function getActiveHookQuest(player, incidentID, traderID)
    local store = Quests.GetStore and Quests.GetStore(player, false) or nil
    if not store then
        return nil
    end

    for _, quest in ipairs(store.quests or {}) do
        if quest.status == "active" and tostring(quest.hookId or "") == HOOK_ID then
            if not incidentID and not traderID then
                return quest
            end
            if incidentID and tostring(quest.hookIncidentId or "") == tostring(incidentID) then
                return quest
            end
            local hookState = type(quest.hookState) == "table" and quest.hookState or nil
            if traderID and hookState and tostring(hookState.traderId or "") == tostring(traderID) then
                return quest
            end
        end
    end

    return nil
end

local function removePlayerIncident(player, incidentID)
    local incidentMap = getPlayerIncidentMap(player, true)
    if incidentMap and incidentID then
        incidentMap[tostring(incidentID)] = nil
    end
end

local function clearPendingMirrorsExcept(player, keepIncidentID)
    local incidentMap = getPlayerIncidentMap(player, true)
    if not incidentMap then
        return
    end

    for incidentID, incident in pairs(incidentMap) do
        if tostring(incidentID) ~= tostring(keepIncidentID or "") and tostring(incident and incident.status or "") == "pending" then
            incidentMap[incidentID] = nil
        end
    end
end

local function copyIncidentForPlayer(incident)
    if type(incident) ~= "table" then
        return nil
    end

    return {
        incidentId = tostring(incident.incidentId or ""),
        hookId = HOOK_ID,
        traderId = incident.traderId and tostring(incident.traderId) or nil,
        traderName = incident.traderName and tostring(incident.traderName) or nil,
        factionId = incident.factionId and tostring(incident.factionId) or nil,
        factionName = incident.factionName and tostring(incident.factionName) or nil,
        homeCoords = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS),
        rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS),
        distressCoords = buildCoords(incident.distressCoords, incident.traderName and tostring(incident.traderName) or "Trader", 10),
        status = tostring(incident.status or "pending"),
        ownerPlayerKey = incident.ownerPlayerKey and tostring(incident.ownerPlayerKey) or nil,
        ownerUsername = incident.ownerUsername and tostring(incident.ownerUsername) or nil,
        questId = incident.questId and tostring(incident.questId) or nil,
        createdAt = tonumber(incident.createdAt) or 0,
        expiresAt = tonumber(incident.expiresAt) or 0,
        acceptedAt = tonumber(incident.acceptedAt) or nil,
        exteriorSpawned = incident.exteriorSpawned == true,
        rescueDistance = tonumber(incident.rescueDistance) or nil,
        homeDistance = tonumber(incident.homeDistance) or nil,
        routeDistance = tonumber(incident.routeDistance) or nil,
        cashReward = tonumber(incident.cashReward) or nil,
    }
end

local function mirrorIncidentToPlayer(player, incident)
    local incidentMap = getPlayerIncidentMap(player, true)
    if not incidentMap or not incident or not incident.incidentId then
        return nil
    end

    incidentMap[tostring(incident.incidentId)] = copyIncidentForPlayer(incident)
    return incidentMap[tostring(incident.incidentId)]
end

local function findPendingObjectiveSquare(bounds, requireRoom, preferredOnly)
    if not bounds or not getCell then
        return nil
    end

    local cell = getCell()
    if not cell then
        return nil
    end

    local minX = math.floor(tonumber(bounds.x) or 0)
    local minY = math.floor(tonumber(bounds.y) or 0)
    local maxX = minX + math.max(1, math.floor(tonumber(bounds.w) or 1)) - 1
    local maxY = minY + math.max(1, math.floor(tonumber(bounds.h) or 1)) - 1

    for z = 0, 2 do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                if square and not square:isSolid() and not square:isSolidTrans() then
                    local room = square:getRoom()
                    local roomName = normalizeLower(room and room:getName() or nil)
                    if (requireRoom ~= true or room ~= nil)
                        and (not preferredOnly or (roomName and PREFERRED_HOUSE_ROOMS[roomName] == true))
                    then
                        return square
                    end
                end
            end
        end
    end

    return nil
end

local function findRescueInteriorLocation(site)
    local bounds = site and site.building or nil
    local square = findPendingObjectiveSquare(bounds, true, true)
        or findPendingObjectiveSquare(bounds, true, false)
        or findPendingObjectiveSquare(bounds, false, false)

    if square then
        return square:getX(), square:getY(), square:getZ()
    end

    return site and site.x or nil, site and site.y or nil, site and site.z or 0
end

local function chooseExteriorSpawnPoint(site, index)
    local bounds = site and site.building or nil
    local centerX = math.floor(tonumber(site and site.x) or 0)
    local centerY = math.floor(tonumber(site and site.y) or 0)
    local z = math.floor(tonumber(site and site.z) or 0)

    if not bounds then
        local angle = ((index - 1) / EXTERIOR_ZOMBIE_GROUPS) * math.pi * 2
        local radius = 6 + (index % 3)
        return centerX + math.floor(math.cos(angle) * radius), centerY + math.floor(math.sin(angle) * radius), z
    end

    local minX = math.floor(tonumber(bounds.x) or centerX)
    local minY = math.floor(tonumber(bounds.y) or centerY)
    local width = math.max(2, math.floor(tonumber(bounds.w) or 2))
    local height = math.max(2, math.floor(tonumber(bounds.h) or 2))
    local maxX = minX + width - 1
    local maxY = minY + height - 1
    local offset = 3 + (index % 2)

    local points = {
        { x = minX - offset, y = minY - offset },
        { x = centerX, y = minY - offset },
        { x = maxX + offset, y = minY - offset },
        { x = maxX + offset, y = centerY },
        { x = maxX + offset, y = maxY + offset },
        { x = centerX, y = maxY + offset },
        { x = minX - offset, y = maxY + offset },
        { x = minX - offset, y = centerY },
    }

    local point = points[((index - 1) % #points) + 1]
    return point.x, point.y, z
end

local function despawnLiveTrader(uuid)
    if not isAuthoritative() or not DTNPCServerCore or not DTNPCServerCore.GetNPCDataByUUID then
        return
    end

    local zombie = DTNPCServerCore.GetNPCDataByUUID(uuid)
    if type(zombie) == "boolean" then
        return
    end

    local liveZombie = zombie
    if liveZombie then
        if DTNPCManager and DTNPCManager.RemoveData then
            DTNPCManager.RemoveData(uuid, nil, nil, nil, { reason = "objective_hook_reposition" })
        end
        liveZombie:removeFromWorld()
        liveZombie:removeFromSquare()
    end
end

local function restoreTraderIncidentFlags(npcData, incident)
    npcData.doObjectiveHookId = nil
    npcData.doObjectiveIncidentId = nil
    npcData.doObjectiveIncidentStatus = nil
    npcData.doObjectiveOwnerPlayerKey = nil
    npcData.doObjectiveOwnerUsername = nil
    npcData.doObjectiveSuppressTrade = nil
    npcData.doObjectiveDistress = nil
    npcData.doObjectiveEscortActive = nil
    npcData.doObjectiveEscortQuestId = nil
    npcData.doObjectiveRescueSite = nil
    npcData.doObjectiveDistressCoords = nil
    npcData.doObjectiveHomeCoords = nil
    npcData.doObjectiveFactionId = nil
    if incident and incident.status then
        npcData.doObjectiveLastResolution = tostring(incident.status)
    end
end

local function markTraderForIncident(npcData, incident, status)
    if not npcData or not incident then
        return
    end

    npcData.doObjectiveHookId = HOOK_ID
    npcData.doObjectiveIncidentId = tostring(incident.incidentId)
    npcData.doObjectiveIncidentStatus = tostring(status or incident.status or "pending")
    npcData.doObjectiveOwnerPlayerKey = incident.ownerPlayerKey and tostring(incident.ownerPlayerKey) or nil
    npcData.doObjectiveOwnerUsername = incident.ownerUsername and tostring(incident.ownerUsername) or nil
    npcData.doObjectiveSuppressTrade = true
    npcData.doObjectiveDistress = tostring(status or incident.status or "pending") == "pending"
    npcData.doObjectiveEscortActive = tostring(status or incident.status or "pending") == "accepted"
    npcData.doObjectiveEscortQuestId = incident.questId and tostring(incident.questId) or nil
    npcData.doObjectiveRescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    npcData.doObjectiveDistressCoords = buildCoords(incident.distressCoords, tostring(incident.traderName or "Trader"), 10)
    npcData.doObjectiveHomeCoords = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS)
    npcData.doObjectiveFactionId = incident.factionId and tostring(incident.factionId) or nil
end

local function buildDistressTargetCoords(incident, x, y, z)
    if not incident or x == nil or y == nil then
        return nil
    end

    local traderName = tostring(incident.traderName or "Trader")
    local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local homeCoords = buildCoords(incident.homeCoords, traderName .. "'s Base", HOME_RADIUS)

    return buildCoords({
        x = x,
        y = y,
        z = z or 0,
        label = traderName,
        town = rescueSite and rescueSite.town or (homeCoords and homeCoords.town) or nil,
        county = rescueSite and rescueSite.county or (homeCoords and homeCoords.county) or nil,
        radius = 10,
        symbolID = "DOQuestTarget",
        worldIcon = "friend.png",
        r = 0.95,
        g = 0.76,
        b = 0.22,
        a = 1.0,
        scale = 1.05,
    }, traderName, 10)
end

local isLiveTraderSpawned

local function applyDistressState(incident)
    if not incident or not isAuthoritative() then
        return false
    end

    local uuid = incident.traderId
    local soul = getSoul(uuid)
    if not isAliveSoul(soul) then
        return false
    end

    local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local spawnX, spawnY, spawnZ = findRescueInteriorLocation(rescueSite)
    if not spawnX or not spawnY then
        return false
    end

    incident.distressCoords = buildDistressTargetCoords(incident, spawnX, spawnY, spawnZ)
    soul.lastX = spawnX
    soul.lastY = spawnY
    soul.lastZ = spawnZ or 0
    soul.status = "Resting"
    soul.state = "Idle"
    soul.returnTime = 0
    soul.returnStatus = nil
    soul.master = nil
    soul.masterID = nil
    soul.combatOrder = nil
    soul.guardCombatOrder = nil
    soul.tasks = {}
    soul.requestedReturnStatus = nil
    soul.travelTarget = nil
    markTraderForIncident(soul, incident, "pending")
    saveSoul(uuid, soul)
    despawnLiveTrader(uuid)
    return true
end

local function ensurePendingTraderSpawned(player, incident)
    if not incident or tostring(incident.status or "") ~= "pending" or not isAuthoritative() then
        return false
    end

    local uuid = incident.traderId
    if not uuid then
        return false
    end

    local distressCoords = buildCoords(incident.distressCoords, tostring(incident.traderName or "Trader"), 10)
    if not distressCoords then
        if applyDistressState(incident) ~= true then
            return false
        end
        distressCoords = buildCoords(incident.distressCoords, tostring(incident.traderName or "Trader"), 10)
    end

    if player and distressCoords then
        local dist = distanceBetween(player:getX(), player:getY(), distressCoords.x, distressCoords.y)
        if dist > ZOMBIE_ACTIVATION_RADIUS then
            return false
        end
    end

    if isLiveTraderSpawned(uuid) then
        return true
    end

    local soul = getSoul(uuid)
    if not isAliveSoul(soul) then
        return false
    end

    if distressCoords then
        soul.lastX = distressCoords.x
        soul.lastY = distressCoords.y
        soul.lastZ = distressCoords.z or 0
    end
    soul.status = "Resting"
    soul.state = "Idle"
    soul.returnTime = 0
    soul.returnStatus = nil
    soul.master = nil
    soul.masterID = nil
    soul.combatOrder = nil
    soul.guardCombatOrder = nil
    soul.tasks = {}
    soul.requestedReturnStatus = nil
    soul.travelTarget = nil
    markTraderForIncident(soul, incident, "pending")
    saveSoul(uuid, soul)

    if DTNPCServerCore and DTNPCServerCore.RespawnNPC then
        local zombie = DTNPCServerCore.RespawnNPC(soul, uuid)
        return zombie ~= nil
    end

    return false
end

local function restoreTraderState(incident, resolution)
    if not incident or not isAuthoritative() then
        return false
    end

    local uuid = incident.traderId
    local soul = getSoul(uuid)
    if not soul then
        return false
    end

    incident.status = tostring(resolution or incident.status or "completed")
    restoreTraderIncidentFlags(soul, incident)
    soul.master = nil
    soul.masterID = nil
    soul.combatOrder = nil
    soul.guardCombatOrder = nil
    soul.tasks = {}
    soul.requestedReturnStatus = nil
    soul.travelTarget = nil
    soul.returnTime = 0
    soul.returnStatus = nil

    if tostring(soul.status or "") ~= "Dead" then
        local home = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS)
        if home then
            soul.lastX = home.x
            soul.lastY = home.y
            soul.lastZ = home.z or 0
        end
        soul.status = "Resting"
        soul.state = "Idle"
    end

    saveSoul(uuid, soul)
    despawnLiveTrader(uuid)
    incident.updatedAt = DO.NowMs()
    return true
end

local function trySpawnExteriorZombies(player, incident)
    if not incident or incident.exteriorSpawned == true or not isAuthoritative() then
        return false
    end

    local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    if not rescueSite then
        return false
    end

    if player then
        local dist = distanceBetween(player:getX(), player:getY(), rescueSite.x, rescueSite.y)
        if dist > ZOMBIE_ACTIVATION_RADIUS then
            return false
        end
    end

    if not addZombiesInOutfit then
        return false
    end

    local spawnedAny = false
    for index = 1, EXTERIOR_ZOMBIE_GROUPS do
        local spawnX, spawnY, spawnZ = chooseExteriorSpawnPoint(rescueSite, index)
        local zombieList = addZombiesInOutfit(
            spawnX,
            spawnY,
            spawnZ,
            EXTERIOR_ZOMBIES_PER_GROUP,
            "Naked",
            50,
            false,
            false,
            false,
            false,
            false,
            false,
            1
        )
        if zombieList and zombieList:size() > 0 then
            spawnedAny = true
        end
    end

    if spawnedAny then
        incident.exteriorSpawned = true
        incident.exteriorSpawnedAt = DO.NowMs()
    end

    return spawnedAny
end

isLiveTraderSpawned = function(uuid)
    if not isAuthoritative() then
        return false
    end

    if DTNPCServerCore and DTNPCServerCore.FindZombieByUUID then
        return DTNPCServerCore.FindZombieByUUID(uuid) ~= nil
    end

    return false
end

local function isResidentialBuilding(building)
    if not building then
        return false
    end

    local details = type(building.details) == "table" and building.details or {}
    local area = tonumber(building.area) or 0
    if area < 50 or area > 320 then
        return false
    end

    local primary = normalizeLower(details.primaryRoom or building.name)
    if primary and BLACKLISTED_RESCUE_ROOMS[primary] == true then
        return false
    end

    local hasHouseRoom = PREFERRED_HOUSE_ROOMS[primary] == true
    for _, roomName in ipairs(details.uniqueRooms or {}) do
        local normalized = normalizeLower(roomName)
        if normalized and PREFERRED_HOUSE_ROOMS[normalized] == true then
            hasHouseRoom = true
            break
        end
    end

    return hasHouseRoom
end

local function buildRescueSiteForBuilding(traderName, building, homeCoords)
    if not building then
        return nil
    end

    local bx = tonumber(building.cx) or tonumber(building.x)
    local by = tonumber(building.cy) or tonumber(building.y)
    if not bx or not by then
        return nil
    end

    return buildCoords({
        x = bx,
        y = by,
        z = 0,
        label = string.format("Reach %s's hideout", tostring(traderName or "the trader")),
        town = building.town or (DT_GeolocatorSystem and DT_GeolocatorSystem.GetTownName and DT_GeolocatorSystem.GetTownName(bx, by)) or nil,
        county = building.county or (DT_GeolocatorSystem and DT_GeolocatorSystem.GetCountyName and DT_GeolocatorSystem.GetCountyName(bx, by)) or nil,
        radius = RESCUE_RADIUS,
        symbolID = "DOQuestTarget",
        worldIcon = "friend.png",
        r = 0.95,
        g = 0.62,
        b = 0.18,
        scale = 1.05,
        building = {
            x = math.floor(tonumber(building.x) or bx),
            y = math.floor(tonumber(building.y) or by),
            w = math.max(1, math.floor(tonumber(building.w) or 1)),
            h = math.max(1, math.floor(tonumber(building.h) or 1)),
        },
    }, homeCoords and homeCoords.label or "Distress Signal", RESCUE_RADIUS)
end

local function pickRescueSiteForTrader(player, soul)
    local homeCoords = buildCoords(soul and soul.homeCoords, "Trader Base", HOME_RADIUS)
    if not homeCoords then
        return nil
    end

    local homeMetrics = buildEscortDistanceMetrics(player, homeCoords, homeCoords)
    if player and (not homeMetrics or homeMetrics.homeDistance > MAX_PLAYER_DISTANCE) then
        return nil
    end

    local geolocator = DT_GeolocatorSystem
    if not geolocator or not geolocator.GetBuildingsNearPoint then
        local fallbackSite = buildCoords({
            x = homeCoords.x + ZombRand(-50, 50),
            y = homeCoords.y + ZombRand(-50, 50),
            z = homeCoords.z,
            label = "Reach the distress house",
            town = homeCoords.town,
            county = homeCoords.county,
            radius = RESCUE_RADIUS,
        }, "Distress House", RESCUE_RADIUS)
        local fallbackMetrics = buildEscortDistanceMetrics(player, fallbackSite, homeCoords)
        if fallbackMetrics and fallbackMetrics.withinPlayerRange == true then
            return fallbackSite
        end
        return nil
    end

    if geolocator.LoadBuildings then
        geolocator.LoadBuildings()
    end

    local targetTown = homeCoords.town
        or (geolocator.GetTownName and geolocator.GetTownName(homeCoords.x, homeCoords.y))
        or nil
    local buildings = geolocator.GetBuildingsNearPoint(homeCoords.x, homeCoords.y, 260, targetTown)
    local fallback = geolocator.GetBuildingsNearPoint(homeCoords.x, homeCoords.y, 420, nil)
    local candidates = {}

    local function consider(list, preferTown)
        for _, building in ipairs(list or {}) do
            if isResidentialBuilding(building) then
                local bx = tonumber(building.cx) or tonumber(building.x)
                local by = tonumber(building.cy) or tonumber(building.y)
                if bx and by then
                    local distSqToHome = distanceSq(bx, by, homeCoords.x, homeCoords.y)
                    local distSqToPlayer = player and distanceSq(player:getX(), player:getY(), bx, by) or 0
                    if distSqToHome >= (MIN_RESCUE_DISTANCE_FROM_HOME * MIN_RESCUE_DISTANCE_FROM_HOME)
                        and (not player or distSqToPlayer <= (MAX_PLAYER_DISTANCE * MAX_PLAYER_DISTANCE))
                    then
                        candidates[#candidates + 1] = {
                            building = building,
                            preferTown = preferTown == true,
                            distSqToHome = distSqToHome,
                            distSqToPlayer = distSqToPlayer,
                        }
                    end
                end
            end
        end
    end

    consider(buildings, true)
    if #candidates == 0 then
        consider(fallback, false)
    end

    table.sort(candidates, function(left, right)
        if left.preferTown ~= right.preferTown then
            return left.preferTown == true
        end
        if left.distSqToPlayer ~= right.distSqToPlayer then
            return left.distSqToPlayer < right.distSqToPlayer
        end
        if left.distSqToHome ~= right.distSqToHome then
            return left.distSqToHome < right.distSqToHome
        end
        return tostring(left.building and left.building.name or "") < tostring(right.building and right.building.name or "")
    end)

    local selected = candidates[1] and candidates[1].building or nil
    if not selected then
        return nil
    end

    return buildRescueSiteForBuilding(soul and soul.name, selected, homeCoords)
end

local function incidentIsExpired(incident, nowMs)
    nowMs = tonumber(nowMs) or DO.NowMs()
    return incident and tonumber(incident.expiresAt) > 0 and tonumber(incident.expiresAt) <= nowMs
end

local function removeWorldIncident(worldState, incidentID)
    if not worldState or not incidentID then
        return
    end

    local incident = worldState.incidents[tostring(incidentID)]
    if incident and incident.traderId then
        worldState.byTraderId[tostring(incident.traderId)] = nil
    end
    worldState.incidents[tostring(incidentID)] = nil
end

local function cleanupWorldIncidents()
    if not isAuthoritative() then
        return
    end

    local worldState = getWorldState(true)
    if not worldState then
        return
    end

    local nowMs = DO.NowMs()
    local changed = false
    for incidentID, incident in pairs(worldState.incidents) do
        local status = tostring(incident.status or "pending")
        if status == "completed" or status == "failed" or status == "abandoned" then
            removeWorldIncident(worldState, incidentID)
            changed = true
        elseif status == "pending" and incidentIsExpired(incident, nowMs) then
            restoreTraderState(incident, "expired")
            removeWorldIncident(worldState, incidentID)
            changed = true
        end
    end

    if changed then
        transmitWorldState()
    end
end

local function buildEscortRefreshTarget()
    local minimum = Runtime.getConfiguredMinimumEscortIncidents and Runtime.getConfiguredMinimumEscortIncidents() or 0
    local chance = Runtime.getConfiguredEscortIncidentChancePercent and Runtime.getConfiguredEscortIncidentChancePercent() or 0
    local bonus = 0
    local passed = false
    local roll = nil

    if minimum < 3 then
        if Runtime.rollChancePercent then
            passed, roll = Runtime.rollChancePercent(chance)
        else
            roll = ZombRand(0, 100)
            passed = roll < chance
        end
        if passed then
            bonus = 1
        end
    end

    return math.min(3, minimum + bonus), minimum, chance, passed, roll
end

local function findEligibleTraders(worldState, player)
    local roster = ModData and ModData.get and ModData.get("DynamicTrading_Roster") or nil
    local souls = roster and roster.Souls or nil
    if not souls then
        return {}, {
            missingRoster = true,
            total = 0,
        }
    end

    local candidates = {}
    local summary = {
        total = 0,
        dead = 0,
        notTrading = 0,
        noHome = 0,
        outOfRange = 0,
        reserved = 0,
        hooked = 0,
        eligible = 0,
    }

    for uuid, soul in pairs(souls) do
        summary.total = summary.total + 1
        local homeCoords = buildCoords(soul and soul.homeCoords, "Trader Base", HOME_RADIUS)
        local homeMetrics = buildEscortDistanceMetrics(player, homeCoords, homeCoords)
        local status = tostring(soul and soul.status or "")
        local state = tostring(soul and soul.state or "")
        local isTrading = status == "Trading" or state == "Trading"
        if not isAliveSoul(soul) then
            summary.dead = summary.dead + 1
        elseif not isTrading or state == "Departure" then
            summary.notTrading = summary.notTrading + 1
        elseif homeCoords == nil or homeMetrics == nil then
            summary.noHome = summary.noHome + 1
        elseif homeMetrics.homeDistance > MAX_PLAYER_DISTANCE then
            summary.outOfRange = summary.outOfRange + 1
        elseif worldState.byTraderId[tostring(uuid)] then
            summary.reserved = summary.reserved + 1
        elseif tostring(soul.doObjectiveHookId or "") ~= "" then
            summary.hooked = summary.hooked + 1
        else
            candidates[#candidates + 1] = {
                traderId = tostring(uuid),
                soul = soul,
                homeDistance = tonumber(homeMetrics.homeDistance) or math.huge,
                recentUsedAt = getRecentTraderUsage(player, uuid) or 0,
            }
            summary.eligible = summary.eligible + 1
        end
    end

    table.sort(candidates, function(left, right)
        local leftRecent = tonumber(left and left.recentUsedAt) or 0
        local rightRecent = tonumber(right and right.recentUsedAt) or 0
        if leftRecent == rightRecent then
            local leftDistance = tonumber(left and left.homeDistance) or math.huge
            local rightDistance = tonumber(right and right.homeDistance) or math.huge
            if leftDistance == rightDistance then
                return tostring(left and left.traderId or "") < tostring(right and right.traderId or "")
            end
            return leftDistance < rightDistance
        end
        return leftRecent < rightRecent
    end)

    return candidates, summary
end

local function createIncidentForPlayer(player, excludedTraderIds)
    if not isAuthoritative() then
        return nil
    end

    local worldState = getWorldState(true)
    if not worldState then
        return nil
    end

    local candidates, summary = findEligibleTraders(worldState, player)
    if not candidates or #candidates == 0 then
        hookLog(
            "Create",
            "No eligible escort trader found total=" .. tostring(summary and summary.total or 0)
                .. " dead=" .. tostring(summary and summary.dead or 0)
                .. " notTrading=" .. tostring(summary and summary.notTrading or 0)
                .. " noHome=" .. tostring(summary and summary.noHome or 0)
                .. " outOfRange=" .. tostring(summary and summary.outOfRange or 0)
                .. " reserved=" .. tostring(summary and summary.reserved or 0)
                .. " hooked=" .. tostring(summary and summary.hooked or 0)
        )
        return nil
    end

    for _, candidate in ipairs(candidates) do
        local soul = candidate and candidate.soul or nil
        if excludedTraderIds and excludedTraderIds[tostring(candidate.traderId)] == true then
            hookLog("Create", "Skipping trader " .. tostring(candidate.traderId) .. ": already selected for this refresh")
        else
        local rescueSite = pickRescueSiteForTrader(player, soul)
        local homeCoords = buildCoords(soul and soul.homeCoords, tostring(soul and soul.name or "Trader") .. "'s Base", HOME_RADIUS)
        local metrics = buildEscortDistanceMetrics(player, rescueSite, homeCoords)
            if not rescueSite then
                hookLog("Create", "Skipping trader " .. tostring(candidate.traderId) .. ": no valid rescue site")
            elseif not homeCoords then
                hookLog("Create", "Skipping trader " .. tostring(candidate.traderId) .. ": missing home coordinates")
            elseif not metrics or metrics.withinPlayerRange ~= true then
                hookLog(
                    "Create",
                    "Skipping trader " .. tostring(candidate.traderId)
                        .. ": route out of range rescueDistance=" .. tostring(metrics and math.floor((metrics.rescueDistance or 0) + 0.5) or "nil")
                        .. " homeDistance=" .. tostring(metrics and math.floor((metrics.homeDistance or 0) + 0.5) or "nil")
                )
            else
                local cashReward = computeEscortCashReward(metrics.routeDistance)

                local incident = {
                    incidentId = nextIncidentID(player, candidate.traderId),
                    hookId = HOOK_ID,
                    traderId = candidate.traderId,
                    traderName = tostring(soul.name or "Trader"),
                    archetype = soul.archetype or soul.archetypeID or soul.jobType or nil,
                    factionId = soul.factionID and tostring(soul.factionID) or nil,
                    factionName = getFactionName(soul.factionID),
                    homeCoords = homeCoords,
                    rescueSite = rescueSite,
                    status = "pending",
                    ownerPlayerKey = nil,
                    ownerUsername = nil,
                    questId = nil,
                    createdAt = DO.NowMs(),
                    expiresAt = DO.NowMs() + INCIDENT_TTL_MS,
                    exteriorSpawned = false,
                    rescueDistance = math.floor(metrics.rescueDistance + 0.5),
                    homeDistance = math.floor(metrics.homeDistance + 0.5),
                    routeDistance = math.floor(metrics.routeDistance + 0.5),
                    cashReward = cashReward,
                }

                worldState.incidents[incident.incidentId] = incident
                worldState.byTraderId[candidate.traderId] = incident.incidentId

                applyDistressState(incident)
                markRecentTraderUsage(player, candidate.traderId)
                transmitWorldState()
                hookLog(
                    "Create",
                    "Created escort incident for trader " .. tostring(incident.traderName)
                        .. " traderId=" .. tostring(incident.traderId)
                        .. " rescueDistance=" .. tostring(incident.rescueDistance)
                        .. " homeDistance=" .. tostring(incident.homeDistance)
                        .. " reward=" .. tostring(incident.cashReward)
                        .. " recentUsedAt=" .. tostring(candidate.recentUsedAt or 0)
                )
                return incident
            end
        end
    end

    hookLog("Create", "Escort incident refresh could not find a valid rescue site from " .. tostring(#candidates) .. " eligible traders")
    return nil
end

local function collectPendingIncidentsForPlayer(player)
    local worldState = getWorldState(false)
    if not worldState then
        return {}
    end

    local results = {}
    local px = player and player:getX() or nil
    local py = player and player:getY() or nil

    for _, incident in pairs(worldState.incidents) do
        if tostring(incident.status or "") == "pending"
            and not incidentIsExpired(incident)
            and incidentMatchesPlayerRange(player, incident)
        then
            local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
            results[#results + 1] = {
                incident = incident,
                score = rescueSite and px and py and distanceSq(px, py, rescueSite.x, rescueSite.y) or math.huge,
            }
        end
    end

    table.sort(results, function(left, right)
        if tonumber(left and left.score) == tonumber(right and right.score) then
            return tostring(left and left.incident and left.incident.incidentId or "") < tostring(right and right.incident and right.incident.incidentId or "")
        end
        return (tonumber(left and left.score) or math.huge) < (tonumber(right and right.score) or math.huge)
    end)

    local incidents = {}
    for _, entry in ipairs(results) do
        incidents[#incidents + 1] = entry.incident
    end
    return incidents
end

local function buildEscortRewards(incident)
    local moneyAmount = tonumber(incident and incident.cashReward) or computeEscortCashReward(incident and incident.routeDistance)
    local rewards = {
        { kind = "money", amount = math.max(180, math.min(300, math.floor(moneyAmount))) },
    }
    if incident and incident.factionId then
        rewards[#rewards + 1] = {
            kind = "reputation",
            amount = 6,
            factionID = tostring(incident.factionId),
            factionName = incident.factionName,
        }
    end
    return rewards
end

local function buildBaseQuestSpecForIncident(incident)
    local traderName = tostring(incident and incident.traderName or "Trader")
    local homeCoords = buildCoords(incident and incident.homeCoords, traderName .. "'s Base", HOME_RADIUS)
    local rescueSite = buildCoords(incident and incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    if not homeCoords or not rescueSite then
        return nil
    end

    local baseTimeLimitHours = 18

    return {
        id = tostring(incident.questId or ""),
        hookId = HOOK_ID,
        hookIncidentId = tostring(incident.incidentId),
        hookState = {
            traderId = tostring(incident.traderId),
            traderName = traderName,
            traderTitle = incident.archetype and tostring(incident.archetype) or nil,
            factionId = incident.factionId and tostring(incident.factionId) or nil,
            factionName = incident.factionName,
            rescueSite = rescueSite,
            homeCoords = homeCoords,
            rescueDistance = tonumber(incident.rescueDistance) or nil,
            homeDistance = tonumber(incident.homeDistance) or nil,
            routeDistance = tonumber(incident.routeDistance) or nil,
            routeBaselineDistance = math.floor(distanceBetween(rescueSite.x, rescueSite.y, homeCoords.x, homeCoords.y) + 0.5),
        },
        name = string.format("Escort %s Home", traderName),
        targetLocation = homeCoords,
        rewardContext = {
            factionID = incident.factionId and tostring(incident.factionId) or nil,
            factionName = incident.factionName,
        },
        rewards = buildEscortRewards(incident),
        baseTimeLimitHours = baseTimeLimitHours,
        timeLimitHours = DO.Quests and DO.Quests.Runtime and DO.Quests.Runtime.scaleQuestTimeLimit
            and DO.Quests.Runtime.scaleQuestTimeLimit(baseTimeLimitHours)
            or baseTimeLimitHours,
        expirationScaled = true,
        sourceTrader = {
            traderID = incident.traderId and tostring(incident.traderId) or nil,
            displayName = traderName,
            factionID = incident.factionId and tostring(incident.factionId) or nil,
            factionName = incident.factionName,
            archetype = incident.archetype and tostring(incident.archetype) or nil,
            currentState = incident.status and tostring(incident.status) or nil,
        },
        objectives = {
            {
                id = "escort_trader_home",
                type = "escortTarget",
                label = "Guide the trader back to base",
                required = 1,
                progress = 0,
                targetLocation = homeCoords,
            },
        },
    }
end

local function buildQuestSpecForIncident(player, incident)
    local baseSpec = buildBaseQuestSpecForIncident(incident)
    if not baseSpec then
        return nil
    end

    if DO.Rewards and DO.Rewards.NormalizeRewards then
        DO.Rewards.NormalizeRewards(baseSpec, baseSpec.rewards)
    end

    local store = player and Quests.GetStore and Quests.GetStore(player, true) or nil
    local proceduralSpec = Runtime.buildProceduralEscortSpec and Runtime.buildProceduralEscortSpec(player, store, incident, function()
        return buildBaseQuestSpecForIncident(incident)
    end) or nil
    if proceduralSpec then
        if DO.Rewards and DO.Rewards.NormalizeRewards then
            DO.Rewards.NormalizeRewards(proceduralSpec, proceduralSpec.rewards)
        end
        return proceduralSpec
    end

    return baseSpec
end

local function syncIncidentMirrorForPlayer(player, incident)
    local mirrored = mirrorIncidentToPlayer(player, incident)
    if player and player.transmitModData then
        player:transmitModData()
    end
    return mirrored
end

local function activateEscortForPlayer(player, incident)
    local uuid = incident and incident.traderId or nil
    local soul = getSoul(uuid)
    if not isAliveSoul(soul) then
        return false
    end

    local playerKey = DO.GetPlayerKey and DO.GetPlayerKey(player) or nil
    local username = getPlayerUsername(player)
    local onlineID = getPlayerOnlineID(player)
    soul.status = "Working"
    soul.state = "Follow"
    soul.returnTime = 0
    soul.returnStatus = nil
    soul.master = username
    soul.masterID = onlineID
    soul.requestedReturnStatus = nil
    soul.tasks = {}
    soul.combatOrder = nil
    soul.guardCombatOrder = nil
    soul.guardAttackMode = nil
    markTraderForIncident(soul, incident, "accepted")
    saveSoul(uuid, soul)

    if DTNPCServerCore and DTNPCServerCore.UpdateNPCByUUID then
        DTNPCServerCore.UpdateNPCByUUID(uuid, {
            doObjectiveHookId = HOOK_ID,
            doObjectiveIncidentId = tostring(incident.incidentId),
            doObjectiveIncidentStatus = "accepted",
            doObjectiveOwnerPlayerKey = playerKey,
            doObjectiveOwnerUsername = username,
            doObjectiveSuppressTrade = true,
            doObjectiveDistress = false,
            doObjectiveEscortActive = true,
            doObjectiveEscortQuestId = incident.questId,
            doObjectiveRescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS),
            doObjectiveHomeCoords = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS),
            doObjectiveFactionId = incident.factionId,
            status = "Working",
            state = "Follow",
            master = username,
            masterID = onlineID,
            returnTime = 0,
            returnStatus = nil,
            requestedReturnStatus = nil,
            tasks = {},
            combatOrder = nil,
            guardCombatOrder = nil,
            guardAttackMode = nil,
        }, true)
    end

    if DTNPCServerCore and DTNPCServerCore.IssueOrderByUUID then
        local ok = DTNPCServerCore.IssueOrderByUUID(uuid, player, {
            state = "Follow",
        })
        if ok then
            return true
        end
    end

    saveSoul(uuid, soul)
    return true
end

local function getClientTraderSnapshot(traderId)
    if not traderId then
        return nil
    end

    local zombie = DTNPCClient and DTNPCClient.FindZombieByUUID and DTNPCClient.FindZombieByUUID(traderId) or nil
    if zombie then
        local npcData = DTNPC and DTNPC.GetData and DTNPC.GetData(zombie) or nil
        return {
            live = true,
            zombie = zombie,
            npcData = npcData,
            x = zombie:getX(),
            y = zombie:getY(),
            z = zombie:getZ(),
            status = npcData and npcData.status or nil,
            isDead = zombie:isDead() or (npcData and tostring(npcData.status or "") == "Dead"),
        }
    end

    local cached = DTNPCClient and DTNPCClient.NPCCache and DTNPCClient.NPCCache[traderId] or nil
    local npcData = cached and cached.npcData or nil
    if npcData then
        return {
            live = false,
            npcData = npcData,
            x = npcData.lastX,
            y = npcData.lastY,
            z = npcData.lastZ or 0,
            status = npcData.status,
            isDead = tostring(npcData.status or "") == "Dead",
        }
    end

    local meta = DTNPCClient and DTNPCClient.MetadataCache and DTNPCClient.MetadataCache[traderId] or nil
    if meta then
        return {
            live = false,
            npcData = meta,
            x = meta.lastX,
            y = meta.lastY,
            z = meta.lastZ or 0,
            status = meta.status,
            isDead = tostring(meta.status or "") == "Dead",
        }
    end

    if DT_RadioScannerManager and DT_RadioScannerManager.GetSoul then
        local soul = DT_RadioScannerManager.GetSoul(traderId)
        if soul then
            local hasLastKnownPosition = soul.lastX ~= nil and soul.lastY ~= nil
            local rescueSite = type(soul.doObjectiveRescueSite) == "table" and soul.doObjectiveRescueSite or nil
            local distressCoords = type(soul.doObjectiveDistressCoords) == "table" and soul.doObjectiveDistressCoords or nil
            local homeCoords = type(soul.doObjectiveHomeCoords) == "table" and soul.doObjectiveHomeCoords or soul.homeCoords
            local fallback = hasLastKnownPosition and nil or (distressCoords or rescueSite or homeCoords)
            return {
                live = false,
                npcData = soul,
                x = hasLastKnownPosition and soul.lastX or (fallback and fallback.x),
                y = hasLastKnownPosition and soul.lastY or (fallback and fallback.y),
                z = hasLastKnownPosition and (soul.lastZ or 0) or ((fallback and fallback.z) or 0),
                status = soul.status,
                isDead = tostring(soul.status or "") == "Dead",
                locationSource = hasLastKnownPosition and "lastKnown"
                    or (distressCoords and "distressCoords" or (rescueSite and "rescueSite" or (homeCoords and "homeCoords" or nil))),
            }
        end
    end

    return nil
end

local function snapshotIsIncapacitated(snapshot)
    local npcData = snapshot and snapshot.npcData or nil
    if not npcData then
        return false
    end

    return tostring(npcData.incapState or "") == "Active"
        or tostring(npcData.state or "") == "Incapacitated"
        or tostring(snapshot.status or "") == "Incapacitated"
end

local function getEscortRouteBaselineDistance(hookState, rescueSite, homeCoords)
    local persisted = tonumber(hookState and hookState.routeBaselineDistance)
    if persisted and persisted > 0 then
        return persisted
    end

    if rescueSite and homeCoords then
        local rescueToHome = distanceBetween(rescueSite.x, rescueSite.y, homeCoords.x, homeCoords.y)
        if rescueToHome > 0 then
            return rescueToHome
        end
    end

    local routeDistance = tonumber(hookState and hookState.routeDistance)
    local rescueDistance = tonumber(hookState and hookState.rescueDistance)
    if routeDistance and routeDistance > 0 and rescueDistance and rescueDistance >= 0 then
        local previousTotalDistance = routeDistance - rescueDistance
        if previousTotalDistance > 0 then
            return previousTotalDistance
        end
    end

    local homeDistance = tonumber(hookState and hookState.homeDistance)
    if homeDistance and homeDistance > 0 then
        return homeDistance
    end

    return nil
end

local function getEscortObjectiveLocationState(hookState, objective, fallbackLocation)
    if type(hookState) ~= "table" then
        return nil
    end

    local traderName = tostring(hookState.traderName or "Trader")
    local rescueSite = buildCoords(hookState.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local homeCoords = buildCoords(hookState.homeCoords, traderName .. "'s Base", HOME_RADIUS)
    local snapshot = getClientTraderSnapshot(hookState.traderId)
    local snapshotSource = snapshot and tostring(snapshot.locationSource or "") or nil

    if objective and objective.completed == true then
        return {
            kind = "home",
            location = homeCoords or fallbackLocation or rescueSite,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if homeCoords then
        return {
            kind = "home",
            location = homeCoords,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if snapshotSource == "rescueSite" and rescueSite then
        return {
            kind = "rescue",
            location = rescueSite,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if snapshotSource == "homeCoords" then
        return {
            kind = rescueSite and "rescue" or "home",
            location = rescueSite or homeCoords or fallbackLocation,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if snapshot and snapshot.x and snapshot.y then
        local traderLocation = buildCoords({
            x = snapshot.x,
            y = snapshot.y,
            z = snapshot.z or 0,
            label = traderName,
            radius = 12,
            symbolID = "DOQuestTarget",
            worldIcon = "friend.png",
            r = 0.95,
            g = 0.76,
            b = 0.22,
            a = 1.0,
            scale = 1.0,
        }, traderName, 12)

        if traderLocation then
            if homeCoords and isWithinRadius(homeCoords, traderLocation.x, traderLocation.y, traderLocation.z) then
                return {
                    kind = "home",
                    location = homeCoords,
                    homeCoords = homeCoords,
                    rescueSite = rescueSite,
                    snapshot = snapshot,
                }
            end

            return {
                kind = "trader",
                location = traderLocation,
                homeCoords = homeCoords,
                rescueSite = rescueSite,
                snapshot = snapshot,
            }
        end
    end

    if rescueSite then
        return {
            kind = "rescue",
            location = rescueSite,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if homeCoords then
        return {
            kind = "home",
            location = homeCoords,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    if fallbackLocation then
        return {
            kind = "fallback",
            location = fallbackLocation,
            homeCoords = homeCoords,
            rescueSite = rescueSite,
            snapshot = snapshot,
        }
    end

    return {
        kind = "missing",
        location = nil,
        homeCoords = homeCoords,
        rescueSite = rescueSite,
        snapshot = snapshot,
    }
end

local function emitEscortNoise(player, quest)
    if not player or not quest then
        return false
    end

    quest.hookState = type(quest.hookState) == "table" and quest.hookState or {}
    local nowMs = DO.NowMs()
    local lastNoiseAt = tonumber(quest.hookState.lastEscortNoiseAt) or 0
    if nowMs > 0 and lastNoiseAt > 0 and nowMs - lastNoiseAt < ESCORT_NOISE_COOLDOWN_MS then
        return false
    end

    local x = roundNumber(player:getX())
    local y = roundNumber(player:getY())
    local z = roundNumber(player:getZ())
    if DT_AudioManager and DT_AudioManager.PlayUISound then
        DT_AudioManager.PlayUISound("DT_HordeWarning", 1.0)
    end

    local flavorLines = {
        "I heard something moving out there.",
        "That noise is pulling more of them in.",
        "Movement nearby. Stay sharp.",
        "I can hear them coming.",
    }
    if player.Say and #flavorLines > 0 then
        player:Say(flavorLines[ZombRand(#flavorLines) + 1])
    end

    if addSound then
        local ok = pcall(addSound, player, x, y, z, ESCORT_NOISE_RADIUS, ESCORT_NOISE_VOLUME)
        if ok then
            quest.hookState.lastEscortNoiseAt = nowMs
            return true
        end
    end

    local manager = getWorldSoundManager and getWorldSoundManager() or nil
    if manager and manager.addSound then
        manager:addSound(player, x, y, z, ESCORT_NOISE_RADIUS, ESCORT_NOISE_VOLUME)
        quest.hookState.lastEscortNoiseAt = nowMs
        return true
    end

    return false
end

local function getEscortNpcDataByUUID(uuid)
    if not uuid or not DTNPCServerCore or not DTNPCServerCore.GetNPCDataByUUID then
        return nil, nil
    end

    local zombie, npcData = DTNPCServerCore.GetNPCDataByUUID(uuid)
    if type(zombie) == "boolean" then
        zombie = nil
    end
    return zombie, npcData
end

local function primeEscortBandageSupply(npcData, consumedBandage)
    if not npcData or not DTNPCHealth or not DTNPCHealth.EnsureDefaults then
        return false
    end

    local combatHealth = DTNPCHealth.EnsureDefaults(npcData)
    if not combatHealth then
        return false
    end

    combatHealth.bandageUnlimited = false
    combatHealth.bandageCharges = math.max(1, tonumber(combatHealth.bandageCharges) or 0)
    if consumedBandage and consumedBandage.fullType and tostring(consumedBandage.fullType) ~= "" then
        combatHealth.bandageItemFullType = tostring(consumedBandage.fullType)
    end
    return true
end

local function buildPendingScannerEntry(player, incident)
    local rescueSite = buildCoords(incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local homeCoords = buildCoords(incident.homeCoords, "Trader Base", HOME_RADIUS)
    local snapshot = getClientTraderSnapshot(incident and incident.traderId)
    local distressTarget = nil
    if snapshot and snapshot.x and snapshot.y then
        distressTarget = buildDistressTargetCoords(incident, snapshot.x, snapshot.y, snapshot.z or 0)
    end
    if not distressTarget then
        distressTarget = buildCoords(incident.distressCoords, tostring(incident.traderName or "Trader"), 10)
    end

    local target = distressTarget or rescueSite
    if not target then
        return nil
    end

    local traderDistance = distanceBetween(player:getX(), player:getY(), target.x, target.y)
    local homeDistance = homeCoords and distanceBetween(target.x, target.y, homeCoords.x, homeCoords.y) or nil
    local expiresAt = tonumber(incident.expiresAt) or 0
    local remainingHours = expiresAt > 0 and math.max(0, (expiresAt - (DO.NowMs and DO.NowMs() or 0)) / (1000 * 60 * 60)) or nil
    return {
        uuid = tostring(incident.traderId or incident.incidentId),
        hookId = HOOK_ID,
        incidentId = tostring(incident.incidentId),
        entryKind = "pendingIncident",
        name = tostring(incident.title or incident.traderName or "Trader Distress Call"),
        faction = incident.factionId,
        factionName = incident.factionName or getFactionName(incident.factionId) or "Independent",
        archetype = incident.archetype and tostring(incident.archetype) or "Trader",
        gender = "Unknown",
        identitySeed = 1,
        x = target.x,
        y = target.y,
        z = target.z,
        distText = string.format("Distressed Trader: %.0fm", traderDistance),
        expireText = remainingHours and string.format("Signal %.1fh", remainingHours) or "Pending rescue",
        detailText = homeDistance and formatDistanceLabel("Home", homeDistance) or "",
        isLive = snapshot and snapshot.live == true,
        canLock = false,
        locked = false,
        priority = 120,
        sortTime = tonumber(incident.createdAt) or 0,
    }
end

local function buildActiveQuestScannerEntry(player, quest)
    local hookState = type(quest and quest.hookState) == "table" and quest.hookState or nil
    local objective = quest and quest.objectives and quest.objectives[1] or nil
    local fallbackTarget = buildCoords(quest and quest.targetLocation, tostring(quest and quest.name or "Escort"), HOME_RADIUS)
    local targetState = getEscortObjectiveLocationState(hookState, objective, fallbackTarget)
    local target = targetState and targetState.location or fallbackTarget
    if not hookState or not target then
        return nil
    end

    local targetDistance = distanceBetween(player:getX(), player:getY(), target.x, target.y)
    local homeCoords = targetState and targetState.homeCoords or buildCoords(hookState.homeCoords, "Trader Base", HOME_RADIUS)
    local escortDistance = targetState and targetState.snapshot and homeCoords and targetState.snapshot.x and targetState.snapshot.y
        and distanceBetween(targetState.snapshot.x, targetState.snapshot.y, homeCoords.x, homeCoords.y)
        or nil
    local distancePrefix = "Destination"
    if targetState and targetState.kind == "rescue" then
        distancePrefix = "Distress House"
    end

    local detail = DO.Quests and DO.Quests.GetQuestDetailData and DO.Quests.GetQuestDetailData(player, quest.id) or nil
    local remainingHours = detail and tonumber(detail.timeRemainingHours) or nil
    return {
        uuid = tostring(hookState.traderId or quest.id),
        hookId = HOOK_ID,
        incidentId = tostring(quest.hookIncidentId or ""),
        questID = tostring(quest.id or ""),
        entryKind = "activeQuest",
        name = tostring(quest.title or hookState.traderName or quest.name or "Escort Trader"),
        faction = hookState.factionId,
        factionName = hookState.factionName or getFactionName(hookState.factionId) or "Independent",
        archetype = quest.giverTitle or hookState.traderTitle or "Trader",
        gender = "Unknown",
        identitySeed = 1,
        x = target.x,
        y = target.y,
        z = target.z,
        distText = string.format("%s: %.0fm", distancePrefix, targetDistance),
        expireText = remainingHours ~= nil and string.format("Expires in %.1fh", math.max(0, remainingHours))
            or (quest.rewardPreview and ("Rewards: " .. tostring(quest.rewardPreview)))
            or "Escort active",
        detailText = escortDistance and formatDistanceLabel("Escort", escortDistance) or "",
        isLive = false,
        canLock = false,
        locked = false,
        priority = 140,
        sortTime = tonumber(quest.createdAt) or 0,
    }
end

local Hook = {
    id = HOOK_ID,
}

function Hook.refreshIncidentsForPlayer(player)
    if not player or not isAuthoritative() then
        return false
    end

    cleanupWorldIncidents()

    local playerKey = DO.GetPlayerKey and DO.GetPlayerKey(player) or nil
    local store, hookStore = ensurePlayerHookStore(player, true)
    local worldState = getWorldState(true)
    if not store or not hookStore or not worldState then
        return false
    end

    local changed = false
    local activeQuest = getActiveHookQuest(player)
    local currentAccepted = nil
    local pendingCount = 0
    local syncedCount = 0
    local createdCount = 0

    for incidentID, incident in pairs(hookStore.incidents or {}) do
        local liveIncident = worldState.incidents[tostring(incidentID)]
        if not liveIncident then
            hookStore.incidents[incidentID] = nil
            changed = true
        elseif tostring(liveIncident.status or "") == "accepted" and tostring(liveIncident.ownerPlayerKey or "") == tostring(playerKey or "") then
            currentAccepted = liveIncident
            hookStore.incidents[incidentID] = copyIncidentForPlayer(liveIncident)
            changed = true
        elseif tostring(liveIncident.status or "") ~= "pending" then
            hookStore.incidents[incidentID] = nil
            changed = true
        elseif not incidentMatchesPlayerRange(player, liveIncident) then
            hookStore.incidents[incidentID] = nil
            changed = true
        else
            local spawnedTrader = ensurePendingTraderSpawned(player, liveIncident)
            local spawnedExterior = trySpawnExteriorZombies(player, liveIncident)
            hookStore.incidents[incidentID] = copyIncidentForPlayer(liveIncident)
            pendingCount = pendingCount + 1
            if spawnedTrader == true or spawnedExterior == true then
                changed = true
            end
        end
    end

    if currentAccepted or activeQuest then
        for incidentID, incident in pairs(hookStore.incidents or {}) do
            if tostring(incident and incident.status or "") == "pending" then
                hookStore.incidents[incidentID] = nil
                changed = true
            end
        end
        if currentAccepted then
            trySpawnExteriorZombies(player, currentAccepted)
        end
        hookLog(
            "Refresh",
            "Escort refresh suspended pendingCount=" .. tostring(pendingCount)
                .. " accepted=" .. tostring(currentAccepted ~= nil)
                .. " activeQuest=" .. tostring(activeQuest and activeQuest.id or "none")
        )
        if changed then
            player:transmitModData()
        end
        return changed
    end

    local targetPendingCount, minimumPendingCount, extraChance, extraPassed, extraRoll = buildEscortRefreshTarget()
    local selectedIncidentIds = {}

    for incidentID, incident in pairs(hookStore.incidents or {}) do
        if tostring(incident and incident.status or "") == "pending" then
            selectedIncidentIds[tostring(incidentID)] = true
        end
    end

    for _, pendingIncident in ipairs(collectPendingIncidentsForPlayer(player)) do
        local incidentId = tostring(pendingIncident.incidentId or "")
        if incidentId ~= "" and not selectedIncidentIds[incidentId] and pendingCount < targetPendingCount then
            ensurePendingTraderSpawned(player, pendingIncident)
            trySpawnExteriorZombies(player, pendingIncident)
            syncIncidentMirrorForPlayer(player, pendingIncident)
            selectedIncidentIds[incidentId] = true
            pendingCount = pendingCount + 1
            syncedCount = syncedCount + 1
            changed = true
        end
    end

    local selectedTraderIds = {}
    for _, incident in pairs(hookStore.incidents or {}) do
        if tostring(incident and incident.status or "") == "pending" and incident.traderId then
            selectedTraderIds[tostring(incident.traderId)] = true
        end
    end

    while pendingCount < targetPendingCount do
        local createdIncident = createIncidentForPlayer(player, selectedTraderIds)
        if not createdIncident then
            break
        end

        ensurePendingTraderSpawned(player, createdIncident)
        trySpawnExteriorZombies(player, createdIncident)
        syncIncidentMirrorForPlayer(player, createdIncident)
        selectedIncidentIds[tostring(createdIncident.incidentId or "")] = true
        selectedTraderIds[tostring(createdIncident.traderId or "")] = true
        pendingCount = pendingCount + 1
        createdCount = createdCount + 1
        changed = true
    end

    hookLog(
        "Refresh",
        "Escort refresh pending=" .. tostring(pendingCount)
            .. " minimum=" .. tostring(minimumPendingCount)
            .. " target=" .. tostring(targetPendingCount)
            .. " synced=" .. tostring(syncedCount)
            .. " created=" .. tostring(createdCount)
            .. " extraChance=" .. tostring(extraChance)
            .. " extraRoll=" .. tostring(extraRoll ~= nil and extraRoll or "n/a")
            .. " extraPassed=" .. tostring(extraPassed)
    )
    if pendingCount < minimumPendingCount then
        hookLog(
            "Refresh",
            "Escort floor unmet pending=" .. tostring(pendingCount)
                .. " minimum=" .. tostring(minimumPendingCount)
                .. " (see Create logs for rejection reasons)"
        )
    end

    if changed then
        player:transmitModData()
    end
    return changed
end

function Hook.buildScannerEntries(player)
    local results = {}
    if not player then
        return results
    end

    local _, hookStore = ensurePlayerHookStore(player, false)
    if hookStore then
        for _, incident in pairs(hookStore.incidents or {}) do
            if tostring(incident.status or "") == "pending" and incidentMatchesPlayerRange(player, incident) then
                local entry = buildPendingScannerEntry(player, incident)
                if entry then
                    results[#results + 1] = entry
                end
            end
        end
    end

    local store = Quests.GetStore and Quests.GetStore(player, false) or nil
    if store then
        for _, quest in ipairs(store.quests or {}) do
            if quest.status == "active" and tostring(quest.hookId or "") == HOOK_ID then
                local entry = buildActiveQuestScannerEntry(player, quest)
                if entry then
                    results[#results + 1] = entry
                end
            end
        end
    end

    return results
end

function Hook.buildOffer(player, context)
    local incident = type(context) == "table" and (context.incident or context) or nil
    local traderName = incident and tostring(incident.traderName or "the trader") or "the trader"
    local questSpec = player and incident and buildQuestSpecForIncident(player, incident) or nil
    local contractTitle = tostring(questSpec and (questSpec.title or questSpec.name) or (traderName .. " Escort"))
    local rewardPreview = questSpec and questSpec.rewardPreview and tostring(questSpec.rewardPreview) or nil
    local rescueSite = buildCoords(incident and incident.rescueSite, "Distress Signal", RESCUE_RADIUS)
    local homeCoords = buildCoords(incident and incident.homeCoords, "Trader Base", HOME_RADIUS)
    local metrics = player and rescueSite and homeCoords and buildEscortDistanceMetrics(player, rescueSite, homeCoords) or nil
    local routeText = metrics and formatEscortRouteText(metrics.routeDistance, metrics.homeDistance) or ""
    return {
        choiceLabels = {
            accept = "Accept",
            details = "Details",
            decline = "Decline",
            leave = "Leave",
        },
        offer = string.format("%s. Zombies pinned me down here. Escort me back to base, and I'll make it worth your time.", contractTitle),
        details = string.format(
            "Keep %s alive and get them back to their home base. The dead are crowding the front of the house.%s%s",
            traderName,
            routeText ~= "" and (" " .. routeText .. ".") or "",
            rewardPreview and (" Reward package: " .. rewardPreview .. ".") or ""
        ),
        accept = string.format("I'm with you. Stay sharp and get me home."),
        decline = "Then I stay put and hope the walls keep holding.",
        active = string.format("We already have an escort running. Keep me moving."),
        unavailable = "This rescue isn't available anymore.",
    }
end

function Hook.acceptIncident(player, args)
    if not player or not isAuthoritative() then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = args and args.incidentId or nil,
            reason = "not_authoritative",
            message = "The escort system is unavailable right now.",
        }
    end

    local incidentId = args and args.incidentId and tostring(args.incidentId) or nil
    local worldState = getWorldState(true)
    local incident = worldState and incidentId and worldState.incidents[incidentId] or nil
    if not incident then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "missing_incident",
            message = "That rescue call is gone.",
        }
    end

    if incidentIsExpired(incident) then
        restoreTraderState(incident, "expired")
        removeWorldIncident(worldState, incidentId)
        transmitWorldState()
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "expired",
            message = "You got here too late.",
        }
    end

    local playerKey = DO.GetPlayerKey and DO.GetPlayerKey(player) or nil
    local username = getPlayerUsername(player)
    if incident.ownerPlayerKey and tostring(incident.ownerPlayerKey) ~= tostring(playerKey) then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "already_reserved",
            message = "Someone else already claimed this escort.",
        }
    end

    local existingQuest = getActiveHookQuest(player, incidentId, incident.traderId)
    if existingQuest then
        incident.ownerPlayerKey = tostring(playerKey)
        incident.ownerUsername = username and tostring(username) or nil
        incident.status = "accepted"
        incident.questId = tostring(existingQuest.id or incident.questId or "")
        syncIncidentMirrorForPlayer(player, incident)
        transmitWorldState()
        return {
            ok = true,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = incident.traderId,
            questID = tostring(existingQuest.id or ""),
            message = "Escort accepted. Get the trader home.",
        }
    end

    local soul = getSoul(incident.traderId)
    if not isAliveSoul(soul) then
        incident.status = "failed"
        transmitWorldState()
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "trader_dead",
            message = "The trader didn't make it.",
        }
    end

    incident.ownerPlayerKey = tostring(playerKey)
    incident.ownerUsername = username and tostring(username) or nil
    incident.status = "accepted"
    incident.acceptedAt = DO.NowMs()
    incident.questId = incident.questId or string.format("HOOK_%s_%d", tostring(incident.traderId):gsub("[^%w_:%-]", "_"), ZombRand(1000, 9999))

    activateEscortForPlayer(player, incident)
    local questSpec = buildQuestSpecForIncident(player, incident)
    if not questSpec then
        incident.status = "pending"
        incident.ownerPlayerKey = nil
        incident.ownerUsername = nil
        incident.acceptedAt = nil
        incident.questId = nil
        applyDistressState(incident)
        transmitWorldState()
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "invalid_spec",
            message = "The escort could not be prepared.",
        }
    end

    local startedQuest = Quests.StartQuest and Quests.StartQuest(player, questSpec) or nil
    if not startedQuest then
        incident.status = "pending"
        incident.ownerPlayerKey = nil
        incident.ownerUsername = nil
        incident.acceptedAt = nil
        incident.questId = nil
        applyDistressState(incident)
        transmitWorldState()
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            reason = "start_failed",
            message = "The escort could not be started.",
        }
    end

    incident.questId = tostring(startedQuest.id or incident.questId or "")

    syncIncidentMirrorForPlayer(player, incident)
    transmitWorldState()

    return {
        ok = true,
        hookId = HOOK_ID,
        incidentId = incidentId,
        traderId = incident.traderId,
        questID = tostring(startedQuest.id or ""),
        message = "Escort accepted. Get the trader home.",
    }
end

function Hook.performEscortAction(player, args)
    local action = tostring(args and args.action or ""):lower()
    local traderId = args and args.traderId and tostring(args.traderId) or nil
    local incidentId = args and args.incidentId and tostring(args.incidentId) or nil
    if not player or not isAuthoritative() or action == "" or not traderId then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = traderId,
            action = action,
            message = "The escort cannot respond right now.",
        }
    end

    local worldState = getWorldState(false)
    local incident = worldState and incidentId and worldState.incidents[incidentId] or nil
    local playerKey = tostring(DO.GetPlayerKey and DO.GetPlayerKey(player) or "")
    local soul = getSoul(traderId)
    if incidentId and incident == nil and soul and tostring(soul.doObjectiveIncidentId or "") == incidentId then
        incident = {
            traderId = traderId,
            ownerPlayerKey = soul.doObjectiveOwnerPlayerKey,
            status = soul.doObjectiveEscortActive == true and "accepted" or soul.doObjectiveIncidentStatus,
        }
    end

    if not incident or tostring(incident.status or "") ~= "accepted" then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = traderId,
            action = action,
            message = "This escort mission is no longer active.",
        }
    end

    if tostring(incident.ownerPlayerKey or "") ~= playerKey then
        return {
            ok = false,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = traderId,
            action = action,
            message = "Only the assigned rescuer can command this escort.",
        }
    end

    if action == "follow" or action == "stay" then
        local targetState = action == "follow" and "Follow" or "Stay"
        local changed, updatedNPC = false, nil
        if DTNPCServerCore and DTNPCServerCore.IssueOrderByUUID then
            changed, updatedNPC = DTNPCServerCore.IssueOrderByUUID(traderId, player, { state = targetState })
        end
        return {
            ok = changed == true or updatedNPC ~= nil,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = traderId,
            action = action,
            message = action == "follow"
                    and "Stay close. I'll follow your lead."
                or "I'll hold here until you move me again.",
            stateChanged = changed == true,
        }
    end

    if action == "patchup" then
        local bandageItem = DO.MedicalItemUtils and DO.MedicalItemUtils.FindFirstBandageItem
            and DO.MedicalItemUtils.FindFirstBandageItem(player)
            or nil
        if not bandageItem then
            return {
                ok = false,
                hookId = HOOK_ID,
                incidentId = incidentId,
                traderId = traderId,
                action = action,
                message = "You need a bandage, adhesive bandage, or rag before you can patch me up.",
            }
        end

        local zombie, npcData = getEscortNpcDataByUUID(traderId)
        if not npcData and DTNPCServerCore and DTNPCServerCore.SpawnNearbyCompanionByUUID then
            DTNPCServerCore.SpawnNearbyCompanionByUUID(traderId, player, 2, 5)
            zombie, npcData = getEscortNpcDataByUUID(traderId)
        end

        local reservedBandage = {
            fullType = tostring(bandageItem.getFullType and bandageItem:getFullType() or ""),
            displayName = DO.MedicalItemUtils and DO.MedicalItemUtils.GetBandageDisplayName
                and DO.MedicalItemUtils.GetBandageDisplayName(bandageItem)
                or "bandage",
        }

        if not primeEscortBandageSupply(npcData, reservedBandage) then
            return {
                ok = false,
                hookId = HOOK_ID,
                incidentId = incidentId,
                traderId = traderId,
                action = action,
                message = "The escort can't be treated right now.",
            }
        end

        if DTNPCServerCore and DTNPCServerCore.UpdateNPCByUUID then
            DTNPCServerCore.UpdateNPCByUUID(traderId, {
                combatHealth = npcData.combatHealth,
            }, true)
        end

        local patched = DTNPCServerCore and DTNPCServerCore.StartPatchUpByUUID
            and DTNPCServerCore.StartPatchUpByUUID(traderId)
            or false
        if patched == true and DO.MedicalItemUtils and DO.MedicalItemUtils.ConsumeFirstBandageItem then
            DO.MedicalItemUtils.ConsumeFirstBandageItem(player)
        end
        return {
            ok = patched == true,
            hookId = HOOK_ID,
            incidentId = incidentId,
            traderId = traderId,
            action = action,
            message = patched == true
                    and ("Use this " .. tostring(reservedBandage.displayName or "bandage") .. " and keep moving.")
                or "I can't patch up right now. Keep the dead off me.",
            stateChanged = patched == true,
        }
    end

    return {
        ok = false,
        hookId = HOOK_ID,
        incidentId = incidentId,
        traderId = traderId,
        action = action,
        message = "That escort command isn't supported.",
    }
end

function Hook.finalizeQuest(player, args)
    if not player or not isAuthoritative() then
        return false
    end

    local incidentId = args and args.incidentId and tostring(args.incidentId) or nil
    local resolution = tostring(args and args.resolution or "completed")
    local worldState = getWorldState(true)
    local incident = worldState and incidentId and worldState.incidents[incidentId] or nil
    if not incident then
        removePlayerIncident(player, incidentId)
        if player.transmitModData then
            player:transmitModData()
        end
        return false
    end

    if resolution == "completed" then
        restoreTraderState(incident, "completed")
    elseif resolution == "failed" or resolution == "abandoned" then
        local soul = getSoul(incident.traderId)
        if isAliveSoul(soul) then
            restoreTraderState(incident, resolution)
        else
            incident.status = resolution
            incident.updatedAt = DO.NowMs()
        end
    else
        incident.status = resolution
        incident.updatedAt = DO.NowMs()
    end

    removePlayerIncident(player, incidentId)
    player:transmitModData()
    transmitWorldState()
    return true
end

function Hook.forceIncidentForPlayer(player, args)
    if not player or not isAuthoritative() then
        return {
            ok = false,
            reason = "not_authoritative",
        }
    end

    cleanupWorldIncidents()

    local store, hookStore = ensurePlayerHookStore(player, true)
    local worldState = getWorldState(true)
    if not store or not hookStore or not worldState then
        hookLog("Debug", "Force escort failed: state unavailable")
        return {
            ok = false,
            reason = "state_unavailable",
        }
    end

    local activeQuest = getActiveHookQuest(player)
    if activeQuest then
        hookLog("Debug", "Force escort skipped: active escort quest already exists for player")
        return {
            ok = false,
            reason = "active_quest",
            questId = tostring(activeQuest.id or ""),
        }
    end

    clearPendingMirrorsExcept(player, nil)

    local incident = createIncidentForPlayer(player)
    if not incident then
        hookLog("Debug", "Force escort failed: no eligible Trading trader within " .. tostring(MAX_PLAYER_DISTANCE) .. "m")
        if player and player.transmitModData then
            player:transmitModData()
        end
        return {
            ok = false,
            reason = "no_eligible_trader",
        }
    end

    syncIncidentMirrorForPlayer(player, incident)
    trySpawnExteriorZombies(player, incident)
    transmitWorldState()
    hookLog(
        "Debug",
        "Forced escort incident traderId=" .. tostring(incident.traderId)
            .. " rescueDistance=" .. tostring(incident.rescueDistance)
            .. " homeDistance=" .. tostring(incident.homeDistance)
            .. " reward=" .. tostring(incident.cashReward)
    )
    return {
        ok = true,
        incidentId = tostring(incident.incidentId or ""),
        traderId = tostring(incident.traderId or ""),
    }
end

function Hook.onQuestAccepted(player, quest, store)
    local hookState = type(quest and quest.hookState) == "table" and quest.hookState or nil
    local incidentId = quest and quest.hookIncidentId or nil
    if not player or not hookState or not incidentId then
        return
    end

    local incidentMap = getPlayerIncidentMap(player, true)
    if incidentMap and incidentMap[tostring(incidentId)] then
        incidentMap[tostring(incidentId)].questId = tostring(quest.id)
        incidentMap[tostring(incidentId)].status = "accepted"
    end
end

function Hook.onQuestUpdate(player, quest, store)
    local hookState = type(quest and quest.hookState) == "table" and quest.hookState or nil
    if not player or not quest or not hookState then
        return nil
    end

    local traderId = hookState.traderId and tostring(hookState.traderId) or nil
    local snapshot = getClientTraderSnapshot(traderId)
    local objective = quest.objectives and quest.objectives[1] or nil
    local homeCoords = buildCoords(hookState.homeCoords, "Trader Base", HOME_RADIUS)

    if snapshot and snapshot.isDead == true then
        return {
            fail = true,
            reason = "escort_target_lost",
        }
    end

    if snapshot and snapshotIsIncapacitated(snapshot) then
        return {
            fail = true,
            reason = "escort_target_incapacitated",
        }
    end

    if objective and homeCoords and snapshot and snapshot.x and snapshot.y then
        local reachedHome = isWithinRadius(homeCoords, snapshot.x, snapshot.y, snapshot.z)
        if reachedHome then
            local changed = (tonumber(objective.progress) or 0) < 1 or objective.completed ~= true
            objective.progress = 1
            objective.required = 1
            objective.completed = true
            return {
                changed = changed,
                complete = true,
                reason = "escort_home",
            }
        end
    end

    if snapshot and snapshot.x and snapshot.y and homeCoords then
        emitEscortNoise(player, quest)
    end

    return nil
end

function Hook.onQuestComplete(player, quest, store)
    return true
end

function Hook.onQuestFail(player, quest, store)
    return true
end

function Hook.resolveQuestLocation(player, quest, objective, fallbackLocation)
    local hookState = type(quest and quest.hookState) == "table" and quest.hookState or nil
    local targetState = getEscortObjectiveLocationState(hookState, objective, fallbackLocation)
    return targetState and targetState.location or fallbackLocation
end

function Hook.buildSummary(player, quest, detail)
    local hookState = type(quest and quest.hookState) == "table" and quest.hookState or nil
    if not hookState then
        return nil
    end

    local traderName = tostring(hookState.traderName or quest.name or "Trader")
    local objective = quest and quest.objectives and quest.objectives[1] or nil
    local fallbackLocation = detail and detail.targetLocation or buildCoords(quest and quest.targetLocation, traderName, HOME_RADIUS)
    local targetState = getEscortObjectiveLocationState(hookState, objective, fallbackLocation)
    local snapshot = targetState and targetState.snapshot or getClientTraderSnapshot(hookState.traderId)
    local homeCoords = targetState and targetState.homeCoords or buildCoords(hookState.homeCoords, "Trader Base", HOME_RADIUS)
    local targetLocation = targetState and targetState.location or fallbackLocation
    local routeBaselineDistance = getEscortRouteBaselineDistance(hookState, targetState and targetState.rescueSite or nil, homeCoords)
    local distanceToHome = nil
    if snapshot and homeCoords and snapshot.x and snapshot.y then
        distanceToHome = distanceBetween(snapshot.x, snapshot.y, homeCoords.x, homeCoords.y)
    end

    local progressRatio = nil
    if objective and objective.completed == true then
        progressRatio = 1
    elseif distanceToHome and routeBaselineDistance and routeBaselineDistance > 0 then
        progressRatio = math.max(0, math.min(1, 1 - (distanceToHome / routeBaselineDistance)))
    elseif distanceToHome then
        progressRatio = 0
    end

    local destinationLabel = homeCoords and tostring(homeCoords.label or "Trader Base") or "Trader Base"
    local escortCondition = snapshot and snapshotIsIncapacitated(snapshot) and "Escort failed" or "Keep the trader on their feet"

    local summaryFragments = {
        "Reach the destination",
    }
    if distanceToHome then
        summaryFragments[#summaryFragments + 1] = string.format("Destination %.0fm", distanceToHome)
    else
        summaryFragments[#summaryFragments + 1] = destinationLabel
    end

    return {
        currentObjectiveLabel = "Reach " .. destinationLabel,
        targetLabel = targetLocation and tostring(targetLocation.label or destinationLabel) or (detail and detail.targetLabel) or destinationLabel,
        primaryProgress = distanceToHome and {
            label = "Distance to Base",
            value = string.format("%.0fm remaining", distanceToHome),
            detail = routeBaselineDistance and string.format("Started %.0fm out", routeBaselineDistance)
                or "Keep the trader moving toward base",
            ratio = progressRatio or 0,
            color = (objective and objective.completed == true) and { r = 0.34, g = 0.82, b = 0.48 } or { r = 0.42, g = 0.82, b = 0.54 },
        } or nil,
        lines = {
            {
                id = "escort_destination",
                label = "Destination",
                value = destinationLabel,
                completed = objective and objective.completed == true,
                current = true,
            },
            {
                id = "escort_condition",
                label = "Escort Condition",
                value = escortCondition,
                completed = false,
                current = false,
            },
        },
        summaryFragments = summaryFragments,
        replaceSummaryFragments = true,
    }
end

DO.RegisterObjectiveHook(HOOK_ID, Hook)
