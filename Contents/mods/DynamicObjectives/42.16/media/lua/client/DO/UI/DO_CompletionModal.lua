require "ISUI/ISPanel"
require "ISUI/ISButton"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_CompletionModal = ISPanel:derive("DO_CompletionModal")
DO_CompletionModal.instance = DO_CompletionModal.instance or nil
DO_CompletionModal.lastCompletedQuestID = DO_CompletionModal.lastCompletedQuestID or nil
DO_CompletionModal.lastCompletedAt = DO_CompletionModal.lastCompletedAt or 0

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

function DO_CompletionModal:initialise()
    ISPanel.initialise(self)
end

function DO_CompletionModal:createChildren()
    ISPanel.createChildren(self)

    local buttonW = 96
    local buttonH = 26
    self.closeButton = ISButton:new((self.width - buttonW) / 2, self.height - buttonH - 18, buttonW, buttonH, "Close", self, self.onCloseButton)
    self.closeButton:initialise()
    self.closeButton.backgroundColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.85 }
    self.closeButton.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
    self:addChild(self.closeButton)
end

function DO_CompletionModal:onCloseButton()
    self:setVisible(false)
    self:removeFromUIManager()
end

function DO_CompletionModal:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.58, 0.04, 0.04, 0.04)
    self:drawRectBorder(0, 0, self.width, self.height, 0.55, 1, 1, 1)
end

function DO_CompletionModal:render()
    local x = 20
    local y = 18
    self:drawTextCentre("Objective Complete", self.width / 2, y, 0.98, 0.98, 0.98, 1, UIFont.Medium)
    y = y + 34

    self:drawTextCentre(tostring(self.questName or "Completed"), self.width / 2, y, 0.86, 0.92, 1.0, 1, UIFont.Small)
    y = y + 26

    for _, line in ipairs(self.bodyLines or {}) do
        self:drawText(line, x, y, 0.9, 0.9, 0.9, 0.94, UIFont.Small)
        y = y + 18
    end
end

function DO_CompletionModal:applyQuest(quest)
    self.questID = quest and quest.id or nil
    self.questName = quest and quest.name or "Completed"
    self.bodyLines = {
        "The marked objective is secure.",
        "No nearby zeds remain and the contract is cleared.",
    }

    local core = getCore and getCore() or nil
    if core then
        self:setX((core:getScreenWidth() - self.width) / 2)
        self:setY((core:getScreenHeight() - self.height) / 2)
    end
end

function DO_CompletionModal:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.noBackground = true
    o.questID = nil
    o.questName = nil
    o.bodyLines = {}
    return o
end

function DO_CompletionModal.Open(quest)
    local modal = DO_CompletionModal.instance
    if not modal then
        modal = DO_CompletionModal:new(0, 0, 360, 180)
        modal:initialise()
        modal:instantiate()
        DO_CompletionModal.instance = modal
    end

    modal:applyQuest(quest)
    modal:addToUIManager()
    modal:setVisible(true)
    modal:bringToTop()
    return modal
end

local function onTick()
    local player = getLocalPlayer()
    if not player or not DO.Quests or not DO.Quests.GetLatestCompletedQuest then
        return
    end

    local quest = DO.Quests.GetLatestCompletedQuest(player)
    if not quest or tonumber(quest.completedAt) == nil then
        return
    end

    local completedAt = tonumber(quest.completedAt) or 0
    if DO_CompletionModal.lastCompletedQuestID == quest.id and completedAt <= (DO_CompletionModal.lastCompletedAt or 0) then
        return
    end

    DO_CompletionModal.lastCompletedQuestID = quest.id
    DO_CompletionModal.lastCompletedAt = completedAt
    DO_CompletionModal.Open(quest)
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end
