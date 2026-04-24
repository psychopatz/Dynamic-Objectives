require "ISUI/ISUIElement"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.ClearIndicators = DynamicObjectives.ClearIndicators or {}

local DO = DynamicObjectives
local ClearIndicators = DO.ClearIndicators
local Resolver = DO.ZombieTargetResolver or {}

ClearIndicators.updateCounter = ClearIndicators.updateCounter or 0
ClearIndicators.dirty = true
ClearIndicators.lastSignature = ClearIndicators.lastSignature or "none"
ClearIndicators.trackPool = ClearIndicators.trackPool or {}
ClearIndicators.MAX_TRACKS = ClearIndicators.MAX_TRACKS or 6
ClearIndicators.MIN_DISTANCE = ClearIndicators.MIN_DISTANCE or 1.5
ClearIndicators.INDICATOR_HALF_WIDTH = ClearIndicators.INDICATOR_HALF_WIDTH or 50
ClearIndicators.INDICATOR_HALF_HEIGHT = ClearIndicators.INDICATOR_HALF_HEIGHT or 100
ClearIndicators.textureNames = ClearIndicators.textureNames or {
    far = "media/textures/Zomb1W.png",
    medium = "media/textures/Zomb2W.png",
    near = "media/textures/Zomb3W.png",
    pointBlank = "media/textures/Zomb4W.png",
}

DO_ZombieDirectionTrack = DO_ZombieDirectionTrack or ISUIElement:derive("DO_ZombieDirectionTrack")

local function isLivingZombie(zombie)
    return zombie and not zombie:isDead() and (not zombie.getHealth or tonumber(zombie:getHealth()) == nil or tonumber(zombie:getHealth()) > 0)
end

local function getScreenCenter()
    local core = getCore and getCore() or nil
    if not core then
        return 0, 0
    end

    return core:getScreenWidth() / 2, core:getScreenHeight() / 2
end

local function distanceToPoint(playerObj, x, y)
    if not playerObj then
        return math.huge
    end

    return IsoUtils.DistanceTo(
        tonumber(playerObj:getX()) or 0,
        tonumber(playerObj:getY()) or 0,
        tonumber(x) or 0,
        tonumber(y) or 0
    )
end

local function getDistanceColor(distance)
    if distance <= 5 then
        return { r = 1.0, g = 0.08, b = 0.26, a = 0.96 }
    end
    if distance <= 10 then
        return { r = 0.99, g = 0.73, b = 0.04, a = 0.94 }
    end
    if distance <= 20 then
        return { r = 0.15, g = 1.0, b = 0.54, a = 0.92 }
    end
    return { r = 0.47, g = 0.83, b = 0.99, a = 0.9 }
end

