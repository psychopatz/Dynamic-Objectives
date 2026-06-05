require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISRichTextPanel"
require "DO/UI/MissionViewer/DO_MissionViewerShared"

DO_MissionViewerDetailPanel = ISPanel:derive("DO_MissionViewerDetailPanel")

local DO = DynamicObjectives

local function T(key, fallback, params)
    if DO and DO.Text and DO.Text.Get then
        return DO.Text.Get(key, params, fallback)
    end
    return fallback or key
end

function DO_MissionViewerDetailPanel:initialise()
    ISPanel.initialise(self)
end

function DO_MissionViewerDetailPanel:createChildren()
    ISPanel.createChildren(self)

    local pad = 12
    self.nameLabel = ISLabel:new(pad, pad, 18, T("DOCommon_UI_MissionViewer_Details", "Mission Details"), 1, 1, 1, 1, UIFont.Medium, true)
    self.nameLabel:initialise()
    self:addChild(self.nameLabel)

    self.metaLabel = ISLabel:new(pad, pad + 26, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.metaLabel:initialise()
    self:addChild(self.metaLabel)

    local buttonY = pad + 52
    local buttonW = 110
    local gap = 6

    self.trackButton = ISButton:new(pad, buttonY, buttonW, 24, T("DOCommon_UI_MissionViewer_Track", "Track"), self, self.onTrackMission)
    self.trackButton:initialise()
    self:addChild(self.trackButton)

    self.locateButton = ISButton:new(pad + buttonW + gap, buttonY, buttonW, 24, T("DOCommon_UI_MissionViewer_Locate", "Locate"), self, self.onLocateMission)
    self.locateButton:initialise()
    self:addChild(self.locateButton)

    self.abandonButton = ISButton:new(pad + (buttonW * 2) + (gap * 2), buttonY, buttonW, 24, T("DOCommon_UI_MissionViewer_Abandon", "Abandon"), self, self.onAbandonMission)
    self.abandonButton:initialise()
    self.abandonButton.backgroundColor = { r = 0.42, g = 0.1, b = 0.1, a = 1.0 }
    self:addChild(self.abandonButton)

    self.body = ISRichTextPanel:new(pad, buttonY + 32, self.width - (pad * 2), self.height - buttonY - 44)
    self.body:initialise()
    self.body:instantiate()
    self.body:setAnchorLeft(true)
    self.body:setAnchorRight(true)
    self.body:setAnchorTop(true)
    self.body:setAnchorBottom(true)
    self:addChild(self.body)

    self:applyDetail(nil)
end

function DO_MissionViewerDetailPanel:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.4, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, self.width, self.height, 0.35, 0.9, 0.9, 0.9)
end

function DO_MissionViewerDetailPanel:applyDetail(detail)
    self.detail = detail

    if not self.nameLabel or not self.body then
        return
    end

    if not detail then
        self.nameLabel:setName(T("DOCommon_UI_MissionViewer_Details", "Mission Details"))
        self.metaLabel:setName(T("DOCommon_UI_MissionViewer_NoMissionSelected", "No mission selected"))
        self.body.text = DO_MissionViewerShared.buildDetailText(nil)
        self.body:paginate()
        self.trackButton:setEnable(false)
        self.locateButton:setEnable(false)
        self.abandonButton:setEnable(false)
        return
    end

    self.nameLabel:setName(tostring(detail.title or detail.name or detail.questID or T("DOCommon_UI_MissionViewer_Mission", "Mission")))
    local metaParts = {
        tostring(detail.statusLabel or T("DOCommon_UI_MissionViewer_Active", "Active")),
        T("DOCommon_UI_ObjectiveHUD_Step", "STEP {current} / {total}", {
            current = tonumber(detail.currentStep) or 1,
            total = tonumber(detail.totalSteps) or 1,
        }),
    }
    if detail.giverName and detail.giverName ~= "" then
        metaParts[#metaParts + 1] = tostring(detail.giverName)
    end
    self.metaLabel:setName(table.concat(metaParts, "  |  "))
    self.body.text = DO_MissionViewerShared.buildDetailText(detail)
    self.body:paginate()

    local isActive = detail.status == "active"
    self.trackButton:setEnable(isActive and detail.tracked ~= true)
    self.locateButton:setEnable(isActive == true)
    self.abandonButton:setEnable(isActive == true)
    self.trackButton:setTitle(detail.tracked == true
        and T("DOCommon_UI_MissionViewer_Tracked", "Tracked")
        or T("DOCommon_UI_MissionViewer_Track", "Track"))
    self.locateButton:setTitle(detail.located == true
        and T("DOCommon_UI_MissionViewer_Unlocate", "Unlocate")
        or T("DOCommon_UI_MissionViewer_Locate", "Locate"))
end

function DO_MissionViewerDetailPanel:onTrackMission()
    local player = DO_MissionViewerShared.getLocalPlayer()
    if player and self.detail and self.detail.questID and DO.Quests and DO.Quests.SetTrackedQuest then
        DO.Quests.SetTrackedQuest(player, self.detail.questID)
        if self.ownerWindow and self.ownerWindow.refreshData then
            self.ownerWindow:refreshData(self.detail.questID)
        end
    end
end

function DO_MissionViewerDetailPanel:onLocateMission()
    local player = DO_MissionViewerShared.getLocalPlayer()
    if player and self.detail and self.detail.questID and DO.Quests and DO.Quests.ToggleLocatedQuest then
        DO.Quests.ToggleLocatedQuest(player, self.detail.questID)
        if self.ownerWindow and self.ownerWindow.refreshData then
            self.ownerWindow:refreshData(self.detail.questID)
        end
    end
end

function DO_MissionViewerDetailPanel:onAbandonMission()
    local player = DO_MissionViewerShared.getLocalPlayer()
    if player and self.detail and self.detail.questID and DO.Quests and DO.Quests.AbandonQuest then
        DO.Quests.AbandonQuest(player, self.detail.questID)
        if self.ownerWindow and self.ownerWindow.refreshData then
            self.ownerWindow:refreshData(self.detail.questID)
        end
    end
end

function DO_MissionViewerDetailPanel:update()
    ISPanel.update(self)
    self.refreshTick = (tonumber(self.refreshTick) or 0) + 1
    if self.refreshTick >= 60 then
        self.refreshTick = 0
        if self.ownerWindow and self.ownerWindow.refreshSelectedDetail then
            self.ownerWindow:refreshSelectedDetail()
        end
    end
end

function DO_MissionViewerDetailPanel:new(x, y, width, height, ownerWindow)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.noBackground = true
    o.ownerWindow = ownerWindow
    o.refreshTick = 0
    o.detail = nil
    return o
end
