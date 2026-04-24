DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.MapMarkers = DynamicObjectives.MapMarkers or {}

local registered = false

local function registerTexture(symbolID, path, group)
    if not MapSymbolDefinitions or not MapSymbolDefinitions.getInstance then
        return
    end

    MapSymbolDefinitions.getInstance():addTexture(symbolID, path, group or "Locations")
end

if not registered then
    registerTexture("DOQuestTarget", "media/ui/Map/quest_target.png", "Locations")
    registerTexture("DOQuestTurnIn", "media/ui/Map/quest_target.png", "Locations")
    registerTexture("DOQuestZombie", "media/ui/DOQuestZeds/Zombie.png", "Symbols")
    registerTexture("DOQuestZombie_above", "media/ui/DOQuestZeds/Zombie_above.png", "Symbols")
    registerTexture("DOQuestZombie_below", "media/ui/DOQuestZeds/Zombie_below.png", "Symbols")
    registered = true
end
