DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.MapMarkers = DynamicObjectives.MapMarkers or {}

local registered = false

local function registerTexture(symbolID, path)
    if not MapSymbolDefinitions or not MapSymbolDefinitions.getInstance then
        return
    end

    MapSymbolDefinitions.getInstance():addTexture(symbolID, path, "Locations")
end

if not registered then
    registerTexture("DOQuestTarget", "media/ui/Map/quest_target.png")
    registerTexture("DOQuestTurnIn", "media/ui/Map/quest_target.png")
    registered = true
end
