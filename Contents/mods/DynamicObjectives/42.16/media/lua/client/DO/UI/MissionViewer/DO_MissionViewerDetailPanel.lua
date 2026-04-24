require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISRichTextPanel"
require "DO/UI/MissionViewer/DO_MissionViewerShared"

DO_MissionViewerDetailPanel = ISPanel:derive("DO_MissionViewerDetailPanel")

local DO = DynamicObjectives

function DO_MissionViewerDetailPanel:initialise()
    ISPanel.initialise(self)
end

function DO_MissionViewerDetailPanel:createChildren()
    ISPanel.createChildren(self)

    local pad = 12
    self.nameLabel = ISLabel:new(pad, pad, 18, "Mission Details", 1, 1, 1, 1, UIFont.Medium, true)
    self.nameLabel:initialise()
    self:addChild(self.nameLabel)

    self.metaLabel = ISLabel:new(pad, pad + 26, 18, "", 1, 1, 1, 1, UIFont.Small, true)
    self.metaLabel:initialise()
    self:addChild(self.metaLabel)

    local buttonY = pad + 52
    local buttonW = 110
    local gap = 6

    self.trackButton = ISButton:new(pad, buttonY, buttonW, 24, "Track", self, self.onTrackMission)
    self.trackButton:initialise()
    self:addChild(self.trackButton)

    self.locateButton = ISButton:new(pad + buttonW + gap, buttonY, buttonW, 24, "Locate", self, self.onLocateMission)
    self.locateButton:initialise()
    self:addChild(self.locateButton)

    self.abandonButton = ISButton:new(pad + (buttonW * 2) + (gap * 2), buttonY, buttonW, 24, "Abandon", self, self.onAbandonMission)
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
        self.nameLabel:setName("Mission Details")
        self.metaLabel:setName("No mission selected")
        self.body.text = DO_MissionViewerShared.buildDetailText(nil)
        self.body:paginate()
        self.trackButton:setEnable(false)
        self.locateButton:setEnable(false)
        self.abandonButton:setEnable(false)
        return
    end

    self.nameLabel:setName(tostring(detail.name or detail.questID or "Mission"))
    self.metaLabel:setName(string.format("%s  |  Step %d / %d", tostring(detail.statusLabel or "Active"), tonumber(detail.currentStep) or 1, tonumber(detail.totalSteps) or 1))
    self.body.text = DO_MissionViewerShared.buildDetailText(detail)
    self.body:paginate()

    local isActive = detail.status == "active"
    self.trackButton:setEnable(isActive and detail.tracked ~= true)
    self.locateButton:setEnable(isActive == true)
    self.abandonButton:setEnable(isActive == true)
    self.trackButton:setTitle(detail.tracked == true and "Tracked" or "Track")
    self.locateButton:setTitle(detail.located == true and "Unlocate" or "Locate")
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
