require "ISUI/ISPanel"
require "ISUI/ISButton"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_FailureModal = ISPanel:derive("DO_FailureModal")
DO_FailureModal.instance = DO_FailureModal.instance or nil
DO_FailureModal.lastFailedQuestID = DO_FailureModal.lastFailedQuestID or nil
DO_FailureModal.lastFailedAt = DO_FailureModal.lastFailedAt or 0
DO_FailureModal.initializedFailureBaseline = DO_FailureModal.initializedFailureBaseline or false
DO_FailureModal.sessionStartedAt = DO_FailureModal.sessionStartedAt or 0

local DO = DynamicObjectives
local AUTO_CLOSE_MS = 8000

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function trimText(value, limit)
    local text = tostring(value or "")
    limit = math.max(6, math.floor(tonumber(limit) or 48))
    if #text <= limit then
        return text
    end
    return text:sub(1, limit - 3) .. "..."
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

local function humanizeReason(reason)
    local map = {
        escort_target_incapacitated = "Escort incapacitated",
        escort_target_lost = "Escort target lost",
        reward_contact_unavailable = "Turn-in contact unavailable",
        time_expired = "Contract expired",
        abandoned = "Mission abandoned",
        hook_failed = "Objective hook failed",
        failed = "Mission failed",
    }

    local key = tostring(reason or "")
    if map[key] then
        return map[key]
    end

    key = key:gsub("_", " "):gsub("%s+", " ")
    key = key:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest or "")
    end)
    return key ~= "" and key or "Mission failed"
end

local function buildFailureSummary(quest)
    local detail = DO.Quests and DO.Quests.GetQuestDetailData and DO.Quests.GetQuestDetailData(getLocalPlayer(), quest.id) or nil
    local giverName = tostring((detail and detail.giverName) or quest.giverName or "Unknown Contact")
    local factionName = tostring((detail and detail.giverFactionName) or quest.giverFactionName or "Independent")
    local reason = humanizeReason((detail and detail.failureReason) or quest.failureReason)
    local objectiveLabel = tostring((detail and detail.currentObjectiveLabel) or quest.name or "Mission")
    local stepLine = detail and detail.currentStep and detail.totalSteps
        and string.format("Step %d / %d", math.max(1, tonumber(detail.currentStep) or 1), math.max(1, tonumber(detail.totalSteps) or 1))
        or "Objective failed"

    return {
        title = tostring((detail and detail.title) or quest.title or quest.name or "Mission Failed"),
        giver = giverName,
        faction = factionName,
        reason = reason,
        objective = objectiveLabel,
        stepLine = stepLine,
    }
end

function DO_FailureModal:getNowMs()
    return DO.NowMs and DO.NowMs() or 0
end

function DO_FailureModal:initialise()
    ISPanel.initialise(self)
end

function DO_FailureModal:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new((self.width - 96) / 2, self.height - 44, 96, 26, "Close", self, self.onCloseButton)
    self.closeButton:initialise()
    self.closeButton.backgroundColor = { r = 0.24, g = 0.16, b = 0.16, a = 0.92 }
    self.closeButton.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self:addChild(self.closeButton)
end

function DO_FailureModal:onCloseButton()
    self:setVisible(false)
    self:removeFromUIManager()
    self.addedToUIManager = false
    self.autoCloseAt = 0
end

function DO_FailureModal:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.92, 0.04, 0.03, 0.04)
    self:drawRect(0, 0, self.width, 4, 0.96, 0.82, 0.18, 0.2)
    self:drawRectBorder(0, 0, self.width, self.height, 0.76, 0.88, 0.34, 0.36)
end

function DO_FailureModal:drawCard(x, y, w, h, title, value, detail, color)
    color = color or { r = 0.92, g = 0.38, b = 0.4 }
    self:drawRect(x, y, w, h, 0.54, 0.08, 0.06, 0.07)
    self:drawRect(x, y, w, 3, 0.92, color.r, color.g, color.b)
    self:drawRectBorder(x, y, w, h, 0.42, color.r, color.g, color.b)
    self:drawText(tostring(title or ""), x + 12, y + 10, color.r, color.g, color.b, 1, UIFont.Small)
    self:drawText(trimText(value, 46), x + 12, y + 28, 0.98, 0.96, 0.96, 1, UIFont.Medium)
    if detail and tostring(detail) ~= "" then
        self:drawText(trimText(detail, 62), x + 12, y + h - 24, 0.78, 0.74, 0.74, 1, UIFont.Small)
    end
end

function DO_FailureModal:render()
    ISPanel.render(self)
    if not self.summary then
        return
    end

    local centerX = self.width / 2
    self:drawTextCentre("Objective Failed", centerX, 16, 0.98, 0.98, 0.98, 1, UIFont.Large)
    self:drawTextCentre(trimText(self.summary.title, 48), centerX, 42, 0.8, 0.9, 1.0, 1, UIFont.Medium)

    local infoY = 82
    local cardGap = 12
    local topCardW = math.floor((self.width - 48 - cardGap) / 2)
    local topCardH = 84
    local leftX = 18
    local rightX = leftX + topCardW + cardGap

    self:drawCard(leftX, infoY, topCardW, topCardH, "Failure Reason", self.summary.reason, self.summary.stepLine, { r = 0.9, g = 0.28, b = 0.3 })
    self:drawCard(rightX, infoY, topCardW, topCardH, "Objective", self.summary.objective, "No rewards were paid out.", { r = 0.84, g = 0.42, b = 0.24 })

    local bottomY = infoY + topCardH + 14
    self:drawCard(18, bottomY, self.width - 36, 92, "Contact", self.summary.giver, "Faction: " .. tostring(self.summary.faction or "Independent"), { r = 0.72, g = 0.46, b = 0.5 })
