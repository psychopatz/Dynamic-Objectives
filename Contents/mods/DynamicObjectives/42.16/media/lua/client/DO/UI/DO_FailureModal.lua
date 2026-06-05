require "ISUI/ISPanel"
require "ISUI/ISButton"
pcall(require, "DO/UI/DO_MissionModalShared")

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_FailureModal = ISPanel:derive("DO_FailureModal")
DO_FailureModal.instance = DO_FailureModal.instance or nil

local DO = DynamicObjectives
local Shared = DO_MissionModalShared or {}
local AUTO_CLOSE_MS = 8000
local BOX_ANIM_MS = 260
local ENTRY_STAGGER_MS = 95
local ENTRY_ANIM_MS = 280

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
    if Shared.TrimText then
        return Shared.TrimText(value, limit, 6)
    end
    local text = tostring(value or "")
    limit = math.max(6, math.floor(tonumber(limit) or 48))
    if #text <= limit then
        return text
    end
    return text:sub(1, limit - 3) .. "..."
end

local function getLocalPlayer()
    if Shared.GetLocalPlayer then
        return Shared.GetLocalPlayer()
    end
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
        escort_target_incapacitated = T("DOCommon_UI_Failure_ReasonEscortIncapacitated", "Escort incapacitated"),
        escort_target_lost = T("DOCommon_UI_Failure_ReasonEscortLost", "Escort target lost"),
        reward_contact_unavailable = T("DOCommon_UI_Failure_ReasonContactUnavailable", "Turn-in contact unavailable"),
        time_expired = T("DOCommon_UI_Failure_ReasonTimeExpired", "Contract expired"),
        abandoned = T("DOCommon_UI_Failure_ReasonAbandoned", "Mission abandoned"),
        hook_failed = T("DOCommon_UI_Failure_ReasonHookFailed", "Objective hook failed"),
        failed = T("DOCommon_UI_Failure_ReasonFailed", "Mission failed"),
    }

    local key = tostring(reason or "")
    if map[key] then
        return map[key]
    end

    key = key:gsub("_", " "):gsub("%s+", " ")
    key = key:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest or "")
    end)
    return key ~= "" and key or T("DOCommon_UI_Failure_MissionFailed", "Mission failed")
end

local function buildFailureSummary(quest)
    local detail = DO.Quests and DO.Quests.GetQuestDetailData and DO.Quests.GetQuestDetailData(getLocalPlayer(), quest.id) or nil
    local giverName = tostring((detail and detail.giverName) or quest.giverName or T("DOCommon_UI_Failure_UnknownContact", "Unknown Contact"))
    local factionName = tostring((detail and detail.giverFactionName) or quest.giverFactionName or T("DOCommon_UI_Failure_Independent", "Independent"))
    local reason = humanizeReason((detail and detail.failureReason) or quest.failureReason)
    local objectiveLabel = tostring((detail and detail.currentObjectiveLabel) or quest.name or T("DOCommon_UI_Failure_Objective", "Mission"))
    local stepLine = detail and detail.currentStep and detail.totalSteps
        and T("DOCommon_UI_Failure_Step", "Step {current} / {total}", {
            current = math.max(1, tonumber(detail.currentStep) or 1),
            total = math.max(1, tonumber(detail.totalSteps) or 1),
        })
        or T("DOCommon_UI_Failure_ObjectiveFailed", "Objective failed")

    return {
        header = tostring(quest.status or "") == "abandoned"
            and T("DOCommon_UI_Failure_HeaderAbandoned", "Objective Abandoned")
            or T("DOCommon_UI_Failure_HeaderFailed", "Objective Failed"),
        title = tostring((detail and detail.title) or quest.title or quest.name or T("DOCommon_UI_Failure_Title", "Mission Failed")),
        giver = giverName,
        faction = factionName,
        reason = reason,
        objective = objectiveLabel,
        stepLine = stepLine,
    }
end

function DO_FailureModal:getNowMs()
    return Shared.GetNowMs and Shared.GetNowMs() or (DO.NowMs and DO.NowMs() or 0)
end

function DO_FailureModal:initialise()
    ISPanel.initialise(self)
end

function DO_FailureModal:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new((self.width - 96) / 2, self.height - 44, 96, 26, T("DOCommon_UI_Close", "Close"), self, self.onCloseButton)
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
    local alpha, scale = self:getBoxAnimation()
    local drawW = self.width * scale
    local drawH = self.height * scale
    local drawX = (self.width - drawW) / 2
    local drawY = (self.height - drawH) / 2
    self:drawRect(drawX, drawY, drawW, drawH, 0.92 * alpha, 0.04, 0.03, 0.04)
    self:drawRect(drawX, drawY, drawW, 4, 0.96 * alpha, 0.82, 0.18, 0.2)
    self:drawRectBorder(drawX, drawY, drawW, drawH, 0.76 * alpha, 0.88, 0.34, 0.36)
end

