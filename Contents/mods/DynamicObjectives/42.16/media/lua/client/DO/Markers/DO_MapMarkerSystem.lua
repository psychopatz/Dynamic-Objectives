require "ISUI/Maps/ISWorldMap"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.MapMarkers = DynamicObjectives.MapMarkers or {}

local DO = DynamicObjectives
local MapMarkers = DO.MapMarkers

MapMarkers.hiddenMaps = MapMarkers.hiddenMaps or {}
MapMarkers.ownedSymbolIDs = MapMarkers.ownedSymbolIDs or {
    DOQuestTarget = true,
    DOQuestTurnIn = true,
}
MapMarkers.updateCounter = MapMarkers.updateCounter or 0
MapMarkers.dirty = true
MapMarkers.lastSignature = MapMarkers.lastSignature or nil

local function ensureHiddenMap(playerObj)
    if not playerObj or not ISWorldMap then
        return nil
    end

    local playerNum = playerObj:getPlayerNum()
    local existing = MapMarkers.hiddenMaps[playerNum]
    if existing and existing.javaObject then
        return existing
    end

    local map = ISWorldMap:new(0, 0, 10, 10)
    map:initialise()
    map:instantiate()
    map.character = playerObj
    map.playerNum = playerNum
    map:initDataAndStyle()
    map:setVisible(false)

    MapMarkers.hiddenMaps[playerNum] = map
    return map
end

local function getSymbolsAPI(playerObj)
    local map = ensureHiddenMap(playerObj)
    if not map or not map.mapAPI then
        return nil
    end

    local symbols = map.mapAPI:getSymbolsAPIv2()
    if symbols and symbols.initDefaultAnnotations and not map.doAnnotationsReady then
        symbols:initDefaultAnnotations()
        map.doAnnotationsReady = true
    end
    return symbols
end

local function clearOwnedSymbols(symbols)
    if not symbols then
        return
    end

    for index = symbols:getSymbolCount() - 1, 0, -1 do
        local symbol = symbols:getSymbolByIndex(index)
        if symbol and symbol.getSymbolID then
            local symbolID = symbol:getSymbolID()
            if symbolID and MapMarkers.ownedSymbolIDs[symbolID] then
                symbols:removeSymbolByIndex(index)
            end
        end
    end
end

local function drawTrackedMarker(symbols, marker)
    if not symbols or not marker then
        return
    end

    local symbol = symbols:addTexture(
        tostring(marker.symbolID or "DOQuestTarget"),
        math.floor(tonumber(marker.x) or 0),
        math.floor(tonumber(marker.y) or 0)
    )
    if not symbol then
        return
    end

    symbol:setAnchor(0.5, 0.5)
    symbol:setRGBA(
        tonumber(marker.r) or 1.0,
        tonumber(marker.g) or 0.85,
        tonumber(marker.b) or 0.2,
        tonumber(marker.a) or 1.0
    )
    symbol:setScale((ISMap and ISMap.SCALE or 1) * (tonumber(marker.scale) or 1.0))
    symbol:setVisible(true)
end

local function buildMarkerSignature(marker)
    if not marker then
        return "none"
    end

    return table.concat({
        tostring(marker.questID),
        tostring(marker.x),
        tostring(marker.y),
        tostring(marker.z),
        tostring(marker.symbolID),
        tostring(marker.description),
    }, "|")
end

function MapMarkers.RequestFullRefresh()
    MapMarkers.dirty = true
end

function MapMarkers.Refresh(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer()
    if not playerObj or not DO.Quests or not DO.Quests.GetTrackedMarkerData then
        return
    end

    local symbols = getSymbolsAPI(playerObj)
    if not symbols then
        return
    end

    local marker = DO.Quests.GetTrackedMarkerData(playerObj)
    local signature = buildMarkerSignature(marker)
    if not MapMarkers.dirty and signature == MapMarkers.lastSignature then
        return
    end

    clearOwnedSymbols(symbols)
    if marker then
        drawTrackedMarker(symbols, marker)
    end

    MapMarkers.lastSignature = signature
    MapMarkers.dirty = false
end

function MapMarkers.OnTick()
    MapMarkers.updateCounter = (tonumber(MapMarkers.updateCounter) or 0) + 1
    if MapMarkers.updateCounter < 30 then
        return
    end
    MapMarkers.updateCounter = 0
    MapMarkers.Refresh()
end

Events.OnTick.Add(MapMarkers.OnTick)
