DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.ClearIndicators = DynamicObjectives.ClearIndicators or {}

local DO = DynamicObjectives
local ClearIndicators = DO.ClearIndicators

ClearIndicators.updateCounter = ClearIndicators.updateCounter or 0
ClearIndicators.dirty = true
ClearIndicators.lastSignature = ClearIndicators.lastSignature or "none"
ClearIndicators.activeArrows = ClearIndicators.activeArrows or {}
ClearIndicators.MAX_ARROWS = ClearIndicators.MAX_ARROWS or 6

local function removeArrow(arrow)
    if arrow and arrow.remove then
        arrow:remove()
    end
end

local function buildSignature(data)
    if not data then
        return "none"
    end

    local parts = {
        tostring(data.questID),
        tostring(data.nearbyZombies),
        tostring(data.playerPresent),
    }

    for index, sample in ipairs(data.targetSamples or {}) do
        if index > ClearIndicators.MAX_ARROWS then
            break
        end
        parts[#parts + 1] = string.format(
            "%d:%d:%d:%d",
            index,
            math.floor(tonumber(sample.x) or 0),
            math.floor(tonumber(sample.y) or 0),
            math.floor(tonumber(sample.z) or 0)
        )
    end

    return table.concat(parts, "|")
end

local function getArrowTextureName()
    local texture = getTexture and getTexture("media/ui/Map/quest_target.png") or nil
    return texture and texture:getName() or nil
end

function ClearIndicators.RequestFullRefresh()
    ClearIndicators.dirty = true
end

function ClearIndicators.Clear()
    for index = #ClearIndicators.activeArrows, 1, -1 do
        removeArrow(ClearIndicators.activeArrows[index])
        ClearIndicators.activeArrows[index] = nil
    end

    ClearIndicators.lastSignature = "none"
    ClearIndicators.dirty = false
end

function ClearIndicators.Refresh(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer()
    if not playerObj or not DO.Quests or not DO.Quests.GetTrackedClearanceTargetData then
        ClearIndicators.Clear()
        return
    end

    local data = DO.Quests.GetTrackedClearanceTargetData(playerObj)
    local signature = buildSignature(data)
    if not ClearIndicators.dirty and signature == ClearIndicators.lastSignature then
        return
    end

    local markerManager = getWorldMarkers and getWorldMarkers() or nil
    local addDirectionArrow = markerManager and markerManager.addDirectionArrow or nil
    local textureName = getArrowTextureName()
    if not data or not addDirectionArrow or not textureName then
        ClearIndicators.Clear()
        return
    end

    ClearIndicators.Clear()

    for index, sample in ipairs(data.targetSamples or {}) do
        if index > ClearIndicators.MAX_ARROWS then
            break
        end

        local arrow = markerManager:addDirectionArrow(
            playerObj,
            math.floor(tonumber(sample.x) or 0),
            math.floor(tonumber(sample.y) or 0),
            math.floor(tonumber(sample.z) or 0),
            textureName,
            0.95,
            0.2,
            0.18,
            0.92
        )

        if arrow then
            if arrow.setTexture then
                arrow:setTexture(textureName)
            end
            if arrow.setTexDown then
                arrow:setTexDown(textureName)
            end
            if arrow.setRenderWidth then
                arrow:setRenderWidth(72)
            end
            if arrow.setRenderHeight then
                arrow:setRenderHeight(72)
            end
            ClearIndicators.activeArrows[#ClearIndicators.activeArrows + 1] = arrow
        end
    end

    ClearIndicators.lastSignature = signature
    ClearIndicators.dirty = false
end

function ClearIndicators.OnTick()
    ClearIndicators.updateCounter = (tonumber(ClearIndicators.updateCounter) or 0) + 1
    if ClearIndicators.updateCounter < 20 then
        return
    end

    ClearIndicators.updateCounter = 0
    ClearIndicators.Refresh()
end

Events.OnTick.Add(ClearIndicators.OnTick)
