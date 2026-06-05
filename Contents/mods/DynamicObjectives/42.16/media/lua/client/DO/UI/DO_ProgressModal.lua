require "ISUI/ISPanel"
require "ISUI/ISButton"
pcall(require, "DO/UI/DO_MissionModalShared")

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_ProgressModal = ISPanel:derive("DO_ProgressModal")
DO_ProgressModal.instance = DO_ProgressModal.instance or nil

local DO = DynamicObjectives
local Shared = DO_MissionModalShared or {}
local PROGRESS_SOUND = "DO_MissionProgress"
local AUTO_CLOSE_MS = 6000
local BOX_ANIM_MS = 260
local ENTRY_STAGGER_MS = 90
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
    if Shared.Clamp then
        return Shared.Clamp(value, minValue, maxValue)
    end
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
    local maxLength = math.max(6, math.floor(tonumber(limit) or 48))
    if #text <= maxLength then
        return text
    end
    return text:sub(1, maxLength - 3) .. "..."
end

local function getNowMs()
    if Shared.GetNowMs then
        return Shared.GetNowMs()
    end
    return DO.NowMs and DO.NowMs() or 0
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

local function buildObjectiveStatus(objective)
    if type(objective) ~= "table" then
        return T("DOCommon_UI_Progress_Pending", "Pending")
    end

    if objective.completed == true then
        return T("DOCommon_UI_Progress_Done", "Done")
    end

    local progress = math.max(0, math.floor(tonumber(objective.progress) or 0))
    local required = math.max(1, math.floor(tonumber(objective.required) or 1))
    if objective.type == "pickupItem" then
        return T("DOCommon_UI_Progress_PendingPickup", "Pending pickup")
    end
    if objective.type == "areaClear" then
        return progress > 0 and T("DOCommon_UI_Progress_Cleared", "{progress} / {required} cleared", {
            progress = progress,
            required = required,
        }) or T("DOCommon_UI_Progress_SecureArea", "Secure the area")
    end
    if objective.type == "claimRewards" then
        return T("DOCommon_UI_Progress_ClaimPayout", "Claim your payout")
    end
    if objective.type == "deliverItem" then
        return T("DOCommon_UI_Progress_Delivered", "{progress} / {required} delivered", { progress = progress, required = required })
    end
    if objective.type == "obtainDrop" then
        return T("DOCommon_UI_Progress_Recovered", "{progress} / {required} recovered", { progress = progress, required = required })
    end
    if objective.type == "kill" then
        return T("DOCommon_UI_Progress_Cleared", "{progress} / {required} cleared", { progress = progress, required = required })
    end
    return T("DOCommon_UI_Progress_Generic", "{progress} / {required}", { progress = progress, required = required })
end

local function buildChecklist(quest)
    local entries = {}
    for index, objective in ipairs(quest and quest.objectives or {}) do
        entries[#entries + 1] = {
            index = index,
            id = tostring(objective.id or ("objective_" .. tostring(index))),
            label = tostring(objective.label or objective.type or T("DOCommon_UI_Progress_Objective", "Objective {index}", {
                index = tostring(index)
            })),
            completed = objective.completed == true,
            status = buildObjectiveStatus(objective),
        }
    end
    return entries
end

local function prioritizeChecklistEntry(entries, objectiveID)
    if type(entries) ~= "table" or #entries <= 1 then
        return entries
    end

    local probe = tostring(objectiveID or "")
    if probe == "" then
        return entries
    end

    for index, entry in ipairs(entries) do
        if tostring(entry and entry.id or "") == probe then
            if index > 1 then
                table.remove(entries, index)
                table.insert(entries, 1, entry)
            end
            break
        end
    end

    return entries
end

local function findObjective(quest, objectiveID)
    local probe = tostring(objectiveID or "")
    for _, objective in ipairs(quest and quest.objectives or {}) do
        if tostring(objective and objective.id or "") == probe then
            return objective
        end
    end
    return nil
end

local function buildSummary(event)
    local quest = type(event and event.quest) == "table" and event.quest or {}
    local objective = {}
    if type(event and event.objective) == "table" then
        objective = event.objective
    else
        objective = findObjective(quest, event and event.objectiveID or nil) or {}
    end
    local giverName = tostring(quest.giverName or T("DOCommon_UI_Progress_MissionContact", "Mission Contact"))
    local factionName = tostring(quest.giverFactionName or T("DOCommon_UI_Progress_Independent", "Independent"))
    local objectiveLabel = tostring(objective.label or objective.id or T("DOCommon_UI_Progress_ObjectiveUpdated", "Objective updated"))
    local highlightedObjectiveID = tostring(objective.id or (event and event.objectiveID) or "")
    local checklist = prioritizeChecklistEntry(buildChecklist(quest), highlightedObjectiveID)

    return {
        title = tostring(quest.title or quest.name or T("DOCommon_UI_Progress_Title", "Mission Progress")),
        objectiveLabel = objectiveLabel,
        giverLine = giverName .. " - " .. factionName,
        objectiveStatus = buildObjectiveStatus(objective),
        checklist = checklist,
        highlightedObjectiveID = highlightedObjectiveID,
    }
