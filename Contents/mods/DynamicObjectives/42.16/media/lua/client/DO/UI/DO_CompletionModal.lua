require "ISUI/ISPanel"
require "ISUI/ISButton"

DynamicObjectives = DynamicObjectives or {}
DynamicObjectives.UI = DynamicObjectives.UI or {}

DO_CompletionModal = ISPanel:derive("DO_CompletionModal")
DO_CompletionModal.instance = DO_CompletionModal.instance or nil
DO_CompletionModal.lastCompletedQuestID = DO_CompletionModal.lastCompletedQuestID or nil
DO_CompletionModal.lastCompletedAt = DO_CompletionModal.lastCompletedAt or 0
DO_CompletionModal.initializedCompletionBaseline = DO_CompletionModal.initializedCompletionBaseline or false
DO_CompletionModal.sessionStartedAt = DO_CompletionModal.sessionStartedAt or 0

local DO = DynamicObjectives

local function trimText(value, limit)
    local text = tostring(value or "")
    limit = math.max(4, math.floor(tonumber(limit) or 40))
    if #text <= limit then
        return text
    end
    return text:sub(1, limit - 3) .. "..."
end

local function getItemDisplayName(itemType)
    local value = tostring(itemType or "")
    if value == "" then
        return "Loot"
    end

    local manager = (ScriptManager and ScriptManager.instance) or (getScriptManager and getScriptManager()) or nil
    if manager and manager.getItem then
        local scriptItem = manager:getItem(value)
        if scriptItem and scriptItem.getDisplayName then
            return tostring(scriptItem:getDisplayName() or value)
        end
    end

    return tostring(value:match("([^%.]+)$") or value)
end

local function getItemTexture(itemType)
    if not getTexture then
        return nil
    end

    local shortType = tostring(itemType or ""):match("([^%.]+)$")
    if shortType and shortType ~= "" then
        local texture = getTexture("Item_" .. shortType)
        if texture then
            return texture
        end
    end

    return getTexture("Item_Money")
end

