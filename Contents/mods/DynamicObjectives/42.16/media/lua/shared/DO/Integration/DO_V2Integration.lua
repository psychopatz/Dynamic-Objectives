DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.Integration = DynamicObjectives.Integration or {}
DynamicObjectives.Integration.V2 = DynamicObjectives.Integration.V2 or {}

local DO = DynamicObjectives
local V2 = DO.Integration.V2

local function isModActive(modID)
    if not getActivatedMods or not modID then
        return false
    end

    local mods = getActivatedMods()
    return mods and mods.contains and mods:contains(modID) or false
end

local function getPlayerRegion(player)
    if not player or not DT_GeolocatorSystem or not DT_GeolocatorSystem.ResolveRegionName then
        return nil
    end

    return DT_GeolocatorSystem.ResolveRegionName(player:getX(), player:getY())
end

local function buildFallbackDestination(player, purpose)
    local offsets = {
        { 240, 0 },
        { 0, 240 },
        { -240, 0 },
        { 0, -240 },
        { 180, 180 },
        { -180, 180 },
        { 180, -180 },
        { -180, -180 },
    }

    local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
    local index = (playerNum % #offsets) + 1
    local offset = offsets[index]
    local px = math.floor(player and player:getX() or 0)
    local py = math.floor(player and player:getY() or 0)

    return {
        x = px + offset[1],
        y = py + offset[2],
        z = player and player:getZ() or 0,
        label = tostring(purpose or "Objective Site"),
        symbolID = "DOQuestTarget",
        worldIcon = "loot.png",
        r = 1.0,
        g = 0.85,
        b = 0.2,
        a = 1.0,
        scale = 1.15,
        radius = 45,
        source = "fallback",
    }
end

function V2.IsEnvironmentActive()
    return isModActive("DynamicTradingV2") or isModActive("DynamicTradingCommon")
end

function V2.HasDestinationResolver()
    return DT_GeolocatorSystem
        and DT_GeolocatorSystem.GetAvailableFactionBases
        and DT_GeolocatorSystem.ResolveRegionName
end

function V2.ResolveDebugDestination(player, purpose)
    if not player then
        return nil
    end

    if not V2.HasDestinationResolver() then
        return buildFallbackDestination(player, purpose)
    end

    local targetTown = getPlayerRegion(player) or ""
    local candidates = DT_GeolocatorSystem.GetAvailableFactionBases(targetTown, {}) or {}
    if #candidates == 0 then
        candidates = DT_GeolocatorSystem.GetAvailableFactionBases("", {}) or {}
    end

    local best = nil
    local px = player:getX()
    local py = player:getY()
    local bestDistance = nil

    for _, candidate in ipairs(candidates) do
        local coords = candidate and candidate.coords or nil
        local cx = coords and tonumber(coords.x) or nil
        local cy = coords and tonumber(coords.y) or nil
        if cx and cy then
            local dx = cx - px
            local dy = cy - py
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 120 and (not bestDistance or distance < bestDistance) then
                best = candidate
                bestDistance = distance
            end
        end
    end

    if not best then
        best = candidates[1]
    end

    local coords = best and best.coords or nil
    if not coords or coords.x == nil or coords.y == nil then
        return buildFallbackDestination(player, purpose)
    end

    return {
        x = math.floor(tonumber(coords.x) or 0),
        y = math.floor(tonumber(coords.y) or 0),
        z = math.floor(tonumber(coords.z) or 0),
        label = tostring(best.name or purpose or "Objective Site"),
        symbolID = "DOQuestTarget",
        worldIcon = "loot.png",
        r = 1.0,
        g = 0.85,
        b = 0.2,
        a = 1.0,
        scale = 1.15,
        radius = 55,
        town = best.town,
        county = best.county,
        source = "dt_v2",
    }
end
