require "ISUI/ISPanel"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_ObjectiveHUD = ISPanel:derive("DO_ObjectiveHUD")
DO_ObjectiveHUD.instance = DO_ObjectiveHUD.instance or nil

local DO = DynamicObjectives

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

local function drawProgressBar(panel, x, y, width, ratio, color)
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
    panel:drawRect(x, y, width, 6, 0.25, 0, 0, 0)
    panel:drawRectBorder(x, y, width, 6, 0.35, 1, 1, 1)
    panel:drawRect(x + 1, y + 1, math.max(0, (width - 2) * ratio), 4, 0.8, color.r, color.g, color.b)
end

local function measureText(font, text)
    local manager = getTextManager and getTextManager() or nil
    if not manager then
        return 0
    end
    return manager:MeasureStringX(font, tostring(text or ""))
end

local function drawStrike(panel, x, y, width, color)
    panel:drawRect(x, y, math.max(0, width), 1, 0.92, color.r, color.g, color.b)
end

function DO_ObjectiveHUD:initialise()
    ISPanel.initialise(self)
end

function DO_ObjectiveHUD:createChildren()
    ISPanel.createChildren(self)
end

function DO_ObjectiveHUD:isExpanded()
    return self.data ~= nil and (self.pinnedOpen == true or self.mouseOver == true)
end

function DO_ObjectiveHUD:syncLayout()
    local core = getCore and getCore() or nil
    if not core then
        return
    end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local scale = clamp(screenW / 1920, 0.85, 1.2)
    local lineCount = self.data and #(self.data.lines or {}) or 0
    local extraRows = self.data and self.data.difficultyLabel and self.data.difficultyLabel ~= "" and 1 or 0
    local collapsedSize = clamp(math.floor(42 * scale), 38, 52)
    local expandedWidth = clamp(math.floor(screenW * 0.23), 300, 430)
    local expandedHeight = math.max(
        math.floor(220 * scale),
        math.floor((176 + (lineCount * 28) + (extraRows * 18)) * scale)
    )
    local expanded = self:isExpanded()

    self.collapsedSize = collapsedSize
    self.expandedWidth = expandedWidth
    self.expandedHeight = expandedHeight

    self:setWidth(expanded and expandedWidth or collapsedSize)
    self:setHeight(expanded and expandedHeight or collapsedSize)
    self:setX(screenW - self.width - math.floor(18 * scale))
    self:setY(math.max(72, math.floor(screenH * 0.1)))
end

function DO_ObjectiveHUD:syncFromQuest()
    local player = getLocalPlayer()
    local data = player and DO.Quests and DO.Quests.GetTrackedObjectiveUIData and DO.Quests.GetTrackedObjectiveUIData(player) or nil
    self.data = data
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

function DO_ObjectiveHUD:onMouseMove(dx, dy)
    if self.mouseOver ~= true then
        self.mouseOver = true
        self:syncLayout()
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function DO_ObjectiveHUD:onMouseMoveOutside(dx, dy)
    if self.mouseOver ~= false then
        self.mouseOver = false
        self:syncLayout()
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function DO_ObjectiveHUD:onMouseUp(x, y)
    if not self.data then
        return false
    end

    self.pinnedOpen = not self.pinnedOpen
    self:syncLayout()
    return true
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
    self:drawRect(0, 0, self.width, 34, 0.92, 0.11, 0.12, 0.14)
end

function DO_ObjectiveHUD:renderCollapsed()
    local icon = self.iconTexture
    local pad = 6
    local iconSize = self.width - (pad * 2)
    if icon then
        self:drawTextureScaled(icon, pad, pad, iconSize, iconSize, 1, 1, 1, 1)
    else
        self:drawTextCentre("OBJ", self.width / 2, 11, 0.95, 0.82, 0.52, 1, UIFont.Small)
    end

    self:drawRect(self.width - 12, 4, 8, 8, 0.95, 0.95, 0.42, 0.18)
end

function DO_ObjectiveHUD:renderExpanded()
    local x = 14
    local y = 8
    local titleRight = self.width - 14
    local icon = self.iconTexture

    if icon then
        self:drawTextureScaled(icon, x, 5, 22, 22, 1, 1, 1, 1)
    end

    self:drawText("OBJECTIVE TRACKER", x + 28, y, 0.95, 0.82, 0.52, 0.98, UIFont.Small)
    self:drawTextRight(
        self.pinnedOpen == true and "CLICK TO UNPIN" or "HOVER OR CLICK TO PIN",
        titleRight,
        y,
        0.78,
        0.8,
        0.82,
        0.96,
        UIFont.Small
    )

    y = 40
    self:drawTextRight(
        string.format("STEP %d / %d", tonumber(self.data.currentStep) or 1, tonumber(self.data.totalSteps) or 1),
        titleRight,
        y,
        0.86,
        0.88,
        0.9,
        0.98,
        UIFont.Small
    )
    self:drawText(self.data.name or "Objective", x, y, 1, 1, 1, 0.98, UIFont.Medium)
    y = y + 22

    if self.data.targetLabel and self.data.targetLabel ~= "" then
        self:drawText(self.data.targetLabel, x, y, 0.84, 0.86, 0.9, 0.9, UIFont.Small)
        y = y + 18
    end

    if self.data.difficultyLabel and self.data.difficultyLabel ~= "" then
        self:drawText(
            string.format("Threat: %s  x%.2f", tostring(self.data.difficultyLabel), tonumber(self.data.difficulty) or 1.0),
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

    if self.data.currentObjectiveLabel and self.data.currentObjectiveLabel ~= "" then
        self:drawText(
            "Current: " .. tostring(self.data.currentObjectiveLabel),
            x,
            y,
            0.97,
            0.72,
            0.42,
            0.96,
            UIFont.Small
        )
        y = y + 20
    end

    local progress = self.data.primaryProgress
    if progress then
        self:drawRect(x, y, self.width - 28, 48, 0.24, 0.16, 0.18, 0.21)
        self:drawRectBorder(x, y, self.width - 28, 48, 0.22, 0.9, 0.9, 0.9)
        self:drawText(tostring(progress.label or "Progress"), x + 10, y + 7, 0.78, 0.82, 0.9, 0.95, UIFont.Small)
        self:drawTextRight(tostring(progress.value or ""), self.width - 24, y + 6, 1, 1, 1, 0.98, UIFont.Medium)
        self:drawText(tostring(progress.detail or ""), x + 10, y + 25, 0.82, 0.84, 0.86, 0.88, UIFont.Small)
        drawProgressBar(self, x + 10, y + 40, self.width - 48, progress.ratio or 0, progress.color or { r = 0.86, g = 0.28, b = 0.22 })
        y = y + 62
    end

    self:drawText("Checklist", x, y, 0.92, 0.94, 0.98, 0.94, UIFont.Small)
    y = y + 18

    for _, line in ipairs(self.data.lines or {}) do
        local rowTop = y - 2
        local rowHeight = 24
        local checkboxX = x
        local textX = checkboxX + 22
        local valueText = tostring(line.value or "")
        local labelText = tostring(line.label or "Step")

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
    o.mouseOver = false
    o.pinnedOpen = false
    o.iconTexture = getTexture("media/ui/Icon_MarketInfo.png")
    o:setVisible(false)
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
