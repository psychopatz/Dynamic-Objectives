require "ISUI/ISPanel"
require "DO/UI/DO_MissionViewerWindow"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_ObjectiveHUD = ISPanel:derive("DO_ObjectiveHUD")
DO_ObjectiveHUD.instance = DO_ObjectiveHUD.instance or nil

local DO = DynamicObjectives
local SETTINGS_FILE = "DynamicObjectives_UI.txt"
local SETTINGS_SECTION = "objective_tracker"
local HEADER_HEIGHT = 34
local DRAG_THRESHOLD = 4

local function T(key, fallback, params)
    if DO and DO.Text and DO.Text.Get then
        return DO.Text.Get(key, params, fallback)
    end
    if type(params) == "table" and fallback then
        return (tostring(fallback):gsub("{([%w_]+)}", function(name)
            local value = params[name]
            return value == nil and ("{" .. name .. "}") or tostring(value)
        end))
    end
    return fallback or key
end

local function getLocalPlayer()
    if DO.GetLocalPlayer then
        return DO.GetLocalPlayer()
    end
    if getSpecificPlayer then
        return getSpecificPlayer(0)
    end
    return getPlayer and getPlayer() or nil
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function measureText(font, text)
    local manager = getTextManager and getTextManager() or nil
    if not manager then
        return 0
    end
    return manager:MeasureStringX(font, tostring(text or ""))
end

local function drawProgressBar(panel, x, y, width, ratio, color)
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
    panel:drawRect(x, y, width, 6, 0.25, 0, 0, 0)
    panel:drawRectBorder(x, y, width, 6, 0.35, 1, 1, 1)
    panel:drawRect(x + 1, y + 1, math.max(0, (width - 2) * ratio), 4, 0.8, color.r, color.g, color.b)
end

local function drawStrike(panel, x, y, width, color)
    panel:drawRect(x, y, math.max(0, width), 1, 0.92, color.r, color.g, color.b)
end

local function formatRemainingHours(hours)
    local value = tonumber(hours)
    if not value then
        return nil
    end

    local totalMinutes = math.max(0, math.floor((value * 60) + 0.5))
    local wholeHours = math.floor(totalMinutes / 60)
    local minutes = totalMinutes % 60
    if wholeHours <= 0 then
        return T("DOCommon_UI_ObjectiveHUD_MinutesRemaining", "{minutes}m remaining", {
            minutes = minutes
        })
    end
    if minutes <= 0 then
        return T("DOCommon_UI_ObjectiveHUD_HoursRemaining", "{hours}h remaining", {
            hours = wholeHours
        })
    end
    return T("DOCommon_UI_ObjectiveHUD_HoursMinutesRemaining", "{hours}h {minutes}m remaining", {
        hours = wholeHours,
        minutes = minutes,
    })
end

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and y >= rect.y
        and x <= (rect.x + rect.w)
        and y <= (rect.y + rect.h)
end

