DynamicObjectives = DynamicObjectives or {}

require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "DO/UI/MissionViewer/DO_MissionViewerShared"
require "DO/UI/MissionViewer/DO_MissionViewerListPanel"
require "DO/UI/MissionViewer/DO_MissionViewerDetailPanel"

DO_MissionViewerWindow = ISCollapsableWindow:derive("DO_MissionViewerWindow")
DO_MissionViewerWindow.instance = nil

local DO = DynamicObjectives

local function T(key, fallback, params)
    if DO and DO.Text and DO.Text.Get then
        return DO.Text.Get(key, params, fallback)
    end
    return fallback or key
end

function DO_MissionViewerWindow:initialise()
    ISCollapsableWindow.initialise(self)
    self:setResizable(true)
    self.minimumWidth = 860
    self.minimumHeight = 520
end

function DO_MissionViewerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local pad = 10
    local th = self:titleBarHeight()
    local contentY = th + pad
    local contentH = self.height - th - (pad * 2)
    local listW = math.max(320, math.floor(self.width * 0.38))
    local detailX = pad + listW + 10
    local detailW = self.width - detailX - pad

    self.tabPanel = ISTabPanel:new(pad, contentY, listW, contentH)
    self.tabPanel:initialise()
    self.tabPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.tabPanel:setAnchorLeft(true)
    self.tabPanel:setAnchorTop(true)
    self.tabPanel:setAnchorBottom(true)
    self:addChild(self.tabPanel)

    self.currentPanel = DO_MissionViewerListPanel:new(0, 0, listW, contentH - self.tabPanel.tabHeight, "active", self)
    self.currentPanel:initialise()
    self.currentPanel:setAnchorRight(true)
    self.currentPanel:setAnchorBottom(true)
    self.tabPanel:addView(T("DOCommon_UI_MissionViewer_TabCurrent", "Current"), self.currentPanel)

    self.donePanel = DO_MissionViewerListPanel:new(0, 0, listW, contentH - self.tabPanel.tabHeight, "done", self)
    self.donePanel:initialise()
    self.donePanel:setAnchorRight(true)
    self.donePanel:setAnchorBottom(true)
    self.tabPanel:addView(T("DOCommon_UI_MissionViewer_TabDone", "Done"), self.donePanel)
    self.tabPanel:activateView(T("DOCommon_UI_MissionViewer_TabCurrent", "Current"))

    self.detailPanel = DO_MissionViewerDetailPanel:new(detailX, contentY, detailW, contentH, self)
    self.detailPanel:initialise()
    self.detailPanel:setAnchorLeft(true)
    self.detailPanel:setAnchorRight(true)
    self.detailPanel:setAnchorTop(true)
    self.detailPanel:setAnchorBottom(true)
    self:addChild(self.detailPanel)

    self.tabPanel.onActivateView = function(view)
        self.activeMode = view == self.donePanel and "done" or "active"
        local summary = view and view.getSelectedSummary and view:getSelectedSummary() or nil
        self:onMissionSelected(summary, self.activeMode)
    end

    self:refreshData()
end

function DO_MissionViewerWindow:onMissionSelected(summary, mode)
    if self.isRefreshingData then return end
    self.selectedQuestID = summary and summary.questID or self.selectedQuestID
    self.selectedMode = mode or self.selectedMode or "active"

    local player = DO_MissionViewerShared.getLocalPlayer()
    local detail = summary and summary.detail or nil
    if summary and summary.questID and DO.Quests and DO.Quests.GetQuestDetailData then
        detail = DO.Quests.GetQuestDetailData(player, summary.questID) or detail
    end

    if not detail and self.selectedQuestID and DO.Quests and DO.Quests.GetQuestDetailData then
        detail = DO.Quests.GetQuestDetailData(player, self.selectedQuestID)
    end

    self.detailPanel:applyDetail(detail)
end

