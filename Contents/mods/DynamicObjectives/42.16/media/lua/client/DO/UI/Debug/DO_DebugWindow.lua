DynamicObjectives = DynamicObjectives or {}
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
pcall(require, "DT/Common/UI/ConversationUI/DT_ConversationQuestOffer")
require "DO/UI/DO_MissionViewerWindow"

DO_DebugWindow = ISCollapsableWindow:derive("DO_DebugWindow")
DO_DebugWindow.instance = nil
local TRADER_HELP_HOOK_ID = "TraderNeeds.HelpEscort"

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

local function measureText(font, text)
    local manager = getTextManager and getTextManager() or nil
    if not manager then
        return 0
    end
    return manager:MeasureStringX(font, tostring(text or ""))
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

    self.pad = 10
    self.gap = 6
    self.buttonH = 24
    self.labelW = 108
    self.controlButtonW = 24
    self.summaryWidth = 0

    self.lblDifficultyTitle = ISLabel:new(0, 0, 18, "Base Difficulty", 1, 1, 1, 1, UIFont.Small, true)
    self.lblDifficultyTitle:initialise()
    self:addChild(self.lblDifficultyTitle)

    self.btnDifficultyDown = ISButton:new(0, 0, self.controlButtonW, self.buttonH, "-", self, self.onDecreaseDifficulty)
    self.btnDifficultyDown:initialise()
    self:addChild(self.btnDifficultyDown)

    self.lblDifficultyValue = ISLabel:new(0, 0, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.lblDifficultyValue:initialise()
    self:addChild(self.lblDifficultyValue)

    self.btnDifficultyUp = ISButton:new(0, 0, self.controlButtonW, self.buttonH, "+", self, self.onIncreaseDifficulty)
    self.btnDifficultyUp:initialise()
    self:addChild(self.btnDifficultyUp)

    self.lblTimerTitle = ISLabel:new(0, 0, 18, "Timer Hours", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTimerTitle:initialise()
    self:addChild(self.lblTimerTitle)

    self.btnTimerDown = ISButton:new(0, 0, self.controlButtonW, self.buttonH, "-", self, self.onDecreaseTimer)
    self.btnTimerDown:initialise()
    self:addChild(self.btnTimerDown)

    self.lblTimerValue = ISLabel:new(0, 0, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTimerValue:initialise()
    self:addChild(self.lblTimerValue)

    self.btnTimerUp = ISButton:new(0, 0, self.controlButtonW, self.buttonH, "+", self, self.onIncreaseTimer)
    self.btnTimerUp:initialise()
    self:addChild(self.btnTimerUp)

    self.btnKill = ISButton:new(0, 0, 80, self.buttonH, "Start Kill Zone", self, self.onStartKillQuest)
    self.btnKill:initialise()
    self:addChild(self.btnKill)

    self.btnHunt = ISButton:new(0, 0, 80, self.buttonH, "Start Hunt Drop", self, self.onStartHuntQuest)
    self.btnHunt:initialise()
    self:addChild(self.btnHunt)

    self.btnCourier = ISButton:new(0, 0, 80, self.buttonH, "Start Courier Run", self, self.onStartCourierQuest)
    self.btnCourier:initialise()
    self:addChild(self.btnCourier)

    self.btnRestingChain = ISButton:new(0, 0, 80, self.buttonH, "Start Resting Chain", self, self.onStartRestingChainQuest)
    self.btnRestingChain:initialise()
    self.btnRestingChain.backgroundColor = { r = 0.12, g = 0.3, b = 0.18, a = 1.0 }
    self:addChild(self.btnRestingChain)

    self.btnForceTraderHelp = ISButton:new(0, 0, 80, self.buttonH, "Force Trader Help Escort", self, self.onForceTraderHelpEscort)
    self.btnForceTraderHelp:initialise()
    self.btnForceTraderHelp.backgroundColor = { r = 0.28, g = 0.24, b = 0.12, a = 1.0 }
    self:addChild(self.btnForceTraderHelp)

    self.btnMissionViewer = ISButton:new(0, 0, 80, self.buttonH, "Open Mission Viewer", self, self.onOpenMissionViewer)
    self.btnMissionViewer:initialise()
    self:addChild(self.btnMissionViewer)

    self.btnQuestManager = ISButton:new(0, 0, 80, self.buttonH, "Open Quest Manager", self, self.onOpenQuestManager)
    self.btnQuestManager:initialise()
    self:addChild(self.btnQuestManager)

    self.btnQuestConversation = ISButton:new(0, 0, 80, self.buttonH, "Preview Quest Conversation", self, self.onOpenQuestConversationPreview)
    self.btnQuestConversation:initialise()
    self:addChild(self.btnQuestConversation)

    self.btnMissionCompleteModal = ISButton:new(0, 0, 80, self.buttonH, "Test Completion Modal", self, self.onTestCompletionModal)
    self.btnMissionCompleteModal:initialise()
    self.btnMissionCompleteModal.backgroundColor = { r = 0.1, g = 0.35, b = 0.5, a = 1.0 }
    self:addChild(self.btnMissionCompleteModal)

    self.btnMissionProgressModal = ISButton:new(0, 0, 80, self.buttonH, "Test Progress Modal", self, self.onTestProgressModal)
    self.btnMissionProgressModal:initialise()
    self.btnMissionProgressModal.backgroundColor = { r = 0.48, g = 0.36, b = 0.08, a = 1.0 }
    self:addChild(self.btnMissionProgressModal)

    self.btnMissionFailModal = ISButton:new(0, 0, 80, self.buttonH, "Test Failure Modal", self, self.onTestFailureModal)
    self.btnMissionFailModal:initialise()
    self.btnMissionFailModal.backgroundColor = { r = 0.42, g = 0.16, b = 0.16, a = 1.0 }
    self:addChild(self.btnMissionFailModal)

    self.lblTracked = ISLabel:new(0, 0, 18, "Tracked: None", 1, 1, 1, 1, UIFont.Small, true)
    self.lblTracked:initialise()
    self:addChild(self.lblTracked)

    self.lblLocated = ISLabel:new(0, 0, 18, "Located: None", 1, 1, 1, 1, UIFont.Small, true)
    self.lblLocated:initialise()
    self:addChild(self.lblLocated)

    self.activeList = ISScrollingListBox:new(0, 0, 100, 120)
    self.activeList:initialise()
    self.activeList:setAnchorLeft(true)
    self.activeList:setAnchorRight(true)
    self.activeList:setAnchorTop(true)
    self.activeList:setAnchorBottom(true)
    self:addChild(self.activeList)

    self.btnTrack = ISButton:new(0, 0, 80, self.buttonH, "Track Selected", self, self.onTrackSelected)
    self.btnTrack:initialise()
    self:addChild(self.btnTrack)

    self.btnLocate = ISButton:new(0, 0, 80, self.buttonH, "Locate Selected", self, self.onLocateSelected)
    self.btnLocate:initialise()
    self:addChild(self.btnLocate)

    self.btnAbandon = ISButton:new(0, 0, 80, self.buttonH, "Abandon Selected", self, self.onAbandonSelected)
    self.btnAbandon:initialise()
    self.btnAbandon.backgroundColor = { r = 0.45, g = 0.1, b = 0.1, a = 1.0 }
    self:addChild(self.btnAbandon)

    self.btnDump = ISButton:new(0, 0, 80, self.buttonH, "Dump State", self, self.onDumpState)
    self.btnDump:initialise()
    self:addChild(self.btnDump)

    self.btnRefresh = ISButton:new(0, 0, 80, self.buttonH, "Refresh", self, self.onRefreshList)
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

function DO_DebugWindow:getContentWidth()
    local controlMin = 460
    local buttonTextWidth = math.max(
        measureText(UIFont.Small, "Start Resting Chain"),
        measureText(UIFont.Small, "Force Trader Help Escort"),
        measureText(UIFont.Small, "Open Mission Viewer"),
        measureText(UIFont.Small, "Preview Quest Conversation"),
        measureText(UIFont.Small, "Test Completion Modal"),
        measureText(UIFont.Small, "Test Progress Modal"),
        measureText(UIFont.Small, "Test Failure Modal"),
        measureText(UIFont.Small, "Locate Selected")
    ) + 28
    local rowWidth = (buttonTextWidth * 2) + self.gap + (self.pad * 2)
    local fullRowWidth = buttonTextWidth + (self.pad * 2)
    local labelWidth = self.labelW + self.controlButtonW + measureText(UIFont.Small, string.format("x%.2f", tonumber(self.debugDifficulty) or 1.0)) + self.controlButtonW + 32
    local listWidth = math.max(self.summaryWidth + 36, 440)

    return math.max(controlMin, rowWidth, fullRowWidth, labelWidth + (self.pad * 2), listWidth + (self.pad * 2))
end

function DO_DebugWindow:syncWindowSize()
    local core = getCore and getCore() or nil
    if not core then
        self:layoutChildren()
        return
    end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local contentWidth = clamp(self:getContentWidth(), 460, math.max(520, screenW - 80))
    local listItems = self.activeList and #(self.activeList.items or {}) or 0
    local listHeight = clamp(math.max(104, listItems * 28), 120, math.floor(screenH * 0.42))
    local contentHeight = 404 + listHeight
    local windowHeight = clamp(contentHeight + self:titleBarHeight() + 20, 420, screenH - 100)

    self:setWidth(contentWidth)
    self:setHeight(windowHeight)
    self:setX(clamp(self:getX(), 20, math.max(20, screenW - contentWidth - 20)))
    self:setY(clamp(self:getY(), 40, math.max(40, screenH - windowHeight - 40)))
    self:layoutChildren()
end

function DO_DebugWindow:layoutChildren()
    if not self.lblDifficultyTitle then
        return
    end

    local x = self.pad
    local y = self:titleBarHeight() + self.pad
    local buttonH = self.buttonH
    local gap = self.gap
    local fullW = self.width - (self.pad * 2)
    local halfW = math.floor((fullW - gap) / 2)

    self.lblDifficultyTitle:setX(x)
    self.lblDifficultyTitle:setY(y + 4)
    self.btnDifficultyDown:setX(x + self.labelW)
    self.btnDifficultyDown:setY(y)
    self.lblDifficultyValue:setX(x + self.labelW + self.controlButtonW + 8)
    self.lblDifficultyValue:setY(y + 4)
    self.btnDifficultyUp:setX(x + fullW - self.controlButtonW)
    self.btnDifficultyUp:setY(y)
    y = y + buttonH + gap

    self.lblTimerTitle:setX(x)
    self.lblTimerTitle:setY(y + 4)
    self.btnTimerDown:setX(x + self.labelW)
    self.btnTimerDown:setY(y)
    self.lblTimerValue:setX(x + self.labelW + self.controlButtonW + 8)
    self.lblTimerValue:setY(y + 4)
    self.btnTimerUp:setX(x + fullW - self.controlButtonW)
    self.btnTimerUp:setY(y)
    y = y + buttonH + 10

    self.btnKill:setX(x)
    self.btnKill:setY(y)
    self.btnKill:setWidth(halfW)
    self.btnHunt:setX(x + halfW + gap)
    self.btnHunt:setY(y)
    self.btnHunt:setWidth(halfW)
    y = y + buttonH + gap

    self.btnCourier:setX(x)
    self.btnCourier:setY(y)
    self.btnCourier:setWidth(fullW)
    y = y + buttonH + gap

    self.btnRestingChain:setX(x)
    self.btnRestingChain:setY(y)
    self.btnRestingChain:setWidth(fullW)
    y = y + buttonH + gap

    self.btnForceTraderHelp:setX(x)
    self.btnForceTraderHelp:setY(y)
    self.btnForceTraderHelp:setWidth(fullW)
    y = y + buttonH + gap

    self.btnMissionViewer:setX(x)
    self.btnMissionViewer:setY(y)
    self.btnMissionViewer:setWidth(halfW)
    self.btnQuestManager:setX(x + halfW + gap)
    self.btnQuestManager:setY(y)
    self.btnQuestManager:setWidth(halfW)
    y = y + buttonH + gap

    self.btnQuestConversation:setX(x)
    self.btnQuestConversation:setY(y)
    self.btnQuestConversation:setWidth(fullW)
    y = y + buttonH + gap

    self.btnMissionCompleteModal:setX(x)
    self.btnMissionCompleteModal:setY(y)
    self.btnMissionCompleteModal:setWidth(fullW)
    y = y + buttonH + gap

    self.btnMissionProgressModal:setX(x)
    self.btnMissionProgressModal:setY(y)
    self.btnMissionProgressModal:setWidth(fullW)
    y = y + buttonH + 10

    self.btnMissionFailModal:setX(x)
    self.btnMissionFailModal:setY(y)
    self.btnMissionFailModal:setWidth(fullW)
    y = y + buttonH + 10

    self.lblTracked:setX(x)
    self.lblTracked:setY(y)
    y = y + 18
    self.lblLocated:setX(x)
    self.lblLocated:setY(y)
    y = y + 18 + gap

    local footerRows = (buttonH * 2) + gap + 12
    local listHeight = math.max(120, self.height - y - footerRows - 18)
    self.activeList:setX(x)
    self.activeList:setY(y)
    self.activeList:setWidth(fullW)
    self.activeList:setHeight(listHeight)
    y = y + listHeight + gap

    self.btnTrack:setX(x)
    self.btnTrack:setY(y)
    self.btnTrack:setWidth(halfW)
    self.btnLocate:setX(x + halfW + gap)
    self.btnLocate:setY(y)
    self.btnLocate:setWidth(halfW)
    y = y + buttonH + gap

    local thirdW = math.floor((fullW - (gap * 2)) / 3)
    self.btnAbandon:setX(x)
    self.btnAbandon:setY(y)
    self.btnAbandon:setWidth(thirdW)
    self.btnDump:setX(x + thirdW + gap)
    self.btnDump:setY(y)
    self.btnDump:setWidth(thirdW)
    self.btnRefresh:setX(x + (thirdW * 2) + (gap * 2))
    self.btnRefresh:setY(y)
    self.btnRefresh:setWidth(fullW - (thirdW * 2) - (gap * 2))
end

function DO_DebugWindow:refreshQuestList()
    if not self.activeList or not DynamicObjectives or not DynamicObjectives.Quests then
        return
    end

    local player = getLocalPlayer()
    local selectedQuestID = self:getSelectedQuestID()
    local summaries = DynamicObjectives.Quests.GetActiveQuestSummary and DynamicObjectives.Quests.GetActiveQuestSummary(player) or {}
    local tracked = DynamicObjectives.Quests.GetTrackedQuest and DynamicObjectives.Quests.GetTrackedQuest(player) or nil
    local located = DynamicObjectives.Quests.GetLocatedQuest and DynamicObjectives.Quests.GetLocatedQuest(player) or nil

    self.summaryWidth = 0
    self.activeList:clear()

    for _, summary in ipairs(summaries) do
        self.activeList:addItem(summary.display, summary.questID)
        self.summaryWidth = math.max(self.summaryWidth, measureText(UIFont.Small, summary.display))
    end

    if selectedQuestID then
        for index, item in ipairs(self.activeList.items or {}) do
            if tostring(item.item) == tostring(selectedQuestID) then
                self.activeList.selected = index
                break
            end
        end
    end

    if self.lblTracked then
        self.lblTracked:setName("Tracked: " .. tostring(tracked and tracked.name or "None"))
    end
    if self.lblLocated then
        self.lblLocated:setName("Located: " .. tostring(located and located.name or "None"))
    end

    self:syncWindowSize()
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

function DO_DebugWindow:onStartRestingChainQuest()
    local player = getLocalPlayer()
    if player and DynamicObjectives.Quests and DynamicObjectives.Quests.DebugStartRestingChainQuest then
        DynamicObjectives.Quests.DebugStartRestingChainQuest(player, self.debugDifficulty, self.debugTimeLimitHours)
        self:refreshQuestList()
    end
end

function DO_DebugWindow:onForceTraderHelpEscort()
    local player = getLocalPlayer()
    if not player then
        return
    end

    if isClient() and not isServer() then
        if sendClientCommand then
            sendClientCommand(player, "DynamicObjectives", "ForceObjectiveHookIncident", {
                hookId = TRADER_HELP_HOOK_ID,
            })
        end
        if player.Say then
            player:Say("Forcing trader help escort incident...")
        end
    else
        local hook = DynamicObjectives.GetObjectiveHook and DynamicObjectives.GetObjectiveHook(TRADER_HELP_HOOK_ID) or nil
        local result = hook and hook.forceIncidentForPlayer and hook.forceIncidentForPlayer(player, {
            hookId = TRADER_HELP_HOOK_ID,
        }) or nil

        if DynamicObjectives.UI and DynamicObjectives.UI.RequestScannerQuestRefresh then
            DynamicObjectives.UI.RequestScannerQuestRefresh(player)
        end

        if player.Say then
            if result and result.ok == true then
                player:Say("Trader help escort forced.")
            else
                player:Say("No eligible trader help escort found.")
            end
        end
    end
    self:refreshQuestList()
end

function DO_DebugWindow:onOpenMissionViewer()
    if DO_MissionViewerWindow and DO_MissionViewerWindow.OnOpen then
        DO_MissionViewerWindow.OnOpen()
    end
end

function DO_DebugWindow:onOpenQuestManager()
    if DO_QuestManagerWindow and DO_QuestManagerWindow.OnOpen then
        DO_QuestManagerWindow.OnOpen()
    end
end

function DO_DebugWindow:onOpenQuestConversationPreview()
    local player = getLocalPlayer()
    if not player then
        return
    end

    if DT_ConversationQuestOffer and DT_ConversationQuestOffer.OpenDebugConversation then
        DT_ConversationQuestOffer.OpenDebugConversation(player, {
            onQuestAccepted = function()
                self:refreshQuestList()
            end,
            onCloseCallback = function()
                self:refreshQuestList()
            end,
        })
        return
    end

    if player.Say then
        player:Say("Quest conversation preview unavailable.")
    end
end

function DO_DebugWindow:onTestCompletionModal()
    local player = getLocalPlayer()
    if not player then
        return
    end

    local quest = DynamicObjectives.Quests
        and DynamicObjectives.Quests.DebugSimulateQuestCompletion
        and DynamicObjectives.Quests.DebugSimulateQuestCompletion(player, self.debugDifficulty, self.debugTimeLimitHours)
        or nil

    if quest and DO_MissionModalShared and DO_MissionModalShared.ProcessMissionEvents then
        DO_MissionModalShared.ProcessMissionEvents(player)
        self:refreshQuestList()
        return
    end

    if quest and DO_CompletionModal and DO_CompletionModal.Open then
        DO_CompletionModal.Open(quest)
        self:refreshQuestList()
        return
    end

    if player.Say then
        player:Say("Completion modal simulation unavailable.")
    end
end

function DO_DebugWindow:onTestProgressModal()
    local player = getLocalPlayer()
    if not player then
        return
    end

    local quest = DynamicObjectives.Quests
        and DynamicObjectives.Quests.DebugSimulateQuestProgress
        and DynamicObjectives.Quests.DebugSimulateQuestProgress(player, self.debugDifficulty, self.debugTimeLimitHours)
        or nil

    if quest and DO_MissionModalShared and DO_MissionModalShared.ProcessMissionEvents then
        DO_MissionModalShared.ProcessMissionEvents(player)
        self:refreshQuestList()
        return
    end

    if quest and DO_ProgressModal and DO_ProgressModal.OpenFromEvent then
        DO_ProgressModal.OpenFromEvent({
            kind = "progress",
            quest = quest,
            objective = quest.objectives and quest.objectives[1] or nil,
            objectiveID = quest.objectives and quest.objectives[1] and quest.objectives[1].id or nil,
        })
        self:refreshQuestList()
        return
    end

    if player.Say then
        player:Say("Progress modal simulation unavailable.")
    end
end

function DO_DebugWindow:onTestFailureModal()
    local player = getLocalPlayer()
    if not player then
        return
    end

    local quest = DynamicObjectives.Quests
        and DynamicObjectives.Quests.DebugSimulateQuestFailure
        and DynamicObjectives.Quests.DebugSimulateQuestFailure(player, self.debugDifficulty, self.debugTimeLimitHours)
        or nil

    if quest and DO_MissionModalShared and DO_MissionModalShared.ProcessMissionEvents then
        DO_MissionModalShared.ProcessMissionEvents(player)
        self:refreshQuestList()
        return
    end

    if quest and DO_FailureModal and DO_FailureModal.Open then
        DO_FailureModal.Open(quest)
        self:refreshQuestList()
        return
    end

    if player.Say then
        player:Say("Failure modal simulation unavailable.")
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

    self:syncWindowSize()
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

function DO_DebugWindow:onLocateSelected()
    local player = getLocalPlayer()
    local questID = self:getSelectedQuestID()
    if player and questID and DynamicObjectives.Quests and DynamicObjectives.Quests.ToggleLocatedQuest then
        DynamicObjectives.Quests.ToggleLocatedQuest(player, questID)
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

    local window = DO_DebugWindow:new(120, 80, 540, 480)
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
    o.summaryWidth = 0
    o:setResizable(false)
    return o
end