end

function DO_ProgressModal:initialise()
    ISPanel.initialise(self)
end

function DO_ProgressModal:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new((self.width - 96) / 2, self.height - 42, 96, 26, T("DOCommon_UI_Close", "Close"), self, self.onCloseButton)
    self.closeButton:initialise()
    self.closeButton.backgroundColor = { r = 0.28, g = 0.22, b = 0.08, a = 0.92 }
    self.closeButton.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self:addChild(self.closeButton)
end

function DO_ProgressModal:onCloseButton()
    self:setVisible(false)
    self:removeFromUIManager()
    self.addedToUIManager = false
    self.autoCloseAt = 0
end

function DO_ProgressModal:prerender()
    local alpha, scale = self:getBoxAnimation()
    local drawW = self.width * scale
    local drawH = self.height * scale
    local drawX = (self.width - drawW) / 2
    local drawY = (self.height - drawH) / 2
    self:drawRect(drawX, drawY, drawW, drawH, 0.92 * alpha, 0.08, 0.07, 0.03)
    self:drawRect(drawX, drawY, drawW, 4, 0.96 * alpha, 0.96, 0.78, 0.28)
    self:drawRectBorder(drawX, drawY, drawW, drawH, 0.76 * alpha, 0.95, 0.8, 0.34)
end

function DO_ProgressModal:drawChecklistEntry(entry, x, y, w, highlight)
    local accent = highlight and { r = 0.98, g = 0.86, b = 0.34 } or { r = 0.82, g = 0.72, b = 0.3 }
    local alpha, offsetY, scale = self:getEntryAnimation((entry and entry.index or 1) + 1)
    local cardAlpha = alpha * (highlight and 0.72 or 0.52)
    local drawW = w * scale
    local drawH = 34 * scale
    local drawX = x + ((w - drawW) / 2)
    local drawY = y + offsetY + ((34 - drawH) / 2)
    self:drawRect(drawX, drawY, drawW, drawH, cardAlpha, 0.14, 0.12, 0.05)
    self:drawRect(drawX, drawY, 4, drawH, 0.95 * alpha, accent.r, accent.g, accent.b)
    self:drawRectBorder(drawX, drawY, drawW, drawH, 0.34 * alpha, accent.r, accent.g, accent.b)

    local marker = entry.completed and T("DOCommon_UI_Progress_MarkerDone", "DONE") or T("DOCommon_UI_Progress_MarkerNext", "NEXT")
    local markerColor = entry.completed and { r = 0.98, g = 0.9, b = 0.42 } or { r = 0.9, g = 0.82, b = 0.5 }
    self:drawText(marker, drawX + 10, drawY + 9, markerColor.r, markerColor.g, markerColor.b, alpha, UIFont.Small)
    self:drawText(trimText(entry.label, 42), drawX + 56, drawY + 7, 0.98, 0.98, 0.94, alpha, UIFont.Small)
    self:drawTextRight(trimText(entry.status, 20), drawX + drawW - 12, drawY + 8, 0.84, 0.82, 0.74, alpha, UIFont.Small)
end