function DO_MissionViewerWindow:refreshSelectedDetail()
    if not self.selectedQuestID then
        return
    end
    self:refreshData(self.selectedQuestID, true)
end

function DO_MissionViewerWindow:refreshData(preferredQuestID, preserveTab)
    if not self.currentPanel or not self.donePanel then
        return
    end

    self.isRefreshingData = true
    self.currentPanel:refreshMissions(preferredQuestID or self.selectedQuestID)
    self.donePanel:refreshMissions(preferredQuestID or self.selectedQuestID)
    self.isRefreshingData = false

    local selectedMode = self.selectedMode or "active"
    if not preserveTab then
        if preferredQuestID and self.donePanel:selectQuest(preferredQuestID) and not self.currentPanel:selectQuest(preferredQuestID) then
            selectedMode = "done"
        elseif self.currentPanel:getSelectedSummary() then
            selectedMode = "active"
        elseif self.donePanel:getSelectedSummary() then
            selectedMode = "done"
        end
    end

    self.selectedMode = selectedMode
    if selectedMode == "done" then
        self.tabPanel:activateView(T("DOCommon_UI_MissionViewer_TabDone", "Done"))
        self:onMissionSelected(self.donePanel:getSelectedSummary(), "done")
    else
        self.tabPanel:activateView(T("DOCommon_UI_MissionViewer_TabCurrent", "Current"))
        self:onMissionSelected(self.currentPanel:getSelectedSummary(), "active")
    end
end

function DO_MissionViewerWindow:onResize()
    ISCollapsableWindow.onResize(self)

    if not self.tabPanel or not self.detailPanel then
        return
    end

    local pad = 10
    local th = self:titleBarHeight()
    local contentY = th + pad
    local contentH = self.height - th - (pad * 2)
    local listW = math.max(320, math.floor(self.width * 0.38))
    local detailX = pad + listW + 10
    local detailW = self.width - detailX - pad

    self.tabPanel:setX(pad)
    self.tabPanel:setY(contentY)
    self.tabPanel:setWidth(listW)
    self.tabPanel:setHeight(contentH)

    self.detailPanel:setX(detailX)
    self.detailPanel:setY(contentY)
    self.detailPanel:setWidth(detailW)
    self.detailPanel:setHeight(contentH)
    if self.detailPanel.body then
        self.detailPanel.body:setWidth(detailW - 24)
        self.detailPanel.body:setHeight(contentH - 96)
        self.detailPanel.body:paginate()
    end
end

function DO_MissionViewerWindow:update()
    ISCollapsableWindow.update(self)
    self.refreshTick = (tonumber(self.refreshTick) or 0) + 1
    if self.refreshTick >= 90 then
        self.refreshTick = 0
        self:refreshData(self.selectedQuestID, true)
    end
end

function DO_MissionViewerWindow.OnOpen()
    if DO_MissionViewerWindow.instance then
        DO_MissionViewerWindow.instance:setVisible(true)
        DO_MissionViewerWindow.instance:bringToTop()
        DO_MissionViewerWindow.instance:refreshData()
        return DO_MissionViewerWindow.instance
    end

    local core = getCore and getCore() or nil
    local screenW = core and core:getScreenWidth() or 1280
    local screenH = core and core:getScreenHeight() or 720
    local width = math.min(1040, screenW - 80)
    local height = math.min(680, screenH - 120)
    local window = DO_MissionViewerWindow:new((screenW - width) / 2, (screenH - height) / 2, width, height)
    window:initialise()
    window:addToUIManager()
    DO_MissionViewerWindow.instance = window
    return window
end

function DO_MissionViewerWindow:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = T("DOCommon_UI_MissionViewer_Title", "Mission Viewer")
    o.pin = true
    o.resizable = true
    o.refreshTick = 0
    o.selectedQuestID = nil
    o.selectedMode = "active"
    return o
end

return DO_MissionViewerWindow