function DO_FailureModal:drawCard(x, y, w, h, title, value, detail, color)
    color = color or { r = 0.92, g = 0.38, b = 0.4 }
    local animIndex = self.cardAnimIndex or 0
    local alpha, offsetY, scale = self:getEntryAnimation(animIndex)
    local drawW = w * scale
    local drawH = h * scale
    local drawX = x + ((w - drawW) / 2)
    local drawY = y + offsetY + ((h - drawH) / 2)
    self.cardAnimIndex = animIndex + 1

    self:drawRect(drawX, drawY, drawW, drawH, 0.54 * alpha, 0.08, 0.06, 0.07)
    self:drawRect(drawX, drawY, drawW, 3, 0.92 * alpha, color.r, color.g, color.b)
    self:drawRectBorder(drawX, drawY, drawW, drawH, 0.42 * alpha, color.r, color.g, color.b)
    self:drawText(tostring(title or ""), drawX + 12, drawY + 10, color.r, color.g, color.b, alpha, UIFont.Small)
    self:drawText(trimText(value, 46), drawX + 12, drawY + 28, 0.98, 0.96, 0.96, alpha, UIFont.Medium)
    if detail and tostring(detail) ~= "" then
        self:drawText(trimText(detail, 62), drawX + 12, drawY + drawH - 24, 0.78, 0.74, 0.74, alpha, UIFont.Small)
    end
end

function DO_FailureModal:render()
    ISPanel.render(self)
    if not self.summary then
        return
    end

    self.cardAnimIndex = 1
    local headerAlpha, headerOffset = self:getEntryAnimation(0)
    local centerX = self.width / 2
    self:drawTextCentre(tostring(self.summary.header or T("DOCommon_UI_Failure_HeaderFailed", "Objective Failed")), centerX, 16 + headerOffset, 0.98, 0.98, 0.98, headerAlpha, UIFont.Large)
    self:drawTextCentre(trimText(self.summary.title, 48), centerX, 42 + headerOffset, 0.8, 0.9, 1.0, headerAlpha, UIFont.Medium)

    local infoY = 82
    local cardGap = 12
    local topCardW = math.floor((self.width - 48 - cardGap) / 2)
    local topCardH = 84
    local leftX = 18
    local rightX = leftX + topCardW + cardGap

    self:drawCard(leftX, infoY, topCardW, topCardH, T("DOCommon_UI_Failure_FailureReason", "Failure Reason"), self.summary.reason, self.summary.stepLine, { r = 0.9, g = 0.28, b = 0.3 })
    self:drawCard(rightX, infoY, topCardW, topCardH, T("DOCommon_UI_Failure_ObjectiveCard", "Objective"), self.summary.objective, T("DOCommon_UI_Failure_NoRewards", "No rewards were paid out."), { r = 0.84, g = 0.42, b = 0.24 })

    local bottomY = infoY + topCardH + 14
    self:drawCard(18, bottomY, self.width - 36, 92, T("DOCommon_UI_Failure_Contact", "Contact"), self.summary.giver, T("DOCommon_UI_Failure_Faction", "Faction: {value}", {
        value = tostring(self.summary.faction or T("DOCommon_UI_Failure_Independent", "Independent"))
    }), { r = 0.72, g = 0.46, b = 0.5 })
end

function DO_FailureModal:update()
    ISPanel.update(self)

    local nowMs = self:getNowMs()
    if (tonumber(self.autoCloseAt) or 0) > 0 then
        local remaining = math.max(0, math.ceil((tonumber(self.autoCloseAt) - nowMs) / 1000))
        if self.closeButton then
            self.closeButton:setTitle(remaining > 0
                and T("DOCommon_UI_CloseCountdown", "Close ({seconds})", { seconds = tostring(remaining) })
                or T("DOCommon_UI_Close", "Close"))
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

function DO_FailureModal:getBoxAnimation()
    if Shared.GetGrowAnimation then
        return Shared.GetGrowAnimation(self.openedAt, {
            durationMs = BOX_ANIM_MS,
            startScale = 0.88,
            endScale = 1.0,
            travelY = 18,
            startAlpha = 0.24,
        })
    end
    return 1, 1, 0
end

function DO_FailureModal:getEntryAnimation(index)
    if Shared.GetEntryAnimation then
        return Shared.GetEntryAnimation(self.openedAt, index, {
            delayMs = 40,
            staggerMs = ENTRY_STAGGER_MS,
            durationMs = ENTRY_ANIM_MS,
            startScale = 0.93,
            endScale = 1.0,
            travelY = 16,
            startAlpha = 0.18,
        })
    end
    return 1, 0, 1
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

    DO_FailureModal.instance:setWidth(width)
    DO_FailureModal.instance:setHeight(height)
    if Shared.CenterModal then
        Shared.CenterModal(DO_FailureModal.instance)
    else
        DO_FailureModal.instance:setX(x)
        DO_FailureModal.instance:setY(y)
    end
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

function DO_FailureModal.OpenFromEvent(event)
    local quest = type(event) == "table" and event.quest or nil
    if not quest then
        return nil
    end
    return DO_FailureModal.Open(quest)
end

function DO_FailureModal.ProcessLatestFailedQuest(player)
    return Shared.ProcessMissionEvents and Shared.ProcessMissionEvents(player or getLocalPlayer()) or nil
end
