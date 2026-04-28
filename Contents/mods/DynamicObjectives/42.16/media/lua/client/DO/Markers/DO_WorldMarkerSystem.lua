DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.WorldMarkers = DynamicObjectives.WorldMarkers or {}

local DO = DynamicObjectives
local WorldMarkers = DO.WorldMarkers

WorldMarkers.MARKER_ID = WorldMarkers.MARKER_ID or "DO_TrackedQuest"
WorldMarkers.updateCounter = WorldMarkers.updateCounter or 0
WorldMarkers.dirty = true
WorldMarkers.lastSignature = WorldMarkers.lastSignature or nil

local function buildSignature(marker)
    if not marker then
        return "none"
    end

    return table.concat({
        tostring(marker.questID),
        tostring(marker.x),
        tostring(marker.y),
        tostring(marker.z),
        tostring(marker.worldIcon),
        tostring(marker.description),
    }, "|")
end

function WorldMarkers.RequestFullRefresh()
    WorldMarkers.dirty = true
end

local function hasActiveMarker()
    return EventMarkerHandler
        and EventMarkerHandler.markers
        and EventMarkerHandler.markers[WorldMarkers.MARKER_ID] ~= nil
end

function WorldMarkers.Clear()
    if EventMarkerHandler and EventMarkerHandler.remove then
        EventMarkerHandler.remove(WorldMarkers.MARKER_ID)
    end
    WorldMarkers.lastSignature = "none"
    WorldMarkers.dirty = false
end

function WorldMarkers.Refresh(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer()
    if not playerObj or not DO.Quests or not DO.Quests.GetLocatedMarkerData then
        WorldMarkers.Clear()
        return
    end

    local marker = DO.Quests.GetLocatedMarkerData(playerObj)
    local signature = buildSignature(marker)
    local markerMissing = marker ~= nil and hasActiveMarker() ~= true
    if not WorldMarkers.dirty and signature == WorldMarkers.lastSignature and markerMissing ~= true then
        return
    end

    if not marker or not EventMarkerHandler or not EventMarkerHandler.set then
        WorldMarkers.Clear()
        return
    end

    EventMarkerHandler.set(
        WorldMarkers.MARKER_ID,
        tostring(marker.worldIcon or "loot.png"),
        600,
        tonumber(marker.x) or 0,
        tonumber(marker.y) or 0,
        {
            r = tonumber(marker.r) or 1.0,
            g = tonumber(marker.g) or 0.85,
            b = tonumber(marker.b) or 0.2,
        },
        tostring(marker.description or marker.name or "Tracked Objective")
    )

    WorldMarkers.lastSignature = signature
    WorldMarkers.dirty = false
end

function WorldMarkers.OnTick()
    WorldMarkers.updateCounter = (tonumber(WorldMarkers.updateCounter) or 0) + 1
    if WorldMarkers.updateCounter < 30 then
        return
    end
    WorldMarkers.updateCounter = 0
    WorldMarkers.Refresh()
end

Events.OnTick.Add(WorldMarkers.OnTick)
