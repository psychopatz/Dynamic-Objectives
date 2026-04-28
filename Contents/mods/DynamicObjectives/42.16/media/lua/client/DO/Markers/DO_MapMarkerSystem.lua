require "ISUI/Maps/ISWorldMap"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.MapMarkers = DynamicObjectives.MapMarkers or {}

local DO = DynamicObjectives
local MapMarkers = DO.MapMarkers
local Resolver = DO.ZombieTargetResolver or {}

MapMarkers.hiddenMaps = MapMarkers.hiddenMaps or {}
MapMarkers.ownedSymbolIDs = MapMarkers.ownedSymbolIDs or {
    DOQuestTarget = true,
    DOQuestTurnIn = true,
    DOQuestZombie = true,
    DOQuestZombie_above = true,
    DOQuestZombie_below = true,
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

local function countOwnedSymbols(symbols)
    if not symbols then
        return 0
    end

    local owned = 0
    for index = symbols:getSymbolCount() - 1, 0, -1 do
        local symbol = symbols:getSymbolByIndex(index)
        if symbol and symbol.getSymbolID then
            local symbolID = symbol:getSymbolID()
            if symbolID and MapMarkers.ownedSymbolIDs[symbolID] then
                owned = owned + 1
            end
        end
    end
    return owned
end

local function getExpectedOwnedSymbolCount(marker, state)
    local expected = marker and 1 or 0
    if state and state.quest then
        expected = expected + #(state.targets or {})
    end
    return expected
end

local function drawSymbol(symbols, symbolID, x, y, rgba, scale)
    if not symbols then
        return nil
    end

    local symbol = symbols:addTexture(
        tostring(symbolID),
        math.floor(tonumber(x) or 0),
        math.floor(tonumber(y) or 0)
    )
    if not symbol then
        return nil
    end

    symbol:setAnchor(0.5, 0.5)
    symbol:setRGBA(
        tonumber(rgba and rgba.r) or 1.0,
        tonumber(rgba and rgba.g) or 1.0,
        tonumber(rgba and rgba.b) or 1.0,
        tonumber(rgba and rgba.a) or 1.0
    )
    symbol:setScale((ISMap and ISMap.SCALE or 1) * (tonumber(scale) or 1.0))
    symbol:setVisible(true)
    return symbol
end

local function drawTrackedMarker(symbols, marker)
    if not marker then
        return
    end

    drawSymbol(
        symbols,
        marker.symbolID or "DOQuestTarget",
        marker.x,
        marker.y,
        {
            r = marker.r,
            g = marker.g,
            b = marker.b,
            a = marker.a,
        },
        marker.scale
    )
end

local function getZombieSymbolID(entryZ, playerZ)
    local symbolID = "DOQuestZombie"
    local ez = math.floor(tonumber(entryZ) or 0)
    local pz = math.floor(tonumber(playerZ) or 0)
    if ez > pz then
        symbolID = symbolID .. "_above"
    elseif ez < pz then
        symbolID = symbolID .. "_below"
    end
    return symbolID
end

local function getZombieColor(state, entry)
    local status = state and state.status or "none"
    if status == "spawn_pending" then
        return { r = 0.96, g = 0.67, b = 0.18, a = 0.92 }
    end
    if status == "unloaded" or status == "unloaded_cached" then
        return { r = 0.78, g = 0.84, b = 0.92, a = 0.88 }
    end
    if entry and entry.kind == "cached" then
        return { r = 0.79, g = 0.87, b = 0.96, a = 0.9 }
    end
    if entry and entry.kind == "zone_sample" then
        return { r = 0.98, g = 0.82, b = 0.31, a = 0.92 }
    end
    if entry and entry.kind == "zone_live" then
        return { r = 0.93, g = 0.52, b = 0.18, a = 0.96 }
    end
    return { r = 0.78, g = 0.10, b = 0.12, a = 0.98 }
end

local function getZombieScale(state, entry)
    if entry and entry.kind == "location" then
        return 0.22
    end
    if state and (state.status == "spawn_pending" or state.status == "unloaded") then
        return 0.24
    end
    return 0.26
end

local function drawZombieMarkers(symbols, playerObj, state)
    if not symbols or not playerObj or not state then
        return
    end

    for _, entry in ipairs(state.targets or {}) do
        drawSymbol(
            symbols,
            getZombieSymbolID(entry.z, playerObj:getZ()),
            entry.x,
            entry.y,
            getZombieColor(state, entry),
            getZombieScale(state, entry)
        )
    end
end

local function buildMarkerSignature(marker, state)
    local parts = {}
    if marker then
        parts[#parts + 1] = table.concat({
            tostring(marker.questID),
            tostring(marker.x),
            tostring(marker.y),
            tostring(marker.z),
            tostring(marker.symbolID),
            tostring(marker.description),
        }, "|")
    else
        parts[#parts + 1] = "marker:none"
    end

    if state and state.quest then
        parts[#parts + 1] = table.concat({
            tostring(state.quest.id),
            tostring(state.status),
            tostring(state.message or ""),
            tostring(#(state.targets or {})),
        }, "|")
        for index, entry in ipairs(state.targets or {}) do
            parts[#parts + 1] = string.format(
                "%d:%s:%d:%d:%d",
                index,
                tostring(entry.kind or "none"),
                math.floor(tonumber(entry.x) or 0),
                math.floor(tonumber(entry.y) or 0),
                math.floor(tonumber(entry.z) or 0)
            )
        end
    else
        parts[#parts + 1] = "zeds:none"
    end

    return table.concat(parts, "||")
end

function MapMarkers.RequestFullRefresh()
    MapMarkers.dirty = true
end

function MapMarkers.Refresh(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer()
    if not playerObj or not DO.Quests or not DO.Quests.GetLocatedMarkerData then
        return
    end

    local symbols = getSymbolsAPI(playerObj)
    if not symbols then
        return
    end

    local marker = DO.Quests.GetLocatedMarkerData(playerObj)
    local state = Resolver.ResolveLocatedQuestTargets and Resolver.ResolveLocatedQuestTargets(playerObj) or nil
    local signature = buildMarkerSignature(marker, state)
    local missingSymbols = countOwnedSymbols(symbols) ~= getExpectedOwnedSymbolCount(marker, state)
    if not MapMarkers.dirty and signature == MapMarkers.lastSignature and missingSymbols ~= true then
        return
    end

    clearOwnedSymbols(symbols)
    if marker then
        drawTrackedMarker(symbols, marker)
    end
    if state and state.quest and #(state.targets or {}) > 0 then
        drawZombieMarkers(symbols, playerObj, state)
    end

    MapMarkers.lastSignature = signature
    MapMarkers.dirty = false
end

function MapMarkers.OnTick()
    MapMarkers.updateCounter = (tonumber(MapMarkers.updateCounter) or 0) + 1
    if MapMarkers.updateCounter < 15 then
        return
    end
    MapMarkers.updateCounter = 0
    MapMarkers.Refresh()
end

Events.OnTick.Add(MapMarkers.OnTick)
