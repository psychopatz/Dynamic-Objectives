DynamicObjectives = DynamicObjectives or {}

DO_DebugWindow = ISCollapsableWindow:derive("DO_DebugWindow")
DO_DebugWindow.instance = nil

local function getLocalPlayer()
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

local function getDifficultyStep(value)
    local difficulty = tonumber(value) or 1.0
    if difficulty >= 50 then
        return 10
    elseif difficulty >= 10 then
        return 5
    elseif difficulty >= 5 then
        return 1
    end
    return 0.5
end

function DO_DebugWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function DO_DebugWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local x = 10
    local y = self:titleBarHeight() + 10
    local buttonH = 24
    local gap = 6
    local fullW = self.width - 20
    local halfW = math.floor((fullW - gap) / 2)
    local labelW = 108
    local controlButtonW = 24

    self.lblDifficultyTitle = ISLabel:new(x, y + 4, 18, "Base Difficulty", 1, 1, 1, 1, UIFont.Small, true)
    self.lblDifficultyTitle:initialise()
    self:addChild(self.lblDifficultyTitle)

    self.btnDifficultyDown = ISButton:new(x + labelW, y, controlButtonW, buttonH, "-", self, self.onDecreaseDifficulty)
    self.btnDifficultyDown:initialise()
    self:addChild(self.btnDifficultyDown)

    self.lblDifficultyValue = ISLabel:new(x + labelW + controlButtonW + 8, y + 4, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.lblDifficultyValue:initialise()
    self:addChild(self.lblDifficultyValue)

    self.btnDifficultyUp = ISButton:new(x + fullW - controlButtonW, y, controlButtonW, buttonH, "+", self, self.onIncreaseDifficulty)
    self.btnDifficultyUp:initialise()
    self:addChild(self.btnDifficultyUp)
    y = y + buttonH + gap

    self.lblTimerTitle = ISLabel:new(x, y + 4, 18, "Timer Hours", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTimerTitle:initialise()
    self:addChild(self.lblTimerTitle)

    self.btnTimerDown = ISButton:new(x + labelW, y, controlButtonW, buttonH, "-", self, self.onDecreaseTimer)
    self.btnTimerDown:initialise()
    self:addChild(self.btnTimerDown)

    self.lblTimerValue = ISLabel:new(x + labelW + controlButtonW + 8, y + 4, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTimerValue:initialise()
    self:addChild(self.lblTimerValue)

    self.btnTimerUp = ISButton:new(x + fullW - controlButtonW, y, controlButtonW, buttonH, "+", self, self.onIncreaseTimer)
    self.btnTimerUp:initialise()
    self:addChild(self.btnTimerUp)
    y = y + buttonH + 10

    self.btnKill = ISButton:new(x, y, halfW, buttonH, "Start Kill Zone", self, self.onStartKillQuest)
    self.btnKill:initialise()
    self:addChild(self.btnKill)

    self.btnHunt = ISButton:new(x + halfW + gap, y, halfW, buttonH, "Start Hunt Drop", self, self.onStartHuntQuest)
    self.btnHunt:initialise()
    self:addChild(self.btnHunt)
    y = y + buttonH + gap

    self.btnCourier = ISButton:new(x, y, fullW, buttonH, "Start Courier Run", self, self.onStartCourierQuest)
    self.btnCourier:initialise()
    self:addChild(self.btnCourier)
    y = y + buttonH + 10

    self.lblTracked = ISLabel:new(x, y, 18, "Tracked: None", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTracked:initialise()
    self:addChild(self.lblTracked)
    y = y + 18 + gap

    local footerHeight = (buttonH * 2) + gap + 14
    local listHeight = math.max(120, self.height - y - footerHeight - 14)
    self.activeList = ISScrollingListBox:new(x, y, fullW, listHeight)
    self.activeList:initialise()
    self.activeList:setAnchorLeft(true)
    self.activeList:setAnchorRight(true)
    self.activeList:setAnchorTop(true)
    self.activeList:setAnchorBottom(true)
    self:addChild(self.activeList)
    y = y + listHeight + gap

    self.btnTrack = ISButton:new(x, y, halfW, buttonH, "Track Selected", self, self.onTrackSelected)
    self.btnTrack:initialise()
    self:addChild(self.btnTrack)

    self.btnAbandon = ISButton:new(x + halfW + gap, y, halfW, buttonH, "Abandon Selected", self, self.onAbandonSelected)
    self.btnAbandon:initialise()
    self.btnAbandon.backgroundColor = { r = 0.45, g = 0.1, b = 0.1, a = 1.0 }
    self:addChild(self.btnAbandon)
    y = y + buttonH + gap

    self.btnDump = ISButton:new(x, y, halfW, buttonH, "Dump State", self, self.onDumpState)
    self.btnDump:initialise()
    self:addChild(self.btnDump)

    self.btnRefresh = ISButton:new(x + halfW + gap, y, halfW, buttonH, "Refresh", self, self.onRefreshList)
    self.btnRefresh:initialise()
    self:addChild(self.btnRefresh)

    self.refreshCounter = 0
    self:refreshDebugControls()
    self:refreshQuestList()
end

function DO_DebugWindow:getSelectedQuestID()
    local entry = self.activeList and self.activeList:getItem() or nil
    return entry and entry.item or nil
end

function DO_DebugWindow:refreshQuestList()
    if not self.activeList or not DynamicObjectives or not DynamicObjectives.Quests then
        return
    end

    local player = getLocalPlayer()
    self.activeList:clear()

    local summaries = DynamicObjectives.Quests.GetActiveQuestSummary and DynamicObjectives.Quests.GetActiveQuestSummary(player) or {}
    for _, summary in ipairs(summaries) do
        self.activeList:addItem(summary.display, summary.questID)
    end

    local tracked = DynamicObjectives.Quests.GetTrackedQuest and DynamicObjectives.Quests.GetTrackedQuest(player) or nil
    if self.lblTracked then
        self.lblTracked:setName("Tracked: " .. tostring(tracked and tracked.name or "None"))
    end
end

function DO_DebugWindow:update()
    ISCollapsableWindow.update(self)
    self.refreshCounter = (tonumber(self.refreshCounter) or 0) + 1
    if self.refreshCounter >= 90 then
        self.refreshCounter = 0
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onStartKillQuest()
    local player = getLocalPlayer()
    if player and DynamicObjectives.Quests and DynamicObjectives.Quests.DebugStartKillZoneQuest then
        DynamicObjectives.Quests.DebugStartKillZoneQuest(player, self.debugDifficulty, self.debugTimeLimitHours)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onStartHuntQuest()
    local player = getLocalPlayer()
    if player and DynamicObjectives.Quests and DynamicObjectives.Quests.DebugStartHuntQuest then
        DynamicObjectives.Quests.DebugStartHuntQuest(player, self.debugDifficulty, self.debugTimeLimitHours)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onStartCourierQuest()
    local player = getLocalPlayer()
    if player and DynamicObjectives.Quests and DynamicObjectives.Quests.DebugStartCourierQuest then
        DynamicObjectives.Quests.DebugStartCourierQuest(player, self.debugDifficulty, self.debugTimeLimitHours)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:refreshDebugControls()
    if self.lblDifficultyValue then
        self.lblDifficultyValue:setName(string.format("x%.2f", tonumber(self.debugDifficulty) or 1.0))
    end

    if self.lblTimerValue then
        local hours = math.max(0, math.floor(tonumber(self.debugTimeLimitHours) or 0))
        self.lblTimerValue:setName(hours > 0 and string.format("%dh", hours) or "Off")
    end
end

function DO_DebugWindow:onDecreaseDifficulty()
    local current = tonumber(self.debugDifficulty) or 1.0
    self.debugDifficulty = clamp(current - getDifficultyStep(current), 0.5, 100.0)
    self:refreshDebugControls()
end

function DO_DebugWindow:onIncreaseDifficulty()
    local current = tonumber(self.debugDifficulty) or 1.0
    self.debugDifficulty = clamp(current + getDifficultyStep(current), 0.5, 100.0)
    self:refreshDebugControls()
end

function DO_DebugWindow:onDecreaseTimer()
    self.debugTimeLimitHours = clamp(math.floor((tonumber(self.debugTimeLimitHours) or 0) - 1), 0, 72)
    self:refreshDebugControls()
end

function DO_DebugWindow:onIncreaseTimer()
    self.debugTimeLimitHours = clamp(math.floor((tonumber(self.debugTimeLimitHours) or 0) + 1), 0, 72)
    self:refreshDebugControls()
end

function DO_DebugWindow:onTrackSelected()
    local player = getLocalPlayer()
    local questID = self:getSelectedQuestID()
    if player and questID and DynamicObjectives.Quests and DynamicObjectives.Quests.SetTrackedQuest then
        DynamicObjectives.Quests.SetTrackedQuest(player, questID)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onAbandonSelected()
    local player = getLocalPlayer()
    local questID = self:getSelectedQuestID()
    if player and questID and DynamicObjectives.Quests and DynamicObjectives.Quests.AbandonQuest then
        DynamicObjectives.Quests.AbandonQuest(player, questID)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onDumpState()
    local player = getLocalPlayer()
    if player and DynamicObjectives.Quests and DynamicObjectives.Quests.DumpState then
        DynamicObjectives.Quests.DumpState(player)
    end
end

function DO_DebugWindow:onRefreshList()
    self:refreshQuestList()
end

function DO_DebugWindow.OnOpen()
    if DO_DebugWindow.instance then
        DO_DebugWindow.instance:setVisible(true)
        DO_DebugWindow.instance:bringToTop()
        DO_DebugWindow.instance:refreshQuestList()
        return
    end

    local window = DO_DebugWindow:new(120, 80, 460, 420)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    DO_DebugWindow.instance = window
end

function DO_DebugWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Dynamic Objectives Debug"
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.45 }
    o.debugDifficulty = 1.0
    o.debugTimeLimitHours = 0
    o:setResizable(false)
    return o
end