local function buildRewardSummary(quest)
    local summary = {
        money = 0,
        reputation = 0,
        lootCount = 0,
        lootLines = {},
        firstItemType = nil,
    }

    for _, reward in ipairs(quest and quest.rewards or {}) do
        if type(reward) == "table" then
            if reward.kind == "money" then
                summary.money = summary.money + math.max(0, math.floor(tonumber(reward.amount) or 0))
            elseif reward.kind == "reputation" then
                summary.reputation = summary.reputation + math.floor(tonumber(reward.amount) or 0)
            elseif reward.kind == "item" then
                local count = math.max(1, math.floor(tonumber(reward.count) or 1))
                local itemType = tostring(reward.itemType or "")
                summary.lootCount = summary.lootCount + count
                summary.firstItemType = summary.firstItemType or itemType
                summary.lootLines[#summary.lootLines + 1] = tostring(count) .. "x " .. getItemDisplayName(itemType)
            end
        end
    end

    return summary
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
    self:drawRect(0, 0, self.width, self.height, 0.72, 0.03, 0.035, 0.03)
    self:drawRectBorder(0, 0, self.width, self.height, 0.65, 1, 1, 1)
end

function DO_CompletionModal:drawRewardCard(x, y, w, h, title, value, detail, color, texture)
    color = color or { r = 0.75, g = 0.85, b = 1.0 }
    self:drawRect(x, y, w, h, 0.55, 0.08, 0.08, 0.08)
    self:drawRectBorder(x, y, w, h, 0.45, color.r, color.g, color.b)

    local iconX = x + 10
    local iconY = y + 12
    local iconSize = 34
    if texture then
        self:drawTextureScaled(texture, iconX, iconY, iconSize, iconSize, 0.95, 1, 1, 1)
    else
        self:drawRect(iconX, iconY, iconSize, iconSize, 0.35, color.r, color.g, color.b)
        self:drawRectBorder(iconX, iconY, iconSize, iconSize, 0.6, color.r, color.g, color.b)
        self:drawTextCentre(tostring(title or "?"):sub(1, 1), iconX + (iconSize / 2), iconY + 9, 1, 1, 1, 1, UIFont.Small)
    end

    self:drawText(tostring(title or ""), x + 52, y + 9, color.r, color.g, color.b, 1, UIFont.Small)
    self:drawText(tostring(value or ""), x + 52, y + 27, 0.98, 0.98, 0.92, 1, UIFont.Medium)
    if detail and tostring(detail) ~= "" then
        self:drawText(tostring(detail), x + 52, y + 52, 0.72, 0.76, 0.72, 1, UIFont.Small)
    end
end

function DO_CompletionModal:render()
    local y = 16
    self:drawTextCentre("Objective Complete", self.width / 2, y, 0.98, 0.98, 0.92, 1, UIFont.Medium)
    y = y + 30

    self:drawTextCentre(trimText(self.questName or "Completed", 54), self.width / 2, y, 0.68, 0.9, 1.0, 1, UIFont.Small)
    y = y + 30

    local summary = self.rewardSummary or {}
    local lootValue = summary.lootCount and summary.lootCount > 0 and (tostring(summary.lootCount) .. " item" .. (summary.lootCount == 1 and "" or "s")) or "No loot"
    local lootDetail = trimText(summary.lootLines and summary.lootLines[1] or "Contract record updated", 42)
    local moneyValue = "$" .. tostring(math.max(0, tonumber(summary.money) or 0))
    local repAmount = math.floor(tonumber(summary.reputation) or 0)
    local repValue = repAmount >= 0 and ("+" .. tostring(repAmount)) or tostring(repAmount)

    self:drawRewardCard(18, y, self.width - 36, 74, "LOOT", lootValue, lootDetail, { r = 0.66, g = 0.88, b = 0.42 }, self.lootTexture)
    y = y + 82
    self:drawRewardCard(18, y, (self.width - 46) / 2, 70, "CASH", moneyValue, "Paid to inventory", { r = 0.95, g = 0.86, b = 0.34 }, self.moneyTexture)
    self:drawRewardCard(28 + ((self.width - 46) / 2), y, (self.width - 46) / 2, 70, "REP", repValue, "Faction standing", { r = 0.44, g = 0.76, b = 1.0 }, nil)

    y = y + 82
    for index, line in ipairs(self.bodyLines or {}) do
        if index <= 2 then
            self:drawTextCentre(line, self.width / 2, y, 0.8, 0.82, 0.78, 0.94, UIFont.Small)
            y = y + 16
        end
    end
end

function DO_CompletionModal:applyQuest(quest)
    self.questID = quest and quest.id or nil
    self.questName = quest and quest.name or "Completed"
    self.rewardSummary = buildRewardSummary(quest)
    self.lootTexture = getItemTexture(self.rewardSummary and self.rewardSummary.firstItemType or nil)
    self.moneyTexture = getTexture and getTexture("Item_Money") or nil
    self.bodyLines = {
        "Collected from the reward contact.",
        "The contract is cleared.",
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
    o.rewardSummary = {}
    o.lootTexture = nil
    o.moneyTexture = nil
    return o
end

function DO_CompletionModal.Open(quest)
    local modal = DO_CompletionModal.instance
    if not modal then
        modal = DO_CompletionModal:new(0, 0, 430, 290)
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
        DO_CompletionModal.initializedCompletionBaseline = true
        return
    end

    local completedAt = tonumber(quest.completedAt) or 0
    if DO_CompletionModal.sessionStartedAt <= 0 and DO.NowMs then
        DO_CompletionModal.sessionStartedAt = tonumber(DO.NowMs()) or 0
    end

    if DO_CompletionModal.initializedCompletionBaseline ~= true then
        DO_CompletionModal.initializedCompletionBaseline = true
        DO_CompletionModal.lastCompletedQuestID = quest.id
        DO_CompletionModal.lastCompletedAt = completedAt
        return
    end

    if DO_CompletionModal.sessionStartedAt > 0 and completedAt < DO_CompletionModal.sessionStartedAt then
        DO_CompletionModal.lastCompletedQuestID = quest.id
        DO_CompletionModal.lastCompletedAt = math.max(completedAt, tonumber(DO_CompletionModal.lastCompletedAt) or 0)
        return
    end

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