local function buildSignature(state)
    if not state or not state.quest then
        return "none"
    end

    local parts = {
        tostring(state.quest.id),
        tostring(state.status or "none"),
        tostring(#(state.targets or {})),
        tostring(state.message or ""),
    }

    for index, entry in ipairs(state.targets or {}) do
        parts[#parts + 1] = string.format(
            "%d:%s:%d:%d:%d:%0.2f",
            index,
            tostring(entry.kind or "none"),
            math.floor(tonumber(entry.x) or 0),
            math.floor(tonumber(entry.y) or 0),
            math.floor(tonumber(entry.z) or 0),
            tonumber(entry.distance) or 0
        )
    end

    return table.concat(parts, "|")
end

function DO_ZombieDirectionTrack:initialise()
    ISUIElement.initialise(self)
    self:addToUIManager()
    self.javaObject:setWantKeyEvents(false)
    self.javaObject:setConsumeMouseEvents(false)
    self.CurrentDist = math.huge
    self.TargetObject = nil
    self.targetX = nil
    self.targetY = nil
    self.targetZ = nil
    self.kind = nil
    self:setVisible(false)
end

function DO_ZombieDirectionTrack:onMouseMove(dx, dy)
    return false
end

function DO_ZombieDirectionTrack:onMouseUp(x, y)
    return false
end

function DO_ZombieDirectionTrack:onRightMouseUp(x, y)
    return false
end

function DO_ZombieDirectionTrack:onMouseDown(x, y)
    return false
end

function DO_ZombieDirectionTrack:onRightMouseDown(x, y)
    return false
end

function DO_ZombieDirectionTrack:onRightMouseDownOutside(x, y)
    return false
end

function DO_ZombieDirectionTrack:onRightMouseUpOutside(x, y)
    return false
end

function DO_ZombieDirectionTrack:UpdateTextures()
    self.Dist1 = getTexture(ClearIndicators.textureNames.far)
    self.Dist2 = getTexture(ClearIndicators.textureNames.medium)
    self.Dist3 = getTexture(ClearIndicators.textureNames.near)
    self.Dist4 = getTexture(ClearIndicators.textureNames.pointBlank)
end

function DO_ZombieDirectionTrack:clearTarget()
    self.TargetObject = nil
    self.targetX = nil
    self.targetY = nil
    self.targetZ = nil
    self.CurrentDist = math.huge
    self.angle = 0
    self.kind = nil
    self:setVisible(false)
end

function DO_ZombieDirectionTrack:isVisibleTarget()
    if self.TargetObject then
        return isLivingZombie(self.TargetObject)
    end

    return self.targetX ~= nil and self.targetY ~= nil
end

function DO_ZombieDirectionTrack:isSameEntry(entry)
    if not entry then
        return false
    end

    if entry.zombie then
        return self.TargetObject == entry.zombie
    end

    return self.TargetObject == nil
        and math.floor(tonumber(self.targetX) or 0) == math.floor(tonumber(entry.x) or 0)
        and math.floor(tonumber(self.targetY) or 0) == math.floor(tonumber(entry.y) or 0)
        and math.floor(tonumber(self.targetZ) or 0) == math.floor(tonumber(entry.z) or 0)
end

function DO_ZombieDirectionTrack:isReusableForDistance(distance)
    if not self:isVisibleTarget() then
        return true
    end

    return (tonumber(self.CurrentDist) or math.huge) > (tonumber(distance) or math.huge)
end

function DO_ZombieDirectionTrack:setAngleFromPoint(x, y)
    if not self.playerObj or x == nil or y == nil then
        return
    end

    local radians = math.atan2(y - self.playerObj:getY(), x - self.playerObj:getX()) + (math.pi * 1.25)
    local degrees = ((radians * 180 / math.pi + 270)) % 360
    degrees = degrees + math.sin((2 / 57.2958) * degrees) * 13
    self.angle = degrees
end

function DO_ZombieDirectionTrack:setTarget(playerObj, entry)
    if not playerObj or not entry then
        self:clearTarget()
        return
    end

    self.playerObj = playerObj
    self.TargetObject = entry.zombie
    self.targetX = tonumber(entry.x) or (entry.zombie and tonumber(entry.zombie:getX()) or nil)
    self.targetY = tonumber(entry.y) or (entry.zombie and tonumber(entry.zombie:getY()) or nil)
    self.targetZ = tonumber(entry.z) or (entry.zombie and tonumber(entry.zombie:getZ()) or 0) or 0
    self.kind = tostring(entry.kind or "live")
    self.CurrentDist = tonumber(entry.distance) or distanceToPoint(playerObj, self.targetX, self.targetY)
    self:setAngleFromPoint(self.targetX, self.targetY)
    self:setVisible(self.CurrentDist > ClearIndicators.MIN_DISTANCE)
end

function DO_ZombieDirectionTrack:refreshTarget()
    if not self.playerObj then
        self:clearTarget()
        return false
    end

    if self.TargetObject then
        if isLivingZombie(self.TargetObject) ~= true then
            self:clearTarget()
            return false
        end
        self.targetX = self.TargetObject:getX()
        self.targetY = self.TargetObject:getY()
        self.targetZ = self.TargetObject:getZ()
    elseif self.targetX == nil or self.targetY == nil then
        self:clearTarget()
        return false
    end

    self.CurrentDist = distanceToPoint(self.playerObj, self.targetX, self.targetY)
    self:setAngleFromPoint(self.targetX, self.targetY)
    self:setVisible(self.CurrentDist > ClearIndicators.MIN_DISTANCE)
    return true
end

function DO_ZombieDirectionTrack:render()
    if not self:isVisibleTarget() then
        return
    end

    if not self.Dist1 then
        self:UpdateTextures()
    end

    if not self:refreshTarget() then
        return
    end

    if self.CurrentDist <= ClearIndicators.MIN_DISTANCE then
        return
    end

    local centerX, centerY = getScreenCenter()
    self:setX(centerX)
    self:setY(centerY)

    local textureToUse = self.Dist1
    local rgba = getDistanceColor(self.CurrentDist)
    if self.CurrentDist <= 5 then
        textureToUse = self.Dist4
    elseif self.CurrentDist <= 10 then
        textureToUse = self.Dist3
    elseif self.CurrentDist <= 20 then
        textureToUse = self.Dist2
    end

    if not textureToUse then
        return
    end

    local scaleW = ClearIndicators.INDICATOR_HALF_WIDTH
    local scaleH = ClearIndicators.INDICATOR_HALF_HEIGHT
    local angCos = math.cos(self.angle / 57.2958)
    local angSin = math.sin(self.angle / 57.2958)

    local tlx0 = -scaleW
    local tly0 = -scaleH
    local trx0 = scaleW
    local try0 = -scaleH
    local brx0 = scaleW
    local bry0 = scaleH
    local blx0 = -scaleW
    local bly0 = scaleH

    local tlx1 = tlx0 * angCos - tly0 * angSin
    local tly1 = tlx0 * angSin + tly0 * angCos
    local trx1 = trx0 * angCos - try0 * angSin
    local try1 = trx0 * angSin + try0 * angCos
    local brx1 = brx0 * angCos - bry0 * angSin
    local bry1 = brx0 * angSin + bry0 * angCos
    local blx1 = blx0 * angCos - bly0 * angSin
    local bly1 = blx0 * angSin + bly0 * angCos

    self:drawPolygon(textureToUse, tlx1, tly1, trx1, try1, brx1, bry1, blx1, bly1, rgba.r, rgba.g, rgba.b, rgba.a)
end

function DO_ZombieDirectionTrack:new(playerObj)
    local centerX, centerY = getScreenCenter()
    local o = ISUIElement:new(centerX, centerY, 0, 0)
    setmetatable(o, self)
    self.__index = self
    o.playerObj = playerObj
    o.TargetObject = nil
    o.targetX = nil
    o.targetY = nil
    o.targetZ = nil
    o.CurrentDist = math.huge
    o.angle = 0
    o.kind = nil
    o.bConsumeMouseEvents = false
    o:UpdateTextures()
    return o
end

local function ensureTrackPool(playerObj)
    for index = 1, ClearIndicators.MAX_TRACKS do
        if not ClearIndicators.trackPool[index] then
            local track = DO_ZombieDirectionTrack:new(playerObj)
            track:initialise()
            ClearIndicators.trackPool[index] = track
        else
            ClearIndicators.trackPool[index].playerObj = playerObj
            if not ClearIndicators.trackPool[index].Dist1 then
                ClearIndicators.trackPool[index]:UpdateTextures()
            end
        end
    end
end

local function clearTrackPool()
    for _, track in ipairs(ClearIndicators.trackPool or {}) do
        track:clearTarget()
    end
end

local function assignTargets(playerObj, targets)
    ensureTrackPool(playerObj)

    for _, entry in ipairs(targets or {}) do
        local placed = false

        for _, track in ipairs(ClearIndicators.trackPool) do
            if track:isSameEntry(entry) then
                track:setTarget(playerObj, entry)
                placed = true
                break
            end
        end

        if not placed then
            for _, track in ipairs(ClearIndicators.trackPool) do
                if track:isReusableForDistance(entry.distance) then
                    track:setTarget(playerObj, entry)
                    placed = true
                    break
                end
            end
        end
    end

    for _, track in ipairs(ClearIndicators.trackPool) do
        local matched = false
        for _, entry in ipairs(targets or {}) do
            if track:isSameEntry(entry) then
                matched = true
                break
            end
        end
        if not matched then
            track:clearTarget()
        end
    end
end

function ClearIndicators.RequestFullRefresh()
    ClearIndicators.dirty = true
end

function ClearIndicators.Clear()
    clearTrackPool()
    ClearIndicators.lastSignature = "none"
    ClearIndicators.dirty = false
end

function ClearIndicators.Refresh(playerObj)
    playerObj = playerObj or DO.GetLocalPlayer()
    if not playerObj or not Resolver.ResolveLocatedQuestTargets then
        ClearIndicators.Clear()
        return
    end

    local state = Resolver.ResolveLocatedQuestTargets(playerObj)
    local signature = buildSignature(state)
    if not ClearIndicators.dirty and signature == ClearIndicators.lastSignature then
        return
    end

    if not state or not state.quest or #(state.targets or {}) <= 0 then
        ClearIndicators.Clear()
        return
    end

    assignTargets(playerObj, state.targets)
    ClearIndicators.lastSignature = signature
    ClearIndicators.dirty = false
end

function ClearIndicators.OnTick()
    ClearIndicators.updateCounter = (tonumber(ClearIndicators.updateCounter) or 0) + 1
    if ClearIndicators.updateCounter < 4 then
        return
    end

    ClearIndicators.updateCounter = 0
    ClearIndicators.Refresh()
end

Events.OnTick.Add(ClearIndicators.OnTick)