function DO_ProgressModal:render()
    ISPanel.render(self)
    if not self.summary then
        return
    end

    local headerAlpha, headerOffset = self:getEntryAnimation(0)
    local heroAlpha, heroOffset, heroScale = self:getEntryAnimation(1)
    local countdownRatio = self.autoCloseAt and self.autoCloseAt > 0
        and clamp((self.autoCloseAt - getNowMs()) / AUTO_CLOSE_MS, 0, 1)
        or 0

    self:drawTextCentre(T("DOCommon_UI_Progress_Title", "Mission Progress"), self.width / 2, 16 + headerOffset, 0.98, 0.96, 0.84, headerAlpha, UIFont.Medium)
    self:drawTextCentre(trimText(self.summary.title, 50), self.width / 2, 42 + headerOffset, 0.98, 0.9, 0.48, headerAlpha, UIFont.Small)
    self:drawTextCentre(trimText(self.summary.giverLine, 60), self.width / 2, 60 + headerOffset, 0.8, 0.78, 0.68, headerAlpha, UIFont.Small)

    local heroX = 18
    local heroY = 86 + heroOffset
    local heroW = self.width - 36
    local heroH = 64
    local drawHeroW = heroW * heroScale
    local drawHeroH = heroH * heroScale
    local drawHeroX = heroX + ((heroW - drawHeroW) / 2)
    local drawHeroY = heroY + ((heroH - drawHeroH) / 2)

    self:drawRect(drawHeroX, drawHeroY, drawHeroW, drawHeroH, 0.52 * heroAlpha, 0.18, 0.16, 0.05)
    self:drawRect(drawHeroX, drawHeroY, drawHeroW, 3, 0.95 * heroAlpha, 0.98, 0.84, 0.28)
    self:drawRectBorder(drawHeroX, drawHeroY, drawHeroW, drawHeroH, 0.34 * heroAlpha, 0.98, 0.84, 0.28)
    self:drawText(T("DOCommon_UI_Progress_CheckpointReached", "CHECKPOINT REACHED"), drawHeroX + 12, drawHeroY + 12, 0.98, 0.92, 0.42, heroAlpha, UIFont.Small)
    self:drawText(trimText(self.summary.objectiveLabel, 42), drawHeroX + 12, drawHeroY + 32, 0.98, 0.98, 0.94, heroAlpha, UIFont.Medium)
    self:drawTextRight(trimText(self.summary.objectiveStatus, 22), drawHeroX + drawHeroW - 10, drawHeroY + 32, 0.88, 0.84, 0.68, heroAlpha, UIFont.Small)

    self:drawRect(18, 158, self.width - 36, 4, 0.24 * heroAlpha, 0.2, 0.16, 0.08)
    self:drawRect(18, 158, (self.width - 36) * countdownRatio, 4, 0.92 * heroAlpha, 0.98, 0.84, 0.28)

    local listX = 18
    local listY = 176
    local listW = self.width - 36
    local maxEntries = math.min(4, #(self.summary.checklist or {}))
    for index = 1, maxEntries do
        local entry = self.summary.checklist[index]
        self:drawChecklistEntry(
            entry,
            listX,
            listY + ((index - 1) * 40),
            listW,
            tostring(entry.id or "") == tostring(self.summary.highlightedObjectiveID or "")
        )
    end
end

function DO_ProgressModal:applyEvent(event)
    self.summary = buildSummary(event or {})
    self.openedAt = getNowMs()
    self.autoCloseAt = self.openedAt + AUTO_CLOSE_MS
    self.remainingSeconds = math.ceil(AUTO_CLOSE_MS / 1000)
    if self.closeButton and self.closeButton.setTitle then
        self.closeButton:setTitle(T("DOCommon_UI_CloseCountdown", "Close ({seconds})", {
            seconds = tostring(self.remainingSeconds)
        }))
    end
end

function DO_ProgressModal:getBoxAnimation()
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

function DO_ProgressModal:getEntryAnimation(index)
    if Shared.GetEntryAnimation then
        return Shared.GetEntryAnimation(self.openedAt, index, {
            delayMs = 30,
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

function DO_ProgressModal:update()
    ISPanel.update(self)

    if not self:getIsVisible() then
        return
    end

    local remainingMs = math.max(0, math.floor((tonumber(self.autoCloseAt) or 0) - getNowMs()))
    if remainingMs <= 0 then
        self:onCloseButton()
        return
    end

    local remainingSeconds = math.max(1, math.ceil(remainingMs / 1000))
    if remainingSeconds ~= self.remainingSeconds then
        self.remainingSeconds = remainingSeconds
        if self.closeButton and self.closeButton.setTitle then
                self.closeButton:setTitle(T("DOCommon_UI_CloseCountdown", "Close ({seconds})", {
                    seconds = tostring(remainingSeconds)
                }))
            end
        end
end

function DO_ProgressModal:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.summary = nil
    o.openedAt = 0
    o.autoCloseAt = 0
    o.remainingSeconds = 0
    o.addedToUIManager = false
    return o
end

function DO_ProgressModal.OpenFromEvent(event)
    if type(event) ~= "table" or type(event.quest) ~= "table" then
        return nil
    end

    local modal = DO_ProgressModal.instance
    if not modal then
        modal = DO_ProgressModal:new(0, 0, 500, 360)
        modal:initialise()
        modal:instantiate()
        DO_ProgressModal.instance = modal
    end

    modal:setWidth(500)
    modal:setHeight(360)
    modal:applyEvent(event)
    if Shared.CenterModal then
        Shared.CenterModal(modal)
    else
        local core = getCore and getCore() or nil
        if core then
            modal:setX(math.floor((core:getScreenWidth() - modal.width) / 2))
            modal:setY(math.floor((core:getScreenHeight() - modal.height) / 2))
        end
    end
    if modal.closeButton then
        modal.closeButton:setX((modal.width - 96) / 2)
        modal.closeButton:setY(modal.height - 42)
    end

    if modal.addedToUIManager ~= true then
        modal:addToUIManager()
        modal.addedToUIManager = true
    end

    modal:setVisible(true)
    modal:bringToTop()
    if Shared.PlayUISound then
        Shared.PlayUISound(PROGRESS_SOUND, getLocalPlayer())
    end
    return modal
end