end

function DO_FailureModal:update()
    ISPanel.update(self)

    local nowMs = self:getNowMs()
    if (tonumber(self.autoCloseAt) or 0) > 0 then
        local remaining = math.max(0, math.ceil((tonumber(self.autoCloseAt) - nowMs) / 1000))
        if self.closeButton then
            self.closeButton:setTitle(remaining > 0 and ("Close (" .. tostring(remaining) .. ")") or "Close")
        end
        if nowMs >= tonumber(self.autoCloseAt) then
            self:onCloseButton()
        end
    end
end

function DO_FailureModal:setQuest(quest)
    self.quest = quest
    self.summary = buildFailureSummary(quest or {})
    self.openedAt = self:getNowMs()
    self.autoCloseAt = self.openedAt + AUTO_CLOSE_MS
end

function DO_FailureModal:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = true
    o.quest = nil
    o.summary = nil
    o.openedAt = 0
    o.autoCloseAt = 0
    o.addedToUIManager = false
    return o
end

function DO_FailureModal.Open(quest)
    if not quest then
        return nil
    end

    local core = getCore and getCore() or nil
    local screenW = core and core:getScreenWidth() or 1280
    local screenH = core and core:getScreenHeight() or 720
    local width = 500
    local height = 290
    local x = math.floor((screenW - width) / 2)
    local y = math.floor((screenH - height) / 2)

    if not DO_FailureModal.instance then
        DO_FailureModal.instance = DO_FailureModal:new(x, y, width, height)
        DO_FailureModal.instance:initialise()
        DO_FailureModal.instance:instantiate()
    end

    DO_FailureModal.instance:setX(x)
    DO_FailureModal.instance:setY(y)
    DO_FailureModal.instance:setWidth(width)
    DO_FailureModal.instance:setHeight(height)
    DO_FailureModal.instance:setVisible(true)
    DO_FailureModal.instance:setQuest(quest)
    if DO_FailureModal.instance.closeButton then
        DO_FailureModal.instance.closeButton:setX((width - 96) / 2)
        DO_FailureModal.instance.closeButton:setY(height - 44)
    end

    if DO_FailureModal.instance.addedToUIManager ~= true then
        DO_FailureModal.instance:addToUIManager()
        DO_FailureModal.instance.addedToUIManager = true
    else
        DO_FailureModal.instance:bringToTop()
    end

    return DO_FailureModal.instance
end

local function processLatestFailedQuest(player)
    player = player or getLocalPlayer()
    if not player or not (DO.Quests and DO.Quests.GetLatestFailedQuest) then
        return nil
    end

    local quest = DO.Quests.GetLatestFailedQuest(player)
    if not quest or tonumber(quest.failedAt) == nil then
        if DO_FailureModal.initializedFailureBaseline ~= true then
            DO_FailureModal.initializedFailureBaseline = true
        end
        return nil
    end

    local failedAt = tonumber(quest.failedAt) or 0
    if DO_FailureModal.sessionStartedAt <= 0 and DO.NowMs then
        DO_FailureModal.sessionStartedAt = tonumber(DO.NowMs()) or 0
    end

    if DO_FailureModal.initializedFailureBaseline ~= true then
        DO_FailureModal.initializedFailureBaseline = true
        if DO_FailureModal.sessionStartedAt > 0 and failedAt < DO_FailureModal.sessionStartedAt then
            DO_FailureModal.lastFailedQuestID = quest.id
            DO_FailureModal.lastFailedAt = failedAt
            return nil
        end
    end

    if DO_FailureModal.sessionStartedAt > 0 and failedAt < DO_FailureModal.sessionStartedAt then
        DO_FailureModal.lastFailedQuestID = quest.id
        DO_FailureModal.lastFailedAt = math.max(failedAt, tonumber(DO_FailureModal.lastFailedAt) or 0)
        return nil
    end

    if DO_FailureModal.lastFailedQuestID == quest.id and failedAt <= (DO_FailureModal.lastFailedAt or 0) then
        return nil
    end

    DO_FailureModal.lastFailedQuestID = quest.id
    DO_FailureModal.lastFailedAt = failedAt
    return DO_FailureModal.Open(quest)
end

function DO_FailureModal.ProcessLatestFailedQuest(player)
    return processLatestFailedQuest(player or getLocalPlayer())
end

local function onTick()
    DO_FailureModal.ProcessLatestFailedQuest(getLocalPlayer())
end

local function onGameStart()
    if DO_FailureModal.instance and DO_FailureModal.instance.addedToUIManager == true then
        DO_FailureModal.instance:setVisible(false)
        DO_FailureModal.instance:removeFromUIManager()
        DO_FailureModal.instance.addedToUIManager = false
    end
    DO_FailureModal.sessionStartedAt = 0
    DO_FailureModal.initializedFailureBaseline = false
    DO_FailureModal.lastFailedQuestID = nil
    DO_FailureModal.lastFailedAt = 0
end

if Events then
    if Events.OnTick then
        Events.OnTick.Add(onTick)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(onGameStart)
    end
end