local function parsePair(value)
    if not value or value == "" then
        return nil, nil
    end

    local parts = {}
    for part in string.gmatch(tostring(value), "([^,]+)") do
        parts[#parts + 1] = tonumber(part)
    end

    if #parts ~= 2 or not parts[1] or not parts[2] then
        return nil, nil
    end

    return math.floor(parts[1]), math.floor(parts[2])
end

function DO_ObjectiveHUD:loadPersistedState()
    self.persisted = {
        collapsedX = nil,
        collapsedY = nil,
        expandedX = nil,
        expandedY = nil,
        pinnedOpen = false,
    }

    local reader = getFileReader and getFileReader(SETTINGS_FILE, false) or nil
    if not reader then
        return
    end

    local prefix = SETTINGS_SECTION .. "."
    local line = reader:readLine()
    while line do
        local key, value = string.match(line, "^([^=]+)=(.*)$")
        if key and value and string.sub(key, 1, #prefix) == prefix then
            local field = string.sub(key, #prefix + 1)
            if field == "collapsed" then
                self.persisted.collapsedX, self.persisted.collapsedY = parsePair(value)
            elseif field == "expanded" then
                self.persisted.expandedX, self.persisted.expandedY = parsePair(value)
            elseif field == "pinned" then
                self.persisted.pinnedOpen = tostring(value) == "true"
            end
        end
        line = reader:readLine()
    end
    reader:close()
end

function DO_ObjectiveHUD:savePersistedState()
    if not self.persisted or not getFileWriter then
        return
    end

    if self.persisted.collapsedX == nil or self.persisted.collapsedY == nil then
        self.persisted.collapsedX, self.persisted.collapsedY = self:getDefaultCollapsedPosition()
    end
    if self.persisted.expandedX == nil or self.persisted.expandedY == nil then
        self.persisted.expandedX, self.persisted.expandedY = self:getDefaultExpandedPosition()
    end

    local writer = getFileWriter(SETTINGS_FILE, true, false)
    if not writer then
        return
    end

    writer:write(string.format("%s.collapsed=%d,%d\r\n", SETTINGS_SECTION, math.floor(self.persisted.collapsedX or 0), math.floor(self.persisted.collapsedY or 0)))
    writer:write(string.format("%s.expanded=%d,%d\r\n", SETTINGS_SECTION, math.floor(self.persisted.expandedX or 0), math.floor(self.persisted.expandedY or 0)))
    writer:write(string.format("%s.pinned=%s\r\n", SETTINGS_SECTION, tostring(self.pinnedOpen == true)))
    writer:close()
end

function DO_ObjectiveHUD:getPinTexture()
    if self.pinnedOpen == true then
        return self.toggleOnOverTexture or self.toggleOnTexture
    end
    return self.toggleOffOverTexture or self.toggleOffTexture
end

function DO_ObjectiveHUD:initialise()
    ISPanel.initialise(self)
end

function DO_ObjectiveHUD:createChildren()
    ISPanel.createChildren(self)
end

function DO_ObjectiveHUD:isExpanded()
    return self.data ~= nil and (self.windowOpen == true or self.pinnedOpen == true)
end

function DO_ObjectiveHUD:measureExpandedSize()
    local core = getCore and getCore() or nil
    if not core then
        return 360, 240
    end

    local screenW = core:getScreenWidth()
    local xPad = 14
    local bodyWidth = 300
    local data = self.data or {}
    local locateLabel = data.located == true
        and T("DOCommon_UI_ObjectiveHUD_Unlocate", "UNLOCATE")
        or T("DOCommon_UI_ObjectiveHUD_Locate", "LOCATE")
    local locateWidth = math.max(74, measureText(UIFont.Small, locateLabel) + 18)
    local missionsWidth = math.max(82, measureText(UIFont.Small, T("DOCommon_UI_ObjectiveHUD_Missions", "MISSIONS")) + 18)
    local pinWidth = 34
    local baseHeaderWidth = 64 + locateWidth + missionsWidth + pinWidth + 18

    bodyWidth = math.max(bodyWidth, measureText(UIFont.Medium, data.title or data.name or T("DOCommon_UI_ObjectiveHUD_Objective", "Objective")) + baseHeaderWidth)
    if data.giverName and data.giverName ~= "" then
        bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, tostring(data.giverName) .. " - " .. tostring(data.giverFactionName or T("DOCommon_UI_ObjectiveHUD_Independent", "Independent"))) + 40)
    end
    bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, tostring(data.chainSummary or "")) + 40)
    bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, tostring(data.targetLabel or "")) + 40)
    bodyWidth = math.max(
        bodyWidth,
        measureText(
            UIFont.Small,
            T("DOCommon_UI_ObjectiveHUD_Threat", "Threat: {label}  x{difficulty}", {
                label = tostring(data.difficultyLabel or T("DOCommon_UI_ObjectiveHUD_Unknown", "Unknown")),
                difficulty = string.format("%.2f", tonumber(data.difficulty) or 1.0)
            })
        ) + 40
    )

    if tonumber(data.timeLimitHours) and tonumber(data.timeLimitHours) > 0 then
        bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, T("DOCommon_UI_ObjectiveHUD_Expires", "Expires: {value}", {
            value = tostring(formatRemainingHours(data.timeRemainingHours) or T("DOCommon_UI_ObjectiveHUD_Expired", "Expired"))
        })) + 40)
    end
    if data.rewardPreview and data.rewardPreview ~= "" then
        bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, T("DOCommon_UI_ObjectiveHUD_Rewards", "Rewards: {value}", {
            value = tostring(data.rewardPreview)
        })) + 40)
    end
    if data.currentObjectiveLabel and data.currentObjectiveLabel ~= "" then
        bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, T("DOCommon_UI_ObjectiveHUD_Current", "Current: {value}", {
            value = tostring(data.currentObjectiveLabel)
        })) + 40)
    end
    if data.primaryProgress then
        bodyWidth = math.max(
            bodyWidth,
            measureText(UIFont.Small, tostring(data.primaryProgress.label or T("DOCommon_UI_ObjectiveHUD_Progress", "Progress")))
                + measureText(UIFont.Medium, tostring(data.primaryProgress.value or ""))
                + 80
        )
        bodyWidth = math.max(bodyWidth, measureText(UIFont.Small, tostring(data.primaryProgress.detail or "")) + 60)
    end

    for _, line in ipairs(data.lines or {}) do
        local rowWidth = 44
            + measureText(UIFont.Small, tostring(line.label or T("DOCommon_UI_MissionViewer_Objective", "Objective")))
            + measureText(UIFont.Small, tostring(line.value or ""))
            + 40
        bodyWidth = math.max(bodyWidth, rowWidth)
    end

    local width = clamp(bodyWidth + (xPad * 2), 320, math.min(520, screenW - 40))
    local height = 52 + 24
    if data.chainSummary and data.chainSummary ~= "" then
        height = height + 18
    end
    if data.giverName and data.giverName ~= "" then
        height = height + 18
    end
    if data.targetLabel and data.targetLabel ~= "" then
        height = height + 18
    end
    if data.difficultyLabel and data.difficultyLabel ~= "" then
        height = height + 18
    end
    if tonumber(data.timeLimitHours) and tonumber(data.timeLimitHours) > 0 then
        height = height + 18
    end
    if data.rewardPreview and data.rewardPreview ~= "" then
        height = height + 18
    end
    if data.currentObjectiveLabel and data.currentObjectiveLabel ~= "" then
        height = height + 20
    end
    if data.primaryProgress then
        height = height + 62
    end
    height = height + 18 + (#(data.lines or {}) * 28)
    height = clamp(height + 16, 220, 700)

    return width, height
end

function DO_ObjectiveHUD:getDefaultCollapsedPosition()
    local core = getCore and getCore() or nil
    if not core then
        return 20, 72
    end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local scale = clamp(screenW / 1920, 0.85, 1.2)
    return screenW - self.collapsedSize - math.floor(18 * scale), math.max(72, math.floor(screenH * 0.1))
end

function DO_ObjectiveHUD:getDefaultExpandedPosition()
    local core = getCore and getCore() or nil
    if not core then
        return 20, 72
    end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local scale = clamp(screenW / 1920, 0.85, 1.2)
    return screenW - self.expandedWidth - math.floor(18 * scale), math.max(72, math.floor(screenH * 0.1))
end

function DO_ObjectiveHUD:clampPosition(x, y, width, height)
    local core = getCore and getCore() or nil
    if not core then
        return x, y
    end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local maxX = math.max(0, screenW - width - 8)
    local maxY = math.max(0, screenH - height - 8)
    return clamp(math.floor(x or 0), 0, maxX), clamp(math.floor(y or 0), 0, maxY)
end

function DO_ObjectiveHUD:getAnchoredPosition(expanded)
    local width = expanded and self.expandedWidth or self.collapsedSize
    local height = expanded and self.expandedHeight or self.collapsedSize
    local posX, posY

    if expanded then
        posX = self.persisted and self.persisted.expandedX or nil
        posY = self.persisted and self.persisted.expandedY or nil
        if posX == nil or posY == nil then
            posX, posY = self:getDefaultExpandedPosition()
        end
    else
        posX = self.persisted and self.persisted.collapsedX or nil
        posY = self.persisted and self.persisted.collapsedY or nil
        if posX == nil or posY == nil then
            posX, posY = self:getDefaultCollapsedPosition()
        end
    end

    return self:clampPosition(posX, posY, width, height)
end

function DO_ObjectiveHUD:storeCurrentPosition()
    if not self.persisted then
        return
    end

    if self:isExpanded() then
        self.persisted.expandedX = math.floor(self:getX())
        self.persisted.expandedY = math.floor(self:getY())
    else
        self.persisted.collapsedX = math.floor(self:getX())
        self.persisted.collapsedY = math.floor(self:getY())
    end
end

function DO_ObjectiveHUD:syncLayout()
    local core = getCore and getCore() or nil
    if not core then
        return
    end

    local screenW = core:getScreenWidth()
    local scale = clamp(screenW / 1920, 0.85, 1.2)
    local collapsedSize = clamp(math.floor(42 * scale), 38, 52)
    local expandedWidth, expandedHeight = self:measureExpandedSize()
    local expanded = self:isExpanded()

    self.collapsedSize = collapsedSize
    self.expandedWidth = expandedWidth
    self.expandedHeight = expandedHeight

    local width = expanded and expandedWidth or collapsedSize
    local height = expanded and expandedHeight or collapsedSize
    self:setWidth(width)
    self:setHeight(height)

    if not self.isDragging then
        local x, y = self:getAnchoredPosition(expanded)
        self:setX(x)
        self:setY(y)
    else
        local x, y = self:clampPosition(self:getX(), self:getY(), width, height)
        self:setX(x)
        self:setY(y)
    end
end

function DO_ObjectiveHUD:syncFromQuest()
    local player = getLocalPlayer()
    local data = player and DO.Quests and DO.Quests.GetTrackedObjectiveUIData and DO.Quests.GetTrackedObjectiveUIData(player) or nil
    self.data = data
    self.hitAreas = {}
    if not data then
        self.windowOpen = false
    end
    self:setVisible(data ~= nil)
    self:syncLayout()
end

function DO_ObjectiveHUD:update()
    ISPanel.update(self)
    self.refreshTick = (tonumber(self.refreshTick) or 0) + 1
    if self.refreshTick >= 10 then
        self.refreshTick = 0
        self:syncFromQuest()
    else
        self:syncLayout()
    end
end

function DO_ObjectiveHUD:onLocateQuest()
    local player = getLocalPlayer()
    if player and self.data and self.data.questID and DO.Quests and DO.Quests.ToggleLocatedQuest then
        DO.Quests.ToggleLocatedQuest(player, self.data.questID)
        self:syncFromQuest()
    end
end

function DO_ObjectiveHUD:onOpenMissionViewer()
    if DO_MissionViewerWindow and DO_MissionViewerWindow.OnOpen then
        DO_MissionViewerWindow.OnOpen()
    end
end

function DO_ObjectiveHUD:onTogglePinned()
    self.pinnedOpen = not self.pinnedOpen
    if self.pinnedOpen == true then
        self.windowOpen = true
    end
    self:savePersistedState()
    self:syncLayout()
end

function DO_ObjectiveHUD:isDragZone(x, y)
    if not self.data then
        return false
    end

    if not self:isExpanded() then
        return true
    end

    if y > HEADER_HEIGHT then
        return false
    end

    return not pointInRect(x, y, self.hitAreas.locate)
        and not pointInRect(x, y, self.hitAreas.missions)
        and not pointInRect(x, y, self.hitAreas.pin)
end

function DO_ObjectiveHUD:beginDragCandidate()
    self.dragPending = true
    self.dragAccumX = 0
    self.dragAccumY = 0
    self.isDragging = false
    if self.setCapture then
        self:setCapture(true)
    end
end

function DO_ObjectiveHUD:updateDrag(dx, dy)
    if self.dragPending ~= true then
        return false
    end

    self.dragAccumX = (tonumber(self.dragAccumX) or 0) + (tonumber(dx) or 0)
    self.dragAccumY = (tonumber(self.dragAccumY) or 0) + (tonumber(dy) or 0)

    if self.isDragging ~= true then
        if math.abs(self.dragAccumX) < DRAG_THRESHOLD and math.abs(self.dragAccumY) < DRAG_THRESHOLD then
            return false
        end
        self.isDragging = true
    end

    local nextX, nextY = self:clampPosition(self:getX() + (tonumber(dx) or 0), self:getY() + (tonumber(dy) or 0), self.width, self.height)
    self:setX(nextX)
    self:setY(nextY)
    self:storeCurrentPosition()
    return true
end

function DO_ObjectiveHUD:endDrag()
    local wasDragging = self.isDragging == true
    self.dragPending = false
    self.isDragging = false
    self.dragAccumX = 0
    self.dragAccumY = 0
    if self.setCapture then
        self:setCapture(false)
    end
    if wasDragging then
        self:savePersistedState()
    end
    return wasDragging
end

function DO_ObjectiveHUD:handleClick(x, y)
    if not self.data then
        return false
    end

    if self:isExpanded() then
        if pointInRect(x, y, self.hitAreas.locate) then
            self:onLocateQuest()
            return true
        end
        if pointInRect(x, y, self.hitAreas.missions) then
            self:onOpenMissionViewer()
            return true
        end
        if pointInRect(x, y, self.hitAreas.pin) then
            self:onTogglePinned()
            return true
        end
        if self.pinnedOpen ~= true then
            self.windowOpen = false
            self:syncLayout()
            return true
        end
        return true
    end

    self.windowOpen = true
    self:syncLayout()
    return true
end

function DO_ObjectiveHUD:onMouseDown(x, y)
    if not self.data then
        return false
    end

    if self:isDragZone(x, y) then
        self:beginDragCandidate()
        return true
    end

    return true
end

function DO_ObjectiveHUD:onMouseMove(dx, dy)
    if self:updateDrag(dx, dy) then
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function DO_ObjectiveHUD:onMouseMoveOutside(dx, dy)
    if self:updateDrag(dx, dy) then
        return true
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function DO_ObjectiveHUD:onMouseUp(x, y)
    if not self.data then
        self:endDrag()
        return false
    end

    if self:endDrag() then
        return true
    end

    return self:handleClick(x, y)
end

function DO_ObjectiveHUD:onMouseUpOutside(x, y)
    self:endDrag()
    return ISPanel.onMouseUpOutside(self, x, y)
end

function DO_ObjectiveHUD:prerender()
    if not self.data then
        return
    end

    if not self:isExpanded() then
        self:drawRect(0, 0, self.width, self.height, 0.88, 0.1, 0.11, 0.13)
        self:drawRectBorder(0, 0, self.width, self.height, 0.7, 0.95, 0.95, 0.95)
        return
    end

    self:drawRect(0, 0, self.width, self.height, 0.78, 0.03, 0.04, 0.05)
    self:drawRectBorder(0, 0, self.width, self.height, 0.55, 0.96, 0.96, 0.96)
    self:drawRect(0, 0, self.width, HEADER_HEIGHT, 0.92, 0.11, 0.12, 0.14)
end

function DO_ObjectiveHUD:drawHeaderButton(x, y, width, height, label, active)
    local fill = active and { r = 0.22, g = 0.36, b = 0.22 } or { r = 0.16, g = 0.16, b = 0.18 }
    local border = active and { r = 0.66, g = 0.92, b = 0.66 } or { r = 0.84, g = 0.84, b = 0.84 }
    self:drawRect(x, y, width, height, 0.92, fill.r, fill.g, fill.b)
    self:drawRectBorder(x, y, width, height, 0.6, border.r, border.g, border.b)
    self:drawTextCentre(label, x + (width / 2), y + 4, 0.96, 0.96, 0.96, 0.98, UIFont.Small)
end

function DO_ObjectiveHUD:drawPinToggle(x, y, width, height)
    local texture = self:getPinTexture()
    if texture then
        self:drawTextureScaled(texture, x + 5, y + 3, width - 10, height - 6, 0.98, 1, 1, 1)
        return
    end

    local fill = self.pinnedOpen == true and { r = 0.3, g = 0.8, b = 0.34 } or { r = 0.42, g = 0.42, b = 0.42 }
    self:drawRect(x + 6, y + 6, width - 12, height - 12, 0.95, fill.r, fill.g, fill.b)
end

function DO_ObjectiveHUD:renderCollapsed()
    local icon = self.iconTexture
    local pad = 6
    local iconSize = self.width - (pad * 2)
    if icon then
        self:drawTextureScaled(icon, pad, pad, iconSize, iconSize, 1, 1, 1, 1)
    else
        self:drawTextCentre(T("DOCommon_UI_ObjectiveHUD_HeaderShort", "OBJ"), self.width / 2, 11, 0.95, 0.82, 0.52, 1, UIFont.Small)
    end

    local dot = self.data and self.data.located == true and { r = 0.36, g = 0.84, b = 0.48 } or { r = 0.95, g = 0.95, b = 0.42 }
    self:drawRect(self.width - 12, 4, 8, 8, 0.95, dot.r, dot.g, dot.b)
end

function DO_ObjectiveHUD:renderExpanded()
    local x = 14
    local y = 8
    local titleRight = self.width - 14
    local icon = self.iconTexture
    local locateLabel = self.data.located == true
        and T("DOCommon_UI_ObjectiveHUD_Unlocate", "UNLOCATE")
        or T("DOCommon_UI_ObjectiveHUD_Locate", "LOCATE")
    local locateWidth = math.max(74, measureText(UIFont.Small, locateLabel) + 18)
    local missionsWidth = math.max(82, measureText(UIFont.Small, T("DOCommon_UI_ObjectiveHUD_Missions", "MISSIONS")) + 18)
    local pinWidth = 34
    local buttonY = 5
    local buttonH = 22
    local locateX = titleRight - locateWidth
    local missionsX = locateX - 6 - missionsWidth
    local pinX = missionsX - 6 - pinWidth

    self.hitAreas = {
        pin = { x = pinX, y = buttonY, w = pinWidth, h = buttonH },
        missions = { x = missionsX, y = buttonY, w = missionsWidth, h = buttonH },
        locate = { x = locateX, y = buttonY, w = locateWidth, h = buttonH },
    }

    if icon then
        self:drawTextureScaled(icon, x, 5, 22, 22, 1, 1, 1, 1)
    end

    self:drawText(T("DOCommon_UI_ObjectiveHUD_Header", "OBJECTIVE TRACKER"), x + 28, y, 0.95, 0.82, 0.52, 0.98, UIFont.Small)
    self:drawPinToggle(pinX, buttonY, pinWidth, buttonH)
    self:drawHeaderButton(missionsX, buttonY, missionsWidth, buttonH, T("DOCommon_UI_ObjectiveHUD_Missions", "MISSIONS"), false)
    self:drawHeaderButton(locateX, buttonY, locateWidth, buttonH, locateLabel, self.data.located == true)

    y = 40
    self:drawTextRight(
        T("DOCommon_UI_ObjectiveHUD_Step", "STEP {current} / {total}", {
            current = tonumber(self.data.currentStep) or 1,
            total = tonumber(self.data.totalSteps) or 1,
        }),
        titleRight,
        y,
        0.86,
        0.88,
        0.9,
        0.98,
        UIFont.Small
    )
    self:drawText(self.data.title or self.data.name or T("DOCommon_UI_ObjectiveHUD_Objective", "Objective"), x, y, 1, 1, 1, 0.98, UIFont.Medium)
    y = y + 22

    if self.data.chainSummary and self.data.chainSummary ~= "" then
        self:drawText(self.data.chainSummary, x, y, 0.66, 0.84, 1.0, 0.94, UIFont.Small)
        y = y + 18
    end

    if self.data.giverName and self.data.giverName ~= "" then
        self:drawText(
            tostring(self.data.giverName) .. " - " .. tostring(self.data.giverFactionName or T("DOCommon_UI_ObjectiveHUD_Independent", "Independent")),
            x,
            y,
            0.72,
            0.84,
            0.98,
            0.94,
            UIFont.Small
        )
        y = y + 18
    end

    if self.data.targetLabel and self.data.targetLabel ~= "" then
        self:drawText(self.data.targetLabel, x, y, 0.84, 0.86, 0.9, 0.9, UIFont.Small)
        y = y + 18
    end

    if self.data.difficultyLabel and self.data.difficultyLabel ~= "" then
        self:drawText(
            T("DOCommon_UI_ObjectiveHUD_Threat", "Threat: {label}  x{difficulty}", {
                label = tostring(self.data.difficultyLabel),
                difficulty = string.format("%.2f", tonumber(self.data.difficulty) or 1.0)
            }),
            x,
            y,
            0.92,
            0.84,
            0.62,
            0.94,
            UIFont.Small
        )
        y = y + 18
    end

    if tonumber(self.data.timeLimitHours) and tonumber(self.data.timeLimitHours) > 0 then
        local remainingText = formatRemainingHours(self.data.timeRemainingHours) or T("DOCommon_UI_ObjectiveHUD_Expired", "Expired")
        local timeColor = { r = 0.72, g = 0.86, b = 0.98 }
        if tonumber(self.data.timeRemainingHours) and tonumber(self.data.timeRemainingHours) <= 1 then
            timeColor = { r = 0.98, g = 0.56, b = 0.42 }
        end
        self:drawText(T("DOCommon_UI_ObjectiveHUD_Expires", "Expires: {value}", {
            value = remainingText
        }), x, y, timeColor.r, timeColor.g, timeColor.b, 0.94, UIFont.Small)
        y = y + 18
    end

    if self.data.rewardPreview and self.data.rewardPreview ~= "" then
        self:drawText(T("DOCommon_UI_ObjectiveHUD_Rewards", "Rewards: {value}", {
            value = tostring(self.data.rewardPreview)
        }), x, y, 0.72, 0.9, 0.72, 0.94, UIFont.Small)
        y = y + 18
    end

    if self.data.currentObjectiveLabel and self.data.currentObjectiveLabel ~= "" then
        self:drawText(T("DOCommon_UI_ObjectiveHUD_Current", "Current: {value}", {
            value = tostring(self.data.currentObjectiveLabel)
        }), x, y, 0.97, 0.72, 0.42, 0.96, UIFont.Small)
        y = y + 20
    end

    local progress = self.data.primaryProgress
    if progress then
        self:drawRect(x, y, self.width - 28, 48, 0.24, 0.16, 0.18, 0.21)
        self:drawRectBorder(x, y, self.width - 28, 48, 0.22, 0.9, 0.9, 0.9)
        self:drawText(tostring(progress.label or T("DOCommon_UI_ObjectiveHUD_Progress", "Progress")), x + 10, y + 7, 0.78, 0.82, 0.9, 0.95, UIFont.Small)
        self:drawTextRight(tostring(progress.value or ""), self.width - 24, y + 6, 1, 1, 1, 0.98, UIFont.Medium)
        self:drawText(tostring(progress.detail or ""), x + 10, y + 25, 0.82, 0.84, 0.86, 0.88, UIFont.Small)
        drawProgressBar(self, x + 10, y + 40, self.width - 48, progress.ratio or 0, progress.color or { r = 0.86, g = 0.28, b = 0.22 })
        y = y + 62
    end

    self:drawText(T("DOCommon_UI_ObjectiveHUD_Checklist", "Checklist"), x, y, 0.92, 0.94, 0.98, 0.94, UIFont.Small)
    y = y + 18

    for _, line in ipairs(self.data.lines or {}) do
        local rowTop = y - 2
        local rowHeight = 24
        local checkboxX = x
        local textX = checkboxX + 22
        local valueText = tostring(line.value or "")
        local labelText = tostring(line.label or T("DOCommon_UI_MissionViewer_Objective", "Objective"))

        if line.current == true then
            self:drawRect(x - 6, rowTop, self.width - 16, rowHeight, 0.12, 0.95, 0.62, 0.22)
        end

        local boxColor = { r = 0.48, g = 0.48, b = 0.5 }
        local labelColor = { r = 0.78, g = 0.78, b = 0.8 }
        local valueColor = { r = 0.92, g = 0.92, b = 0.94 }

        if line.completed == true then
            boxColor = { r = 0.36, g = 0.84, b = 0.48 }
            labelColor = { r = 0.56, g = 0.88, b = 0.68 }
            valueColor = { r = 0.72, g = 0.96, b = 0.78 }
        elseif line.accent == "warn" then
            boxColor = { r = 0.95, g = 0.62, b = 0.18 }
            labelColor = { r = 1.0, g = 0.82, b = 0.58 }
            valueColor = { r = 1.0, g = 0.9, b = 0.7 }
        elseif line.current == true then
            boxColor = { r = 0.97, g = 0.68, b = 0.24 }
            labelColor = { r = 1.0, g = 0.88, b = 0.72 }
            valueColor = { r = 1.0, g = 0.97, b = 0.9 }
        end

        self:drawRectBorder(checkboxX, y + 4, 12, 12, 0.75, boxColor.r, boxColor.g, boxColor.b)
        if line.completed == true then
            self:drawRect(checkboxX + 2, y + 6, 8, 8, 0.95, boxColor.r, boxColor.g, boxColor.b)
        elseif line.current == true then
            self:drawRect(checkboxX + 3, y + 7, 6, 6, 0.9, boxColor.r, boxColor.g, boxColor.b)
        end

        self:drawText(labelText, textX, y + 1, labelColor.r, labelColor.g, labelColor.b, 0.94, UIFont.Small)
        self:drawTextRight(valueText, self.width - 14, y + 1, valueColor.r, valueColor.g, valueColor.b, 0.94, UIFont.Small)

        if line.completed == true then
            local labelWidth = measureText(UIFont.Small, labelText)
            local valueWidth = measureText(UIFont.Small, valueText)
            drawStrike(self, textX, y + 8, math.max(labelWidth, self.width - textX - valueWidth - 30), labelColor)
        end

        y = y + 28
    end
end

function DO_ObjectiveHUD:render()
    if not self.data then
        return
    end

    if self:isExpanded() then
        self:renderExpanded()
    else
        self:renderCollapsed()
    end
end

function DO_ObjectiveHUD:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.noBackground = true
    o.moveWithMouse = false
    o.refreshTick = 0
    o.data = nil
    o.hitAreas = {}
    o.windowOpen = false
    o.pinnedOpen = false
    o.dragPending = false
    o.isDragging = false
    o.dragAccumX = 0
    o.dragAccumY = 0
    o.iconTexture = getTexture("media/ui/Icon_MarketInfo.png")
    o.toggleOnTexture = getTexture("media/ui/Entity/widget_toggle_on.png")
    o.toggleOnOverTexture = getTexture("media/ui/Entity/widget_toggle_on_over.png")
    o.toggleOffTexture = getTexture("media/ui/Entity/widget_toggle_off.png")
    o.toggleOffOverTexture = getTexture("media/ui/Entity/widget_toggle_off_over.png")
    o:setVisible(false)
    o:setCapture(false)
    o:loadPersistedState()
    o.pinnedOpen = o.persisted and o.persisted.pinnedOpen == true or false
    return o
end

function DO_ObjectiveHUD.Ensure()
    if DO_ObjectiveHUD.instance then
        return DO_ObjectiveHUD.instance
    end

    local hud = DO_ObjectiveHUD:new(0, 0, 360, 240)
    hud:initialise()
    hud:instantiate()
    hud:addToUIManager()
    hud:syncFromQuest()
    DO_ObjectiveHUD.instance = hud
    return hud
end

local function onTick()
    local player = getLocalPlayer()
    if not player then
        return
    end

    local hud = DO_ObjectiveHUD.Ensure()
    if hud and not hud:getIsVisible() then
        hud:syncFromQuest()
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end
